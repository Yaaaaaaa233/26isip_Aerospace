function [opt, c, arms] = q4_opt(chunkId, pass)
%Q39.Q4_OPT Q4 正式验收批预注册定义(单一事实源, QUAD_MIGRATION_PLAN 20260921
% §4-Q4/§5-M6·M7)。开批前冻结; 执行中如需修正, 先改本文件并在证据文档登记
% 修正与依据, 再续跑(行级幂等)。
% 批结构(每臂 true/est/diff 三行记账, M7):
%   F1*  estMode='l1'  正式配置五臂: openloop/known/sweepcal/purerl_off/purerl_on
%   F2*  estMode='truth' 真值口径基线五臂(同种子) —— M6 赢面损耗的参照批
%   ×2   两遍(pass=1/2)全部换独立 MATLAB 会话重跑, 逐字段逐位比对(M6 逐位确定)
% 场景共性(与 Q1/Q3 共性一致, 仅时长 9000s): platform 后端, seed=11,
% evalSeconds=9000, tailSteps=60, 复合风 B=2.5 sigma=0.3。
% 预注册口径声明:
%   - 正式批跑在 L1 档(D1: Q4 不得在 L0 口径跑); 声明系数 = 配置自身
%     (声明上界档), 残差在可申报误差带内(Q3 实测尾偏差 0.12~0.17%);
%   - 真值批 purerl 在线预训练于真值链(9000s 无缓存命中, 与 l1 批的
%     在线预训练同域对齐, 预训练域=各自部署口径);
%   - openloop/known 不读功率: 其真值口径应在两批间逐位一致(P3 冻结复核点,
%     3600s 已证, 9000s 复验);
%   - rows 契约: evalSeconds=9000 -> rowsN ∈ [9000, 11250)(预算合同, 逐值入档;
%     purerl 在线预训练幕日志可比预算多出个位秒行, 3600s 批实测 +6)。
% M6 门(评估器 q39.q4_gates):
%   a) 学习臂(sweepcal/purerl_off/purerl_on)真值口径超额 < 开环真值口径超额
%      (l1 批上评估; 真值批同判据作参照行);
%   b) 赢面损耗 wear = margin_truth批(臂) − margin_l1批(臂) ≤ 1pp/臂;
%      前置: 两批开环真值超额逐位相等;
%   c) ×2 逐位: pass1/pass2 全字段一致(NaN==NaN 视为相等);
%   d) rows 契约(见上)。
if nargin < 2, pass = 1; end
assert(pass == 1 || pass == 2, 'q39:Q4Opt', 'pass must be 1 or 2.');
opt = struct('estMode','l1','s1_pct',0,'s2_pct_mps',0,'s4_vpct',0,...
    'dwell_s',0,'pretrainCache',false);
opt.arms = {};   % struct() 收到空 cell 会生成 0x0 空结构体, 必须后补字段
opt.decl = [];
switch upper(chunkId)
    case 'SMOKE'   % runner 冒烟(120s, 独立 CSV, 不入门)
        opt.arms = {'openloop','sweepcal'};
    case 'F1A'
        opt.arms = {'openloop','known'};
    case 'F1B', opt.arms = {'sweepcal'};
    case 'F1C', opt.arms = {'purerl_off'};
    case 'F1D', opt.arms = {'purerl_on'};
    case 'F2A'
        opt = local_truth(opt);
        opt.arms = {'openloop','known'};
    case 'F2B'
        opt = local_truth(opt);
        opt.arms = {'sweepcal'};
    case 'F2C'
        opt = local_truth(opt);
        opt.arms = {'purerl_off'};
    case 'F2D'
        opt = local_truth(opt);
        opt.arms = {'purerl_on'};
    otherwise
        error('q39:Q4Opt', 'Unknown chunk id: %s', chunkId);
end
arms = opt.arms;
c = w36.config('backend','platform','seed',11,'evalSeconds',9000,'tailSteps',60,...
    'windKind','composite','windBias',2.5,'windAmp',0,'windAmpY',0,'turbStd',0.3);
if strcmpi(chunkId, 'SMOKE')
    c.evalSeconds = 120;
end
end

function opt = local_truth(opt)
opt.estMode = 'truth';
end
