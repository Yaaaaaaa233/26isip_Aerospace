function [coefs,w,fitRms,uLo,uHi,uKept] = fit_curve_wind(psSet,vvSet,PmSet,p,wFixed)
%FIT_CURVE_WIND 联合辨识 min Σ (P_i − f(|v_i·t̂_i − w|))², f=四次多项式(归一化基)。
% 任务3.6共享工具(sweepcal与rl的Stage A都调用): 内层(固定w) f 线性最小二乘;
% 外层(对w) 多起点数值下降(8方向×3幅值网格, 限步防发散)。
% 返回: 归一化基系数(基x=(u-7.5)/4.5), 风矢量, 拟合RMS, 样本覆盖的u范围,
%       uKept=截断后参与拟合的样本u集合(升序, 供curve_argmin做支撑谷底选择)。
% 注意: argmin求谷底时只允许在[uLo,uHi]内搜索(多项式外推区会假下潜)。
ps=psSet(:); vv=vvSet(:); Pm=PmSet(:);
cx=vv.*cos(ps); cy=vv.*sin(ps);
uAll=min(max(hypot(cx,cy),0.5),19.5);
% 2026-09-08修: 高速段(u>swHi+0.5)样本不参与拟合——扫频顶(v→12)顺风段会产生
% u≈13–17的样本, 处于曲线陡升+涟漪区, 四次式在该区系统性欠拟合(实测偏差≈1),
% LS会拿谷底精度去换高点拟合 → û*被拖偏; 谷底辨识只需覆盖[~3,12], 风辨识来自
% 速度域覆盖与航向几何, 不依赖高u样本。极端输入兜底: 保留样本过少则放宽到u90分位。
uCap=min(p.upper-1, p.swHi+0.5);
keep = uAll<=uCap;
if nnz(keep)<max(30,ceil(0.3*numel(uAll)))
    uSrt=sort(uAll);
    keep = uAll<=uSrt(ceil(0.9*numel(uSrt)));
end
cx=cx(keep); cy=cy(keep); Pm=Pm(keep); uAll=uAll(keep);
uKept=sort(uAll);
uLo=max(p.lower+0.5, min(uAll));
uHi=min(uCap,        max(uAll));
ang=(0:7)*pi/4; mag=[1.5 3.5 6.0];
S=zeros(numel(ang)*numel(mag),2); ii=0;
for m=mag
    for a=ang
        ii=ii+1; S(ii,:)=[cos(a)*m, sin(a)*m];
    end
end
bestSse=Inf; coefs=nan(1,5); w=[0;0]; fitRms=NaN;
if nargin>=5 && isscalar(wFixed)==false && numel(wFixed)==2
    % wFixed: 冻结风估计(在线重拟合用标定值——窄带样本上重估风会被曲线偏差污染)
    [coefs,sseW]=profSol(wFixed(:),cx,cy,Pm);
    w=wFixed(:); fitRms=sqrt(sseW/numel(uAll));
    return;
end
% 2026-09-09 抗退化改造(平台强风实测: 联合SSE最优解的谷底跑到11.25, 真值5.15):
% 机制——平台曲线陡峭, 四次式在保留带宽上无法完全表出, 错误ŵ+柔性四次式可以在
% 保留带内拿到比真解更低的SSE(谷底落在样本稀疏区)。单一SSE选择不再可靠, 改为:
%   (1) 收集全部下降终解(去重, 按SSE取前5)作为候选盆地;
%   (2) "帧坍缩"判据: P严格只是空速的函数, 正确的ŵ使所有(v,ψ)样本在u=|v·t̂−ŵ|
%       坐标系中坍缩到一条曲线(分箱内P方差最小); 错误ŵ把云散开(方差大);
%   (3) 谷底内点约束: û*必须落在样本u范围内侧(距边缘>=0.25), 贴边=外推伪影;
%   选择代价 = SSE比值 + 0.8×帧方差比值, 在内点候选中取最小。
candW=zeros(24,2); candSse=Inf(24,1); nC=0;
for si=1:size(S,1)
    w2=S(si,:).';
    for it=1:8
        [cC,sse]=profSol(w2,cx,cy,Pm);
        e=0.08;
        [~,s1]=profSol(w2+[e;0],cx,cy,Pm);
        [~,s2]=profSol(w2+[0;e],cx,cy,Pm);
        g=[(s1-sse)/e; (s2-sse)/e];
        step=0.9*g;
        if norm(step)>0.30, step=step*0.30/norm(step); end
        w2=w2-step;
        if norm(step)<1e-5, break; end
    end
    w2=min(max(w2,-8),8);                % 风幅值物理上限
    [cC,sse]=profSol(w2,cx,cy,Pm);
    if sse<bestSse, bestSse=sse; end
    dup=false;
    for j=1:nC
        if norm(candW(j,:)-w2)<0.4
            dup=true;
            if sse<candSse(j), candSse(j)=sse; candW(j,:)=w2; end
            break;
        end
    end
    if ~dup && nC<24, nC=nC+1; candW(nC,:)=w2; candSse(nC)=sse; end
end
if nC==0, return; end
[~,ordS]=sort(candSse(1:nC),'ascend');
topW=candW(ordS(1:min(5,nC)),:); topSse=candSse(ordS(1:min(5,nC)));
nb=12; uSrt=sort(uAll); eIdx=round(linspace(1,numel(uSrt),nb+1));
eEdge=uSrt(eIdx); eEdge(1)=eEdge(1)-1; eEdge(end)=eEdge(end)+1;
bid=discretize(uAll,eEdge);   % 每样本的箱号(histcounts第一输出是计数, 不是箱号)
scoreV=Inf(1,size(topW,1));
for i=1:size(topW,1)
    uk=min(max(hypot(cx-topW(i,1),cy-topW(i,2)),0.5),19.5);
    vTot=0;
    for b=1:nb
        mk=bid==b;
        if nnz(mk)>=2, vTot=vTot+sum((Pm(mk)-mean(Pm(mk))).^2); end
    end
    if vTot>0, scoreV(i)=vTot; end
end
% 选择: 先剔除谷底非内点的候选, 再在"SSE比值+0.8x帧方差比值"最小者中定选
sel=0; bestCost=Inf;
for i=1:size(topW,1)
    cCi=profSol(topW(i,:).',cx,cy,Pm);
    uArgT=w36.curve_argmin(cCi,uLo,uHi,p,uKept);
    if ~isfinite(uArgT), continue; end
    if uArgT<uLo+0.25 || uArgT>uHi-0.25, continue; end
    sRef=min(scoreV(scoreV<Inf));
    if ~isfinite(sRef), sRef=1e-12; end
    cost=(topSse(i)/max(topSse(1),1e-12)) + 0.8*(scoreV(i)/sRef);
    if cost<bestCost, bestCost=cost; sel=i; end
end
if sel==0
    [~,sel]=min(topSse);
end
w=topW(sel,:).';
[coefs,sseSel]=profSol(w,cx,cy,Pm);
fitRms=sqrt(sseSel/numel(uAll));
end

function [cOut,sseOut]=profSol(wq,cx,cy,Pm)
u=min(max(hypot(cx-wq(1),cy-wq(2)),0.5),19.5);
x=(u-7.5)/4.5;                            % 归一化基, 条件数健康
Ph=[ones(size(u)), x, x.^2, x.^3, x.^4];
cOut=(Ph.'*Ph+1e-8*eye(5))\(Ph.'*Pm);
sseOut=sum((Ph*cOut-Pm).^2);
end
