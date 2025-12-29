function [Value_data, incremental_leave] = leave_operation(Value_data, agents, tasks, Value_Params, probs)
% leave_operation: 尝试让智能体从已加入的任务中撤回部分资源。
% 参考 join_operation 的流程：抽样候选、构造前后状态、做可行性验证、计算ΔU 并按模拟退火规则决定是否放弃。
%
% 输入参数：
%   Value_data   - 智能体的数据结构，包含 agentID、SC（资源联盟结构）、resources_matrix 等
%   agents       - 所有智能体的结构体数组
%   tasks        - 所有任务的结构体数组
%   Value_Params - 参数结构体（M=任务数、K=资源类型数、N=智能体数、Temperature=模拟退火温度等）
%   probs        - K×M 矩阵，probs(r,j) 表示资源类型r下选择任务j的概率（用于加权抽样）
%
% 输出参数：
%   Value_data        - 更新后的智能体数据结构
%   incremental_leave - 是否成功执行了撤出操作（1=成功，0=失败）

    incremental_leave = 0;  % 初始化撤出标志为0（未撤出）
    agentID = Value_data.agentID;  % 获取当前智能体的ID
    M = Value_Params.M;  % 任务总数
    K = Value_Params.K;  % 资源类型总数
    tol = 1e-9;  % 数值容差，用于浮点数比较

    % ========== 1) 智能体索引转换 ==========
    % 将 agentID 转换为 agents 数组中的索引位置
    agentIdx = agentID;
    if agentIdx < 1 || agentIdx > numel(agents) || ~isstruct(agents(agentIdx))
        % 如果 agentID 不能直接作为索引，则在 agents 数组中查找
        agentIdx = find([agents.id] == agentID, 1, 'first');
        if isempty(agentIdx)
            error('leave_operation:AgentNotFound', 'agentID=%d not found in agents.', agentID);
        end
    end

    % ========== 2) 初始化/验证 resources_matrix ==========
    % resources_matrix(m, r) = 智能体对任务m分配的资源类型r的数量
    % 若不存在或维度不对，则从 SC（资源联盟结构）中提取
    if ~isfield(Value_data, 'resources_matrix') || isempty(Value_data.resources_matrix) || ...
            any(size(Value_data.resources_matrix) ~= [M, K])
        Value_data.resources_matrix = zeros(M, K);
        if isfield(Value_data, 'SC') && ~isempty(Value_data.SC)
            % 从每个任务的 SC{m} 矩阵中提取该智能体的资源分配
            for m = 1:M
                Value_data.resources_matrix(m, :) = Value_data.SC{m}(agentIdx, :);
            end
        end
    end

    % ========== 3) 初始化/验证 SC（资源联盟结构）==========
    % SC{m} 是 N×K 矩阵，SC{m}(i,r) 表示智能体i对任务m分配的资源类型r的数量
    if ~isfield(Value_data, 'SC') || isempty(Value_data.SC)
        Value_data.SC = cell(M, 1);  % 创建 M 个任务的cell数组
        for m = 1:M
            Value_data.SC{m} = zeros(Value_Params.N, K);  % 每个任务的资源分配矩阵
            Value_data.SC{m}(agentIdx, :) = Value_data.resources_matrix(m, :);  % 填入该智能体的分配
        end
    end

    % ========== 4) 初始化/验证 coalitionstru（联盟结构矩阵）==========
    % coalitionstru 是 (M+1)×N 矩阵，coalitionstru(m,i)=i 表示智能体i参与任务m
    % 第 M+1 行是空任务（void task），表示智能体未分配任何任务
    if ~isfield(Value_data, 'coalitionstru') || isempty(Value_data.coalitionstru) || ...
            size(Value_data.coalitionstru, 1) ~= M + 1 || size(Value_data.coalitionstru, 2) < agentIdx
        Value_data.coalitionstru = zeros(M + 1, Value_Params.N);
    end

    % ========== 5) 设置调试输出开关 ==========
    verbose = true;  % 默认打印调试信息
    if isfield(Value_Params, 'verbose')
        verbose = logical(Value_Params.verbose);
    end

    % ========== 6) 备份原始资源分配矩阵 ==========
    % 若本轮所有撤出尝试都失败，则回滚到此备份
    original_resources_matrix = Value_data.resources_matrix;  % 保留一份备份，若撤出失败则回滚

    % ========== 7) 主循环：遍历每种资源类型，尝试撤出 ==========
    for r = 1:K
        % 7.1) 找出当前智能体在资源类型r上已分配的所有任务
        currentAllocColumn = Value_data.resources_matrix(:, r);  % 该智能体对所有任务的资源r分配
        candidateTasks = find(currentAllocColumn > tol);  % 找出有分配的任务（分配量>0）
        if isempty(candidateTasks)
            % 该资源类型未分配给任何任务，跳过
            continue;
        end

        % 7.2) 根据选择概率对候选任务加权抽样
        weights = ones(1, numel(candidateTasks));  % 默认均匀抽样（每个任务权重相等）
        if nargin >= 5 && ~isempty(probs) && size(probs, 1) >= r
            % 如果提供了 probs 矩阵，使用其第r行作为权重
            row = probs(r, :);  % probs 的第r行：资源类型r对各任务的选择概率
            if numel(row) >= M
                weights = row(candidateTasks);  % 提取候选任务对应的权重
            end
        end
        if all(weights <= tol)
            % 若所有权重都为0，则回退到均匀分布
            weights = ones(1, numel(candidateTasks));
        end
        % 累积分布函数抽样（不依赖 randsample）
        edges = cumsum(weights);  % 累积权重
        pick = rand() * edges(end);  % 生成 [0, sum(weights)] 范围内的随机数
        idx = find(edges >= pick, 1, 'first');  % 找到第一个累积值>=pick的位置
        if isempty(idx)
            idx = 1;
        end
        sourceTask = candidateTasks(idx);  % 确定要撤出的源任务

        % 7.3) 获取当前分配量，检查是否有效
        currentAmount = currentAllocColumn(sourceTask);  % 该任务上资源r的当前分配量
        if currentAmount <= tol
            % 分配量接近0，无法撤出，跳过
            continue;
        end


        % 7.4) 撤出全部该资源类型：直接将该任务上的资源类型r分配量清零
        remainingAmount = 0;  % 撤出后该任务该资源类型分配量为0
        releasedAmount = currentAmount;  % 释放全部分配量
        if releasedAmount <= tol
            % 释放量太小，跳过
            continue;
        end

        % ========== 8) 构造操作前后的状态 ==========
        % 8.1) 操作前状态（P = Previous）
        SC_P = Value_data.SC;  % 操作前的资源联盟结构（cell数组）
        R_agent_P = Value_data.resources_matrix;  % 操作前该智能体的资源分配矩阵 (M×K)

        % 8.2) 操作后状态（Q = Query/新状态）
        % 将 sourceTask 上资源类型r的分配量减少到 remainingAmount
        R_agent_Q = R_agent_P;  % 先复制
        R_agent_Q(sourceTask, r) = remainingAmount;  % 修改撤出任务的资源分配

        % 8.3) 同步更新 SC_Q：将该智能体在所有任务上的新分配写入
        SC_Q = SC_P;  % 先复制整个联盟结构
        for m = 1:M
            taskMatrix = SC_Q{m};  % 获取任务m的资源分配矩阵 (N×K)
            taskMatrix(agentIdx, :) = R_agent_Q(m, :);  % 更新该智能体的分配
            SC_Q{m} = taskMatrix;  % 写回
        end

        % ========== 9) 可行性检测（硬约束） ==========
        % 检查撤出后是否满足：非负分配、容量约束、能量可达性等
        [feasible, info] = validate_leave_feasibility(Value_data, agents, tasks, Value_Params, agentIdx, SC_P, SC_Q, R_agent_Q);
        if ~feasible
            % 不可行，跳过此次撤出尝试
            if verbose
                reason = 'unknown';
                if isfield(info, 'reason')
                    reason = info.reason;  % 获取不可行的具体原因
                end
                fprintf('智能体%d: 资源类型%d退出任务%d不可行（原因：%s）\n', agentID, r, sourceTask, reason);
            end
            continue;  % 继续尝试下一种资源类型
        end

        % ========== 10) 计算效用变化 ΔU ==========
        % 临时写入操作后资源矩阵，用于效用计算
        Value_data.resources_matrix = R_agent_Q;
        % 调用 overlap_coalition_utility 计算 ΔU = U(SC_Q) - U(SC_P)
        % 返回值 > 0 表示撤出后效用提升；< 0 表示效用下降
        delta_U = overlap_coalition_utility(tasks, agents, SC_P, SC_Q, agentID, Value_Params, Value_data);

        % ========== 11) 决策：是否接受此次撤出 ==========
        accept_leave = false;  % 初始化接受标志
        if delta_U > 0
            % 情况1：ΔU > 0，撤出后效用提升，直接接受
            accept_leave = true;
            if verbose
                fprintf('智能体%d: 退出任务%d(资源类型%d), ΔU=%.4f > 0\n', agentID, sourceTask, r, delta_U);
            end
        else
            % 情况2：ΔU <= 0，撤出后效用下降，使用模拟退火概率接受差解
            T = 1;  % 默认温度
            if isfield(Value_Params, 'Temperature') && ~isempty(Value_Params.Temperature)
                T = Value_Params.Temperature;  % 获取当前退火温度
            end
            if abs(T) < tol
                T = 1;  % 防止温度过小导致数值问题
            end
            % 模拟退火接受概率：P = exp(ΔU / T)
            % 温度越高，接受差解的概率越大；ΔU 越接近0，接受概率越大
            acceptProb = exp(delta_U / T);
            if rand() < acceptProb
                % 以概率 acceptProb 接受差解
                accept_leave = true;
                if verbose
                    fprintf('智能体%d: 退出任务%d(资源类型%d), ΔU=%.4f, SA接受概率=%.4f\n', ...
                        agentID, sourceTask, r, delta_U, acceptProb);
                end
            else
                % 拒绝差解
                if verbose
                    fprintf('智能体%d: 拒绝退出任务%d(资源类型%d), ΔU=%.4f, SA拒绝\n', ...
                        agentID, sourceTask, r, delta_U);
                end
            end
        end

        % ========== 12) 执行决策结果 ==========
        if accept_leave
            % 接受撤出：更新所有相关状态
            Value_data.SC = SC_Q;  % 接受撤出，写回联盟结构
            
            % 12.1) 找出撤出后该智能体仍参与的所有任务
            assignedTasksPost = find(any(R_agent_Q > tol, 2));  % 任意资源类型分配>0的任务

            % 12.2) 更新 coalitionstru 矩阵
            coalition_after = Value_data.coalitionstru;
            coalition_after(1:M, agentIdx) = 0;  % 先清空该智能体在所有真实任务上的标记
            for mIdx = assignedTasksPost'
                % 标记该智能体参与的任务
                coalition_after(mIdx, agentIdx) = agents(agentIdx).id;
            end
            if isempty(assignedTasksPost)
                % 若撤出后不参与任何任务，则放入空任务行
                coalition_after(M + 1, agentIdx) = agents(agentIdx).id;
            else
                % 若仍参与至少一个任务，则清空空任务行标记
                coalition_after(M + 1, agentIdx) = 0;
            end
            Value_data.coalitionstru = coalition_after;

            % 12.3) 设置撤出成功标志，打印日志，并跳出循环
            incremental_leave = 1;  % 标记本轮成功执行了撤出
            if verbose
                fprintf('  资源分配变化: 任务%d释放资源类型%d数量%.2f\n', sourceTask, r, releasedAmount);
            end
            break;  % 一旦成功撤出，就结束本轮操作（不再尝试其他资源类型）
        else
            % 拒绝撤出：回滚 resources_matrix 到操作前状态
            Value_data.resources_matrix = R_agent_P;
        end
    end

    % ========== 13) 全局回滚检查 ==========
    % 若本轮所有资源类型的撤出尝试都失败（incremental_leave 仍为0），
    % 则将 resources_matrix 回滚到进入函数时的初始状态
    if incremental_leave == 0
        Value_data.resources_matrix = original_resources_matrix;
    end
