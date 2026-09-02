function u = inv_power(P, c, branch)
%INV_POWER 代理功率的数值逆：给 P 求空速 |u|（双分支二分）。
% P0 在 [0,V*] 递减、(V*,∞) 递增、P0(V*)=P* 为全局极小——给定 P>P*
% 有两个候选 |u|（谷两侧）。branch:
%   'low'  低速支 |u|∈[0.05·V*, V*]
%   'high' 高速支 |u|∈[V*, 3·V*]
%   'near' 默认, 取 |u/V*−1| 较小的一支(近工作点, 有符号歧义时不可靠)
% P≤P*(噪声) 时返回 V*。注: 在线风估计(est_step)不使用本函数——它直接
% 在功率域做LM残差, 避开谷底双支歧义; 本函数作为独立工具保留。
if nargin<3, branch='near'; end
b=2*(1-c.Pstar);
sz=size(P);
P=P(:);
u=ones(size(P))*c.Vstar;
for k=1:numel(P)
    if P(k)<=c.Pstar+1e-12, continue; end
    lo=0.05; hi=1;                               % 低速支二分
    for it=1:40
        mid=(lo+hi)/2;
        if 1-1.5*b*mid^2+b*mid^3>P(k), lo=mid; else, hi=mid; end
    end
    xl=(lo+hi)/2;
    lo=1; hi=3;                                   % 高速支二分
    for it=1:40
        mid=(lo+hi)/2;
        if 1-1.5*b*mid^2+b*mid^3<P(k), lo=mid; else, hi=mid; end
    end
    xr=(lo+hi)/2;
    switch branch
        case 'low', x=xl;
        case 'high', x=xr;
        otherwise
            if abs(xl-1)<=abs(xr-1), x=xl; else, x=xr; end
    end
    u(k)=x*c.Vstar;
end
u=reshape(u,sz);
end
