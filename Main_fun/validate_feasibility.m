function [isFeasible, info, cost_data] = validate_feasibility(Value_data, agents, tasks, Value_Params, agentID, SC)
% VALIDATE_FEASIBILITY 可行性检测：非负分配、携带量、能量可达性
%
% 输入:
%   Value_data   - 智能体数据结构
%   agents       - 智能体数组
%   tasks        - 任务数组
%   Value_Params - 全局参数
%   agentID      - 智能体ID
%   SC_Q         - 新的联盟结构
%   R_agent_Q    - 资源分配矩阵 (M x K)
%
% 输出:
%   isFeasible   - 是否可行
%   info         - 错误信息
%   cost_data    - 成本数据结构


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

% 维度检查
if isempty(R_agent_Q) || any(size(R_agent_Q) ~= [Value_Params.M, Value_Params.K])
    isFeasible = false;
    info.reason = 'bad_R_agent_Q_size';
    return;
end

% 非负约束
if min(R_agent_Q(:)) < -tol
    isFeasible = false;
    info.reason = 'negative_allocation';
    return;
end

% 携带量约束
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

% 能量可达性
energyCap = agents(agentIdx).Emax;
assignedTasks = find(cellfun(@(x) any(x(agentIdx, :) > tol), SC))';

% 计算能量成本
[t_fly_total, T_exec_total, totalDistance, requiredEnergy, orderedTasks, task_arrival_times, t_wait_total] = ...
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
end
