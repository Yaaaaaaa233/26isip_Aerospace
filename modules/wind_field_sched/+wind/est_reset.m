function est = est_reset(c)
%EST_RESET 在线风估计器状态初始化（滑窗LM，估二维风矢量 ŵ=(ŵx,ŵy)）。
% 模型：对窗口内每个样本 k，P0(|v_k·t̂_k + ŵ|) ≈ Pm_k；
% 滑窗长度 estWindow（等效带宽=1/窗长，任务4带宽设计准则的扫描变量）。
est=struct('V',zeros(1,0),'psi',zeros(1,0),'Pm',zeros(1,0),...
    'theta',[0;0],'window',c.estWindow,'lm',c.estLmDamp,'Vstar',c.Vstar,...
    'Pstar',c.Pstar,'b',2*(1-c.Pstar),'filled',0);
end
