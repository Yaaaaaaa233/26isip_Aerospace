function uo = curve_argmin(coefs,uLo,uHi,p)
%CURVE_ARGMIN 在归一化基系数coefs上求曲线谷底(只允许[uLo,uHi]∩速度域, 禁止外推)。
ug=linspace(max(p.lower+0.5,uLo),min(p.upper-1,uHi),451);
xg=(ug-7.5)/4.5;
Pv=coefs(1)+coefs(2)*xg+coefs(3)*xg.^2+coefs(4)*xg.^3+coefs(5)*xg.^4;
[~,im]=min(Pv);
uo=ug(im);
if im>1 && im<numel(ug)
    y1=Pv(im-1); y2=Pv(im); y3=Pv(im+1);
    den=y1-2*y2+y3;
    if den>1e-12
        uo=ug(im)+0.5*(ug(2)-ug(1))*(y1-y3)/den;
    end
end
uo=min(max(uo,p.lower+0.5),p.upper-1);
end
