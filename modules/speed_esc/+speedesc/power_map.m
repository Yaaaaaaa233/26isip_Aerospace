function J = power_map(speed,optimum,c)
%POWER_MAP Algorithm-validation proxy, not measured X8 power.
if strcmp(c.curve,'debug')
    J=1+0.003*(speed-optimum).^2;
else
    b=2*(1-c.minimumRatio); x=speed./optimum;
    J=1-1.5*b*x.^2+b*x.^3;
end
end
