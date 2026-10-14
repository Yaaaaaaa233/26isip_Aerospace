function fig = launch_quad_demo(visible)
%LAUNCH_QUAD_DEMO 四旋翼新模型展示面板(演示层, 2026-10-15 v3)。
% v2: 布局层按老 UI(modules/platform_link/launch_3_6_demo.m)骨架重做——uifigure +
%   uigridlayout 网格托管 + uipanel 卡片(put/choice/number 助手同款), 修 v1 手工
%   坐标错位问题。内容语义与 v1 相同。
% v3: 视觉修复(仅布局层)——滑条刻度标签截断(表单末行 32->54)、环境卡"放大"按钮
%   压住风速轴 x 刻度(uiaxes 包 uipanel 再入 flex 行)、P(v) 图例遮曲线(改左上)、
%   时间线图例贴 v_cmd 尖峰(改顶部横排)、'1x' 行不撑满致底部约 120 px 空带(改显式
%   行高按客户区配平)、左栏"小字说明"归位到评价卡下方(表单 4 行)。语义/API 不变。
% 黑箱红线: 面板仅演示, 不作可引用数据源(数字口径以 docs/evidence 证据 CSV 为准);
%   演示链 = air_quad_tick(P4 薄包装 -> quad_sim.ctrl/step 权威链)逐步推进,
%   无 P2 现实性退化(时延/噪声/量化见 P2 验收证据, 面板不复现)。
% 臂 = +quad_sim/p3_arm 策略句柄(信息面=白名单 t/v/x/Phat/Vmeas/Ehat/cmd, G-P2);
%   openloop 固定 8 / sweepcal 在线三点扫 / known = R7 定律 oracle(v*=6-w, 显式)。
% P(v) 谷图 = E1 真值扫描证据加载(docs/evidence/quad_migration/quad_p3/
%   quad_p3_sweep_vi.csv), 不重算; 谷随风移动 = R7 定律(命令谷 = 空速谷 6 - w)。
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
% ---- 状态 ----
st = struct('t',0,'k',0,'vCmd',8,'Ehat',0,'Ewh',0,'needReset',true, ...
    'phase',1,'running',false);
nMax = ceil(T_s/dt); down = 5; nD = ceil(nMax/down)+1;
hist = struct('t',zeros(1,nD),'v',zeros(1,nD),'vc',zeros(1,nD), ...
    'P',zeros(1,nD),'Ph',zeros(1,nD),'E',zeros(1,nD),'Eh',zeros(1,nD),'n',0);
pol = []; estTier = 'vi'; windKind = 'phase'; rate = 2; armName = 'sweepcal';
cfg = quad_sim.config(quad_sim.baseline('b40'),'est_model',estTier);
assignin('base','air_quad_config',cfg);
% ================= UI 骨架(老 3.6 面板同款: uifigure+uigridlayout+卡片) =================
fig = uifigure('Name','四旋翼在线速度寻优演示(P4 薄包装链, 演示层)', ...
    'Position',[40 30 1500 960],'Color',[.96 .97 .98],'Visible',visible, ...
    'AutoResizeChildren','off','CloseRequestFcn',@onClose);
outer = uigridlayout(fig,[3 2]);
outer.RowHeight = {44,'1x',28}; outer.ColumnWidth = {330,'1x'};
outer.Padding = [12 10 12 10]; outer.RowSpacing = 10;
header = uilabel(outer,'Text', ...
    '四旋翼演示 | P̂=V·I 测量主档(R8③) × 谷=气动物理涌现(E1) × 命令谷=空速谷6∓风(R7) × 臂=p3_arm(G-P2 白名单) × [演示口径, 非数据源]', ...
    'FontName','Microsoft YaHei','FontSize',14,'FontWeight','bold');
