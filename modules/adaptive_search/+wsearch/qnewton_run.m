function info = qnewton_run(plant, p, n)
%QNEWTON_RUN 割线牛顿寻优：宽stencil全局下降 + 小stencil牛顿精调 两相制。
% 与 ea_run(直接stencil抛光)/spsa(纯宽stencil差分)不同的模型法路线：
% ── 相位1 全局下降(宽stencil ±qnD=1.5, 同spsa口径) ──
%   探针间隔3与涟漪波长(λ1=6,λ2=2)整倍对齐→差分只余基线斜率,
%   不落入涟漪局部谷；斜率连续两次足够小→进入相位2。
% ── 相位2 局部牛顿(小stencil ±qnS=0.25) ──
%   1) 小stencil探针停在涟漪谷内(谷深A1+A2、宽约±0.7)，
%      单步搜索能耗≈0.5%(宽stencil≈4%)——能耗关键设计；
%   2) 局部等效对象≈二次：牛顿步 -g/(2b) 直达顶点；
%   3) 曲率b由割线自校正 b_sec=(ĝ_new−ĝ_old)/(2·s)(正弦风漂零均值,
%      EWMA平均后不偏), 只在步长大(信噪比高)时更新, 收敛后冻结；
%   4) 周期=qnPairs对交错探针+qnHold步hold(占空比省能耗), 步长限幅。
% ── 相位2监测: 每qnWideEvery步插一对宽探针 ──
%   宽stencil基线斜率若超阈(qnWideThr), 说明风漂/跳变已把局部谷
%   带离(或落入别谷), 用宽斜率证据重定位(跳变恢复)。
% 黑箱口径：只用 plant.q 测量(红线1)。
gE=0; bE=p.qnB0; v=p.initialSpeed;
prevGhat=NaN; prevS=0; iter=0; iterLocal=0; calm=0; phase=1;
needLocal=2*p.qnPairs+p.qnHold;               % 局部周期所需预算
while plant.count()<=n-2
    if phase==1
        % ---- 宽stencil对: 涟漪相消的基线斜率 ----
        d=randi([0 1])*2-1;
        yp=plant.q(v+p.qnD*d,'search'); plant.amendEstimate(v);
        ym=plant.q(v-p.qnD*d,'search'); plant.amendEstimate(v);
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
            yp=plant.q(v+p.qnD*d,'probe'); plant.amendEstimate(v);
            ym=plant.q(v-p.qnD*d,'probe'); plant.amendEstimate(v);
            gW=(yp-ym)/(2*p.qnD*d);
            if abs(gW)>p.qnWideThr                  % 宽斜率证据: 跳变/漂出谷
                gE=0; prevGhat=NaN; prevS=0;         % 旧盆地的局部模型作废
                phase=1; calm=0;                     % 重入全局下降相位
                continue;
            end
        end
        if plant.count()>n-2*p.qnPairs
            break;                             % 预算不足以完成本轮探针, 转末段hold
        end
        yp=zeros(1,p.qnPairs); ym=zeros(1,p.qnPairs);
        for r=1:p.qnPairs
            yp(r)=plant.q(v+p.qnS,'refine'); plant.amendEstimate(v);
            ym(r)=plant.q(v-p.qnS,'refine'); plant.amendEstimate(v);
        end
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
        plant.q(v,'hold'); plant.amendEstimate(v);
    end
end
while plant.count()<n
    plant.q(v,'hold'); plant.amendEstimate(v);
end
info=struct('best',v,'bestP',NaN,'iterations',iter,'curvEwma',bE,...
    'gradEwma',gE,'phaseReached',phase,'dutyCycle',2*p.qnPairs/(2*p.qnPairs+p.qnHold));
end
