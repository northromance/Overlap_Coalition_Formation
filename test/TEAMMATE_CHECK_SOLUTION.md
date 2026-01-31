# "队友检查"方案：在validate_feasibility中保证全局可行性

## 核心思想 💡

> "在加入或离开一个任务时，不仅检查自己是否可行，还要检查队友是否仍然可行"

**这是一个主动预防策略！**

```
传统方式：
  Agent 1 加入 Task 5
  → 只检查 Agent 1 是否可行 ✓
  → 不管对队友的影响 ✗

队友检查方式：
  Agent 1 加入 Task 5
  → 检查 Agent 1 是否可行 ✓
  → 检查 Task 5 中已有的队友是否仍可行 ✓
  → 如果队友变得不可行，拒绝加入 ✓
```

---

## 方案设计

### 1. 核心逻辑

```matlab
function [isFeasible, info, cost_data] = validate_feasibility(
    Value_data, agents, tasks, Value_Params, agentID, SC,
    check_teammates)  % 新增参数：是否检查队友

    %% 第1步：检查自己
    [isFeasible_self, info, cost_data] = check_self_feasibility(...);

    if ~isFeasible_self
        isFeasible = false;
        return;
    end

    %% 第2步：检查队友（新增）
    if check_teammates
        [isFeasible_teammates, affected_agents] = check_teammates_feasibility(
            agentID, SC, agents, tasks, Value_Params);

        if ~isFeasible_teammates
            isFeasible = false;
            info.reason = 'teammates_would_become_infeasible';
            info.affected_agents = affected_agents;
            return;
        end
    end

    isFeasible = true;
end
```

### 2. 队友检查函数

```matlab
function [all_feasible, affected_agents] = check_teammates_feasibility(
    agentID, SC, agents, tasks, Value_Params)
% CHECK_TEAMMATES_FEASIBILITY 检查队友是否仍然可行
%
% 输入：
%   agentID - 当前决策的智能体ID
%   SC      - 提议的新联盟结构（包含agentID的决策）
%   agents, tasks, Value_Params - 标准参数
%
% 输出：
%   all_feasible     - 所有队友是否都可行
%   affected_agents  - 受影响的智能体列表（不可行的）

    all_feasible = true;
    affected_agents = [];
    tol = 1e-9;

    N = Value_Params.N;
    M = Value_Params.M;

    %% 找出所有队友
    % 队友定义：在SC中与agentID参与相同任务的其他智能体
    teammates = [];

    for j = 1:M
        if isempty(SC{j}), continue; end

        % 检查agentID是否参与任务j
        if agentID <= size(SC{j}, 1) && any(SC{j}(agentID, :) > tol)
            % 找出任务j的其他参与者
            for i = 1:N
                if i ~= agentID && i <= size(SC{j}, 1)
                    if any(SC{j}(i, :) > tol)
                        teammates = [teammates, i];
                    end
                end
            end
        end
    end

    % 去重
    teammates = unique(teammates);

    if isempty(teammates)
        return;  % 没有队友，直接返回
    end

    fprintf('      [队友检查] Agent %d 的队友: [%s]\n', ...
        agentID, num2str(teammates));

    %% 检查每个队友
    for idx = 1:length(teammates)
        teammate_id = teammates(idx);

        % 为队友创建临时Value_data
        % 注意：这里需要队友的完整状态，但我们只有SC
        % 简化方案：只检查能量约束

        [feasible, info, cost_data] = validate_feasibility_simple(
            teammate_id, SC, agents, tasks, Value_Params);

        if ~feasible
            all_feasible = false;
            affected_agents(end+1) = teammate_id;

            fprintf('      ⚠️  队友 Agent %d 会变得不可行: %s (能量: %.2f/%.2f)\n', ...
                teammate_id, info.reason, ...
                cost_data.requiredEnergy, agents(teammate_id).Emax);
        end
    end

    if all_feasible
        fprintf('      ✅ 所有队友仍然可行\n');
    else
        fprintf('      ❌ %d 个队友会变得不可行\n', length(affected_agents));
    end
end
```

### 3. 简化的可行性检查（避免递归）

