# 代码修改记录

> 日期：2026-03-13
> 涉及算法：Qi2023（对比算法）、OCF_SAtabu_global（主算法）
> 目标：统一参数、对齐迭代逻辑、精简冗余代码

---

## 背景

对比分析 Qi2023 与 OCF_SAtabu_global 后发现以下问题：

1. `resource_confidence` 在候选生成和效用评估中使用了不同来源的值（`AddPara.resource_confidence = 0.95` vs `Value_Params.resource_confidence = 0.7`），导致 delta_u 判断基准不一致。
2. `Preference_gain` 未透传 `AddPara`，内部效用计算缺少正确的参数上下文。
3. Qi2023 的迭代计数粒度为 per-agent（每个 agent 操作 +1），OCF 为 per-sweep（N 个 agent 完整扫一轮 +1），相同 `MaxIter=80` 下 Qi2023 实际搜索量仅为 OCF 的约 1/6，对比不公平。
4. Qi2023 每轮结束未调用 `update_task_schedule`，缺少时序缓存供可视化使用。
5. OCF 哈希函数使用 `sort + strjoin` 字符串拼接，比 Qi2023 的 `mat2str` 开销更大。
6. `update_task_schedule` 依赖 `energy_cost`，对 N 个智能体逐个调用 `calc_with_global_sync`，可合并为一次 `calc_all_agents_with_global_sync`。
7. `validate_feasibility` 共 314 行，其中 `validate_feasibility_simple` 与主函数自身检查逻辑完全重复。

---

## 修改详情

### Fix-1：统一 `resource_confidence` 来源

**问题**：`AddPara.resource_confidence = 0.95`（搜索阶段）和 `Value_Params.resource_confidence = 0.7`（初始构造）并存，导致候选生成与效用评估使用不同置信度，破坏 delta 判断一致性。

**方案**：删除 `AddPara.resource_confidence`，所有地方统一读取 `Value_Params.resource_confidence`，并将其值统一设为 `0.95`。

**修改文件：**

| 文件 | 改动 |
|---|---|
| `Compare_Algorithms.m` | 删除 `AddPara.resource_confidence = 0.95`；`resource_confidence` 改为 `0.95` 并注释说明统一由 `Value_Params` 控制 |
| `Main_fun/calc_gaps.m` | `AddPara.resource_confidence` → `Value_Params.resource_confidence` |
| `comalg/alg3_Qi2023/Qi2023_main.m`（本地 `execute_exchange_operation`） | `AddPara.resource_confidence` → `Value_Params.resource_confidence` |
| `comalg/alg7_OCF_SAtabu/OCF_SAtabu_global_main.m`（`generate_candidate_solution_tabu`） | `AddPara.resource_confidence` → `Value_Params.resource_confidence` |
| `comalg/alg7_OCF_SAtabu/OCF_SAtabu_global_main2.m` | 同上 |
| `comalg/alg4_Shi2024/Shi2024_main.m` | 同上 |
| `comalg/alg1_SA/join_operation.m` | 同上 |

---

### Fix-2：`Preference_gain` 透传 `AddPara`

**问题**：`Qi2023_main.m` 调用 `Preference_gain` 时未传 `AddPara`，导致内部效用计算缺少参数上下文（修复 Fix-1 后尤为重要）。

**修改文件：**

| 文件 | 改动 |
|---|---|
| `Main_fun/Preference_gain.m` | 函数签名增加 `AddPara`（`nargin < 8` 时默认 `verbose=false`）；内部所有 `calc_agent_total_utility` 和 `get_agent_util_proxy` 调用均追加 `AddPara` 参数；`get_agent_util_proxy` 签名同步增加 `AddPara` |
| `comalg/alg3_Qi2023/Qi2023_main.m` | `Preference_gain(...)` 调用追加 `AddPara` |

---

### Fix-3：Qi2023 迭代粒度改为 per-sweep

**问题**：Qi2023 的 `k_iter`、`k_stable`、`Gamma` 在每个 agent 操作后递增，而 OCF 在每次完整 N-agent 扫描结束后递增一次。相同 `MaxIter=80`、`N=6` 时，Qi2023 约做 13 次完整扫描，OCF 做 80 次，实际搜索量相差约 6 倍。

**方案（方案B）**：将 `k_iter`、`k_stable`、`Gamma` 更新及历史记录全部移至 for-i 循环结束后，稳定性判断改为 `isequal(SC_before_sweep, SC_global)`，与 OCF 逻辑对齐。Qi2023 无温度判断，终止条件仅为 `k_iter >= K_max_inner` 或 `k_stable >= K_len`。

