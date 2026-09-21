function out = steady_curve(c, V, vv)
%PLANE_QUAD.STEADY_CURVE 四旋翼无风配平稳态 P(v) 解析曲线(Q2 轨 A, M4' 对拍基线)。
% 与 P2 链 3.8 local_curveJV 同式, 差异 = 4 电机单桨无共轴:
%   T_rot(v) = m*g/(4*cos(theta(v))) (含废阻配平俯仰), 受 T_ce(V) 封顶
%   P(v) = 4*( bench(n) - H3_sav(T, v) ) + P_drag(v) + P_aux
% 输出 struct 含 v/P/nPerMotor/satMargin(配平点到 H9 上限的推力裕度)与
%   悬停/谷底锚点 + 谷底二次曲率 k(±1.5 m/s 窗)。
% 口径: quad_placeholder(P4)。
if nargin<1||isempty(c),c=plane_quad.config();end
if nargin<2||isempty(V)
    V=c.battery_n_ser*interp1(c.battery_ocv_soc,c.battery_ocv_cell_V,1);   % 满电
end
if nargin<3||isempty(vv),vv=0:0.05:14;end
n=numel(vv);P=zeros(1,n);nkrpm=zeros(1,n);marg=zeros(1,n);
nce=c.ceiling_kn_rpm_per_V*V;
Tce=max(0,polyval(c.bench_T_coef_desc,nce/1000));   % kgf
for i=1:n
    v=vv(i);
    aD=0.5*c.air_density_kgpm3*c.cda_m2*v^2/c.mass_kg;
    th=atan(aD/c.gravity_mps2);
    TrotKgf=min(c.mass_kg/(c.motor_count*cos(th)),Tce);   % kgf/电机
    marg(i)=1-TrotKgf/Tce;
    nn=local_n_of_t(c,TrotKgf);
    nkrpm(i)=nn;
    bench=polyval(local_p_coef(c,V),nn);
    sav=local_ind_saving(c,TrotKgf*c.gravity_mps2,v);
    Pdrag=0.5*c.air_density_kgpm3*c.cda_m2*v^3;
    P(i)=c.motor_count*(bench-sav)+Pdrag+c.aux_power_W;
end
[Pmin,iv]=min(P);vStar=vv(iv);
msk=vv>=vStar-1.5&vv<=vStar+1.5;
if nnz(msk)>=3
    p=polyfit(vv(msk)-vStar,P(msk),2);k=2*p(1);
else
    k=NaN;
end
out=struct('v',vv,'P',P,'nPerMotor_krpm',nkrpm,'satMargin',marg,'V',V,...
    'Pmin_W',Pmin,'vStar',vStar,'kValley',k,'hoverW',interp1(vv,P,0),...
    'Tce_kgf',Tce,'T_hover_per_motor_kgf',c.mass_kg/c.motor_count);
end
function n=local_n_of_t(c,t)
b=c.bench_T_coef_desc;
r=roots([b(1),b(2),b(3)-t]);r=r(imag(r)<1e-9&real(r)>0);n=min(real(r));
if isempty(n)||~isfinite(n),n=0;end
end
function [vi,vi0]=local_vi(c,T_N,vair)
vi=0;vi0=0;
if T_N<=0||vair<=0,return;end
A=pi*(c.prop_diameter_m^2)/4;k=T_N/(2*c.air_density_kgpm3*A);
vi0=sqrt(k);vi=sqrt((vair/2)^2+k)-vair/2;
end
function sv=local_ind_saving(c,T_N,vair)
[vi,vi0]=local_vi(c,T_N,vair);
sv=max(0,c.h3_induced_gain*T_N*(vi0-vi));
end
function pc=local_p_coef(c,V)
V=min(max(V,c.bench_V_nom(1)),c.bench_V_nom(end));
i=find(c.bench_V_nom<=V,1,'last');j=min(i+1,numel(c.bench_V_nom));
if i==j,pc=c.bench_P_coef(i,:);return;end
w=(V-c.bench_V_nom(i))/(c.bench_V_nom(j)-c.bench_V_nom(i));
pc=(1-w)*c.bench_P_coef(i,:)+w*c.bench_P_coef(j,:);
end