put(header,1,[1 2]);
% ---- 左栏(参数表单/操作/评价卡/日志) ----
leftLayout = uigridlayout(outer,[5 1]); put(leftLayout,2,1);
% 显式行高: uigridlayout 的 '1x' 行在本环境只取内容偏好高度而非剩余空间, 会留
% 底部空带; 按客户区 939 px(1500x960 图 - 上下内边距/标题/状态)配平到 826 px(v3 修复)
leftLayout.RowHeight = {176,110,175,30,303};
leftLayout.Padding = [0 0 0 0]; leftLayout.RowSpacing = 8;
left = leftLayout;
form = uipanel(left,'BorderType','none'); put(form,1,1);
g = uigridlayout(form,[4 2]); g.ColumnWidth = {140,'1x'};
% 末行 54 px: uislider 刻度标签需要约 48 px, 32 px 会截断标签(v3 修复)
g.RowHeight = {32,32,32,54}; g.Padding = [0 0 8 0]; g.RowSpacing = 7;
hArm = choice(g,'控制策略',1,{'sweepcal 在线寻优','openloop 恒速 8','known R7 oracle'}, ...
    {'sweepcal','openloop','known'},'sweepcal');
hArm.ValueChangedFcn = @onArm;
hEst = choice(g,'估计档',2,{'vi (V·I 测量主档)','l1 (空速修正降级)','l0 (粗估降级)'}, ...
    {'vi','l1','l0'},'vi');
hEst.ValueChangedFcn = @onEst;
hWind = choice(g,'风剧本',3,{'三段相位 4/0/-4 (P3 口径)','静风 0','恒风 +2.5'}, ...
    {'phase','calm','gust'},'phase');
hWind.ValueChangedFcn = @onWind;
speedLabel = uilabel(g,'Text','播放速度: 2.00x','FontName','Microsoft YaHei', ...
    'FontSize',11,'WordWrap','on'); put(speedLabel,4,1);
% 刻度 1x 与 0.5x 间距过近会叠字, 去掉 0.5x 标签(极限值仍可拖动, 读数在左侧文本)
speedSlider = uislider(g,'Limits',[0.5 5],'Value',2,'MajorTicks',[1 2 3 5], ...
    'MajorTickLabels',{'1x','2x','3x','5x'}); put(speedSlider,4,2);
speedSlider.ValueChangedFcn = @(~,ev) setSpeed(ev.Value);
actions = uigridlayout(left,[2 4]); put(actions,2,1);
actions.RowHeight = {34,34}; actions.RowSpacing = 7; actions.Padding = [0 0 8 0];
play = uibutton(actions,'Text','播放'); put(play,1,1);
pauseBtn = uibutton(actions,'Text','暂停'); put(pauseBtn,1,2);
resetBtn = uibutton(actions,'Text','重置'); put(resetBtn,1,3);
finishBtn = uibutton(actions,'Text','末帧'); put(finishBtn,1,4);
exportPng = uibutton(actions,'Text','导出PNG'); put(exportPng,2,[1 4]);
play.ButtonPushedFcn = @onRun; pauseBtn.ButtonPushedFcn = @onPause;
resetBtn.ButtonPushedFcn = @onReset; finishBtn.ButtonPushedFcn = @onFinish;
exportPng.ButtonPushedFcn = @exportCurrent;
resultCard = uipanel(left,'Title','★ 评价结果(实时)','FontName','Microsoft YaHei', ...
    'FontSize',11,'ForegroundColor',[.62 .08 .08],'HighlightColor',[.62 .08 .08]);
put(resultCard,3,1);
rg = uigridlayout(resultCard,[5 2]); rg.RowHeight = {26,24,24,24,24};
rg.ColumnWidth = {'1x','1x'}; rg.Padding = [8 2 8 2]; rg.RowSpacing = 1;
mkTag = @(txt) uilabel(rg,'Text',txt,'FontName','Microsoft YaHei','FontSize',9, ...
    'FontColor',[.25 .25 .25]);
mkVal = @(sz) uilabel(rg,'Text','—','FontName','Microsoft YaHei','FontSize',sz, ...
    'FontWeight','bold','HorizontalAlignment','right');
labET = mkTag('E真 / Ê (Wh, 任务累计)'); put(labET,1,1);
labE = mkVal(12); put(labE,1,2); labE.FontColor = [.0 .45 .2];
labVT = mkTag('v_cmd / v实 (m/s)'); put(labVT,2,1);
labV = mkVal(11); put(labV,2,2);
labPT = mkTag('P̂ / P真 (W)'); put(labPT,3,1);
labP = mkVal(11); put(labP,3,2);
labST = mkTag('命令谷 6∓w (R7) / 相位'); put(labST,4,1);
labStar = mkVal(11); put(labStar,4,2);
labTT = mkTag('t (s) / 估计档'); put(labTT,5,1);
labT = mkVal(11); put(labT,5,2);
readout = uilabel(left,'Text','演示口径: tick=薄包装权威链; P(v)=E1 证据', ...
    'WordWrap','on','FontName','Microsoft YaHei','FontSize',9, ...
    'FontColor',[.4 .4 .4]); put(readout,4,1);
