# Qi2023 vs OCF_SAtabu_global 对比分析报告

> 生成日期：2026-03-13
> 目的：分析速度差异根因 + Qi2023 潜在问题 + 可修改方案（待人工确认后执行）

---

## 一、为什么 Qi2023 比 OCF_SAtabu_global 快很多

### 1.1 迭代计数粒度不同（**最关键原因**）

| 算法 | k_iter/k_stable 在哪里递增 | MaxIter=80 时实际执行 |
|------|---------------------------|----------------------|
| **Qi2023** | 每个 agent 操作后递增一次（Line 209） | N=6 个 agent × ≈13次外层扫描 = ~80 个 agent 步 |
| **OCF** | 每次外层 while 循环结束递增（Line 300） | 80次外层扫描 × N=6 agent = ~480 个 agent 步 |

**结论**：相同 `MaxIter=80`，OCF 实际做了 **6倍** 于 Qi2023 的 agent 决策步数。

### 1.2 每次候选评估的效用计算量不同

| 算法 | 每次候选评估调用几次 `calc_agent_total_utility` |
|------|------------------------------------------------|
| **Qi2023** | `Preference_gain` ≈ 2（self×2）+ 受影响队友数×2；仅当 `delta_u > 0` 时才追加 N 次全量统计 |
| **OCF** | `global_utility_diff` = **固定 2N 次**（每个候选都算 SC_candidate + SC_current 的全量 GSU）|

对于 N=6：每次 agent 操作 OCF 调用 12 次，Qi2023 调用 2–6 次（平均约 4 次）。

此外，OCF **每次外层 while 结束时**还额外调用 N=6 次计算 `current_utility_global`：

```matlab
% OCF_SAtabu_global_main.m 第 258-260 行
current_utility_global = 0;
for j = 1:Value_Params.N
    current_utility_global = current_utility_global + ...
        UtilityEvaluator.calc_agent_total_utility(...);
end
```

Qi2023 只在接受时才做这个计算。

### 1.3 接受准则不同

- **Qi2023**：`delta_u > 0` 才接受（纯贪婪），收敛快、运行短
- **OCF**：Metropolis 准则，温度高时大量接受劣解，探索时间更长

### 1.4 哈希函数复杂度不同

| 算法 | 哈希函数实现 | 复杂度 |
|------|-------------|-------|
| **Qi2023** | `mat2str(temp_vec)` | O(N·M·K) 矩阵展开 |
| **OCF** | 构建字符串数组 → `sort(hash_parts)` → `strjoin` | O(N·M·K·log(N·M·K)) 含排序 |

### 1.5 OCF 特有的额外开销

- 每次 `accept` 时调用 `OCFUtils.build_coalitionstru_from_SC`（矩阵遍历构建）
- 每轮结束调用 `update_task_schedule`（触发全局时间同步）
- 精英解维护：每次外层循环检查并可能复制 SC  

---

## 二、Qi2023 中发现的潜在问题

### 问题 1：`resource_confidence` 两套参数互相矛盾 ⚠️ 高优先级

**位置**：`Main_fun/UtilityEvaluator.m` 第 153 行

```matlab
% 当前实现：calc_agent_total_utility 使用 Value_Params.resource_confidence
confidence = Value_Params.resource_confidence;  % = 0.7（初始构造置信度）
```

但 `calc_gaps` 和 `execute_exchange_operation` 使用：
```matlab
confidence = AddPara.resource_confidence;  % = 0.95（SA搜索阶段置信度）
```

**后果**：
- 候选生成（`calc_gaps`）用 0.95 估算需求 → 认为任务需求较高
- 效用评估（`calc_agent_total_utility`）用 0.7 估算需求 → 认为任务需求较低
- 两步用不同置信度估算的需求，导致 `varsigma_m`（任务完成度）计算偏差，效用比较失去一致性

**此问题同时影响 Qi2023 和 OCF。**

**修改方案 A（推荐）**：让 `calc_agent_total_utility` 也接受并使用 `AddPara.resource_confidence`，将第 153 行改为：
```matlab
confidence = 0.9;  % 默认值
if nargin >= 6 && isfield(AddPara, 'resource_confidence')
    confidence = AddPara.resource_confidence;
end
```

**修改方案 B（保守）**：统一使用一个置信度，把 `Value_Params.resource_confidence` 改为 0.95，将 `T_init_construction` 阶段改为传入独立参数。

---

### 问题 2：`Preference_gain` 未传 `AddPara` ⚠️ 中优先级

**位置**：`Qi2023_main.m` 第 177 行

```matlab
delta_u = Preference_gain(tasks, agents, SC_global, SC_new_candidate, i, Value_Params, Value_data(i));
```

