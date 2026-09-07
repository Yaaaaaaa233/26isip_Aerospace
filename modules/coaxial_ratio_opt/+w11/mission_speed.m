function V = mission_speed(p, t)
%MISSION_SPEED 任务飞行速度(白名单内知识: 固定速度任务是任务书参数, 非寻优对象真值)。
% 控制器用同一闭式死推航向 ψ̂'=V(t)/R; 对象侧(scenario/make_plant)同式生成真航向。
switch p.flightMode
    case 'hover', V=0;
    case 'fixed', V=p.fwdSpeed;
    otherwise,    V=p.fwdSpeed+p.varyAmp*sin(p.varyOmega*t);
end
end
