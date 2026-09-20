function [opt, c, arms] = q1_opt(chunkId)
%Q39.Q1_OPT Q1 敏感性矩阵预注册定义(单一事实源, QUAD_MIGRATION_PLAN §4-Q1/§5-M5)。
% 场景共性(对齐 moe38.csv 锚点口径): platform 后端, seed=11, evalSeconds=3600,
% tailSteps=60, 复合风 B=2.5 sigma=0.3(与 3.8 预训练缓存元数据一致, ANCHOR
% 幕可复现 moe38 3600s 行)。
% 估计器场景选项:
%   estMode    'truth' = 真值口径(可叠加合成标定误差 s1/s2)
%              'l0'    = L0 静态映射(结构性失配本体)
%   s1_pct     S1 常数乘性偏差 [%]
%   s2_pct_mps S2 线性倾斜偏差(随空速) [%/m/s]
%   s4_vpct    S4 电压传感器标定偏差(端电压缩放, 只在 l0 上物理起效) [%]
%   dwell_s    S5 指令后固定驻留秒数(0 = 38 号就位委托制原样)
%   pretrainCache purerl 预训练缓存开关: 仅 ANCHOR 开(复现 moe38 真值口径预训练);
%                其余场景一律关 = 在线预训练于同一口径 plant(预训练域=部署口径)。
% 预注册修正(2026-09-21, 开批前; 依据 run_q1_checks 的 trim_curve 实测):
%   P2 平台曲线的谷底由 H3 前飞诱导项创造, L0 纯静态映射曲线无谷
%   (vStarL0=0, 谷区结构偏差 ~+20%)。因此 S1/S2/S5 移到 truth 口径+合成标定
%   误差上测——"临界倾斜 b1*"只对已抓住曲线形状、仅剩标定残差的估计器(L1 档)
%   有定义; S3/S4 留在 l0 基座(S3 回答"纯静态查表可行吗", S4 电压路径只在
%   l0 上物理进入反解与查表)。解释边界: P2 只建 H3 功率项、未建真实螺旋桨
%   的转速下降(n 效应), 实机 pwm 本身携带空速信息, L0 在实机口径大概率保留
%   谷——S3 结论为保守上界, Q2 轨 B 复核。
% 臂 reductions(预注册): sweepcal/purerl_off 全场景; purerl_on 只跑 6 个代表档
% (S3/S1p5/S2p14/S2m14/S4p1/S5d1, 覆盖全部场景族), 全档留 Q4/M6 正式批;
% openloop/known 与估计器无关(指令不读功率), 只在 ANCHOR + XCHECK 各跑一次并
% 逐位比对 powerTrue, 其余场景复用 ANCHOR 行。S1/S2/S5(truth 口径)的参照行 =
% ANCHOR(无偏差真值); S3/S4(l0 口径)的参照行 = 两者互比 + ANCHOR 开环超额。
opt = common('truth', 0, 0, 0, 0, false, {});
switch chunkId   % 档位名大小写敏感, 勿 upper()
    case 'ANCHOR'
        opt.pretrainCache = true;
        opt.arms = {'openloop','known','sweepcal','purerl_off','purerl_on'};
    case 'XCHECK'
        opt = common('l0', 0, 0, 0, 0, false, {});
        opt.arms = {'openloop','known'};
    case 'S3'    % 结构性偏差 = L0 本体(无附加人工偏差)
        opt = common('l0', 0, 0, 0, 0, false, {'sweepcal','purerl_off','purerl_on'});
        arms = opt.arms;
    case 'S1m3', opt = common('truth', -3, 0, 0, 0, false, {'sweepcal','purerl_off'});
    case 'S1p3', opt = common('truth',  3, 0, 0, 0, false, {'sweepcal','purerl_off'});
    case 'S1m5', opt = common('truth', -5, 0, 0, 0, false, {'sweepcal','purerl_off'});
    case 'S1p5', opt = common('truth',  5, 0, 0, 0, false, {'sweepcal','purerl_off','purerl_on'});
    case 'S2m07', opt = common('truth', 0, -0.7, 0, 0, false, {'sweepcal','purerl_off'});
    case 'S2p07', opt = common('truth', 0,  0.7, 0, 0, false, {'sweepcal','purerl_off'});
    case 'S2m14', opt = common('truth', 0, -1.4, 0, 0, false, {'sweepcal','purerl_off','purerl_on'});
    case 'S2p14', opt = common('truth', 0,  1.4, 0, 0, false, {'sweepcal','purerl_off','purerl_on'});
    case 'S2m28', opt = common('truth', 0, -2.8, 0, 0, false, {'sweepcal','purerl_off'});
    case 'S2p28', opt = common('truth', 0,  2.8, 0, 0, false, {'sweepcal','purerl_off'});
    case 'S4p1', opt = common('l0', 0, 0,  1.0, 0, false, {'sweepcal','purerl_off','purerl_on'});
    case 'S4m1', opt = common('l0', 0, 0, -1.0, 0, false, {'sweepcal','purerl_off'});
    case 'S5d1', opt = common('truth', 0, 0, 0, 1, false, {'sweepcal','purerl_off','purerl_on'});
    case 'S5d2', opt = common('truth', 0, 0, 0, 2, false, {'sweepcal','purerl_off'});
    case 'S5d5', opt = common('truth', 0, 0, 0, 5, false, {'sweepcal','purerl_off'});
    case 'RERUN' % M5: S3 换独立 MATLAB 会话重跑, 与 S3 行逐位比对
        opt = common('l0', 0, 0, 0, 0, false, {'sweepcal','purerl_off','purerl_on'});
        arms = opt.arms;
    otherwise
        error('q39:Q1Opt', 'Unknown chunk id: %s', chunkId);
end
arms = opt.arms;
c = w36.config('backend','platform','seed',11,'evalSeconds',3600,'tailSteps',60,...
    'windKind','composite','windBias',2.5,'windAmp',0,'windAmpY',0,'turbStd',0.3);
end
function opt = common(mode, s1, s2, s4, dw, cache, arms)
opt = struct('estMode',mode,'s1_pct',s1,'s2_pct_mps',s2,'s4_vpct',s4,...
    'dwell_s',dw,'pretrainCache',cache);
opt.arms = arms;   % struct() 收到空 cell 会生成 0x0 空结构体, 必须后补字段
end
