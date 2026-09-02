function [log, info] = run_policy(mode, c)
%RUN_POLICY 三档信息结构调度策略执行一幕（路线交付项：风速信息价值）。
% mode:
%   'known'   已知风(上界参照)：直接用真风解析调度 v*(t)——信息结构参照,
%             非因果算法(其意义恰是给出"若风已知能省多少"的标尺)
%   'online'  在线估计风(因果)：滑窗LM风估计 ŵ → 解析公式调度; 配
%             观测性激励(每 obsDuty 步 ±obsDither, 占空比小、近最优处
%             功率对空速不敏感的补偿)
%   'blind'   不知风：匀速在线搜索(基准/探测两相交替的长窗爬山)
%   'uniform' 离线最优匀速(信息-free参照, 用真值离线选 vU)
%   'fixed'   恒飞 v=V*(朴素基线)
% 黑箱口径：所有因果模式只见 plant.q 的带噪测量+航向+时间(红线1)。
plant=wind.plant(c);
n=c.duration;
est=wind.est_reset(c);
tt=(0:n-1)*c.tEval;
psiAll=2*pi*tt/c.circlePeriod;
if strcmp(mode,'uniform')
    uB=wind.uniform_baseline(c);
    vU=uB.vU;
end
vU=NaN; vB=c.Vstar; blindDir=1; blindPhase=0; accBase=0; accProbe=0; cntB=0; cntP=0;
vHist=zeros(1,n); estX=zeros(1,n); estY=zeros(1,n);
dither=0;
for k=1:n
    t=tt(k); psi=psiAll(k);
    switch mode
        case 'known'
            sa=wind.analytic_sched(c,t);
            v=sa.v;
        case 'online'
            if est.filled>=16
                qh=cos(psi)*est.theta(1)+sin(psi)*est.theta(2);
                w2h=est.theta(1)^2+est.theta(2)^2;
                disc=c.Vstar^2-w2h;
                if disc>=0
                    v=-qh+sqrt(qh^2+disc);
                else
                    v=-qh;
                end
            else
                v=c.Vstar;
            end
            if mod(k,c.obsDuty)==0                          % 观测性激励
                if mod(k,2*c.obsDuty)<c.obsDuty, dither=c.obsDither; else, dither=-c.obsDither; end
            else
                dither=0;
            end
            v=v+dither;
        case 'blind'
            ph=floor((k-1)/c.blindPeriod);                  % 基准/探测两相
            if mod(ph,2)==0
                v=vB;                                       % 基准相
            else
                v=vB+blindDir*c.blindStep;                  % 探测相
            end
        case 'uniform'
            v=vU;
        case 'fixed'
            v=c.Vstar;
        otherwise
            error('wind:RunPolicy','Unknown mode: %s',mode);
    end
    v=min(max(v,c.vLower),c.vUpper);
    Pm=plant.q(v,mode);
    est=wind.est_step(est,v,psi,Pm);                        % 估计器持续更新
    vHist(k)=v; estX(k)=est.theta(1); estY(k)=est.theta(2);
    % --- 不知风: 相位结束时的接受/换向逻辑 ---
    if strcmp(mode,'blind')
        if mod(floor((k-1)/c.blindPeriod),2)==0
            accBase=accBase+Pm; cntB=cntB+1;
        else
            accProbe=accProbe+Pm; cntP=cntP+1;
        end
        if cntP==c.blindPeriod                               % 一对相完成
            mB=accBase/cntB; mP=accProbe/cntP;
            if mP<mB-1e-4
                vB=min(max(vB+blindDir*c.blindStep,c.vLower),c.vUpper);
            else
                blindDir=-blindDir;
            end
            accBase=0; accProbe=0; cntB=0; cntP=0;
        end
    end
end
log=plant.table();
log.vCmd=vHist(:); log.windEstY=estY(:); log.windEstX=estX(:);
m=wind.mop_moe(log,c);
info=struct('mode',mode,'moe',m,'vUniform',vU,'finalWindEst',[est.theta(1) est.theta(2)],...
    'nSteps',n);
end
