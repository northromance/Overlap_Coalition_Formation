classdef StateTran
    % StateTransition 专门用于处理联盟结构和资源状态的变更操作
    % 包含：calc_move_changes (全量迁移), join_changes (增量加入) 等
    
    methods(Static)
        
        function [SC_P, SC_Q, R_agent_P, R_agent_Q] = calc_move_changes(Value_data, agents, Value_Params, cur_task_idx, target_task_idx, agent_col_idx)
            % CALC_MOVE_CHANGES 计算智能体从一个任务【全量迁移】到另一个任务时的资源状态变化。
            % 适用场景：贪婪策略中的任务选择（Switch），通常假设单任务模式或全量转移。
            % 核心修正：针对个体资源矩阵 R_agent 采用"全盘清零"策略。
            %
            % 输入：
            %   Value_data: 当前数据状态。
            %   agents: 智能体列表。
            %   Value_Params: 全局参数。
            %   cur_task_idx: 当前所在任务ID (旧任务)。
            %   target_task_idx: 目标任务ID (新任务)。
            %   agent_col_idx: 智能体在矩阵中的行索引。
            
            %% 1. 初始化与备份
            M = Value_Params.M;
            K = Value_Params.K;
            agentID = Value_data.agentID;
            
            % 备份原始状态 (P状态)
            SC_P = Value_data.SC;
            R_agent_P = Value_data.resources_matrix;
            
            % 初始化新状态 (Q状态)，先复制 SC
            SC_Q = SC_P;
            
            %% 2. 准备智能体资源向量
            raw_res = agents(agentID).resources(:)';
            % 确保资源向量维度为 K
            if length(raw_res) >= K
                agent_full_res = raw_res(1:K);
            else
                agent_full_res = [raw_res, zeros(1, K - length(raw_res))];
            end
            
            %% 3. [关键操作] 个体资源矩阵全盘清零
            % 无论之前在哪，新状态 R_agent_Q 应只包含目标任务的资源，其余归零
            R_agent_Q = zeros(M, K);
            
            %% 4. 执行"撤出"逻辑 (更新 SC 全局矩阵)
            % 个体矩阵 R_agent_Q 已在上方清零，此处只需处理 SC_Q
            if cur_task_idx <= M
                % 从旧任务的小组中移除该智能体的资源贡献
                if cur_task_idx <= numel(SC_Q) && ~isempty(SC_Q{cur_task_idx})
                    SC_Q{cur_task_idx}(agent_col_idx, :) = 0;
                end
            end
            
            %% 5. 执行"加入"逻辑 (更新 SC 和 R_agent)
            if target_task_idx <= M
                % A. 个体视图：在目标任务行填入资源 (唯一非零行)
                R_agent_Q(target_task_idx, :) = agent_full_res;
                
                % B. 全局视图：将资源加入新任务的分配矩阵中
                if target_task_idx <= numel(SC_Q)
                    if isempty(SC_Q{target_task_idx})
                        SC_Q{target_task_idx} = zeros(Value_Params.N, K);
                    end
                    cols_to_fill = min(K, size(SC_Q{target_task_idx}, 2));
                    SC_Q{target_task_idx}(agent_col_idx, 1:cols_to_fill) = agent_full_res(1:cols_to_fill);
                end
            end
        end
        
        function [SC_P, SC_Q, R_agent_P, R_agent_Q] = join_changes(Value_data, agents, Value_Params, target, agentID, r)
            % JOIN_CHANGES 计算【单资源增量加入】操作前后的全局结构与个体状态变化。
            % 适用场景：SA算法中的微调（Join），支持重叠联盟。
            %
            % 输入：
            %   Value_data: 当前数据状态
            %   agents: 智能体列表
            %   Value_Params: 全局参数
            %   target: 目标任务索引
            %   agentID: 智能体 ID
            %   r: 要投入的资源类型索引 (1..K)
            
            M = Value_Params.M;
            
            %% 0. 索引转换与校验
            % 确保获取的是矩阵中的行索引
            if agentID >= 1 && agentID <= numel(agents) && isstruct(agents(agentID)) && agents(agentID).id == agentID
                agentIdx = agentID;
            else
                agentIdx = find([agents.id] == agentID, 1, 'first');
                if isempty(agentIdx)
                    error('join_changes:AgentNotFound', 'agentID=%d not found.', agentID);
                end
            end
            
            %% 1. 获取操作前状态 (P)
            SC_P = Value_data.SC; % 引用当前状态
            
            % 调用本类内部的工具函数提取操作前的个体矩阵
            R_agent_P = OCFUtils.get_agent_resource_matrix(SC_P, agentIdx, Value_Params);

            %% 2. 构建操作后状态 (Q)
            SC_Q = SC_P; % 复制 Cell 数组
            
            % 获取该资源类型的可用量（假设全量投入）
            if isfield(Value_data, 'resources')
                 cap_r = Value_data.resources(r); 
            else
                 cap_r = agents(agentIdx).resources(r);
            end
            
            % 执行 Join：更新目标任务的分配矩阵
            if isempty(SC_Q{target})
                SC_Q{target} = zeros(Value_Params.N, Value_Params.K);
            end
            SC_Q{target}(agentIdx, r) = cap_r;
            
            %% 3. 获取操作后状态 (Q) 的个体视图
            % 调用本类内部的工具函数提取操作后的个体矩阵
            R_agent_Q = OCFUtils.get_agent_resource_matrix(SC_Q, agentIdx, Value_Params);
        end
        


        function [SC_P, SC_Q, R_agent_P, R_agent_Q] = leave_changes(Value_data, agents, Value_Params, target_task_idx, agentID, r)
            % LEAVE_CHANGES 计算【单资源撤出】操作前后的全局结构与个体状态变化。
            % 适用场景：SA算法中的微调（Leave），将某一种资源从特定任务中完全撤回。
            %
            % 输入：
            %   Value_data: 当前数据状态
            %   agents: 智能体列表
            %   Value_Params: 全局参数
            %   target_task_idx: 要离开的目标任务索引
            %   agentID: 智能体 ID
            %   r: 要撤出的资源类型索引 (1..K)
            
            M = Value_Params.M;
            
            %% 0. 索引转换与校验
            % 确保获取的是矩阵中的行索引
            if agentID >= 1 && agentID <= numel(agents) && isstruct(agents(agentID)) && agents(agentID).id == agentID
                agentIdx = agentID;
            else
                agentIdx = find([agents.id] == agentID, 1, 'first');
                if isempty(agentIdx)
                    error('leave_changes:AgentNotFound', 'agentID=%d not found.', agentID);
                end
            end
            
            %% 1. 获取操作前状态 (P)
            SC_P = Value_data.SC; 
            
            % 提取操作前的个体矩阵 (用于对比或恢复)
            R_agent_P = OCFUtils.get_agent_resource_matrix(SC_P, agentIdx, Value_Params);

            %% 2. 构建操作后状态 (Q)
            SC_Q = SC_P; % 复制 Cell 数组
            
            % 执行 Leave：将目标任务的特定资源分配置为 0 (完全撤出)
            if target_task_idx <= numel(SC_Q) && ~isempty(SC_Q{target_task_idx})
                SC_Q{target_task_idx}(agentIdx, r) = 0;
            end
            
            %% 3. 获取操作后状态 (Q) 的个体视图
            % 调用工具函数重新生成 R_agent_Q，确保数据一致性
            R_agent_Q = OCFUtils.get_agent_resource_matrix(SC_Q, agentIdx, Value_Params);
        end
        
    end % end methods
end % end classdef