logBox = uitextarea(left,'Editable','off','FontName','Microsoft YaHei','FontSize',9);
put(logBox,5,1);
% ---- 右侧绘图区(老面板 3x2 网格: 4 axes + 飞机/环境双卡) ----
plots = uigridlayout(outer,[3 2]); put(plots,2,2);
% 显式行高(同上, '1x' 不撑满): 上两行各 274 px 承载四图, 卡片行 250 px;
% 三行 + 行距 826 px 与左栏配平, 两侧底边对齐(约 y=884), 消除底部空带
plots.RowHeight = {274,274,250}; plots.ColumnWidth = {'1x','1x'};
plots.RowSpacing = 14; plots.ColumnSpacing = 18; plots.Padding = [0 0 0 0];
ax = gobjects(1,4); axHold = gobjects(1,2);
% uiaxes 直接放多行 uigridlayout 单元格时会按自身偏好高度渲染并伸出单元格(压住
% 下一行, 底部留空带); 每行两只轴先包一层无边框 uipanel 再入 flex 行, 行高才能
% 撑满(v3 修复)。holder 背景色与图区底色一致, 不引入可见色块。
for r = 1:2
    axHold(r) = uipanel(plots,'BorderType','none', ...
        'BackgroundColor',[.96 .97 .98]); put(axHold(r),r,[1 2]);
    hg = uigridlayout(axHold(r),[1 2]);
    hg.Padding = [0 0 0 0]; hg.ColumnSpacing = 18;
    for c = 1:2
        k = 2*(r-1)+c;
        ax(k) = uiaxes(hg); put(ax(k),1,c);
        disableDefaultInteractivity(ax(k)); ax(k).Toolbar.Visible = 'off';
    end
end
airPanel = uipanel(plots,'Title','飞机模型：功率+速度双表盘(黑箱仪表)', ...
    'FontName','Microsoft YaHei','ForegroundColor',[.15 .3 .6], ...
    'HighlightColor',[.15 .3 .6]);
airPanel.Layout.Row = 3; airPanel.Layout.Column = 1;
ag = uigridlayout(airPanel,[5 2]); ag.RowHeight = {150,16,16,16,34};
ag.ColumnWidth = {'1x','1x'}; ag.Padding = [6 6 6 4]; ag.RowSpacing = 4;
gPower = uigauge(ag,'Limits',[400 1400]); put(gPower,1,1);
labPw = uilabel(ag,'Text','功率表 P̂ / W','FontName','Microsoft YaHei','FontSize',9, ...
    'HorizontalAlignment','center'); put(labPw,2,1);
gSpeed = uigauge(ag,'Limits',[0 16]); put(gSpeed,1,2);
labSp = uilabel(ag,'Text','地速表 / m·s⁻¹','FontName','Microsoft YaHei','FontSize',9, ...
    'HorizontalAlignment','center'); put(labSp,2,2);
labVI = uilabel(ag,'Text','母线: —','FontName','Microsoft YaHei','FontSize',10, ...
    'HorizontalAlignment','center'); put(labVI,3,[1 2]);
labTh = uilabel(ag,'Text','油门组: —','FontName','Microsoft YaHei','FontSize',10, ...
    'HorizontalAlignment','center'); put(labTh,4,[1 2]);
btnAirSize = uibutton(ag,'Text','放大 ⤢'); put(btnAirSize,5,[1 2]);
btnAirSize.ButtonPushedFcn = @(~,~) toggleSize('air');
envPanel = uipanel(plots,'Title','环境模型：相位风 × 风矢量', ...
    'ForegroundColor',[.1 .45 .25],'HighlightColor',[.1 .45 .25]);
