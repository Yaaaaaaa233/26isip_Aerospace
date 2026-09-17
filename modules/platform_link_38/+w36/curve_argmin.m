function uo = curve_argmin(coefs,uLo,uHi,p,uKept)
%CURVE_ARGMIN 在归一化基系数coefs上求曲线谷底(只允许[uLo,uHi]∩速度域, 禁止外推)。
% 2026-09-08 样本支撑选择(可选第5参uKept=参与拟合的样本u集合): uCap截断后四次式
% 在样本稀疏的拟合区边缘会弯出"假谷"(实测argmin被吸到边缘≈12, û*冒高后飞行自采
% 样进一步确认, 50步量级难恢复)。真谷底两侧都有密样本, 假谷只有单侧——故提供
% uKept时只在"内点局部极小"中选样本支撑(±0.75内样本数)最大者, 支撑并列取f更低;
% 无内点极小才退回全局argmin(4参调用保持原行为)。
ug=linspace(max(p.lower+0.5,uLo),min(p.upper-1,uHi),451);
xg=(ug-7.5)/4.5;
Pv=coefs(1)+coefs(2)*xg+coefs(3)*xg.^2+coefs(4)*xg.^3+coefs(5)*xg.^4;
[~,im]=min(Pv);
uo=ug(im);
if nargin>=5 && ~isempty(uKept)
    loc=find(Pv(2:end-1)<Pv(1:end-2) & Pv(2:end-1)<=Pv(3:end))+1;   % 内点局部极小
    if ~isempty(loc)
        best=loc(1); bestCnt=-1; bestPv=Inf;
        for ii=loc
            cnt=nnz(uKept>=ug(ii)-0.75 & uKept<=ug(ii)+0.75);
            if cnt>bestCnt || (cnt==bestCnt && Pv(ii)<bestPv)
                bestCnt=cnt; bestPv=Pv(ii); best=ii;
            end
        end
        im=best; uo=ug(im);
    end
end
if im>1 && im<numel(ug)
    y1=Pv(im-1); y2=Pv(im); y3=Pv(im+1);
    den=y1-2*y2+y3;
    if den>1e-12
        uo=ug(im)+0.5*(ug(2)-ug(1))*(y1-y3)/den;
    end
end
uo=min(max(uo,p.lower+0.5),p.upper-1);
end
