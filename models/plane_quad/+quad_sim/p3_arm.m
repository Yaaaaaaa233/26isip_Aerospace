function pol = p3_arm(kind, arg)
%QUAD_SIM.P3_ARM P3 臂工厂(策略句柄, 方案 §4.3 预注册)。
% pol = @(info) vRef。info 为 realism_run 的因果白名单面(只含 t/v/x/Phat/Vmeas/
% Ehat/cmd), 臂看不到真功率/真风/真状态 —— 因果边界(G-P2)。
%   pol = p3_arm('openloop', vFixed)      固定速度基线(无反馈)
%   pol = p3_arm('sweepcal', o)           在线三点扫+二次拟合定谷(G-P4 轻量版):
%       o.cycle_s 周期(默认 30) o.dwell_s 每点驻留(3) o.tail_s 驻留尾均值窗(2)
%       o.probeOff_mps 探测偏置(1.5) o.supportExt_mps 支撑域外延(0=不外推)
%       o.maxStep_mps 单周期钳位(1.5) o.curvMin_pp1 过平门槛(0.5)
%       o.vMin_mps/vMax_mps 限幅 o.vInit_mps 初值
%       —— 样本支撑选谷(锚定实测最优样本)+邻域钳位+曲率门槛+探针边界防退化
%       (方案 §4.6/§4.7), 只读 info.Phat 估计口径
%   pol = p3_arm('known', map)            oracle 上界: map.bounds_s(1xN+1) 相位边界
%       + map.vStar(1xN) 逐相位真值扫描 v*(显式 oracle, v* 来源=真值扫描, 不来自 info)
%   pol = p3_arm('const', v)              常值(真值扫描/复跑用)
% 多臂适配(2026-10-15, 预注册 p3_multiarm_opt; 参数默认值以该文件为准):
%   pol = p3_arm('rl', o)                 三段式 sim-to-real REINFORCE
%       (括号扫标定 + 模型内离线预训练 + 在线对偶微调), 见 p3_pol_rl
%   pol = p3_arm('hybrid', o)             标定后在线: 冻结形状 1-D 平移跟踪 +
%       信赖域探针对(航向风辨识已剪, 见 p3_multiarm_opt 裁决 a), 见 p3_pol_hybrid
%   pol = p3_arm('purerl', o)             纯在线 REINFORCE(无扫频无模型), 见 p3_pol_purerl
%   pol = p3_arm('purerl_on', warm)       试飞预训练在线部署(lr/4, σ=0.5)
%   pol = p3_arm('purerl_off', warm)      试飞预训练冻结贪心部署
%       warm = quad_sim.p3_warmup(c,o) 输出(预训练=额外试飞预算, 不占任务窗)
narginchk(2,2);
switch char(kind)
    case {'openloop','const'}
        vFix = arg;
        pol = @(info) vFix;
    case 'sweepcal'
        o = struct('cycle_s',30,'dwell_s',3,'tail_s',2,'probeOff_mps',1.5, ...
            'supportExt_mps',0,'maxStep_mps',1.5,'curvMin_pp1',0.5, ...
            'vMin_mps',4,'vMax_mps',14,'vInit_mps',8);
        if ~isempty(arg)
            fn = fieldnames(arg);
            for k = 1:numel(fn), o.(fn{k}) = arg.(fn{k}); end
        end
        pol = local_sweepcal(o);
    case 'known'
        map = arg;
        assert(isfield(map,'bounds_s') && isfield(map,'vStar'), ...
            'p3_arm:Known','map needs bounds_s and vStar.');
        pol = @(info) local_known(map,info);
    case 'hybrid'
        pol = quad_sim.p3_pol_hybrid(local_mergearg(struct(),arg));
    case 'rl'
        pol = quad_sim.p3_pol_rl(local_mergearg(struct(),arg));
    case 'purerl'
        o = local_mergearg(struct('mode','scratch'),arg);
        pol = quad_sim.p3_pol_purerl(o);
    case {'purerl_on','purerl_off'}
        if isstruct(arg) && isfield(arg,'warm')
            o = arg;
        else
            o = struct('warm',arg);
        end
        kstr = char(kind);
        o.mode = kstr(8:end);                        % 'purerl_on'->'on'
        pol = quad_sim.p3_pol_purerl(o);
    otherwise
        error('p3_arm:Kind','Unknown arm kind: %s',char(kind));
