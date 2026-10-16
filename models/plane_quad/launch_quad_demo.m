function fig = launch_quad_demo(visible)
%LAUNCH_QUAD_DEMO 四旋翼在线速度寻优演示面板(演示层, 2026-10-15 v4)。
% v4: 布局与运行模型整体回贴老 UI(modules/platform_link/launch_3_6_demo.m,
%   只读参考), 与 v1-v3 的差异收敛为"内容换四旋翼语义, 骨架不动":
%   - 骨架同构: 头部大标题 / 模块切换按钮(控制台|飞机模型|环境模型) / 滚动表单 /
%     操作钮三行(播放暂停重置末帧 + 导出PNG导出GIF + 载入证据清空日志) / 6 行红框
%     评价卡 / 读出单行 / 日志框 / 右侧 3x2(4 轴 + 飞机模型双表盘卡 + 环境模型卡) /
%     resizeLayout 动态配平(SizeChangedFcn 同款)。
%   - 绘图同构(流畅性根因): setupPanels 一次建好全部 line/patch/text 图元,
%     每帧只 set XData/YData + drawnow limitrate, 不 cla 不重建 legend
%     (v3 每拍全量重画 6 轴, 面板层 300 步 2.67s vs 物理 0.38s)。
% 黑箱红线: 面板仅演示, 不作可引用数据源(数字口径以 docs/evidence 证据 CSV 为准);
%   演示链 = air_quad_tick(P4 薄包装 -> quad_sim.ctrl/step 权威链)逐步推进,
%   无 P2 现实性退化(时延/噪声/量化见 P2 验收证据, 面板不复现)。
% 臂 = +quad_sim/p3_arm 策略句柄(信息面=白名单 t/v/x/Phat/Vmeas/Ehat/cmd, G-P2);
%   openloop 固定 8 / sweepcal 在线三点扫 / known = R7 定律 oracle(v*=6-w, 显式)。
% P(v) 谷图 = E1 真值扫描证据加载(docs/evidence/quad_migration/quad_p3/
%   quad_p3_sweep_vi.csv), 不重算; 谷随风移动 = R7 定律(命令谷 = 空速谷 6 - w)。
% 估计档 est_model: 'vi'=V·I 测量主档(R8③) / 'l1' / 'l0' 降级档。
% 用法: launch_quad_demo                    % 交互
%       fig = launch_quad_demo('off');      % 无窗(批处理/冒烟)
%       S = getappdata(fig,'qdemo'); S.step(500); S.state   % 批处理驱动
if nargin < 1, visible = 'on'; end
root = fileparts(mfilename('fullpath'));
repo = fileparts(fileparts(root));
addpath(root); addpath(fullfile(repo,'models','px4_x8'));
% ---- 常量(P3 窗口口径) ----
dt = 0.01; T_s = 240; phWind = [4 0 -4]; phBnd = [0 80 160 240];
vMin = 4; vMax = 14; uStar = 6;
whitelist = {'t','v','x','Phat','Vmeas','Ehat','cmd'};
% ---- P(v) 证据曲线(不重算) ----
curveCsv = fullfile(repo,'docs','evidence','quad_migration','quad_p3', ...
    'quad_p3_sweep_vi.csv');
Pev = []; vGrid = 4:14;
if isfile(curveCsv)
    Tw = readtable(curveCsv);
    vGrid = unique(Tw.v_mps)';
    Pev = zeros(numel(phWind),numel(vGrid));
    for p = 1:numel(phWind)
        rows = Tw.phase == p;
        Pev(p,:) = Tw.P_true_W(rows)';
    end
end
% ---- 状态(可变状态一律具名嵌套 getter 暴露, 勿匿名捕获) ----
st = struct('t',0,'k',0,'vCmd',8,'Ehat',0,'Ewh',0,'needReset',true, ...
    'phase',1,'running',false,'maxAcc',0);
nMax = ceil(T_s/dt); down = 5; nD = ceil(nMax/down)+1;
hist = struct('t',zeros(1,nD),'v',zeros(1,nD),'vc',zeros(1,nD), ...
    'P',zeros(1,nD),'Ph',zeros(1,nD),'E',zeros(1,nD),'Eh',zeros(1,nD),'n',0);
% ---- MOP/MOE 评价行(1 Hz 行口径, 逐式照搬 w36.mop_moe: tEval=1 s / tailSteps=60 / eps=0.4) ----
% 列映射(老 UI log -> 演示行): estimate->v_cmd(臂的谷信念) optimumTrue->命令谷 v*(t)
%   speed/speedCmd->v实/v_cmd  powerTrue->行区间均 V·I  minPowerTrue->known 参照趟同行均值
%   hold 行 -> 行末 v_cmd 未变; 峰值加速度 -> max|dv实/dt|(逐物理步)
moeEps = 0.4; moeTail = 60; nRow = round(1/dt);
mop = struct('n',0,'t',zeros(1,ceil(T_s)+2),'vc',zeros(1,ceil(T_s)+2), ...
    'v',zeros(1,ceil(T_s)+2),'P',zeros(1,ceil(T_s)+2), ...
    'lag',zeros(1,ceil(T_s)+2),'inband',false(1,ceil(T_s)+2), ...
    'chg',false(1,ceil(T_s)+2));
rowPsum = 0; rowLagSum = 0; rowN = 0; prevV4 = NaN;
pol = []; refs = [];   % refs=MOE 参照(known/openloop 同配置趟, ensureRefs 缓存)
estTier = 'vi'; windKind = 'phase'; rate = 2; armName = 'sweepcal';
showEv = true; showTruth = true; showBand = true; curView = 'console';
cfg = quad_sim.config(quad_sim.baseline('b40'),'est_model',estTier);
assignin('base','air_quad_config',cfg);
% ================= UI 骨架(老 3.6 面板逐项同构) =================
fig = uifigure('Name','四旋翼在线速度寻优演示(P4 薄包装链, 演示层)', ...
    'Position',[40 30 1500 960],'Color',[.96 .97 .98],'Visible',visible, ...
    'AutoResizeChildren','off');
outer = uigridlayout(fig,[3 2]); outer.RowHeight = {44,'1x',28};
outer.ColumnWidth = {330,'1x'}; outer.Padding = [12 10 12 10]; outer.RowSpacing = 10;
header = uilabel(outer,'Text', ...
    '四旋翼演示 | P̂=V·I 测量主档(R8③) × 谷=气动物理涌现(E1) × 命令谷=空速谷6∓风(R7) × 臂=p3_arm(G-P2 白名单) × [演示口径, 非数据源]', ...
    'FontName','Microsoft YaHei','FontSize',15,'FontWeight','bold');
