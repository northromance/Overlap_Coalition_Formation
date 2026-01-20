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
    % 根据本轮的联盟形成结果的成本、收益和净效用

    Rcost = zeros(Value_Params.M, Value_Params.N);
    coalition_utility = zeros(1, Value_Params.M);

    % 资源维度 K（优先参数，其次 agent 定义）
    K = Value_Params.K;
    eps_val = 1e-9;
    total_completed_value = 0;

    % 遍历每个任务，按与 Value_utility 相同的逻辑计算收益/成本
    for j = 1:Value_Params.M
        % 参与者：优先用 SC 解析，若无则回落到联盟矩阵
        participants = OCFUtils.get_participants(Value_data(1).SC,j, eps_val);

        if isempty(participants)
            coalition_utility(j) = 0;
            continue;
        end

        % 真实任务需求（不足补零，超出截断）
        demand = tasks(j).resource_demand(:)';

        SC_task = Value_data(1).SC{j}; % 当前任务的资源分配联盟结构

        % 完成度与期望价值
        total_resources = sum(SC_task(participants, :), 1);
        D_C = OCFUtils.calc_task_completion_degree(total_resources, demand, K);
        if D_C == 0
            coalition_utility(j) = 0;
            continue;
        end

        V_C = tasks(j).value;

        % 按 Value_utility 逻辑计算每个成员的贡献/成本并求和
        coalition_cost = 0;
        coalition_revenue = 0;
        for idx = 1:numel(participants)
            pid = participants(idx); % 成员序号

            % 贡献比（r_n）该成员在联盟j下的贡献比率
            r_n_C = OCFUtils.calc_resource_contribution_ratio(SC_task, pid, participants);
            agent_revenue = r_n_C * V_C * D_C;


            % 成本：全局同步时间表
            alpha_fly = agents(pid).fuel;
            alpha_wait = agents(pid).wait_fuel;
            beta = agents(pid).beta;


            % 当前联盟结构
            SC_global = Value_data(1).SC;
            % 参与者的资源分配矩阵
            R_agent_safe = Value_data(pid).resources_matrix;


            % B. 找出所有非零投入的任务 ID
            my_raw_tasks = find(any(R_agent_safe > eps_val, 2))';
      
            % D. 使用工具函数按优先级排序
            my_tasks = OCFUtils.sort_tasks_by_priority(my_raw_tasks, tasks);
            % ----------------------------------------------------
            [t_fly_total, t_wait_total, t_exec_total] = calc_with_global_sync( ...
                pid, my_tasks, agents, tasks, Value_Params, SC_global, R_agent_safe, eps_val);

            agent_cost = t_fly_total * alpha_fly + t_wait_total * alpha_wait + t_exec_total * beta;
            Rcost(j, pid) = agent_cost;

            coalition_revenue = coalition_revenue + agent_revenue;
            coalition_cost = coalition_cost + agent_cost;
        end

        coalition_utility(j) = max(coalition_revenue - coalition_cost, 0);
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
[is_consistent, logs] = check_data_consistency(Value_data, Value_Params);

if ~is_consistent
    disp('数据有严重问题，停止后续分析！');
    % 可以打印 logs 查看详情
end
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
