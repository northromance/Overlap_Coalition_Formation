# 接受准则对比分析：旧版 vs 论文定义

## 1. 两种准则的代码层面区别

### 旧版（当前代码）
```matlab
delta_GSU = GSU(CS2) - GSU(CS1)

if delta_GSU > 1e-4
    accept = true;          % 全局效用提升 → 确定性接受
elseif delta_GSU < 0
    prob = exp(delta_GSU / T);
    accept = (rand < prob); % 全局效用下降 → 概率接受
end
```

### 论文定义（CS2 ≻ᵢ CS1）
```matlab
delta_u_ii = u_i(CS2) - u_i(CS1)
delta_GSU  = GSU(CS2) - GSU(CS1)

if delta_u_ii > 1e-4 && delta_GSU > 1e-4
    accept = true;          % 两个条件同时满足 → 确定性接受
elseif delta_GSU < 0
    prob = exp(delta_GSU / T);
    accept = (rand < prob); % 全局效用下降 → 概率接受
end
```

---

## 2. "移项后不是一样的吗？" — 不一样

用户的直觉来自：

**论文条件 2 移项推导：**
```
u_i(CS2) - u_i(CS1)  >  Σ_{o≠i}[u_o(CS1) - u_o(CS2)]
=> u_i(CS2) - u_i(CS1) + Σ_{o≠i}[u_o(CS2) - u_o(CS1)] > 0
=> Σ_all [u_o(CS2) - u_o(CS1)] > 0
=> GSU(CS2) > GSU(CS1)
```

移项确实证明：**条件 2 单独 等价于 delta_GSU > 0**。

**但论文的偏好是条件 1 AND 条件 2**，不是只有条件 2：

| 情况 | delta_u_ii | delta_GSU | 旧版接受？ | 论文定义接受？ |
|------|-----------|-----------|-----------|--------------|
| A    | > 0       | > 0       | ✅ 确定性  | ✅ 确定性     |
| B    | **< 0**   | > 0       | ✅ 确定性  | ❌ 概率性     |
| C    | > 0       | **< 0**   | ❌ 概率性  | ❌ 概率性     |
| D    | < 0       | < 0       | ❌ 概率性  | ❌ 概率性     |

**关键差异在情况 B**：智能体 i 自身效用下降，但全局效用提升。

---

## 3. 为什么旧版效用更高？

### 情况 B 是关键：自我牺牲型动作

```
例：智能体 ii 将资源从高收益任务 A 转移到急缺资源的任务 B
- delta_u_ii = -5   （ii 自身利益受损）
- delta_u_其他 = +20 （其他智能体大幅获益，因为任务 B 完成度提升）
- delta_GSU = -5 + 20 = +15
```

| 版本 | 处理方式 | 效果 |
|------|---------|------|
| 旧版 | delta_GSU > 0 → **确定性接受** | 允许"自我牺牲"式移动，系统高效收敛到高全局效用 |
| 论文版 | delta_u_ii < 0 → **只能概率接受** | 此类有益移动大幅减少，探索能力受限 |

### 本质矛盾：理性约束 vs 系统最优

```
旧版 = "无条件全局利他主义"
       智能体会接受任何对集体有利的动作，不管自身是否亏损
       → 更激进的搜索，更高的全局效用

论文版 = "有限制的利他主义"（理性约束）
        智能体必须"自己也不亏"才会确定性配合
        → 更保守，符合博弈论中个体理性约束
        → 但搜索空间受限，最优解可能更低
```

### SA 概率接受能否弥补差距？

情况 B 在论文版中退化为概率接受 `exp(delta_GSU/T)`：
- 高温阶段：prob 较大，能接受一部分
- 低温阶段：`delta_GSU = +15` 时 `prob = exp(+15/T)`... **但代码写的是 `elseif delta_GSU < 0`**

**这里有一个隐含 Bug**：当 `delta_u_ii < 0 且 delta_GSU > 0` 时（情况 B），论文版代码中两个分支都不满足：
```matlab
if delta_u_ii > 1e-4 && delta_GSU > 1e-4  → false（delta_u_ii < 0）
elseif delta_GSU < 0                        → false（delta_GSU > 0）
% ← 什么都不执行，accept 保持 false！
```

**情况 B 在论文版中被完全封死，连概率接受的机会都没有！**

---

## 4. 结论

| | 旧版 | 论文版 |
|---|---|---|
| 接受条件 | delta_GSU > 0 | delta_u_ii > 0 AND delta_GSU > 0 |
| 情况 B（牺牲自己利己他人） | 确定性接受 | **完全拒绝**（不是概率，是 accept=false） |
| 实验效用 | 更高 | 更低 |
| 理论依据 | 无个体理性约束 | 符合 OCF 博弈个体理性 |
| 稳定性概念 | 社会福利最优 | Nash 稳定 / 个体理性稳定 |

### 建议

论文的偏好定义是为了证明**博弈论稳定性**（如 Nash stability），而非追求最高全局效用。

如果目标是**最大化全局效用**（实验性能），旧版更合适。
如果目标是**符合论文中稳定性定义**，用论文版但需补充情况 B 的概率接受逻辑：

```matlab
% 情况 B 的修复：delta_u_ii < 0 但 delta_GSU > 0 时也给概率接受机会
elseif delta_GSU > 0  % 情况 B：全局有益但自身受损
    prob = exp(-delta_u_ii / Value_Params.Temperature); % 用个体损失衡量
    accept = (rand < prob);
```
