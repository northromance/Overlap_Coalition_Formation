classdef StateTran
    % StateTran 专门用于处理联盟结构与资源状态变化的模块
    % 包含 calc_move_changes（整体迁移）、join_changes（资源加入）、
    % leave_changes（资源撤出）等操作
    
    methods(Static)
        
        function [SC_P, SC_Q, R_agent_P, R_agent_Q] = calc_move_changes(Value_data, agents, Value_Params, cur_task_idx, target_task_idx, agent_col_idx)
            % CALC_MOVE_CHANGES 计算智能体执行一次“整体迁移”（Switch）时，
            % 联盟结构和资源状态的变化。
            %
            % 该函数用于贪婪算法或局部搜索中的 Switch 操作：
            % 智能体从当前任务退出，并将全部资源迁移到目标任务。
            %
            % 输入：
            %   Value_data        当前系统状态
            %   agents            智能体列表
            %   Value_Params      全局参数
            %   cur_task_idx      当前所在任务 ID
            %   target_task_idx   目标任务 ID
            %   agent_col_idx     智能体在联盟矩阵中的行索引
            
            %% 1. 初始化
            M = Value_Params.M;
            K = Value_Params.K;
            agentID = Value_data.agentID;
            
            % 原始状态 (P 状态)
            SC_P = Value_data.SC;
            R_agent_P = Value_data.resources_matrix;
            
            % 初始化新状态 (Q 状态)
            SC_Q = SC_P;
            
            %% 2. 准备智能体资源向量
            raw_res = agents(agentID).resources(:)';
            
            if length(raw_res) >= K
                agent_full_res = raw_res(1:K);
            else
                agent_full_res = [raw_res, zeros(1, K - length(raw_res))];
            end
            
            %% 3. 初始化资源状态
            % 新状态下资源只在目标任务上分配
            R_agent_Q = zeros(M, K);
            
            %% 4. 执行“离开当前任务”操作
            if cur_task_idx <= M
                if cur_task_idx <= numel(SC_Q) && ~isempty(SC_Q{cur_task_idx})
                    SC_Q{cur_task_idx}(agent_col_idx, :) = 0;
                end
            end
            
            %% 5. 执行“加入目标任务”操作
            if target_task_idx <= M
                
                % A. 更新资源矩阵（该智能体的资源全部投入目标任务）
                R_agent_Q(target_task_idx, :) = agent_full_res;
                
                % B. 更新全局联盟结构 SC
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
            % JOIN_CHANGES 计算“资源加入”操作后的状态变化
            %
            % 用于 SA 算法中的微操作 Join：
            % 智能体将某一种资源 r 投入目标任务。
            %
            % 输入：
            %   Value_data   当前系统状态
            %   agents       智能体列表
            %   Value_Params 全局参数
            %   target       目标任务
            %   agentID      智能体 ID
            %   r            资源类型 (1..K)
            
            M = Value_Params.M;
            
            %% 0. 智能体索引检查
            if agentID >= 1 && agentID <= numel(agents) && ...
                    isstruct(agents(agentID)) && agents(agentID).id == agentID
                
                agentIdx = agentID;
            else
                agentIdx = find([agents.id] == agentID, 1, 'first');
                
                if isempty(agentIdx)
                    error('join_changes:AgentNotFound', 'agentID=%d not found.', agentID);
                end
            end
            
            %% 1. 当前状态 (P)
            SC_P = Value_data.SC;
            
            R_agent_P = OCFUtils.get_agent_resource_matrix(SC_P, agentIdx, Value_Params);

            %% 2. 新状态 (Q)
            SC_Q = SC_P;
            
            % 获取该资源类型的容量
            if isfield(Value_data, 'resources')
                 cap_r = Value_data.resources(r); 
            else
                 cap_r = agents(agentIdx).resources(r);
            end
            
            % 执行 Join 操作
            if isempty(SC_Q{target})
                SC_Q{target} = zeros(Value_Params.N, Value_Params.K);
            end
            
            SC_Q{target}(agentIdx, r) = cap_r;
            
            %% 3. 计算新资源状态
            R_agent_Q = OCFUtils.get_agent_resource_matrix(SC_Q, agentIdx, Value_Params);
        end
        

        function [SC_P, SC_Q, R_agent_P, R_agent_Q] = leave_changes(Value_data, agents, Value_Params, target_task_idx, agentID, r)
            % LEAVE_CHANGES 计算“资源撤出”操作后的状态变化
            %
            % 用于 SA 算法中的微操作 Leave：
            % 智能体从某个任务中撤出某一类资源。
            %
            % 输入：
            %   Value_data       当前系统状态
            %   agents           智能体列表
            %   Value_Params     全局参数
            %   target_task_idx  要撤出的任务
            %   agentID          智能体 ID
            %   r                资源类型
            
            M = Value_Params.M;
            
            %% 0. 智能体索引检查
            if agentID >= 1 && agentID <= numel(agents) && ...
                    isstruct(agents(agentID)) && agents(agentID).id == agentID
                
                agentIdx = agentID;
            else
                agentIdx = find([agents.id] == agentID, 1, 'first');
                
                if isempty(agentIdx)
                    error('leave_changes:AgentNotFound', 'agentID=%d not found.', agentID);
                end
            end
            
            %% 1. 当前状态 (P)
            SC_P = Value_data.SC; 
            
            R_agent_P = OCFUtils.get_agent_resource_matrix(SC_P, agentIdx, Value_Params);

            %% 2. 新状态 (Q)
            SC_Q = SC_P;
            
            % 从目标任务撤出资源
            if target_task_idx <= numel(SC_Q) && ~isempty(SC_Q{target_task_idx})
                SC_Q{target_task_idx}(agentIdx, r) = 0;
            end
            
            %% 3. 更新资源矩阵
            R_agent_Q = OCFUtils.get_agent_resource_matrix(SC_Q, agentIdx, Value_Params);
        end
        
    end
end