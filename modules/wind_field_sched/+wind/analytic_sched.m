function s = analytic_sched(c, t)
%ANALYTIC_SCHED 解析最优变速调度 v*(t) 与理论最低功率 Pmin(t)（路线公式）。
%   v*(t) = −q + sqrt(q² + V*² − |w|²),  q=t̂ᵀw(t)
% 可行性 |w|≤V*：判别式≥0 → |u*|=V* 精确可达, Pmin≡P*；
%   不可行（横向风分量|w⊥|>V*）→ 最优努力 v*=−q（最小化|u|），Pmin=P0(|w⊥|)。
% 速度边界裁剪后再计算实际可达 Pmin（评价侧口径，含裁剪损失）。
t=t(:)';
[wx,wy]=wind.wind_truth(c,t);
psi=2*pi*t/c.circlePeriod;
q=cos(psi).*wx+sin(psi).*wy;
w2=wx.^2+wy.^2;
% 可行性按逐时刻判别: 横向风分量 |w⊥|≤V* ⟺ q²+V*²−|w|²≥0
% (顺风/逆风对齐段即使 |w|>V* 也能靠调地速使 |u|=V*; 只有横向分量
%  超过 V* 的航向才真正不可达最优)。全周期可行性条件 = max_t|w(t)|<V*。
disc=q.^2+c.Vstar^2-w2;
feasible=disc>=0;
vstar=-q+sqrt(max(disc,0));                % 可行分支（解析最优）
bestEffort=-q;                             % 不可行分支：最小化|u|
vRaw=feasible.*vstar+(~feasible).*bestEffort;
vCmd=min(max(vRaw,c.vLower),c.vUpper);
% 裁剪后的实际 |u| 与可达最低功率
u2=vCmd.^2+2*vCmd.*q+w2;
Pmin=wind.power_curve(sqrt(max(u2,0)),c);
t=t(:); wx=wx(:); wy=wy(:); q=q(:); w2=w2(:); psi=psi(:); feasible=feasible(:);
vCmd=vCmd(:); vRaw=vRaw(:); Pmin=Pmin(:);
s=struct('t',t,'v',vCmd,'vRaw',vRaw,'q',q,'w2',w2,'psi',psi,...
    'wx',wx,'wy',wy,'feasible',feasible,'Pmin',Pmin);
end
