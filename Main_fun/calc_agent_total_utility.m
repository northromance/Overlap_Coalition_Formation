function agentutility = calc_agent_total_utility(SC, agents, tasks, Value_Params, Value_data)
% COMPUTE_VALITY 计算智能体在当前联盟结构 SC 下的总净效用
%
% 核心逻辑：Total Utility = (Sum of Revenues) - (Total Path Cost)
% 避免了旧代码中"每计算一个任务的收益就减去一次全程成本"的逻辑错误。

    %% 0. 初始化与数据准备
    tol = 1e-9;
    
    % 假设 Value_data 是当前智能体的结构体
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

    % [引用更新] 获取当前智能体参与的所有任务列表
    % 使用 WorldSim.get_agent_tasks_fast (或 OCFUtils.get_agent_participated_tasks)
    task_list = WorldSim.get_agent_tasks_fast(SC, agent_id);
    
    % 过滤掉 Void 任务 (如果有 > M 的索引)
    task_list = task_list(task_list <= M);

    % 如果没有参与任何任务，效用为 0
    if isempty(task_list)
        agentutility = 0;
        return;
    end

    %% 1. 第一阶段：累加总收益 (Total Revenue)
    total_revenue = 0;
    
    % 获取置信度参数
    if isfield(Value_Params, 'resource_confidence')
        confidence = Value_Params.resource_confidence;
    else
        confidence = 0.9;
    end
    
    % 遍历参与的每一个任务，累加其带来的价值
    for i = 1:length(task_list)
        curr_task = task_list(i);
        
        % A. 准备信念与需求
        belief = Value_data.initbelief(curr_task, :);
        task_type_demands = Value_Params.task_type_demands;
        
        % [引用更新] 计算基于信念的需求
        demand = WorldSim.calculate_demand_quantile(belief, task_type_demands, confidence);
        
        % B. 解析联盟状态
        % [引用更新] 获取该任务的所有参与者
        participants = OCFUtils.get_participants(SC, curr_task, tol);
        SC_task = SC{curr_task};
        
        % C. 计算完成度 (D_C)
        total_resources = sum(SC_task(participants, :), 1);
        % [引用更新] WorldSim
        D_C = WorldSim.calc_task_completion_degree(total_resources, demand, K);
        
        % 如果该任务未完成或无贡献，跳过收益计算
        if D_C <= tol
            continue; 
        end
        
        % D. 计算资源贡献比例 (r_n)
        % [引用更新] WorldSim
        r_n_C = OCFUtils.calc_resource_contribution_ratio(SC_task, agent_id, participants);
        
        % E. 计算期望价值 (V_C)
        task_types = Value_Params.task_type;
        values = tasks(curr_task).WORLD.value;
        
        % 维度对齐与期望计算
        tlen = min([task_types, numel(values), size(belief, 2)]);
        V_C = sum(values(1:tlen) .* belief(1:tlen));
        
        % F. 累加
        total_revenue = total_revenue + (r_n_C * V_C * D_C);
    end

    %% 2. 第二阶段：计算总成本 (Total Cost)
    % 将所有任务视为一个整体序列，计算一次性的总能耗
    
    % A. 构建物理引擎所需的参数
    % 从 SC 中提取个体的资源分配矩阵 R_agent
    % [引用更新] WorldSim
    
    % B. 任务排序 (物理移动必须遵循优先级或特定顺序)
    % [引用更新] OCFUtils (基础工具)
    orderedTasks = OCFUtils.sort_tasks_by_priority(task_list, tasks);
    
    % C. 调用物理引擎核心 (计算同步后的精确时间)
    % 这个函数会考虑其他队友的到达时间，计算出该智能体的真实等待和飞行时间
    [t_fly, t_wait, t_exec] = WorldSim.calc_with_global_sync( ...
        agent_id, orderedTasks, agents, tasks, Value_Params, SC, tol);
    
    
    total_cost = t_fly * alpha_fly + t_wait * alpha_wait + t_exec * beta;

    %% 3. 第三阶段：计算净效用
    % Utility = Revenue - Cost
    
    if total_revenue > total_cost
        agentutility = total_revenue - total_cost;
    else
        % 根据具体业务逻辑，效用可以为负（表示亏损），也可以截断为0
        agentutility = 0;
    end
    
end