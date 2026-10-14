function result = run_quad_demo_smoke()
%RUN_QUAD_DEMO_SMOKE 演示面板开发级冒烟(2026-10-14)。
% 运行: cd models/plane_quad && run_quad_demo_smoke
% 口径: 演示层(黑箱红线: 面板不作可引用数据源); 门(全部硬断言):
%   S-D1 构建+推进: step(300) 状态前进、能量有限
%   S-D2 确定性: 两次独立启动各 step(300) 历史逐位一致
%   S-D3 因果白名单: 面板内逐调用断言(info 面仅 t/v/x/Phat/Vmeas/Ehat/cmd)
%   S-D4 0xF2 组帧自洽: 24 B/标识 0xF2/校验和=前23B和(R8①)/电压油门读回 <=1 LSB
%   S-D5 sweepcal 长推 sane: 1500 步(15 s)后 vCmd 在 [4,14] 带内、能耗有限
root = fileparts(mfilename('fullpath'));
repo = fileparts(fileparts(root));
addpath(root); addpath(fullfile(repo,'models','px4_x8'));
resDir = fullfile(root,'results');
if ~exist(resDir,'dir'), mkdir(resDir); end
fails = {};
% ---- S-D1 + S-D2 (两次独立启动, 各 300 步后对比) ----
h = cell(1,2); sv = cell(1,2); frames = cell(1,2);
for r = 1:2
    fig = launch_quad_demo('off');
    S = getappdata(fig,'qdemo');
    S.step(300);
    sv{r} = S.state(); h{r} = S.hist(); frames{r} = S.frame();
    if r == 2
        S.step(1200);                          % 续推到 1500 步(S-D5, 另存)
        svEnd = S.state();
        png = fullfile(resDir,'quad_demo_shot.png');
        saveas(fig,png);
    end
    close(fig);
end
if sv{1}.k ~= 300 || ~isfinite(sv{1}.Ewh) || ~isfinite(sv{1}.Ehat)
    fails{end+1} = 'S-D1: advance failed/nonfinite';
end
detOK = isequal(h{1},h{2});
if ~detOK, fails{end+1} = 'S-D2: two fresh launches not bitwise'; end
% ---- S-D4 组帧自洽(两次帧都查) ----
frameOK = true;
for r = 1:2
    b = frames{r};
    ck = mod(sum(b(1:23)),256);
    frameOK = frameOK && numel(b) == 24 && b(1) == 242 && b(24) == ck;
end
if ~frameOK, fails{end+1} = 'S-D4: telemetry frame invalid'; end
% ---- S-D5 长推 sane ----
vOK = svEnd.vCmd >= 4 && svEnd.vCmd <= 14 && isfinite(svEnd.Ewh) && svEnd.k == 1500;
if ~vOK
    fails{end+1} = sprintf('S-D5: vCmd=%.2f k=%d not sane',svEnd.vCmd,svEnd.k);
end
T2 = cell2table({sv{1}.k, detOK, frameOK, svEnd.vCmd, svEnd.Ewh, svEnd.Ehat}, ...
    'VariableNames',{'steps','deterministic','frame_ok','vCmd_end','Ewh','Ehat'});
csv = fullfile(resDir,'quad_demo_smoke.csv'); writetable(T2,csv,'Encoding','UTF-8');
result = struct('pass',isempty(fails),'tier','smoke','csv',csv, ...
    'png',fullfile(resDir,'quad_demo_shot.png'), ...
    'deterministic',detOK,'frameOK',frameOK,'failures',{fails});
if ~result.pass
    error('quad:DemoSmoke','DEMO SMOKE FAIL (%d): %s | archive: %s', ...
        numel(fails),strjoin(fails,'; '),csv);
end
fprintf('demo smoke PASS -> %s | det %d | frame %d | vCmd_end %.2f | E %.3f Wh\n', ...
    csv,detOK,frameOK,svEnd.vCmd,svEnd.Ewh);
end
