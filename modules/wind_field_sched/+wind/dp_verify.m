function out = dp_verify(c, rateMax)
%DP_VERIFY 动态规划数值验证解析调度的全局最优性（路线交付项）。
% 在一个盘旋周期上离散化 v 网格与时间步，DP 求最小平均功率的调度：
%   rateMax=Inf → 逐点最优（应与解析调度一致，验证公式）；
%   rateMax 有限 → |Δv|≤rateMax·tEval 的限速约束（未来加速度限制的接口）。
% 首步状态不限（进入窗口任意），代价=周期平均功率。
if nargin<2, rateMax=inf; end
vg=linspace(c.vLower,c.vUpper,c.dpGridN);
nT=max(8,round(c.circlePeriod/c.tEval));
tt=(0:nT-1)*c.tEval;
[wx,wy]=wind.wind_truth(c,tt);
psi=2*pi*tt/c.circlePeriod;
q=cos(psi).*wx+sin(psi).*wy; w2=wx.^2+wy.^2;
% 代价矩阵 C(m,i) = P0(|v_i·t̂_m + w_m|)
C=zeros(nT,c.dpGridN);
for m=1:nT
    u2=vg.^2+2*vg*q(m)+w2(m);
    C(m,:)=wind.power_curve(sqrt(max(u2,0)),c);
end
% 反向DP: cost-to-go 矩阵 Jf(nT,:) 为终端代价，逐行向前递推
Jf=nan(nT,c.dpGridN);
Jf(nT,:)=C(nT,:);
back=zeros(nT,c.dpGridN);
if isinf(rateMax)
    for m=nT-1:-1:1
        [Jnext,ix]=min(Jf(m+1,:));          % 无限速: 后继逐点最优
        back(m,:)=ix';
        Jf(m,:)=C(m,:)+Jnext;
    end
else
    dvm=abs(vg-vg')<=rateMax*c.tEval+1e-12; % 可达掩码(|Δv|≤限速)
    for m=nT-1:-1:1
        for i=1:c.dpGridN
            cand=Jf(m+1,dvm(:,i));
            [Jn,ix]=min(cand);
            back(m,i)=find(dvm(:,i),1)+ix-1;  % 可达带连续: 首址+偏移
            Jf(m,i)=C(m,i)+Jn;
        end
    end
end
% 前向回溯最优调度
[~,i0]=min(Jf(1,:));
vDp=zeros(1,nT); idx=i0; vDp(1)=vg(idx);
for m=1:nT-1
    idx=back(m,idx); vDp(m+1)=vg(idx);
end
% 解析对照（同一时间栅格）与相对差
sa=wind.analytic_sched(c,tt);
u2d=vDp.^2+2*vDp.*q+w2;
meanPdp=mean(wind.power_curve(sqrt(max(u2d,0)),c));
meanPan=mean(sa.Pmin);
out=struct('vDp',vDp,'t',tt,'meanPowerDp',meanPdp,'meanPowerAnalytic',meanPan,...
    'relDiff',(meanPdp-meanPan)/max(meanPan,eps),'rateMax',rateMax);
end
