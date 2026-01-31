# Qi2023 算法能量不足问题分析

## 问题时间
2026-01-31

## 🔴 问题现象

运行 Compare_Algorithms 时，Qi2023 算法的最终一致性检查发现多个智能体能量不足：

```
[检查5] 可行性检查（能量约束）...
  ❌ Agent 1 能量不足: 需要 339.13 > 拥有 317.63
  ❌ Agent 2 能量不足: 需要 428.17 > 拥有 313.06
  ❌ Agent 3 能量不足: 需要 314.09 > 拥有 313.41
  ❌ Agent 4 能量不足: 需要 348.18 > 拥有 303.90
  ❌ Agent 6 能量不足: 需要 408.47 > 拥有 316.07

❌ 检查失败！发现 5 处错误
```

**测试场景：**
- 智能体数：6
- 任务数：10
- 资源类型：6
- 算法：Qi2023（基于偏好引力的禁忌搜索）

---

## 🔍 根本原因分析

### 1. Qi2023 算法的决策机制

**Qi2023 算法特点：**
- 使用 **禁忌搜索（Tabu Search）** 而非 SA 的 join/leave 操作
- 通过 `execute_exchange_operation` 函数直接修改 SC（联盟结构）
- **没有调用 `validate_feasibility` 进行可行性检查**
- **没有启用队友检查机制**

**代码证据：**
```matlab
% Qi2023_main.m 第159行
SC_new_candidate = execute_exchange_operation(i, agents, SC_temp, probs,
                                               Value_Params, Value_data(i), AddPara);

% execute_exchange_operation 函数（第319-388行）
% 功能：根据概率分配资源到任务
% 问题：只检查需求缺口，不检查能量约束
```

### 2. 与 SA_Value 算法的对比

| 特性 | SA_Value | Qi2023 |
|------|----------|--------|
| 决策方式 | join_operation / leave_operation | execute_exchange_operation |
| 可行性检查 | ✅ 调用 validate_feasibility | ❌ 不调用 |
| 队友检查 | ✅ 启用（check_teammates=true） | ❌ 无此机制 |
| 能量约束 | ✅ 决策前检查 | ❌ 决策后才发现 |
| 携带量约束 | ✅ 决策前检查 | ❌ 决策后才发现 |

### 3. execute_exchange_operation 的问题

**当前逻辑（第319-388行）：**
```matlab
function SC_new = execute_exchange_operation(agent_idx, agents, SC_current,
                                              probs, Value_Params, Value_data, AddPara)
    % 遍历资源类型
    for k = 1:K
        % 1. 根据概率选择任务
        selected_task = ...;

        % 2. 计算需求缺口
        expected_demand = WorldSim.calculate_demand_quantile(...);
        can_add = max(0, demand_k - curr_alloc);

        % 3. 如果有缺口，直接投入资源
        if can_add > 0
            SC_new{selected_task}(agent_idx, k) = resource_amt;
        end
    end
    % ❌ 没有检查：
    %   - 智能体的能量是否足够
    %   - 智能体的携带量是否超标
    %   - 队友是否会变得不可行
end
```

**问题：**
1. **只考虑需求缺口**：只要任务有需求缺口，就投入资源
2. **不检查能量约束**：不计算飞行+等待+执行的总能量
3. **不检查携带量约束**：不检查是否超过智能体的资源携带量
4. **不考虑队友影响**：不检查加入任务后是否会导致队友能量超标

---

## 🎯 问题的本质

### SA_Value vs Qi2023 的决策流程对比

**SA_Value（正确）：**
```
智能体决策
  ↓
join_operation / leave_operation
  ↓
validate_feasibility (check_teammates=true)
  ├─ 非负约束检查
  ├─ 携带量约束检查
  ├─ 能量约束检查（energy_cost）
  └─ 队友可行性检查
  ↓
可行 → 接受决策
不可行 → 拒绝决策
```

**Qi2023（有问题）：**
```
智能体决策
  ↓
execute_exchange_operation
  ├─ 计算需求缺口
  └─ 直接投入资源
  ↓
❌ 没有可行性检查
  ↓
最终一致性检查才发现能量超标
```

---

## 💡 解决方案

### 方案1：在 execute_exchange_operation 中添加可行性检查（推荐）

**修改位置：** `Qi2023_main.m` 第319-388行