put(header,1,[1 2]);
leftLayout = uigridlayout(outer,[6 1]); put(leftLayout,2,1);
leftLayout.RowHeight = {38,'1x',150,175,30,'1x'};
leftLayout.Padding = [0 0 0 0]; leftLayout.RowSpacing = 8;
left = leftLayout;
% --- 模块切换按钮(左上三个, 老 UI 同构) ---
mods = uigridlayout(left,[1 3]); put(mods,1,1); mods.Padding = [0 0 8 0];
btnConsole = uibutton(mods,'Text','控制台(主)','FontWeight','bold'); put(btnConsole,1,1);
btnAir = uibutton(mods,'Text','飞机模型'); put(btnAir,1,2);
btnEnv = uibutton(mods,'Text','环境模型'); put(btnEnv,1,3);
% --- 参数表单(滚动, 老 UI 同构) ---
form = uipanel(left,'BorderType','none'); put(form,2,1);
g = uigridlayout(form,[9 2]); g.ColumnWidth = {150,'1x'};
g.RowHeight = [repmat({30},1,5),{26,26,26},30];
g.Padding = [0 0 8 0]; g.RowSpacing = 7; g.Scrollable = 'on';
hArm = choice(g,'控制策略',1,{'sweepcal 在线寻优','openloop 恒速 8','known R7 oracle', ...
    'rl 三段REINFORCE','hybrid 标定后在线','purerl 纯在线RL'}, ...
    {'sweepcal','openloop','known','rl','hybrid','purerl'},'sweepcal');
hArm.ValueChangedFcn = @onArm;
hEst = choice(g,'估计档',2,{'vi (V·I 测量主档)','l1 (空速修正降级)','l0 (粗估降级)'}, ...
    {'vi','l1','l0'},'vi');
hEst.ValueChangedFcn = @onEst;
hWind = choice(g,'风剧本',3,{'三段相位 4/0/-4 (P3 口径)','静风 0','恒风 +2.5'}, ...
    {'phase','calm','gust'},'phase');
hWind.ValueChangedFcn = @onWind;
hTw = number(g,'任务窗 / s',4,240,[30 600]);
hTw.ValueChangedFcn = @onChanged;
hV0 = number(g,'初始速度 v_cmd / m/s',5,8,[4 14]);
hV0.ValueChangedFcn = @onChanged;
cbEv = uicheckbox(g,'Text','显示 P(v) 证据曲线(E1, 不重算)','Value',true);
put(cbEv,6,[1 2]); cbEv.ValueChangedFcn = @(~,~) toggleEv();
cbTruth = uicheckbox(g,'Text','显示真值线(P真/E真)','Value',true);
put(cbTruth,7,[1 2]); cbTruth.ValueChangedFcn = @(~,~) toggleTruth();
cbBand = uicheckbox(g,'Text','显示相位风色带','Value',true);
put(cbBand,8,[1 2]); cbBand.ValueChangedFcn = @(~,~) toggleBand();
speedLabel = uilabel(g,'Text','播放速度: 2.00x','FontName','Microsoft YaHei','FontSize',11);
put(speedLabel,9,1);
speedSlider = uislider(g,'Limits',[0.5 8],'Value',2,'MajorTicks',[.5 1 2 4 8], ...
    'MajorTickLabels',{'0.5x','1x','2x','4x','8x'}); put(speedSlider,9,2);
speedSlider.ValueChangedFcn = @(~,ev) setSpeed(ev.Value);
% --- 操作按钮(三行, 老 UI 同构) ---
actions = uigridlayout(left,[3 4]); put(actions,3,1); actions.Padding = [0 0 8 0];
actions.RowHeight = {34,34,34}; actions.RowSpacing = 7;
play = uibutton(actions,'Text','播放'); put(play,1,1);
pauseBtn = uibutton(actions,'Text','暂停'); put(pauseBtn,1,2);
reset = uibutton(actions,'Text','重置'); put(reset,1,3);
finish = uibutton(actions,'Text','末帧'); put(finish,1,4);
exportPng = uibutton(actions,'Text','导出PNG'); put(exportPng,2,1);
exportGif = uibutton(actions,'Text','导出GIF动画'); put(exportGif,2,[2 4]);
loadEvBtn = uibutton(actions,'Text','载入P3证据'); put(loadEvBtn,3,1);
clearLogBtn = uibutton(actions,'Text','清空日志'); put(clearLogBtn,3,[2 4]);
% --- MOP/MOE 评价结果卡片(6 行, 老 3.6 UI report() 口径/格式逐字同构) ---
resultCard = uipanel(left,'Title','★ MOP/MOE 评价结果(任务窗终点)','FontName','Microsoft YaHei', ...
    'FontSize',11,'ForegroundColor',[.62 .08 .08],'HighlightColor',[.62 .08 .08]);
put(resultCard,4,1);
rg = uigridlayout(resultCard,[6 2]); rg.RowHeight = {30,24,24,24,24,24};
rg.ColumnWidth = {'1x','1x'}; rg.Padding = [8 2 8 2]; rg.RowSpacing = 1;
mkTag = @(txt) uilabel(rg,'Text',txt,'FontName','Microsoft YaHei','FontSize',9, ...
    'FontColor',[.25 .25 .25]);
mkVal = @(sz) uilabel(rg,'Text','—','FontName','Microsoft YaHei','FontSize',sz, ...
    'FontWeight','bold','HorizontalAlignment','right');
labOverallT = mkTag('MOE 综合效能 overall(2026-09-04口径: =续航能耗Emin/Eactual)');
put(labOverallT,1,1);
labOverall = mkVal(15); put(labOverall,1,2); labOverall.FontColor = [.0 .45 .2];
labEnergyT = mkTag('续航能效 MOE_energy / 能耗超额'); put(labEnergyT,2,1);
labEnergy = mkVal(11); put(labEnergy,2,2);
labLiftT = mkTag('vs 开环基线: ΔMOE / 能耗相对变化'); put(labLiftT,3,1);
labLift = mkVal(11); put(labLift,3,2);
labInstT = mkTag('瞬时能效 instant / 指令跟踪滞后'); put(labInstT,4,1);
labInst = mkVal(11); put(labInst,4,2);
labSetT = mkTag('入带步数 / 任务可用率'); put(labSetT,5,1);
labSet = mkVal(11); put(labSet,5,2);
labSeaT = mkTag('搜索步数(含就位) / 稳态波动σ'); put(labSeaT,6,1);
labSea = mkVal(11); put(labSea,6,2);
readout = uilabel(left,'Text','','WordWrap','on','FontName','Microsoft YaHei');
put(readout,5,1);
logBox = uitextarea(left,'Editable','off','FontName','Microsoft YaHei','FontSize',9);
put(logBox,6,1);
% ---- 右侧绘图区(老 UI 3x2 同构: 4 轴 + 飞机模型卡 + 环境模型卡) ----
plots = uigridlayout(outer,[3 2]); put(plots,2,2); plots.Padding = [0 0 0 0];
plots.RowHeight = {'1x','1x',250}; plots.ColumnWidth = {'1x','1x'};
plots.RowSpacing = 14; plots.ColumnSpacing = 18;
ax = gobjects(1,4); for k = 1:4, ax(k) = uiaxes(plots); end
put(ax(1),1,1); put(ax(2),1,2); put(ax(3),2,1); put(ax(4),2,2);
for k = 1:4
    disableDefaultInteractivity(ax(k)); ax(k).Toolbar.Visible = 'off';
