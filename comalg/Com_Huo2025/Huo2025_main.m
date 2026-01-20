function [Value_data, history_data] = Huo2025_main(agents, tasks, AddPara, Value_Params)
% HUO2025_MAIN 基于多智能体联盟形成与任务值估计的主算法函数
%
% 核心逻辑：
%   这是一个去中心化的多智能体协同算法，模拟了以下过程：
%   1. 初始化：每个智能体拥有对任务价值的初始信念（InitBelief）。
%   2. 任务选择 (Value_order)：智能体基于当前信念和贪婪策略选择最佳任务。
%   3. 通信 (Value_communication)：智能体与邻居交换信息，更新对任务价值的认知。
%   4. 观测与更新 (Collect & Update)：智能体执行任务后获得观测值，利用贝叶斯推断更新信念。
%   5. 评估：计算每轮的联盟效用、成本和净收益，统计演化曲线。
%
% 输入：
%   agents       - 智能体结构体数组 (位置、速度、资源、传感器参数等)
%   tasks        - 任务结构体数组 (位置、真实价值、资源需求等)
%   AddPara      - 附加参数 (保留接口)
%   Value_Params - 全局参数 (M, N, K, 轮数等)
%
% 输出：
%   Value_data   - 最终时刻的系统状态 (联盟结构、资源分配、总效用)
%   history_data - 历史记录 (每轮的收益、成本曲线，用于画图)

%% ==================== 1. 初始化阶段 ====================

% 生成全连通的通信图（默认所有智能体可以相互通信）
Graph = ones(Value_Params.N, Value_Params.N);

% 获取任务类型数量 (用于信念向量的维度)
task_types = Value_Params.task_type;  
if isempty(task_types)
    task_types = numel(tasks(1).WORLD.value);
end

% 初始化每个智能体的内部状态
for i = 1:Value_Params.N 
    Value_data(i).agentID = agents(i).id;
    Value_data(i).agentIndex = i;
    Value_data(i).iteration = 0;      % 记录联盟变更次数
    Value_data(i).unif = 0;           % 随机变量 (用于随机策略或打破平局)
    
    % 联盟结构矩阵 (M+1) x N：记录每个任务有哪些智能体
    Value_data(i).coalitionstru = zeros(Value_Params.M+1, Value_Params.N);
    
    % 信念矩阵 (M x Types)：记录对每个任务类型的概率估计
    Value_data(i).initbelief = zeros(Value_Params.M+1, task_types);
    
    % 观测计数矩阵：记录历史观测到的次数 (用于 Dirichlet 更新)
    Value_data(i).observe = zeros(Value_Params.M, task_types);
    Value_data(i).preobserve = zeros(Value_Params.M, task_types);
    
    % --- 资源分配初始化 (与 SA 算法对齐) ---
    % resources_matrix (M x K): 我对每个任务投入的资源
    Value_data(i).resources_matrix = zeros(Value_Params.M, Value_Params.K);
    
    % SC (Cell Array): 全局资源分配视图
    Value_data(i).SC = cell(Value_Params.M, 1);      
    for m = 1:Value_Params.M
        Value_data(i).SC{m} = zeros(Value_Params.N, Value_Params.K);  
        % 初始资源分配为 0
        Value_data(i).SC{m}(i, :) = Value_data(i).resources_matrix(m, :);
    end
end

% 全局统计变量初始化
summatrix = zeros(Value_Params.M, task_types);            % 全局累积观测矩阵
total_value_history = zeros(1, Value_Params.num_rounds);  % 记录每轮完成的总任务价值
total_value_possible = sum(arrayfun(@(t) t.value, tasks));% 任务总潜在价值 (上限)

% 初始状态：所有智能体都在 Void 任务 (第 M+1 个任务) 中待命
for k = 1:Value_Params.N
    for j = 1:Value_Params.M+1
        if j == Value_Params.M+1
            for i = 1:Value_Params.N
                Value_data(k).coalitionstru(j,i) = agents(i).id;
            end
        end
    end
end

% 初始化信念：均匀分布 (表示一无所知)
for i = 1:Value_Params.N 
    for j = 1:Value_Params.M
        Value_data(i).initbelief(j, 1:end) = ones(1, task_types) / task_types;
    end
end


