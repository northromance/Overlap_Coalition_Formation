function [Value_data, incremental_leave] = leave_operation(Value_data, agents, tasks, Value_Params, probs)
% LEAVE_OPERATION 执行智能体退出任务的操作 (SA算子)
%
% 功能描述：
%   尝试让当前智能体 (Value_data.agentID) 从其已加入的某个任务中完全撤出某类资源。
%   这是模拟退火算法中的“破坏”或“收缩”步骤，有助于释放资源给更重要的任务，
%   或通过接受劣解来跳出局部最优。
%
% 核心流程：
%   1. 筛选：找出该智能体当前已分配资源的任务。
%   2. 试探：构造“撤出该任务该资源”后的新状态。
%   3. 验证：检查撤出后的状态是否物理可行 (特别是路径/能量约束)。
%   4. 评估：计算效用变化 Delta U。
%   5. 决策：根据 SA 温度概率决定是否执行。
%   6. 更新：更新数据结构 (SC, resources, coalitionstru)。
%
% 输入：
%   Value_data   - 智能体状态结构体
%   agents       - 智能体物理属性
%   tasks        - 任务属性
%   Value_Params - 全局参数 (温度, 维度等)
%   probs        - (此处未使用，保留接口兼容性)
%
% 输出：
%   Value_data        - 更新后的状态
%   incremental_leave - 成功标志 (1=成功执行, 0=未执行)

    incremental_leave = 0;  % 初始化：默认操作未执行
    agentID = Value_data.agentID;
    
    % 获取维度信息
    M = Value_Params.M;  % 任务数
    K = Value_Params.K;  % 资源类型数
    tol = 1e-9;          % 浮点数容差
    
    % 智能体索引转换 (ID -> Index)
    agentIdx = agentID;
    if agentIdx < 1 || agentIdx > numel(agents) || ~isstruct(agents(agentIdx))
        agentIdx = find([agents.id] == agentID, 1, 'first');
        if isempty(agentIdx)
            error('leave_operation:AgentNotFound', 'agentID=%d not found in agents.', agentID);
        end
    end
    
    % 调试开关
    verbose = true;
    if isfield(Value_Params, 'verbose')
        verbose = logical(Value_Params.verbose);
    end
    
    % 备份原始资源矩阵 (用于最后的全局回滚)
    original_resources_matrix = Value_data.resources_matrix;
    
    % --- 0. 快速剪枝 ---
    % 如果智能体当前什么任务都没做（全0），则无法执行撤出操作，直接返回
    if all(Value_data.resources_matrix(:) <= tol)
        return;
    end
    
    %% 主循环：遍历每种资源类型，寻找撤出机会
    for r = 1:K
        
        % --- 1. 寻找候选任务 ---
        % 获取该智能体在资源类型 r 上的所有分配情况
        currentAllocColumn = Value_data.resources_matrix(:, r);
        
        % 找出分配量 > 0 的任务索引
        candidateTasks = find(currentAllocColumn > tol);
        
        if isempty(candidateTasks)
            continue; % 该资源类型没分配给任何人，跳过
        end
        
        % --- 2. 遍历候选任务，逐个尝试撤出 ---
        for taskIdx = 1:numel(candidateTasks)
            sourceTask = candidateTasks(taskIdx);  % 目标任务 ID
            
            % 获取当前分配量
            currentAmount = currentAllocColumn(sourceTask);
            if currentAmount <= tol
                continue;
            end
            
            % --- 3. 定义撤出行为 ---
            % 策略：完全撤出 (Full Withdrawal)
            % 将该任务上的该资源分配量直接置为 0
            remainingAmount = 0; 
            
            % --- 4. 构造新旧状态 (State Construction) ---
            
            % 4.1 记录操作前状态 (P = Previous)
            SC_P = Value_data.SC;                     % 原始联盟结构
            R_agent_P = Value_data.resources_matrix;  % 原始资源分配
            
            % 4.2 构造操作后状态 (Q = Query)
            R_agent_Q = R_agent_P;
            R_agent_Q(sourceTask, r) = remainingAmount; % 修改：置零
            
            % 4.3 同步更新联盟结构 SC_Q
            SC_Q = SC_P;
            for m = 1:M
                % 获取任务 m 的当前分配矩阵 (N x K)
                taskMatrix = SC_Q{m};
                % 更新当前智能体 (agentIdx) 的行
                taskMatrix(agentIdx, :) = R_agent_Q(m, :);
                SC_Q{m} = taskMatrix;
            end
            
            % --- 5. 可行性验证 (Feasibility Check) ---
            % 撤出操作看似简单，但也可能导致不可行。
            % 例如：如果任务之间有某种依赖，或者撤出导致路径改变后的能量计算出现问题
            % (虽然通常撤出只会省能量，但逻辑上必须验证一致性)
            [feasible, info, cost_data] = validate_feasibility(Value_data, agents, tasks, Value_Params, agentID, SC_P, SC_Q, R_agent_P, R_agent_Q, sourceTask, r);
            
            if ~feasible
                if verbose
                    % 打印拒绝原因
                    reason_str = 'unknown';
                    if isfield(info, 'reason'), reason_str = info.reason; end
                    % (此处省略详细的 switch-case 打印逻辑以保持简洁，参考 join_operation)
                    % fprintf('智能体%d: 撤出任务%d不可行 (%s)\n', agentID, sourceTask, reason_str);
                end
                continue; % 尝试下一个任务
            end
            
            % --- 6. 计算效用变化 ΔU ---
            % 临时将资源矩阵设为 Q 状态以供计算函数使用
            Value_data.resources_matrix = R_agent_Q;
            
            % Delta U = Utility(New) - Utility(Old)
            % 注意：撤出通常会导致任务完成度下降，从而导致效用下降 (ΔU < 0)。
            % 但这正是 SA 的精髓：允许暂时变差，以寻找全局更优。
            delta_U = overlap_coalition_utility(tasks, agents, SC_P, SC_Q, agentID, Value_Params, Value_data);
            
            % --- 7. 决策 (Decision Making) ---
            accept_leave = false;
            
            if delta_U > 0
                % 情况 A: 撤出反而让效用增加了？
                % (例如：减少了过度拥挤导致的惩罚，或者省下的能量带来的收益 > 任务损失)
                accept_leave = true;
            else
                % 情况 B: 效用下降，按概率接受 (模拟退火)
                T = 1;
                if isfield(Value_Params, 'Temperature') && ~isempty(Value_Params.Temperature)
                    T = Value_Params.Temperature;
                end
                if abs(T) < tol, T = 1; end % 防止除零
                
                % Metropolis 准则
                acceptProb = exp(delta_U / T);
                
                if rand() < acceptProb
                    accept_leave = true;
                end
            end
            
            % --- 8. 执行更新 (Execute) ---
            if accept_leave
                % 确认接受：更新核心数据结构
                Value_data.SC = SC_Q;
                
                % [优化] 复用可行性验证中计算好的时间表
                if exist('cost_data', 'var')
                    Value_data.cost_data = cost_data;
                    % 注意：这里通常还需要更新 Value_data.task_schedule
                    if isstruct(cost_data)
                        Value_data.task_schedule = cost_data;
                    end
                end
                
                % --- 更新成员矩阵 coalitionstru ---
                % 重新扫描资源矩阵，确定智能体当前到底参与了哪些任务
                assignedTasksPost = find(any(R_agent_Q > tol, 2)); % 只要有资源投入就算参与
                
                coalition_after = Value_data.coalitionstru;
                % 1. 清空所有真实任务行的标记
                coalition_after(1:M, agentIdx) = 0;
                
                % 2. 重新标记参与的任务
                for mIdx = assignedTasksPost'
                    coalition_after(mIdx, agentIdx) = agents(agentIdx).id;
                end
                
                % 3. 维护 Void 任务 (第 M+1 行)
                if isempty(assignedTasksPost)
                    % 如果什么都没做，标记为闲置
                    coalition_after(M + 1, agentIdx) = agents(agentIdx).id;
                else
                    % 如果有活干，移出闲置列表
                    coalition_after(M + 1, agentIdx) = 0;
                end
                
                Value_data.coalitionstru = coalition_after;
                
                % 设置成功标志并退出
                incremental_leave = 1;
                if verbose
                    fprintf('[Leave Accept] Agent %d <- Task %d | ResType: %d | dU: %.4f\n', ...
                        agentID, sourceTask, r, delta_U);
                end
                break; % 贪婪策略：找到一个动作就执行并退出，进入下一轮同步
                
            else
                % 拒绝：回滚资源矩阵
                % 注意：SC 和 coalitionstru 此时还没改，只需回滚 resources_matrix 即可
                Value_data.resources_matrix = R_agent_P;
            end
            
        end % end for tasks
        
        if incremental_leave == 1
            break; % 已执行操作，跳出外层循环
        end
    end % end for resource types
    
    % --- 9. 全局安全回滚 ---
    % 如果遍历了所有可能都没能成功执行撤出，确保数据一致性
    if incremental_leave == 0
        Value_data.resources_matrix = original_resources_matrix;
    end

end