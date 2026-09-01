function s = golden_search(f, a, b, tol, maxEval)
%GOLDEN_SEARCH Golden-section minimization of a unimodal f on [a,b].
% 与任务1同源实现(任务2自包含, 不依赖 task1_search——该目录正由他人修改)。
C=(3-sqrt(5))/2; count=0;
x1=a+C*(b-a); x2=b-C*(b-a);
f1=fev(x1); f2=fev(x2);
while (b-a)>tol && count<maxEval
    if f1<f2
        b=x2; x2=x1; f2=f1; x1=a+C*(b-a); f1=fev(x1);
    else
        a=x1; x1=x2; f1=f2; x2=b-C*(b-a); f2=fev(x2);
    end
end
if f1<f2, s=struct('x',x1,'fx',f1); else, s=struct('x',x2,'fx',f2); end
s.evals=count;
    function y=fev(x)
        count=count+1; y=f(x);
    end
end
