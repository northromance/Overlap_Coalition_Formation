# Shi2024_main 修改建议报告

> 生成日期：2026-03-17
> 定位：作为对比算法，保留 Quit/Transfer/Join 三阶段结构，修复已知问题，提升公平性和效率

---

## 修改原则

Shi2024 作为**对比算法**，修改目标是：
1. 修复明显的逻辑错误，使其能正确运行
2. 与其他算法保持公平的对比条件（信念更新、参数独立）
3. 不改变算法的核心特征（确定性禁忌搜索 + Quit/Transfer/Join）
4. 不引入 SA/Metropolis 等主算法的核心机制（避免算法趋同）

---

## 修改项 1：初始构造去掉正效用门槛

### 问题
`initial_coalition_formation` line 236：
```matlab
if best_task > 0 && best_utility > 0   % ← 问题所在
```
效用为负的智能体不加入任何任务，初始解过于稀疏。

### 修改建议
```matlab
% 修改前
if best_task > 0 && best_utility > 0

% 修改后
if best_task > 0   % 只要找到可行任务就加入，允许负效用（后续迭代可退出）
```

### 理由
- 与 CLAUDE.md Bug1 一致：效用可以为负，不应截断
- 初始解稀疏会导致后续 Phase 1 的 Quit/Transfer 几乎无事可做，算法退化
- Qi2023 和 OCF_SAtabu 的初始构造均无此限制

---

## 作者：效用为负是可以，但是在生成初始解的时候 应该跟QI2023和OCF保持类似的逻辑虽然没有选择概率抽样

## 修改项 3：信念更新默认与其他算法对齐

### 问题
`Shi2024_main.m` line 34：
```matlab
enable_belief_update = false;   % ← 默认关闭
```
Qi2023 和 OCF_SAtabu 默认开启信念更新，对比不公平。

### 修改建议
```matlab
% 修改前
enable_belief_update = false;

% 修改后
enable_belief_update = true;    % 与 Qi2023/OCF_SAtabu 对齐
```

同时，当前 Shi2024 的观测收集只在 `enable_belief_update=true` 时执行（line 98-100），信念更新开启后需确认 `summatrix` 初始化正确。检查 line 61：
```matlab
summatrix = zeros(M, Value_Params.task_type);   % 已正确初始化，无需修改
```

### 理由
- 多轮对比实验中，信念更新是核心机制之一，关闭会使 Shi2024 在后期轮次中使用过时信念，人为降低其性能

---

## 修改项 4：修复 record_round_data 中硬编码 agent 1 信念

### 问题
`record_round_data` line 475：
```matlab
belief = Value_data(1).initbelief(j, :);   % ← 硬编码 agent 1
```
历史记录中的任务完成度基于 agent 1 的信念，信念更新开启后各 agent 信念不同，记录不准确。

### 修改建议
用平均信念替代，或直接用上帝视角需求（与 `evaluate_coalition_metrics` 保持一致）：

**方案A（推荐）：改用真实需求（上帝视角，与最终评估一致）**
```matlab
% 修改前（line 474-480）
for j = 1:M
    belief = Value_data(1).initbelief(j, :);
    demand = WorldSim.calculate_demand_quantile(belief, Value_Params.task_type_demands, confidence);
    ...
    D_C = WorldSim.calc_task_completion_degree(total_resources, demand, K);

% 修改后
for j = 1:M
    demand = tasks(j).resource_demand(:)';   % 直接用真实需求
    ...
    D_C = WorldSim.calc_task_completion_degree(total_resources, demand, K);
```

注意：方案A需要将 `tasks` 传入 `record_round_data`，当前函数签名已有 `tasks` 参数，可直接使用。

**方案B（保守）：改用所有 agent 信念的均值**
```matlab
belief = mean(reshape([Value_data.initbelief], M, [], N), 3);   % M×task_type 均值
belief_j = belief(j, :);
demand = WorldSim.calculate_demand_quantile(belief_j, Value_Params.task_type_demands, confidence);
```

### 理由
- 历史记录的任务完成度应与最终评估口径一致，方便画图分析
- 方案A更简单，且与 `evaluate_coalition_metrics` 完全对齐

---

### 作者 作为最终记录记录任务完成度应该与QI2023和OCF保持一致。


## 修改项 6：Phase 1 Preference_gain 调用优化（性能）

### 问题
Phase 1 中对每个 (agent j, task_p, resource k, transfer目标 i_trans) 四元组都调用一次 `Preference_gain`，而 `Preference_gain` 内部每次都触发 `calc_all_agents_with_global_sync`，计算量极大。

### 修改建议（轻量级）
在 Phase 1 的最外层（每个 agent j 开始前）预计算一次当前 SC 的基准效用，传入 `Preference_gain` 时复用，避免重复计算 `u_n_P`：

当前 `Preference_gain` 内部：
```matlab
u_n_Q = UtilityEvaluator.calc_agent_total_utility(SC_Q, ...)
u_n_P = UtilityEvaluator.calc_agent_total_utility(SC_P, ...)   % ← 每次都重算
```

**修改方案**：在 `Preference_gain` 增加可选的预计算参数（类似 OCF_SAtabu 的 `precomputed_GSU_current`）：
```matlab
% Preference_gain 函数签名扩展（可选第9个参数）
function deltaU = Preference_gain(tasks, agents, SC_P, SC_Q, agentID, Value_Params, Value_data, AddPara, precomputed_u_P)
if nargin < 9 || isempty(precomputed_u_P)
    u_n_P = UtilityEvaluator.calc_agent_total_utility(SC_P, agents, tasks, Value_Params, Value_data, AddPara);
else
    u_n_P = precomputed_u_P;   % 复用预计算值
end
```

然后在 Shi2024 Phase 1 的 agent j 循环开始时预计算一次：
```matlab
for j = 1:N
    Value_data(j).SC = SC;
    u_j_baseline = UtilityEvaluator.calc_agent_total_utility(SC, agents, tasks, Value_Params, Value_data(j), AddPara_silent);
    % 后续所有 Preference_gain 调用传入 u_j_baseline
    gain_transfer = Preference_gain(tasks, agents, SC, SC_temp, j, Value_Params, Value_data(j), AddPara_silent, u_j_baseline);
```

### 注意
- 此修改涉及 `Preference_gain.m`（共享函数），会同时影响 Qi2023
- 建议先确认 Qi2023 的调用方式兼容（`nargin < 9` 兜底保证向后兼容）
- 这是**性能优化**，不改变算法结果

## 作者 不改变Preference_gain原来函数 

