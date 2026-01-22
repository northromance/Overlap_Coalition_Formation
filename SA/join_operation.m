function [Value_data, incremental_join] = join_operation(Value_data, agents, tasks, Value_Params, probs)
% JOIN_OPERATION 执行智能体加入任务的操作 (SA内核)
% 
% 核心流程：
%   1. 采样：根据概率选择一个目标任务。
%   2. 试探：计算加入该任务后的资源分配变化。
%   3. 验证：检查物理可行性 (能量、载重、非负)。
%   4. 评估：计算效用增量 (Delta U)。
%   5. 决策：根据 Metropolis 准则决定是否接受。
%   6. 更新：如果接受，更新联盟结构、资源分配和时间表。

    incremental_join = 0;
    agentID = Value_data.agentID;
    tol = 1e-9;
    
    % agentID -> agents 索引
    agentIdx = agentID;
    
    % verbose：打印调试信息（默认开，可在 Value_Params.verbose 关闭）
    verbose = true;
    if isfield(Value_Params, 'verbose')
        verbose = logical(Value_Params.verbose);
    end

    % 主流程：对每种资源类型 r 抽一个候选任务 -> 可行性 -> 计算ΔU -> 接受则退出
    for r = 1:Value_Params.K
        
        %% 1. 任务抽样 (Sampling)
        % 根据资源缺口和启发式概率，选择一个目标任务尝试加入
        target = OCFUtils.sample_task_from_probs(probs(r, :), Value_Params.M);
        if isempty(target)
            continue;
        end
        
        %% 2. 生成新状态 (State Generation)
        % 计算加入操作后的联盟结构 (SC) 和资源分配 (R)
        % SC_P/R_agent_P: 操作前 (Previous)
        % SC_Q/R_agent_Q: 操作后 (Query/Proposal)
        [SC_P, SC_Q, R_agent_P, R_agent_Q] = join_changes(Value_data, agents, Value_Params, target, agentID, r);
        
        %% 3. 可行性检测 (Feasibility Check)
        % 检查：非负约束、最大携带量、能量/路径可达性
        % 优化：同时返回 cost_data (包含计算好的路径和能量)，供后续复用
        [feasible, info, cost_data] = validate_feasibility(Value_data, agents, tasks, Value_Params, agentID, SC_P, SC_Q, R_agent_P, R_agent_Q, target, r);
        
        if ~feasible
            if verbose
                % 解释不可行原因
                reason_str = info.reason;
                switch reason_str
                    case 'agent_not_found'
                        reason_detail = '智能体不存在';
                    case 'bad_R_agent_Q_size'
                        reason_detail = '资源矩阵维度错误';
                    case 'negative_allocation'
                        reason_detail = '资源分配为负';
                    case 'capacity_exceeded'
                        reason_detail = '超出资源容量';
                    case 'energy_insufficient'
                        reason_detail = '能量不足(路径不可达)';
                    otherwise
                        reason_detail = reason_str;
                end
                % 仅在调试深度较深时打印拒绝信息，避免刷屏
                % fprintf('智能体%d: 资源类型%d加入任务%d不可行（原因：%s）\n', agentID, r, target, reason_detail);
            end
            continue; % 尝试下一种资源类型
        end
        
        %% 4. 计算效用增量 (Delta U)
        % 计算系统整体效用的变化：Utility(New) - Utility(Old)
        delta_U = overlap_coalition_utility(tasks, agents, SC_P, SC_Q, agentID, Value_Params, Value_data);
        
        %% 5. 决策模块 (Decision Making)
        % 模拟退火 (SA) 准则：
        % - 如果变好 (delta_U > 0)，必然接受。
        % - 如果变差，以 exp(delta_U / T) 的概率接受，防止陷入局部最优。
        accept_join = false;
        
        if delta_U > 0
            accept_join = true;
        else
            T = Value_Params.Temperature;  % 当前温度
            P_join = exp(delta_U / T);     % 接受概率
            number  =rand() ;
            if number < P_join
                accept_join = true;
            end
        end
        
        %% 6. 执行状态更新 (Update State)
        if accept_join
            % --- A. 更新核心数据 ---
            Value_data.SC = SC_Q;                   % 更新全网联盟结构
            Value_data.resources_matrix = R_agent_Q; % 更新个人资源分配
            
            % --- B. 复用计算结果 (Optimization) ---
            % 直接使用可行性检测中计算好的 task_schedule，避免 energy_cost 重复计算
            if exist('cost_data', 'var') && ~isempty(cost_data)
                Value_data.task_schedule = cost_data; 
            end
            
            % --- C. 更新联盟成员矩阵 (coalitionstru) ---
            % 这是一个 (M+1)×N 的矩阵，用于快速索引“谁在哪个任务里”。
            % 第 1~M 行：真实任务
            % 第 M+1 行：Void 任务 (空闲池)
            
            % 1) 扫描当前资源矩阵，找出所有分配量 > 0 的任务索引
            assignedTasksPost = find(any(Value_data.resources_matrix > tol, 2));
            
            % 2) 复制旧结构作为底板
            coalition_after = Value_data.coalitionstru;
            
            % 3) [关键] 清空旧状态
            % 先假设该智能体退出了所有任务（置0）
            coalition_after(1:Value_Params.M, agentIdx) = 0;
            
            % 4) [关键] 写入新状态
            % 将智能体ID填入所有参与的任务行
            for mIdx = assignedTasksPost'
                coalition_after(mIdx, agentIdx) = agents(agentIdx).id;
            end
            
            % 5) [关键] 维护 Void 任务状态
            if isempty(assignedTasksPost)
                % 如果没参与任何任务，放入 Void 池
                coalition_after(Value_Params.M + 1, agentIdx) = agents(agentIdx).id;
            else
                % 如果参与了任务，从 Void 池移除
                coalition_after(Value_Params.M + 1, agentIdx) = 0;
            end
            
            % 6) 写回 Value_data
            Value_data.coalitionstru = coalition_after;
            
            incremental_join = 1;
            
            % --- D. 打印关键变化 (Log) ---
            if verbose
                fprintf('[Join Accept] Agent %d -> Task %d | ResType: %d | Amount: %.2f | dU: %.4f\n', ...
                    agentID, target, r, R_agent_Q(target, r), delta_U);
            end
            
            % 贪婪策略：一旦找到一个可行的优化步骤，立即执行并退出循环，
            % 进入下一轮状态同步或下一个智能体的决策。
            break; 
            
        else
            % 拒绝：回滚（实际上不需要做操作，因为 Value_data 尚未修改）
            % 为了代码健壮性，保持显式回滚逻辑
            Value_data.resources_matrix = R_agent_P;
        end
    end
end