%% ==================== 2. 主循环：多轮博弈与演化 ====================
% 每一轮代表一次“决策-行动-观测-学习”的完整周期
for counter = 1:Value_Params.num_rounds
    
    % 记录每一轮开始时的信念 (用于调试或画图)
    for i = 1:Value_Params.N   
        for j = 1:Value_Params.M
            Value_data(i).tasks(j).prob(counter, :) = Value_data(i).initbelief(j, 1:end);
        end
    end
    
    % --- 子循环：联盟形成协商 (Coalition Formation) ---
    % 智能体之间通过多次迭代协商，达成稳定的联盟结构
    T = 1;         % 协商迭代步数
    lastTime = T-1;
    doneflag = 0;  % 收敛标志
    
    while(doneflag == 0)
        
        % 1. 任务选择 (Task Selection)
        % 每个智能体基于当前收益计算，贪婪地选择最佳任务
        for ii = 1:Value_Params.N
            % 调用 Value_order：计算如果加入其他任务能否提高效用
            [incremental(ii), curnumberrow(ii), Value_data(ii)] = Value_order(agents, tasks, Value_data(ii), Value_Params);
        end
        
        % 检查是否有智能体改变了主意
        if (length(find(incremental == 0)) == Value_Params.N)
            lastTime = lastTime; % 无人改变
        else
            lastTime = T;        % 有人改变，更新最后变动时间
        end
        
        % 2. 通信 (Communication)
        % 智能体交换信念和联盟结构信息，达成共识
        Value_data = Value_communication(agents, tasks, Value_data, Value_Params, Graph);
        
        % 3. 收敛检测 (Convergence Check)
        % 如果连续 2 次迭代没有人改变选择，认为联盟结构已稳定
        if (T - lastTime > 2)
            doneflag = 1;
        else
            T = T + 1;
        end
    end
    
    % 记录第一轮形成的初始联盟 (用于对比分析)
    if counter == 1
        for j = 1:Value_Params.M
            initial_coalition(j).member = find(Value_data(1).coalitionstru(j,:) ~= 0);
        end
    end
    
    % --- 观测与信念更新 (Observation & Belief Update) ---
    % 联盟稳定后，智能体执行任务并获得观测值
    
    % 构建当前任务列表
    curTaskList = cell(1, Value_Params.N);
    for i = 1:Value_Params.N
        if curnumberrow(i) ~= Value_Params.M+1
            curTaskList{i} = curnumberrow(i);
        else
            curTaskList{i} = []; % Void 任务无观测
        end
    end
    
    % 收集观测值 (模拟传感器数据)
    [Value_data, summatrix] = OCFUtils.collect_observations(Value_data, agents, tasks, Value_Params, curTaskList, summatrix);
    
    % 利用 Dirichlet 分布更新后验信念
    Value_data = OCFUtils.update_belief_from_observations(Value_data, Value_Params);
    
    
    %% ==================== 3. 绩效评估 (Evaluation) ====================
    % 计算本轮的成本、收益和净效用
    
    Rcost = zeros(Value_Params.M, Value_Params.N);
    coalition_utility = zeros(1, Value_Params.M);
    
    % 确定资源维度 K
    if isfield(Value_Params, 'K')
        K = Value_Params.K;
    elseif isfield(agents(1), 'resources')
        K = length(agents(1).resources);
    else
        K = 6;  % 默认
    end
    
    eps_val = 1e-9;
    total_completed_value = 0;
    
    % 遍历每个任务，计算其联盟表现
    for j = 1:Value_Params.M
        % 获取该任务的成员列表
        lianmeng(j).member = find(Value_data(1).coalitionstru(j,:) ~= 0);
        
        if isempty(lianmeng(j).member)
            coalition_utility(j) = 0;
            continue;
        end
        
        % 获取成员的真实 Agent ID
        member_ids = [];
        for idx = 1:length(lianmeng(j).member)
            col_idx = lianmeng(j).member(idx);
            agent_id = Value_data(1).coalitionstru(j, col_idx);
            if agent_id > 0 && agent_id <= length(agents)
                member_ids = [member_ids, agent_id];
            end
        end
        
        if isempty(member_ids)
            coalition_utility(j) = 0;
            continue;
        end
        
        % --- 计算资源完成度 (D_C) ---
        % 获取任务需求
        if isfield(tasks(j), 'resource_demand')
            demand = tasks(j).resource_demand(:)';
            if length(demand) < K
                demand = [demand, zeros(1, K - length(demand))];
            end
        else
            demand = ones(1, K) * 2;
        end
        
        % 汇总联盟总资源 (假设全额投入)
        total_resources = zeros(1, K);
        for i = 1:length(member_ids)
            member_id = member_ids(i);
            if isfield(agents(member_id), 'resources')
                member_res = agents(member_id).resources(:)';
                if length(member_res) >= K
                    total_resources = total_resources + member_res(1:K);
                elseif ~isempty(member_res)
                    total_resources(1:length(member_res)) = total_resources(1:length(member_res)) + member_res;
                end
            end
        end
        
        % 计算完成度 (0~1)
        D_C = OCFUtils.calc_task_completion_degree(total_resources, demand, K);
        
        % --- 计算期望收益 (Revenue) ---
        % 收益 = 期望价值 * 完成度
        values = tasks(j).WORLD.value;
        tlen = min(task_types, numel(values));
        % 期望价值基于当前信念 Value_data(1).initbelief (假设已达成共识)
        V_C = sum(values(1:tlen) .* Value_data(1).initbelief(j, 1:tlen));
        
        coalition_revenue = V_C * D_C;
        
        % --- 计算成本 (Cost) - 包含物理约束 ---
        % 1) 计算所有成员到达时间 (单程)
        arrival_times = zeros(1, numel(member_ids));
        for idx = 1:numel(member_ids)
            mid = member_ids(idx);
            start_xy = [agents(mid).x, agents(mid).y];
            one_way_dist = OCFUtils.compute_route_distance(start_xy, j, tasks, false);
            
            v_mid = eps_val;
            if isfield(agents(mid), 'vel') && ~isempty(agents(mid).vel)
                v_mid = max(agents(mid).vel, eps_val);
            end
            arrival_times(idx) = one_way_dist / v_mid;
        end
        
        % 同步开始时间 (木桶效应：等最后一个人到)
        sync_start = max(arrival_times);
        
        % 2) 计算任务执行时间 (并行模型)
        task_exec_time = 0;
        if isfield(tasks(j), 'duration_by_resource') && ~isempty(tasks(j).duration_by_resource)
            task_exec_time = max(tasks(j).duration_by_resource(:));
        elseif isfield(tasks(j), 'duration')
            task_exec_time = tasks(j).duration;
        end
        
        % 3) 计算每个成员的总成本 (飞行+等待+执行)
        coalition_cost = 0;
        for idx = 1:numel(member_ids)
            member_id = member_ids(idx);
            
            % 飞行成本 (闭环往返)
            start_xy = [agents(member_id).x, agents(member_id).y];
            total_dist = OCFUtils.compute_route_distance(start_xy, j, tasks); % 默认 true (闭环)
            
            v_mid = eps_val;
            if isfield(agents(member_id), 'vel') && ~isempty(agents(member_id).vel)
                v_mid = max(agents(member_id).vel, eps_val);
            end
            fly_time = total_dist / v_mid;
            
            % 等待成本 (Wait Time = Sync Start - My Arrival)
            my_arrival = arrival_times(idx);
            wait_time = max(0, sync_start - my_arrival);
            
            % 能耗系数
            alpha_fly = agents(member_id).fuel;
            alpha_wait = alpha_fly * 0.5; % 默认等待能耗是飞行的一半
            if isfield(agents, 'wait_fuel') && isfield(agents(member_id), 'wait_fuel') && ~isempty(agents(member_id).wait_fuel)
                alpha_wait = agents(member_id).wait_fuel;
            end
            
            beta = 0;
            if isfield(agents, 'beta') && isfield(agents(member_id), 'beta')
                beta = agents(member_id).beta;
            end
            
            member_cost = fly_time * alpha_fly + wait_time * alpha_wait + task_exec_time * beta;
            
            Rcost(j, member_id) = member_cost;
            coalition_cost = coalition_cost + member_cost;
        end
        
        % --- 汇总联盟净效用 ---
        coalition_utility(j) = max(coalition_revenue - coalition_cost, 0);
        
        % 统计真实完成价值 (用于对比实验)
        total_completed_value = total_completed_value + tasks(j).value * D_C;
    end
    
    % 记录本轮统计数据
    total_value_history(counter) = total_completed_value;  % 真实价值
    cost_sum(counter) = sum(Rcost(:));                     % 总成本
    net_profit(counter) = sum(coalition_utility);          % 总净收益
    
    counter = counter + 1; % 似乎多余，for 循环会自动增加
    
