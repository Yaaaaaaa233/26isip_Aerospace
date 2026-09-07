function cdw = calibrate_cdw(c)
%CALIBRATE_CDW 二分标定下桨有效下洗系数: 使 MT 链(gamma=1)的最优桨比 r*_mt = c.rStar0。
% 锚点依据: Opazo et al. 2022 Sec V.C 飞试——最小总电流出现在 eta_Omega≈0.89。
% 结构(诱导+剖面形状)取自链本身, 此单参数只吸收"下桨有效平均下洗占比"的模型简并。
etaG=linspace(0.30,14.0,1600);
lo=0.002; hi=0.200;
    function rs = valley_of(x)
        rMap=w11.r_of_etaT(etaG,c,x,1.0);
        Pm=w11.chain_power_at(etaG,rMap,c,x,1.0);
        [~,im]=min(Pm);
        rs=rMap(im);
    end
rsLo=valley_of(lo); rsHi=valley_of(hi);
assert((rsLo-c.rStar0)*(rsHi-c.rStar0)<0,'w11:Config',...
    'cdw calibration bracket failed (rStar0 outside attainable valley range).');
% r*_mt 随 cdw 单调递减(下桨下洗越强, 最优越偏向高转速差), 标准二分:
for it=1:60
    mid=0.5*(lo+hi);
    if valley_of(mid)>c.rStar0, lo=mid; else, hi=mid; end
end
cdw=0.5*(lo+hi);
end
