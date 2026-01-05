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

% 智能体索引转换
agentIdx = agentID;
if agentIdx < 1 || agentIdx > numel(agents) || ~isstruct(agents(agentIdx))
    agentIdx = find([agents.id] == agentID, 1, 'first');
    if isempty(agentIdx)
        error('leave_operation:AgentNotFound', 'agentID=%d not found in agents.', agentID);
    end
end

% 设置调试输出开关
verbose = true;
if isfield(Value_Params, 'verbose')
    verbose = logical(Value_Params.verbose);
end

% 备份原始资源分配矩阵（若所有撤出尝试都失败，则回滚）
original_resources_matrix = Value_data.resources_matrix;

% 前置检查：如果智能体没有分配资源给任何任务，直接返回
if all(Value_data.resources_matrix(:) <= tol)
    % 该智能体未参与任何任务，无需撤出
    if verbose
        fprintf('智能体%d: 未分配任何资源，无需退出操作\n', agentID);
    end
    return;
end

%% 主循环：遍历每种资源类型，尝试撤出
for r = 1:K
    % 1) 找出当前智能体在资源类型r上已分配的所有任务
    currentAllocColumn = Value_data.resources_matrix(:, r);  % 该智能体对所有任务的资源r分配
    candidateTasks = find(currentAllocColumn > tol);  % 找出有分配的任务（分配量>0）
    if isempty(candidateTasks)
        % 该资源类型未分配给任何任务，跳过
        continue;
    end

    % 2) 遍历该资源类型下的所有候选任务，逐个尝试撤出
    for taskIdx = 1:numel(candidateTasks)
        sourceTask = candidateTasks(taskIdx);  % 当前尝试撤出的任务

        % 3) 获取当前分配量，检查是否有效
        currentAmount = currentAllocColumn(sourceTask);  % 该任务上资源r的当前分配量
        if currentAmount <= tol
            % 分配量接近0，无法撤出，跳过该任务
            continue;
        end

        % 4) 撤出全部该资源类型：直接将该任务上的资源类型r分配量清零
        remainingAmount = 0;  % 撤出后该任务该资源类型分配量为0
        releasedAmount = currentAmount;  % 释放全部分配量
        if releasedAmount <= tol
            % 释放量太小，跳过该任务
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
        [feasible, info] = validate_feasibility(Value_data, agents, tasks, Value_Params, agentID, SC_P, SC_Q, R_agent_P, R_agent_Q, sourceTask, r);
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

            % 12.3) 设置撤出成功标志，打印日志，并跳出所有循环
            incremental_leave = 1;  % 标记本轮成功执行了撤出
            if verbose
                fprintf('  资源分配变化: 任务%d释放资源类型%d数量%.2f\n', sourceTask, r, releasedAmount);
            end
            break;  % 跳出候选任务循环
        else
            % 拒绝撤出：回滚 resources_matrix 到操作前状态
            Value_data.resources_matrix = R_agent_P;
        end
    end  % 结束候选任务循环

    % 如果已成功撤出，跳出资源类型循环
    if incremental_leave == 1
        break;
    end
end

% ========== 13) 全局回滚检查 ==========
% 若本轮所有资源类型的撤出尝试都失败（incremental_leave 仍为0），
% 则将 resources_matrix 回滚到进入函数时的初始状态
if incremental_leave == 0
    Value_data.resources_matrix = original_resources_matrix;
end
end