end

%% ==================== 4. 输出适配 (Formatting) ====================
% 将算法内部数据转换为统一的对比框架格式

% 1. 提取最终的 Value_data
final_Value_data = struct();
final_Value_data.coalitionstru = Value_data(1).coalitionstru;  % 最终联盟结构
final_Value_data.totalvalue = net_profit(end);                 % 最终净收益

% 2. 构建最终资源分配矩阵 (用于绘图或分析)
final_Value_data.agentresources = zeros(Value_Params.N, Value_Params.M, Value_Params.K);
for j = 1:Value_Params.M
    member_ids = find(Value_data(1).coalitionstru(j, :) ~= 0);
    for i = 1:length(member_ids)
        member_id = member_ids(i);
        if isfield(agents(member_id), 'resources')
            member_res = agents(member_id).resources(:)';
            if length(member_res) >= Value_Params.K
                final_Value_data.agentresources(member_id, j, :) = member_res(1:Value_Params.K);
            elseif ~isempty(member_res)
                final_Value_data.agentresources(member_id, j, 1:length(member_res)) = member_res;
            end
        end
    end
end

% 3. 填充历史记录与统计指标f
final_Value_data.cost_sum = cost_sum(end);
final_Value_data.net_profit_history = net_profit;
final_Value_data.cost_history = cost_sum;
final_Value_data.Rcost = Rcost;

% 4. 构建 History Data 结构体
history_data = struct();
history_data.algorithm = 'Huo2025';
history_data.final_utility = net_profit(end);
history_data.net_profit_evolution = net_profit;
history_data.cost_evolution = cost_sum;
history_data.num_rounds = Value_Params.num_rounds;
history_data.initial_coalition = initial_coalition;
history_data.total_value_history = total_value_history;
history_data.total_value_possible = total_value_possible;

% 返回结果
Value_data = final_Value_data;

end