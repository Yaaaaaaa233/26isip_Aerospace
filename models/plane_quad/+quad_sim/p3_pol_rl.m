function pol = p3_pol_rl(o)
%QUAD_SIM.P3_POL_RL 多臂适配 rl 臂(sim-to-real REINFORCE 三段式, 1-D 单桶版)。
% pol = p3_pol_rl(o); v = pol(info)。info=白名单面。w36.rl_run v3 的直线链移植:
%   Stage A 首飞括号扫标定(p3_phase_a, 全速域平扫的谷邻域早停版——1-D 谷辨识
%           只需谷邻域覆盖, 平扫在本链能耗惩罚过大, 见 p3_multiarm_opt 裁决 a)
%   Stage B 学到的模型里离线预训练(纯 REINFORCE, 零飞行成本; 1-D 单桶下收敛到
%           模型谷=曲线 argmin, 保留机制与环航 24 桶版同构; u 钳位 v̂*±preTrust
%           ——截断拟合只在谷邻域可信, w36 同款保险)
%   Stage C 部署+在线微调(对偶交替 ±σ 逐样本, bBase/Pb EMA 基线, REINFORCE
%           ÷σ² 正确缩放, dB 限幅, σ 退火)——吸收模型误差与风漂移
% 因果口径: 只读 info.Phat/info.t(白名单), 曲线知识来自自己标定拟合。
o = local_def(o);
A = quad_sim.p3_phase_a(o.sweep);
mu = NaN; sigma = o.rlSigma; bBase = NaN; Pb = NaN;
nSim = o.nSim; kStep = 0;
tD0 = NaN; sumP = 0; nP = 0; bStageC = false; vHold = o.sweep.vInit_mps;
pol = @step;
    function v = step(info)
        if ~bStageC
            v = A.step(info); vHold = v;
            if A.done()
                S = A.samples();
                F = quad_sim.p3_fit_valley(S.v,S.P,o.sweep);
                % ---- Stage B: 模型内离线 REINFORCE(瞬间完成, 不占飞行) ----
                mu = local_clip(F.vStar,o);
                for j = 1:nSim
                    sgn = (-1)^j;
                    vb = local_pre_clip(mu+sgn*sigma,F,o);
                    Pm = local_poly(F.coefs,vb);
                    if isnan(bBase), bBase = Pm; r0 = Pm; else, r0 = bBase; end
                    r = -(Pm-r0)/max(abs(r0),0.1);
                    if ~isnan(bBase) && j > 1, bBase = 0.9*bBase+0.1*Pm; end
                    aDev = vb-mu;
                    lrT = o.rlLr*max(0.03,1-j/nSim);
                    dB = lrT*r*aDev/(sigma^2);
                    dB = min(max(dB,-o.dBMax),o.dBMax);
                    mu = local_clip(mu+dB,o);
                end
                bBase = NaN; Pb = NaN;        % 基线不带出预训练(在线重建)
                sigma = max(o.rlSigmaMin,0.5*o.rlSigma);
                bStageC = true; tD0 = NaN; sumP = 0; nP = 0;
            end
            return;
        end
        % ---- Stage C: 在线对偶探索微调(w36 Stage C 同构) ----
        if isnan(tD0)
            kStep = kStep+1;
            vHold = local_clip(mu+(-1)^kStep*sigma,o);
            tD0 = info.t; sumP = 0; nP = 0;
        end
        v = vHold;
        if info.t >= tD0 + 0.5                   % 驻留整段均值(测量语义 v2)
            sumP = sumP + info.Phat; nP = nP + 1;
        end
        if info.t >= tD0 + o.dwell_s
            Pm = sumP/max(nP,1);
            if isnan(Pb), Pb = Pm; else, Pb = 0.98*Pb+0.02*Pm; end
            if isnan(bBase), bBase = Pm; else, bBase = 0.9*bBase+0.1*Pm; end
            r = -(Pm-bBase)/max(Pb,0.1);
            aDev = vHold-mu;
            dB = o.rlLr*r*aDev/(sigma^2);
            dB = min(max(dB,-o.dBMax),o.dBMax);
            mu = local_clip(mu+dB,o);
            sigma = max(o.rlSigmaMin,sigma*0.995);
            tD0 = NaN;
        end
    end
end
function o = local_def(o)
d = struct('dwell_s',3,'tail_s',2,'rlSigma',0.50,'rlSigmaMin',0.20, ...
    'rlLr',0.20,'dBMax',0.10,'nSim',2000,'preTrust_mps',2.5,'sweep',[]);
if ~isempty(o)
    fn = fieldnames(o);
    for k = 1:numel(fn), d.(fn{k}) = o.(fn{k}); end
end
if isempty(d.sweep)
    d.sweep = struct('step_mps',1,'dwell_s',d.dwell_s,'tail_s',d.tail_s, ...
        'maxPts',11,'curvMin_pp1',0.5,'vMin_mps',4,'vMax_mps',14,'vInit_mps',8);
end
o = d;
end
function v = local_clip(v,o)
v = min(max(v,o.sweep.vMin_mps),o.sweep.vMax_mps);
end
function v = local_pre_clip(v,F,o)
v = min(max(v,F.vStar-o.preTrust_mps),F.vStar+o.preTrust_mps);
v = local_clip(v,o);
end
function y = local_poly(c,v)
x = (v-9)/5;
y = c(1)+c(2)*x+c(3)*x.^2+c(4)*x.^3+c(5)*x.^4;
end
