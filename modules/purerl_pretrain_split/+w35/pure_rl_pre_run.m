function info = pure_rl_pre_run(plant, p, n, mode, warmPlant)
%PURE_RL_PRE_RUN 预训练纯奖励RL(任务3.5): 把3.4的purerl拆成在线/离线两种部署。
%   mode='off' 预训练离线部署: 试飞时段预训练收敛后冻结策略, 评估期纯贪心执行,
%              不再学习(部署确定性/可复现, 无探索能耗);
%   mode='on'  预训练在线部署: 预训练初始化策略与分桶基线, 评估期继续小幅在线
%              修正(lr=1/4, σ=0.5), 吸收干扰漂移。
% ── 预训练(试飞时段)为何不违反预算公平 ──
% 预训练在独立plant实例上进行, 不计入600步评测预算、不进评价表/MOE(任务书口径:
% 任务窗从第一次评估步开始); 试飞场景=static、湍流为同分布不同实现(scenario seed
% 偏移), 不泄漏评测段任何真值。信息预算类别与扫频标定(占预算)不同, 结论表述时
% 必须注明"预训练步为额外试飞预算"(红线3边界, 见README)。
% ── 收敛判据(自动停止"当你认为模型学习好了") ──
% 每 blk=200 步一块: 块内平均|策略更新| < 0.02 且 块均功率相对改善 < 0.05% → 判定
% 收敛; 最少2块(400步)起判, 上限 p.plWarmMax(2400步)。σ 从 plSigma0=1.2 退火到
% 0.5(预训练结束时已到部署探索幅值, 评估期无需重新退火)。
% 因果口径(红线1): 预训练与评估都只拿带噪功率+自身指令(航向死推)+tEval; 无曲线/
% u*/风/噪声真值; p为ctrl_view白名单。
if nargin<5
    error('w35:PureRLPre','需要 warmPlant(试飞时段plant实例)。');
end
nBin=round(p.plBins);
muB=p.initialSpeed*ones(1,nBin);
bBase=nan(1,nBin);

% ================= 试飞预训练时段(不占评测预算) =================
qsW=w35.settled_q(warmPlant,p,1e9);
sigma=p.plSigma0;
psiUnw=0; Pb=NaN; k=0; lastSgn=1; stepsSinceFlip=99;
blk=200; blkN=0; blkSumP=0; blkCnt=0; blkSumDB=0;
blkMeanP=[]; blkMeanDB=[]; converged=false; warmupSteps=0;
while warmPlant.count()<p.plWarmMax
    k=k+1;
    ib=min(nBin,floor(mod(psiUnw,2*pi)/(2*pi/nBin))+1);
    if stepsSinceFlip>=p.plHold, lastSgn=-lastSgn; stepsSinceFlip=0; end
    stepsSinceFlip=stepsSinceFlip+1;
    v=min(max(muB(ib)+lastSgn*sigma,p.lower+0.3),p.upper-0.3);
    c0=warmPlant.count();
    Pm=qsW(v,'warmup');
    if ~isfinite(Pm), break; end
    sUsed=warmPlant.count()-c0;
    for j=1:sUsed
        psiUnw=psiUnw+v/p.turnRadius*p.tEval;
    end
    if isnan(Pb), Pb=Pm; else, Pb=0.98*Pb+0.02*Pm; end
    if isnan(bBase(ib)), bBase(ib)=Pm; else, bBase(ib)=0.9*bBase(ib)+0.1*Pm; end
    r=-(Pm-bBase(ib))/max(abs(bBase(ib)),0.1);
    aDev=v-muB(ib);
    muStep=0;
    if sUsed>1
        % 瞬态测量不更新(与purerl同款): 只采样, 不学习
    else
        lrT=p.plLr*max(0.25,0.99^k);
        K=round(p.plKern);
        for b=ib-K:ib+K
            b2=mod(b-1,nBin)+1;
            wgt=exp(-0.5*((b-ib)/max(K,0.5))^2);
            dB=lrT*wgt*r*aDev/(sigma^2);
            dB=min(max(dB,-0.05),0.05);
            muB(b2)=min(max(muB(b2)+dB,p.lower+0.3),p.upper-0.3);
            muStep=muStep+abs(dB)*wgt;
        end
    end
    blkSumP=blkSumP+Pm; blkCnt=blkCnt+1; blkSumDB=blkSumDB+muStep;
    sigma=max(0.50,sigma*0.998);
    if blkCnt>=blk
        blkN=blkN+1;
        mP=blkSumP/max(blkCnt,1); mDB=blkSumDB/max(blkCnt,1);
        blkMeanP(end+1)=mP; blkMeanDB(end+1)=mDB; %#ok<AGROW>
        % 收敛=功率平台期: 近两块的平均相对改善<0.1%(块均噪声SEM≈0.06%, 取2倍余量),
        % 单看|策略更新|不行——部署lr下的噪声驱动抖动(~0.05)会淹没一切固定阈值。
        if blkN>=3
            imp=(blkMeanP(end-2)-mP)/max(abs(mP),0.1)/2;
            if imp<1e-3, converged=true; end
        end
        blkSumP=0; blkCnt=0; blkSumDB=0;
        if converged && k>=400, break; end
    end
