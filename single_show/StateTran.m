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
            %   agent_col_idx     智能体在联盟矩阵中的行索引（注意：虽命名为 col_idx，实际作行索引使用）

            %% 1. 初始化与状态保存
            % 提取系统的宏观维度参数：M个任务，K种资源
            M = Value_Params.M;
            K = Value_Params.K;
            agentID = Value_data.agentID;

            % 保存移动前的“旧状态”（P - Past/Present）
            % SC_P 记录了移动前的全局联盟（各任务分配情况）
            % R_agent_P 记录了移动前该智能体的资源投放矩阵
            SC_P = Value_data.SC;
            R_agent_P = Value_data.resources_matrix;

            % 初始化移动后的“新状态”（Q - Q-state/New）
            % 拷贝一份旧状态，后续我们只在这个副本上进行增量修改，提高计算效率
            SC_Q = SC_P;

            %% 2. 准备智能体资源向量 (防错处理)
            % 提取当前智能体的全部原始资源向量，转为行向量
            raw_res = agents(agentID).resources(:)';

            % 确保资源向量的长度与系统定义的资源种类数 K 严格对齐
            if length(raw_res) >= K
                % 如果智能体资源维度超过了 K，截断保留前 K 个
                agent_full_res = raw_res(1:K);
            else
                % 如果智能体资源维度不足 K，在末尾补 0，代表不具备缺失的资源能力
                agent_full_res = [raw_res, zeros(1, K - length(raw_res))];
            end

            %% 3. 初始化个体的资源状态矩阵
            % 初始化该智能体在新状态下的资源分配矩阵 (M 行 x K 列)
            % 因为是“整体迁移(Switch)”，智能体要撤销所有分散投资，
            % 所以先全盘清零，后面再单独在目标任务上“All-in”
            R_agent_Q = zeros(M, K);

            %% 4. 执行“离开当前任务”操作 (从旧联盟中抹除)
            % 确保当前任务 ID 是合法的（不越界）
            if cur_task_idx <= M
                % 确保全局联盟结构 SC_Q 中，当前任务的矩阵存在且不为空
                if cur_task_idx <= numel(SC_Q) && ~isempty(SC_Q{cur_task_idx})
                    % 核心动作：在当前任务的联盟矩阵中，找到代表该智能体的那一行，将其提供的资源清零。
                    % 这在物理意义上代表：该智能体撤出了分配给该任务的所有资源，退出了联盟。
                    SC_Q{cur_task_idx}(agent_col_idx, :) = 0;
                end
            end

            %% 5. 执行“加入目标任务”操作 (注入新联盟)
            % 确保目标任务 ID 合法
            if target_task_idx <= M

                % A. 更新个体层面的资源矩阵
                % 将智能体的全部资源（agent_full_res）写在目标任务（target_task_idx）对应的行上。
                R_agent_Q(target_task_idx, :) = agent_full_res;

                % B. 更新全局层面的联盟结构 SC_Q
                if target_task_idx <= numel(SC_Q)

                    % 如果目标任务原本没有分配任何智能体，对应的矩阵为空，
                    % 则先初始化一个 N(总智能体数) 行 x K(资源种类) 列的零矩阵，用来存放未来的分配情况
                    if isempty(SC_Q{target_task_idx})
                        SC_Q{target_task_idx} = zeros(Value_Params.N, K);
                    end

                    % 安全校验：确定要填入的列数，防止维度溢出
                    cols_to_fill = min(K, size(SC_Q{target_task_idx}, 2));

                    % 核心动作：在目标任务的联盟矩阵中，找到该智能体对应的行，
                    % 填入它带来的全部资源。这代表它正式带资加入了新任务。
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

            R_agent_P = SS_OCFUtils.get_agent_resource_matrix(SC_P, agentIdx, Value_Params);

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
            R_agent_Q = SS_OCFUtils.get_agent_resource_matrix(SC_Q, agentIdx, Value_Params);
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

            R_agent_P = SS_OCFUtils.get_agent_resource_matrix(SC_P, agentIdx, Value_Params);

            %% 2. 新状态 (Q)
            SC_Q = SC_P;

            % 从目标任务撤出资源
            if target_task_idx <= numel(SC_Q) && ~isempty(SC_Q{target_task_idx})
                SC_Q{target_task_idx}(agentIdx, r) = 0;
            end

            %% 3. 更新资源矩阵
            R_agent_Q = SS_OCFUtils.get_agent_resource_matrix(SC_Q, agentIdx, Value_Params);
        end

    end
end