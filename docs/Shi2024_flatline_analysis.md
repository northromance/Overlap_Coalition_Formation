# Shi2024 历史演化曲线第2轮后变直线 — 根因分析报告

日期：2026-03-17

---

## 现象描述

在 `Plot_Results.m` 绘制的第三张图（历史演化过程）中，Shi2024 的
`coalition_utility` 和 `total_completed_value` 曲线在第1轮有值，
第2轮之后变成一条水平直线，不再变化。

---

## 根因分析

### 根因1：`optimize_coalitions` 几乎不产生任何移动（最核心原因）

**问题链**：

1. `sample_from_probs` 按概率采样目标任务。
2. Transfer 阶段：`prob_k(task_p) = 0` 后，还额外排除了 `SC_quit` 中已有资源 k 的任务。
   但 `SC_quit` 是把 `task_p` 的资源 k 清零后的副本，其他任务的资源 k 状态与 `SC` 相同。
   **实际上排除的是"智能体 j 在其他任务上已投入资源 k 的任务"**，这没有问题。
3. Join 阶段：排除 `SC{i_excl}(j,k) >= tol` 的任务，即已投入资源 k 的任务。
   **问题在于**：`Qi_Gamma_init = 1`（极低），Boltzmann 分布几乎均匀，
   采样到的目标任务大概率是随机的，不一定有正的 `Preference_gain`。
   `gain > 0` 的条件很严格，大多数采样结果被拒绝。

4. **更关键**：`Shi_K_stable_max = 10`，`max_inner_iter = 200`。
   每次迭代 N×K 次采样（6×6=36次），每次只采样1个目标任务，
   大多数被 `gain > 0` 或禁忌表拒绝。
   **连续10次迭代无任何 SC 变化就触发收敛退出**。
   第2轮开始时 SC 已经是第1轮贪婪初始化的结果，
   禁忌表从上一轮清空（每轮重置），但 SC 本身已经是局部最优，
   概率采样很难找到 `gain > 0` 的移动，**迅速在1~2次迭代内触发 k_stable 收敛**。

**结论**：`optimize_coalitions` 在第2轮及之后几乎立即收敛退出，
SC 不发生任何变化，历史记录的效用值自然是一条直线。

---

### 根因2：禁忌表跨迭代累积但不跨轮重置（加剧收敛）

当前代码：
```matlab
% optimize_coalitions 函数顶部
TabuList = {};  % 每次调用 optimize_coalitions 时重置
```

每轮调用一次 `optimize_coalitions`，禁忌表确实每轮重置。
但在同一轮的迭代内，禁忌表会累积。
由于每轮迭代次数极少（触发 k_stable 就退出），
禁忌表实际上几乎没有起到"避免重复"的作用，
反而在极少数有效移动被接受后，把这些状态加入禁忌，
下一次迭代无法再访问，进一步减少可接受移动数量。

---

### 根因3：`Preference_gain` 的利他项使 `gain > 0` 条件更难满足

`Preference_gain` 计算的是：
```
deltaU = delta_self + sum_gain_new - sum_loss_old + sum_diff_other
```

Transfer 操作（从任务 A 转移到任务 B）：
- `delta_self`：自身效用变化，可能为正也可能为负
- `sum_loss_old`：离开任务 A 的队友损失，**这是负贡献**
- `sum_gain_new`：加入任务 B 的队友收益，可能为正

在 N=6、M=10 的场景下，任务参与者少，
`sum_loss_old` 往往很小（任务 A 可能只有1个参与者即自己），
但 `delta_self` 本身也很小（概率采样的目标任务不一定比当前任务更好）。
**整体 `gain > 0` 的概率很低**，导致大量采样被拒绝。

---

### 根因4：`validate_feasibility` 过滤掉大量候选

`validate_feasibility` 启用了队友检查（`true`），
会验证智能体的能量约束。
在 Transfer 场景下，目标任务可能距离更远，
能量不足导致 `isFeasible = false`，进一步减少有效候选数量。

---

### 根因5：随机退出操作未真正更新全局 SC

当前实现：
```matlab
SC_after_leave = SC;
% ... 随机清零部分资源 ...
Value_data(j).SC = SC_after_leave;
% 预计算概率分布（基于退出后的 SC）
probs_j = Qi2023_Select_probs(...);
Value_data(j).SC = SC;  % 恢复为全局 SC
```

随机退出只影响概率计算的基准，**不改变全局 SC**。
这与 Qi2023 的设计不同——Qi2023 的退出操作会真正修改 `SC_temp`，
然后基于 `SC_temp` 做交换操作，最终通过 `Preference_gain` 决定是否接受整体变化。

Shi2024 当前的退出操作**没有扰动搜索空间**，
只是改变了概率分布的计算基准，实际效果微乎其微。

---

## 问题汇总

| # | 问题 | 影响 |
|---|------|------|
| 1 | `Shi_K_stable_max=10` 过小，概率采样命中率低，迅速触发收敛 | **最主要**，直接导致直线 |
| 2 | `Qi_Gamma_init=1` 过低，概率分布近均匀，采样目标质量差 | 加剧问题1 |
| 3 | `gain > 0` 条件严格（利他项），大量采样被拒绝 | 加剧问题1 |
| 4 | `validate_feasibility` 能量约束过滤大量候选 | 加剧问题1 |
| 5 | 随机退出未真正扰动 SC，探索性不足 | 中等影响 |

---

## 修复建议

### 建议1（立即见效）：提高 `Shi_K_stable_max`

```matlab
% Compare_Algorithms.m
Shi_K_stable_max = 30;  % 从 10 提高到 30，与 Qi2023 的 Qi_K_stable_max 对齐
```

### 建议2：提高 `Qi_Gamma_init` 用于 Shi2024

Shi2024 使用 `Qi_Gamma_init=1` 导致概率近均匀。
可以在 `optimize_coalitions` 内部使用更高的 Gamma：

```matlab
Gamma = max(Value_Params.Qi_Gamma_init, 5);  % Shi2024 内部使用更高 Gamma
```

### 建议3：随机退出改为真正扰动 SC（与 Qi2023 对齐）

将退出操作的结果作为 Transfer/Join 的起点，而不仅仅用于概率计算：

```matlab
% 退出后直接在 SC_after_leave 基础上做 Transfer/Join
% 最终通过 Preference_gain(SC_original, SC_final) 决定是否接受整体变化
```

### 建议4：放宽 `gain > 0` 为 `gain >= -epsilon`（SA 风格）

引入小的接受阈值，允许轻微劣解被接受，增加探索性：

```matlab
if gain_transfer >= -1e-3  % 允许微小劣解
```

---

## 验证方法

修改后运行 `Compare_Algorithms.m`（`algorithms_to_run_ids = [3,4,7]`），
观察：
1. Shi2024 的 `k_iter_per_round` 是否不再固定在 1~2
2. 历史演化曲线是否在第2轮后继续变化
3. 运行时间是否在可接受范围内（不超过 Qi2023 的 2 倍）
