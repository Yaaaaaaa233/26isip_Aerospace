function fig = launch_quad_demo(visible)
%LAUNCH_QUAD_DEMO 四旋翼新模型展示面板(演示层, 2026-10-14)。
% 黑箱红线: 面板仅演示, 不作可引用数据源(数字口径以 docs/evidence 证据 CSV 为准);
%   演示链 = air_quad_tick(P4 薄包装 -> quad_sim.ctrl/step 权威链)逐步推进,
%   无 P2 现实性退化(时延/噪声/量化见 P2 验收证据, 面板不复现)。
% 臂 = +quad_sim/p3_arm 策略句柄(信息面=白名单 t/v/x/Phat/Vmeas/Ehat/cmd, G-P2);
%   openloop 固定 8 / sweepcal 在线三点扫 / known = R7 定律 oracle(v*=6-w, 显式)。
% P(v) 谷图 = E1 真值扫描证据加载(docs/evidence/quad_migration/quad_p3/
%   quad_p3_sweep_vi.csv), 不重算; 谷随风移动 = R7 定律(命令谷 = 空速谷 6 - w)。
% 区: 控制台(臂/估计档/风剧本/速度/起停) | P(v) 谷图 | 时间线 | 仪表 + 0xF2 组帧。
% 用法: launch_quad_demo                    % 交互
%       fig = launch_quad_demo('off');      % 无窗(批处理/冒烟)
%       S = getappdata(fig,'qdemo'); S.step(500); S.state   % 批处理驱动
if nargin < 1, visible = 'on'; end
root = fileparts(mfilename('fullpath'));
repo = fileparts(fileparts(root));
addpath(root); addpath(fullfile(repo,'models','px4_x8'));
% ---- 常量(P3 窗口口径) ----
dt = 0.01; T_s = 240; phWind = [4 0 -4]; phBnd = [0 80 160 240];
vMin = 4; vMax = 14; uStar = 6;             % 空速谷 6 m/s(E1 证据, 相位不变)
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
    'P',zeros(1,nD),'Ph',zeros(1,nD),'n',0);
pol = []; estTier = 'vi'; windKind = 'phase'; rate = 2; armName = 'sweepcal';
cfg = quad_sim.config(quad_sim.baseline('b40'),'est_model',estTier);
assignin('base','air_quad_config',cfg);
% ---- 图 ----
fig = figure('Name','quad demo (演示层, 非数据源)','NumberTitle','off', ...
    'Position',[60 50 1280 820],'Visible',visible, ...
    'Color',[0.96 0.96 0.97],'CloseRequestFcn',@onClose);
% 控制台
uicontrol(fig,'Style','text','String','臂:','Units','normalized', ...
    'Position',[0.02 0.955 0.03 0.03],'BackgroundColor',[0.96 0.96 0.97]);
hArm = uicontrol(fig,'Style','popupmenu','Units','normalized', ...
    'Position',[0.05 0.955 0.11 0.035], ...
    'String',{'sweepcal (在线寻优)','openloop (恒速 8)','known (R7 oracle)'}, ...
    'Value',1,'Callback',@onArm);
uicontrol(fig,'Style','text','String','估计档:','Units','normalized', ...
    'Position',[0.17 0.955 0.05 0.03],'BackgroundColor',[0.96 0.96 0.97]);
hEst = uicontrol(fig,'Style','popupmenu','Units','normalized', ...
    'Position',[0.22 0.955 0.14 0.035], ...
    'String',{'vi (V·I 测量主档, R8③)','l1 (空速修正降级)','l0 (粗估降级)'}, ...
    'Value',1,'Callback',@onEst);
uicontrol(fig,'Style','text','String','风剧本:','Units','normalized', ...
    'Position',[0.37 0.955 0.05 0.03],'BackgroundColor',[0.96 0.96 0.97]);
hWind = uicontrol(fig,'Style','popupmenu','Units','normalized', ...
    'Position',[0.42 0.955 0.16 0.035], ...
    'String',{'三段相位 4/0/-4 (P3 口径)','静风 0','恒风 +2.5'}, ...
    'Value',1,'Callback',@onWind);
uicontrol(fig,'Style','text','String','速度x','Units','normalized', ...
    'Position',[0.59 0.955 0.04 0.03],'BackgroundColor',[0.96 0.96 0.97]);
hRate = uicontrol(fig,'Style','slider','Units','normalized', ...
    'Position',[0.63 0.958 0.12 0.028],'Min',0.5,'Max',5,'Value',2, ...
    'SliderStep',[0.1 0.2],'Callback',@onRate);
hRun = uicontrol(fig,'Style','pushbutton','String','开始','Units','normalized', ...
    'Position',[0.77 0.952 0.06 0.04],'Callback',@onRun);
uicontrol(fig,'Style','pushbutton','String','复位','Units','normalized', ...
    'Position',[0.84 0.952 0.06 0.04],'Callback',@onReset);
