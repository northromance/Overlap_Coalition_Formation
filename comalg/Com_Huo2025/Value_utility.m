function agentutility = Value_utility(agents, tasks, numberrow, numbercolumn, numberofcoworker, Value_data, Value_Params)
% VALUE_UTILITY 计算智能体加入某任务后的预期效用值
%
% 核心公式：
%   Utility = Revenue - Cost
%   Revenue = (资源贡献比 r_n) × (期望任务价值 V_C) × (任务完成度 D_C)
%   Cost    = (飞行能耗) + (同步等待能耗) + (执行能耗)
%
% 输入参数：
%   agents          : 智能体结构体数组（包含位置、速度、资源容量、能耗系数等）
%   tasks           : 任务结构体数组（包含位置、需求、价值分布等）
%   numberrow       : 当前考察的任务索引（行号）。注意：若是 M+1 则为 Void 任务
%   numbercolumn    : 当前智能体在联盟矩阵中的列索引（注意：这不是 agentID，需要转换）
%   numberofcoworker: 当前任务行中，所有非零列的索引列表（即联盟成员的列索引）
%   Value_data      : 全局状态数据，包含 coalitionstru（成员矩阵）和 initbelief（信念）
%   Value_Params    : 全局参数（K, M, task_type 等）
%
% 输出：
%   agentutility    : 计算出的净效用值。如果 < 0 则返回 0。

    %% 1. 特殊情况处理：Void 任务
    % 如果当前任务行号是 M+1，说明是“空闲/虚任务”。
    % 按照设定，待在虚任务中没有效用（或者效用为0）。
    if (numberrow == Value_Params.M + 1)
        agentutility = 0;
        return;
    end

    %% 2. 准备基础数据
    % 读取资源类型数量 K
    K = Value_Params.K;
    % 获取当前任务的资源需求向量（转置为行向量以便计算）
    demand = tasks(numberrow).resource_demand(:)';
    
    %% 3. 解析联盟成员 (Column Index -> Agent ID)
    % 输入的 numberofcoworker 只是列索引，需要查 coalitionstru 表才能知道具体是谁
    member_ids = [];
    for i = 1:length(numberofcoworker)
        col_idx = numberofcoworker(i);                                   % 取出列号
        
        % 边界检查：确保列号在有效范围内
        if col_idx > 0 && col_idx <= size(Value_data.coalitionstru, 2)   
            % 从成员矩阵中查出真实的 Agent ID
            agent_id_tmp = Value_data.coalitionstru(numberrow, col_idx); 
            
            % 过滤无效 ID（ID必须大于0且在agents数组范围内）
            if agent_id_tmp > 0 && agent_id_tmp <= length(agents)       
                member_ids = [member_ids, agent_id_tmp];                 % 加入成员列表
            end
        end
    end

    % 如果解析后发现没有有效成员（理论上不应发生，除非数据错误），效用归零
    if isempty(member_ids)
        agentutility = 0;
        return;
    end

    %% 4. 确定当前智能体的 ID
    % 同样需要从 coalitionstru 中获取自己的 ID
    agent_id = Value_data.coalitionstru(numberrow, numbercolumn);
    
    % 防御性编程：如果查不到有效 ID，假定列索引即为 ID (适用于简单的一对一映射情况)
    if agent_id <= 0 || agent_id > numel(agents)
        agent_id = numbercolumn;                                         
    end

    % 定义数值容差，防止分母为 0
    eps_val = 1e-9;

    %% 5. 获取/构建联盟资源矩阵 SC_task (Snapshot)
    % 优先使用 Value_data.SC 中的资源分配结构（例如 SC_Q），否则退回到全额贡献假设。
    use_SC = false;
    if isfield(Value_data, 'SC') && numberrow <= numel(Value_data.SC) && ~isempty(Value_data.SC{numberrow})
        SC_task = Value_data.SC{numberrow};
        % 对齐资源维度
        if size(SC_task, 2) < K
            SC_task(:, end+1:K) = 0;
        elseif size(SC_task, 2) > K
            SC_task = SC_task(:, 1:K);
        end
        use_SC = true;
    else
        SC_task = [];
    end
    
    if ~use_SC
        % 退化：按照成员最大资源全额投入构造矩阵（原逻辑）
        SC_task = zeros(length(agents), K); % 初始化 N x K 矩阵
        for i = 1:length(member_ids)
            member_id = member_ids(i);                                        % 成员 ID
            if isfield(agents(member_id), 'resources')
                member_resources = agents(member_id).resources(:)';           % 获取该成员的最大资源能力
                
                % 填充矩阵，确保维度匹配
                if length(member_resources) >= K
                    SC_task(member_id, :) = member_resources(1:K);            % 截取前 K 维
                else
                    SC_task(member_id, 1:length(member_resources)) = member_resources; % 维度不足补0
                end
            end
        end
    end
    
    % 仅保留有效成员行
    valid_members = member_ids(member_ids <= size(SC_task, 1));
    if isempty(valid_members)
        agentutility = 0;
        return;
    end

    %% 6. 计算收益 (Revenue) 相关指标
    
    % 6.1 联盟总资源：按有效成员将资源累加
    total_resources = sum(SC_task(valid_members, :), 1);
    
    % 6.2 资源完成度 (D_C)：衡量提供的资源满足了多少需求 (0~1)
    % 如果完成度为 0，说明没有任何有效资源投入，效用直接为 0
    D_C = OCFUtils.calc_task_completion_degree(total_resources, demand, K);
    if D_C == 0
        agentutility = 0;
        return;
    end

    % 6.3 资源贡献比例 (r_n)：当前智能体贡献占团队总贡献的比例
    % 公式：r_n = ||My_Resource|| / sum(||Member_Resources||)
    % agent 行索引：若超界则退回到第一个有效成员，避免空行
    agent_row_idx = agent_id;
    if agent_row_idx < 1 || agent_row_idx > size(SC_task, 1)
        agent_row_idx = valid_members(1);
    end
    r_n_C = OCFUtils.calc_resource_contribution_ratio(SC_task, agent_row_idx, valid_members);

    % 6.4 期望价值 (Expected Value, V_C)
    % 任务价值不是固定的，而是基于智能体的信念 (Belief) 计算的期望值。
    % 任务可能有多种类型 (task_types)，每种类型对应不同的价值。
    task_types = Value_Params.task_type;
    if isempty(task_types)
        task_types = numel(tasks(numberrow).WORLD.value);                 % 自动推断类型数量
    end
    
    values = tasks(numberrow).WORLD.value;                                % 任务在不同类型下的真实价值表
    tlen = min(task_types, numel(values));                                % 防止索引越界
    
    % 期望价值 = Sum( 某类型的价值 * 任务属于该类型的概率(信念) )
    V_C = sum(values(1:tlen) .* Value_data.initbelief(numberrow, 1:tlen)); 

    % 6.5 计算总收益
    revenue = r_n_C * V_C * D_C;

    %% 7. 计算成本 (Cost) - 包含同步机制
    
    % 7.1 计算所有成员的到达时间 (Arrival Time)
    arrival_times = zeros(1, numel(member_ids));
    for idx = 1:numel(member_ids)
        mid = member_ids(idx);
        start_xy_member = [agents(mid).x, agents(mid).y];                 % 成员位置
        
        % 注意：此处 compute_route_distance 第4个参数为 true (close_loop)，
        % 这意味着计算的是【往返距离】。如果仅仅是计算【到达时间】，这可能是一个近似或特定的算法设定。
        % 通常到达时间 = 单程距离 / 速度。
        one_way_dist = OCFUtils.compute_route_distance(start_xy_member, numberrow, tasks, false); 
        
        v_member = eps_val;
        if isfield(agents(mid), 'vel') && ~isempty(agents(mid).vel)
            v_member = max(agents(mid).vel, eps_val);                     % 获取速度
        end
        arrival_times(idx) = one_way_dist / v_member;                     % 计算该成员的耗时
    end

    % 7.2 同步开始时间 (Sync Start Time)
    % 任务必须等所有人到齐才能开始（木桶效应），所以取最大到达时间
    sync_start_time = max(arrival_times);

    % 7.3 获取当前智能体的到达时间
    my_idx = find(member_ids == agent_id, 1);
    if isempty(my_idx)
        my_arrival = 0; % 理论上不应发生
    else
        my_arrival = arrival_times(my_idx);
    end

    % 7.4 计算等待时间 (Wait Time)
    % 如果我早到了，我必须悬停等待队友。
    wait_time = max(0, sync_start_time - my_arrival);

    % 7.5 计算任务执行时间 (Exec Time)
    % 假设任务执行时长取决于最耗时的那种资源的固有处理时间
    task_exec_time = 0;
    if isfield(tasks(numberrow), 'duration_by_resource') && ~isempty(tasks(numberrow).duration_by_resource)
        task_exec_time = max(tasks(numberrow).duration_by_resource(:));
    elseif isfield(tasks(numberrow), 'duration')
        task_exec_time = tasks(numberrow).duration;
    end

    % 7.6 计算飞行能耗 (Fly Cost)
    % 重新计算一遍该智能体的闭环飞行距离
    start_xy = [agents(agent_id).x, agents(agent_id).y];
    total_distance = OCFUtils.compute_route_distance(start_xy, numberrow, tasks,true); % 默认 close_loop=true
    
    v_agent = eps_val;
    if isfield(agents(agent_id), 'vel') && ~isempty(agents(agent_id).vel)
        v_agent = max(agents(agent_id).vel, eps_val);
    end
    fly_time = total_distance / v_agent;                                  % 总飞行时间

    % 7.7 聚合各项成本
    alpha_fly = agents(agent_id).fuel;           % 单位飞行能耗
    alpha_wait = agents(agent_id).wait_fuel;     % 单位等待能耗
    beta = agents(agent_id).beta;                % 单位执行能耗
    
    % 总成本公式
    cost = fly_time * alpha_fly + wait_time * alpha_wait + task_exec_time * beta;

    %% 8. 计算最终效用
    % 净效用 = 收益 - 成本
    % 如果成本高于收益，则效用归零（理性的智能体不会做亏本生意）
    if (revenue - cost) > 0
        agentutility = revenue - cost;
    else
        agentutility = 0;
    end
end