```matlab
function [isFeasible, info, cost_data] = validate_feasibility_simple(
    agentID, SC, agents, tasks, Value_Params)
% VALIDATE_FEASIBILITY_SIMPLE 简化的可行性检查（不检查队友）
%
% 用于队友检查，避免递归调用

    info = struct('reason', '');
    cost_data = struct();
    isFeasible = true;
    tol = 1e-9;

    agentIdx = agentID;

    %% 1. 提取资源分配
    R_agent = OCFUtils.get_agent_resource_matrix(SC, agentID, Value_Params);

    %% 2. 非负约束
    if min(R_agent(:)) < -tol
        isFeasible = false;
        info.reason = 'negative_allocation';
        return;
    end

    %% 3. 携带量约束
    if isfield(agents(agentIdx), 'resources')
        cap = agents(agentIdx).resources(:)';
        if length(cap) < Value_Params.K
            cap = [cap, zeros(1, Value_Params.K - length(cap))];
        else
            cap = cap(1:Value_Params.K);
        end

        maxAllocByType = max(R_agent, [], 1);
        if any(maxAllocByType - cap > tol)
            isFeasible = false;
            info.reason = 'capacity_exceeded';
            return;
        end
    end

    %% 4. 能量约束
    energyCap = agents(agentIdx).Emax;
    assignedTasks = find(any(R_agent > tol, 2))';

    if isempty(assignedTasks)
        cost_data.requiredEnergy = 0;
        return;
    end

    % 计算能量成本
    [t_fly_total, T_exec_total, totalDistance, requiredEnergy, ...
     orderedTasks, task_arrival_times, t_wait_total] = ...
        energy_cost(agentIdx, assignedTasks, agents, tasks, Value_Params, SC);

    if requiredEnergy > energyCap + tol
        isFeasible = false;
        info.reason = 'energy_insufficient';
    end

    % 返回成本数据
    cost_data.requiredEnergy = requiredEnergy;
    cost_data.orderedTasks = orderedTasks;
    cost_data.t_fly_total = t_fly_total;
    cost_data.t_wait_total = t_wait_total;
    cost_data.T_exec_total = T_exec_total;
    cost_data.totalDistance = totalDistance;
    cost_data.assignedTasks = assignedTasks;
end
```

---

## 完整实现

### 修改 validate_feasibility.m

```matlab
function [isFeasible, info, cost_data] = validate_feasibility(
    Value_data, agents, tasks, Value_Params, agentID, SC, check_teammates)
% VALIDATE_FEASIBILITY 可行性检测：非负分配、携带量、能量可达性
%
% 新增功能：队友检查
%   如果 check_teammates = true，会检查队友是否仍然可行
%   如果队友会变得不可行，拒绝当前决策

    % 默认参数：检查队友
    if nargin < 7
        check_teammates = true;
    end

    R_agent_Q = OCFUtils.get_agent_resource_matrix(SC, agentID, Value_Params);

    info = struct('reason', '');
    cost_data = struct();
    isFeasible = true;
    tol = 1e-9;

    % agentID -> agents下标
    agentIdx = agentID;
    if agentIdx < 1 || agentIdx > numel(agents)
        agentIdx = find([agents.id] == agentID, 1, 'first');
        if isempty(agentIdx)
            isFeasible = false;
            info.reason = 'agent_not_found';
            return;
        end
    end

    %% 原有检查逻辑（维度、非负、携带量）
    if isempty(R_agent_Q) || any(size(R_agent_Q) ~= [Value_Params.M, Value_Params.K])
        isFeasible = false;
        info.reason = 'bad_R_agent_Q_size';
        return;
    end

    if min(R_agent_Q(:)) < -tol
        isFeasible = false;
        info.reason = 'negative_allocation';
        return;
    end

    cap = Value_data.resources(:);
    if numel(cap) ~= Value_Params.K
        isFeasible = false;
        info.reason = 'bad_capacity_size';
        return;
    end

    maxAllocByType = max(R_agent_Q, [], 1)';
    if any(maxAllocByType - cap > tol)
        isFeasible = false;
        info.reason = 'capacity_exceeded';
        return;
    end

    %% 能量可达性
    energyCap = agents(agentIdx).Emax;
    assignedTasks = find(cellfun(@(x) any(x(agentIdx, :) > tol), SC))';

    [t_fly_total, T_exec_total, totalDistance, requiredEnergy, orderedTasks, ...
     task_arrival_times, t_wait_total] = ...
        energy_cost(agentIdx, assignedTasks, agents, tasks, Value_Params, SC);

    if requiredEnergy > energyCap + tol
        isFeasible = false;
        info.reason = 'energy_insufficient';
        return;
    end

    % 返回成本数据
    cost_data = struct( ...
        'requiredEnergy', requiredEnergy, ...
        'orderedTasks', orderedTasks, ...
        'task_arrival_times', task_arrival_times, ...
        't_fly_total', t_fly_total, ...
        't_wait_total', t_wait_total, ...
        'T_exec_total', T_exec_total, ...
        'totalDistance', totalDistance, ...
        'assignedTasks', assignedTasks);

    %% ========== 新增：队友检查 ==========
    if check_teammates
        [all_teammates_feasible, affected_agents] = check_teammates_feasibility(
            agentID, SC, agents, tasks, Value_Params);

        if ~all_teammates_feasible
            isFeasible = false;
            info.reason = 'teammates_would_become_infeasible';
            info.affected_agents = affected_agents;
            info.details = sprintf('会导致 %d 个队友不可行', length(affected_agents));
            return;
        end
    end
end
```

