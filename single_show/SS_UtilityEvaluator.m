classdef SS_UtilityEvaluator
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
        %     task_list = SS_OCFUtils.get_agent_tasks_fast(SC, agent_id, tol);
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
        %         demand = SS_WorldSim.calculate_demand_quantile(belief, task_type_demands, confidence);
        %
        %         % B. 获取参与者状态
        %         participants = SS_OCFUtils.get_participants(SC, curr_task, tol);
        %         SC_task = SC{curr_task};
        %
        %         % C. 计算任务完成度
        %         total_resources = sum(SC_task(participants, :), 1);
        %         D_C = SS_WorldSim.calc_task_completion_degree(total_resources, demand, K);
        %
        %         if D_C <= tol
        %             continue;
        %         end
        %
        %         % D. 计算资源贡献比例
        %         r_n_C = SS_OCFUtils.calc_resource_contribution_ratio(SC_task, agent_id, participants);
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
        %     orderedTasks = SS_OCFUtils.sort_tasks_by_priority(task_list, tasks);
        %
        %     % 全局同步推演时间
        %     [t_fly, t_wait, t_exec] = SS_WorldSim.calc_with_global_sync( ...
        %         agent_id, orderedTasks, agents, tasks, Value_Params, SC, tol);
        %
        %     % 综合总成本
        %     total_cost = t_fly * alpha_fly + t_wait * alpha_wait + t_exec * beta;
        %
        %     %% 3. 第三阶段：计算净效用
        %     agentutility = total_revenue - total_cost;
        % end
        
        
        
        function [agentutility, task_utilities] = calc_agent_total_utility(SC, agents, tasks, Value_Params, Value_data, AddPara)
            % CALC_AGENT_TOTAL_UTILITY 计算智能体 n 在当前联盟结构 SC 下的总净效用
            %
            % 按照式(1)-(6)的建模:
            %   u_n^m(A_m) = [||A_m^(n)||_1 / sum||A_m^(i)||_1] * (V_km * varsigma_m) - E_{n,m}^Cost
            %   E_{n,m}^Cost = E_{n,m}^move + E_{n,m}^wait + E_{n,m}^exec
            %   E_{n,m}^move = varpi * Dist(m', m)
            %   E_{n,m}^wait = gamma * (T_{n,m}^wait_pre + T_{n,m}^wait_post)
            %
            % 输入:
            %   SC           - 全局联盟结构 (M x 1 Cell, 每个为 N x K 资源分配矩阵)
            %   agents       - 智能体结构体数组
            %   tasks        - 任务结构体数组
            %   Value_Params - 全局参数 (N, M, K, task_type, task_type_demands)
            %   Value_data   - 当前智能体数据 (agentID/agentIndex, initbelief)
            %   AddPara      - (可选) 附加参数，包含 resource_confidence
            %
            % 输出:
            %   agentutility   - 智能体 n 的总净效用标量
            %   task_utilities - containers.Map，键为任务号，值为 u_n^m

            tol = 1e-9;

            % 获取当前智能体 ID 及环境维度
            if isfield(Value_data, 'agentID')
                agent_id = Value_data.agentID;
            else
                agent_id = Value_data.agentIndex;
            end
            K = Value_Params.K;   % 资源种类数
            M = Value_Params.M;   % 任务数
            N = Value_Params.N;   % 智能体数

            % 获取智能体 n 参与的任务列表
            task_list = SS_OCFUtils.get_agent_tasks_fast(SC, agent_id, tol);
            task_list = task_list(task_list <= M);
            task_utilities = containers.Map('KeyType', 'double', 'ValueType', 'double');

            if isempty(task_list)
                agentutility = 0;
                return;
            end

            % 获取资源置信度和任务类型需求
            confidence = Value_Params.resource_confidence;
            [demand_mode, demand_rounding_mode] = SS_WorldSim.get_demand_estimation_settings(AddPara, Value_Params);
            task_type_demands = Value_Params.task_type_demands;
            task_types = Value_Params.task_type;

            % 获取智能体能耗系数
            varpi = agents(agent_id).fuel;      % 移动能耗系数 ϖ
            gamma = agents(agent_id).wait_fuel; % 等待能耗系数 γ
            beta = agents(agent_id).beta;       % 执行能耗系数 β
            vel = agents(agent_id).vel;         % 智能体速度

            % 对任务按优先级排序（确定执行顺序 m' -> m）
            ordered_tasks = SS_OCFUtils.sort_tasks_by_priority(task_list, tasks);

            % 计算全局同步信息（获取所有任务的同步时间和执行时长）
            % 【优化】persistent 缓存：SC 未变时直接复用，避免同一迭代内重复调用
            persistent cached_SC_util cached_results_util;
            if isempty(cached_SC_util) || ~isequal(SC, cached_SC_util)
                cached_results_util = SS_WorldSim.calc_all_agents_with_global_sync(agents, tasks, Value_Params, SC, tol);
                cached_SC_util = SC;
            end
            all_agents_results = cached_results_util;
            agent_result = all_agents_results(agent_id);

            % 初始化当前位置为智能体起始位置
            curr_pos = [agents(agent_id).x, agents(agent_id).y];
            curr_time = 0;  % 当前时刻

            % 累计总效用
            agentutility = 0;

            %% 对每个任务计算效用 u_n^m
            for idx = 1:length(ordered_tasks)
                task_id = ordered_tasks(idx);
                task_pos = [tasks(task_id).x, tasks(task_id).y];

                % ========== 收益计算 ==========
                % A. 计算任务需求
                belief = Value_data.initbelief(task_id, :);
                demand = SS_WorldSim.estimate_demand_from_belief( ...
                    belief, ...
                    task_type_demands, ...
                    demand_mode, ...
                    confidence, ...
                    demand_rounding_mode);

                % B. 获取联盟成员及资源分配
                participants = SS_OCFUtils.get_participants(SC, task_id, tol);
                SC_task = SC{task_id};

                % C. 计算任务完成度 varsigma_m
                total_resources = sum(SC_task(participants, :), 1);
                varsigma_m = SS_WorldSim.calc_task_completion_degree(total_resources, demand, K);

                if varsigma_m <= tol
                    task_utilities(task_id) = 0;
                    continue;
                end

                % D. 计算任务期望价值 V_km（基于信念的期望值）
                values = tasks(task_id).WORLD.value;
                tlen = min([task_types, numel(values), size(belief, 2)]);
                V_km = sum(values(1:tlen) .* belief(1:tlen));

                % E. 计算资源贡献比例 ||A_m^(n)||_1 / sum_i ||A_m^(i)||_1
                r_nm = SS_OCFUtils.calc_resource_contribution_ratio(SC_task, agent_id, participants);

                % F. 收益 = 资源贡献比例 × 任务价值 × 完成度
                revenue_nm = r_nm * V_km * varsigma_m;

                % ========== 成本计算 ==========
                % G. 移动成本 E_{n,m}^move = varpi * Dist(m', m)
                dist_to_task = norm(task_pos - curr_pos);
                E_move = varpi * dist_to_task;

                % H. 获取时间信息
                % 从 agent_result 中找到该任务在序列中的索引
                task_idx_in_seq = find(agent_result.task_sequence == task_id, 1);

                % 智能体到达任务 m 的时刻
                fly_time = dist_to_task / max(vel, tol);
                AT_nm = curr_time + fly_time;

                % 任务 m 的同步开始时刻 ST_m
                ST_m = agent_result.start_times(task_idx_in_seq);

                % 智能体 n 在任务 m 的执行时长 Dur_{n,m}
                Dur_nm = agent_result.execution_times(task_idx_in_seq);

                % 联盟整体执行时长 Dur_m（需要计算联盟中最慢的成员）
                Dur_m = SS_WorldSim.calc_coalition_exec_time(SC, task_id, tasks(task_id), Value_Params, tol);

                % I. 同步前等待时间 T_{n,m}^wait_pre = ST_m - AT_{n,m}
                T_wait_pre = max(0, ST_m - AT_nm);

                % J. 同步后等待时间 T_{n,m}^wait_post = Dur_m - Dur_{n,m}
                T_wait_post = max(0, Dur_m - Dur_nm);

                % K. 等待成本 E_{n,m}^wait = gamma * (T_wait_pre + T_wait_post)
                E_wait = gamma * (T_wait_pre + T_wait_post);

                % L. 执行成本 E_{n,m}^exec = beta * Dur_{n,m}
                E_exec = beta * Dur_nm;

                % M. 任务 m 的总成本
                E_nm_cost = E_move + E_wait + E_exec;

                % ========== 计算任务效用 ==========
                % N. u_n^m = 收益 - 成本
                u_nm = revenue_nm - E_nm_cost;

                task_utilities(task_id) = u_nm;
                agentutility = agentutility + u_nm;

                % 更新当前位置和时间（任务完成后）
                curr_pos = task_pos;
                curr_time = ST_m + Dur_m;  % 联盟任务完成时刻
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
                participants = SS_OCFUtils.get_participants(SC_global, j, eps_val);
                
                if isempty(participants)
                    task_completion_degrees(j) = 0;
                    continue;
                end
                
                SC_task = SC_global{j};
                demand = tasks(j).resource_demand(:)'; % 上帝视角：真实需求
                
                total_resources = sum(SC_task(participants, :), 1);
                
                D_C = SS_WorldSim.calc_task_completion_degree(total_resources, demand, K);
                task_completion_degrees(j) = D_C;
                
                if D_C > 0
                    V_C = tasks(j).value; % 上帝视角：真实价值
                    total_completed_value = total_completed_value + (V_C * D_C);
                end
            end
            
            %% 3. 第二阶段：计算所有智能体的总成本 (Cost)
            all_agents_results = SS_WorldSim.calc_all_agents_with_global_sync(agents, tasks, Value_Params, SC_global, eps_val);
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
