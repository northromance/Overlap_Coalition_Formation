function agentutility = Value_utility(agents, tasks, numberrow, numbercolumn, ~, Value_data, Value_Params, SC, R_agent)
% VALUE_UTILITY 计算智能体在特定资源分配状态下的预期净效用
%
% 核心逻辑：Utility = max(0, Revenue - Cost)
% 输入：SC/R_agent 为提议状态（假设移动后）的结构

    %% 0. 初始化与快速剪枝
    tol = 1e-9;
    
    % 若为 Void 任务 (M+1)，无收益，直接返回
    if numberrow > Value_Params.M
        agentutility = 0;
        return;
    end
    
    agent_id = numbercolumn; % 列索引即为 Agent ID
    
    %% 1. 准备基础数据 (基于信念的需求估算)
    K = Value_Params.K;
    
    % 提取计算分位数需求所需的参数
    belief = Value_data.initbelief(numberrow, :); 
    task_type_demands = Value_Params.task_type_demands; 
    
    % 获取置信度，若参数未定义则默认为 0.9
    if isfield(Value_Params, 'resource_confidence')
        confidence = Value_Params.resource_confidence;
    else
        confidence = 0.9; 
    end
    
    % 计算基于信念的估计需求 (而非真实需求)
    demand = OCFUtils.calculate_demand_quantile(belief, task_type_demands, confidence);
    
    %% 2. 计算收益 (Revenue)
    % 公式：收益 = 完成度(D_C) * 期望价值(V_C) * 贡献比(r_n)
    
    % A. 解析参与者与资源
    % 优先从 SC (提议状态) 解析
    participants = OCFUtils.get_participants(SC, numberrow, tol);
    SC_task = SC{numberrow}; 
    
    % B. 计算任务完成度 (D_C)
    total_resources = sum(SC_task(participants, :), 1);
    D_C = OCFUtils.calc_task_completion_degree(total_resources, demand, K);
    
    if D_C <= tol
        agentutility = 0; % 无法满足任何需求，收益为0
        return;
    end
    
    % C. 计算资源贡献比例 (r_n)
    r_n_C = OCFUtils.calc_resource_contribution_ratio(SC_task, agent_id, participants);
    
    % D. 计算期望价值 (V_C)
    % 期望价值 = Σ (类型价值 * 类型信念概率)
    task_types = Value_Params.task_type;
    values = tasks(numberrow).WORLD.value;
    
    % 维度对齐处理
    tlen = min([task_types, numel(values), size(belief, 2)]);
    V_C = sum(values(1:tlen) .* belief(1:tlen));
    
    % E. 总收益
    revenue = r_n_C * V_C * D_C;
    
    %% 3. 计算成本 (Cost) - 全局同步机制
    % 公式：成本 = 飞行能耗 + 等待能耗 + 执行能耗
    
    % 提取能耗系数
    alpha_fly = agents(agent_id).fuel;
    alpha_wait = agents(agent_id).wait_fuel;
    beta = agents(agent_id).beta;
    
    % A. 构建任务序列 (基于 R_agent 提议状态)
    myOrderedTasks = find(any(R_agent > tol, 2))';
    
    % 确保当前考察的任务包含在序列中
    if isempty(myOrderedTasks), myOrderedTasks = numberrow;
    elseif ~ismember(numberrow, myOrderedTasks), myOrderedTasks = [numberrow, myOrderedTasks];
    end
    
    % 按优先级排序任务 (物理引擎需要有序输入)
    orderedTasks = OCFUtils.sort_tasks_by_priority(myOrderedTasks, tasks);
    
    % B. 调用物理引擎 (计算时间消耗)
    [t_fly, t_wait, t_exec] = calc_with_global_sync( ...
        agent_id, orderedTasks, agents, tasks, Value_Params, SC, R_agent, tol);
    
    % C. 聚合总成本
    cost = t_fly * alpha_fly + t_wait * alpha_wait + t_exec * beta;
    
    %% 4. 计算净效用
    % 理性约束：收益必须大于成本
    if revenue > cost
        agentutility = revenue - cost;
    else
        agentutility = 0;
    end
end