function env = make_environment(c)
%MAKE_ENVIRONMENT 模块1/3：environment(风的模型+环境扰动)。
% 任务2口径的静态崎岖对象当前不含风；本模块为任务3-5的风场预留统一接口：
%   wind(t) -> [wx wy]   环境风矢量(地坐标)
% 当前实现：恒零风 + 可选阵风脉冲位(默认关闭)。功率崎岖项视为机体-
% 功率特性的组成部分(见 aircraft.power_at)，不属环境。
% 因果边界：environment 的真值(风/曲线)只进评价日志，不进控制台。
env=struct('wind',@wind,'config',c);
    function w=wind(t)
        % 返回时刻 t 的风矢量(行向量)。任务2静态场景恒零风。
        w=[0 0];
        %#ok<NASGU>  % t 预留给任务3-5: 常值风/正弦风/二维矢量风
    end
end
