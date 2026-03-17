# Huo2025 k_stable 0/1 震荡分析报告
日期：2026-03-17

---

## 现象描述

`k_stable` 在 0 和 1 之间反复震荡，无法累积到 `K_stable_max`，内循环只能靠 `MaxIter` 退出。

---

## 根本原因：决策阶段与通信阶段的 SC 视图不一致

### 关键时序

```
迭代 t：
  [决策] for ii=1:N → 各 agent 基于自己的本地 SC 独立决策，更新自己的 Value_data(ii).SC
  [通信] SC_before_comm = Value_data(1).SC   ← 此时已是 agent 1 决策后的 SC
         Snapshot_data = Value_data           ← 包含所有人决策后的状态
         广播 winner k 的 SC 给所有人
         SC_after_comm = Value_data(1).SC
  [稳定] isequal(SC_before_comm, SC_after_comm)
```

### 震荡的具体机制

**第 t 轮**（假设 agent 1 是 winner，k_stable = 1）：

- 决策阶段：所有 agent 基于上轮共识 SC 决策，假设所有人都不移动（incremental 全 0）
- 通信阶段：`SC_before_comm = Value_data(1).SC`（未变）
- winner 仍是 agent 1（iteration 最高），`best_k = 1`，agent 1 不被覆盖
- `SC_after_comm = SC_before_comm` → `k_stable = 2` ✓

**第 t+1 轮**（某 agent j 因信念更新后效用变化，决定移动）：

- 决策阶段：agent j 移动，`Value_data(j).SC` 更新，`Value_data(j).iteration += 1`
- 通信阶段：`SC_before_comm = Value_data(1).SC`（agent 1 未动，SC 是旧的）
- winner 变为 agent j（iteration 更高），agent 1 被覆盖为 agent j 的 SC
- `SC_after_comm ≠ SC_before_comm` → `k_stable = 0` ✗

**第 t+2 轮**：

- 所有人基于 agent j 广播的新 SC 决策
- 假设这次没人移动
- `SC_before_comm = Value_data(1).SC`（上轮被 j 覆盖后的 SC）
- 通信后 winner 仍是 agent j，agent 1 再次被覆盖为同一份 SC
- `SC_after_comm = SC_before_comm`（内容相同）→ `k_stable = 1` ✓

**第 t+3 轮**：

- 又有某 agent 因为接收到新 SC 后发现可以移动，iteration 再次增加
- `k_stable = 0` ✗

---

## 核心矛盾：`SC_before_comm` 取的是 agent 1 的决策后状态

```matlab
SC_before_comm = Value_data(1).SC;  % agent 1 决策后的 SC
```

这里有两个问题：

### 问题 A：SC_before_comm 已经包含了 agent 1 本轮的决策结果

`SC_before_comm` 不是"通信前的共识 SC"，而是"agent 1 本轮决策后的 SC"。如果 agent 1 本轮移动了，`SC_before_comm` 就已经是新状态，通信后 winner 若不是 agent 1，`SC_after_comm` 会变成 winner 的旧 SC，反而比 `SC_before_comm` 更旧，导致误判为"有变化"。

### 问题 B：通信协议本身会周期性地引入 SC 变化

每当有任意一个 agent 移动（iteration 增加），它就成为新 winner，下一轮通信就会把它的 SC 广播出去，覆盖 agent 1 的视图，触发 `SC_after_comm ≠ SC_before_comm`，k_stable 归零。

只要系统中还有 agent 在移动（哪怕只有一个），k_stable 就无法连续累积。

---

## 为什么会出现 0/1 交替而不是持续为 0

- **k_stable = 1 的条件**：本轮没有 agent 移动（incremental 全 0），且 winner 不变（agent 1 仍是 winner 或 winner 的 SC 与 agent 1 的 SC 相同）
- **k_stable = 0 的条件**：任意一个 agent 移动，成为新 winner，下一轮通信覆盖 agent 1

在接近收敛时，大多数 agent 不再移动，偶尔有一个 agent 因为接收到新 SC 后发现微小改进而移动，导致 0/1 交替。

---

## 与其他算法（Qi2023/OCF）的本质区别

| 算法 | 稳定性判断对象 | 为什么能收敛 |
|------|--------------|-------------|
| Qi2023/OCF | `isequal(SC_before_sweep, SC_global)` | SC_global 是所有 agent 共享的单一全局变量，决策和通信都直接修改它，before/after 比较的是同一个对象 |
| Huo2025（当前） | `isequal(SC_before_comm, SC_after_comm)` | SC_before_comm 是 agent 1 决策后的局部视图，通信后被 winner 覆盖，两者不是同一语义 |

Qi2023/OCF 中 SC_global 是**集中式单一变量**，所有人读写同一份，before/after 比较天然有意义。Huo2025 是**分布式多视图**，每个 agent 维护自己的 SC，agent 1 的 SC 不能代表全局共识状态。

---

## 结论

k_stable 0/1 震荡**不是收敛逻辑写错了**，而是：

1. **`SC_before_comm` 的语义不对**：应该是"上一轮通信后的共识 SC"，而不是"agent 1 本轮决策后的 SC"
2. **通信协议的接力传播特性**：每次有新 winner 广播都会改变 agent 1 的视图，导致稳定性计数被频繁重置
3. **分布式视图与集中式稳定性判断的矛盾**：用单个 agent 的局部 SC 变化来判断全局是否稳定，在分布式系统中天然不准确

### 修复方向

将 `SC_before_comm` 的采样时机从"决策后"移到"上一轮通信后"（即在 while 循环顶部、决策阶段之前记录），这样比较的才是"上轮共识 SC"与"本轮通信后新共识 SC"的差异，语义才正确：

```matlab
% while 循环顶部（决策之前）
SC_before_sweep = Value_data(1).SC;  % 上轮通信后的共识 SC

% ... 决策阶段 ...
% ... 通信阶段 ...

% 稳定性判断
if isequal(SC_before_sweep, Value_data(1).SC)
    k_stable = k_stable + 1;
else
    k_stable = 0;
end
```

这与 Qi2023 的 `SC_before_sweep = SC_global` 逻辑完全对齐。

---

## 修复实施（2026-03-17）

已在 `Huo2025_main.m` while 循环顶部添加 `SC_before_sweep = Value_data(1).SC`，稳定性判断改为 `isequal(SC_before_sweep, Value_data(1).SC)`，删除原 `SC_before_comm` 变量。修复后无论哪个 agent 移动都能被正确检测。
