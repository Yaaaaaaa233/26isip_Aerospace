function [pol,dump] = p3_pol_hybrid(o)
%QUAD_SIM.P3_POL_HYBRID 多臂适配 hybrid 臂(标定后在线, 1-D 平移跟踪+重括号版)。
% pol = p3_pol_hybrid(o); v = pol(info)。info=白名单面(t/v/x/Phat/Vmeas/Ehat/cmd)。
% w36.hybrid_run 的直线链移植(p3_multiarm_opt 裁决 a + 勘误登记 2):
%   Phase A 括号扫标定(p3_phase_a)
%   Phase B 冻结形状 + 1-D 平移跟踪(小漂移快路径; 对齐评估域=支撑∪顶点±1 m/s)
%          + 信赖域探针对(û* 测量锚, w36 探针信赖域同款)
%          + **重括号升级**(大阶跃主恢复, 勘误 2): 探针对斜率 |sPair|>escHard
%            (单次)或连续两对同号 |sPair|>escThr -> 从当前 v̂* 重跑括号扫
%            (reMaxPts 上限), 支撑选谷+边界顶点逻辑重定谷, s=F.vStar-v̂* 重锚。
% 测量语义 v2(勘误 2): 驻留整段 1 Hz 子对 (v实,P̂) 即样本(速度环 τ≈2.9 s,
% 3 s 驻留不到位; 加速偏差上下行自相消), 探针斜率=两驻留子对合并回归斜率。
% 平移更新接受双门: 残差 RMS<=sRmsMax(拒两支歧义错支) + |Δs|<=sMaxJump。
% 因果口径: 只读 info 面, 曲线知识来自自己标定拟合。
o = local_def(o);
A = quad_sim.p3_phase_a(o.sweep);
nW = ceil(o.win_s)+4;                 % 近窗(1 Hz 点)环形
tW = nan(1,nW); vW = nan(1,nW); PW = nan(1,nW); iW = 0;
tSec = NaN; sumSec = 0; sumSecV = 0; nSec = 0; vHold = o.sweep.vInit_mps;
bPhaseB = false; F = []; s = 0; uArg = NaN; vHat = NaN;
bEst = o.bEstMin; sPrev = NaN; vHatPrev = NaN;
tNextShift = NaN; tNextProbe = NaN;
pState = 0;                          % 0=跟踪; 1/2=探针驻留; 3=重括号
tD0 = NaN; tSub0 = NaN; vUp = NaN; vDn = NaN;
pv = zeros(1,0); pP = zeros(1,0);    % 本探针对全部子对(回归用)
uvm = NaN; upm = NaN; dvm = NaN; dpm = NaN;
prevBigSgn = NaN; A2 = []; tLastEsc = -inf;
evT = []; evK = []; evV = []; evS = [];   % 事件日志(诊断): t/类型/v/x
pol = @step;
dump = @getDump;
    function v = step(info)
        t = info.t;
        % ---- 1 Hz 近窗子对(实测地速配对, 测量语义 v2) ----
        if isnan(tSec), tSec = floor(t); end
        sumSec = sumSec + info.Phat; sumSecV = sumSecV + info.v; nSec = nSec + 1;
        if t >= tSec+1
            if nSec >= 10
                iW = iW+1; k = mod(iW-1,nW)+1;
                tW(k) = tSec; vW(k) = sumSecV/nSec; PW(k) = sumSec/nSec;
            end
            tSec = tSec+1; sumSec = 0; sumSecV = 0; nSec = 0;
        end
        if ~bPhaseB
            v = A.step(info); vHold = v;
            if A.done()
                S = A.samples();
                F = quad_sim.p3_fit_valley(S.v,S.P,o.sweep);
                bEst = max(F.curv,o.bEstMin);
                s = 0; uArg = F.vStar; vHat = local_clip(F.vStar,o);
                tNextShift = t + o.hyWindEvery_s; tNextProbe = t + o.ucProbeEvery_s;
                bPhaseB = true;
                evT(end+1) = t; evK(end+1) = 1; evV(end+1) = vHat; evS(end+1) = s;
            end
            return;
        end
        % ---- 重括号(勘误 2: 大阶跃主恢复) ----
        if pState == 3
            v = A2.step(info); vHold = v;
            if A2.done()
                S2 = A2.samples();
                F2 = quad_sim.p3_fit_valley(S2.v,S2.P,o.sweep);
                vHat = local_clip(F2.vStar,o);
                s = F.vStar - vHat;          % 平移参考重锚
                uArg = vHat;
                bEst = max(F2.curv,o.bEstMin);
                sPrev = NaN; prevBigSgn = NaN;
                tNextShift = t + o.hyWindEvery_s; tNextProbe = t + o.ucProbeEvery_s;
                pState = 0;
                evT(end+1) = t; evK(end+1) = 5; evV(end+1) = vHat; evS(end+1) = s;
            end
            return;
        end
        % ---- 平移跟踪(每 hyWindEvery_s; 小漂移快路径) ----
        if t >= tNextShift
            tNextShift = t + o.hyWindEvery_s;
            [sHat,nIn,sRms] = local_shift(tW,vW,PW,F,o,s);
            % 接受双门(勘误 2): 残差 RMS<=sRmsMax(拒两支歧义错支, 错支残差>100 W)
            % + 连续性 |Δs|<=sMaxJump(大跳变是重括号的职责, 平移快路径只管小漂移)。
            if nIn >= max(3,ceil(0.5*nnz(~isnan(tW)))) ...
                    && isfinite(sRms) && sRms <= o.sRmsMax ...
                    && abs(sHat-s) <= o.sMaxJump
                s = s + o.sDamp*(sHat-s);
            end
            uArg = F.vStar - s;                  % 平移预测(不限速)
            vHat = min(max(vHat,uArg-o.trustR_mps),uArg+o.trustR_mps);
            vHat = local_clip(vHat,o);
            evT(end+1) = t; evK(end+1) = 2; evV(end+1) = vHat; evS(end+1) = s;
        end
        % ---- 探针对(每 ucProbeEvery_s) + 信赖域锚定 + 升级判据 ----
        if pState == 0
            v = local_clip(vHat,o);
            if t >= tNextProbe
                tNextProbe = t + o.ucProbeEvery_s;
                vUp = local_clip(vHat+o.ucProbeDelta_mps,o);
                v = vUp; pState = 1; tD0 = t; tSub0 = t;
                pv = zeros(1,0); pP = zeros(1,0);
            end
        else
            if pState == 1, v = vUp; else, v = local_clip(vHat-o.ucProbeDelta_mps,o); end
            % 子对(实测地速配对, 测量语义 v2)
            if info.t >= tD0 + 0.5
                pv(end+1) = info.v; pP(end+1) = info.Phat;
            end
            if info.t >= tD0 + o.dwell_s
                if pState == 1
                    uvm = mean(pv); upm = mean(pP);
                    vDn = local_clip(vHat-o.ucProbeDelta_mps,o);
                    pState = 2; tD0 = t; tSub0 = t;
                    v = vDn;
                else
                    dvm = mean(pv); dpm = mean(pP); pState = 0;
                    evT(end+1) = t; evK(end+1) = 7; evV(end+1) = uvm; evS(end+1) = upm;
                    evT(end+1) = t; evK(end+1) = 8; evV(end+1) = dvm; evS(end+1) = dpm;
                    sPair = local_slope(pv,pP);   % 两驻留子对合并回归斜率
                    if isfinite(sPair)
                        evT(end+1) = t; evK(end+1) = 3; evV(end+1) = vHat; evS(end+1) = sPair;
                        % 升级判据(勘误 2 终版): 方向抑制——斜率指向域外时
                        % 谷不可达, 升级无意义; 重括号后 escCooldown_s 冷却防循环。
                        canEsc = ~((sPair > 0 && vHat <= o.sweep.vMin_mps+0.5) || ...
                            (sPair < 0 && vHat >= o.sweep.vMax_mps-0.5));
                        esc = canEsc && (t-tLastEsc) > o.escCooldown_s && ...
                            (abs(sPair) > o.escHard || ...
                            (~isnan(prevBigSgn) && sign(sPair) == prevBigSgn ...
                             && abs(sPair) > o.escThr));
                        if abs(sPair) > o.escThr
                            prevBigSgn = sign(sPair);
                        else
                            prevBigSgn = NaN;
                        end
                        if esc
                            % 大阶跃/持续外向斜率: 重括号重定谷(实测样本, 无外推)
                            A2 = quad_sim.p3_phase_a(local_reopt(o,vHat));
                            pState = 3; tLastEsc = t;
                            evT(end+1) = t; evK(end+1) = 4; evV(end+1) = vHat; evS(end+1) = s;
                        elseif abs(sPair) > o.ucThr
                            du = -o.ucGain*sPair/max(bEst,o.bEstMin);
                            du = min(max(du,-o.maxStepProbe_mps),o.maxStepProbe_mps);
                            vHatPrev = vHat;
                            vHat = min(max(vHat+du,uArg-o.trustR_mps),uArg+o.trustR_mps);
                            vHat = local_clip(vHat,o);
                            evT(end+1) = t; evK(end+1) = 6; evV(end+1) = vHat; evS(end+1) = du;
                            if ~isnan(sPrev) && abs(vHat-vHatPrev) > 0.05
                                bRaw = abs(sPair-sPrev)/abs(vHat-vHatPrev);
                                bEst = min(o.bEstMax,max(o.bEstMin, ...
                                    0.8*bEst+0.2*min(bRaw,o.bEstMax)));
                            end
                            sPrev = sPair;
                        else
                            sPrev = NaN;
                        end
                    end
                end
            end
        end
        vHold = v;
    end
    function S = getDump()
        S = struct('vHat',vHat,'s',s,'uArg',uArg,'bEst',bEst,'pState',pState, ...
            'evT',evT,'evK',evK,'evV',evV,'evS',evS);
    end
