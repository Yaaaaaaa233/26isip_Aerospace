function [J, vG, PG, wells] = power_map(v, c, wantWells)
%POWER_MAP Rugged ground-truth curve on the debug quadratic base. Evaluator side.
% J(v) = 1 + 0.003(v-6)^2 + A1 cos(2π(v-6)/λ1+φ1) + A2 cos(2π(v-6)/λ2+φ2)
% 默认 φ1=φ2=π：崎岖项为绕 v=6 的偶函数(负余弦)——
%   * 全局最优点精确落在基准最优 6(无漂移)，曲线关于 6 严格对称；
%   * 对称设计使"滤波+顶点"类对称估计量在统计意义上无偏(用户"无偏移"要求)；
%   * P''(6)=0.006+ΣA k^2>0，6 为极小。改相位会破坏对称性(用户自担)。
% [vG,PG] = 数值全局最优(细网格)；wells = 局部极小列表 [v, J, |v-vG|]。
% 任务2无平移：曲线静态；真值只进评价日志，不返回给搜索器。
if nargin<3, wantWells=false; end
u = v - c.optimum0;
J = 1 + 0.003*u.^2 ...
    + c.rippleA1*cos(2*pi*u/c.rippleL1+c.rippleF1) ...
    + c.rippleA2*cos(2*pi*u/c.rippleL2+c.rippleF2);
ug = linspace(c.lower-c.optimum0, c.upper-c.optimum0, 8001);
yg = 1 + 0.003*ug.^2 ...
    + c.rippleA1*cos(2*pi*ug/c.rippleL1+c.rippleF1) ...
    + c.rippleA2*cos(2*pi*ug/c.rippleL2+c.rippleF2);
[PG, ig] = min(yg); vG = ug(ig) + c.optimum0;
if wantWells
    wells = zeros(0,3);
    for i = 2:numel(ug)-1
        lo = max(1,i-25); hi = min(numel(ug),i+25);   % 邻域约0.0625 m/s
        if yg(i) < yg(i-1) && yg(i) < yg(i+1) && yg(i) <= min(yg(lo:hi))
            wells(end+1,:) = [ug(i)+c.optimum0, yg(i), abs(ug(i)+c.optimum0-vG)]; %#ok<AGROW>
        end
    end
end
end
