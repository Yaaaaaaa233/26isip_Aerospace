# 同组模块接入接口

## 1. 环境适配器

适配器是普通MATLAB结构体：

```matlab
adapter.name  = 'teammate_circle_model_v1';
adapter.reset = @resetModel;
adapter.step  = @stepModel;

[state,sample] = adapter.reset(seed,c);
[state,sample] = adapter.step(state,v_ref,dt);
speedrl.validate_adapter(adapter,c);
```

`state` 完全由模型提供者管理，可以包含Simulink状态、风场生成器或数据回放游标。RL不会读取它。`step` 必须因果执行：应用当前 `v_ref` 推进 `dt` 后返回这一时刻可获得的测量。

必需sample字段：

| 字段 | 尺寸/单位 | 规则 |
|---|---|---|
| `time_s` | 标量，s | 接收端当前时刻，单调递增 |
| `ground_velocity_ne_mps` | 2×1，m/s | N/E二维地速 |
| `wind_velocity_ne_mps` | 2×1，m/s | 观测风；不可用时为NaN |
| `wind_sample_time_s` | 标量，s | 风的原始采样时刻，不是到达时刻 |
| `power_w` | 标量，W | 电池端观测功率，可带噪声/延迟 |
| `power_sample_time_s` | 标量，s | 功率原始采样时刻 |
| `voltage_v`、`soc` | 标量 | 不可用时可为NaN |
| `path_phase_rad` | 标量，rad | 直线可固定为0 |
| `path_tangent_ne` | 2×1 | 必须为单位向量 |
| `radial_error_m` | 标量，m | 直线或未建模时可为0 |
| `velocity_valid` | logical | 速度质量与新鲜度 |
| `wind_valid` | logical | 风质量与新鲜度 |
| `power_valid` | logical | 功率质量与新鲜度 |

允许添加 `sample.evaluator` 存放真实功率、真实风等评分数据，但 `speedrl.context` 会将其丢弃。不得把真实最优速度或未来风复制到必需字段中。

## 2. 基准模块

基准函数只接收清洗后的测量context：

```matlab
baseline.name = 'global_multipeak_solver';
baseline.reference = @reference;

function [v,info] = reference(ctx)
    % ctx中只有当前/历史测量派生量，没有环境真实最优点。
    v = ...;
    info = struct('method','global_search_v1');
end
```

返回值必须是一个速度标量。最终边界和变化率仍由RL工程统一处理。

多峰模块应在内部完成全局候选搜索并返回当前选中的 `v_base`。如果候选谷点切换会产生抖动，模块自身应提供滞回或切换成本；不要把完整功率曲线塞进TD3观测。

圆周解析模块可以使用当前相位、切向/法向观测风和已知解析参数，但不得读取仿真器未来风数组。当前工程中的 `wind_analytic` 仅是简化空速曲线的接口样例，不是同学最终解析解。

## 3. 时间与坐标约定

全部二维向量顺序为 `[North; East]`。相对气流统一为：

```matlab
air_velocity_ne = ground_velocity_ne - wind_velocity_ne;
air_speed = norm(air_velocity_ne);
wind_tangent = dot(wind_velocity_ne,path_tangent_ne);
normal = [-path_tangent_ne(2);path_tangent_ne(1)];
wind_normal = dot(wind_velocity_ne,normal);
```

传感器延迟不能通过把旧功率配给未来真值来“修复”。适配器应保留各信号采样时间；策略使用历史观测处理未知动态。

## 4. 推荐合并顺序

1. 用 `validate_adapter` 检查字段、尺寸和切向量。
2. 固定 `delta_v=0`，确认新环境的基准速度、功率和轨迹能够跑完整回合。
3. 使用解析脚本或同学的解析基准，确认相对固定速度确实存在可复现实验差异。
4. 再挂接TD3，并使用与基准完全相同的种子、噪声和初始条件。
5. 环境变更后先重新训练，不能直接把旧策略的结果称为新模型验证。