end
function o = local_def(o)
d = struct('dwell_s',3,'tail_s',2,'hyWindEvery_s',10,'win_s',30, ...
    'sRange',[-8 8],'sDamp',0.8,'ucProbeEvery_s',20,'ucProbeDelta_mps',1.5, ...
    'ucGain',0.30,'ucThr',1.0,'trustR_mps',1.5,'maxStepProbe_mps',0.4, ...
    'bEstMin',0.5,'bEstMax',50,'escThr',6.0,'escHard',10.0,'reMaxPts',9, ...
    'escCooldown_s',40,'sRmsMax',20,'sMaxJump',4,'sweep',[]);
if ~isempty(o)
    fn = fieldnames(o);
    for k = 1:numel(fn), d.(fn{k}) = o.(fn{k}); end
end
if isempty(d.sweep)
    d.sweep = struct('step_mps',1,'dwell_s',d.dwell_s,'tail_s',d.tail_s, ...
        'maxPts',11,'curvMin_pp1',0.5,'vMin_mps',4,'vMax_mps',14,'vInit_mps',8);
end
o = d;
end
function o2 = local_reopt(o,vInit)
% 重括号配置: 同 Phase A 参数, 起点=当前 v̂*, maxPts=reMaxPts
o2 = o.sweep;
o2.vInit_mps = min(max(vInit,o.sweep.vMin_mps),o.sweep.vMax_mps);
o2.maxPts = o.reMaxPts;
end
function v = local_clip(v,o)
v = min(max(v,o.sweep.vMin_mps),o.sweep.vMax_mps);
end
function s = local_slope(vv,pp)
% 子对合并回归斜率(实测地速配对; 上下行加速偏差自相消)
if numel(vv) < 3, s = NaN; return; end
vm = mean(vv); pm = mean(pp);
den = sum((vv-vm).^2);
if den < 0.05, s = NaN; return; end      % 速度展宽不足, 斜率不可辨识
s = sum((vv-vm).*(pp-pm))/den;
end
function [sHat,nIn,sRms] = local_shift(tW,vW,PW,F,o,sNow)
% 1-D 平移对齐: ŝ=argmin mean (P-g0(v+s))^2。评估域=支撑∪顶点±1 m/s
% (勘误 2: 该域四次式外推误差 <=31 W; 更远处 >75 W 不可信, 不进拟合)
ok = ~isnan(tW) & ~isnan(PW);
vv = vW(ok); pp = PW(ok); nIn = 0; sHat = sNow; sRms = NaN;
if numel(vv) < 3, return; end
evLo = min(F.vLo,F.vStar)-1; evHi = max(F.vHi,F.vStar)+1;
gs = o.sRange(1):0.25:o.sRange(2);
mse = inf(size(gs)); cnt = zeros(size(gs));
for i = 1:numel(gs)
    x = vv+gs(i);
    mk = x >= evLo-1e-9 & x <= evHi+1e-9;
    cnt(i) = nnz(mk);
    if cnt(i) >= max(3,ceil(0.5*numel(vv)))
        e = pp(mk)-local_poly(F.coefs,x(mk));
        mse(i) = mean(e.^2);
    end
end
[best,im] = min(mse);
if ~isfinite(best), return; end
nIn = cnt(im); sRms = sqrt(best);
sHat = gs(im);
if im > 1 && im < numel(gs)          % 抛物细化
    y1 = mse(im-1); y2 = mse(im); y3 = mse(im+1);
    den = y1-2*y2+y3;
    if isfinite(y1) && isfinite(y3) && isfinite(den) && den > 1e-12
        sHat = gs(im)+0.5*(gs(2)-gs(1))*(y1-y3)/den;
    end
end
end
function y = local_poly(c,x)
xn = (x-9)/5;
y = c(1)+c(2)*xn+c(3)*xn.^2+c(4)*xn.^3+c(5)*xn.^4;
end