**修改文件：**

| 文件 | 改动 |
|---|---|
| `comalg/alg3_Qi2023/Qi2023_main.m` | 重构 while 内循环（约 100 行替换） |

**新循环结构：**

```
while k_iter <= K_max_inner && k_stable <= K_len

    SC_before_sweep = SC_global          ← 记录扫描前状态

    for i = 1:N                          ← N-agent 完整扫描
        A. 离开操作（随机撤出资源）
        B. 引力计算（Qi2023 偏好重力公式）
        C. 交换操作（重新分配资源）
        D. 禁忌检查
        E. 效用检查：delta_u > 0 则接受，否则回滚
    end

    F1. 计算本轮总效用（扫描后统一计算一次）
    F2. isequal 稳定性判断 → k_stable++/=0
    F3. Gamma 更新（per-sweep）
    F4. k_iter++（per-sweep）
    F5. 记录内循环历史
    F6. 定期日志输出

end
```

**效果对比：**

| | 修改前 | 修改后 |
|---|---|---|
| `k_iter` 递增时机 | 每个 agent 操作后 | 每次完整 N-agent 扫描后 |
| `k_stable` 语义 | 连续拒绝的 agent 步数 | 连续无改进的完整扫描次数 |
| `MaxIter=80` 实际扫描次数 | ~13 次 | 80 次（与 OCF 一致）|
| `current_utility` 计算时机 | 每次 agent 接受时 | 每次扫描结束统一计算 |

---

### Fix-4：Qi2023 每轮结束调用 `update_task_schedule`

**问题**：OCF 每轮结束调用 `update_task_schedule` 缓存时序数据供可视化/分析使用，Qi2023 缺少此步骤。

**修改文件：**

| 文件 | 改动 |
|---|---|
| `comalg/alg3_Qi2023/Qi2023_main.m` | 在第 5 步"同步联盟结构"之后插入 `Value_data = update_task_schedule(Value_data, agents, tasks, Value_Params);` |

---

### Fix-6：统一两算法哈希函数

**问题**：OCF 的 `get_SC_hash` 使用 `sort(hash_parts) + strjoin`，需要对每个非零元素构建字符串再排序，复杂度 O(NMK·log(NMK))。Qi2023 使用 `mat2str(temp_vec)`，按固定顺序展开矩阵，无需排序，更简洁高效。

**修改文件：**

| 文件 | 改动 |
|---|---|
| `comalg/alg7_OCF_SAtabu/OCF_SAtabu_global_main.m` | `get_SC_hash` 改为 `mat2str` 固定顺序展开，删除 `sort + strjoin_custom` 逻辑 |

**修改前：**
```matlab
% 逐元素构建字符串 → sort → strjoin（约20行）
hash_parts{end+1} = sprintf('%d-%d-%d-%.4f', m, i, k, amount);
hash_parts = sort(hash_parts);
hash_str = strjoin_custom(hash_parts, '|');
```

**修改后：**
```matlab
temp_vec = [];
for m = 1:Value_Params.M
    temp_vec = [temp_vec; SC{m}(:)];
end
hash_str = mat2str(temp_vec);
```

---

### `update_task_schedule` 重写：移除 `energy_cost` 依赖

**问题**：`update_task_schedule` 对每个智能体逐个调用 `energy_cost`，`energy_cost` 内部再调用 `WorldSim.calc_with_global_sync`，共 N 次独立的全局时间同步计算。而 `WorldSim.calc_all_agents_with_global_sync` 可一次性返回所有智能体的时间数据。

**方案**：重写 `update_task_schedule`，改为调用一次 `calc_all_agents_with_global_sync`，遍历结果写入 `Value_data(i).task_schedule`。能耗在循环内用三项时间乘以对应系数内联计算。

> `energy_cost.m` 文件保留，因为 `validate_feasibility.m` 仍需要它做 per-agent 能量约束检查（需要 `requiredEnergy` 字段）。

**修改文件：**

| 文件 | 改动 |
|---|---|
| `Main_fun/update_task_schedule.m` | 完整重写，314行旧逻辑替换为 ~50 行 |

**修改前后对比：**

| | 修改前 | 修改后 |
|---|---|---|
| 全局时间同步调用次数 | N 次（每个 agent 各调一次 `calc_with_global_sync`） | 1 次（`calc_all_agents_with_global_sync`） |
| 依赖文件 | `energy_cost.m` | 无（直接用 WorldSim） |
| 代码行数 | 39 行 | 50 行（含注释） |

