# 同步到达机制 (Synchronization Arrival Mechanism)

## 修改概述

在 `Arrive_time` 分支上，`energy_cost.m` 已被修改以支持**多智能体同步到达**机制。

## 核心逻辑

### 1. 判断是否需要同步
**条件**: 如果一个任务由**多个智能体**共同执行（在同一资源类型上有多个智能体分配），则需要同步。

**实现**: `need_sync_for_task(SC, task_idx, N)`
- 检查 `SC{task_idx}` 矩阵
- 统计有多少智能体对该任务有资源分配
- 如果 > 1 个，返回 `true`

### 2. 计算同步时间
**原则**: 任务开始时间 = 联盟中**最晚到达者**的到达时间

**公式**:
```
对于任务 m 的所有参与者 i:
  1. 找出智能体 i 参与的所有任务（从SC结构）
  2. 按priority排序任务序列
  3. 计算从起点到任务 m 的累积时间：
     - 飞行时间：从上一个任务位置到当前任务
     - 执行时间：之前所有任务的执行时间
  
  arrival_time(i) = Σ (飞行时间 + 执行时间) for all tasks before m
  
task_start_time = max(arrival_time(所有参与者))
```

**实现**: 
- `calculate_task_sync_time(...)` - 主函数，计算联盟的同步时间
- `calculate_agent_arrival_time(...)` - 辅助函数，计算单个智能体的到达时间
  - 根据 SC 找出智能体的所有任务
  - 按 priority 排序任务序列
  - 累积计算到目标任务的飞行和执行时间

### 3. 速度调整机制
**逻辑**: 先到的智能体降低速度，确保与最晚者同时到达

**公式**:
```
实际飞行时间(n) = task_start_time - current_time(n)
调整后速度(n) = distance(n→task) / 实际飞行时间(n)
```

**约束**:
- 速度范围: `[v_min, v_max]`，其中 `v_min = 0.3 * v_max`
- 如果计算出的速度 < v_min，则按 v_min 飞行后在任务点等待

## 函数接口变化

### 原接口
```matlab
[t_wait_total, T_exec_total, totalDistance, requiredEnergy, orderedTasks] = ...
    energy_cost(agentIdx, assignedTasks, agents, tasks, Value_Params, R_agent)
```

### 新接口
```matlab
[t_wait_total, T_exec_total, totalDistance, requiredEnergy, orderedTasks, task_arrival_times] = ...
    energy_cost(agentIdx, assignedTasks, agents, tasks, Value_Params, R_agent, SC)
```

**新增参数**:
- `SC`: 资源联盟结构 (cell数组)，用于判断是否需要同步

**新增输出**:
- `task_arrival_times`: 各任务的到达时间向量

**向后兼容**: 如果不传入 `SC` 或 `SC` 为空，则使用原始逻辑（不考虑同步）

## 示例场景

### 场景: 任务 Task 4 需要 2 个无人机协同

**初始状态**:
- 无人机 A: 位置 (10, 20), 空闲时间 T=10, 速度 v=10
- 无人机 B: 位置 (50, 30), 空闲时间 T=12, 速度 v=10
- Task 4: 位置 (100, 50)

**计算过程**:
1. **距离计算**:
   - A → Task4: 距离 = 92.2
   - B → Task4: 距离 = 56.6

2. **理论到达时间**:
   - A: 10 + 92.2/10 = 19.22
   - B: 12 + 56.6/10 = 17.66

3. **同步决策**:
   - 最晚到达 = max(19.22, 17.66) = 19.22
   - Task 4 开始时间 = 19.22

4. **速度调整**:
   - A: 实际飞行时间 = 19.22 - 10 = 9.22s (全速飞行)
   - B: 实际飞行时间 = 19.22 - 12 = 7.22s (降速: v = 56.6/7.22 = 7.84)

5. **能量成本**:
   - A: 飞行成本 = 9.22 × α
   - B: 飞行成本 = 7.22 × α

## 当前局限性与后续改进

### 局限性
1. **执行时间简化**: 当前使用任务的总执行时间 `tasks.duration`
   - 实际上应该根据资源分配 `SC{m}(i,:)` 和 `duration_by_resource` 精确计算
   - 后续可以调用类似的逻辑来计算每个智能体的实际执行时间
   
2. **同步递归**: 当前计算其他智能体到达时间时，没有考虑那些任务本身可能也需要同步
   - 例如：任务A需要同步 → 计算时发现任务B也需要同步 → 递归计算
   - 当前实现是单层计算，未处理多层嵌套同步
   
3. **能量模型简化**: 速度调整后的能量消耗仍按时间计算
   - 实际上低速飞行可能更省能量（需更复杂的物理模型）

### 建议改进方向
1. **精确执行时间计算**: 
   - 在 `calculate_agent_arrival_time` 中集成 `duration_by_resource` 逻辑
   - 根据智能体的实际资源分配计算执行时间

2. **处理嵌套同步**:
   - 当计算其他智能体到达时间时，检查其路径上的任务是否也需要同步
   - 可能需要引入缓存机制避免重复计算

3. **能量模型优化**:
   - 引入速度相关的能量消耗函数: `E = f(v, d)`
   - 可能需要在 `agents` 结构体中添加更多参数

4. **全局时间轴可视化**:
   - 创建函数绘制所有智能体的时间线（甘特图）
   - 显示同步等待点和速度调整区间

## 测试建议

1. **单智能体任务**: 确保不影响原有逻辑
2. **双智能体同步**: 验证速度调整和时间计算
3. **多任务序列**: 测试时间轴的正确推进
4. **边界情况**: 
   - 距离为0
   - 速度极限情况
   - 大量智能体参与

## 相关文件

修改涉及的文件:
- `SA/energy_cost.m` - 核心修改
- `SA/overlap_coalition_self_utility_actual.m` - 调用更新
- `SA/overlap_coalition_self_utility.m` - 调用更新  
- `SA/validate_feasibility.m` - 调用更新

---
**分支**: Arrive_time  
**修改日期**: 2026-01-07  
**修改人**: GitHub Copilot