end
% 飞机模型卡(双表盘, 老 UI 同构)
airPanel = uipanel(plots,'Title','飞机模型：速度+功率双表盘(黑箱仪表)', ...
    'FontName','Microsoft YaHei','ForegroundColor',[.15 .3 .6], ...
    'HighlightColor',[.15 .3 .6]);
airPanel.Layout.Row = 3; airPanel.Layout.Column = 1;
ag = uigridlayout(airPanel,[5 2]); ag.RowHeight = {150,16,16,16,34};
ag.ColumnWidth = {'1x','1x'}; ag.Padding = [6 6 6 4]; ag.RowSpacing = 4;
gSpeed = uigauge(ag,'Limits',[0 16]); put(gSpeed,1,1);
labSp = uilabel(ag,'Text','地速表 / m·s⁻¹','FontName','Microsoft YaHei','FontSize',9, ...
    'HorizontalAlignment','center'); put(labSp,2,1);
gPower = uigauge(ag,'Limits',[400 1400]); put(gPower,1,2);
labPw = uilabel(ag,'Text','功率表 P̂ / W','FontName','Microsoft YaHei','FontSize',9, ...
    'HorizontalAlignment','center'); put(labPw,2,2);
labVI = uilabel(ag,'Text','母线: —','FontName','Microsoft YaHei','FontSize',10, ...
    'HorizontalAlignment','center'); put(labVI,3,1);
labThG = uilabel(ag,'Text','油门组: —','FontName','Microsoft YaHei','FontSize',10, ...
    'HorizontalAlignment','center'); put(labThG,3,2);
labMetrics = uilabel(ag,'Text','','FontName','Microsoft YaHei','FontSize',10, ...
    'HorizontalAlignment','center'); put(labMetrics,4,[1 2]);
btnAirSize = uibutton(ag,'Text','放大 ⤢'); put(btnAirSize,5,[1 2]);
btnAirSize.ButtonPushedFcn = @(~,~) toggleSize('air');
% 环境模型卡(风速-相位 + 风矢量, 老 UI 同构)
envPanel = uipanel(plots,'Title','环境模型：相位风剧本 × 风矢量(绿=w_x, 紫=命令谷)', ...
    'ForegroundColor',[.1 .45 .25],'HighlightColor',[.1 .45 .25]);
envPanel.Layout.Row = 3; envPanel.Layout.Column = 2;
eg = uigridlayout(envPanel,[2 2]); eg.RowHeight = {'1x',28};
eg.ColumnWidth = {'1x','1x'}; eg.Padding = [4 4 4 2]; eg.RowSpacing = 2;
eg.ColumnSpacing = 8;
axEnv = uiaxes(eg); put(axEnv,1,1); disableDefaultInteractivity(axEnv);
axEnv.Toolbar.Visible = 'off';
title(axEnv,'风速-相位(三段剧本)','FontSize',8);
axWind = uiaxes(eg); put(axWind,1,2); disableDefaultInteractivity(axWind);
axWind.Toolbar.Visible = 'off';
title(axWind,'风矢量 + 工作点','FontSize',8);
btnEnvSize = uibutton(eg,'Text','放大 ⤢'); put(btnEnvSize,2,[1 2]);
btnEnvSize.ButtonPushedFcn = @(~,~) toggleSize('env');
status = uilabel(outer,'Text','就绪','FontName','Microsoft YaHei'); put(status,3,2);
clock = timer('ExecutionMode','fixedSpacing','Period',.15,'BusyMode','drop', ...
    'TimerFcn',@tick);
% ---- 图元一次建好(setupPanels 同构; 每帧只推 XData/YData) ----
h = struct();
setupPanels();
S = struct('step',@stepSim,'state',@getState,'hist',@getHist,'policy',@getPol, ...
    'whitelist',{whitelist},'frame',@frameNow,'autostart',@onRun, ...
    'reset',@doReset,'refs',@getRefs,'finish',@doFinish);
setappdata(fig,'qdemo',S);
play.ButtonPushedFcn = @onRun; pauseBtn.ButtonPushedFcn = @onPause;
reset.ButtonPushedFcn = @onReset; finish.ButtonPushedFcn = @onFinish;
exportPng.ButtonPushedFcn = @exportCurrent; exportGif.ButtonPushedFcn = @exportGifCurrent;
loadEvBtn.ButtonPushedFcn = @loadEvidence; clearLogBtn.ButtonPushedFcn = @clearLog;
btnConsole.ButtonPushedFcn = @(~,~) setView('console');
btnAir.ButtonPushedFcn = @(~,~) setView('air');
btnEnv.ButtonPushedFcn = @(~,~) setView('env');
fig.CloseRequestFcn = @onClose; fig.SizeChangedFcn = @resizeLayout;
resizeLayout(); highlightButtons();
logMsg('四旋翼在线速度寻优演示就绪 | 演示链=air_quad_tick(P4 薄包装→quad_sim 权威链)逐步推进 | 演示口径, 非可引用数据源');
logMsg('读法: P(v) 三相位证据曲线(不重算)谷随风移动=命令谷 6∓w(R7); 时间线左轴 v_cmd/v实、右轴 P̂/P真; 能量累计同窗口径');
logMsg('估计档 vi=V·I 测量主档(R8③, 无 L0 结构偏差), l1/l0 为降级档; 黑箱红线: 面板数字不作验收证据');
updateReadout();