end
warmupSteps=warmPlant.count();
muPre=muB; bBasePre=bBase; sigmaPre=max(0.50,sigma);

% ================= 评估时段(600步任务窗) =================
qs=w35.settled_q(plant,p,n);
psiUnw=0; kStep=0; v=p.initialSpeed; lastSgn=1; stepsSinceFlip=99;
Pb=NaN; sigma=p.plSigmaMin;
muTrace=nan(1,n); sigHist=nan(1,n); ibHist=zeros(1,n);
nUpdate=0;
while plant.count()<n
    kStep=kStep+1;
    ib=min(nBin,floor(mod(psiUnw,2*pi)/(2*pi/nBin))+1);
    if strcmp(mode,'on')
        % 在线部署: 对偶交替探索+REINFORCE继续修正(lr取预训练末段低档)
        if stepsSinceFlip>=p.plHold, lastSgn=-lastSgn; stepsSinceFlip=0; end
        stepsSinceFlip=stepsSinceFlip+1;
        v=min(max(muB(ib)+lastSgn*sigma,p.lower+0.3),p.upper-0.3);
        c0=plant.count();
        Pm=qs(v,'pure');
        if ~isfinite(Pm), kStep=kStep-1; break; end
        sUsed=plant.count()-c0;
        for j=1:sUsed
            psiUnw=psiUnw+v/p.turnRadius*p.tEval;
        end
        if isnan(Pb), Pb=Pm; else, Pb=0.98*Pb+0.02*Pm; end
        if isnan(bBase(ib)), bBase(ib)=Pm; else, bBase(ib)=0.9*bBase(ib)+0.1*Pm; end
        r=-(Pm-bBase(ib))/max(abs(bBase(ib)),0.1);
        aDev=v-muB(ib);
        if sUsed>1
            % 瞬态不更新
        else
            lrT=0.25*p.plLr;
            K=round(p.plKern);
            for b=ib-K:ib+K
                b2=mod(b-1,nBin)+1;
                wgt=exp(-0.5*((b-ib)/max(K,0.5))^2);
                dB=lrT*wgt*r*aDev/(sigma^2);
                dB=min(max(dB,-0.05),0.05);
                muB(b2)=min(max(muB(b2)+dB,p.lower+0.3),p.upper-0.3);
                nUpdate=nUpdate+1;
            end
        end
    else
        % 离线部署: 纯贪心执行预训练策略, 零探索零学习(可复现)
        v=min(max(muB(ib),p.lower+0.3),p.upper-0.3);
        c0=plant.count();
        Pm=qs(v,'pure');
        if ~isfinite(Pm), kStep=kStep-1; break; end
        sUsed=plant.count()-c0;
        for j=1:sUsed
            psiUnw=psiUnw+v/p.turnRadius*p.tEval;
        end
    end
    muTrace(kStep)=muB(ib); sigHist(kStep)=sigma; ibHist(kStep)=ib;
end
while plant.count()<n
    plant.q(v,'hold'); plant.amendEstimate(v);
end
if strcmp(mode,'on'), m='purerl_on'; else, m='purerl_off'; end
info=struct('best',v,'bestP',NaN,'mode',m,'muB',muB,...
    'muTrace',{muTrace},'sigma',sigma,'sigma0',p.plSigma0,...
    'baselineBins',nBin,'kern',p.plKern,...
    'warmupSteps',warmupSteps,'warmConverged',converged,...
    'warmBlocks',blkN,'warmBlockP',{blkMeanP},'warmBlockDB',{blkMeanDB},...
    'muPre',{muPre},'bBasePre',{bBasePre},'nUpdate',nUpdate);
end
