function [isFeasible, info] = validate_feasibility(Value_data, agents, tasks, Value_Params, agentID, SC_P, SC_Q, R_agent_P, R_agent_Q, target, r)
% join 可行性检测（硬约束，不可行则拒绝）
% 检查项：非负分配、携带量、目标任务参与性、能量可达性
% 输出：isFeasible（布尔值）与 info（含不可行原因）

    info = struct('reason', '');
    
    % 未使用的参数（保留接口兼容性）
    unused = SC_P; %#ok<NASGU>
    unused = R_agent_P; %#ok<NASGU>

    isFeasible = true;
    tol = 1e-9;

    %% 0) agentID -> agents 下标
    agentIdx = agentID;
    if agentIdx < 1 || agentIdx > numel(agents)
        agentIdx = find([agents.id] == agentID, 1, 'first');
        if isempty(agentIdx)
            isFeasible = false;
            info.reason = 'agent_not_found';
            return;
        end
    end

    %% 1) 维度检查：M×K
    if isempty(R_agent_Q) || any(size(R_agent_Q) ~= [Value_Params.M, Value_Params.K])
        isFeasible = false;
        info.reason = 'bad_R_agent_Q_size';
        return;
    end

    %% 2) 非负约束
    if min(R_agent_Q(:)) < -tol
        isFeasible = false;
        info.reason = 'negative_allocation';
        return;
    end

    %% 3) 携带量约束：单个任务的资源分配量不超过智能体容量（资源可复用）
    % 由于资源可以复用（重叠联盟），只需检查每个任务上的分配量不超过容量
    % 例：携带5，可以给两个任务各分配5，但不能给单个任务分配8
    cap = Value_data.resources(:);  % K×1 向量

    if numel(cap) ~= Value_Params.K
        isFeasible = false;
        info.reason = 'bad_capacity_size';
        return;
    end

    % 检查每个任务上的分配量是否超过容量
    maxAllocByType = max(R_agent_Q, [], 1)';  % 每种资源在所有任务中的最大分配量
    
    if any(maxAllocByType - cap > tol)
        isFeasible = false;
        info.reason = 'capacity_exceeded';
        return;
    end

    %% 5) 能量可达性：起点->任务序列->起点

    energyCap = agents(agentIdx).Emax;


    % 获取该智能体分配到的任务
    assignedTasks = [];
    for m = 1:Value_Params.M
        if any(SC_Q{m}(agentIdx, :) > tol)
            assignedTasks = [assignedTasks, m]; %#ok<AGROW>
        end
    end

    % 计算能量需求
    [~, ~, ~, requiredEnergy, ~] = ...
        energy_cost(agentIdx, assignedTasks, agents, tasks, Value_Params, R_agent_Q);

    if requiredEnergy > energyCap + tol
        isFeasible = false;
        info.reason = 'energy_insufficient';
        return;
    end

end
