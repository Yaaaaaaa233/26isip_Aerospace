function [dx, dlev] = drift_of(gamma, c)
%DRIFT_OF 干扰因子→(谷底漂移 Δr*, 功率水平因子 Plev) 查表(config 预计算, MT链数值)。
gamma=min(max(gamma,c.drMapG(1)),c.drMapG(end));
dx = interp1(c.drMapG, c.drMapD, gamma, 'pchip');
dlev = interp1(c.levMapG, c.levMapP, gamma, 'pchip');
end
