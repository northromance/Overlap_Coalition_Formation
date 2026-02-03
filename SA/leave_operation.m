function [Value_data, incremental_leave] = leave_operation(Value_data, agents, tasks, Value_Params, probs,AddPara)
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
%   Value_data   - 智能体状态结构体 (包含当前资源分配、信念等)
%   agents       - 智能体物理属性 (结构体数组)
%   tasks        - 任务属性 (结构体数组)
%   Value_Params - 全局参数 (温度, 维度, 惩罚因子等)
%   probs        - (此处未使用，保留接口兼容性)
%
% 输出：
%   Value_data        - 更新后的状态结构体
%   incremental_leave - 成功标志 (1=成功执行并接受, 0=未执行或被拒绝)

    incremental_leave = 0;  % 初始化：默认操作未执行
    agentID = Value_data.agentID;
    
    % 获取维度信息
    M = Value_Params.M;  % 任务数
    K = Value_Params.K;  % 资源类型数
    tol = 1e-9;          % 浮点数容差 (判断是否为0)
    
    % 智能体索引转换 (ID -> Index)
    % 确保能够正确索引 agents 数组
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
    
    % 备份原始资源矩阵 (用于最后的全局回滚，以防万一)
    original_resources_matrix = Value_data.resources_matrix;
    
    % --- 0. 快速剪枝 ---
    % 如果智能体当前什么任务都没做（全0），则无法执行撤出操作，直接返回
    if all(Value_data.resources_matrix(:) <= tol)
        return;
    end
    
    %% 主循环：遍历每种资源类型，寻找撤出机会
    for r = 1:K
        
        % --- 1. 寻找候选任务 ---
        % 获取该智能体在资源类型 r 上的所有分配情况 (M x 1 向量)
        currentAllocColumn = Value_data.resources_matrix(:, r);
        
        % 找出分配量 > 0 的任务索引
        candidateTasks = find(currentAllocColumn > tol);
        
        if isempty(candidateTasks)
            continue; % 该资源类型没分配给任何人，尝试下一类资源
        end
        
        % --- 2. 遍历候选任务，逐个尝试撤出 ---
        for taskIdx = 1:numel(candidateTasks)
            sourceTask = candidateTasks(taskIdx);  % 目标任务 ID (计划从中撤退)
        
             [SC_P, SC_Q, R_agent_P, R_agent_Q] = StateTran.leave_changes(Value_data, agents, Value_Params, sourceTask, agentID, r);
            
            % --- 5. 可行性验证 (Feasibility Check) ---
            % 撤出操作看似简单(只是省资源)，但也可能导致不可行。
            % 原因：
            % 1. 任务路径改变：撤出任务可能改变访问顺序，进而改变飞行距离和能耗。
            % 2. 约束耦合：某些约束可能要求必须同时提供多种资源(虽少见，但通用性需考虑)。
            % 3. 队友影响：撤出可能影响队友的等待时间
            % [feasible, info, cost_data] = validate_feasibility(Value_data, agents, tasks, Value_Params, agentID, SC_Q, true);
            
            % % if ~feasible
            %     if verbose
            %         % 打印拒绝原因 (调试用)
            %         reason_str = 'unknown';
            %         if isfield(info, 'reason'), reason_str = info.reason; end
            %         % fprintf('智能体%d: 撤出任务%d不可行 (%s)\n', agentID, sourceTask, reason_str);
            %     end
            %     % continue; % 不可行，尝试下一个任务
            % % end
            
            % --- 6. 计算效用变化 ΔU ---
            % 临时将 Value_data 中的资源矩阵设为 Q 状态，以便效用函数读取
            % 注意：这只是临时的，如果拒绝会回滚
            Value_data.resources_matrix = R_agent_Q;
            
            % 调用 BMBT 偏好计算函数
            % Delta U = Utility(New) - Utility(Old)
            % 预期：撤出通常会导致任务资源不足，效用下降 (ΔU < 0)。
            delta_U = Preference_gain(tasks, agents, SC_P, SC_Q, agentID, Value_Params, Value_data);
            
            % --- 7. 决策 (Decision Making) ---
            accept_leave = false;
            
            if delta_U > 0
                % 情况 A: 撤出反而让效用增加了？(Delta > 0)
                % 解释：
                % 1. 可能是之前的分配造成了巨大的路径绕行惩罚，撤出后路径变优，省下的成本 > 任务收益损失。
                % 2. 或者是减少了某个拥挤任务的过度分配惩罚。
                accept_leave = true;
            else
                % 情况 B: 效用下降 (Delta < 0) -> SA 核心逻辑
                % 我们以一定概率接受"变差"的操作，防止算法卡在局部最优解。
                
                T = 1; % 默认温度
                if isfield(Value_Params, 'Temperature') && ~isempty(Value_Params.Temperature)
                    T = Value_Params.Temperature;
                end
                if abs(T) < tol, T = 1; end % 保护：防止除零错误
                
                % Metropolis 准则: P = exp(Delta / T)
                % Delta是负数，T是正数，所以 P < 1
                acceptProb = exp(delta_U / T);
                
                if rand() < acceptProb
                    accept_leave = true;
                end
            end
            
            % --- 8. 执行更新 (Execute Update) ---
            if accept_leave
                % === 确认接受：正式更新核心数据结构 ===
                
                % A. 更新联盟结构 (SC)
                Value_data.SC = SC_Q;
                
                % B. 更新资源矩阵 (resources_matrix)
                % (实际上在 Step 6 已经赋值了，这里确认保留)
                Value_data.resources_matrix = R_agent_Q;
                
                % C. 更新时间表和成本数据 (Optimization)
                % 直接复用可行性验证中计算好的 task_schedule，避免 energy_cost 重复计算
                if exist('cost_data', 'var') && ~isempty(cost_data)
                    Value_data.cost_data = cost_data; % 缓存成本数据
                    if isstruct(cost_data)
                        Value_data.task_schedule = cost_data; % 更新时间表
                    end
                end
                
                % D. 更新联盟成员矩阵 (coalitionstru)
                % 这是一个 (M+1) x N 的矩阵，用于快速索引“谁在哪个任务里”
                
                % 1) 重新扫描资源矩阵，找出所有分配量 > 0 的任务索引
                assignedTasksPost = find(any(R_agent_Q > tol, 2)); 
                
                coalition_after = Value_data.coalitionstru;
                
                % 2) 先假设该智能体退出了所有真实任务（1~M行置0）
                coalition_after(1:M, agentIdx) = 0;
                
                % 3) 根据扫描结果，重新填入 ID
                for mIdx = assignedTasksPost'
                    coalition_after(mIdx, agentIdx) = agents(agentIdx).id;
                end
                
                % 4) 维护 Void 任务 (第 M+1 行) - 也就是空闲池
                if isempty(assignedTasksPost)
                    % 如果什么都没做，标记为闲置 (填入ID)
                    coalition_after(M + 1, agentIdx) = agents(agentIdx).id;
                else
                    % 如果有活干，移出闲置列表 (置0)
                    coalition_after(M + 1, agentIdx) = 0;
                end
                
                Value_data.coalitionstru = coalition_after;
                
                % 设置成功标志
                incremental_leave = 1;
                
                % 打印日志
                if verbose
                    fprintf('[Leave Accept] Agent %d <- Task %d | ResType: %d | dU: %.4f\n', ...
                        agentID, sourceTask, r, delta_U);
                end
                
                % 贪婪策略：一旦找到一个可行的优化步骤，立即执行并退出循环，
                % 进入下一轮状态同步或下一个智能体的决策。
                break; 
                
            else
                % === 拒绝：回滚 ===
                % 只需回滚 resources_matrix 即可，因为 SC 和 coalitionstru 还没改
                Value_data.resources_matrix = R_agent_P;
            end
            
        end % end for tasks (遍历候选任务)
        
        if incremental_leave == 1
            break; % 已执行操作，跳出资源类型循环
        end
    end % end for resource types (遍历资源类型)
    
    % --- 9. 全局安全回滚 ---
    % 如果遍历了所有可能都没能成功执行撤出 (或者都被拒绝了)，
    % 确保数据完全恢复到函数入口时的状态
    if incremental_leave == 0
        Value_data.resources_matrix = original_resources_matrix;
    end
end