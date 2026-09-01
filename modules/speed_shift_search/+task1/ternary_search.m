function s = ternary_search(f, a, b, tol, maxEval)
%TERNARY_SEARCH 每轮取三分点两次评估、丢弃一侧区间的经典三分搜索。
% 作为黄金分割的对照基线：同样的无导数单峰保证，但每轮的两个内点
% 无法互相复用，同等精度约需黄金分割的2倍评估次数。
% 返回值取最后一次迭代中较优的三分点，不再额外评估中点。
count=0; brackets=zeros(0,2); bestX=NaN; bestF=Inf;
while (b-a)>tol && count<maxEval
    m1=a+(b-a)/3; m2=b-(b-a)/3;
    f1=fev(m1); f2=fev(m2);
    if f1<f2, b=m2; if f1<bestF, bestX=m1; bestF=f1; end
    else,      a=m1; if f2<bestF, bestX=m2; bestF=f2; end
    end
end
if isnan(bestX), bestX=0.5*(a+b); bestF=fev(bestX); end
s=struct('x',bestX,'fx',bestF,'evals',count,'bracket',[a b]);
s.brackets=brackets;

    function y=fev(xx)
        count=count+1; brackets(end+1,:)=[a b]; y=f(xx);
    end
end
