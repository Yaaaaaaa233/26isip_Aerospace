function F = p3_fit_valley(vSet,PSet,o)
%QUAD_SIM.P3_FIT_VALLEY 1-D 功率-速度曲线拟合 + 支撑选谷(多臂适配共享原语)。
% 直线链移植 w36.fit_curve_wind(内层线性最小二乘)+w36.curve_argmin(支撑谷底
% 选择/禁外推/抛物细化), 裁掉 2-D 风辨识外层(见 p3_multiarm_opt 裁决 a)。
% 拟合: P ≈ 四次多项式(归一化基 x=(v-9)/5, [4,14]->[-1,1], 条件数健康)。
% 返回 F:
%   F.coefs  1x5 归一化基系数(冻结形状 g0, 供平移对齐; 选谷不用它——
%            四次式 wiggle 伪极小曾把谷吸到支撑顶, 见 worklog 2026-10-15)
%   F.vStar  谷底(m/s): 样本锚定(锚=实测最优样本, 预注册语义) + 邻域三点
%            抛物细化(顶点须落括号内); 锚在样本边 -> 靠边三点顶点外推
%            (可出域, **仅用于谷预测/平移对齐**, 动作限幅由臂负责)——
%            本链相位 1 真谷在域外(v*=2), 边界截断的 argmin 无法预测平移
%            后的谷, 顶点外推是预测唯一信息来源;
%            顶点距边 >maxVertexOut 视为病态, 退锚点
%   F.vLo/F.vHi  样本覆盖范围(支撑, 禁外推用)
%   F.vKept  参与拟合的样本 v(升序, 支撑判据)
%   F.curv   谷底曲率 2a (W/(m/s)^2; 供探针 bEst 初值)
%   F.edgeMin  true=谷被边界截断(vStar 在域外)
% o: vMin_mps/vMax_mps/curvMin_pp1/maxVertexOut_mps(默认 3)
narginchk(3,3);
if ~isfield(o,'maxVertexOut_mps'), o.maxVertexOut_mps = 3; end
v = vSet(:); P = PSet(:);
assert(numel(v) >= 3 && numel(v) == numel(P), ...
    'quad_sim:P3FitValley','need >=3 paired samples.');
% 归一化基最小二乘(ridge 1e-8, 与 w36 profSol 同式)——仅作冻结形状 g0
% 供平移对齐; 选谷不用四次式(wiggle 伪极小曾把谷吸到支撑顶, 见 worklog)。
x = (v-9)/5;
Ph = [ones(size(x)), x, x.^2, x.^3, x.^4];
coefs = (Ph.'*Ph+1e-8*eye(5))\(Ph.'*P);
% 速度聚类(0.05 m/s 桶, 同速子对取均值)——三点抛物需要不同速度的样本
[vc,~,iu] = unique(round(v*20)/20);
Pc = accumarray(iu,P,[],@mean);
[vSorted,ixS] = sort(vc); PSorted = Pc(ixS);
vKept = vSorted;
vLo = min(v); vHi = max(v);
% 谷底 = 样本锚定(锚=实测最优样本, 预注册"锚定实测最优样本"语义):
% 邻域三点抛物细化(顶点须落括号内), 锚在样本边 -> 靠边三点顶点外推
% (仅谷预测/平移对齐用, 可出域; 动作限幅由臂负责)。
[~,im] = min(PSorted);
vStar = vSorted(im);
curv = NaN; edgeMin = false;
if im > 1 && im < numel(vSorted)
    p3 = local_quad3(vSorted(im-1:im+1),PSorted(im-1:im+1));
    if isfinite(p3.vertex) && p3.curv > 0 ...
            && p3.vertex >= vSorted(im-1) && p3.vertex <= vSorted(im+1)
        vStar = p3.vertex;
        curv = max(p3.curv,0);
    end
elseif numel(vSorted) >= 3
    edgeMin = true;
    if im <= 1, idx = 1:3; else, idx = numel(vSorted)+(-2:0); end
    p3 = local_quad3(vSorted(idx),PSorted(idx));
    if isfinite(p3.vertex) && abs(p3.vertex-vStar) <= o.maxVertexOut_mps
        vStar = p3.vertex;         % 顶点可出域; 臂动作限幅自理
        curv = max(p3.curv,0);
    end
end
if vStar <= o.vMin_mps+1e-9 || vStar >= o.vMax_mps-1e-9 ...
        || vStar <= vLo+1e-9 || vStar >= vHi-1e-9
    edgeMin = true;
end
if isnan(curv)
    xx = (vStar-9)/5;
    curv = (2*coefs(3)+6*coefs(4)*xx+12*coefs(5)*xx^2)/25;
end
F = struct('coefs',coefs,'vStar',vStar,'vLo',vLo,'vHi',vHi, ...
    'vKept',vKept,'curv',max(curv,0),'edgeMin',edgeMin);
end
function y = local_poly(c,v)
x = (v-9)/5;
y = c(1)+c(2)*x+c(3)*x.^2+c(4)*x.^3+c(5)*x.^4;
end
function Q = local_quad3(v,P)
% 三点抛物: 顶点与曲率(均匀/非均匀网格通用)
A = [v(:).^2, v(:), ones(3,1)];
if rcond(A) < 1e-12, Q = struct('vertex',NaN,'curv',NaN); return; end
c = A\P(:);
if c(1) <= 0, Q = struct('vertex',NaN,'curv',NaN); return; end
Q = struct('vertex',-c(2)/(2*c(1)), 'curv',2*c(1));
end
