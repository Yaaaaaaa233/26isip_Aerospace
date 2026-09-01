function s = golden_search(f, a, b, tol, maxEval)
%GOLDEN_SEARCH Golden-section minimization of a unimodal f on [a,b].
% 每次评估区间收缩 0.618（区间比 0.382 的对称内点互相复用），
% 是无导数单峰搜索中逐次评估意义下的最优策略(Kiefer 1953)。
% 返回 s.x 当前最优点、s.evals 评估次数、s.bracket 最终夹逼区间。
C=(3-sqrt(5))/2; count=0; brackets=zeros(0,2);
x1=a+C*(b-a);   % 左内点
x2=b-C*(b-a);   % 右内点
f1=fev(x1); f2=fev(x2);
while (b-a)>tol && count<maxEval
    if f1<f2
        b=x2; x2=x1; f2=f1; x1=a+C*(b-a); f1=fev(x1);
    else
        a=x1; x1=x2; f1=f2; x2=b-C*(b-a); f2=fev(x2);
    end
end
if f1<f2, s=struct('x',x1,'fx',f1); else, s=struct('x',x2,'fx',f2); end
s.evals=count; s.bracket=[a b]; s.brackets=brackets;

    function y=fev(x)
        count=count+1; brackets(end+1,:)=[a b]; y=f(x);
    end
end
