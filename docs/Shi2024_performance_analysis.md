# Shi2024 性能瓶颈分析与优化建议

> 创建日期：2026-03-22
> 问题背景：每轮种子实验耗时约 7 分钟，主要原因是 Shi2024 算法的计算量过大。

---

## 一、当前参数规模

| 参数 | 值 | 含义 |
|------|-----|------|
| `N` | 6 | 智能体数量 |
| `M` | 10 | 任务数量 |
| `K` | 6 | 资源种类数 |
| `num_rounds` | 100 | 总轮数 |
| `max_inner_iter` | 100 | 每轮最大内层迭代次数 |
| `Shi_K_stable_max` | 10 | 稳定性阈值（连续无改进次数） |

---

## 二、调用链结构（核心问题所在）

```
optimize_coalitions()                         [99轮 × 最多100次迭代]
└─ for j = 1:N (6 agents)
   ├─ calc_gaps()                             [每agent 1次]
   ├─ Qi2023_Select_probs()                   [每agent 1次]
   ├─ for task_idx in task_list (≤10)
   │  └─ for k = 1:K (6)
   │     ├─ validate_feasibility()            [每次]
   │     └─ Preference_gain()                 ★ 核心瓶颈
   ├─ for k = 1:K (6)
   │  ├─ validate_feasibility()
   │  └─ Preference_gain()                    ★
   └─ Preference_gain()  [最终门控]            ★

Preference_gain()
├─ calc_agent_total_utility(SC_Q, ...)        → WorldSim.calc_all_agents_with_global_sync()
├─ calc_agent_total_utility(SC_P, ...)        → WorldSim.calc_all_agents_with_global_sync()
├─ for 新任务队友 (new_tasks × teammates)
│  └─ get_agent_util_proxy() × 2              → calc_agent_total_utility() × 2
├─ for 旧任务队友 (source_tasks × teammates)
│  └─ get_agent_util_proxy() × 2
└─ for 稳定任务队友 (stable_tasks × teammates)
   └─ get_agent_util_proxy() × 2
```

---

## 三、瓶颈定量估算

### 3.1 Preference_gain 调用频次

每次内层迭代（单个 agent）：
- Transfer 阶段：`≤ M × K = 10 × 6 = 60` 次
- Join 阶段：`≤ K = 6` 次
- 最终门控：`1` 次
- 合计：**≤ 67 次 / agent / 迭代**

全算法总调用量：
```
99轮 × 100迭代 × 6 agent × 67次 ≈ 397,800 次 Preference_gain
```

### 3.2 每次 Preference_gain 内部的 calc_agent_total_utility 调用

- 自身效用：`SC_Q` 和 `SC_P` 各 1 次 = **2 次**
- 队友效用（BMBT 公式中的 g/h/o 三类）：
  - 假设平均 3 类任务 × 平均 2 个队友 = 6 个队友
  - 每个队友 2 次（SC_Q 和 SC_P）= **12 次**
- 合计：**约 14 次 calc_agent_total_utility / Preference_gain**

### 3.3 calc_agent_total_utility 的缓存失效问题

`UtilityEvaluator.m` 中使用的是 **1-slot persistent 缓存**：
```matlab
persistent cached_SC_util cached_results_util;
if isempty(cached_SC_util) || ~isequal(SC, cached_SC_util)
    cached_results_util = WorldSim.calc_all_agents_with_global_sync(...);
    cached_SC_util = SC;
end
```

在 Preference_gain 内部，代码交替调用 `calc_agent_total_utility(SC_Q, ...)` 和 `calc_agent_total_utility(SC_P, ...)`，**SC 每次都不同，导致缓存命中率接近 0%**。

### 3.4 最终估算

```
WorldSim.calc_all_agents_with_global_sync 总调用次数
≈ 397,800 × 14 = 约 556 万次
```

`calc_all_agents_with_global_sync` 本身复杂度约 O(N × M)，是最重的函数，**这是 7 分钟耗时的根本原因**。

---

## 四、各瓶颈贡献比例（估算）

| 瓶颈 | 估算占比 | 说明 |
|------|---------|------|
| `Preference_gain` 内队友效用计算（g/h/o 三类） | **~60%** | 每次调用 12 次 calc_agent_total_utility |
| `Preference_gain` 内自身效用计算 | **~15%** | 每次 2 次，缓存命中率低 |
| `validate_feasibility()` | **~10%** | 调用频次同 Preference_gain，但开销较轻 |
| `calc_gaps` + `Qi2023_Select_probs` | **~5%** | 每 agent 各 1 次 |
| 其他（isequal_SC、数据结构操作等） | **~10%** | 分摊较小 |

---

## 五、优化建议（按优先级排序）

### 方案 A：减少参数规模（立竿见影，5 分钟→约 2 分钟）

**修改 `Compare_Algorithms.m`：**

```matlab
% 当前值（太慢）
num_rounds     = 100;
MaxIter        = 100;
Shi_K_stable_max = 10;

% 建议值（Shi2024 专属，快约 3-5 倍）
% Shi2024 轮内优化收敛很快，不需要跑满 100 轮
num_rounds     = 30;   % Shi2024 通常 20-30 轮后效用已收敛
MaxIter        = 50;   % 减半，稳定性阈值保底
Shi_K_stable_max = 5;  % 更快触发提前停止
```

> **注意**：`num_rounds` 目前是全局参数，修改会影响所有算法。
> 建议为 Shi2024 单独传入覆盖值，或在 `Shi2024_main.m` 中加 override 逻辑。

---

### 方案 B：修复 Preference_gain 的缓存失效（根本优化，效果最大）

