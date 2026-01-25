function agentutility = calc_agent_total_utility(SC, agents, tasks, Value_Params, Value_data)
% COMPUTE_VALITY 计算智能体在当前联盟结构 SC 下的总净效用
%
% 核心逻辑：Total Utility = (Sum of Revenues) - (Total Path Cost)
% 改进点：避免了旧代码中"每计算一个任务的收益就减去一次全程成本"的逻辑错误，
%        现在采用了“收益分任务累加，成本按路径整体扣除”的正确模式。

    %% 0. 初始化与数据准备
    tol = 1e-9; % 定义数值计算的容差，防止浮点数误差
    
    % --- 获取当前智能体 ID ---
    % 兼容不同的数据结构命名（agentID 或 agentIndex）
    if isfield(Value_data, 'agentID')
        agent_id = Value_data.agentID;
    elseif isfield(Value_data, 'agentIndex')
        agent_id = Value_data.agentIndex;
    else
        error('无法在 Value_data 中找到 agent_id');
    end
    
    % --- 提取全局参数与个体属性 ---
    K = Value_Params.K;             % 资源维度数
    M = Value_Params.M;             % 任务总数
    alpha_fly = agents(agent_id).fuel;      % 单位飞行能耗系数
    alpha_wait = agents(agent_id).wait_fuel;% 单位等待能耗系数
    beta = agents(agent_id).beta;           % 单位执行能耗系数

    % --- 获取参与任务列表 ---
    % [引用更新] 使用 OCFUtils 快速查找该智能体投入资源大于 tol 的任务索引
    task_list = OCFUtils.get_agent_tasks_fast(SC, agent_id, tol);
    
    % --- 过滤无效任务 ---
    % 排除索引超过 M 的任务（通常 M+1 代表 Void/虚拟任务，不产生收益）
    task_list = task_list(task_list <= M);

    % --- 快速剪枝 ---
    % 如果智能体当前没有参与任何任务，则没有收益和成本，效用直接为 0
    if isempty(task_list)
        agentutility = 0;
        return;
    end

    %% 1. 第一阶段：累加总收益 (Total Revenue)
    % 逻辑：遍历智能体参与的每一个任务，计算其分红，并累加到总收益中。
    total_revenue = 0;
    
    % 获取置信度参数 (用于需求估算中的风险控制)
    if isfield(Value_Params, 'resource_confidence')
        confidence = Value_Params.resource_confidence;
    else
        confidence = 0.9; % 默认 90% 置信度
    end
    
    % --- 循环计算单任务收益 ---
    for i = 1:length(task_list)
        curr_task = task_list(i);
        
        % A. 准备信念与需求 (Belief & Demand)
        % 提取智能体对该任务类型的信念（概率分布）
        belief = Value_data.initbelief(curr_task, :);
        task_type_demands = Value_Params.task_type_demands;
        
        % [引用更新] 计算基于信念的估算需求
        % 使用分位数法 (Quantile) 确保在 confidence 置信度下资源足够
        demand = WorldSim.calculate_demand_quantile(belief, task_type_demands, confidence);
        
        % B. 解析联盟状态 (Coalition State)
        % [引用更新] 获取该任务当前的所有参与者 ID
        participants = OCFUtils.get_participants(SC, curr_task, tol);
        SC_task = SC{curr_task}; % 获取该任务的资源分配矩阵
        
        % C. 计算完成度 (Completion Degree, D_C)
        % 汇总所有参与者的资源投入
        total_resources = sum(SC_task(participants, :), 1);
        % [引用更新] 计算资源满足需求的程度 (0.0 ~ 1.0)
        D_C = WorldSim.calc_task_completion_degree(total_resources, demand, K);
        
        % 如果任务完成度极低（未开始或无贡献），跳过该任务的收益计算
        if D_C <= tol
            continue; 
        end
        
        % D. 计算资源贡献比例 (Contribution Ratio, r_n)
        % 计算当前智能体投入占联盟总投入的比例，决定分红权重
        % [引用更新] OCFUtils -> WorldSim (注：此处保留了您原始代码中的 OCFUtils 引用)
        r_n_C = OCFUtils.calc_resource_contribution_ratio(SC_task, agent_id, participants);
        
        % E. 计算期望价值 (Expected Value, V_C)
        % 公式：V_C = Σ (类型真实价值 * 类型信念概率)
        task_types = Value_Params.task_type;
        values = tasks(curr_task).WORLD.value;
        
        % 维度对齐处理：取类型数、价值表长度、信念长度的最小值，防止索引越界
        tlen = min([task_types, numel(values), size(belief, 2)]);
        V_C = sum(values(1:tlen) .* belief(1:tlen));
        
        % F. 累加收益
        % 单任务收益 = 贡献比 * 期望价值 * 完成度
        total_revenue = total_revenue + (r_n_C * V_C * D_C);
    end

    %% 2. 第二阶段：计算总成本 (Total Cost)
    % 逻辑：跳出任务循环，将 task_list 视为一条完整的行动路径，一次性计算总耗时。
    
    % A. 构建物理引擎所需的参数
    % 从 SC 中提取个体的资源分配矩阵 R_agent
    % [引用更新] WorldSim
    % (注：此处代码逻辑是准备参数，但在下一行调用前未显式赋值 R_agent，
    %  这可能依赖于外部变量或此处留白，但在计算成本时是必要的)
    
    % B. 任务排序 (Task Scheduling)
    % 物理移动必须遵循特定顺序（如按优先级执行），而非随意的索引顺序
    % [引用更新] OCFUtils (基础工具)
    orderedTasks = OCFUtils.sort_tasks_by_priority(task_list, tasks);
    
    % C. 调用物理引擎核心 (Physics Engine)
    % 计算考虑了全局同步 (Global Sync) 后的精确时间：
    % - t_fly: 总飞行时间
    % - t_wait: 总等待时间（含等到齐 + 等完工）
    % - t_exec: 总执行时间
    [t_fly, t_wait, t_exec] = WorldSim.calc_with_global_sync( ...
        agent_id, orderedTasks, agents, tasks, Value_Params, SC, tol);
    
    % D. 聚合总成本
    % 总成本 = 飞行油耗 + 等待油耗 + 执行能耗
    total_cost = t_fly * alpha_fly + t_wait * alpha_wait + t_exec * beta;

    %% 3. 第三阶段：计算净效用 (Net Utility)
    % Utility = Revenue - Cost
    
    if total_revenue > total_cost
        % 如果收益大于成本，返回净利润
        agentutility = total_revenue - total_cost;
    else
        % 理性约束：如果亏本（成本 > 收益），效用截断为 0
        % (表示智能体不会选择做亏本买卖，或者净效用不能为负)
        agentutility = 0;
    end
    
end