function etaT = r2etaT(r, c)
%R2ETAT 转速比→推力比反演(预计算单调网格 pchip 插值; 见 config.m 第2步)。
etaT = interp1(c.rGrid, c.etaGrid, r, 'pchip', 'extrap');
end
