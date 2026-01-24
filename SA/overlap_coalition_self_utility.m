function individual_utility = overlap_coalition_self_utility(n, task_m, SC, agents, tasks, Value_Params, agent_belief)
% OVERLAP_COALITION_SELF_UTILITY 计算智能体 n 在特定任务 m 中的个体效用
%
% 效用公式:
%   Utility_n(C) = Revenue - Cost
%   Revenue (收益) = r_n(C) * V_C * D_C
%   Cost (成本)    = t_fly * alpha_fly + t_wait * alpha_wait + T_exec * beta
%
% 其中:
%   r_n(C): 智能体 n 在该任务中的资源贡献占比 (Contribution Ratio)
%   V_C:    任务的预期价值 (Expected Value)，基于智能体的信念
%   D_C:    任务的完成度 (Completion Degree)，基于投入资源与预期需求
%   Costs:  包括飞行耗油、等待耗油和执行任务耗油
%
% 输入:
%   n            - 智能体 ID
%   task_m       - 目标任务 ID
%   SC           - 全局联盟结构 (Schedule Cell Array)
%   agents       - 智能体属性结构体
%   tasks        - 任务属性结构体
%   Value_Params - 全局参数 (M, N, K 等)
%   agent_belief - 智能体 n 对各个任务类型的信念矩阵 (M x TaskTypes)
%
% 输出:
%   individual_utility - 计算出的净效用值

    %% 1. 基础校验
    % 检查任务索引是否越界
    if task_m < 1 || task_m > Value_Params.M
        individual_utility = 0;
        return;
    end
    
    % 检查该任务当前是否有成员参与 (SC{task_m} 中是否有非零行)
    % any(..., 2) 按行检查，find 获取非零行的索引(即成员ID)
    member_idx = find(any(SC{task_m} > 0, 2))';
    if isempty(member_idx)
        individual_utility = 0;
        return;
    end

    %% 2. 估算任务资源需求 (Expected Resource Demand)
    % 智能体不知道任务的真实需求，只能根据信念 (Belief) 进行估算
    
    if isfield(Value_Params, 'task_type_demands') && ~isempty(Value_Params.task_type_demands)
        % 获取智能体对该任务类型的概率分布信念
        b = agent_belief(task_m, :);
        num_types = size(Value_Params.task_type_demands, 1);
        use_b = b(1:num_types); % 截取有效部分
        
        % 策略分歧：风险规避 vs 数学期望
        if isfield(Value_Params, 'resource_confidence') && Value_Params.resource_confidence > 0
            % [策略A] 分位数法 (Quantile): 
            % 计算一个需求值，使得任务真实需求小于该值的概率达到 resource_confidence (例如 95%)
            % 这是一种风险规避策略，宁可多估算需求以免任务失败
            expected_demand = WorldSim.calculate_demand_quantile(use_b, Value_Params.task_type_demands, Value_Params.resource_confidence);
        else
            % [策略B] 期望值法 (Expectation):
            % 简单的加权平均：Prob * Demand
            expected_demand = use_b * Value_Params.task_type_demands;
        end
    else
        % [兜底] 如果没有定义类型需求，使用任务结构体中的默认需求（通常是上帝视角值，仿真中应尽量避免直接使用）
        expected_demand = tasks(task_m).resource_demand;
    end

    %% 3. 计算任务完成度 (Completion Degree, D_C)
    % 衡量当前投入的资源满足预期需求的程度 (0.0 ~ 1.0)
    D_C = WorldSim.calc_task_completion_degree(SC{task_m}, expected_demand, Value_Params.K);
    
    % 如果完成度为 0，说明没有任何有效产出，效用直接归零
    if D_C == 0
        individual_utility = 0;
        return;
    end

    %% 4. 计算贡献占比 (Contribution Ratio, r_n)
    % 智能体 n 投入的资源占联盟总投入资源的比例，决定了分蛋糕能分多少
    % 这里调用了 OCFUtils (或应为 WorldSim/CoalitionOps) 中的方法
    r_n_C = OCFUtils.calc_resource_contribution_ratio(SC{task_m}, n, member_idx);

    %% 5. 计算任务预期价值 (Expected Value, V_C)
    % 同样基于信念计算。任务真实价值未知，只能加权估算。
    b = agent_belief(task_m, :);
    % 获取所有可能的任务类型对应的真实价值表 (WORLD.value)
    % 注意：tasks(task_m).WORLD.value 通常是一个包含所有类型价值的数组
    v = tasks(task_m).WORLD.value; 
    
    % 加权求和: Sum(Value_Type_i * Prob_Type_i)
    V_C = sum(v .* b(1:length(v)));

    %% 6. 计算成本 (Energy Costs)
    % 计算智能体执行该任务所需的时间成本（飞行、等待、执行）
    % 这是一个复杂过程，因为需要考虑任务执行的先后顺序（路径规划）
    [t_fly, t_wait, T_exec] = calc_energy_cost(n, task_m, SC, agents, tasks, Value_Params);

    %% 7. 最终效用汇总
    % 收益部分 = 贡献率 * 预期总价值 * 完成度
    revenue = r_n_C * V_C * D_C;
    
    % 成本部分 = 飞行耗油 + 等待耗油 + 执行耗油
    alpha_fly = agents(n).fuel;      % 单位飞行油耗
    alpha_wait = agents(n).wait_fuel;% 单位等待油耗
    cost = t_fly * alpha_fly + t_wait * alpha_wait + T_exec * agents(n).beta;
    
    % 净效用
    individual_utility = revenue - cost;
