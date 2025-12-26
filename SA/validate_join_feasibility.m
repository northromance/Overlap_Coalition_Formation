function [isFeasible, info] = validate_join_feasibility(Value_data, agents, tasks, Value_Params, agentID, SC_P, SC_Q, R_agent_P, R_agent_Q, target, r)
% validate_join_feasibility
% 对 join 操作后的结果做“可行性”检测（偏硬约束，失败则不允许加入）。
%
% 当前实现的约束（最小但可落地）：
% 1) 资源分配非负：R_agent_Q 中任何元素不能为负。
% 2) 携带量约束：对每种资源类型 k，智能体对所有任务的分配总量
%      sum_m R_agent_Q(m,k) <= cap(k)
%    其中 cap 优先取 Value_data.resources，否则回退 agents(agent).resources。
% 3) 空任务行约束：若 coalitionstru 有空任务行 M+1，则加入真实任务后不能仍在空任务行。
% 4) 任务序列 + 回到起点 + 能量可达性：
%    - 取该智能体被分配到的所有任务（SC_Q(1:M,agentIdx)~=0）
%    - 按 tasks(j).priority 从小到大排序（数值越小优先级越高；若缺失则按任务编号排序）
%    - 形成路径：起点(agents.x,y) -> 任务序列 -> 起点
%    - 用能量预算检查是否可完成整条路径（包含回到起点）
%
% 输出：
%   isFeasible: 是否可行
%   info: 结构体，包含失败原因 reason 和关键数值（便于打印/定位问题）

    info = struct();
    info.agentID = agentID;
    info.target = target;
    info.r = r;

    % 说明：当前版本只用到 SC_Q / R_agent_Q 来做约束检查。
    % 这里保留 SC_P / R_agent_P 作为接口兼容，并避免静态检查告警。
    unused = SC_P; %#ok<NASGU>
    unused = R_agent_P; %#ok<NASGU>

    isFeasible = true;

    tol = 1e-9;

    %% 0) 将 agentID 映射为 agents 数组下标
    % agentID 有时是“编号”，不一定等于数组下标；此处做一次兼容映射。
    agentIdx = agentID;
    if agentIdx < 1 || agentIdx > numel(agents)
        agentIdx = find([agents.id] == agentID, 1, 'first');
        if isempty(agentIdx)
            isFeasible = false;
            info.reason = 'agent_not_found';
            return;
        end
    end

    %% 1) 基本维度检查：资源矩阵必须是 M x K
    if isempty(R_agent_Q) || any(size(R_agent_Q) ~= [Value_Params.M, Value_Params.K])
        isFeasible = false;
        info.reason = 'bad_R_agent_Q_size';
        info.size = size(R_agent_Q);
        return;
    end

    %% 2) 非负约束：资源分配不能出现负数
    minVal = min(R_agent_Q(:));
    info.minAllocated = minVal;
    if minVal < -tol
        isFeasible = false;
        info.reason = 'negative_allocation';
        return;
    end

    %% 3) 携带量约束：每种资源类型的总分配不能超过携带量
    % cap(k)：该智能体携带的第 k 类资源总量
    if isfield(Value_data, 'resources') && ~isempty(Value_data.resources)
        cap = Value_data.resources(:);
    else
        cap = agents(agentIdx).resources(:);
    end

    if numel(cap) ~= Value_Params.K
        isFeasible = false;
        info.reason = 'bad_capacity_size';
        info.capacitySize = numel(cap);
        return;
    end

    % totals(k)：第 k 类资源在所有任务上的分配总量
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

    %% 4) 联盟结构检查：加入真实任务后不能仍在空任务行
    % 若 coalitionstru 有 M+1 行（空任务/void），加入真实任务后需要把该行清零。
    if size(SC_Q, 1) >= Value_Params.M + 1
        inVoid = (SC_Q(Value_Params.M + 1, agentIdx) ~= 0);
        info.inVoidRowAfter = inVoid;
        if target >= 1 && target <= Value_Params.M && inVoid
            isFeasible = false;
            info.reason = 'still_in_void_row';
            return;
        end
    end

    %% 5) 目标任务行检查：既然是“加入 target”，SC_Q(target,agent) 应该非 0
    if target >= 1 && target <= Value_Params.M
        if SC_Q(target, agentIdx) == 0
            isFeasible = false;
            info.reason = 'not_joined_target_row';
            return;
        end
    end

    %% 6) 任务序列(按重要性排序) + 回到起点 + 能量可达性检查
    % 说明：工程里“能量预算”的字段命名不统一；这里做兼容：
    %   优先使用 Value_data.totalEnergy / Value_data.energy，
    %   其次 agents(agent).totalEnergy / agents(agent).energy / agents(agent).Emax。
    % 如果都不存在，则默认跳过该约束（并在 info 中标记），避免破坏旧脚本。

    energyCap = [];
    if isfield(Value_data, 'totalEnergy') && ~isempty(Value_data.totalEnergy)
        energyCap = Value_data.totalEnergy;
    elseif isfield(Value_data, 'energy') && ~isempty(Value_data.energy)
        energyCap = Value_data.energy;
    elseif isfield(agents(agentIdx), 'totalEnergy') && ~isempty(agents(agentIdx).totalEnergy)
        energyCap = agents(agentIdx).totalEnergy;
    elseif isfield(agents(agentIdx), 'energy') && ~isempty(agents(agentIdx).energy)
        energyCap = agents(agentIdx).energy;
    elseif isfield(agents(agentIdx), 'Emax') && ~isempty(agents(agentIdx).Emax)
        energyCap = agents(agentIdx).Emax;
    end

    % 是否启用能量可行性：若提供了预算则默认启用；也可用 Value_Params.enableEnergyFeasibility 强制开关。
    enableEnergy = ~isempty(energyCap);
    if isfield(Value_Params, 'enableEnergyFeasibility') && ~isempty(Value_Params.enableEnergyFeasibility)
        enableEnergy = logical(Value_Params.enableEnergyFeasibility);
    end

    info.energyFeasibilityEnabled = enableEnergy;
    if enableEnergy
        % 6.1 取该智能体当前分配到的所有任务（只看真实任务 1..M）
        assignedTasks = find(SC_Q(1:Value_Params.M, agentIdx) ~= 0);
        info.assignedTasks = assignedTasks(:)';

        % 6.2 按 tasks(j).priority 排序（数值越小优先级越高）；缺失则按任务编号排序
        if ~isempty(assignedTasks) && isfield(tasks, 'priority')
            pr = zeros(size(assignedTasks));
            for ii = 1:numel(assignedTasks)
                pr(ii) = tasks(assignedTasks(ii)).priority;
            end
            [~, orderIdx] = sort(pr, 'ascend');
            orderedTasks = assignedTasks(orderIdx);
        else
            orderedTasks = sort(assignedTasks);
        end
        info.taskSequenceByPriority = orderedTasks(:)';

        % 6.3 构造路径：起点 -> 任务序列 -> 起点，并计算总距离
        startXY = [agents(agentIdx).x, agents(agentIdx).y];
        pts = zeros(numel(orderedTasks) + 2, 2);
        pts(1, :) = startXY;
        for ii = 1:numel(orderedTasks)
            t = orderedTasks(ii);
            pts(ii + 1, :) = [tasks(t).x, tasks(t).y];
        end
        pts(end, :) = startXY; % 起点加到序列末尾

        seg = diff(pts, 1, 1);
        distEach = sqrt(sum(seg.^2, 2));
        totalDistance = sum(distEach);

        info.routePoints = pts;
        info.routeDistance = totalDistance;

        % 6.4 能量消耗模型（与 overlap_coalition_self_utility 的成本项一致）
        % requiredEnergy = t_wait_total * alpha + T_exec_total * beta
        % 其中：
        %   - t_wait_total：沿“起点->任务序列->起点”路径的总飞行时间
        %   - T_exec_total：任务序列中所有任务的总执行时间
        haveAlphaBeta = isfield(Value_Params, 'alpha') && isfield(Value_Params, 'beta') && ...
            ~isempty(Value_Params.alpha) && ~isempty(Value_Params.beta);

        % 速度字段兼容：speed 优先，其次 vel；都没有就按 1
        speed = 1;
        if isfield(agents(agentIdx), 'speed') && ~isempty(agents(agentIdx).speed)
            speed = agents(agentIdx).speed;
        elseif isfield(agents(agentIdx), 'vel') && ~isempty(agents(agentIdx).vel)
            speed = agents(agentIdx).vel;
        end
        speed = max(speed, tol);

        if haveAlphaBeta
            t_wait_total = totalDistance / speed;

            T_exec_total = 0;
            if ~isempty(orderedTasks) && isfield(tasks, 'duration')
                for ii = 1:numel(orderedTasks)
                    T_exec_total = T_exec_total + tasks(orderedTasks(ii)).duration;
                end
            end

            requiredEnergy = t_wait_total * Value_Params.alpha + T_exec_total * Value_Params.beta;
            energyModel = 'utility_cost_alpha_beta';

            info.t_wait_total = t_wait_total;
            info.T_exec_total = T_exec_total;
            info.alpha = Value_Params.alpha;
            info.beta = Value_Params.beta;
            info.speedUsed = speed;
        else
            fuelCoef = 1;
            if isfield(agents(agentIdx), 'fuel') && ~isempty(agents(agentIdx).fuel)
                fuelCoef = agents(agentIdx).fuel;
            end
            requiredEnergy = totalDistance * fuelCoef;
            energyModel = 'distance_fuel';
            info.fuelCoef = fuelCoef;
            info.speedUsed = speed;
        end

        info.energyModel = energyModel;
        info.requiredEnergy = requiredEnergy;
        info.energyCapacity = energyCap;

        if requiredEnergy > energyCap + tol
            isFeasible = false;
            info.reason = 'energy_insufficient';
            return;
        end
    else
        info.energyFeasibilitySkipped = true;
    end

    % 备注：若还需要加入更多可行性约束（例如任务序列/可回到起点），
    % 建议在此函数继续扩展，并在 info.reason 中增加新的失败原因枚举。
end