**输出字段不变：**`task_sequence`, `arrival_times`, `start_times`, `mission_end_time`, `execution_times`, `completion_times`, `total_flight_time`, `total_wait_time`, `total_execution_time`, `total_energy`

---

### `validate_feasibility` 精简重构

**问题**：原文件 314 行，存在严重代码重复：`validate_feasibility_simple` 与主函数的自身检查逻辑完全重复（~90 行），另有 `check_teammates_feasibility` 单独封装（~91 行）带来不必要的跳转层级。其他问题：`try/catch` 静默吞掉能量计算错误；`Value_data` 容量检查 fallback 从未生效（`agents` 始终有 `resources`）；大量废弃注释和调试打印残留。

**方案**：合并为 3 个函数，总 96 行：

| 函数 | 说明 |
|---|---|
| `validate_feasibility`（主函数） | 调用 `check_single_agent` 检查自身，再可选地遍历队友逐一调用 `check_single_agent` |
| `check_single_agent` | 单个 agent 的三项检查：非负 → 携带量 → 能量，替代原来两套重复逻辑 |
| `get_teammates` | 4 行矩阵运算找出共同参与任务的其他 agent |

**删除内容：**

| 删除 | 原因 |
|---|---|
| `validate_feasibility_simple`（~90 行） | 由 `check_single_agent` 统一替代 |
| `check_teammates_feasibility` 独立函数（~91 行） | 逻辑内联到主函数 + `get_teammates` |
| `Value_data` 容量检查 fallback | `agents` 始终有 `resources`，fallback 从未生效 |
| `bad_R_agent_Q_size` 维度检查 | `get_agent_resource_matrix` 保证返回正确大小 |
| `agent_not_found` 分支 | agentID 在调用侧始终有效 |
| `try/catch` | 让错误正常抛出，不静默隐藏 |
| 废弃注释和调试 `fprintf` | 清洁代码 |

**保留内容：**

- 外部调用接口签名完全不变（`Value_data` 参数保留，`%#ok<INUSL>` 标记）
- 三条检查顺序不变：非负 → 携带量 → 能量
- 队友检查语义不变（发现首个不可行队友即返回）
- `cost_data` 输出保留（`alg1_SA/join_operation.m` 有引用）

**代码量对比：**

| | 修改前 | 修改后 |
|---|---|---|
| 总行数 | 314 行 | 96 行 |
| 函数数量 | 4 个 | 3 个 |
| 重复逻辑 | ~90 行（`validate_feasibility_simple`）| 0 行 |

---

---

### Fix-7：精英解与搜索起点分离（OCF_SAtabu_global_main.m）

**问题（精英解回滚降低 SA 探索性）**：
- 每轮结束后强制将 `Value_data.SC` 回滚到精英解（信念视角最优）
- 下一轮 SA 从精英解出发，等于每轮都在精英解附近重复搜索，跨轮探索连续性丢失
- 精英解基于信念分位数需求优化，与真实需求的评价指标不一致

**正确逻辑**（用户指出）：
- **观测/信念更新**：用精英解（最佳已知分配），确保信念更新最有信息量
- **历史记录**：记录精英解对应的上帝视角指标（真实完成度）
- **下一轮搜索起点**：用 SA 内循环结束时的轮末状态，保证跨轮探索连续性不被打断

**修改方案**：
1. 在精英解回滚之前保存 SA 轮末状态：`sa_continuation_SC`
2. 精英解回滚 + 观测/信念更新/历史记录照常执行（使用 elite_SC）
3. 记录完成后，将 `Value_data.SC` 恢复为 `sa_continuation_SC`（仅对非最后轮）
4. 最后一轮保持精英解，供最终一致性检查和输出使用

**修改文件：**

| 文件 | 改动 |
|---|---|
| `comalg/alg7_OCF_SAtabu/OCF_SAtabu_global_main.m` | 在轮末插入 sa_continuation_SC 保存/恢复逻辑，约30行 |

---

### Fix-8：精英解更新粒度改为 per-agent（OCF_SAtabu_global_main.m）

**问题**：精英解 `elite_SC` 仅在每次完整 sweep（N-agent 扫描）结束后更新，存在遗漏 sweep 内最优点的问题：
- sweep 内 agent1 接受了一个高 GSU 候选解 → agent2/3 接受劣解（SA Metropolis）→ sweep 末尾状态比 agent1 发现的最优更差
- sweep 末仅更新一次 elite_SC → agent1 发现的 sweep 内最优丢失