end

%% ==================== 辅助函数 (Helper Functions) ====================

function [t_fly, t_wait, T_exec] = calc_energy_cost(n, task_m, SC, agents, tasks, Value_Params)
    % CALC_ENERGY_COST 计算智能体 n 执行任务 m 及其之前所有任务的累积时间成本
    % 注意：这里的成本不仅仅是 task_m 的，通常包含到达 task_m 路径上的累积成本，
    % 或者根据 energy_cost 的具体实现，可能是特定于该任务的边际成本。
    
    % 1. 找出智能体 n 参与的所有任务
    agent_tasks = find(cellfun(@(x) any(x(n, :) > 0), SC))';
    
    % 如果智能体根本没参与 task_m，成本为 0 (逻辑上也不应该进入此分支)
    if isempty(agent_tasks) || ~ismember(task_m, agent_tasks)
        t_fly = 0; t_wait = 0; T_exec = 0;
        return;
    end
    
    % 2. 构造个体的资源分配矩阵 R_agent (从全局 SC 提取)
    R_agent = zeros(Value_Params.M, Value_Params.K);
    for m = 1:Value_Params.M
        R_agent(m, :) = SC{m}(n, :);
    end
    
    % 3. 调用外部函数 energy_cost 进行路径规划和时间计算
    % energy_cost 通常会负责对 agent_tasks 进行排序 (如 TSP 或 优先级排序)
    % 并返回总的飞行和等待时间。
    [t_fly, ~, ~, ~, orderedTasks, ~, t_wait] = energy_cost(n, agent_tasks, agents, tasks, Value_Params, R_agent, SC);
    
    % 4. 计算执行时间 (Execution Time)
    % 注意：这里的逻辑似乎是计算“直到 task_m 为止”的累积执行时间
    % 或者是 task_m 本身的执行时间，取决于 orderedTasks 的截断逻辑
    task_pos = find(orderedTasks == task_m, 1);
    
    % 计算从第一个任务到目标任务 task_m 的累积执行时长
    % 这意味着成本函数考虑了前序任务带来的疲劳或时间流逝
    T_exec = calc_exec_time_to_task(orderedTasks(1:task_pos), R_agent, tasks, Value_Params);
end

function T = calc_exec_time_to_task(task_list, R_agent, tasks, Value_Params)
    % CALC_EXEC_TIME_TO_TASK 计算任务列表中所有任务的执行时间总和
    T = 0;
    tol = 1e-9;
    for ii = 1:numel(task_list)
        m = task_list(ii);
        used = R_agent(m, :) > tol; % 找出投入了哪些资源
        
        if isfield(tasks, 'duration_by_resource')
            % 细粒度模型：不同资源的执行耗时不同
            dur = tasks(m).duration_by_resource(:)';
            dur = dur(1:min(numel(dur), Value_Params.K));
            used = used(1:numel(dur));
            % 注意：此处使用 sum 表示资源间是"串行"处理或成本累加
            % 如果是并行处理，通常应使用 max
            T = T + sum(dur(used)); 
        elseif isfield(tasks, 'duration')
            % 粗粒度模型：任务有固定时长
            T = T + tasks(m).duration;
        else
            T = T + 1.0; % 默认值
        end
    end
end