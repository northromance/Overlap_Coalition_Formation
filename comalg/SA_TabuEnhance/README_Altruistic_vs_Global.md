# 利他主义偏好版本 vs 全局效用版本对比说明

## ? 核心区别

### 1. **计算方式的本质差异**

#### 全局效用差值
```matlab
delta_E_global = Σ[u_i(SC_new) - u_i(SC_old)]  % i=1 to N
                = 全局新效用 - 全局旧效用
```

#### 利他主义偏好差值（单个智能体 ii）
```matlab
delta_E_altruistic = Preference_gain(SC_old, SC_new, ii)
                   = (u_ii_new - u_ii_old)                    % 自身效用变化
                   + Σ(u_teammate_new - u_teammate_old)      % 队友效用变化
```

### 2. **为什么两者不相等？**

**重复计算问题**：
- 智能体A考虑智能体B的效用变化
- 智能体B也考虑智能体A的效用变化
- 如果对所有智能体求和 Preference_gain，会重复计算队友之间的相互影响

**数学表示**：
```
Σ Preference_gain(ii) ≠ Σ u_i(SC_new) - Σ u_i(SC_old)
i=1:N                    i=1:N           i=1:N
```

**示例**：
假设只有2个智能体A和B：
- Preference_gain(A) = ΔuA + ΔuB  (A考虑自己+B)
- Preference_gain(B) = ΔuB + ΔuA  (B考虑自己+A)
- 求和 = 2(ΔuA + ΔuB) ≠ ΔuA + ΔuB (全局效用差)

---

## ? 特赦准则设计

### 方案A：个体利他偏好特赦（已实现）

```matlab
% 每个智能体维护自己的最优利他效用
best_altruistic_utility = zeros(N, 1);

% 特赦条件
current_altruistic_utility = calc_agent_total_utility(SC_new, ii);
if current_altruistic_utility > best_altruistic_utility(ii)
    accept = true;  % 特赦：该智能体的利他效用超过历史最优
end
```

**优点**：
- ? 完全分布式：每个智能体只看自己的历史
- ? 理论一致：特赦标准与决策标准（利他偏好）一致
- ? 避免集中式假设

**理论依据**：
- 智能体决策时考虑队友（利他性）
- 但比较基准是自己的历史经验（个体记忆）
- 类似于"我这次做的决定（包括对队友的考虑）比我以前最好的决定还要好"

### 方案B：全局效用特赦（备选）

```matlab
% 全局最优记录
best_utility_global = Σ u_i(SC_best);

% 特赦条件
candidate_utility_global = Σ u_i(SC_new);
if candidate_utility_global > best_utility_global
    accept = true;  % 特赦：全局效用改进
end
```

**适用场景**：
- 系统有中央协调器
- 智能体可访问全局信息
- 强调系统整体性能

---

## ? 两个版本的适用场景

### 全局效用版本 (`SA_Value_TabuEnhanced_main.m`)
**适用于**：
- 集中式或半集中式系统
- 强调全局最优性
- 智能体有完整信息访问权限
- 类似"中央规划"模式

**决策逻辑**：
```matlab
delta_E = candidate_utility_global - current_utility_global;
if delta_E >= 0 or rand < exp(delta_E/T)
    accept;
end
```

### 利他主义偏好版本 (`SA_Value_TabuEnhanced_Altruistic_main.m`)
**适用于**：
- 分布式多智能体系统
- 强调个体理性和利他性
- 有限信息环境
- 类似"自组织"模式

**决策逻辑**：
```matlab
delta_E_altruistic = Preference_gain(SC_old, SC_new, ii);
if delta_E_altruistic >= 0 or rand < exp(delta_E_altruistic/T)
    accept;
end
```

---

## ? 实验对比建议

### 关键指标对比

1. **最终性能**
   - 全局效用版本可能更优（集中式优势）
   - 利他版本可能接近但通常略低

2. **收敛速度**
   - 全局版本：可能更快（明确目标）
   - 利他版本：可能更慢（分布式探索）

3. **鲁棒性**
   - 全局版本：对信息准确性要求高
   - 利他版本：对局部信息缺失更鲁棒

4. **可扩展性**
   - 全局版本：随智能体数量增加，全局计算成本上升
   - 利他版本：计算成本仅与局部邻居数量相关

### 实验设置示例

```matlab
% 全局效用版本
alg_params.algorithm = 'SA_TabuEnhanced_Global';

% 利他主义版本
alg_params.algorithm = 'SA_TabuEnhanced_Altruistic';

% 其他参数保持一致
alg_params.SA_T0_round = 500;
alg_params.SA_p_leave = 0.1;
alg_params.num_rounds = 5;
```

---

## ? 理论意义

### 利他主义偏好的优势

1. **更真实的建模**
   - 现实中智能体很少有完整全局信息
   - 利他性是社会性生物的自然特征

2. **分布式可实现**
   - 不需要中央协调器
   - 可在通信受限环境下运行

3. **博弈论基础**
   - 接近"不完全信息博弈"的真实场景
   - 可能收敛到分布式纳什均衡

### 全局效用的优势

1. **性能上界**
   - 提供理论最优解的近似
   - 作为分布式算法的性能基准

2. **调试友好**
   - 目标函数明确
   - 容易判断算法是否正确工作

3. **实际可行性**
   - 现代系统通信能力强
   - 云端协调 + 边缘执行的混合架构

---

## ? 论文写作建议

### 如何呈现两个版本

1. **引言阶段**
   - 说明问题既可用集中式也可用分布式方法
   - 引出利他主义在分布式系统中的作用

2. **方法部分**
   - 先介绍全局效用版本（作为基准）
   - 再介绍利他主义版本（作为创新点）
   - 明确说明两者的理论差异

3. **实验部分**
   - 对比两个版本的性能
   - 分析不同场景下的适用性
   - 讨论性能与分布式程度的权衡

4. **贡献声明**
   - "我们提出了基于利他主义偏好的分布式联盟形成算法"
   - "相比集中式方法，该算法在...场景下表现出更好的...性能"

---

## ? 文件说明

- `SA_Value_TabuEnhanced_main.m` - 全局效用版本（原版）
- `SA_Value_TabuEnhanced_Altruistic_main.m` - 利他主义偏好版本（新版）
- 两个版本API完全一致，可直接替换比较
