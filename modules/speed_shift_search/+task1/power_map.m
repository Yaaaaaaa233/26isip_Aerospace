function J = power_map(v, c)
%POWER_MAP Fixed base curve J0(v), minimum at c.optimum0. Evaluator side only.
% 任务1的平移是严格曲线平移：P(v,t)=power_map(v-dx(t))+dy(t)。
% 注意这与 +speedesc/power_map 的"改v*再算x"横向缩放不同，是有意选择：
% 平移不改变曲线形状与最优点处的曲率，便于考察算法的平移不变性。
if strcmp(c.curve,'debug')
    J=1+0.003*(v-c.optimum0).^2;
else
    b=2*(1-c.minimumRatio); x=v./c.optimum0;
    J=1-1.5*b*x.^2+b*x.^3;
end
end