% ================= 嵌套函数 =================
    function s = getState(), s = st; end
    function hh = getHist(), hh = hist; end
    function p = getPol(), p = pol; end
    function r = getRefs(), r = refs; end
    function doReset(varargin), onReset([],[]); end
    function doFinish(varargin), onFinish([],[]); end
    function n = ticksPerFire()
        n = max(1,round(rate*0.15/dt));
    end
    function setSpeed(val)
        rate = val;
        speedLabel.Text = sprintf('播放速度: %.2fx',val);
        % 运行中 timer 不能直接改 Period(老面板教训): 先 stop 再改再 start
        if strcmp(clock.Running,'on'), stop(clock); clock.Period = .15; start(clock); end
    end
    function w = windAt(t)
        switch windKind
            case 'phase'
                p = find(t < phBnd(2:end),1,'first');
                if isempty(p), p = numel(phWind); end
                w = [phWind(p); 0; 0];
            case 'calm'
                w = [0; 0; 0];
            otherwise
                w = [2.5; 0; 0];
        end
    end
    function p = phaseAt(t)
        p = find(t < phBnd(2:end),1,'first');
        if isempty(p), p = numel(phWind); end
    end
    function buildPolicy()
        switch armName
            case 'openloop'
                pol = quad_sim.p3_arm('openloop',8);
            case 'known'
                switch windKind
                    case 'phase', ws = phWind; bs = phBnd;
                    case 'calm',  ws = 0;      bs = [0 T_s];
                    otherwise,    ws = 2.5;    bs = [0 T_s];
                end
                vs = min(vMax,max(vMin,uStar-ws));
                pol = quad_sim.p3_arm('known',struct('bounds_s',bs,'vStar',vs));
            case {'rl','hybrid','purerl'}
                po = quad_sim.p3_multiarm_opt();
                switch armName
                    case 'rl',     pol = quad_sim.p3_arm('rl',po.rl);
                    case 'hybrid', pol = quad_sim.p3_arm('hybrid',po.hybrid);
                    otherwise,     pol = quad_sim.p3_arm('purerl',po.purerl);
                end
            otherwise
                po = quad_sim.p3_opt();
                pol = quad_sim.p3_arm('sweepcal',po.arms.sweepcal);
        end
    end
    function stepSim(n)
        if isempty(pol), buildPolicy(); end
        for i = 1:n
            if st.t >= T_s
                stopRun();
                redraw();
                return;
            end
            w = windAt(st.t);
            rst = 0;
            if st.needReset, rst = 1; st.needReset = false; end
            % 风语义取负: 面板/P3 口径 +w=头风(P(v,w)=P0(v+w), E1 证据逐点同),
            %   wind_ned 轴向 +w=顺风 -> 植物输入须取负, 否则谷律 6∓w 与证据反向
            y = air_quad_tick([st.vCmd; -w; rst]);
            info = struct('t',st.t,'v',y(4),'x',y(7),'Phat',y(1), ...
                'Vmeas',y(2),'Ehat',st.Ehat,'cmd',st.vCmd);
            assert(isequal(sort(fieldnames(info))',sort(whitelist)), ...
                'quad:DemoCausality','info face has non-whitelist fields.');
            st.k = st.k + 1;
            st.Ehat = st.Ehat + y(1)*dt/3600;
            st.Ewh = st.Ewh + y(2)*y(3)*dt/3600;
            st.phase = phaseAt(st.t);
            % MOP/MOE 评价行累计(1 Hz 行落账, mop_moe 同式)
            rowPsum = rowPsum + y(2)*y(3);
            rowLagSum = rowLagSum + abs(y(4)-st.vCmd);
            rowN = rowN + 1;
            if isfinite(prevV4)
                st.maxAcc = max(st.maxAcc,abs(y(4)-prevV4)/dt);
            end
            prevV4 = y(4);
            if rowN >= nRow
                mop.n = mop.n + 1; ir = mop.n;
                vStarNow = min(vMax,max(vMin,uStar-w(1)));
                mop.t(ir) = st.t + dt; mop.vc(ir) = st.vCmd; mop.v(ir) = y(4);
                mop.P(ir) = rowPsum/rowN; mop.lag(ir) = rowLagSum/rowN;
                mop.inband(ir) = abs(st.vCmd-vStarNow) <= moeEps;
                mop.chg(ir) = (ir == 1) || abs(st.vCmd-mop.vc(ir-1)) > 1e-9;
                rowPsum = 0; rowLagSum = 0; rowN = 0;
            end
            if mod(st.k-1,down) == 0 && hist.n < nD
                hist.n = hist.n + 1;
                hist.t(hist.n) = st.t; hist.v(hist.n) = y(4);
                hist.vc(hist.n) = st.vCmd;
                hist.P(hist.n) = y(2)*y(3); hist.Ph(hist.n) = y(1);
                hist.E(hist.n) = st.Ewh; hist.Eh(hist.n) = st.Ehat;
            end
            st.t = st.t + dt;
            st.vCmd = pol(info);
            st.lastY = y;
        end
        redraw();
    end
    function b = frameNow()
        if ~isfield(st,'lastY'), b = zeros(1,24); return; end
        y = st.lastY;
        b = air_quad_telemetry_pack([y(2); y(3); y(5); y(6); 0]);
    end
    % ---- 一次建图元(老 UI setupPanels 同构; patch 须先于 line, uiaxes 怪癖) ----
    function setupPanels()
        cols = lines(numel(phWind));
        hold(ax(1),'on');
        h.pv = gobjects(1,numel(phWind));
        h.pvStar = gobjects(1,numel(phWind));
        for p = 1:numel(phWind)
            h.pv(p) = line(ax(1),nan,nan,'Color',cols(p,:),'LineStyle','--', ...
                'LineWidth',1.0,'DisplayName',sprintf('风 %+.0f m/s 证据',phWind(p)));
            h.pvStar(p) = line(ax(1),nan,nan,'Color',cols(p,:),'Marker','p', ...
                'LineStyle','none','MarkerSize',12,'HandleVisibility','off');
        end
        h.ptWork = line(ax(1),nan,nan,'Color',[.25 .25 .25],'Marker','o', ...
            'MarkerFaceColor',[.9 .9 .9],'MarkerSize',8,'LineWidth',1.2, ...
            'DisplayName','当前工作点');
        h.vline = line(ax(1),nan,nan,'Color',[.85 .18 .18],'LineStyle',':', ...
            'LineWidth',1.0,'DisplayName','v_{cmd}');
        xlabel(ax(1),'地速指令 v / m·s⁻¹','FontSize',9);
        ylabel(ax(1),'P / W','FontSize',9);
        grid(ax(1),'on');
        title(ax(1),sprintf('功率-速度: P(v) 谷随风移动(E1 证据; 谷*=6∓w=%s)', ...
            mat2str(min(vMax,max(vMin,uStar-phWind)))),'FontSize',10);
        legend(ax(1),'Location','northwest','NumColumns',2,'FontSize',7);
        % 时间线(相位色带 patch 先建)
        hold(ax(2),'on');
        h.band = gobjects(1,numel(phWind));
        for p = 1:numel(phWind)
            x2 = [phBnd(p) phBnd(p+1) phBnd(p+1) phBnd(p)];
            h.band(p) = patch(ax(2),x2,[0 0 1400 1400],cols(p,:),'FaceAlpha',0.08, ...
                'EdgeColor','none','HandleVisibility','off');
        end
        yyaxis(ax(2),'left'); hold(ax(2),'on');
        h.vc = line(ax(2),nan,nan,'Color',[.55 .3 .75],'LineWidth',.8, ...
            'DisplayName','v_{cmd}');
        h.v = line(ax(2),nan,nan,'Color',[.2 .4 .8],'LineWidth',1.2, ...
            'DisplayName','v_{实}');
        ylabel(ax(2),'v / m·s⁻¹','FontSize',9); ylim(ax(2),[0 16]);
        yyaxis(ax(2),'right'); hold(ax(2),'on');
        h.Ph = line(ax(2),nan,nan,'Color',[.0 .55 .25],'LineWidth',1.0, ...
            'DisplayName','P̂');
        h.P = line(ax(2),nan,nan,'Color',[.85 .45 .1],'LineStyle','--', ...
            'LineWidth',1.0,'DisplayName','P真(V·I)');
        ylabel(ax(2),'P / W','FontSize',9); ylim(ax(2),[400 1400]);
        title(ax(2),'任务时间线(相位风色带, 240 s 窗)','FontSize',10);
        xlabel(ax(2),'t / s','FontSize',9); xlim(ax(2),[0 T_s]); grid(ax(2),'on');
        legend(ax(2),'Orientation','horizontal','Location','north','FontSize',8);
        % 能量累计
        hold(ax(3),'on');
        h.E = line(ax(3),nan,nan,'Color',[.2 .3 .4],'LineWidth',1.4, ...
            'DisplayName','E真(V·I)');
        h.Eh = line(ax(3),nan,nan,'Color',[.85 .18 .18],'LineStyle','--', ...
            'LineWidth',1.2,'DisplayName','Ê(P̂)');
        title(ax(3),'能量累计(同窗口径)','FontSize',10);
        xlabel(ax(3),'t / s','FontSize',9); ylabel(ax(3),'E / Wh','FontSize',9);
        xlim(ax(3),[0 T_s]); grid(ax(3),'on');
        legend(ax(3),'Location','northwest','FontSize',8);
        % 0xF2 帧(bar 对象一次建, 每帧只推 YData)
        hold(ax(4),'on');
        h.frameBar = bar(ax(4),1:24,zeros(1,24),0.7,'HandleVisibility','off');
        h.frameRef = line(ax(4),[0.5 24.5],[242 242],'LineStyle',':', ...
            'Color',[.6 .6 .6],'HandleVisibility','off');
        h.frameTxt = text(ax(4),1,246,'0xF2','FontSize',8);
        title(ax(4),'0xF2 副帧 24 字节(R8① 校验和=前23B和 mod 256)','FontSize',10);
        xlabel(ax(4),'Data[]','FontSize',9); ylabel(ax(4),'字节值','FontSize',9);
        xlim(ax(4),[0.5 24.5]); ylim(ax(4),[0 265]); grid(ax(4),'on');
        % 环境: 风速-相位(阶梯 + 色带)
        hold(axEnv,'on');
        h.envBand = gobjects(1,numel(phWind));
        for p = 1:numel(phWind)
            xe = [phBnd(p) phBnd(p+1) phBnd(p+1) phBnd(p)];
            h.envBand(p) = patch(axEnv,xe,[-8 -8 8 8],cols(p,:),'FaceAlpha',0.08, ...
                'EdgeColor','none','HandleVisibility','off');
        end
        h.envW = line(axEnv,nan,nan,'Color',[.2 .4 .8],'LineWidth',1.4, ...
            'DisplayName','w_x(t)');
        h.envNow = line(axEnv,nan,nan,'Color',[.85 .18 .18],'Marker','v', ...
            'LineStyle','none','MarkerSize',8,'HandleVisibility','off');
        title(axEnv,'风速-相位(三段剧本)','FontSize',8);
        xlabel(axEnv,'t / s','FontSize',8); ylabel(axEnv,'w_x / m·s⁻¹','FontSize',8);
        xlim(axEnv,[0 T_s]); ylim(axEnv,[-8 8]); grid(axEnv,'on');
        % 环境: 风矢量 + 工作点(老 UI setArrow 式: line+text, 不每帧 quiver)
        hold(axWind,'on');
        h.arrow = line(axWind,nan,nan,'Color',[.0 .55 .25],'LineWidth',2.2);
        h.arrowTip = text(axWind,0,0,char(10132),'FontName','Segoe UI Symbol', ...
            'FontSize',14,'Color',[.0 .55 .25],'HorizontalAlignment','center', ...
            'VerticalAlignment','middle');
        h.workPt = line(axWind,nan,nan,'Color',[.62 .16 .86],'Marker','p', ...
            'MarkerFaceColor',[.62 .16 .86],'MarkerSize',12,'LineStyle','none');
        h.windTxt = text(axWind,0,0.45,'','FontSize',9,'HorizontalAlignment','center');
        h.starTxt = text(axWind,0,-0.55,'','FontSize',9,'HorizontalAlignment','center');
        xlim(axWind,[-1 3]); ylim(axWind,[-1 1]); axis(axWind,'off');
    end
    % ---- 每帧增量更新(老 UI redraw 同构: 只 set 数据, drawnow limitrate) ----
    function redraw()
        % P(v) 图: 三相位证据曲线 + 谷星 + 工作点 + v_cmd 竖线
        for p = 1:numel(phWind)
            if showEv && ~isempty(Pev)
                h.pv(p).XData = vGrid; h.pv(p).YData = Pev(p,:);
                lw = 1.0; ls = '--';
                if p == st.phase, lw = 2.2; ls = '-'; end
                h.pv(p).LineWidth = lw; h.pv(p).LineStyle = ls;
                [~,iv] = min(Pev(p,:));
                h.pvStar(p).XData = vGrid(iv); h.pvStar(p).YData = Pev(p,iv);
            else
                h.pv(p).XData = nan; h.pv(p).YData = nan;
                h.pvStar(p).XData = nan; h.pvStar(p).YData = nan;
            end
        end
        if isfield(st,'lastY') && ~isempty(st.lastY)
            h.ptWork.XData = st.lastY(4); h.ptWork.YData = st.lastY(2)*st.lastY(3);
            h.vline.XData = [st.vCmd st.vCmd]; h.vline.YData = [400 1400];
        end
        % 时间线: 降采样推点(长窗降载, 老 UI 同构)
        n = hist.n;
        if n > 1
            if n > 800, ii = round(linspace(1,n,800)); else, ii = 1:n; end
            h.vc.XData = hist.t(ii); h.vc.YData = hist.vc(ii);
            h.v.XData = hist.t(ii);  h.v.YData = hist.v(ii);
            h.Ph.XData = hist.t(ii); h.Ph.YData = hist.Ph(ii);
            h.P.XData = hist.t(ii);  h.P.YData = hist.P(ii);
            h.E.XData = hist.t(ii);  h.E.YData = hist.E(ii);
            h.Eh.XData = hist.t(ii); h.Eh.YData = hist.Eh(ii);
        end
        h.band(1).Visible = showBand; h.band(2).Visible = showBand;
        h.band(3).Visible = showBand;
        h.P.Visible = showTruth; h.E.Visible = showTruth;
        % 0xF2 帧
        b = frameNow();
        h.frameBar.YData = b;
        title(ax(4),sprintf('0xF2 副帧 24 字节(校验和=%d, R8①)',b(24)),'FontSize',10);
        % 表盘 + 读出
        if isfield(st,'lastY') && ~isempty(st.lastY)
            y = st.lastY;
            gPower.Value = min(max(y(2)*y(3),gPower.Limits(1)),gPower.Limits(2));
            gSpeed.Value = min(max(y(4),gSpeed.Limits(1)),gSpeed.Limits(2));
            labVI.Text = sprintf('母线: %.2f V / %.1f A',y(2),y(3));
            labThG.Text = sprintf('油门组: %.2f / %.2f',y(5),y(6));
            labMetrics.Text = sprintf('P̂ %.0f W | P真 %.0f W | SOC %.3f | 0xF2 校验和 %d', ...
                y(1),y(2)*y(3),y(8),b(24));
        end
        % 环境: 风速阶梯 + 当前时刻
        tt = linspace(0,T_s,200); ww = zeros(size(tt));
        for j = 1:numel(tt)
            wj = windAt(tt(j)); ww(j) = wj(1);
        end
        h.envW.XData = tt; h.envW.YData = ww;
        wNow = windAt(st.t);
        h.envNow.XData = st.t; h.envNow.YData = wNow(1);
        h.envBand(1).Visible = showBand; h.envBand(2).Visible = showBand;
        h.envBand(3).Visible = showBand;
        % 环境: 风矢量箭头 + 命令谷星(老 setArrow 式, 线+字文本)
        wv = wNow(1); ln = wv/4;
        ang = 0; if ln < 0, ang = 180; ln = -ln; end
        tx = ln*cosd(ang); ty = ln*sind(ang);
        h.arrow.XData = [0.15*tx 0.85*tx]; h.arrow.YData = [0 0];
        h.arrowTip.Position = [tx ty 0]; h.arrowTip.Rotation = ang;
        h.arrow.Visible = abs(wv) > 1e-9; h.arrowTip.Visible = abs(wv) > 1e-9;
        vs = min(vMax,max(vMin,uStar-wv));
        h.workPt.XData = (vs-vMin)/(vMax-vMin)*4-1; h.workPt.YData = 0;
        h.windTxt.String = sprintf('w_x=%+.1f m/s',wv);
        h.starTxt.String = sprintf('命令谷 %+.0f',vs);
        h.starTxt.Position = [h.workPt.XData -0.55 0];
        updateReadout();
        drawnow limitrate;
    end
    function updateReadout()
        wRd = windAt(st.t);
        vStarNow = min(vMax,max(vMin,uStar-wRd(1)));
        th1 = 0; th2 = 0; socv = 0;
        if isfield(st,'lastY') && ~isempty(st.lastY)
            th1 = st.lastY(5); th2 = st.lastY(6); socv = st.lastY(8);
        end
        % 行内读数(被 MOP/MOE 卡顶替的四旋翼量并进行内, 信息不丢)
        readout.Text = sprintf(['步 %d | 相位 %d | 指令 %.2f | 地速 %.2f | v*(t) %.2f | ' ...
            't=%.0f s | 估计档 %s | P̂/P真 %.0f/%.0f W | th1/th2 %.2f/%.2f | SOC %.3f | ' ...
            'E真/Ê %.3f/%.3f Wh'], ...
            st.k,st.phase,st.vCmd,localV(),vStarNow,st.t,estTier, ...
            localPhat(),localPtrue(),th1,th2,socv,st.Ewh,st.Ehat);
        % MOP/MOE 卡(老 3.6 UI report() 格式逐字同构, 逐式照搬 w36.mop_moe):
        % Emin/Eopen = known/openloop(8) 参照趟同一 horizon 的部分窗能量(方案1),
        % 任务窗终点即全窗值; 运行中为"至今"值, 不会出现全窗参照/部分窗实飞的错配。
        if ~refsOK() || st.Ewh <= 0 || mop.n < 1
            labOverall.Text = '—'; labOverall.FontColor = [.5 .5 .5];
            if ~refsOK(), labEnergy.Text = '参照未计算(重置后生成)';
            else, labEnergy.Text = '—'; end
            labLift.Text = '—'; labLift.FontColor = [.5 .5 .5];
            labInst.Text = '—'; labSet.Text = '—'; labSea.Text = '—';
        else
            [mOE,eExc,mBo,epct] = energyMOE();
            m = mopCalc();
            labOverall.Text = sprintf('%.4f',mOE);
            if mOE >= 0.99, labOverall.FontColor = [.0 .45 .2];
            elseif mOE >= 0.97, labOverall.FontColor = [.85 .45 .1];
            else, labOverall.FontColor = [.8 .1 .1]; end
            labEnergy.Text = sprintf('%.4f (超额 %.2f%%)',mOE,eExc);
            if strcmp(armName,'openloop')
                labLift.Text = '基线=自身 / —'; labLift.FontColor = [.4 .4 .4];
            else
                lift = mOE - mBo;
                labLift.Text = sprintf('%+.4f / %+.2f%%',lift,epct);
                if lift > 1e-6, labLift.FontColor = [.0 .45 .2];
                elseif lift < -1e-6, labLift.FontColor = [.8 .1 .1];
                else, labLift.FontColor = [.5 .5 .5]; end
            end
            if isfinite(m.MOE_instant)
                labInst.Text = sprintf('%.4f / %.2f m/s',m.MOE_instant,m.meanTrackLag);
            else
                labInst.Text = sprintf('— / %.2f m/s',m.meanTrackLag);
            end
            labSet.Text = sprintf('%g 步 / %.1f%%',m.settleSteps,100*m.MOE_availability);
            labSea.Text = sprintf('%d 步 / σ=%.3f',m.searchSteps,m.steadyFluct);
        end
        status.Text = sprintf(['t=%6.1f s | 相位%d | v_cmd=%4.1f v实=%4.1f | ' ...
            'E真=%.3f Wh Ê=%.3f Wh | 臂=%s 估计档=%s [演示口径, 非数据源]'], ...
            st.t,st.phase,st.vCmd,localV(),st.Ewh,st.Ehat,armName,estTier);
    end
    function v = localV()
        v = 0; if isfield(st,'lastY'), v = st.lastY(4); end
    end
    function p = localPhat()
        p = 0; if isfield(st,'lastY'), p = st.lastY(1); end
    end
    function p = localPtrue()
        p = 0; if isfield(st,'lastY'), p = st.lastY(2)*st.lastY(3); end
    end
    function tick(~,~)
        stepSim(ticksPerFire());
        if st.t >= T_s, stopRun(); end
    end
    function stopRun()
        st.running = false;
        if strcmp(clock.Running,'on'), stop(clock); end
    end
    function onRun(~,~)
        if st.t >= T_s, onReset([],[]); end
        if strcmp(clock.Running,'on')
            stopRun();
        else
            if st.t <= 0, ensureRefs(); end   % 首次播放补 MOE 参照(缓存命中即返回)
            st.running = true;
            if isempty(pol), buildPolicy(); end
            start(clock);
        end
    end
    function onPause(~,~)
        stopRun();
    end
    function onFinish(~,~)
        stopRun();
        stepSim(ceil((T_s-st.t)/dt));
        report();
    end
    function onReset(~,~)
        stopRun();
        clear air_quad_tick
        cfg = quad_sim.config(quad_sim.baseline('b40'),'est_model',estTier);
        assignin('base','air_quad_config',cfg);
        st.t = 0; st.k = 0; st.vCmd = hV0.Value; st.Ehat = 0; st.Ewh = 0;
        st.needReset = true; st.phase = 1; st.maxAcc = 0;
        mop.n = 0; rowPsum = 0; rowLagSum = 0; rowN = 0; prevV4 = NaN;
        hist.n = 0;
        ensureRefs();   % MOE 参照(方案1: known+openloop 同配置趟, 按风剧本/任务窗缓存)
        buildPolicy();
        redraw();
    end
    function report()
        % 老 UI report() 的状态行 + MOP/MOE 汇总行(port, 逐字同构)
        if ~refsOK() || st.Ewh <= 0 || mop.n < 1
            logMsg('MOP/MOE汇总: 参照未计算(按"重置"生成)');
            return;
        end
        [mOE,~,mBo] = energyMOE();
        m = mopCalc();
        status.Text = sprintf(['MOE=%.4f | 末误差 %.3f m/s | 稳态超额 %.3f%% | ' ...
            '全程能耗超额 %.2f%%'],m.MOE_energy,m.finalErr,m.regretPercent, ...
            m.energyExcessPercent);
        logMsg(sprintf(['MOP/MOE汇总: overall=%.4f | MOE_energy=%.4f | ' ...
            '开环基线MOE=%.4f | ΔMOE=%+.4f | 可用率=%.1f%% | 末误差=%.3f | ' ...
            '跟踪滞后=%.2f m/s | 搜索步数=%d(就位占%.0f%%) | 峰值加速度=%.1f m/s²'], ...
            mOE,m.MOE_energy,mBo,mOE-mBo,100*m.MOE_availability,m.finalErr, ...
            m.meanTrackLag,m.searchSteps,100*m.settleQueryRatio,m.maxAccelUsed));
    end
    function ok = refsOK()
        ok = ~isempty(refs) && isfield(refs,'key') && strcmp(refs.key,refsKey());
    end
    function key = refsKey()
        % 参照趟 = air_quad_tick 同链同风剧本: 只依赖 (风剧本, 任务窗) 与代码版本
        key = sprintf('qdemo_refs_v1|%s|%.6g',windKind,T_s);
    end
    function [mOE,eExc,mBo,epct] = energyMOE()
        % 同 horizon 部分窗能量对比(任务窗终点=全窗值, 运行中=至今值)
        kk = min(st.k,numel(refs.Pmin));
        EminP = sum(refs.Pmin(1:kk))*dt/3600;
        EopenP = sum(refs.Popen(1:kk))*dt/3600;
        mOE = EminP/max(st.Ewh,eps);
        eExc = 100*(st.Ewh-EminP)/max(EminP,eps);
        mBo = EminP/max(EopenP,eps);
        epct = 100*(EopenP-st.Ewh)/max(EopenP,eps);
    end
    function m = mopCalc()
        % w36.mop_moe 逐式同构(行口径): 尾窗=60 行, 带内 eps=0.4;
        % MOE.overall = MOE_energy(2026-09-04 用户口径)。
        n = mop.n;
        tail = max(1,n-moeTail)+1:n;
        pmT = refPminRows(tail);
        instEff = pmT./mop.P(tail);
        inband = mop.inband(1:n);
        chg = mop.chg(1:n);
        kSettle = find(inband,1);
        if isempty(kSettle), settleSteps = NaN; else, settleSteps = kSettle; end
        m = struct();
        [mOE,eExc] = energyMOE();
        m.MOE_energy = mOE; m.energyExcessPercent = eExc;
        m.MOE = struct('energy',mOE,'instant',NaN,'availability',NaN,'overall',mOE);
        m.regretPercent = 100*mean((mop.P(tail)-pmT)./pmT);
        m.MOE_instant = mean(instEff(isfinite(instEff)));
        m.MOE_availability = sum(inband)/max(n,1);
        m.settleSteps = settleSteps;
        m.searchSteps = nnz(chg);
        m.settleQueryRatio = nnz(chg & mop.inband(1:n))/max(nnz(chg),1);
        m.meanTrackLag = mean(mop.lag(1:n));
        m.steadyFluct = std(mop.vc(tail),'omitnan');
        wEnd = windAt(mop.t(n));
        m.finalErr = abs(mop.vc(n)-min(vMax,max(vMin,uStar-wEnd(1))));
        m.maxAccelUsed = st.maxAcc;
        m.MOE.instant = m.MOE_instant; m.MOE.availability = m.MOE_availability;
    end
    function pm = refPminRows(rows)
        % known 参照趟逐物理拍 P真 -> 评价行区间均值(与行均功率同口径)
        pm = zeros(1,numel(rows));
        for q = 1:numel(rows)
            k1 = (rows(q)-1)*nRow+1; k2 = min(rows(q)*nRow,numel(refs.Pmin));
            if k1 > numel(refs.Pmin), pm(q) = NaN;
            else, pm(q) = mean(refs.Pmin(k1:k2)); end
        end
    end
    function R = ensureRefs()
        % 方案1: 同配置同风剧本离线参照趟(known=Emin, openloop(8)=基线),
        % 按 (风剧本,任务窗) 缓存(跨启动 appdata 复用); 跑完即清 air_quad_tick。
        key = refsKey();
        if isfield(refs,'key') && strcmp(refs.key,key), R = refs; return; end
        cch = getappdata(0,'qdemo_refs_cache');
        if isa(cch,'containers.Map') && isKey(cch,key)
            refs = cch(key); setappdata(fig,'qdemo_refs',refs);
            R = refs;
            logMsg(sprintf('MOE 参照(缓存): E_known=%.3f Wh | E_openloop=%.3f Wh', ...
                refs.Emin,refs.Eopen));
            return;
        end
        status.Text = 'MOE 参照计算中(known 趟, 约 30 s)...'; drawnow;
        rK = refPass(@refKnownV,'known');
        status.Text = 'MOE 参照计算中(openloop 趟, 约 30 s)...'; drawnow;
        rO = refPass(@(t) 8,'openloop');
        refs = struct('key',key,'Emin',rK.E,'Eopen',rO.E, ...
            'Pmin',rK.P,'Popen',rO.P);
        if ~isa(cch,'containers.Map'), cch = containers.Map; end
        cch(key) = refs; setappdata(0,'qdemo_refs_cache',cch);
        setappdata(fig,'qdemo_refs',refs);   % 测试/诊断挂钩(非 API)
        R = refs;
        logMsg(sprintf('MOE 参照就绪: E_known=%.3f Wh | E_openloop=%.3f Wh (%s)', ...
            rK.E,rO.E,key));
        status.Text = 'MOE 参照就绪';
    end
    function v = refKnownV(t)
        % known 参照策略=R7 命令谷 v*(t)=clip(uStar-w, vMin, vMax)(显式 oracle)
        w = windAt(t);
        v = min(vMax,max(vMin,uStar-w(1)));
    end
    function R = refPass(polFn,tag)
        % 同配置参照趟: 独立走一遍 air_quad_tick(定策略), 逐拍 P真 与能量
        clear air_quad_tick
        K = ceil(T_s/dt); P = zeros(1,K); E = 0; rst = 1;
        for kk = 1:K
            t = (kk-1)*dt;
            y = air_quad_tick([polFn(t); -windAt(t); rst]);   % 风语义取负(同 stepSim)
            rst = 0;
            P(kk) = y(2)*y(3);
            E = E + y(2)*y(3)*dt/3600;
            if mod(kk,2400) == 0
                status.Text = sprintf('MOE 参照计算中(%s 趟 %d%%)...', ...
                    tag,round(100*kk/K)); drawnow;
            end
        end
        clear air_quad_tick
        R = struct('E',E,'P',P);
    end
    function onChanged(~,~)
        stopRun();
        status.Text = '参数已更改，按"重置"或"播放"生效';
    end
    function onArm(hnd,~)
        armName = hnd.Value;
        logMsg(sprintf('臂 -> %s',armName));
        onReset([],[]);
    end
    function onEst(hnd,~)
        estTier = hnd.Value;
        logMsg(sprintf('估计档 -> %s',estTier));
        onReset([],[]);
    end
    function onWind(hnd,~)
        windKind = hnd.Value;
        logMsg(sprintf('风剧本 -> %s',windKind));
        onReset([],[]);
    end
    function toggleEv()
        showEv = cbEv.Value; redraw();
    end
    function toggleTruth()
        showTruth = cbTruth.Value; redraw();
    end
    function toggleBand()
        showBand = cbBand.Value; redraw();
    end
    function logMsg(msg)
        stamp = datestr(now,'HH:MM:SS');
        v = logBox.Value; if ~iscell(v), v = {v}; end
        logBox.Value = [{sprintf('[%s] %s',stamp,msg)}; v(:)];
    end
    function clearLog(~,~)
        logBox.Value = {'日志已清空'};
    end
    function loadEvidence(~,~)
        if ~isfile(curveCsv)
            logMsg('未找到 P(v) 证据 CSV: docs/evidence/quad_migration/quad_p3/quad_p3_sweep_vi.csv');
            return;
        end
        logMsg('—— P3 证据(quad_p3_sweep_vi.csv, 演示只读加载) ——');
        for p = 1:numel(phWind)
            if isempty(Pev), continue; end
            [pmin,iv] = min(Pev(p,:));
            logMsg(sprintf('相位%d 风%+.0f m/s: 谷 v=%.0f m/s, P真=%.1f W', ...
                p,phWind(p),vGrid(iv),pmin));
        end
        logMsg('排序(vi 口径): known 38.99 < sweepcal 42.57 < openloop 44.93 Wh | 数字口径以证据 CSV 为准');
    end
    function exportCurrent(~,~)
        stopRun();
        folder = fullfile(root,'results'); if ~exist(folder,'dir'), mkdir(folder); end
        file = fullfile(folder,['quad_demo_' datestr(now,'yyyymmdd_HHMMSS') '.png']);
        exportapp(fig,file); status.Text = ['面板截图已导出：' file]; logMsg(status.Text);
    end
    function exportGifCurrent(~,~)
        stopRun();
        folder = fullfile(root,'results'); if ~exist(folder,'dir'), mkdir(folder); end
        file = fullfile(folder,['quad_demo_' datestr(now,'yyyymmdd_HHMMSS') '.gif']);
        nFrames = 24; stride = max(1,ceil(nFrames*max(1,round(rate*0.15/dt))));
        status.Text = 'GIF导出中…'; drawnow;
        savedPosition = fig.Position; fig.Position = [40 30 1000 680]; drawnow;
        first = true; cleanupGif = onCleanup(@() set(fig,'Position',savedPosition)); %#ok<NASGU>
        for k = 1:nFrames
            if st.t < T_s, stepSim(stride); end
            tmp = fullfile(tempdir,sprintf('qf_%d.png',randi(1e9)));
            exportapp(fig,tmp);
            [A,map] = rgb2ind(imread(tmp),128);
            if first, imwrite(A,map,file,'gif','LoopCount',Inf,'DelayTime',.15); first = false;
            else, imwrite(A,map,file,'gif','WriteMode','append','DelayTime',.15); end
            delete(tmp);
        end
        status.Text = ['GIF动画已导出：' file]; logMsg(status.Text);
    end
    % ---- 布局/视图(老 UI 同构) ----
    function toggleSize(which)
        if strcmp(which,'air')
            if airPanel.Layout.Row(1) == 1
                airPanel.Layout.Row = 3; airPanel.Layout.Column = 1;
                btnAirSize.Text = '放大 ⤢';
            else
                airPanel.Layout.Row = [1 3]; airPanel.Layout.Column = [1 2];
                btnAirSize.Text = '还原 ⤡';
            end
        else
            if envPanel.Layout.Row(1) == 1
                envPanel.Layout.Row = 3; envPanel.Layout.Column = 2;
                btnEnvSize.Text = '放大 ⤢';
            else
                envPanel.Layout.Row = [1 3]; envPanel.Layout.Column = [1 2];
                btnEnvSize.Text = '还原 ⤡';
            end
        end
        drawnow;
    end
    function setView(v)
        curView = v;
        plots.Visible = 'on';
        airPanel.Visible = 'on'; envPanel.Visible = 'on';
        switch v
            case 'console'
                airPanel.Layout.Row = 3; airPanel.Layout.Column = 1;
                envPanel.Layout.Row = 3; envPanel.Layout.Column = 2;
                btnAirSize.Text = '放大 ⤢'; btnEnvSize.Text = '放大 ⤢';
            case 'air'
                envPanel.Visible = 'off';
                airPanel.Layout.Row = [1 3]; airPanel.Layout.Column = [1 2];
                btnAirSize.Text = '还原 ⤡'; btnEnvSize.Text = '放大 ⤢';
            case 'env'
                airPanel.Visible = 'off';
                envPanel.Layout.Row = [1 3]; envPanel.Layout.Column = [1 2];
                btnAirSize.Text = '放大 ⤢'; btnEnvSize.Text = '还原 ⤡';
        end
        highlightButtons();
        drawnow;
    end
    function highlightButtons()
        if strcmp(curView,'console'), btnConsole.FontWeight='bold'; else, btnConsole.FontWeight='normal'; end
        if strcmp(curView,'air'), btnAir.FontWeight='bold'; else, btnAir.FontWeight='normal'; end
        if strcmp(curView,'env'), btnEnv.FontWeight='bold'; else, btnEnv.FontWeight='normal'; end
        btnConsole.BackgroundColor=[.85 .92 1]*strcmp(curView,'console')+[1 1 1]*(strcmp(curView,'console')==0);
        btnAir.BackgroundColor=[.85 .92 1]*strcmp(curView,'air')+[1 1 1]*(strcmp(curView,'air')==0);
        btnEnv.BackgroundColor=[.85 .92 1]*strcmp(curView,'env')+[1 1 1]*(strcmp(curView,'env')==0);
    end
    function resizeLayout(varargin)
        bodyHeight = max(440,fig.InnerPosition(4)-112);
        outer.RowHeight = {44,bodyHeight,28};
        avail = max(500,bodyHeight)-448;
        formH = max(230,round(0.45*avail)); logH = max(150,avail-formH);
        leftLayout.RowHeight = {38,formH,150,175,30,logH};
    end
    function onClose(~,~)
        stopRun();
        if isvalid(clock), delete(clock); end
        if evalin('base','exist(''air_quad_config'',''var'')')
            evalin('base','clear air_quad_config');
        end
        delete(fig);
    end
end
% ================= 局部助手(老 3.6 面板同款) =================
function h = number(g,text,row,value,limits)
label(g,text,row);
h = uieditfield(g,'numeric','Value',value,'Limits',limits); put(h,row,2);
end
function h = choice(g,text,row,items,data,value)
label(g,text,row);
h = uidropdown(g,'Items',items,'ItemsData',data,'Value',value); put(h,row,2);
end
function label(g,text,row)
h = uilabel(g,'Text',text,'FontName','Microsoft YaHei','FontSize',11, ...
    'WordWrap','on'); put(h,row,1);
end
function put(h,row,col)
h.Layout.Row = row; h.Layout.Column = col;
end
