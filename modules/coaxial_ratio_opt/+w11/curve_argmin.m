function ro = curve_argmin(coefs,rLo,rHi,p,rKept)
%CURVE_ARGMIN 在归一化基系数coefs上求曲线谷底(只允许[rLo,rHi]∩桨比域, 禁止外推)。
% 样本支撑选择(2026-09-08修复移植): 截断拟合后四次式在样本稀疏的拟合区边缘会弯出
% "假谷"(argmin被吸到边缘并因自采样自我确认)。真谷底两侧都有密样本, 假谷只有单侧
% ——提供 rKept(参与拟合的样本r集合)时只在"内点局部极小"中选样本支撑(±0.04内
% 样本数)最大者, 支撑并列取 f 更低; 无内点极小才退回全局argmin(4参调用原行为)。
rg=linspace(max(p.lower+0.03,rLo),min(p.upper-0.03,rHi),451);
xg=(rg-1.0)/0.25;
Pv=coefs(1)+coefs(2)*xg+coefs(3)*xg.^2+coefs(4)*xg.^3+coefs(5)*xg.^4;
[~,im]=min(Pv);
ro=rg(im);
if nargin>=5 && ~isempty(rKept)
    loc=find(Pv(2:end-1)<Pv(1:end-2) & Pv(2:end-1)<=Pv(3:end))+1;   % 内点局部极小
    if ~isempty(loc)
        best=loc(1); bestCnt=-1; bestPv=Inf;
        for ii=loc
            cnt=nnz(rKept>=rg(ii)-0.04 & rKept<=rg(ii)+0.04);
            if cnt>bestCnt || (cnt==bestCnt && Pv(ii)<bestPv)
                bestCnt=cnt; bestPv=Pv(ii); best=ii;
            end
        end
        im=best; ro=rg(im);
    end
end
if im>1 && im<numel(rg)
    y1=Pv(im-1); y2=Pv(im); y3=Pv(im+1);
    den=y1-2*y2+y3;
    if den>1e-12
        ro=rg(im)+0.5*(rg(2)-rg(1))*(y1-y3)/den;
    end
end
ro=min(max(ro,p.lower+0.03),p.upper-0.03);
end