end


function [isFeasible, info] = validate_leave_feasibility(Value_data, agents, tasks, Value_Params, agentIdx, SC_P, SC_Q, R_agent_Q)
% validate_leave_feasibility: 验证撤出操作的可行性（硬约束检查）
%
% 检查项：
%   1. 资源分配非负
%   2. 总分配量不超过智能体容量
%   3. 能量可达性（任务序列+回到起点的总能耗不超过智能体能量上限）
%
% 输入参数：
%   Value_data   - 智能体数据结构
%   agents       - 智能体数组
%   tasks        - 任务数组
%   Value_Params - 参数结构体
%   agentIdx     - 智能体索引
%   SC_P         - 操作前的资源联盟结构（未使用，保留用于接口兼容）
%   SC_Q         - 操作后的资源联盟结构（未使用，保留用于接口兼容）
%   R_agent_Q    - 操作后该智能体的资源分配矩阵 (M×K)
%
% 输出参数：
%   isFeasible - 布尔值，true=可行，false=不可行
%   info       - 结构体，包含检查的详细信息和不可行原因

    %#ok<INUSD>  % 抑制未使用变量的警告
    tol = 1e-9;  % 数值容差
    info = struct();  % 初始化信息结构体
    info.agentIdx = agentIdx;

    isFeasible = true;  % 初始假设可行

    % ========== 检查1：资源分配矩阵维度 ==========
    if isempty(R_agent_Q) || any(size(R_agent_Q) ~= [Value_Params.M, Value_Params.K])
        isFeasible = false;
        info.reason = 'bad_R_agent_Q_size';  % 矩阵维度不对
        info.size = size(R_agent_Q);
        return;
    end

    % ========== 检查2：非负约束 ==========
    % 资源分配量不能为负数
    minVal = min(R_agent_Q(:));
    info.minAllocated = minVal;
    if minVal < -tol
        isFeasible = false;
        info.reason = 'negative_allocation';  % 存在负分配
        return;
    end

    % ========== 检查3：携带量约束 ==========
    % 智能体对各资源类型的总分配量不能超过其携带容量
    cap = [];  % 初始化容量向量
    if isfield(Value_data, 'resources') && ~isempty(Value_data.resources)
        res = Value_data.resources;
        if isscalar(res)
            % 标量：所有资源类型同一容量
            cap = repmat(res, Value_Params.K, 1);
        elseif isvector(res)
            % 向量：每种资源类型的容量
            cap = res(:);
        else
            % 矩阵：尝试提取该智能体对应的列或行
            if size(res, 1) == Value_Params.K && size(res, 2) >= agentIdx
                cap = res(:, agentIdx);
            elseif size(res, 2) == Value_Params.K && size(res, 1) >= agentIdx
                cap = res(agentIdx, :)';
            end
        end
    end
    if isempty(cap)
        % 若 Value_data.resources 不存在，则从 agents 结构体中获取
        cap = agents(agentIdx).resources(:);
    end
    if numel(cap) ~= Value_Params.K
        isFeasible = false;
        info.reason = 'bad_capacity_size';  % 容量向量维度不对
        info.capacitySize = numel(cap);
        return;
    end

    % 计算每种资源类型的总分配量（跨所有任务求和）
    totals = sum(R_agent_Q, 1)';  % totals(r) = 资源类型r的总分配量
    info.totalAllocatedByType = totals;
    info.capacityByType = cap;
    if any(totals - cap > tol)
        % 存在某种资源类型的总分配量超过容量
        isFeasible = false;
        info.reason = 'capacity_exceeded';  % 超过容量限制
        return;
    end

    % ========== 检查4：能量可达性 ==========
    % 验证智能体能否按任务优先级顺序完成所有分配的任务并返回起点
    assignedTasks = find(any(R_agent_Q > tol, 2));  % 找出有资源分配的任务
    info.assignedTasks = assignedTasks(:)';
    info.energyFeasibilityEnabled = true;

    if isempty(assignedTasks)
        % 撤出后不参与任何任务，能量消耗为0，直接可行
        info.requiredEnergy = 0;
        info.taskSequenceByPriority = [];
        info.routeDistance = 0;
        info.t_wait_total = 0;
        info.T_exec_total = 0;
        info.energyCapacity = agents(agentIdx).Emax;
        return;  % 可行
    end

    % 调用统一的能量成本计算函数
    % 计算：起点 -> 按priority排序的任务序列 -> 起点 的总能耗
    [t_wait_total, T_exec_total, totalDistance, requiredEnergy, orderedTasks] = ...
        compute_agent_energy_cost(agentIdx, assignedTasks, agents, tasks, Value_Params, R_agent_Q);

    % 记录能量计算的详细信息
    info.taskSequenceByPriority = orderedTasks(:)';  % 按优先级排序后的任务序列
    info.routeDistance = totalDistance;  % 总路径距离
    info.t_wait_total = t_wait_total;  % 总移动时间
    info.T_exec_total = T_exec_total;  % 总执行时间
    info.requiredEnergy = requiredEnergy;  % 总能量需求
    energyCap = inf;
    if isfield(agents(agentIdx), 'Emax') && ~isempty(agents(agentIdx).Emax)
        energyCap = agents(agentIdx).Emax;
    end
    info.energyCapacity = energyCap;  % 智能体能量上限

    % 检查能量是否充足
    if requiredEnergy > energyCap + tol
        % 能量不足，不可行
        isFeasible = false;
        info.reason = 'energy_insufficient';  % 能量不足
        return;
    end
    % 若所有检查都通过，isFeasible 保持 true
end