end
end
function pol = local_sweepcal(o)
vBest = o.vInit_mps;
tCycle = 10;            % 首个探测周期起点(s)
iProbe = 0;             % 0=跟踪段; 1..3=探测第几点
vPts = zeros(1,3); pPts = zeros(1,3);
tDwell0 = 0; sumP = 0; nP = 0;
pol = @step;
    function v = step(info)
        t = info.t;
        if iProbe > 0
            v = vPts(iProbe);
            if t >= tDwell0 + (o.dwell_s-o.tail_s)  % 驻留尾 tail_s 记 P̂ 均值
                sumP = sumP + info.Phat; nP = nP + 1;
            end
            if t >= tDwell0 + o.dwell_s
                pPts(iProbe) = sumP/max(nP,1);
                sumP = 0; nP = 0;
                iProbe = iProbe + 1;
                if iProbe > 3
                    vBest = local_argmin(vPts,pPts,o,vBest);
                    iProbe = 0;
                else
                    tDwell0 = t;
                end
            end
        else
            v = vBest;
            if t >= tCycle
                vPts = local_probe(vBest,o);
                iProbe = 1; tDwell0 = t; tCycle = tCycle + o.cycle_s;
            end
        end
    end
end
function vPts = local_probe(vBest,o)
% 探针组边界防退化(G-P4 轻量版): 裁剪在域边会退化出重复点(如 vBest=vMin 时
% [vMin vMin vMin+off] 只剩 2 个不同点), 改整体平移, 恒保 3 个不同点
vPts = vBest + o.probeOff_mps*[-1 0 1];
if min(vPts) < o.vMin_mps, vPts = vPts + (o.vMin_mps-min(vPts)); end
if max(vPts) > o.vMax_mps, vPts = vPts - (max(vPts)-o.vMax_mps); end
end
function vb = local_argmin(vPts,pPts,o,vFallback)
% 三点二次拟合取功率谷(G-P4 轻量版第 2 轮, 样本支撑选谷忠实语义 + 曲率门槛):
%   锚 = 实测最优样本点(谷从样本中选, w36 本义); 拟合顶点仅在样本张成域内接受
%   (不外推), 过平拟合弃顶点保锚; 邻域钳位限制单周期更新量。
vb = vFallback;
[pmin,im] = min(pPts);
anchor = vPts(im);
if numel(unique(vPts)) < 3, vb = anchor; return; end  % 欠定: 退实测锚点
pp = polyfit(vPts,pPts,2);
if pp(1) <= 0, vb = anchor; return; end
cand = -pp(2)/(2*pp(1));
if ~isfinite(cand), vb = anchor; return; end
if pp(1) < o.curvMin_pp1, vb = anchor; return; end     % ucThr 语义: 过平顶点病态
if cand < min(vPts)-o.supportExt_mps || cand > max(vPts)+o.supportExt_mps
    vb = anchor; return;                               % 支撑域外=边缘假谷, 退锚点
end
cand = min(o.vMax_mps,max(o.vMin_mps,cand));
vb = min(vFallback+o.maxStep_mps,max(vFallback-o.maxStep_mps,cand));  % 邻域钳位
end
function v = local_known(map,info)
p = find(info.t < map.bounds_s(2:end),1,'first');
if isempty(p), p = numel(map.vStar); end
v = map.vStar(p);
end
function o = local_mergearg(o,arg)
if isempty(arg), return; end
fn = fieldnames(arg);
for k = 1:numel(fn), o.(fn{k}) = arg.(fn{k}); end
end
