function [Value_data, history_data] = Huo2025_main(agents, tasks, AddPara, Value_Params)
% HUO2025_MAIN 基于多智能体联盟形成与任务值估计的主算法函数
%
% 核心逻辑:
%   这是一个去中心化的多智能体协同算法，模拟了以下过程：
%   1. 初始化 (Initialization)：每个智能体拥有对任务价值的初始信念（InitBelief）。
%   2. 任务选择 (Task Selection / Value_order)：智能体基于当前信念和贪婪策略选择最佳任务。
%   3. 通信 (Communication / Value_communication)：智能体与邻居交换信息，更新对任务价值的认知。
%   4. 观测与更新 (Collect & Update)：智能体执行任务后获得观测值，利用贝叶斯推断更新信念。
%   5. 评估 (Evaluation)：计算每轮的联盟效用、成本和净收益，统计演化曲线。
%
% 输入:
%   agents       - 智能体结构体数组 (包含位置、速度、资源能力、传感器参数等)
%   tasks        - 任务结构体数组 (包含位置、真实价值、资源需求等)
%   AddPara      - 附加参数 (保留接口，用于扩展)
%   Value_Params - 全局参数 (包含任务数M, 智能体数N, 资源维数K, 总轮数等)
%
% 输出:
%   Value_data   - 最终时刻的系统状态 (联盟结构、资源分配、信念状态)
%   history_data - 历史记录 (用于画图：每轮的收益、成本、收敛曲线等)

%% ==================== 0. 随机数种子设置 (确保可复现性) ====================
% 修复：在算法开始时设置随机数种子，确保每次运行结果一致，方便调试。
if isfield(Value_Params, 'seed')
    rng(Value_Params.seed);
end

%% ==================== 1. 初始化阶段 ====================

% 生成全连通的通信图 (默认所有智能体可以相互通信，1代表连通)
Graph = ones(Value_Params.N, Value_Params.N);
history_data = struct();

% 获取任务类型的数量 (用于确定信念向量的维度，例如任务可能有3种潜在的价值分布)
task_types = Value_Params.task_type;
if isempty(task_types)
    % 如果未指定，则根据任务定义的维度自动获取
    task_types = numel(tasks(1).WORLD.value);
end

% --- 初始化每个智能体的内部状态 ---
for i = 1:Value_Params.N
    Value_data(i).agentID = agents(i).id;
    Value_data(i).agentIndex = i;
    Value_data(i).iteration = 0;      % 记录联盟变更/协商的次数
    Value_data(i).unif = 0;           % 随机变量 (用于随机策略或打破僵局)
    
    % 联盟结构矩阵 (M+1) x N
    % 行代表任务(M个任务 + 1个空闲状态)，列代表智能体。
    % 这是一个指示矩阵，记录哪个智能体选择了哪个任务。
    Value_data(i).coalitionstru = zeros(Value_Params.M+1, Value_Params.N);
    
    % 信念矩阵 (M x Types)
    % 智能体 i 对任务 m 属于类型 k 的概率估计。
    Value_data(i).initbelief = zeros(Value_Params.M+1, task_types);
    
    % 观测计数矩阵：记录历史观测到的次数 (用于 Dirichlet 分布更新)
    Value_data(i).observe = zeros(Value_Params.M, task_types);
    Value_data(i).preobserve = zeros(Value_Params.M, task_types);
    
    % --- 资源分配初始化 ---
    % resources_matrix (M x K): 我(智能体i)对每个任务投入的资源量
    Value_data(i).resources_matrix = zeros(Value_Params.M, Value_Params.K);
    
    % SC (Cell Array): 全局资源分配视图
    % 智能体 i 认为的全局资源分配情况。SC{m} 是一个 N x K 矩阵，表示所有智能体对任务 m 的投入。
    Value_data(i).SC = cell(Value_Params.M, 1);
    for m = 1:Value_Params.M
        Value_data(i).SC{m} = zeros(Value_Params.N, Value_Params.K);
        % 初始化：将自己的资源投入记录在视图中
        Value_data(i).SC{m}(i, :) = Value_data(i).resources_matrix(m, :);
    end
    % 任务执行与时间轴（供 PlotClass 动画与统计使用）
    Value_data(i).task_schedule = struct();
    Value_data(i).task_schedule.task_sequence = [];
    Value_data(i).task_schedule.arrival_times = [];
    Value_data(i).task_schedule.start_times = [];
    Value_data(i).task_schedule.mission_end_time = [];
    Value_data(i).task_schedule.execution_times = [];
    Value_data(i).task_schedule.completion_times = [];
    Value_data(i).task_schedule.total_flight_time = 0;
    Value_data(i).task_schedule.total_execution_time = 0;
    Value_data(i).task_schedule.total_energy = 0;