### 修改调用方式

#### 在 join_operation.m 中

```matlab
% join_operation.m 第47行
% 原来：
[feasible, info, cost_data] = validate_feasibility(Value_data, agents, tasks,
                                                    Value_Params, agentID, SC_Q);

% 修改为：
[feasible, info, cost_data] = validate_feasibility(Value_data, agents, tasks,
                                                    Value_Params, agentID, SC_Q,
                                                    true);  % 启用队友检查
```

#### 在 leave_operation.m 中

```matlab
% leave_operation.m 第86行
% 同样启用队友检查
[feasible, info, cost_data] = validate_feasibility(Value_data, agents, tasks,
                                                    Value_Params, agentID, SC_Q,
                                                    true);  % 启用队友检查
```

---

## 优化方案

### 优化1：只检查受影响的队友

```matlab
function [all_feasible, affected_agents] = check_teammates_feasibility(
    agentID, SC, SC_old, agents, tasks, Value_Params)
% 新增参数 SC_old：之前的SC状态
% 只检查在SC和SC_old之间发生变化的任务的队友

    affected_tasks = [];

    % 找出发生变化的任务
    for j = 1:Value_Params.M
        if ~isequal(SC{j}, SC_old{j})
            affected_tasks(end+1) = j;
        end
    end

    % 只检查这些任务的队友
    teammates = [];
    for j = affected_tasks
        % 找出任务j的参与者
        participants = find(any(SC{j} > tol, 2));
        teammates = [teammates, setdiff(participants, agentID)];
    end

    teammates = unique(teammates);

    % 检查这些队友
    ...
end
```

### 优化2：缓存队友的可行性状态

```matlab
% 在Value_data中添加缓存
Value_data(i).feasibility_cache = struct();
Value_data(i).feasibility_cache.last_check_SC = SC;
Value_data(i).feasibility_cache.is_feasible = true;

% 在检查时先查缓存
if isequal(SC, Value_data(teammate_id).feasibility_cache.last_check_SC)
    % SC没变，直接使用缓存结果
    feasible = Value_data(teammate_id).feasibility_cache.is_feasible;
else
    % SC变了，重新检查
    [feasible, ~, ~] = validate_feasibility_simple(...);
    % 更新缓存
    Value_data(teammate_id).feasibility_cache.last_check_SC = SC;
    Value_data(teammate_id).feasibility_cache.is_feasible = feasible;
end
```

### 优化3：并行检查队友

```matlab
% 如果队友很多，可以并行检查
if length(teammates) > 5
    parfor idx = 1:length(teammates)
        teammate_id = teammates(idx);
        feasibility_results(idx) = validate_feasibility_simple(...);
    end
else
    % 队友少，顺序检查
    for idx = 1:length(teammates)
        ...
    end
end
```

---

## 理论分析

### 这个方案能保证全局可行性吗？

**答案：可以，但有条件！**

#### 保证的情况

```
场景1：Agent 1 加入 Task 5

检查流程：
1. Agent 1 自己可行？✓
2. Task 5 的现有队友（如果有）仍可行？✓
3. 接受决策 ✓

结果：
- Agent 1 可行 ✓
- 现有队友仍可行 ✓
- 全局可行 ✓
```

#### 不能完全保证的情况

```
场景2：多个任务的间接影响

初始状态：
  Task 3: [Agent 1, Agent 2]
  Task 7: [Agent 2, Agent 3]

Agent 1 加入 Task 5：
  新状态：
    Task 3: [Agent 1, Agent 2]
    Task 5: [Agent 1]
    Task 7: [Agent 2, Agent 3]

队友检查：
  - 检查 Task 5 的队友：无 ✓
  - 检查 Task 3 的队友：Agent 2 仍可行 ✓

但是！Agent 1 加入 Task 5 后：
  - Agent 1 的路径变长
  - Agent 1 在 Task 3 的到达时间延迟
  - Agent 2 在 Task 3 的等待时间增加
  - Agent 2 的总能耗增加
  - 可能导致 Agent 2 在 Task 7 的能量不足

这种"间接影响"很难在决策时完全预测。
```

### 改进方案：递归队友检查

