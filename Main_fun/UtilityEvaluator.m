classdef UtilityEvaluator
    % UtilityEvaluator 效用与性能评估工具类
    % 包含个体效用计算 (Agent View) 和全局性能指标评估 (Global View)。
    
    methods(Static)
        
        function agentutility = calc_agent_total_utility(SC, agents, tasks, Value_Params, Value_data, AddPara)
            % CALC_AGENT_TOTAL_UTILITY 计算智能体在当前联盟结构 SC 下的总净效用 (个体视角)
            %
            % 核心逻辑：Total Utility = (Sum of Revenues) - (Total Path Cost)
            %
            % 输入：
            %   SC           - 全局联盟结构 (Cell Array)
            %   agents       - 智能体结构体数组
            %   tasks        - 任务结构体数组
            %   Value_Params - 全局参数
            %   Value_data   - 包含 agentID/agentIndex 和 initbelief
            %   AddPara      - (可选) 包含 resource_confidence 等参数
            
            %% 0. 初始化与数据准备
            tol = 1e-9;
            
            % 获取当前智能体 ID
            if isfield(Value_data, 'agentID')
                agent_id = Value_data.agentID;
            elseif isfield(Value_data, 'agentIndex')
                agent_id = Value_data.agentIndex;
            else
                error('无法在 Value_data 中找到 agent_id');
            end
            
            K = Value_Params.K;
            M = Value_Params.M;
            alpha_fly = agents(agent_id).fuel;
            alpha_wait = agents(agent_id).wait_fuel;
            beta = agents(agent_id).beta;
            
            % 获取参与任务列表
            task_list = OCFUtils.get_agent_tasks_fast(SC, agent_id, tol);
            task_list = task_list(task_list <= M); % 过滤无效任务
            
            if isempty(task_list)
                agentutility = 0;
                return;
            end
            
            %% 1. 第一阶段：累加总收益 (Total Revenue)
            total_revenue = 0;
            
            % 获取置信度参数
            confidence = 0.9; % 默认值
            if nargin >= 6 && isfield(AddPara, 'resource_confidence')
                confidence = AddPara.resource_confidence;
            end
            
            task_type_demands = Value_Params.task_type_demands;
            task_types = Value_Params.task_type;
            
            for i = 1:length(task_list)
                curr_task = task_list(i);
                
                % A. 准备信念与需求
                belief = Value_data.initbelief(curr_task, :);
                
                % 使用分位数法估算需求
                demand = WorldSim.calculate_demand_quantile(belief, task_type_demands, confidence);
                
                % B. 解析联盟状态
                participants = OCFUtils.get_participants(SC, curr_task, tol);
                SC_task = SC{curr_task};
                
                % C. 计算完成度
                total_resources = sum(SC_task(participants, :), 1);
                D_C = WorldSim.calc_task_completion_degree(total_resources, demand, K);
                
                if D_C <= tol
                    continue;
                end
                
                % D. 计算资源贡献比例
                r_n_C = OCFUtils.calc_resource_contribution_ratio(SC_task, agent_id, participants);
                
                % E. 计算期望价值
                values = tasks(curr_task).WORLD.value;
                tlen = min([task_types, numel(values), size(belief, 2)]);
                V_C = sum(values(1:tlen) .* belief(1:tlen));
                
                % F. 累加收益
                total_revenue = total_revenue + (r_n_C * V_C * D_C);
            end
            
            %% 2. 第二阶段：计算总成本 (Total Cost)
            % 任务排序
            orderedTasks = OCFUtils.sort_tasks_by_priority(task_list, tasks);
            
            % 调用物理引擎计算时间
            [t_fly, t_wait, t_exec] = WorldSim.calc_with_global_sync( ...
                agent_id, orderedTasks, agents, tasks, Value_Params, SC, tol);
            
            % 聚合总成本
            total_cost = t_fly * alpha_fly + t_wait * alpha_wait + t_exec * beta;
            
            %% 3. 第三阶段：计算净效用
            if total_revenue > total_cost
                agentutility = total_revenue - total_cost;
            else
                agentutility = 0;
            end
        end
        
        
        function [global_net_utility, total_global_cost, total_completed_value, task_completion_degrees] = ...
                evaluate_coalition_metrics(SC_global, agents, tasks, Value_Params, eps_val)
            % EVALUATE_COALITION_METRICS 计算全局联盟结构的净效用 (上帝视角)
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
            
            %% 2. 第一阶段：计算所有任务的收益 (Revenue)
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
            
            %% 3. 第二阶段：计算所有智能体的成本 (Cost)
            for i = 1:N
                my_raw_tasks = OCFUtils.get_agent_tasks_fast(SC_global, i);
                
                if isempty(my_raw_tasks)
                    total_global_cost(i) = 0;
                    continue;
                end
                
                my_tasks = OCFUtils.sort_tasks_by_priority(my_raw_tasks, tasks);
                
                alpha_fly = agents(i).fuel;
                alpha_wait = agents(i).wait_fuel;
                beta = agents(i).beta;
                
                [t_fly_total, t_wait_total, t_exec_total] = WorldSim.calc_with_global_sync( ...
                    i, my_tasks, agents, tasks, Value_Params, SC_global, eps_val);
                
                cost_i = t_fly_total * alpha_fly + t_wait_total * alpha_wait + t_exec_total * beta;
                total_global_cost(i) = cost_i;
            end
            
            %% 4. 第三阶段：计算全局净效用
            total_global_cost_sum = sum(total_global_cost);
            global_net_utility = total_completed_value - total_global_cost_sum;
            
            % 返回的 total_global_cost 是总和，如果需要向量形式，请修改函数签名
            total_global_cost = total_global_cost_sum; 
        end
        
    end
end