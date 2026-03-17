# 算法问题分析报告
日期：2026-03-17
涉及文件：`Huo2025_main.m`, `Qi2023_main.m`, `OCF_SAtabu_global_main.m`, `UtilityEvaluator.m`, `Value_utility.m`, `Preference_gain.m`, `Compare_Algorithms.m`

---

## 问题 1：需求计算方式不一致（Huo2025 vs Qi2023/OCF）【影响公平对比】

**位置**：`Value_utility.m` 第28行 vs `UtilityEvaluator.calc_agent_total_utility` 第185行

Huo2025 内部决策用**期望值法**：
```matlab
demand = belief(1:num_types) * task_type_demands;
```

Qi2023 / OCF 用**分位数法**：
```matlab
demand = WorldSim.calculate_demand_quantile(belief, task_type_demands, confidence);
```

**影响**：期望值 < 分位数（confidence=0.7），Huo2025 低估需求 → 高估完成度 D_C → 高估收益。三算法需求估计基准不统一，对比不公平。

**建议修复**：`Value_utility.m` 改用 `WorldSim.calculate_demand_quantile`，与其他算法对齐。

**作者**：对于Huo2025同样修改采用分位数法 与其他方法保持一致。

## 问题 2：`Value_utility.m` 用单智能体时间同步，等待时间计算不准确（Huo2025）【逻辑错误】

**位置**：`Value_utility.m` 第78行

```matlab
[t_fly, t_wait, t_exec] = WorldSim.calc_with_global_sync(agent_id, orderedTasks, ...)
```

单智能体版本无法知道其他参与者的到达时刻，`ST_m`（任务同步开始时刻）= 该智能体自己的到达时刻，而非所有参与者到达时刻的最大值。违反 Bug 4 修复逻辑，导致 Huo2025 等待成本被低估。

**建议修复**：改用 `WorldSim.calc_all_agents_with_global_sync`，与 `UtilityEvaluator` 保持一致。


**作者**：对于与其他方法保持一致`WorldSim.calc_all_agents_with_global_sync 虽然是不需要重叠联盟执行任务但是 对于每个任务所分配的智能体来说，也同样有等待时间等，与其他算法保持一致。

## 问题 3：`Preference_gain.m` 在 Qi2023 中使用，但队友 belief 始终走兜底逻辑【精度问题】

**位置**：`Qi2023_main.m` 第167行调用 `Preference_gain`；`Preference_gain.m` 第141-146行 `get_belief` 兜底逻辑

Qi2023 从未初始化 `Value_data(i).other`，导致 `get_belief` 每次都走兜底：
```matlab
belief = Value_data.initbelief;  % 用自己的belief代替所有队友的belief
```

**影响**：所有队友效用都用智能体 i 自己的信念估算，偏差随信念分化程度增大，多轮后影响显著。

**建议修复**：Qi2023 在信念广播阶段（第269-275行）已有 `Value_data(i).other{j}.initbelief` 赋值，确认该赋值在 `Preference_gain` 调用之前已执行；或在初始化阶段预填 `other` 字段。

**作者**：Qi2023 在使用 Preference_gain的时候 对于其他机器人的效用我已经在other中保存了下来 这里是没有合理计算是吗，应该使用other其他机器人传过来的字段。

## 问题 4：OCF 主算法 `global_utility_diff` 造成 O(N²) 全局同步调用【性能问题，Bug 2 变体】

**位置**：`OCF_SAtabu_global_main.m` 第151行调用 `global_utility_diff`；`global_utility_diff` 第491-519行

每次内循环迭代，每个 agent 调用一次 `global_utility_diff`，内部对 SC_candidate 和 SC_current 各算一遍 GSU（共 2N 次 `calc_agent_total_utility`），每次内部又调用一次 `calc_all_agents_with_global_sync`：

```
每迭代 = N agents × 2N 次全局同步 = 2N² 次
N=6, MaxIter=200, rounds=50 → 约 72,000 次全局同步
```

**建议修复**：在每次迭代开始前调用一次 `calc_all_agents_with_global_sync`，将结果缓存后传入效用计算，避免重复调用。

**作者**：global_utility_diff 应该是没有问题的 因为每个智能体尝试并产生了新的联盟。但是有一个问题，计算方式是上一个机器人计算完然后将结果传递给下一个机器人。因此如果候选联盟结构没有变化或者当前联盟结构没变的话上一个机器人是不是已经计算了一轮。这里可能有重复计算。整体结构是没有问题的。


## 问题 5：`Tmin` 与 `T_min_round` 混用，后期退出逻辑不清晰【参数混乱】

**位置**：`OCFUtils.init_value_params` 第391行；`OCF_SAtabu_global_main.m` 第44-45行、第259行

`Value_Params.Tmin = 0.01`（SA终止温度，由 `init_value_params` 注入）
`Value_Params.T_min_round = 90`（回合温度下界，由 `Compare_Algorithms.m` 单独注入）

每轮温度重置下界为90，而退出条件判断 `T < 0.01`。`SA_alpha=0.8`，从90降到0.01需约38次迭代，MaxIter=200，温度退出条件在后期轮次（T_min_round=90生效时）**永远不会触发**，内循环只靠 `K_stable_max` 或 `MaxIter` 退出，后期探索能力下降但退出变慢。

**建议**：明确两个参数的语义，或将退出条件改为 `T < Value_Params.T_min_round`，与每轮重置逻辑对齐。

-**作者**：修改该参数我的逻辑是 在内循环中应该采用Tmin这个是内循环降温的，然后 T_min_round 是轮num_round轮间 最低的开始温度 意思是随着博弈轮次的增加。初始温度下降但是要保证一定的探索 T_min_round是每轮的最低开始温度。

## 问题 6：`Compare_Algorithms.m` addpath 路径拼接逻辑脆弱【维护风险】

**位置**：`Compare_Algorithms.m` 第13-21行

```matlab
script_dir = fileparts(mfilename('fullpath'));  % 实际是项目根目录
project_root = fileparts(script_dir);           % 实际是项目根目录的父目录
addpath(fullfile(project_root, "Overlap_Coalition_Formation\Main_fun"));
```

`Compare_Algorithms.m` 位于项目根目录，`script_dir` 即为根目录，`project_root` 是其父目录，再拼接项目名绕了一圈。项目目录改名后路径失效。

**建议修复**：直接用 `script_dir` 拼接子目录，或使用 `OCFUtils.add_project_paths()`。

-**作者**：修复可能出现的路径问题




