function [pol,dump] = p3_pol_purerl(o)
%QUAD_SIM.P3_POL_PURERL 多臂适配 purerl 臂(纯奖励 REINFORCE, 1-D 单桶版)。
% [pol,dump] = p3_pol_purerl(o); v = pol(info); S = dump() 取学习器状态。
% w36.pure_rl_run / pure_rl_pre_run 的直线链移植: 无扫频、无模型、无 u*/风知识,
% 只靠"调速度->仪表盘功率->奖励"学最优速度。环航 24/12 航向桶 -> 本链单桶
% (无航向维, 邻域共享核随之删除); 对偶交替 ±σ(plHold 样本换号)+bBase EMA
% 基线+REINFORCE ÷σ²+dB 限幅+σ 退火, 全部照 w36 数值口径。
% o.mode:
%   'scratch' 纯在线从头学(p3_arm('purerl'), w36 pure_rl_run 对应)
%   'on'      试飞预训练后在线部署: lr=onLr, σ=onSigma 继续修正(w36 'on')
%   'off'     试飞预训练后冻结贪心执行, 零探索零学习(w36 'off'; 单桶反应式
%             策略无状态可依, 即恒速——如实报的诚实退化)
% o.warm = p3_warmup 导出的预训练结构(mu/bBase/sigma); mode~=scratch 必带。
% 因果口径: 只读 info.Phat/info.t; 驻留尾窗=w36 settled_q 的 p3 等价
% (尾窗天然滤执行暂态, sUsed>1 暂态门不需要)。
o = local_def(o);
if ~strcmp(o.mode,'scratch')
    assert(isstruct(o.warm) && isfield(o.warm,'mu'), ...
        'quad_sim:P3PolPurerl','mode %s needs o.warm (p3_warmup output).',o.mode);
    mu = o.warm.mu; bBase = o.warm.bBase;
    if strcmp(o.mode,'on'), sigma = o.onSigma; else, sigma = o.warm.sigma; end
else
    mu = o.vInit_mps; bBase = NaN; sigma = o.plSigma0;
end
kStep = 0; lastSgn = 1; stepsSinceFlip = 99;
tD0 = NaN; sumP = 0; nP = 0; vHold = mu;
pol = @step;
dump = @getDump;
    function v = step(info)
        if strcmp(o.mode,'off')
            v = local_clip(mu,o); vHold = v; return;    % 冻结贪心, 零探索
        end
        if isnan(tD0)
            kStep = kStep+1;
            if stepsSinceFlip >= o.plHold, lastSgn = -lastSgn; stepsSinceFlip = 0; end
            stepsSinceFlip = stepsSinceFlip+1;
            vHold = local_clip(mu+lastSgn*sigma,o);
            tD0 = info.t; sumP = 0; nP = 0;
        end
        v = vHold;
        if info.t >= tD0 + 0.5                   % 驻留整段均值(测量语义 v2)
            sumP = sumP + info.Phat; nP = nP + 1;
        end
        if info.t >= tD0 + o.dwell_s
            Pm = sumP/max(nP,1);
            if isnan(bBase), bBase = Pm; else, bBase = 0.9*bBase+0.1*Pm; end
            r = -(Pm-bBase)/max(abs(bBase),0.1);
            aDev = vHold-mu;
            if strcmp(o.mode,'on'), lrT = o.onLr; else
                lrT = o.plLr*max(0.25,0.99^kStep); end
            dB = lrT*r*aDev/(sigma^2);
            dB = min(max(dB,-o.dBMax),o.dBMax);
            mu = local_clip(mu+dB,o);
            if strcmp(o.mode,'scratch')
                sigma = max(o.plSigmaMin,sigma*o.anneal);   % w36 'on' 部署不退火
            end
            tD0 = NaN;
        end
    end
    function S = getDump()
        S = struct('mu',mu,'bBase',bBase,'sigma',sigma,'kStep',kStep,'mode',o.mode);
    end
end
function o = local_def(o)
d = struct('mode','scratch','warm',[],'dwell_s',2,'tail_s',1, ...
    'plSigma0',1.20,'plSigmaMin',0.50,'plLr',10.0,'plHold',2,'dBMax',0.05, ...
    'anneal',0.996,'onLr',2.5,'onSigma',0.50,'vInit_mps',8,'vMin_mps',4, ...
    'vMax_mps',14);
if ~isempty(o)
    fn = fieldnames(o);
    for k = 1:numel(fn), d.(fn{k}) = o.(fn{k}); end
end
o = d;
end
function v = local_clip(v,o)
v = min(max(v,o.vMin_mps),o.vMax_mps);
end
