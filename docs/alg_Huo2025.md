# Huo2025 算法说明

## 概述

Huo2025 是一个**非重叠联盟形成**对比算法（算法 ID = 2）。
每个智能体只能加入一个任务，并将全部资源投入该任务（非重叠约束）。

---

## 改造背景

### 原始版本的问题

原始实现采用**并发决策 + 共识协议**结构：

1. 所有智能体同时调用 `Value_order` 独立决策
2. 通信阶段以"迭代版本号最高者"广播其联盟结构
3. 所有人同步到该广播视图

这导致多智能体之间产生**循环博弈**（A 移向任务 2，B 移向任务 1，下轮反转），
内循环在 `max_inner_iter` 前无法收敛，计算极慢且结果不稳定。

### 改造方案

仿照 Qi2023 的**顺序扫描**结构：

- 每个智能体依次决策（agent 1 → agent 2 → … → agent N）
- 每次决策后**立即更新** `SC_global`，后续智能体看到的是最新状态
- 彻底消除并发博弈震荡

---

## 文件结构

| 文件 | 说明 |
|------|------|
| `Huo2025_main.m` | 主入口：初始化、外层轮循环、内层顺序扫描、轮末评估 |
| `Value_order.m` | 单智能体决策：What-If 遍历所有任务，选最优，返回更新后的 SC_global |
| `Value_utility.m` | 效用计算（未修改）：基于信念的期望收益 - 时间成本 |
| `StateTran.m` | 状态转移（未修改，位于 Main_fun/）：计算迁移后的 SC 变化 |

---

## 算法流程

### 初始化

```
1. 每个智能体状态初始化（信念均匀分布，SC 全零）
2. 随机初始分配：每个智能体随机选一个任务，全部资源投入
3. 同步 SC_global 到所有 Value_data
```

### 外层轮循环（counter = 1 .. num_rounds）

```
1. 记录当前信念快照（用于画图）
2. 内循环：顺序扫描联盟形成
3. 轮末：观测 + 信念更新 + 评估 + 记录历史
```

### 内循环（顺序扫描）

```
while true
    SC_before_sweep = SC_global

    for i = 1..N
        [SC_global, moved] = Value_order(...)   % 智能体 i 决策
        if moved → 广播 SC_global 给所有 Value_data
    end

    稳定性判断：isequal(SC_before_sweep, SC_global)
        是 → k_stable++
        否 → k_stable = 0

    记录内循环历史（效用、k_stable）
    k_iter++

    终止条件：k_stable >= K_stable_max  OR  k_iter >= max_inner_iter
end
```

### Value_order 单智能体决策（含禁忌）

```
1. 扫描 SC_global，找当前任务 cur_task（全零行 → Void）
2. 计算基准效用 cur_utility
3. What-If 遍历 j = 1..M（跳过 cur_task）：
   - 用 StateTran.calc_move_changes 构造候选 SC
   - 禁忌检查：hash(SC_candidate) 在 TabuList 中 → 跳过
   - 用 Value_utility 计算候选效用
   - 记录最优 best_task / best_utility
4. 若 best_utility > cur_utility → 执行迁移，moved = true
                                    将新 SC hash 加入 TabuList（FIFO，长度 Qi_L_tabu）
   否则 → 保持不动，moved = false
```

---

## 关键设计决策

### 决策标准：全局效用增量

`Value_order` 不使用个体效用作为决策标准，而是计算**所有智能体效用之和**的变化：

```
cur_global  = Σ_n u_n(SC_global)
cand_global = Σ_n u_n(SC_candidate)
接受条件：cand_global > cur_global
```

原因：个体贪婪（只看自身效用）会导致智能体移走后，原任务联盟完成度下降，
其他队友效用损失超过自身收益，全局效用净下降。

信念代理：`huo_calc_global_utility` 用当前智能体 `Value_data_i.initbelief` 代理所有智能体的信念。
初始阶段信念均匀分布，差异可忽略；后期信念收敛后各智能体信念趋于一致，代理误差小。

### 禁忌机制（与 Qi2023 一致）

禁忌表在每轮开始时重置，在整个内循环中跨智能体共享（由 `Huo2025_main` 管理并逐次传入 `Value_order`）。

- hash 计算：将 SC 所有矩阵展平拼接后调用 `mat2str`
- 禁忌检查：候选 SC 的 hash 在表中则跳过，即使效用更高
- 禁忌更新：接受移动后将新 SC hash 加入表尾（FIFO 队列）
- 表长上限：`Value_Params.Qi_L_tabu`（与 Qi2023 共用同一参数）
- 每轮重置：防止历史禁忌跨轮干扰新一轮的搜索

### 非重叠联盟约束
`StateTran.calc_move_changes` 执行的是"整体迁移（Switch）"：
从当前任务撤出全部资源，全部投入目标任务。
智能体在任意时刻只出现在一个任务的 SC 矩阵中。

### What-If 污染防护
每次试探任务 j 前，都从原始 `SC_global` 重新构造 `tmp_vd`，
确保各候选任务的评估相互独立，不会因试探顺序影响结果。

### 不考虑主动进 Void
顺序扫描版本不将 Void（M+1）纳入 What-If 遍历。
初始化已保证每个智能体都在某个真实任务中，
算法只在真实任务间寻找更优选择。

---

## 调试输出（AddPara.verbose = true）

| 位置 | 输出内容 |
|------|---------|
| 初始化后 | `[Huo2025] 初始化完成：N=x, M=x, K=x, 轮数=x` |
| 每轮开始 | `[Huo2025] === 第 x/x 轮 ===` |
| 每10次迭代 | `[Huo2025]   迭代 x: 效用=x, k_stable=x` |
| 每轮收敛 | `[Huo2025] 第 x 轮收敛（稳定/达到最大迭代），迭代次数=x，最终效用=x` |
| Value_order 每次决策 | Agent x 当前任务/效用，以及迁移或保持的结果 |

---

## 参数依赖（来自 Value_Params）

| 参数 | 用途 |
|------|------|
| `N, M, K` | 场景维度 |
| `num_rounds` | 外层轮数 |
| `max_inner_iter` | 内循环最大迭代次数 |
| `K_stable_max` | 稳定性阈值（连续无变化次数） |
| `resource_confidence` | 需求分位数置信度（传入 Value_utility） |
| `seed` | 随机种子 |

---

## 一致性检查

轮末调用 `check_coalition_consistency(..., 'Non-OCF', ...)`，
验证每个智能体只出现在一个任务中（非重叠约束）。
