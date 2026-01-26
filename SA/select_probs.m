function probs = Select_probs(Value_data, agents, tasks, Value_Params, resource_gap)
% SELECT_PROBS 计算当前智能体的任务选择概率矩阵 (启发式引导)
%
% 功能描述:
%   基于任务的优先级、当前的资源缺口、智能体自身的剩余资源量以及距离成本，
%   为每种资源类型计算选择各个任务的概率。
%   这个概率矩阵将用于后续 Join 操作中的轮盘赌采样 (Roulette Wheel Selection)，
%   引导算法优先探索那些"高价值、紧缺资源、且距离较近"的任务。
%
% 输入:
%   Value_data   - 当前智能体的状态结构体 (包含 agentID, resources 等)
%   agents       - 智能体列表 (用于获取位置)
%   tasks        - 任务列表 (用于获取位置、优先级)
%   Value_Params - 全局参数 (K, M 等)
%   resource_gap - (MxK 矩阵) 当前每个任务在每种资源上的剩余需求量
%
% 输出:
%   probs        - (KxM 矩阵) 概率分布矩阵。
%                  probs(r, j) 表示针对资源 r，智能体选择加入任务 j 的概率。
%                  每一行的概率之和为 1。

    agentID = Value_data.agentID;
    
    % 初始化概率矩阵 (K种资源 x M个任务)
    probs = zeros(Value_Params.K, Value_Params.M);
    
    %% ==================== 1. 准备归一化因子 (Normalizers) ====================
    % 为了将不同量纲的物理量(优先级、需求量、距离)融合在一个公式里，
    % 我们需要计算它们的最大值，将所有数值映射到 [0, 1] 区间。
    
    % 1. 最大优先级
    max_priority = max([tasks.priority]);
    if max_priority <= 0
        max_priority = 1; % 防止除以零
    end
    
    % 2. 最大剩余需求 (全局)
    max_remaining_demand = max(resource_gap(:));
    if max_remaining_demand <= 0
        max_remaining_demand = 1;
    end
    
    % 3. 智能体的最大资源持有量
    max_agent_resource = max(Value_data.resources);
    if max_agent_resource <= 0
        max_agent_resource = 1;
    end
    
    % 4. 最大距离 (当前智能体到所有任务的最远距离)
    % arrayfun 用于遍历所有任务计算距离
    dists = arrayfun(@(task) sqrt((task.x - agents(agentID).x)^2 + (task.y - agents(agentID).y)^2), tasks);
    max_distance = max(dists);
    if max_distance <= 0
        max_distance = 1;
    end
    
    %% ==================== 2. 计算综合得分 (Heuristic Calculation) ====================
    % 遍历每种资源类型 r
    for r = 1:Value_Params.K
        
        % 遍历每个任务 j
        for j = 1:Value_Params.M
            
            % --- A. 因素 1: 任务的资源紧缺程度 (Remaining Demand) ---
            % 如果 resource_gap 为空或小于0，说明不缺资源，得分为0
            remaining_demand = 0;
            if ~isempty(resource_gap)
                remaining_demand = max(resource_gap(j, r), 0);
            end
            % 归一化: 缺口越大，得分越高 (倾向于去"雪中送炭")
            remaining_demand_norm = remaining_demand / max_remaining_demand;
            
            % --- B. 因素 2: 智能体的供给能力 (Agent Capacity) ---
            % 获取智能体拥有的第 r 类资源总量
            agent_resource_available = Value_data.resources(r);
            % 归一化: 自己拥有的资源越多，越倾向于去贡献该资源
            agent_resource_available_norm = agent_resource_available / max_agent_resource;
            
            % --- C. 因素 3: 距离成本 (Distance Cost) ---
            % 计算欧几里得距离
            task_distance = sqrt((tasks(j).x - agents(agentID).x)^2 + ...
                                 (tasks(j).y - agents(agentID).y)^2);
            if task_distance <= 0
                task_distance = eps; % 防止距离为0导致后续除法异常
            end
            % 归一化距离
            task_distance_norm = max(task_distance / max_distance, eps);
            
            % --- D. 因素 4: 任务优先级 (Priority) ---
            % 归一化优先级
            priority_norm = tasks(j).priority / max_priority;
            
            % --- E. 综合概率公式 (Synthesis) ---
            % 核心逻辑:
            % P ~ (优先级^2) * (需求) * (供给) / (距离)
            %
            % 解释:
            % 1. priority_norm^2: 对优先级进行平方放大，显著增加高优先级任务的权重。
            % 2. remaining_demand_norm: 任务越缺资源，越要去。
            % 3. / task_distance_norm: 距离越近(分母越小)，概率越大。
            
            task_probability = (priority_norm)^2 * remaining_demand_norm * agent_resource_available_norm / task_distance_norm;
            
            probs(r, j) = task_probability;
        end
        
        %% ==================== 3. 行归一化 (Row Normalization) ====================
        % 将这一行 (针对资源 r 的所有任务得分) 转换为真正的概率分布，使其和为 1。
        % 这样后续才可以使用 rand() 进行轮盘赌采样。
        
        total_prob = sum(probs(r, :));
        
        if total_prob > 0
            probs(r, :) = probs(r, :) / total_prob;
        else
            % 如果总概率为 0 (例如该资源所有任务都不缺，或者智能体没有该资源)，
            % 则该行保持全 0，意味着在 join_operation 中不会采样到任何任务。
            probs(r, :) = 0; 
        end
    end
end