```matlab
function [all_feasible, affected_agents] = check_teammates_feasibility_recursive(
    agentID, SC, agents, tasks, Value_Params, depth)
% 递归检查队友的队友
%
% depth: 递归深度
%   depth=1: 只检查直接队友
%   depth=2: 检查队友的队友
%   depth=3: 检查队友的队友的队友
%   ...

    if depth == 0
        all_feasible = true;
        affected_agents = [];
        return;
    end

    % 检查直接队友
    [all_feasible, affected_agents] = check_teammates_feasibility(...);

    if ~all_feasible
        return;
    end

    % 递归检查队友的队友
    for teammate_id in teammates
        [feasible_indirect, affected_indirect] = ...
            check_teammates_feasibility_recursive(
                teammate_id, SC, agents, tasks, Value_Params, depth-1);

        if ~feasible_indirect
            all_feasible = false;
            affected_agents = [affected_agents, affected_indirect];
        end
    end
end
```

**但是：递归深度太大会导致计算爆炸！**

---

## 实用建议

### 推荐配置

```matlab
% 在 join_operation.m 和 leave_operation.m 中

% 配置1：基础队友检查（推荐）
check_teammates = true;
check_depth = 1;  % 只检查直接队友

% 配置2：深度队友检查（谨慎使用）
check_teammates = true;
check_depth = 2;  % 检查队友的队友

% 配置3：关闭队友检查（调试用）
check_teammates = false;
```

### 性能权衡

```
队友检查深度 | 计算开销 | 保证程度 | 推荐场景
-----------|---------|---------|----------
depth=0    | 0%      | 低      | 调试
depth=1    | +20%    | 中      | 推荐（日常使用）
depth=2    | +100%   | 高      | 小规模场景
depth=3+   | +500%   | 很高    | 不推荐
```

### 实现优先级

**第一阶段：基础实现**
1. 实现 `check_teammates_feasibility`（depth=1）
2. 修改 `validate_feasibility` 添加队友检查
3. 在 `join_operation` 和 `leave_operation` 中启用

**第二阶段：优化**
4. 只检查受影响的队友
5. 添加可行性缓存
6. 调整检查深度参数

**第三阶段：高级功能**
7. 递归队友检查（可选）
8. 并行检查（可选）

---

## 测试验证

### 测试1：基础功能

```matlab
% 创建一个会导致队友不可行的场景
SC_before = {
    Task 5: [Agent 1: [5,5], Agent 2: [8,8]]  % Agent 2 接近能量上限
};

% Agent 3 尝试加入 Task 5
% Agent 3 距离很远，会增加 Agent 2 的等待时间
% 应该被拒绝

[feasible, info, ~] = validate_feasibility(..., true);

assert(~feasible);
assert(strcmp(info.reason, 'teammates_would_become_infeasible'));
```

### 测试2：性能测试

```matlab
% 对比启用/禁用队友检查的性能

tic;
for i = 1:100
    validate_feasibility(..., false);  % 不检查队友
end
time_without = toc;

tic;
for i = 1:100
    validate_feasibility(..., true);   % 检查队友
end
time_with = toc;

fprintf('性能开销: %.1f%%\n', (time_with/time_without - 1) * 100);
```

### 测试3：有效性验证

```matlab
% 运行完整算法，统计最终不可行的智能体数量

% 不启用队友检查
check_teammates = false;
[Value_data1, ~] = SA_Value_main(...);
infeasible_count1 = count_infeasible_agents(Value_data1);

% 启用队友检查
check_teammates = true;
[Value_data2, ~] = SA_Value_main(...);
infeasible_count2 = count_infeasible_agents(Value_data2);

fprintf('不检查队友: %d 个不可行\n', infeasible_count1);
fprintf('检查队友:   %d 个不可行\n', infeasible_count2);
fprintf('改进率: %.1f%%\n', (1 - infeasible_count2/infeasible_count1) * 100);
```

---

## 总结

### 队友检查的优势

✅ **主动预防**：在决策时就发现问题
✅ **保护先行者**：确保后来者不破坏先行者
✅ **全局视角**：考虑决策对其他智能体的影响
✅ **易于实现**：只需修改 validate_feasibility

### 局限性

⚠️ **计算开销**：每次决策需要检查多个智能体
⚠️ **间接影响**：难以捕获所有间接影响
⚠️ **递归复杂度**：深度检查会导致计算爆炸

### 推荐方案

```
基础队友检查（depth=1）
    +
全局验证与修复（方案1）
    +
能量预算（方案3）
    =
最佳实践
```

### 实现位置

```
1. 修改 validate_feasibility.m：添加队友检查逻辑
2. 新建 check_teammates_feasibility.m：实现队友检查函数
3. 新建 validate_feasibility_simple.m：简化检查（避免递归）
4. 修改 join_operation.m：启用队友检查
5. 修改 leave_operation.m：启用队友检查
```

**这个方案可以显著减少最终不可行的智能体数量！** 🎯