**问题**：1-slot 缓存在 SC_P / SC_Q 交替调用时完全失效。

**解法**：改为 2-slot 缓存（分别缓存最近两个不同 SC 的结果）：

```matlab
% UtilityEvaluator.m 中替换当前 persistent 缓存逻辑
persistent cache_SC cache_results;
if isempty(cache_SC)
    cache_SC = {}; cache_results = {};
end

% 查找缓存（最多 2 个 slot）
hit = false;
for ci = 1:length(cache_SC)
    if isequal(SC, cache_SC{ci})
        all_agents_results = cache_results{ci};
        hit = true; break;
    end
end
if ~hit
    all_agents_results = WorldSim.calc_all_agents_with_global_sync(...);
    if length(cache_SC) >= 2
        cache_SC(1) = []; cache_results(1) = [];  % LRU 淘汰
    end
    cache_SC{end+1} = SC;
    cache_results{end+1} = all_agents_results;
end
```

**预期效果**：在 Preference_gain 的单次调用内，SC_P 和 SC_Q 各只需计算 1 次 WorldSim，后续对同一 SC 的队友效用计算全部命中缓存。
**估算加速比：约 5-8 倍**（取决于平均任务数/队友数）。

---

### 方案 C：在 Transfer/Join 阶段跳过 BMBT 队友效用（近似加速）

**思路**：Transfer 和 Join 阶段只关心"是否值得尝试"，可以先用**仅自身效用差**做快速筛选，只在最终门控（step E）才用完整 BMBT 公式。

```matlab
% Transfer / Join 阶段：只算自身效用差（快速筛选）
gain_quick = u_self(SC_cand) - u_self(SC_working);
if gain_quick <= 0, continue; end

% 最终门控 step E：使用完整 Preference_gain（含 BMBT 队友项）
final_gain = Preference_gain(tasks, agents, SC, SC_working, j, ...);
```

**预期效果**：Transfer/Join 阶段计算量降低约 85%（从 14 次 util 到 2 次），
整体估算加速约 3-4 倍（需配合方案 B 使用效果更佳）。

---

### 方案 D：降低 Preference_gain 队友效用的计算深度

**思路**：BMBT 中对队友的效用估算（`get_agent_util_proxy`）使用的是代理信念，
精度本来就是近似的，可以只对**直接受影响的任务**计算，跳过 stable_tasks（稳定任务）中的队友效用计算。

```matlab
% 当前：stable_tasks 队友也算（sum_diff_other 项）
% 优化：跳过 stable_tasks，只保留 new_tasks 和 source_tasks

% 在 Preference_gain.m 中，注释掉或条件化 section 5
sum_diff_other = 0;  % 近似：忽略稳定任务的蝴蝶效应
```

**预期效果**：若平均 stable_tasks 占所有任务的 50%，可减少约 30% 的队友效用计算量。

---

### 方案 E：减少 validate_feasibility 调用（次要优化）

**当前问题**：`validate_feasibility` 在每次 Transfer/Join 候选时都调用，包含能量约束检查。

**优化**：先做轻量约束检查（资源容量），通过后再做完整检查：

```matlab
% 轻量检查：仅验证资源分配是否超出智能体总量
total_alloc_k = sum(SC_cand{:}(j, k));  % 所有任务对资源k的分配总量
if total_alloc_k > agents(j).resources(k)
    continue;  % 快速拒绝，不调用 validate_feasibility
end
% 通过后再调用完整检查
[isFeasible, ~, ~] = validate_feasibility(...);
```

---

## 六、综合建议

| 方案 | 实现难度 | 预期加速 | 优先级 |
|------|---------|---------|--------|
| A：减少参数规模 | 极低（改参数） | 3-5× | **立即执行** |
| B：2-slot 缓存 | 低（改缓存逻辑） | 5-8× | **高** |
| C：Transfer/Join 用快速自身效用 | 中（改 Preference_gain 调用方式） | 3-4× | **高** |
| D：跳过 stable_tasks 队友效用 | 低（注释掉一段） | 1.3× | 中 |
| E：轻量资源约束预检 | 低 | 1.2× | 低 |

**建议执行顺序**：
1. 先执行 **方案 A**（0 代码改动，立即验证耗时下降）
2. 再实施 **方案 B**（缓存修复，根本性优化）
3. 视效果决定是否追加 **方案 C**

---

## 七、如何单独控制 Shi2024 的轮数（方案 A 的正确实现）

在 `Compare_Algorithms.m` 中，在 Shi2024 专属参数区域添加覆盖：

```matlab
% ========= Shi2024 专属参数 =========
Shi_K_stable_max = 10;
Value_Params.Shi_K_stable_max = Shi_K_stable_max;
Value_Params.Shi_num_rounds = 30;   % 覆盖 Shi2024 使用的轮数，独立于全局 num_rounds
```

然后在 `Shi2024_main.m` 第 32 行改为：

```matlab
% 原来：
num_rounds = Value_Params.num_rounds;

% 改为：
if isfield(Value_Params, 'Shi_num_rounds')
    num_rounds = Value_Params.Shi_num_rounds;
else
    num_rounds = Value_Params.num_rounds;
end
```

---

## 八、相关文件

| 文件 | 关键位置 |
|------|---------|
| `comalg/alg4_Shi2024/Shi2024_main.m` | `optimize_coalitions()` 函数，Line 252-430 |
| `Main_fun/Preference_gain.m` | 队友效用计算，Line 52-118 |
| `Main_fun/UtilityEvaluator.m` | 1-slot 缓存，Line 168-172 |
| `Compare_Algorithms.m` | Shi2024 参数区，Line 119-230 |