`Preference_gain` 内部调用 `calc_agent_total_utility` 时没有传 `AddPara`：

```matlab
% Preference_gain.m 第 38-39 行
u_n_Q = UtilityEvaluator.calc_agent_total_utility(SC_Q, agents, tasks, Value_Params, Value_data);
u_n_P = UtilityEvaluator.calc_agent_total_utility(SC_P, agents, tasks, Value_Params, Value_data);
```

以及辅助函数（第 152 行）：
```matlab
u = UtilityEvaluator.calc_agent_total_utility(SC, agents, tasks, params, temp_data);
% 缺少 AddPara 参数
```

**后果**（若按方案 A 修复问题1）：修复后若 `calc_agent_total_utility` 依赖 `AddPara.resource_confidence`，而 `Preference_gain` 不传，就会 fallback 到默认值 0.9，而非正确的 0.95，造成 Qi2023 的 delta_u 计算使用不一致的置信度。

**修改方案**：在 `Preference_gain` 函数签名中增加 `AddPara` 参数，并传递给内部的效用计算调用，同时在 `get_agent_util_proxy` 中也传递。

---

### 问题 3：`Preference_gain` 可能对重叠联盟智能体重复计数 ⚠️ 中优先级

**位置**：`Preference_gain.m`

`Preference_gain` 将任务分为三类（新增/退出/稳定）并遍历每类任务的队友：
- `sum_gain_new`：加入新任务 g 的队友效用变化
- `sum_loss_old`：退出旧任务 h 的队友效用变化
- `sum_diff_other`：稳定任务 o 的队友效用变化

在重叠联盟中，agent j 可能同时参与 agent i 的"新任务 g"和"稳定任务 o"，导致 j 的效用变化被计算两次。

**与 `global_utility_diff` 的比较**：

| 指标 | `Preference_gain` | `global_utility_diff` |
|------|-------------------|----------------------|
| 计算方式 | BMBT 偏好增益公式（分类任务+队友遍历） | GSU(candidate) - GSU(current) = Σ所有 agent 效用差 |
| 重叠联盟处理 | 可能双重计数 | 每个 agent 精确计算一次 |
| 语义 | 近似社会福利增益 | 精确社会福利增益 |

**后果**：Qi2023 在接受/拒绝候选解时使用的 `delta_u` 与 OCF 使用的 `delta_E` 语义不同，且 Qi2023 的 `delta_u` 在重叠联盟场景下可能被高估或低估。

**修改方案**：将 `Preference_gain` 替换为与 OCF 相同的 `global_utility_diff` 方式（遍历所有 agent 求和），消除双重计数，同时统一两个算法的效用判断标准。

> ⚠️ 注意：此修改会改变 Qi2023 的算法语义，需要确认是否符合论文原意（Qi et al. 2023 的 BMBT 准则就是用 Preference_gain，改成 GSU 差值后论文描述上不再准确）。如果目标是**公平对比**，推荐统一；如果要**复现原论文**则保留。

---

### 问题 4：迭代计数语义不对称（公平性问题）⚠️ 中优先级

如第一节所述，Qi2023 的 `MaxIter=80` 实际只执行约 13 次外层扫描（每次 6 agent），OCF 执行 80 次外层扫描（每次 6 agent）。

**参数对比**（当前配置）：

| 参数 | Qi2023 实际含义 | OCF 实际含义 |
|------|----------------|-------------|
| `MaxIter = 80` | 80 个 agent 步（13 外层扫） | 80 外层扫（480 个 agent 步） |
| `K_stable_max = 15` | 15 个连续拒绝 agent 步 | 15 次连续无改进外层扫 |

**修改方案（二选一）**：

- **方案 A（简单）**：将 Qi2023 的 `MaxIter` 改为 `MaxIter * N`（= 480），使实际 agent 步数相同
- **方案 B（彻底）**：修改 Qi2023 内循环结构，使 k_iter/k_stable 在每次完整 N-agent 扫描结束后才递增一次（与 OCF 一致），然后设置相同的 `MaxIter=80`

---

### 问题 5：`execute_exchange_operation` 代码重复 ⚠️ 低优先级

`Qi2023_main.m` 中在 line 366 定义了一个 **本地函数** `execute_exchange_operation`，同时 `alg3_Qi2023/` 目录下也存在同名的独立文件 `execute_exchange_operation.m`。

两者可能逐渐产生差异，维护风险较高。

**修改方案**：确认两个文件是否内容相同，若相同则删除本地副本；若不同则选择一个版本并记录差异原因。

---

### 问题 6：`update_task_schedule` 在 Qi2023 中未调用 ℹ️ 低优先级

