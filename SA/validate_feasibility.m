function [isFeasible, info] = validate_feasibility(Value_data, agents, tasks, Value_Params, agentID, SC_P, SC_Q, R_agent_P, R_agent_Q, target, r)
% join可行性检测：非负分配、携带量、能量可达性

    info = struct('reason', '');
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
    assignedTasks = find(cellfun(@(x) any(x(agentIdx, :) > tol), SC_Q))';

    % 新接口返回7个值: [t_fly, T_exec, dist, energy, ordered, arrivals, t_wait]
    [~, ~, ~, requiredEnergy, ~, ~, ~] = energy_cost(agentIdx, assignedTasks, agents, tasks, Value_Params, R_agent_Q, SC_Q);

    if requiredEnergy > energyCap + tol
        isFeasible = false;
        info.reason = 'energy_insufficient';
        return;
    end
end
