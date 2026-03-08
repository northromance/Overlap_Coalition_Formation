classdef UtilityEvaluator
    % UtilityEvaluator 效用评估类
    % 提供智能体效用计算 (Agent View) 和全局效用指标评估 (Global View)。
    
    methods(Static)
        %
        % function agentutility = calc_agent_total_utility(SC, agents, tasks, Value_Params, Value_data, AddPara)
        %     % CALC_AGENT_TOTAL_UTILITY 计算智能体在当前联盟结构 SC 下的总净效用 (个体视角)
        %     %
        %     % 计算逻辑：Total Utility = (Sum of Revenues) - (Total Path Cost)
        %     %
        %     % 输入：
        %     %   SC           - 全局联盟结构 (Cell Array)
        %     %   agents       - 智能体结构体数组
        %     %   tasks        - 任务结构体数组
        %     %   Value_Params - 全局参数
        %     %   Value_data   - 包含 agentID/agentIndex 和 initbelief
        %     %   AddPara      - (可选) 包含 resource_confidence 等参数
        %
        %     %% 0. 初始化与基础准备
        %     tol = 1e-9;
        %
        %     % 获取当前智能体 ID
        %     if isfield(Value_data, 'agentID')
        %         agent_id = Value_data.agentID;
        %     elseif isfield(Value_data, 'agentIndex')
        %         agent_id = Value_data.agentIndex;
        %     else
        %         error('无法在 Value_data 中找到 agent_id');
        %     end
        %
        %     K = Value_Params.K;
        %     M = Value_Params.M;
        %     alpha_fly = agents(agent_id).fuel;
        %     alpha_wait = agents(agent_id).wait_fuel;
        %     beta = agents(agent_id).beta;
        %
        %     % 获取分配的任务列表
        %     task_list = OCFUtils.get_agent_tasks_fast(SC, agent_id, tol);
        %     task_list = task_list(task_list <= M); % 过滤无效任务
        %
        %     if isempty(task_list)
        %         agentutility = 0;
        %         return;
        %     end
        %
        %     %% 1. 第一阶段：累计总收益 (Total Revenue)
        %     total_revenue = 0;
        %
        %     % 获取置信度参数
        %     confidence = 0.9; % 默认值
        %     if nargin >= 6 && isfield(AddPara, 'resource_confidence')
        %         confidence = AddPara.resource_confidence;
        %     end
        %
        %     task_type_demands = Value_Params.task_type_demands;
        %     task_types = Value_Params.task_type;
        %
        %     for i = 1:length(task_list)
        %         curr_task = task_list(i);
        %
        %         % A. 准备任务信念
        %         belief = Value_data.initbelief(curr_task, :);
        %
        %         % 使用分位数计算需求
        %         demand = WorldSim.calculate_demand_quantile(belief, task_type_demands, confidence);
        %
        %         % B. 获取参与者状态
        %         participants = OCFUtils.get_participants(SC, curr_task, tol);
        %         SC_task = SC{curr_task};
        %
        %         % C. 计算任务完成度
        %         total_resources = sum(SC_task(participants, :), 1);
        %         D_C = WorldSim.calc_task_completion_degree(total_resources, demand, K);
        %
        %         if D_C <= tol
        %             continue;
        %         end
        %
        %         % D. 计算资源贡献比例
        %         r_n_C = OCFUtils.calc_resource_contribution_ratio(SC_task, agent_id, participants);
        %
        %         % E. 计算任务期望值
        %         values = tasks(curr_task).WORLD.value;
        %         tlen = min([task_types, numel(values), size(belief, 2)]);
        %         V_C = sum(values(1:tlen) .* belief(1:tlen));
        %
        %         % F. 累计收益
        %         total_revenue = total_revenue + (r_n_C * V_C * D_C);
        %     end
        %
        %     %% 2. 第二阶段：计算总成本 (Total Cost)
        %     % 任务排序
        %     orderedTasks = OCFUtils.sort_tasks_by_priority(task_list, tasks);
        %
        %     % 全局同步推演时间
        %     [t_fly, t_wait, t_exec] = WorldSim.calc_with_global_sync( ...
        %         agent_id, orderedTasks, agents, tasks, Value_Params, SC, tol);
        %
        %     % 综合总成本
        %     total_cost = t_fly * alpha_fly + t_wait * alpha_wait + t_exec * beta;
        %
        %     %% 3. 第三阶段：计算净效用
        %     agentutility = total_revenue - total_cost;
        % end
        
        
        
        function [agentutility, task_utilities] = calc_agent_total_utility(SC, agents, tasks, Value_Params, Value_data, AddPara)
  
            
            tol = 1e-9;
            
            % 获取当前智能体 ID 及环境维度，兼容 agentID 或 agentIndex 两种字段命名
            if isfield(Value_data, 'agentID')
                agent_id = Value_data.agentID;
            else
                agent_id = Value_data.agentIndex;
            end
            K = Value_Params.K;   % 资源种类数
            M = Value_Params.M;   % 任务数
            N = Value_Params.N;   % 智能体数
            
            % 获取智能体 n 参与的任务列表并过滤无效任务
            task_list = OCFUtils.get_agent_tasks_fast(SC, agent_id, tol);
            task_list = task_list(task_list <= M);
            task_utilities = containers.Map('KeyType', 'double', 'ValueType', 'double');
            
            % 若未参与任何任务，效用为 0
            if isempty(task_list)
                agentutility = 0;
                return;
            end
            
            % 获取资源置信度，默认 0.9
            confidence = Value_Params.resource_confidence;
            
            task_type_demands = Value_Params.task_type_demands;
            task_types = Value_Params.task_type;
            
            %% 第一阶段：预计算所有智能体的路径总成本 C_i
            % C_i = alpha_fly * t_fly_i + alpha_wait * t_wait_i + beta * t_exec_i
            % 需对全局 N 个智能体进行推演，以便计算联盟成本 Cost(A_m) 分摊
            agent_costs = zeros(N, 1);
            all_agents_results = WorldSim.calc_all_agents_with_global_sync(agents, tasks, Value_Params, SC, tol);
            for i = 1:N
                agent_costs(i) = all_agents_results(i).t_fly_total * agents(i).fuel ...
                    + all_agents_results(i).t_wait_total * agents(i).wait_fuel ...
                    + all_agents_results(i).t_exec_total * agents(i).beta;
            end

            % 预计算每个智能体投入到所有任务的总资源量，用于将全局成本分摊到具体任务
            agent_total_resources = zeros(N, 1);
            for i = 1:N
                tasks_i = OCFUtils.get_agent_tasks_fast(SC, i, tol);
                tasks_i = tasks_i(tasks_i <= M);
                for task_idx = 1:length(tasks_i)
                    task_id = tasks_i(task_idx);
                    agent_total_resources(i) = agent_total_resources(i) + sum(SC{task_id}(i, :));
                end
            end
            
            %% 第二阶段：计算各任务净效用并按资源比例分摊给智能体 n
            agentutility = 0;
            
            for idx = 1:length(task_list)
                curr_task = task_list(idx);
                
                % --- A. 计算任务需求（基于信念分布的分位数需求） ---
                belief = Value_data.initbelief(curr_task, :);
                demand = WorldSim.calculate_demand_quantile(belief, task_type_demands, confidence);
                
                % --- B. 获取联盟成员及资源分配矩阵 ---
                participants = OCFUtils.get_participants(SC, curr_task, tol);
                SC_task = SC{curr_task};  % N x K 分配矩阵
                
                % --- C. 计算任务完成度 varsigma_m = D_m（投入资源 vs 需求）---
                total_resources = sum(SC_task(participants, :), 1);
                D_m = WorldSim.calc_task_completion_degree(total_resources, demand, K);
                
                % 完成度为 0 表示无效任务，跳过
                if D_m <= tol
                    task_utilities(curr_task) = 0;
                    continue;
                end
                
                % --- D. 计算任务期望值 E[V_m]（信念加权）---
                values = tasks(curr_task).WORLD.value;
                tlen = min([task_types, numel(values), size(belief, 2)]);
                V_m = sum(values(1:tlen) .* belief(1:tlen));
                
                % --- E. 根据智能体对当前任务资源投入占总投入的比例分摊全局成本 ---
                coalition_cost = 0;
                for j = 1:length(participants)
                    i_id = participants(j);

                    resource_to_this_task = sum(SC_task(i_id, :));
                    if agent_total_resources(i_id) > tol
                        cost_slice_ratio = resource_to_this_task / agent_total_resources(i_id);
                    else
                        cost_slice_ratio = 0;
                    end

                    coalition_cost = coalition_cost + agent_costs(i_id) * cost_slice_ratio;
                end
                
                % --- F. 计算任务净效用 ---
                U_m = V_m * D_m - coalition_cost;

                % --- G. 智能体 n 的分摊效用：u_{n,m} = r_{n,m} * U_m ---
                r_nm = OCFUtils.calc_resource_contribution_ratio(SC_task, agent_id, participants);
                u_nm = r_nm * U_m;
                
                task_utilities(curr_task) = u_nm;
                agentutility = agentutility + u_nm;
            end
        end
        %
        
        function [global_net_utility, total_global_cost, total_completed_value, task_completion_degrees] = ...
                evaluate_coalition_metrics(SC_global, agents, tasks, Value_Params, eps_val)
            % EVALUATE_COALITION_METRICS 评估全局联盟结构的净效用 (上帝视角)
            %
            % 输入:
            %   SC_global    - 全局联盟结构 SC
            %   agents       - 智能体结构体数组
            %   tasks        - 任务结构体数组
            %   Value_Params - 全局参数
            %   eps_val      - (可选) 容差
            
            %% 1. 参数初始化
            if nargin < 5 || isempty(eps_val)
                eps_val = 1e-6;
            end
            
            M = Value_Params.M;
            N = Value_Params.N;
            K = Value_Params.K;
            
            task_completion_degrees = zeros(M, 1);
            total_completed_value = 0;
            total_global_cost = zeros(1, N);
            
            %% 2. 第一阶段：计算所有任务的总收益 (Revenue)
            for j = 1:M
                participants = OCFUtils.get_participants(SC_global, j, eps_val);
                
                if isempty(participants)
                    task_completion_degrees(j) = 0;
                    continue;
                end
                
                SC_task = SC_global{j};
                demand = tasks(j).resource_demand(:)'; % 上帝视角：真实需求
                
                total_resources = sum(SC_task(participants, :), 1);
                
                D_C = WorldSim.calc_task_completion_degree(total_resources, demand, K);
                task_completion_degrees(j) = D_C;
                
                if D_C > 0
                    V_C = tasks(j).value; % 上帝视角：真实价值
                    total_completed_value = total_completed_value + (V_C * D_C);
                end
            end
            
            %% 3. 第二阶段：计算所有智能体的总成本 (Cost)
            all_agents_results = WorldSim.calc_all_agents_with_global_sync(agents, tasks, Value_Params, SC_global, eps_val);
            for i = 1:N
                alpha_fly = agents(i).fuel;
                alpha_wait = agents(i).wait_fuel;
                beta = agents(i).beta;

                cost_i = all_agents_results(i).t_fly_total * alpha_fly ...
                    + all_agents_results(i).t_wait_total * alpha_wait ...
                    + all_agents_results(i).t_exec_total * beta;
                total_global_cost(i) = cost_i;
            end
            
            %% 4. 第三阶段：计算全局净效用
            total_global_cost_sum = sum(total_global_cost);
            global_net_utility = total_completed_value - total_global_cost_sum;
            
            % 返回 total_global_cost 的总和，如果需要数组形式请修改函数签名。
            total_global_cost = total_global_cost_sum;
        end
        
    end
end