OCF 每轮结束会调用 `update_task_schedule(Value_data, agents, tasks, Value_Params)` 更新任务执行时序，而 Qi2023 跳过了这一步。

**后果**：如果时序信息被后续轮次的效用计算隐式依赖，Qi2023 的 `task_sequence`/`start_times` 可能是陈旧值。需确认 `UtilityEvaluator.calc_agent_total_utility` 是否依赖 `Value_data` 中的时序缓存。

---

## 三、需要统一的一致性设置

为保证对比算法在相同框架下公平竞争，以下参数和行为应保持一致：

| 维度 | OCF 当前做法 | Qi2023 当前做法 | 建议统一方式 |
|------|------------|----------------|------------|
| `resource_confidence` 使用 | 两处：`Value_Params.resource_confidence=0.7`（效用计算）和 `AddPara.resource_confidence=0.95`（候选生成）| 同上问题 | 统一：效用计算使用 `AddPara.resource_confidence=0.95` |
| 迭代单位 | 外层 while 扫一圈 = 1次迭代 | 每个 agent 步 = 1次迭代 | 统一外层扫完1轮 = 1次迭代 |
| 稳定性阈值语义 | 15次完整扫描无改进 | 15个agent步无改进 | 统一为外层扫描粒度 |
| 每轮结束时序更新 | 有 `update_task_schedule` | 无 | Qi2023 加上 |
| 效用评估函数 | `global_utility_diff`（精确 GSU 差） | `Preference_gain`（BMBT 近似） | 商榷（见问题3讨论）|

---

## 四、修改方案汇总与优先级

以下方案按"改动大小 × 影响面"排序，**人工确认可接受后再执行**：

### 🔴 必须修复（影响实验正确性）

#### Fix-1：统一 `resource_confidence` 的使用
AddPara中resource_confidence直接去掉 在所有算法以及相应的计算函数中都应该保持相同的参数Value_Params.resource_confidence 采用这个统一控制

#### Fix-2：`Preference_gain` 传入 `AddPara`
- **文件**：`Qi2023_main.m` 第 177 行，`Preference_gain.m` 函数签名
- **改动**：增加 `AddPara` 参数并透传给内部效用调用

---

### 🟡 建议修复（影响公平对比）

#### Fix-3：统一迭代计数粒度
- **方案 B（推荐）**：修改 Qi2023 内循环结构，使 `k_iter`/`k_stable` 在完整 N-agent 扫描后才递增
- **涉及文件**：`Qi2023_main.m` 第 135–234 行（while 内循环结构）
- **注意**：这个一个是计算联盟结构时候，控制单次迭代中最大迭代次数的 一个是判断完整智能体计算之后 算迭代一次 当前联盟结构与之前变化与否 不变次数 统一两个算法的判断逻辑 然后除了Qi2023_main.m`没有温度的判断应该都是一样的

#### Fix-4：`Qi2023` 每轮结束调用 `update_task_schedule`
- **文件**：`Qi2023_main.m`，在第 266 行（第 5 步"同步联盟结构"之后）
- **改动**：加一行 `Value_data = update_task_schedule(Value_data, agents, tasks, Value_Params);`
这个是可能用到后续画图计算的部分 2.update_task_schedule 里面的更新是否还有意义 因为 我之前已经修改了calc_all_agents_with_global_sync函数现在这里又有update_task_schedule 调用energy_cost函数 检查里面的逻辑问题分析
---

### 🟢 可选优化（代码质量）

#### Fix-5：消除 `execute_exchange_operation` 重复
- 确认两份代码是否一致，保留其中一份 我已经去掉了单独的文件 对于一个主代码 其调用函数应该尽量放在其文件中 

#### Fix-6：优化 OCF 哈希函数
- 将 `sort(hash_parts)` 替换为固定顺序遍历（m→i→k），不再需要 sort
- 可略微提升 OCF 速度 让两个算法中的哈希函数同步一致 用计算量最小的那个 

---

## 五、总结

| 议题 | 结论 |
|------|------|
| Qi2023 快的根本原因 | MaxIter 语义不同（per-agent 而非 per-sweep），导致实际搜索量相差 ~6×；加上无概率接受（纯贪婪）、每次仅部分 agent 计算效用 |
| Qi2023 最严重的 bug | `resource_confidence` 在候选生成和效用评估中使用了不同值（0.95 vs 0.7），破坏了接受/拒绝判断的一致性 |
| 公平对比最重要的统一项 | 迭代粒度统一（Fix-3）+ `resource_confidence` 统一（Fix-1/Fix-2）|
| 不修改 Preference_gain 这个是该算法下的独立利他偏好  | 

---

*请确认以上各 Fix 后，我再逐项执行代码修改。*