envPanel.Layout.Row = 3; envPanel.Layout.Column = 2;
eg = uigridlayout(envPanel,[2 1]); eg.RowHeight = {'1x',28};
% uiaxes 直接放在 flex 行会伸出单元格压住下一行(uigridlayout 行为), 两轴先包一层
% 无边框 uipanel 再入 flex 行(v3 修复: 原实现按钮压住风速轴 x 刻度)
eg.Padding = [4 4 4 2]; eg.RowSpacing = 2;
envHolder = uipanel(eg,'BorderType','none'); put(envHolder,1,1);
btnEnvSize = uibutton(eg,'Text','放大 ⤢'); put(btnEnvSize,2,1);
btnEnvSize.ButtonPushedFcn = @(~,~) toggleSize('env');
egh = uigridlayout(envHolder,[1 2]); egh.Padding = [0 0 0 0]; egh.ColumnSpacing = 8;
axEnv = uiaxes(egh); put(axEnv,1,1);
disableDefaultInteractivity(axEnv); axEnv.Toolbar.Visible = 'off';
title(axEnv,'风速-相位(三段剧本)','FontSize',8);
axWind = uiaxes(egh); put(axWind,1,2);
disableDefaultInteractivity(axWind); axWind.Toolbar.Visible = 'off';
title(axWind,'风矢量 + 工作点','FontSize',8);
status = uilabel(outer,'Text','就绪','FontName','Microsoft YaHei','FontSize',10);
put(status,3,2);
drawAll();
updateStatus();
clock = timer('ExecutionMode','fixedSpacing','Period',.15,'BusyMode','drop', ...
    'TimerFcn',@(~,~) stepSim(ticksPerFire()));
S = struct('step',@stepSim,'state',@getState,'hist',@getHist,'policy',@getPol, ...
    'whitelist',{whitelist},'frame',@frameNow,'autostart',@onRun);
setappdata(fig,'qdemo',S);

