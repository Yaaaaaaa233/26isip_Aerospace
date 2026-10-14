function bytes = air_quad_telemetry_pack(u)
%AIR_QUAD_TELEMETRY_PACK 商飞-飞控通讯协议遥测第二副帧(0xF2)组帧接口位(P4)。
% 协议:《【20260710】商飞-飞控通讯协议_V1.0》遥测 G 区 5 副帧 x 24 字节, 本函数
%   只组第二副帧(电压/油门/电流), 其余副帧(GPS/高度/报警等)接口位预留 0。
% 输入 u = [bus_V; bus_I; throttle1; throttle2; alarm_bits](5x1);
%   throttle1/2 = 电机 1/2 油门 0..1(4 电机映射见接口文档, 电机 3/4 预留)。
% 输出 bytes = 1x24 double(取值 0..255, 即字节值——Interpreted Fcn 只出 double)。
% 字段映射(表 4.2):
%   Data[0]   = 0xF2 帧标识
%   Data[1:2] = 主电压 U16 小端: bit15=0 选电压1(主电压), bit0~13 电压值 0.1 V
%   Data[3:4] = 转速1/油门1 U16: bit15=1(电动), bit0~13 油门 0.1%(0~1000)
%   Data[5:6] = 转速2/油门2 U16: 同上
%   Data[7]   = 油量/电流 U8: 电动时=电流, 单位 1 A(0~255)
%   Data[8:22]= GPS/状态/报警等接口位(本包装不产, 预留 0; Data[12] 报警字取输入)
%   Data[23]  = 校验和(暂按前 23 字节和 mod 256, 算法以协议原文为准——接口位声明)
% 量化误差 <= 1 LSB(0.1 V / 0.1% / 1 A); 只做组帧不做传输/CRC 分发(后续 SITL/串口)。
u = double(u(:));
assert(numel(u) == 5,'air_quad:Telemetry','u must be [bus_V;bus_I;th1;th2;alarm].');
vRaw = min(16383,round(u(1)*10));              % 0.1 V, bit15=0 -> 主电压1
t1 = min(1000,round(u(3)*1000));               % 0.1% 油门
t2 = min(1000,round(u(4)*1000));
tRaw1 = bitor(32768,t1);                        % bit15=1 电动
tRaw2 = bitor(32768,t2);
iRaw = min(255,round(u(2)));                   % 1 A
alarm = min(255,round(u(5)));
bytes = zeros(1,24);
bytes(1) = 242;                                 % 0xF2
bytes(2) = bitand(vRaw,255); bytes(3) = bitshift(vRaw,-8);
bytes(4) = bitand(tRaw1,255); bytes(5) = bitshift(tRaw1,-8);
bytes(6) = bitand(tRaw2,255); bytes(7) = bitshift(tRaw2,-8);
bytes(8) = iRaw;
bytes(13) = alarm;                              % Data[12] 报警状态字1(1-based 13)
bytes(24) = mod(sum(bytes(1:23)),256);          % 校验和(接口位声明, 见头注)
end
