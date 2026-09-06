function s = brent_search(f, a, b, tol, maxEval)
%BRENT_SEARCH 黄金分割主干 + 逆抛物线插值加速的混合一维搜索(Brent式)。
% 与任务6 wsearch.brent_search 相同(独立重写版), f 由 settled_q 包装后
% 每次评估自带指令就位保持, 预算耗尽时 f 返回 Inf, 本搜索按比较逻辑安全退化。
C=(3-sqrt(5))/2; count=0; brackets=zeros(0,2);
a=min(a,b); b=max(a,b);
x=0.5*(a+b); fx=fev(x); fw=fx; fv=fx; w=x; v=x;
d=0; e=0;
while true
    xm=0.5*(a+b);
    tol1=2*eps(x)+0.5*tol; tol2=2*tol1;
    if abs(x-xm)<=tol2-0.5*(b-a) || count>=maxEval, break; end
    if abs(e)>tol1
        r=(x-w)*(fx-fv); q=(x-v)*(fx-fw);
        p=(x-v)*q-(x-w)*r; q=2*(q-r);
        if q>0, p=-p; end
        q=abs(q); etemp=e; e=d;
        if abs(p)>=abs(0.5*q*etemp) || p<=q*(a-x) || p>=q*(b-x)
            if x>=xm, e=a-x; else, e=b-x; end
            d=C*e;
        else
            d=p/q;
            if x+d-a<tol2 || b-(x+d)<tol2, d=tol1*sstep(xm-x); end
        end
    else
        if x>=xm, e=a-x; else, e=b-x; end
        d=C*e;
    end
    if abs(d)>=tol1, u=x+d; else, u=x+tol1*sstep(d); end
    fu=fev(u);
    if fu<=fx
        if u>=x, a=x; else, b=x; end
        v=w; fv=fw; w=x; fw=fx; x=u; fx=fu;
    else
        if u<x, a=u; else, b=u; end
        if fu<=fw || w==x
            v=w; fv=fw; w=u; fw=fu;
        elseif fu<=fv || v==x || v==w
            v=u; fv=fu;
        end
    end
end
s=struct('x',x,'fx',fx,'evals',count,'bracket',[a b],'brackets',brackets);

    function y=fev(x)
        count=count+1; brackets(end+1,:)=[a b]; y=f(x);
    end

    function s=sstep(b)   % Fortran式sign(a,b): |a|取a、符号取b, b=0取正
        if b>=0, s=1; else, s=-1; end
    end
end
