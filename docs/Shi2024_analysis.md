# Shi2024 算法深度分析报告

> 分析日期：2026-03-17
> 分析文件：`comalg/alg4_Shi2024/Shi2024_main.m`

---

## 问题一：第二轮之后效用曲线为一条直线

### 根本原因：`optimize_coalitions` 的收敛逻辑过于保守

**参数：`Shi_K_stable_max = 10`，`max_inner_iter = 200`**

在 `optimize_coalitions`（第251行）中，稳定性判断逻辑：

```matlab
if isequal_SC(SC, SC_prev_iter)
    k_stable = k_stable + 1;
    if k_stable >= K_len  % K_len = 10
        break;
    end
else
    k_stable = 0;  % 有改进，重置计数器
end
```

**关键问题在于 `Preference_gain` 的接受条件极其严格：**

```matlab
% Transfer: gain_transfer > 0（严格大于0）
% Quit:     gain_quit > 0（严格大于0）
% Join:     gain_join > 0（严格大于0）
```

`Preference_gain` 计算的是包含所有队友效用变化的社会总增益。在第一轮之后，SC 已经通过贪婪初始化形成了一个局部稳定解。**从第二轮开始，信念更新后需求估计更准确，但 SC 结构本身已经稳定**——大多数 agent 的 Quit/Transfer/Join 操作的社会增益都 ≤ 0，导致：

1. 每次迭代几乎没有任何操作被接受
2. `isequal_SC` 立刻返回 true，`k_stable` 快速累积到 10
3. 内循环在约 10 次迭代后退出
4. SC 不变 → 效用不变 → 曲线变成直线

**本质**：第一轮贪婪初始化已经找到了一个在 `Preference_gain > 0` 标准下无法改进的局部最优，后续轮次的信念更新没有改变 SC，因此效用不变。

---

## 问题二：每轮迭代次数比 10 多一点

**直接原因：`k_stable` 需要连续 `K_len=10` 次无变化才退出**

```matlab
while k_iter < max_iterations && k_stable < K_len
    k_iter = k_iter + 1;   % 循环顶部先自增
    ...
    if isequal_SC(SC, SC_prev_iter)
        k_stable = k_stable + 1;
        if k_stable >= K_len
            break;
        end
    else
        k_stable = 0;
    end
end
```

从第二轮开始，SC 几乎不变，所以：

| 迭代次数 | k_stable |
|---------|---------|
| 第1次   | 1       |
| 第2次   | 2       |
| ...     | ...     |
| 第10次  | 10 → break |

退出时 `k_iter = 10`。由于 `k_iter` 在循环顶部先自增，实际执行了 **10次完整迭代**，加上第一轮的初始化（`k_iter=1`），报告出来的数字是 **10~11**，与观察到的"比10次多一点"完全吻合。

对比 Qi2023：`Qi_K_stable_max = 15`，且每轮重置 `k_stable=0`，探索更充分。

---

## 问题三：Shi2024 计算时间远多于 Qi2023 和 OCF

### 原因1：`Preference_gain` 内部嵌套调用 `calc_all_agents_with_global_sync`（最严重）

`Preference_gain` 每次调用 `get_agent_util_proxy`，后者调用 `calc_agent_total_utility`，而 `UtilityEvaluator.m` 第167行：

```matlab
all_agents_results = WorldSim.calc_all_agents_with_global_sync(agents, tasks, Value_Params, SC, tol);
```

**`calc_all_agents_with_global_sync` 是全局时间同步计算，复杂度 O(N×M)。**

在 `optimize_coalitions` 的一次迭代中，`Preference_gain` 被调用的次数估算：

```
Phase 1 (Quit/Transfer):
  N agents × M tasks × K resources × (1次gain_quit + M次gain_transfer)
  = 6 × 10 × 6 × (1 + 10) = 3960 次 Preference_gain 调用

Phase 2 (Join):
  N agents × K resources × M tasks
  = 6 × 6 × 10 = 360 次 Preference_gain 调用
```

每次 `Preference_gain` 内部还对每个队友调用 2 次 `get_agent_util_proxy`，每次都触发 `calc_all_agents_with_global_sync`。

**保守估计：每次迭代调用 `calc_all_agents_with_global_sync` 超过 4000 次。**

> 这违反了 CLAUDE.md Bug 2 规范：
> *错误做法：在每次迭代或每个智能体的效用计算内部调用 `calc_all_agents_with_global_sync`*

### 原因2：`get_SC_hash` 使用 `mat2str` 性能差

```matlab
function hash_str = get_SC_hash(SC)
    temp_vec = [];
    for m = 1:length(SC)
        temp_vec = [temp_vec; SC{m}(:)];  % 动态扩展数组
    end
    hash_str = mat2str(temp_vec);  % 字符串化整个矩阵
end
```