% ================= 嵌套函数(可变状态一律具名嵌套, 勿匿名捕获) =================
    function s = getState(), s = st; end
    function hh = getHist(), hh = hist; end
    function p = getPol(), p = pol; end
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
                return;
            end
            w = windAt(st.t);
            rst = 0;
            if st.needReset, rst = 1; st.needReset = false; end
            y = air_quad_tick([st.vCmd; w; rst]);
            info = struct('t',st.t,'v',y(4),'x',y(7),'Phat',y(1), ...
                'Vmeas',y(2),'Ehat',st.Ehat,'cmd',st.vCmd);
            assert(isequal(sort(fieldnames(info))',sort(whitelist)), ...
                'quad:DemoCausality','info face has non-whitelist fields.');
            st.k = st.k + 1;
            st.Ehat = st.Ehat + y(1)*dt/3600;
            st.Ewh = st.Ewh + y(2)*y(3)*dt/3600;
            st.phase = phaseAt(st.t);
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
        drawAll();
        updateStatus();
    end
    function b = frameNow()
        if ~isfield(st,'lastY'), b = zeros(1,24); return; end
        y = st.lastY;
        b = air_quad_telemetry_pack([y(2); y(3); y(5); y(6); 0]);
    end
    function drawAll()
        drawCurve(); drawTime(); drawEnergy(); drawFrame();
        drawGauges(); drawEnv();
    end
    function drawCurve()
        cla(ax(1)); hold(ax(1),'on');
        if isempty(Pev)
            text(ax(1),0.2,0.5,'P(v) 证据 CSV 缺失');
        else
            cols = lines(numel(phWind));
            for p = 1:numel(phWind)
                lw = 1.0; ls = '--';
                if p == st.phase, lw = 2.2; ls = '-'; end
                plot(ax(1),vGrid,Pev(p,:),ls,'Color',cols(p,:), ...
                    'LineWidth',lw,'DisplayName',sprintf('风 %+.0f m/s',phWind(p)));
                [~,iv] = min(Pev(p,:));
                plot(ax(1),vGrid(iv),Pev(p,iv),'p','Color',cols(p,:), ...
                    'MarkerSize',12,'HandleVisibility','off');
            end
            if isfield(st,'lastY')
                plot(ax(1),st.lastY(4),st.lastY(2)*st.lastY(3),'ko', ...
                    'MarkerSize',8,'LineWidth',1.5,'HandleVisibility','off');
                xline(ax(1),st.vCmd,'k:','HandleVisibility','off');
            end
            legend(ax(1),'Location','northwest','FontSize',8);
            title(ax(1),sprintf('P(v) 谷随风移动 (E1 证据; 谷*=6∓w=%s)', ...
                mat2str(min(vMax,max(vMin,uStar-phWind)))),'FontSize',10);
            xlabel(ax(1),'地速指令 v / m·s⁻¹','FontSize',9);
            ylabel(ax(1),'P / W','FontSize',9);
            grid(ax(1),'on');
        end
        hold(ax(1),'off');
    end
    function drawTime()
        cla(ax(2)); hold(ax(2),'on');
        cols = lines(numel(phWind));
        for p = 1:numel(phWind)          % uiaxes 怪癖: patch 须先于 line 创建
            x = [phBnd(p) phBnd(p+1) phBnd(p+1) phBnd(p)];
            patch(ax(2),x,[0 0 1400 1400],cols(p,:),'FaceAlpha',0.08, ...
                'EdgeColor','none','HandleVisibility','off');
        end
        if hist.n > 1
            ii = 1:hist.n;
            yyaxis(ax(2),'left'); hold(ax(2),'on');   % yyaxis 重置 hold, 换边补
            plot(ax(2),hist.t(ii),hist.vc(ii),'-','LineWidth',1.0, ...
                'DisplayName','v_{cmd}');
            plot(ax(2),hist.t(ii),hist.v(ii),'-','LineWidth',1.4, ...
                'DisplayName','v_{实}');
            ylabel(ax(2),'v / m·s⁻¹','FontSize',9); ylim(ax(2),[0 16]);
            yyaxis(ax(2),'right'); hold(ax(2),'on');
            plot(ax(2),hist.t(ii),hist.Ph(ii),'-','LineWidth',1.0, ...
                'DisplayName','P̂');
            plot(ax(2),hist.t(ii),hist.P(ii),'--','LineWidth',1.0, ...
                'DisplayName','P真(V·I)');
            ylabel(ax(2),'P / W','FontSize',9); ylim(ax(2),[400 1400]);
            legend(ax(2),'Orientation','horizontal','Location','north','FontSize',8);
        end
        title(ax(2),'任务时间线 (相位风色带, 240 s 窗)','FontSize',10);
        xlabel(ax(2),'t / s','FontSize',9); xlim(ax(2),[0 T_s]);
        grid(ax(2),'on');
        hold(ax(2),'off');
    end
    function drawEnergy()
        cla(ax(3)); hold(ax(3),'on');
        if hist.n > 1
            ii = 1:hist.n;
            plot(ax(3),hist.t(ii),hist.E(ii),'-','LineWidth',1.4, ...
                'DisplayName','E真(V·I)');
            plot(ax(3),hist.t(ii),hist.Eh(ii),'--','LineWidth',1.2, ...
                'DisplayName','Ê(P̂)');
        end
        title(ax(3),'能量累计(同窗口径)','FontSize',10);
        xlabel(ax(3),'t / s','FontSize',9); ylabel(ax(3),'E / Wh','FontSize',9);
        xlim(ax(3),[0 T_s]); grid(ax(3),'on');
        if hist.n > 1, legend(ax(3),'Location','northwest','FontSize',8); end
        hold(ax(3),'off');
    end
    function drawFrame()
        cla(ax(4)); hold(ax(4),'on');
        b = frameNow();
        bar(ax(4),1:24,b,0.7,'HandleVisibility','off');
        plot(ax(4),[0.5 24.5],[242 242],':','Color',[.6 .6 .6], ...
            'HandleVisibility','off');
        text(ax(4),1,246,'0xF2','FontSize',8);
        title(ax(4),sprintf('0xF2 副帧 2 字节 (校验和=%d, R8①)',b(24)),'FontSize',10);
        xlabel(ax(4),'Data[]','FontSize',9); ylabel(ax(4),'字节值','FontSize',9);
        xlim(ax(4),[0.5 24.5]); ylim(ax(4),[0 265]); grid(ax(4),'on');
        hold(ax(4),'off');
    end
    function drawGauges()
        if isfield(st,'lastY')
            y = st.lastY;
            gPower.Value = min(max(y(2)*y(3),gPower.Limits(1)),gPower.Limits(2));
            gSpeed.Value = min(max(y(4),gSpeed.Limits(1)),gSpeed.Limits(2));
            labVI.Text = sprintf('母线: %.2f V / %.1f A',y(2),y(3));
            labTh.Text = sprintf('油门组: %.2f / %.2f | SOC %.3f',y(5),y(6),y(8));
        end
    end
    function drawEnv()
        cla(axEnv); hold(axEnv,'on');
        cols = lines(numel(phWind));
        for p = 1:numel(phWind)
            patch(axEnv,[phBnd(p) phBnd(p+1) phBnd(p+1) phBnd(p)], ...
                [-8 -8 8 8],cols(p,:),'FaceAlpha',0.08,'EdgeColor','none', ...
                'HandleVisibility','off');
        end
        tt = linspace(0,T_s,200);
        ww = zeros(size(tt));
        for j = 1:numel(tt)
            wj = windAt(tt(j)); ww(j) = wj(1);
        end
        plot(axEnv,tt,ww,'-','LineWidth',1.4);
        title(axEnv,'风速-相位(三段剧本)','FontSize',8);
        xlabel(axEnv,'t / s','FontSize',8); ylabel(axEnv,'w_x / m·s⁻¹','FontSize',8);
        xlim(axEnv,[0 T_s]); ylim(axEnv,[-8 8]); grid(axEnv,'on');
        hold(axEnv,'off');
        cla(axWind); hold(axWind,'on');
        w = windAt(st.t);
        quiver(axWind,0,0,w(1)/4,0,'LineWidth',2,'MaxHeadSize',2);
        text(axWind,0,0.4,sprintf('w_x=%+.1f m/s',w(1)),'FontSize',9);
        vs = min(vMax,max(vMin,uStar-w(1)));
        plot(axWind,vs,0,'p','MarkerSize',14);
        text(axWind,vs,-0.5,sprintf('命令谷 %+.0f',vs),'FontSize',9, ...
            'HorizontalAlignment','center');
        xlim(axWind,[-1 3]); ylim(axWind,[-1 1]); axis(axWind,'off');
        hold(axWind,'off');
    end
    function updateStatus()
        status.Text = sprintf( ...
            't=%6.1f s | 相位%d | v_cmd=%4.1f v实=%4.1f | E真=%.3f Wh Ê=%.3f Wh | 臂=%s 估计档=%s [演示口径]', ...
            st.t,st.phase,st.vCmd,localV(),st.Ewh,st.Ehat,armName,estTier);
        labE.Text = sprintf('%.3f / %.3f',st.Ewh,st.Ehat);
        labV.Text = sprintf('%.1f / %.1f',st.vCmd,localV());
        labP.Text = sprintf('%.0f / %.0f',localPhat(),localPtrue());
        wNow = windAt(st.t);
        labStar.Text = sprintf('%+.0f / %d', ...
            min(vMax,max(vMin,uStar-wNow(1))),st.phase);
        labT.Text = sprintf('%.1f / %s',st.t,estTier);
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
    function stopRun()
        st.running = false;
        if strcmp(clock.Running,'on'), stop(clock); end
    end
    function onRun(~,~)
        if st.t >= T_s, onReset([],[]); end
        if strcmp(clock.Running,'on')
            stopRun();
        else
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
    end
    function onReset(~,~)
        stopRun();
        clear air_quad_tick
        cfg = quad_sim.config(quad_sim.baseline('b40'),'est_model',estTier);
        assignin('base','air_quad_config',cfg);
        st.t = 0; st.k = 0; st.vCmd = 8; st.Ehat = 0; st.Ewh = 0;
        st.needReset = true; st.phase = 1;
        hist.n = 0;
        buildPolicy();
        drawAll();
        updateStatus();
    end
    function onArm(h,~)
        armName = h.Value;
        logMsg(sprintf('臂 -> %s',armName));
        onReset([],[]);
    end
    function onEst(h,~)
        estTier = h.Value;
        logMsg(sprintf('估计档 -> %s',estTier));
        onReset([],[]);
    end
    function onWind(h,~)
        windKind = h.Value;
        logMsg(sprintf('风剧本 -> %s',windKind));
        onReset([],[]);
    end
    function logMsg(msg)
        v = logBox.Value;
        if ~iscell(v), v = {v}; end
        logBox.Value = [{sprintf('[%6.1f] %s',st.t,msg)}; v(:)];
    end
    function exportCurrent(~,~)
        png = fullfile(root,'results','quad_demo_export.png');
        exportapp(fig,png);
        logMsg(sprintf('导出 %s',png));
    end
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
