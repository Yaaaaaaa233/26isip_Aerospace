function plant = plant(c)
%PLANT 环境风场黑箱被控对象（对象侧；空速物理在对象内换算，红线2位置）。
% 黑箱口径（红线1）：console 每步提交地速 v 并收回一个带噪功率读数；
% 真值风/真值功率只进评价日志。航向 ψ(t) 是飞机可测状态(罗盘)，不算真值泄漏。
%   空速 u = v·t̂ + w(t)，P_true = P0(|u|)，P_meas = P_true·(1+σ·randn)
rng(c.seed);
n=c.duration; rows=zeros(n,9); tags=cell(n,1); k=0;
plant=struct('q',@q,'count',@cnt,'table',@tbl);
    function cn=cnt(), cn=k; end
    function Pm=q(v,tag)
        assert(k<n,'wind:Plant','Evaluation budget exhausted.');
        k=k+1; t=(k-1)*c.tEval;
        a=wind.airspeed(v,c,t);
        Ptrue=wind.power_curve(sqrt(max(a.u2,1e-12)),c);
        Pm=Ptrue*(1+c.noiseSigma*randn);
        rows(k,:)=[k,t,v,Pm,Ptrue,a.wx,a.wy,a.q,NaN];
        tags{k}=tag;
    end
    function out=tbl()
        assert(k==n,'wind:Plant','Run incomplete: %d of %d.',k,n);
        out=table(rows(:,1),rows(:,2),rows(:,3),rows(:,4),rows(:,5),...
            rows(:,6),rows(:,7),rows(:,8),rows(:,9),string(tags),...
            'VariableNames',{'step','time','speed','powerMeas','powerTrue',...
            'windX','windY','windQ','windEstX','tag'});
    end
end
