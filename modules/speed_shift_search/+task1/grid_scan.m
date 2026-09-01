function s = grid_scan(f, lower, upper, resolution)
%GRID_SCAN 均匀网格扫描基线：无信息利用，评估次数由分辨率决定。
% 只保证定位到分辨率的一半；作为"搜索能耗最差、无跟踪能力"的下界对照。
v=linspace(lower,upper,round((upper-lower)/resolution)+1);
fv=inf(size(v));
for k=1:numel(v), fv(k)=f(v(k)); end
[fx,i]=min(fv);
s=struct('x',v(i),'fx',fx,'evals',numel(v),'bracket',[v(max(1,i-1)) v(min(end,i+1))]);
end
