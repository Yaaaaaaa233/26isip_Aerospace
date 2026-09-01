function scn = scenario(kind, c, varargin)
%SCENARIO Shift schedules for task 1. Evaluator side; never given to searchers.
% kind:
%   'static'    无平移(基线)
%   'jumpUp'    dx 跳变 optimum0 -> optimum0+2.7 (如 6.3 -> 9)
%   'jumpDown'  dx 跳变 optimum0 -> optimum0-2.3 (如 6.3 -> 4)
%   'offset'    仅 dy 上移 5% (argmin 不变, 考验不误触发重搜)
%   'ramp'      dx 慢漂 60s..180s 线性 +1.7
%   'midsearch' dx 跳变发生在初始搜索进行中(第6次评估时刻)
%   'manual'    手动设置平移(varargin: shifts cell 数组)
%
% varargin for 'manual':
%   'shifts'  N×4 矩阵 [time(s) dx(m/s) dy  enabled(0/1)]
%             未启用行被忽略；time=0 表示立即生效
% jumps/ramps 的时刻单位是秒, 必须给末段评价留出完整窗口。
% 跳变时刻默认 min(120s, 40%%全程)；短预算测试会自动前移。
tJump=min(120,floor(0.4*c.duration))*c.tEval;
assert(c.duration*c.tEval-tJump>c.tailSteps*c.tEval,...
    'task1:Scenario','Jump must leave a full evaluation tail.');

% 解析 varargin
shifts=zeros(0,4);
for k=1:2:numel(varargin)
    if strcmp(varargin{k},'shifts')
        shifts=varargin{k+1};
    end
end

switch kind
    case 'static',    jumps=zeros(0,3); ramps=zeros(0,3);
    case 'jumpUp',    jumps=[tJump 2.7 0];  ramps=zeros(0,3);
    case 'jumpDown',  jumps=[tJump -2.3 0]; ramps=zeros(0,3);
    case 'offset',    jumps=[tJump 0 0.05]; ramps=zeros(0,3);
    case 'ramp',      jumps=zeros(0,3);      ramps=[60 180 1.7];
    case 'midsearch', jumps=[6*c.tEval 2.7 0]; ramps=zeros(0,3);
    case 'manual'
        jumps=zeros(0,3); ramps=zeros(0,3);
        for r=1:size(shifts,1)
            t=shifts(r,1); dx=shifts(r,2); dy=shifts(r,3); en=shifts(r,4);
            if en==0 || (dx==0 && dy==0), continue; end
            % t=0 表示立即生效(在第1步之前)
            if t==0, t=0.5*c.tEval; end
            jumps(end+1,:)=[t dx dy]; %#ok<AGROW>
        end
    otherwise, error('task1:Scenario','Unknown scenario kind: %s',kind);
end
scn=struct('kind',kind,'jumps',jumps,'ramps',ramps,'noiseSigma',0,'seed',1);
end