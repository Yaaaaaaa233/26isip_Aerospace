function info = qnewton_run(plant, p, n)
%QNEWTON_RUN 割线牛顿寻优(两相制, 算法逻辑原样移植任务6, 查询经指令就位包装器)。
% ── 相位1 全局下降(宽stencil ±qnD=1.5): 探针间隔3与涟漪波长(λ1=6,λ2=2)
%    整倍对齐→差分只余基线斜率; 斜率连续两次足够小→进入相位2。
% ── 相位2 局部牛顿(小stencil ±qnS=0.25): 小stencil就位时间短(Δv小)、
%    驻点能耗低; 曲率由割线自校正; 周期=qnPairs对+qnHold步hold。
% ── 相位2监测: 每qnWideEvery步插一对宽探针, 宽斜率超阈→重入相位1。
% 任务7差异: 全部查询经 w8.settled_q——宽探针就位需 τ+3/amax≈1.8s(2步),
% 小探针 τ+0.5/2≈0.55s(1步), 小stencil在实际动力学下依然显著更省。
qs=w8.settled_q(plant,p,n);
gE=0; bE=p.qnB0; v=p.initialSpeed;
prevGhat=NaN; prevS=0; iter=0; iterLocal=0; calm=0; phase=1;
needLocal=2*p.qnPairs+p.qnHold;               % 局部周期所需预算
while plant.count()<=n-2
    if phase==1
        % ---- 宽stencil对: 涟漪相消的基线斜率 ----
        d=randi([0 1])*2-1;
        yp=qs(v+p.qnD*d,'search');
        if ~isfinite(yp), break; end
        ym=qs(v-p.qnD*d,'search');
        if ~isfinite(ym), break; end
        ghat=(yp-ym)/(2*p.qnD*d);
        gE=0.25*ghat+0.75*gE;
        step=max(-0.8,min(0.8,-p.qnWideGain*gE));
        v=min(max(v+step,p.lower+p.qnD),p.upper-p.qnD);
        if abs(gE)<p.qnCalmThr, calm=calm+1; else, calm=0; end
        if calm>=2, phase=2; end                      % 回局部牛顿相位
        holdUntil=min(n,plant.count()+1);          % 相位1每2步一对, 无hold
    else
        % ---- 局部牛顿周期: qnPairs对小对+qnHold步hold ----
        if plant.count()<=n-(needLocal+2) && ...
                mod(iterLocal,p.qnWideEvery)==0 && iterLocal>0
            d=randi([0 1])*2-1;
            yp=qs(v+p.qnD*d,'probe');
            if isfinite(yp)
                ym=qs(v-p.qnD*d,'probe');
            end
            if isfinite(yp) && isfinite(ym)
                gW=(yp-ym)/(2*p.qnD*d);
                if abs(gW)>p.qnWideThr              % 宽斜率证据: 跳变/漂出谷
                    gE=0; prevGhat=NaN; prevS=0;     % 旧盆地的局部模型作废
                    phase=1; calm=0;                 % 重入全局下降相位
                    continue;
                end
            else
                break;
            end
        end
        if plant.count()>n-2*p.qnPairs
            break;                             % 预算不足以完成本轮探针, 转末段hold
        end
        yp=zeros(1,p.qnPairs); ym=zeros(1,p.qnPairs);
        ok=true;
        for r=1:p.qnPairs
            yp(r)=qs(v+p.qnS,'refine');
            ym(r)=qs(v-p.qnS,'refine');
            if ~isfinite(yp(r)) || ~isfinite(ym(r)), ok=false; break; end
        end
        if ~ok, break; end
        ghat=(mean(yp)-mean(ym))/(2*p.qnS);
        gE=p.qnEwmaG*ghat+(1-p.qnEwmaG)*gE;
        % 割线曲率自校正: 上一步位移引起的原始梯度变化 ≈ 2b·prevS
        if abs(prevS)>=p.qnSecMin && ~isnan(prevGhat)
            bSec=(ghat-prevGhat)/(2*prevS);
            if isfinite(bSec) && bSec>p.qnBmin && bSec<p.qnBmax
                bE=p.qnEwmaB*bSec+(1-p.qnEwmaB)*bE;
            end
        end
        bE=min(max(bE,p.qnBmin),p.qnBmax);
        newton=-gE/(2*bE);
        step=max(-p.qnStepMax,min(p.qnStepMax,newton));
        v=min(max(v+step,p.lower+p.qnS),p.upper-p.qnS);
        prevGhat=ghat; prevS=step;
        iterLocal=iterLocal+1;
        holdUntil=min(n,plant.count()+p.qnHold);
    end
    iter=iter+1;
    while plant.count()<holdUntil                    % 间歇hold(定界防滚动)
        qs(v,'hold');
    end
end
while plant.count()<n
    plant.q(v,'hold'); plant.amendEstimate(v);
end
info=struct('best',v,'bestP',NaN,'iterations',iter,'curvEwma',bE,...
    'gradEwma',gE,'phaseReached',phase,'dutyCycle',2*p.qnPairs/(2*p.qnPairs+p.qnHold));
end
