function [isFeasible, info] = validate_join_feasibility(Value_data, agents, tasks, Value_Params, agentID, SC_P, SC_Q, R_agent_P, R_agent_Q, target, r)
% join 可行性检测（硬约束，不可行则拒绝）。
% 检查项：非负分配；携带量(sum_m R_agent_Q<=cap)；void 行(M+1)一致性；
%         任务序列(按 priority) + 回到起点的能量可达性（使用 agents(i).Emax）。
% 输出：isFeasible 与 info（含 reason 与关键数值）。

    info = struct();
    info.agentID = agentID;
    info.target = target;
    info.r = r;

    % 兼容接口：当前只用 SC_Q / R_agent_Q。
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
        info.size = size(R_agent_Q);
        return;
    end

    %% 2) 非负约束
    minVal = min(R_agent_Q(:));
    info.minAllocated = minVal;
    if minVal < -tol
        isFeasible = false;
        info.reason = 'negative_allocation';
        return;
    end

    %% 3) 携带量约束：sum_m R_agent_Q(:,k) <= cap(k)
    % 分配的资源总数不能超过智能体自己的资源总数
    cap = [];

    if isfield(Value_data, 'resources') && ~isempty(Value_data.resources)
        res = Value_data.resources;
        if isscalar(res)
            % 标量：所有资源类型同一容量
            cap = repmat(res, Value_Params.K, 1);
        elseif isvector(res)
            cap = res(:);
        else
            if size(res, 1) == Value_Params.K && size(res, 2) >= agentIdx
                cap = res(:, agentIdx);
            elseif size(res, 2) == Value_Params.K && size(res, 1) >= agentIdx
                cap = res(agentIdx, :)';
            end
        end
    end
    if isempty(cap)
        cap = agents(agentIdx).resources(:);
    end

    if numel(cap) ~= Value_Params.K
        isFeasible = false;
        info.reason = 'bad_capacity_size';
        info.capacitySize = numel(cap);
        return;
    end

    % totals(k)：第 k 类资源分配总量
    totals = sum(R_agent_Q, 1)';
    info.totalAllocatedByType = totals;
    info.capacityByType = cap;

    % exceed(k) > 0 表示超额
    exceed = totals - cap;
    info.exceedByType = exceed;

    if any(exceed > tol)
        isFeasible = false;
        info.reason = 'capacity_exceeded';
        return;
    end

    %% 4) void 行一致性：加入真实任务后不能仍在 M+1 行
    if size(SC_Q, 1) >= Value_Params.M + 1
        inVoid = (SC_Q(Value_Params.M + 1, agentIdx) ~= 0);
        info.inVoidRowAfter = inVoid;
        if target >= 1 && target <= Value_Params.M && inVoid
            isFeasible = false;
            info.reason = 'still_in_void_row';
            return;
        end
    end

    %% 5) 加入目标行：SC_Q(target,agentIdx) ~= 0
    if target >= 1 && target <= Value_Params.M
        if SC_Q(target, agentIdx) == 0
            isFeasible = false;
            info.reason = 'not_joined_target_row';
            return;
        end
    end

    %% 6) 能量可达性：起点->任务序列->起点
    % 约定：agents(i).Emax 已在初始化阶段赋值。
    energyCap = agents(agentIdx).Emax; %智能体最大能力
    info.energyFeasibilityEnabled = true;

    % 6.1 取该智能体分配到的任务（真实任务 1..M）
    assignedTasks = find(SC_Q(1:Value_Params.M, agentIdx) ~= 0);
    info.assignedTasks = assignedTasks(:)';

    % 6.2 调用统一的能量成本计算函数
    [t_wait_total, T_exec_total, totalDistance, requiredEnergy, orderedTasks] = ...
        compute_agent_energy_cost(agentIdx, assignedTasks, agents, tasks, Value_Params, R_agent_Q);

    % 6.3 记录计算结果到info
    info.taskSequenceByPriority = orderedTasks(:)';
    info.routeDistance = totalDistance;
    info.energyModel = 'time_vel_fuel_and_beta';
    info.t_wait_total = t_wait_total;
    info.T_exec_total = T_exec_total;
    info.alpha = agents(agentIdx).fuel;
    info.beta = agents(agentIdx).beta;
    info.speedUsed = agents(agentIdx).vel;
    info.requiredEnergy = requiredEnergy;
    info.energyCapacity = energyCap;

    if requiredEnergy > energyCap + tol
        isFeasible = false;
        info.reason = 'energy_insufficient';
        return;
    end

    % 扩展约束时在 info.reason 中增加枚举。
end