hStatus = uicontrol(fig,'Style','text','String','','Units','normalized', ...
    'Position',[0.02 0.012 0.96 0.028],'HorizontalAlignment','left', ...
    'BackgroundColor',[0.96 0.96 0.97],'FontName','Consolas');
% 四区
axCurve = axes('Parent',fig,'Units','normalized','Position',[0.05 0.44 0.40 0.46]);
axTime  = axes('Parent',fig,'Units','normalized','Position',[0.53 0.44 0.43 0.46]);
axGauge = axes('Parent',fig,'Units','normalized','Position',[0.05 0.08 0.40 0.28]);
axTel   = axes('Parent',fig,'Units','normalized','Position',[0.53 0.08 0.43 0.28]);
drawCurve(); drawTime(); drawGauge(); drawTel();
tm = timer('ExecutionMode','fixedSpacing','Period',0.05,'BusyMode','drop', ...
    'TimerFcn',@(~,~) stepSim(ticksPerFire()));
S = struct('step',@stepSim,'state',@getState,'hist',@getHist,'policy',@getPol, ...
    'whitelist',{whitelist},'frame',@frameNow);
setappdata(fig,'qdemo',S);
updateStatus();

% ================= 嵌套函数(可变状态一律嵌套, 勿匿名捕获) =================
% 取值器必须是具名嵌套函数: 匿名 @() st 会按值冻结构造时刻快照(交接书教训)。
    function s = getState(), s = st; end
    function hh = getHist(), hh = hist; end
    function p = getPol(), p = pol; end
    function n = ticksPerFire()
        n = max(1,round(rate*0.05/dt));
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
            if st.needReset
                rst = 1; st.needReset = false;
            end
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
            end
            st.t = st.t + dt;
            st.vCmd = pol(info);
            st.lastY = y;
        end
        drawCurve(); drawTime(); drawGauge(); drawTel();
        updateStatus();
    end
    function b = frameNow()
        if ~isfield(st,'lastY'), b = zeros(1,24); return; end
        y = st.lastY;
        b = air_quad_telemetry_pack([y(2); y(3); y(5); y(6); 0]);
    end
    function drawCurve()
        cla(axCurve); hold(axCurve,'on');
        if isempty(Pev)
            text(axCurve,0.2,0.5,'P(v) 证据 CSV 缺失','FontSize',11);
        else
            cols = lines(numel(phWind));
            for p = 1:numel(phWind)
                lw = 1.0; ls = '--';
                if p == st.phase, lw = 2.2; ls = '-'; end
                plot(axCurve,vGrid,Pev(p,:),ls,'Color',cols(p,:), ...
                    'LineWidth',lw,'DisplayName',sprintf('风 %+.0f m/s',phWind(p)));
                [~,iv] = min(Pev(p,:));
                plot(axCurve,vGrid(iv),Pev(p,iv),'p','Color',cols(p,:), ...
                    'MarkerSize',12,'HandleVisibility','off');
            end
            if isfield(st,'lastY')
                plot(axCurve,st.lastY(4),st.lastY(2)*st.lastY(3),'ko', ...
                    'MarkerSize',8,'LineWidth',1.5,'HandleVisibility','off');
                xline(axCurve,st.vCmd,'k:','HandleVisibility','off');
            end
            legend(axCurve,'Location','northeast','FontSize',8);
            xlabel(axCurve,'地速指令 v (m/s)'); ylabel(axCurve,'P (W)');
            title(axCurve,sprintf('P(v) 谷随风移动 (E1 证据; 谷*=6∓w = %s)', ...
                mat2str(min(vMax,max(vMin,uStar-phWind)))));
            grid(axCurve,'on');
        end
        hold(axCurve,'off');
    end
    function drawTime()
        cla(axTime); hold(axTime,'on');
        cols = lines(numel(phWind));
        for p = 1:numel(phWind)
            x = [phBnd(p) phBnd(p+1) phBnd(p+1) phBnd(p)];
            patch(axTime,x,[0 0 1400 1400],cols(p,:),'FaceAlpha',0.08, ...
                'EdgeColor','none','HandleVisibility','off');
            text(axTime,mean(x(1:2)),15.2,sprintf('风 %+.0f',phWind(p)), ...
                'FontSize',8,'Color',cols(p,:));
        end
        if hist.n > 1
            ii = 1:hist.n;
            yyaxis(axTime,'left'); hold(axTime,'on');   % yyaxis 会重置 hold, 逐边补
            plot(axTime,hist.t(ii),hist.vc(ii),'-','LineWidth',1.0, ...
                'DisplayName','v_{cmd}');
            plot(axTime,hist.t(ii),hist.v(ii),'-','LineWidth',1.4, ...
                'DisplayName','v_{实}');
            ylabel(axTime,'v (m/s)'); ylim(axTime,[0 16]);
            yyaxis(axTime,'right'); hold(axTime,'on');
            plot(axTime,hist.t(ii),hist.Ph(ii),'-','LineWidth',1.0, ...
                'DisplayName','P̂');
            plot(axTime,hist.t(ii),hist.P(ii),'--','LineWidth',1.0, ...
                'DisplayName','P真(V·I)');
            ylabel(axTime,'P (W)'); ylim(axTime,[400 1400]);
            legend(axTime,'Location','northwest','FontSize',8);
        end
        xlabel(axTime,'t (s)'); xlim(axTime,[0 T_s]);
        title(axTime,'任务时间线 (三段相位风, 240 s 窗)');
        grid(axTime,'on');
        hold(axTime,'off');
    end
    function drawGauge()
        cla(axGauge); hold(axGauge,'on');
        if ~isfield(st,'lastY')
            text(axGauge,0.2,0.5,'未开始','FontSize',11); return;
        end
        y = st.lastY;
        vals = [y(2)*y(3) y(2) y(3) y(5) y(6) y(8)];
        nrm = [700 30 60 1 1 1];
        lbl = {'P真(V·I)','母线 V','母线 I','油门组1','油门组2','SOC'};
        txt = {sprintf('%.1f W',vals(1)),sprintf('%.2f V',vals(2)), ...
            sprintf('%.1f A',vals(3)),sprintf('%.2f',vals(4)), ...
            sprintf('%.2f',vals(5)),sprintf('%.3f',vals(6))};
        bar(axGauge,vals./nrm,0.6);
        set(axGauge,'XTick',1:6,'XTickLabel',lbl,'FontSize',8);
        ylim(axGauge,[0 1.35]);
        for i = 1:6
            text(axGauge,i,vals(i)/nrm(i)+0.06,txt{i},'HorizontalAlignment','center', ...
                'FontSize',8);
        end
        title(axGauge,'仪表 (归一化条 + 读数; P̂ 见状态栏)');
        grid(axGauge,'on');
    end
    function drawTel()
        cla(axTel); hold(axTel,'on'); axis(axTel,'off');  % 无 hold 时 quiver 会清轴
        b = frameNow();
        hexs = reshape(dec2hex(b,2)',1,[]);
        txt = '';
        for i = 1:24
            txt = [txt hexs(2*i-1:2*i) ' ']; %#ok<AGROW>
            if i == 12, txt = [txt newline]; end %#ok<AGROW>
        end
        text(axTel,0.02,0.82,'0xF2 副帧 2 (24 B, R8①② 映射):','FontSize',10);
        text(axTel,0.02,0.55,txt,'FontName','Consolas','FontSize',10);
        if isfield(st,'lastY')
            w = windAt(st.t);
            quiver(axTel,0.25,0.22,w(1)/4,0,0,'LineWidth',2,'MaxHeadSize',2);
            text(axTel,0.25,0.10,sprintf('风矢量 x = %+.1f m/s (NED)',w(1)),'FontSize',9);
        end
        text(axTel,0.55,0.22,sprintf('E_{真} = %.3f Wh',st.Ewh),'FontSize',10);
        text(axTel,0.55,0.10,sprintf('Ê    = %.3f Wh',st.Ehat),'FontSize',10);
    end
    function updateStatus()
        ph = '相位-';
        if st.t > 0 || st.k > 0, ph = sprintf('相位%d',st.phase); end
        set(hStatus,'String',sprintf( ...
            ' t=%6.1f s | %s | v_cmd=%4.1f v实=%4.1f | P̂=%6.1f W P真=%6.1f W | E=%.3f Wh | 臂=%s 估计档=%s | [演示口径, 非数据源]', ...
            st.t,ph,st.vCmd,localV(),localPhat(),localPtrue(),st.Ewh,armName,estTier));
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
        if strcmp(get(tm,'Running'),'on'), stop(tm); end
        set(hRun,'String','开始');
    end
    function onRun(~,~)
        if st.t >= T_s, onReset([],[]); end
        if strcmp(get(tm,'Running'),'on')
            stopRun();
        else
            st.running = true;
            if isempty(pol), buildPolicy(); end
            start(tm);
            set(hRun,'String','暂停');
        end
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
        drawCurve(); drawTime(); drawGauge(); drawTel();
        updateStatus();
    end
    function onArm(h,~)
        names = {'sweepcal','openloop','known'};
        armName = names{get(h,'Value')};
        onReset([],[]);
    end
    function onEst(h,~)
        tiers = {'vi','l1','l0'};
        estTier = tiers{get(h,'Value')};
        onReset([],[]);
    end
    function onWind(h,~)
        kinds = {'phase','calm','gust'};
        windKind = kinds{get(h,'Value')};
        onReset([],[]);
    end
    function onRate(h,~)
        rate = get(h,'Value');
    end
    function onClose(~,~)
        stopRun();
        if isvalid(tm), delete(tm); end
        if evalin('base','exist(''air_quad_config'',''var'')')
            evalin('base','clear air_quad_config');
        end
        delete(fig);
    end
end