每次禁忌检查都要序列化整个 SC（N×K×M 个数值），且 `is_in_tabu` 用线性遍历字符串比较，复杂度 O(L_tabu)。

### 原因3：Phase 1 的四重嵌套循环

```matlab
for j = 1:N              % 6
  for task_idx           % 最多 M=10
    for k = 1:K          % 6
      for i_trans = 1:M  % 10（Transfer遍历）
        validate_feasibility(...)  % 每次都调用
        Preference_gain(...)       % 每次都调用
```

`validate_feasibility` 本身也调用时间计算，进一步放大开销。

### 与 Qi2023 的对比

| 算法 | 每次迭代 Preference_gain 调用次数 | 倍数 |
|------|----------------------------------|------|
| Qi2023 | ~6次（每 agent 1次） | 1× |
| Shi2024 | >4000次 | **~700×** |

---

## 问题四：效用计算逻辑一致性检查

### 4.1 历史记录口径不一致

Shi2024 的 `record_round_data`（第453行）中混用了两种视角：

```matlab
% total_completed_value：上帝视角（真实需求）
demand = tasks(j).resource_demand(:)';
D_C = WorldSim.calc_task_completion_degree(total_resources, demand, K);
total_completed_value = total_completed_value + tasks(j).value * D_C;

% coalition_utility：信念视角（个体估计）
total_utility = calc_global_utility(SC, agents, tasks, Value_Params, Value_data, AddPara);
% → UtilityEvaluator.calc_agent_total_utility（使用 initbelief）
```

对比 Qi2023（第282行），统一使用上帝视角：

```matlab
[coalition_utility, total_cost, total_completed_value, task_completion_degrees] = ...
    UtilityEvaluator.evaluate_coalition_metrics(SC_global, agents, tasks, Value_Params, eps_val);
```

**结论**：Shi2024 的 `coalition_utility` 字段是信念视角，`total_completed_value` 是真实视角，两者不可直接比较，绘图时会产生误导。

### 4.2 `calc_agent_cost` 重复调用时间同步

`record_round_data` 中（第464行）：

```matlab
for i = 1:N
    agent_cost = calc_agent_cost(i, SC, agents, tasks, Value_Params, tol);
    % calc_agent_cost 内部调用 WorldSim.calc_with_global_sync（单智能体版本）
end
```

对每个 agent 单独调用时间同步，而不是调用一次 `calc_all_agents_with_global_sync`，又是一次性能问题。

### 4.3 `optimize_coalitions` 中 `Value_data.SC` 同步不完整

```matlab
% Phase 1/2 中，只更新了操作智能体 j 的 SC：
SC = SC_cand;
Value_data(j).SC = SC;  % 只更新 j，其他智能体未同步
```

其他智能体的 `Value_data(i).SC` 在迭代中没有同步更新，导致 `Preference_gain` 计算队友效用时使用的是过时的 SC。

对比 Qi2023，每次接受新 SC 后广播给所有智能体：

```matlab
SC_global = SC_new_candidate;
for j = 1:N
    Value_data(j).SC = SC_global;  % 广播给所有智能体
end
```

**这是一个逻辑错误**：Shi2024 在计算队友增益时，队友的 `Value_data.SC` 可能与当前 SC 不一致，导致 `Preference_gain` 计算结果偏差。

### 4.4 `get_agent_util_proxy` 的 `temp_data` 字段不完整

```matlab
function u = get_agent_util_proxy(target_id, target_belief, SC, agents, tasks, params, AddPara)
    temp_data.agentID = target_id;
    temp_data.initbelief = target_belief;
    % 缺少 resources 字段
    u = UtilityEvaluator.calc_agent_total_utility(SC, agents, tasks, params, temp_data, AddPara);
end
```

`temp_data` 缺少 `resources` 字段，若调用链触及 `SA_Select_probs`（访问 `Value_data.resources`）会报错，是潜在脆弱点。

---

## 总结

| 问题 | 根本原因 | 严重程度 |
|------|---------|---------|
| 第2轮后直线 | 贪婪初始化后局部最优，`Preference_gain>0` 条件无法满足 | 算法设计问题 |
| 每轮~10次迭代 | `k_stable` 快速达到 `Shi_K_stable_max=10` | 参数设置问题 |
| 计算时间过长 | `Preference_gain` 内嵌套调用 `calc_all_agents_with_global_sync`，每轮>4000次 | 严重性能问题 |
| 效用口径不一致 | `coalition_utility`（信念视角）vs `total_completed_value`（真实视角）混用 | 数据分析问题 |
| SC同步缺失 | Phase1/2 只更新操作智能体的 `Value_data.SC`，队友未同步 | 逻辑错误 |
