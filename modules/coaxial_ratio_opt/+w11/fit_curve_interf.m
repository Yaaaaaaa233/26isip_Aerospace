function [coefs,th,fitRms,rLo,rHi,rKept] = fit_curve_interf(psSet,rrSet,PmSet,p,thFixed)
%FIT_CURVE_INTERF 联合辨识 min Σ (P_i − f(r_i − δ̂(ψ_i)))², f=四次多项式(归一化基)。
% 可辨识性与规范固定(gauge, 与速度包"必须双向扫"对应的本域关键设计):
%   从 (r,P) 数据只能辨识"当前表观曲线" g(r)=dlev·f(r−δ) —— δ 与 f 各自不可分
%   (任意 δ 配上平移的 f 预测完全相同)。唯一可辨识的全局量是表观谷底位置。
%   故标定/重拟合采用规范 θ(1)=a0 ≡ 0: f̂ 的 argmin 直接给出表观谷底(可辨识),
%   均匀漂移由重拟合链跟踪; 谐波分量 θ(2:3)=[a1,b1] 有航向调制这一独立信息通道
%   (sector/姿态不对称类干扰), 由岭正则+GN辨识, 无调制时被压向0。
%   相对冻结模型的增量漂移(可辨识)由探针斜率承担(hybrid在线段; 见 hybrid_run.m)。
% 内层(固定θ) f 线性最小二乘(岭1e-8); 外层(对 a1,b1) 多起点 Gauss-Newton(限步)。
% 返回: 归一化基系数(基 x=(u-1)/0.25, u=r−δ̂), θ(规范 a0=0), 拟合RMS,
%       样本覆盖的 u 范围, rKept=参与拟合的样本 u 集合(供支撑谷底选择)。
ps=psSet(:); rr=rrSet(:); Pm=PmSet(:);
uAll=min(max(rr,0.76),1.24);
% 截断(修复移植): 扫描域边缘外的样本不参与拟合; 兜底: 保留样本过少放宽到90分位。
uCap=p.swHi+0.02;
keep = uAll<=uCap & uAll>=p.swLo-0.02;
if nnz(keep)<max(30,ceil(0.3*numel(uAll)))
    uSrt=sort(uAll);
    keep = uAll<=uSrt(ceil(0.9*numel(uSrt)));
end
ps=ps(keep); rr=rr(keep); Pm=Pm(keep);
rKept=sort(min(max(rr,0.76),1.24));
rLo=max(p.lower+0.03, min(rKept));
rHi=min(p.upper-0.03, max(rKept));
% 多起点: (a1,b1) 网格(a0 规范固定为0)
S=[-0.03 0 0.03 -0.02 0.02 -0.02 0 0; -0.03 -0.03 -0.03 0 0 0.02 0.02 0].';
bestSse=Inf; coefs=nan(1,5); th=[0;0;0]; fitRms=NaN;
if nargin>=5 && ~isempty(thFixed) && numel(thFixed)==3
    % thFixed: 冻结干扰谐波估计(在线重拟合用当前值——窄带样本上重估谐波会被
    % 曲线偏差污染; 与速度包 wFixed 同理)。a0 仍按规范=0。
    th2=[0; thFixed(2); thFixed(3)];
    [coefs,sseW]=profSol(th2,ps,rr,Pm,p);
    th=th2; fitRms=sqrt(sseW/numel(rKept));
    return;
end
for si=1:size(S,1)
    th2=[0; S(si,1); S(si,2)];
    for it=1:8
        [cC,sse]=profSol(th2,ps,rr,Pm,p);
        e=0.005;
        [~,s1]=profSol(th2+[0;e;0],ps,rr,Pm,p);
        [~,s2]=profSol(th2+[0;0;e],ps,rr,Pm,p);
        g=[0; (s1-sse)/e; (s2-sse)/e];
        step=0.9*g(2:3);
        if norm(step)>0.02, step=step*0.02/norm(step); end
        th2(2:3)=th2(2:3)-step;
        if norm(step)<1e-6, break; end
    end
    th2(2:3)=min(max(th2(2:3),-0.10),0.10);
    [cC,sse]=profSol(th2,ps,rr,Pm,p);
    if sse<bestSse
        bestSse=sse; th=th2; coefs=cC;
        fitRms=sqrt(bestSse/numel(rKept));
    end
end
end

function [cOut,sseOut]=profSol(thq,ps,rr,Pm,p)
u=min(max(rr-(thq(1)+thq(2)*cos(ps)+thq(3)*sin(ps)),0.76),1.24);
x=(u-1.0)/0.25;                            % 归一化基, 条件数健康
Ph=[ones(size(u)), x, x.^2, x.^3, x.^4];
cOut=(Ph.'*Ph+1e-8*eye(5))\(Ph.'*Pm);
sseOut=sum((Ph*cOut-Pm).^2);
end