**修复**：将精英解更新移至 step 5.3（per-agent accept 块内）：当 `current_GSU > best_GSU` 时，同步更新 `elite_global_utility`、`elite_SC`、`elite_coalitionstru`（`new_coalitionstru` 已在 step 5.1 构建，可直接复用）。sweep 末的精英解更新保留作为兜底。

**修改文件：**

| 文件 | 改动 |
|---|---|
| `comalg/alg7_OCF_SAtabu/OCF_SAtabu_global_main.m` | step 5.3 精英解同步更新，约 5 行 |

---

### Fix-9：删除精英解追踪逻辑，保留 best_GSU 愿望准则（OCF_SAtabu_global_main.m）

**背景**：之前的 Fix-7/8 引入了精英解保留 + `sa_continuation_SC` 双轨机制，但分析表明该机制是 OCF 性能劣于 Qi2023 的主要原因之一（sa_continuation 每轮从退化状态出发，误差跨轮积累）。用户决定彻底清理精英解逻辑，回归更干净的纯 SA 行为，并保留 `best_GSU` 愿望准则。

**删除内容：**
- `elite_SC`, `elite_global_utility`, `elite_coalitionstru` 三个变量及所有更新/使用代码
- 轮末"精英解回滚"块（step 5.3 中的 elite 同步 + 轮末 `final_SC = elite_SC` 回写）
- `sa_continuation_SC` / `sa_continuation_coalitionstru` 保存/恢复块
- `best_SC` 死代码变量（只初始化从不使用）
- `[SA-Done]` / `[SA-Next]` verbose 打印（引用已删变量）

**保留内容：**
- `best_GSU` 初始化 + 在 accept 块内的更新（`if current_GSU > best_GSU → best_GSU = current_GSU`）
- 禁忌表愿望准则：`if current_GSU > best_GSU → accept = true`（核心机制）
- `history_data.best_GSU{counter}` 记录
- verbose 输出改为显示 `BestGSU` 而非 `elite_global_utility`

**修改文件：**

| 文件 | 改动 |
|---|---|
| `comalg/alg7_OCF_SAtabu/OCF_SAtabu_global_main.m` | 删除约 50 行精英/continuation 逻辑，函数整体精简 |

| 文件 | 改动类型 |
|---|---|
| `Compare_Algorithms.m` | 删除 `AddPara.resource_confidence`，`resource_confidence` 值改为 0.95 |
| `Main_fun/calc_gaps.m` | `AddPara.resource_confidence` → `Value_Params.resource_confidence` |
| `Main_fun/Preference_gain.m` | 增加 `AddPara` 参数，透传给内部所有效用计算调用 |
| `Main_fun/update_task_schedule.m` | 完整重写，改用 `calc_all_agents_with_global_sync` |
| `Main_fun/validate_feasibility.m` | 精简重构，314 行 → 96 行 |
| `comalg/alg3_Qi2023/Qi2023_main.m` | Fix-1/2/3/4 四项修改 |
| `comalg/alg7_OCF_SAtabu/OCF_SAtabu_global_main.m` | Fix-1/6 两项修改 |
| `comalg/alg7_OCF_SAtabu/OCF_SAtabu_global_main2.m` | Fix-1 |
| `comalg/alg4_Shi2024/Shi2024_main.m` | Fix-1 |
| `comalg/alg1_SA/join_operation.m` | Fix-1 |

---

## 修改后的算法参数对比

| 参数/行为 | Qi2023（修改后） | OCF_SAtabu_global |
|---|---|---|
| `resource_confidence` 来源 | `Value_Params.resource_confidence = 0.95` | 同左 |
| 效用计算置信度 | 0.95（统一） | 0.95（统一） |
| 迭代单位 | 1次 = N-agent 完整扫描 | 1次 = N-agent 完整扫描 |
| `MaxIter=80` 实际 agent 步数 | 80×N = 480 步 | 80×N = 480 步 |
| 稳定性判断 | `isequal(SC_before, SC_after)` | `isequal(previous_SC, final_SC)` |
| 接受准则 | `delta_u > 0`（贪婪） | Metropolis 概率 |
| 每轮结束时序更新 | `update_task_schedule` ✓ | `update_task_schedule` ✓ |
| 哈希函数 | `mat2str` | `mat2str`（已对齐）|

---

## 2026-03-13（补充）

- `Plot_InnerLoop_Evolution.m`：适配新算法结构与编号，支持按算法名/算法ID/`algX` 选择目标算法，兼容 `enabled_count` 与算法真实 `id` 不一致的结果文件。
- `Plot_InnerLoop_Evolution.m`：绘图标题中的温度参数改为兼容 `alpha`/`T_decay` 两种字段，避免新参数结构下报错。
