function A = p3_phase_a(o)
%QUAD_SIM.P3_PHASE_A 括号扫标定状态机(rl/hybrid Phase A 共用, 多臂适配)。
% 闭包状态机, 逐拍喂 info(白名单面):
%   A.step(info) -> vRef   推进扫描(完成点后自动判停/换点)
%   A.done()     -> 标量   扫描是否结束
%   A.samples()  -> struct('v',vSub,'P',pSub) 驻留整段子样本对(实测地速配对)
%   A.tEnd()     -> 扫描结束时刻(s, 首拍 info.t 为时基)
% 扫描序(p3_multiarm_opt 预注册): vInit 起向下优先 1 m/s 双向步进
%   (vInit, vInit-1, ... vMin, vInit+1, ... vMax)。
% 测量语义 v2(勘误 2 修订, 依据见 p3_multiarm_opt): 本链速度环 τ≈2.9 s,
% 3 s 驻留永远不到位——驻留整段的 1 Hz 子均值 (v实,P̂) 对即为样本(加速偏差
% ±m·v·a/η≈±4 W 在上下行间自相消), 配对用实测地速 info.v(指令/实测稳态
% 偏移 0.16-0.38 是斜率标定的系统性偏差源)。
% 判停(预注册口径, 邻域判据无格点化):
%   (i)  域内括号: 运行最优点两侧 0.35~1.6 内各有样本, 三点抛物顶点落
%        括号内且曲率 >= curvMin_pp1 -> 停;
%   (ii) 域边谷: 最优点贴 vMin/vMax 且靠边三点单调朝外 -> 停(谷在域外);
%   (iii) maxPts 驻留数上限 -> 停。
o = local_def(o);
vSub = zeros(1,0); pSub = zeros(1,0);   % 全部子样本对(实测地速配对)
order = [o.vInit_mps, o.vInit_mps-o.step_mps:-o.step_mps:o.vMin_mps, ...
    o.vInit_mps+o.step_mps:o.step_mps:o.vMax_mps];
order = order(order >= o.vMin_mps & order <= o.vMax_mps);
order = unique(order,'stable');
iPt = 1; tD0 = NaN; doneF = false; tEnd = NaN; nPt = 0;
sumV = 0; sumP = 0; nAcc = 0; tSub0 = NaN;
A = struct('step',@step,'done',@isDone,'samples',@samples,'tEnd',@tEndf);
    function v = step(info)
        assert(~doneF,'quad_sim:P3PhaseA','phase A already done.');
        if isnan(tD0), tD0 = info.t; tSub0 = info.t; end
        v = order(iPt);
        % 驻留整段子对: 每 1 s 一格(跳过开头 0.5 s 指令/执行暂态头)
        if info.t >= tD0 + 0.5
            sumV = sumV + info.v; sumP = sumP + info.Phat; nAcc = nAcc + 1;
            if info.t >= tSub0 + 1
                vSub(end+1) = sumV/max(nAcc,1); pSub(end+1) = sumP/max(nAcc,1);
                sumV = 0; sumP = 0; nAcc = 0; tSub0 = tSub0 + 1;
            end
        end
        if info.t >= tD0 + o.dwell_s
            if nAcc >= 10    % 驻留尾部残格并入
                vSub(end+1) = sumV/nAcc; pSub(end+1) = sumP/nAcc;
            end
            sumV = 0; sumP = 0; nAcc = 0;
            nPt = nPt + 1;
            % 最少 2 个驻留才许判停(首驻留悬停起步是纯加速暂态, 单驻留
            % 子对判停无意义; 勘误 2 语义 v2 修订)
            if (nPt >= 2 && local_stop(vSub,pSub,o)) || nPt >= o.maxPts ...
                    || iPt >= numel(order)
                doneF = true; tEnd = info.t;
            else
                iPt = iPt + 1; tD0 = info.t; tSub0 = info.t;
            end
        end
    end
    function tf = isDone(), tf = doneF; end
    function S = samples(), S = struct('v',vSub,'P',pSub); end
    function t = tEndf(), t = tEnd; end
end
function o = local_def(o)
d = struct('step_mps',1,'dwell_s',3,'tail_s',2,'maxPts',11, ...
    'curvMin_pp1',0.5,'vMin_mps',4,'vMax_mps',14,'vInit_mps',8);
if ~isempty(o)
    fn = fieldnames(o);
    for k = 1:numel(fn), d.(fn{k}) = o.(fn{k}); end
end
o = d;
end
function tf = local_stop(vS,pS,o)
% 判停规则(预注册口径, 邻域判据无格点化)
if numel(vS) < 3, tf = false; return; end
[vs,ix] = sort(vS); ps = pS(ix);
[~,im] = min(ps); vm = vs(im);
% (ii) 域边谷: 贴边 + 靠边三点单调朝外
if vm <= o.vMin_mps+1e-9 || vm >= o.vMax_mps-1e-9
    if vm <= o.vMin_mps+1e-9
        tf = ps(1) < ps(2) && ps(2) < ps(3);
    else
        tf = ps(end) < ps(end-1) && ps(end-1) < ps(end-2);
    end
    if tf, return; end
end
% (i) 域内括号: 运行最优点两侧 0.35~1.6 内各有样本
lo = find(vs < vm-0.35,1,'last');
hi = find(vs > vm+0.35,1,'first');
if isempty(lo) || isempty(hi), tf = false; return; end
if vm-vs(lo) > 1.6 || vs(hi)-vm > 1.6, tf = false; return; end
p3 = local_quad3([vs(lo) vm vs(hi)],[ps(lo) ps(im) ps(hi)]);
tf = isfinite(p3.vertex) && p3.curv/2 > o.curvMin_pp1 ...
    && p3.vertex > vs(lo) && p3.vertex < vs(hi);
end
function Q = local_quad3(v,P)
% 三点抛物: 顶点与曲率(非均匀网格通用)
A = [v(:).^2, v(:), ones(3,1)];
if rcond(A) < 1e-12, Q = struct('vertex',NaN,'curv',NaN); return; end
c = A\P(:);
if c(1) <= 0, Q = struct('vertex',NaN,'curv',NaN); return; end
Q = struct('vertex',-c(2)/(2*c(1)), 'curv',2*c(1));
end
