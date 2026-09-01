function summaries = run_demo(agentSource)
%RUN_DEMO Circle/sine-wind interface demo; scripted is not learned RL.
if nargin<1, agentSource=[]; end
root=fileparts(mfilename('fullpath')); addpath(root);
c=speedrl.config('duration',120,'windMode','sine','trajectory','circle','seed',7,...
    'windObservation','observable'); adapter=speedrl.make_synthetic_adapter();
cases={...
    '固定速度', 'fixed', speedrl.make_baseline('fixed');...
    '风场解析基准', 'baseline', speedrl.make_baseline('wind_analytic');...
    '残差接口参考（非RL）', 'scripted', speedrl.make_baseline('fixed')};
if ~isempty(agentSource)
    if ischar(agentSource) || isstring(agentSource), q=load(agentSource,'agent'); policy=q.agent; else, policy=agentSource; end
    cases(end+1,:)={'TD3候选',policy,speedrl.make_baseline('fixed')};
end
logs=cell(size(cases,1),1); summaries=struct([]);
for k=1:size(cases,1)
    [logs{k},m]=speedrl.run_episode(c,cases{k,2},adapter,cases{k,3});
    m.policy=cases{k,1}; summaries=[summaries;m]; %#ok<AGROW>
end
folder=fullfile(root,'results','demo'); if ~exist(folder,'dir'), mkdir(folder); end
S=struct2table(summaries); writetable(S,fullfile(folder,'summary.csv'));
fig=figure('Visible','off','Position',[80 60 1400 900]); cleanup=onCleanup(@()close(fig));
tiledlayout(2,2,'TileSpacing','compact','Padding','compact'); colors=lines(numel(logs));
nexttile; hold on; grid on;
for k=1:numel(logs), plot(logs{k}.time_s,logs{k}.true_power_w,'Color',colors(k,:),'DisplayName',cases{k,1}); end
xlabel('时间 / s'); ylabel('真实代理功率 / W'); title('固定时长功率比较'); legend('Location','best');
nexttile; hold on; grid on;
for k=1:numel(logs), plot(logs{k}.time_s,logs{k}.reference_mps,'Color',colors(k,:),'DisplayName',cases{k,1}); end
yline(c.speedBounds(1),'k:','最低地速'); xlabel('时间 / s'); ylabel('速度参考 / m/s'); title('基准与残差后的速度参考');
nexttile; plot(logs{1}.time_s,[logs{1}.wind_tangent_mps logs{1}.wind_normal_mps]); grid on;
xlabel('时间 / s'); ylabel('风速 / m/s'); title('圆周切向/法向观测风'); legend('切向风','法向风');
nexttile; axis equal; hold on; grid on;
for k=1:numel(logs)
    phase=logs{k}.path_phase_rad; plot(c.pathRadius*cos(phase),c.pathRadius*sin(phase),'Color',colors(k,:),'DisplayName',cases{k,1});
end
xlabel('N / m'); ylabel('E / m'); title('圆周相位接口示意'); legend('Location','best');
sgtitle('残差速度RL接口演示 | 正弦风与圆周均为代理模型，非实测');
exportgraphics(fig,fullfile(folder,'residual_rl_interface.png'),'Resolution',150);
savefig(fig,fullfile(folder,'residual_rl_interface.fig'));
for k=1:numel(logs), writetable(logs{k},fullfile(folder,sprintf('case_%d.csv',k))); end
disp(S(:,{'policy','meanPowerW','estimatedEnduranceHours','boundViolations','rateViolations'}));
end
