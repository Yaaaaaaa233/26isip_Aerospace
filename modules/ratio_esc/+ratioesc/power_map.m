function J = power_map(actualRatio,optimum,c)
%POWER_MAP Dimensionless power along an ASSUMED constant-thrust manifold.
J=1+c.curvature*(actualRatio-optimum).^2;
end
