%PARITY_MATLAB 无 RL 工具箱的奇偶校验:输出 Python 移植对照数值
root = fullfile(fileparts(mfilename('fullpath')), '..', 'speed_rl_residual');
addpath(root);
adapter = speedrl.make_synthetic_adapter();

% A: 确定性场景(无风直线, fixed)——公式级精确比对
c = speedrl.config('windMode','none','trajectory','straight','seed',7);
[~, m] = speedrl.run_episode(c,'fixed',adapter);
fprintf('A none_straight_fixed %.12f %.12f %.12f\n', m.meanPowerW, m.energyWh, m.estimatedEnduranceHours);

% B: 确定性场景(恒定风圆周, fixed)
c = speedrl.config('windMode','constant','trajectory','circle','seed',7);
[~, m] = speedrl.run_episode(c,'fixed',adapter);
fprintf('B constant_circle_fixed %.12f %.12f %.12f\n', m.meanPowerW, m.energyWh, m.estimatedEnduranceHours);

% C: 确定性场景(正弦风圆周, fixed)
c = speedrl.config('windMode','sine','trajectory','circle','seed',7);
[~, m] = speedrl.run_episode(c,'fixed',adapter);
fprintf('C sine_circle_fixed %.12f %.12f %.12f\n', m.meanPowerW, m.energyWh, m.estimatedEnduranceHours);

% D: 随机场景统计比对(不规则风圆周 20 种子, fixed 与 scripted)
fp = zeros(20,1); sp = zeros(20,1);
for k = 1:20
    c = speedrl.config('windMode','irregular','trajectory','circle','seed',2000+k);
    [~, mf] = speedrl.run_episode(c,'fixed',adapter);
    [~, ms] = speedrl.run_episode(c,'scripted',adapter);
    fp(k) = mf.meanPowerW; sp(k) = ms.meanPowerW;
end
fprintf('D irregular_fixed mean %.4f std %.4f\n', mean(fp), std(fp));
fprintf('D irregular_scripted mean %.4f std %.4f\n', mean(sp), std(sp));

% E: 随机恒定风统计比对(种子 3001-3020)
fc = zeros(20,1);
for k = 1:20
    c = speedrl.config('windMode','constant','trajectory','circle','randomizeWind',true,'seed',3000+k);
    [~, mf] = speedrl.run_episode(c,'fixed',adapter);
    fc(k) = mf.meanPowerW;
end
fprintf('E constant_random_fixed mean %.4f std %.4f\n', mean(fc), std(fc));