end
% 全局统计变量初始化
summatrix = zeros(Value_Params.M, task_types);            % 全局累计观测矩阵
total_value_history = zeros(1, Value_Params.num_rounds);  % 记录每轮完成的总任务价值
total_value_possible = sum(arrayfun(@(t) t.value, tasks));% 任务总潜在价值 (理论上限)

% --- 设置初始状态：所有智能体都在 Void 任务 ---
% Void 任务 (第 M+1 个任务) 通常代表"空闲"或"搜索中"。
for k = 1:Value_Params.N
    for j = 1:Value_Params.M+1
        if j == Value_Params.M+1
            for i = 1:Value_Params.N
                % 将所有智能体标记在第 M+1 行 (空闲任务)
                Value_data(k).coalitionstru(j,i) = agents(i).id;
            end
        end
    end
end

% --- 初始化信念：均匀分布 ---
% 初始时刻，智能体一无所知，认为任务属于任何类型的概率相等。
for i = 1:Value_Params.N
    for j = 1:Value_Params.M
        Value_data(i).initbelief(j, 1:end) = ones(1, task_types) / task_types;
    end
end

%% ==================== 2. 主循环：多轮博弈与演化 ====================
% 每一轮 (Round) 代表一次完整的 "决策-行动-观测-学习" 周期
%
for counter = 1:Value_Params.num_rounds
    
    % 记录每一轮开始时的信念 (用于调试或画图，观察信念如何收敛)
    for i = 1:Value_Params.N
        for j = 1:Value_Params.M
            Value_data(i).tasks(j).prob(counter, :) = Value_data(i).initbelief(j, 1:end);
        end
    end
    
    % --- 子循环：联盟形成协商 (Coalition Formation Negotiation) ---
    % 智能体之间通过多次迭代协商，达成稳定的联盟结构
    T = 1;         % 协商迭代步数
    lastTime = T-1;
    doneflag = 0;  % 收敛标志 (0:未收敛, 1:已收敛)
    
    while(doneflag == 0)
        
        % === 步骤 2.1: 任务选择 (Task Selection / Greedy) ===
        % 每个智能体基于当前收益计算，贪婪地选择最佳任务
        for ii = 1:Value_Params.N
            % Value_order 函数核心逻辑：
            % 智能体 ii 假设自己加入其他任务，计算边际贡献，选择贡献最大的任务。
            % 返回值：
            % incremental(ii): 效用增量 (是否变更了选择)
            % curnumberrow(ii): 当前选择的任务编号
            [incremental(ii), curnumberrow(ii), Value_data(ii)] = Value_order(agents, tasks, Value_data(ii), Value_Params);
        end
        
        % === 步骤 2.2: 稳定性检查 ===
        % 检查是否有智能体改变了主意 (incremental 记录了变更情况)
        if (length(find(incremental == 0)) == Value_Params.N)
            lastTime = lastTime; % 无人改变，最后变动时间保持不变
        else
            lastTime = T;        % 有人改变，更新最后变动时间为当前 T
        end
        
        % === 步骤 2.3: 通信 (Communication) ===
        % 智能体交换信念和联盟结构信息，达成共识。
        % 在这里，Value_data(i) 会被更新，包含邻居的最新选择。

        
        for k=1:Value_Params.N
            for n=1:Value_Params.N
                if Graph(k,n)==1
                    if (Value_data(k).iteration>Value_data(n).iteration)...
                            ||((Value_data(k).iteration==Value_data(n).iteration)&&(Value_data(k).unif>Value_data(n).unif))
                        %                if GAME_data(k).unif>GAME_data(n).unif
                        Value_data(n).coalitionstru=Value_data(k).coalitionstru;
                        Value_data(n).SC=Value_data(k).SC;
                        Value_data(n).iteration=Value_data(k).iteration;
                        Value_data(n).unif=Value_data(k).unif;
                    end
                end
            end
        end
        
        % === 步骤 2.4: 收敛判据 (Convergence Check) ===
        % 策略1：如果连续 2 次迭代没有任何人改变选择，认为联盟结构已稳定 (Nash Stable)。
        if (T - lastTime > 2)
            doneflag = 1;
        else
            T = T + 1;
        end
        
        % 策略2：最大迭代次数限制 (防止死循环)
        if isfield(Value_Params, 'max_stable_iterations') && T >= Value_Params.max_stable_iterations
            doneflag = 1;
        end
        
    end % End of While (Negotiation)
    
    % (可选) 记录第一轮形成的初始联盟，用于对比分析
    if counter == 1
        for j = 1:Value_Params.M
            initial_coalition(j).member = find(Value_data(1).coalitionstru(j,:) ~= 0);
        end
    end
    
    % --- 步骤 2.5: 观测与信念更新 (Observation & Belief Update) ---
    % 联盟稳定后，智能体执行任务并获得观测值。
    
    % 提取最终达成共识的资源分配和联盟结构 (以智能体1的视图为准，假设已达成共识)
    Final_SC = Value_data(1).SC;
    final_coalitionstru = Value_data(1).coalitionstru;
    
    % 1. 收集观测值 (Collect Observations)
    % 模拟传感器数据，根据任务真实类型生成带噪声的观测。
    % summatrix 累积了所有历史观测，用于 Bayesian 更新。
    [Value_data, summatrix] = AgentOps.collect_observations(Value_data, agents, tasks, Value_Params, summatrix, Final_SC);
    
    % 2. 更新后验信念 (Update Belief)
    % 利用 Dirichlet 分布 (Beta分布的多维推广) 更新对任务价值的概率估计。
    Value_data = AgentOps.update_belief_from_observations(Value_data, Value_Params);
    
    
    %% ==================== 3. 绩效评估 (Evaluation) ====================
    % 根据本轮的联盟形成结果，计算成本、收益和净效用。
    eps_val = 1e-9; % 防止除零错误
    
    % evaluate_coalition_metrics 计算：
    % - coalition_utility: 联盟产生的总价值
    % - Rcost: 资源消耗成本
    % - total_completed_value: 实际完成的任务价值
    % - task_completion_degrees: 任务完成度
    [coalition_utility, Rcost, total_completed_value, task_completion_degrees] = UtilityEvaluator.evaluate_coalition_metrics(Final_SC, agents, tasks, Value_Params, eps_val);
    
    % 记录本轮统计数据到 history_data 结构体
    history_data = ResultProcessor.record_history_data(history_data, counter, Value_data, Value_Params, ...
        Final_SC, final_coalitionstru, ...
        coalition_utility, Rcost, ...
        total_completed_value, task_completion_degrees, ...
        summatrix);
    
    % counter 在 for 循环中会自动增加，这行代码在 MATLAB 中其实是多余的，但保留原逻辑
    % counter = counter + 1;
    
end % End of For (Rounds)

% 统一补全任务时序信息，便于 PlotClass 动画与后续可视化
Value_data = update_task_schedule(Value_data, agents, tasks, Value_Params);

%% ==================== 4. 输出适配 (Formatting) ====================
% (可选) 数据一致性检查
% [is_consistent, logs] = check_data_consistency(Value_data, Value_Params);
% if ~is_consistent
%     disp('警告：数据存在严重不一致性，请检查通信模块。');
% end

end

