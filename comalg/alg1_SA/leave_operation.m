function [Value_data, incremental_leave] = leave_operation(Value_data, agents, tasks, Value_Params, probs, AddPara)
% LEAVE_OPERATION 执行智能体退出任务的操作 (SA算子) - [带详细日志版]
%
% 修改说明：
%   1. 增加了 accept_type 变量，用于记录接受撤出的具体原因。
%   2. 优化了日志输出，明确显示是 "优化(Optimization)" 还是 "概率跳出(SA_Jump)"。

    incremental_leave = 0;
    agentID = Value_data.agentID;
    
    M = Value_Params.M;
    K = Value_Params.K;
    tol = 1e-9;
    
    agentIdx = agentID;
    if agentIdx < 1 || agentIdx > numel(agents) || ~isstruct(agents(agentIdx))
        agentIdx = find([agents.id] == agentID, 1, 'first');
    end
    
    verbose = true;
    if isfield(AddPara, 'verbose')
        verbose = logical(AddPara.verbose);
    end
    
    original_resources_matrix = Value_data.resources_matrix;
    
    % --- 0. 快速剪枝 ---
    if all(Value_data.resources_matrix(:) <= tol)
        return;
    end
    
    %% 主循环
    for r = 1:K
        currentAllocColumn = Value_data.resources_matrix(:, r);
        candidateTasks = find(currentAllocColumn > tol);
        
        if isempty(candidateTasks), continue; end
        
        for taskIdx = 1:numel(candidateTasks)
            sourceTask = candidateTasks(taskIdx);
            
            % 1. 生成撤出后的状态
            [SC_P, SC_Q, R_agent_P, R_agent_Q] = StateTran.leave_changes(Value_data, agents, Value_Params, sourceTask, agentID, r);
            
            % 更新临时状态以计算效用
            Value_data.resources_matrix = R_agent_Q;
            
            % 2. 计算效用差 (Delta U)
            delta_U = Preference_gain(tasks, agents, SC_P, SC_Q, agentID, Value_Params, Value_data);
            
            % 3. 决策 (Decision Making)
            accept_leave = false;
            accept_type = ''; % [新增] 用于记录接受原因
            
            if delta_U > 0
                % --- 情况 A: 优化 (Optimization) ---
                accept_leave = true;
                accept_type = 'Optimization (dU > 0)'; 
            else
                % --- 情况 B: 模拟退火概率跳出 (SA Jump) ---
                T = 1;
                if isfield(Value_Params, 'Temperature') && ~isempty(Value_Params.Temperature)
                    T = Value_Params.Temperature;
                end
                if abs(T) < tol, T = 1; end
                
                acceptProb = exp(delta_U / T);
                
                if rand() < acceptProb
                    accept_leave = true;
                    % 记录概率值，方便调试查看概率有多大
                    accept_type = sprintf('SA_Jump (P=%.2f%%, T=%.1f)', acceptProb * 100, T);
                end
            end
            
            % 4. 执行更新
            if accept_leave
                Value_data.SC = SC_Q;
                Value_data.resources_matrix = R_agent_Q;
                
                % [注] Leave 操作通常不需要重新规划路径(cost_data)，除非有显式的依赖
                % 但为了兼容原有逻辑保留此处，虽然后在 Leave 中通常不存在 cost_data 变量
                if exist('cost_data', 'var') && ~isempty(cost_data)
                    Value_data.task_schedule = cost_data;
                end
                
                % 更新 coalitionstru
                assignedTasksPost = find(any(R_agent_Q > tol, 2)); 
                coalition_after = Value_data.coalitionstru;
                coalition_after(1:M, agentIdx) = 0;
                for mIdx = assignedTasksPost'
                    coalition_after(mIdx, agentIdx) = agents(agentIdx).id;
                end
                if isempty(assignedTasksPost)
                    coalition_after(M + 1, agentIdx) = agents(agentIdx).id;
                else
                    coalition_after(M + 1, agentIdx) = 0;
                end
                Value_data.coalitionstru = coalition_after;
                
                incremental_leave = 1;
                
                % --- [修改] 打印详细日志 ---
                if verbose
                    fprintf('[Leave Accept] Agent %d <- Task %d | ResType: %d | dU: %.4f | 原因: %s\n', ...
                        agentID, sourceTask, r, delta_U, accept_type);
                end
                
                break; % 成功执行一个操作后退出
            else
                % 拒绝：回滚
                Value_data.resources_matrix = R_agent_P;
            end
        end 
        if incremental_leave == 1, break; end
    end 
    
    if incremental_leave == 0
        Value_data.resources_matrix = original_resources_matrix;
    end
end