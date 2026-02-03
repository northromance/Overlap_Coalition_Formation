function [isFeasible, info, cost_data] = validate_feasibility(Value_data, agents, tasks, Value_Params, agentID, SC, check_teammates, AddPara)
% VALIDATE_FEASIBILITY 可行性检测：非负分配、携带量、能量可达性、队友检查
%
% 输入:
%   Value_data      - 智能体数据结构
%   agents          - 智能体数组
%   tasks           - 任务数组
%   Value_Params    - 全局参数
%   agentID         - 智能体ID
%   SC              - 新的联盟结构
%   check_teammates - 是否检查队友可行性（默认false）
%   AddPara         - 附加参数（包含verbose开关）
%
% 输出:
%   isFeasible   - 是否可行
%   info         - 错误信息
%   cost_data    - 成本数据结构
%
% 新增功能：队友检查
%   如果 check_teammates = true，会检查队友是否仍然可行
%   如果队友会变得不可行，拒绝当前决策

% 默认参数：启用队友检查
if nargin < 7
    check_teammates = true;
end
if nargin < 8
    AddPara = struct('verbose', true);
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
% 智能获取资源信息：优先从 Value_data，否则从 agents
if length(Value_data) >= agentIdx && isfield(Value_data(agentIdx), 'resources')
    cap = Value_data(agentIdx).resources(:);
elseif isfield(agents(agentIdx), 'resources')
    cap = agents(agentIdx).resources(:);
else
    isFeasible = false;
    info.reason = 'no_resource_info';
    return;
end

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
[t_fly_total, t_exec_total, totalDistance, requiredEnergy, orderedTasks, task_arrival_times, t_wait_total] = ...
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
    't_exec_total', t_exec_total, ...
    'totalDistance', totalDistance, ...
    'assignedTasks', assignedTasks);

%% ==================== 队友检查 ====================
% 检查当前决策是否会导致队友变得不可行
if check_teammates
    [all_teammates_feasible, affected_agents] = check_teammates_feasibility(...
        agentID, SC, agents, tasks, Value_Params, tol,AddPara);

    if ~all_teammates_feasible
        isFeasible = false;
        info.reason = 'teammates_would_become_infeasible';
        info.affected_agents = affected_agents;
        info.details = sprintf('会导致 %d 个队友不可行', length(affected_agents));
        return;
    end
end

end

%% ==================== 内部函数：队友检查 ====================
function [all_feasible, affected_agents] = check_teammates_feasibility(...
    agentID, SC, agents, tasks, Value_Params, tol,AddPara)
% CHECK_TEAMMATES_FEASIBILITY 检查队友是否仍然可行
%
% 功能：
%   当智能体加入或离开任务时，检查与其共同参与任务的队友
%   是否会因为等待时间增加而变得不可行
%
% 输入：
%   agentID      - 当前决策的智能体ID
%   SC           - 提议的新联盟结构（包含agentID的决策）
%   agents       - 智能体数组
%   tasks        - 任务数组
%   Value_Params - 全局参数
%   tol          - 容差
%
% 输出：
%   all_feasible     - 所有队友是否都可行
%   affected_agents  - 受影响的智能体列表（不可行的）

all_feasible = true;
affected_agents = [];

N = Value_Params.N;
M = Value_Params.M;

%% 1. 找出所有队友
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

% 调试信息（可选）
if Value_Params.N <= 10  % 只在小规模场景下打印
    % fprintf('      [队友检查] Agent %d 的队友: [%s]\n', ...
    %     agentID, num2str(teammates));
end

%% 2. 检查每个队友
for idx = 1:length(teammates)
    teammate_id = teammates(idx);

    % 检查队友的可行性（不递归检查队友的队友，避免无限递归）
    [feasible, info_teammate, cost_data_teammate] = ...
        validate_feasibility_simple(teammate_id, SC, agents, tasks, Value_Params, tol);

    if ~feasible
        all_feasible = false;
        affected_agents(end+1) = teammate_id;

        % 调试信息
        if AddPara.verbose
            if isfield(cost_data_teammate, 'requiredEnergy')
                fprintf('      ⚠️  队友 Agent %d 会变得不可行: %s (能量: %.2f/%.2f)\n', ...
                    teammate_id, info_teammate.reason, ...
                    cost_data_teammate.requiredEnergy, agents(teammate_id).Emax);
            else
                fprintf('      ⚠️  队友 Agent %d 会变得不可行: %s\n', ...
                    teammate_id, info_teammate.reason);
            end
        end
    end
end

if all_feasible && ~isempty(teammates)
    % fprintf('      ✅ 所有 %d 个队友仍然可行\n', length(teammates));
end

end

%% ==================== 内部函数：简化的可行性检查 ====================
function [isFeasible, info, cost_data] = validate_feasibility_simple(...
    agentID, SC, agents, tasks, Value_Params, tol)
% VALIDATE_FEASIBILITY_SIMPLE 简化的可行性检查（不检查队友）
%
% 功能：
%   用于队友检查，避免递归调用
%   只检查该智能体自身的可行性
%
% 输入：
%   agentID      - 智能体ID
%   SC           - 联盟结构
%   agents       - 智能体数组
%   tasks        - 任务数组
%   Value_Params - 全局参数
%   tol          - 容差
%
% 输出：
%   isFeasible - 是否可行
%   info       - 错误信息
%   cost_data  - 成本数据

info = struct('reason', '');
cost_data = struct();
isFeasible = true;

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
try
    [t_fly_total, t_exec_total, totalDistance, requiredEnergy, ...
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
    cost_data.t_exec_total = t_exec_total;
    cost_data.totalDistance = totalDistance;
    cost_data.assignedTasks = assignedTasks;
catch ME
    % 如果能量计算失败，标记为不可行
    isFeasible = false;
    info.reason = 'energy_calculation_failed';
    info.error_message = ME.message;
end

end
