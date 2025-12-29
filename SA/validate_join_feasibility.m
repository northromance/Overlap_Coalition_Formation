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

    %% 4) 目标任务参与性检查（基于资源联盟结构 SC_Q 为 cell 数组）
    % 在当前实现中，SC_Q/SC_P 是资源联盟结构（cell数组，长度M），
    % 因此不再检查 coalitionstru 的 void 行；改为检查目标任务上是否有资源分配。
    if target >= 1 && target <= Value_Params.M
        joinedTarget = false;
        if iscell(SC_Q) && numel(SC_Q) >= target
            joinedTarget = any(SC_Q{target}(agentIdx, :) > tol);
        else
            % 兜底：如果未传入 cell，则用 R_agent_Q 判断
            joinedTarget = (R_agent_Q(target, r) > tol);
        end
        info.joinedTargetAfter = joinedTarget;
        if ~joinedTarget
            isFeasible = false;
            info.reason = 'not_joined_target';
            return;
        end
    end

    %% 6) 能量可达性：起点->任务序列->起点
    % 能量上限：优先使用 agents(i).Emax；若缺失则视为不限制（Inf）。
    energyCap = inf;
    if isfield(agents(agentIdx), 'Emax') && ~isempty(agents(agentIdx).Emax)
        energyCap = agents(agentIdx).Emax; % 智能体最大能量/能力
    end
    info.energyFeasibilityEnabled = true;

    % 6.1 取该智能体分配到的任务（真实任务 1..M）
    % SC_Q 是 cell(M,1)，SC_Q{m} 是 N×K 矩阵
    % 需要遍历每个任务m，检查该智能体在该任务上是否有资源分配
    assignedTasks = [];
    tol = 1e-9;
    for m = 1:Value_Params.M
        % 检查该智能体在任务m上是否分配了任何资源
        if any(SC_Q{m}(agentIdx, :) > tol)
            assignedTasks = [assignedTasks, m]; %#ok<AGROW>
        end
    end
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
