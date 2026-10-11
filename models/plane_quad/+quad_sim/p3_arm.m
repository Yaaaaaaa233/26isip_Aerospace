function pol = p3_arm(kind, arg)
%QUAD_SIM.P3_ARM P3 臂工厂(策略句柄, 方案 §4.3 预注册)。
% pol = @(info) vRef。info 为 realism_run 的因果白名单面(只含 t/v/x/Phat/Vmeas/
% Ehat/cmd), 臂看不到真功率/真风/真状态 —— 因果边界(G-P2)。
%   pol = p3_arm('openloop', vFixed)      固定速度基线(无反馈)
%   pol = p3_arm('sweepcal', o)           在线三点扫+二次拟合定谷:
%       o.cycle_s 周期(默认 30) o.dwell_s 每点驻留(3) o.probeOff_mps 探测偏置(2)
%       o.vMin_mps/vMax_mps 限幅 o.vInit_mps 初值 —— 只读 info.Phat 估计口径
%   pol = p3_arm('known', map)            oracle 上界: map.bounds_s(1xN+1) 相位边界
%       + map.vStar(1xN) 逐相位真值扫描 v*(显式 oracle, v* 来源=真值扫描, 不来自 info)
%   pol = p3_arm('const', v)              常值(真值扫描/复跑用)
narginchk(2,2);
switch char(kind)
    case {'openloop','const'}
        vFix = arg;
        pol = @(info) vFix;
    case 'sweepcal'
        o = struct('cycle_s',30,'dwell_s',3,'probeOff_mps',2, ...
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
            if t >= tDwell0 + 1                     % 驻留尾 1 s 记 P̂ 均值
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
                vPts = min(o.vMax_mps,max(o.vMin_mps, ...
                    vBest + o.probeOff_mps*[-1 0 1]));
                iProbe = 1; tDwell0 = t; tCycle = tCycle + o.cycle_s;
            end
        end
    end
end
function vb = local_argmin(vPts,pPts,o,vFallback)
% 三点二次拟合取功率谷(退化时保持原值)
vb = vFallback;
if numel(unique(vPts)) < 3, return; end   % 二次拟合需 3 个不同点, 否则欠定告警
pp = polyfit(vPts,pPts,2);
if pp(1) > 0
    cand = -pp(2)/(2*pp(1));
    if isfinite(cand), vb = min(o.vMax_mps,max(o.vMin_mps,cand)); end
end
end
function v = local_known(map,info)
p = find(info.t < map.bounds_s(2:end),1,'first');
if isempty(p), p = numel(map.vStar); end
v = map.vStar(p);
end