**修改思路：**
```matlab
function SC_new = execute_exchange_operation(agent_idx, agents, SC_current,
                                              probs, Value_Params, Value_data, AddPara)
    SC_new = SC_current;

    for k = 1:K
        % 1. 选择任务
        selected_task = ...;

        % 2. 尝试投入资源
        SC_candidate = SC_new;
        SC_candidate{selected_task}(agent_idx, k) = resource_amt;

        % 3. 【新增】可行性检查
        [isFeasible, ~, ~] = validate_feasibility(Value_data, agents, tasks,
                                                   Value_Params, agent_idx,
                                                   SC_candidate, true);

        % 4. 只有可行才接受
        if isFeasible
            SC_new = SC_candidate;
            fprintf('  [资源复用] Agent %d -> Task %d | ResType: %d | 可行 ✓\n',
                    agent_idx, selected_task, k);
        else
            fprintf('  [拒绝投入] Agent %d -> Task %d | ResType: %d | 不可行 ✗\n',
                    agent_idx, selected_task, k);
        end
    end
end
```

**优点：**
- 在决策时就阻止不可行的资源分配
- 启用队友检查，防止影响其他智能体
- 与 SA_Value 的逻辑一致

**缺点：**
- 需要修改 Qi2023 的核心逻辑
- 可能影响算法的收敛速度

---

### 方案2：在禁忌搜索的接受条件中添加可行性检查

**修改位置：** `Qi2023_main.m` 第165-193行

**修改思路：**
```matlab
if ~is_tabu
    % E. 效用检查
    delta_u = Preference_gain(...);

    % 【新增】可行性检查
    all_feasible = true;
    for j = 1:N
        [isFeasible, ~, ~] = validate_feasibility(Value_data, agents, tasks,
                                                   Value_Params, j,
                                                   SC_new_candidate, false);
        if ~isFeasible
            all_feasible = false;
            break;
        end
    end

    % 只有效用提升且所有智能体可行才接受
    if delta_u > 0 && all_feasible
        SC_global = SC_new_candidate;
        ...
    end
end
```

**优点：**
- 不修改 execute_exchange_operation 的逻辑
- 在全局层面检查可行性

**缺点：**
- 需要检查所有智能体，计算开销大
- 可能导致大量候选解被拒绝

---

### 方案3：调整能量预算（治标不治本）

**修改位置：** `Main_fun/Compare_Algorithms.m` 第49行

```matlab
修改前：agent_Emax_min = 300;
修改后：agent_Emax_min = 500;  % 增加能量预算
```

**优点：**
- 简单快速

**缺点：**
- 治标不治本，只是掩盖问题
- 改变了算法的公平对比条件
- 不符合实际应用场景

---

## 📊 推荐方案

### 推荐：方案1（在 execute_exchange_operation 中添加可行性检查）

**理由：**
1. **根本解决问题**：在决策时就阻止不可行的分配
2. **启用队友检查**：防止影响其他智能体
3. **与 SA_Value 一致**：保持算法间的公平对比
4. **符合实际应用**：真实场景中智能体必须考虑能量约束

**实施步骤：**
1. 修改 `execute_exchange_operation` 函数
2. 在投入资源前调用 `validate_feasibility`
3. 只接受可行的资源分配
4. 添加调试信息以便追踪

---

## 🔄 与 SA_Value 问题的对比

### SA_Value 的问题（已修复）
- **原因**：变量命名不一致（T_exec_total vs t_exec_total）
- **影响**：执行能量被漏算，导致能量需求被低估
- **修复**：统一变量命名为小写 t_exec_total

### Qi2023 的问题（待修复）
- **原因**：决策过程中没有调用可行性检查
- **影响**：不可行的资源分配被接受，最终检查才发现
- **修复**：在 execute_exchange_operation 中添加可行性检查

### 共同点
- 都是在决策过程中没有正确检查能量约束
- 都导致最终一致性检查发现大量能量超标
- 都需要在决策时就阻止不可行的操作

---

## ✅ 总结

### 问题本质
**Qi2023 算法在资源分配决策时没有调用 validate_feasibility 进行可行性检查，导致不可行的资源分配被接受。**

### 关键差异
| 算法 | 决策机制 | 可行性检查 | 队友检查 |
|------|----------|-----------|---------|
| SA_Value | join/leave | ✅ | ✅ |
| Qi2023 | execute_exchange | ❌ | ❌ |

### 推荐修复
**在 `execute_exchange_operation` 函数中，每次投入资源前调用 `validate_feasibility` 进行可行性检查（包括队友检查）。**

### 预期效果
```
修复前：
  - 决策时不检查可行性
  - 最终不可行率：50-80%
  - 队友检查：无

修复后：
  - 决策时检查可行性
  - 最终不可行率：5-15%
  - 队友检查：生效
```

**等待用户指令后进行修复。** 🎯
