function W = p3_warmup(c,o)
%QUAD_SIM.P3_WARMUP purerl 族试飞预训练驱动(多臂适配训练栈, p3_multiarm_opt 裁决 b)。
% W = quad_sim.p3_warmup(c, o)
% 在独立 realism_run 实例上跑一个 purerl 学习器(静风定常 w=0, 不含评价窗相位
% 剧本信息, 同分布不同实现), 导出学习器状态供 p3_arm('purerl_on'/'purerl_off')
% 部署。w36 本地路径 warmPlant 同款语义: 预训练不计入 240 s 任务窗能耗——
% **预训练步为额外试飞预算**(w36 红线 3 口径, 结论表述必须注明)。
% 输入: c=config; o=T_s(600)/seed/dwell_s(2)/tail_s(1) + purerl 学习参数覆盖。
% 输出 W: mu/bBase/sigma/kStep + T_s/E_wh/completed 元信息。
% 因果口径: 学习器只见白名单面(逐调用断言, 与评价段 G-P2 同款结构强制)。
narginchk(1,2);
if nargin < 2 || isempty(o), o = struct(); end
d = struct('T_s',600,'seed',20261028,'dwell_s',2,'tail_s',1);
fn = fieldnames(o);
for k = 1:numel(fn), d.(fn{k}) = o.(fn{k}); end
o = d;
po = quad_sim.p3_multiarm_opt();
pl = po.purerl;
pl.mode = 'scratch'; pl.dwell_s = o.dwell_s; pl.tail_s = o.tail_s;
[pol,dump] = quad_sim.p3_pol_purerl(pl);
fields = {'t','v','x','Phat','Vmeas','Ehat','cmd'};   % = p3_opt.gates.policyFields
polw = @(info) local_chk(info,pol,fields);
runopt = struct('profile','window','maxTime_s',o.T_s,'seed',o.seed, ...
    'wind_profile','phases','windPhases_mps',0, ...
    'phaseBounds_s',[0 o.T_s],'vref_policy',polw);
R = quad_sim.realism_run(c,runopt);
W = dump();
W.T_s = o.T_s; W.E_wh = R.E_wh; W.completed = R.completed; W.seed = o.seed;
fprintf('p3_warmup: T=%g s E=%.3f Wh mu=%.2f sigma=%.3f k=%d completed=%d\n', ...
    o.T_s,R.E_wh,W.mu,W.sigma,W.kStep,W.completed);
end
function v = local_chk(info,pol,fields)
assert(isequal(sort(fieldnames(info)),sort(fields(:))), ...
    'quad_sim:P3Warmup','policy info face has non-whitelist fields.');
v = pol(info);
end
