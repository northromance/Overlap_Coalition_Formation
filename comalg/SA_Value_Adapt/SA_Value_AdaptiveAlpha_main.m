function [Value_data, history_data]= SA_Value_AdaptiveAlpha_main(agents,tasks,AddPara,Value_Params)
% SA_Value_AdaptiveAlpha_main - 基于信念变化的自适应温度 SA 算法 (信念优化版)
%
% 核心逻辑修正：
%   1. [决策层] 内循环优化时，使用 calc_agent_total_utility (基于信念的主观效用)
%   2. [物理层] 外循环记录时，使用 UtilityEvaluator (基于真值的客观效用)
%
% 输入：
%   agents       - 智能体结构体数组
%   tasks        - 任务结构体数组
%   AddPara      - 附加控制参数
%   Value_Params - 算法全局参数

%% ==================== 0. 随机数种子设置 ====================
if isfield(Value_Params, 'seed')
    rng(Value_Params.seed);
end

%% ==================== 1. 初始化阶段 ====================
eps_val = 1e-6;
history_data = struct();

% --- 初始化智能体核心数据结构 (Value_data) ---
% 包含 SC (联盟结构矩阵), resources (资源状态), position (位置) 等
Value_data = WorldSim.init_value_data(agents, tasks, Value_Params);

% --- 初始化观测、信念与邻居信息 ---
% summatrix 用于记录观测次数，initbelief 初始化为先验分布
[Value_data, summatrix] = WorldSim.init_observe_belief_neighbor(Value_data, Value_Params.N, Value_Params.M, Value_Params);

%% ==================== 2. 主循环：多轮博弈迭代 ====================
% 仅用于记录历史最高真实效用（不做回滚操作）

for counter=1:Value_Params.num_rounds

    %% 2.2 SA (模拟退火) 迭代初始化
    k_iter = 1;
    previous_SC = Value_data(1).SC;
    k_stable = 0;
    doneflag = 0;

    % --- 自适应温度策略 ---
    T_0 = Value_Params.Temperature;
    T_base = 10;

    if counter == 1
        Value_Params.Temperature = T_0;
        if AddPara.verbose
            fprintf('  [SA_AdaptiveAlpha] Round %d: 初始温度 = %.2f（第一轮）\n', counter, Value_Params.Temperature);
        end
    else
        belief_diff = 0;
        for i = 1:Value_Params.N
            for j = 1:Value_Params.M
                if isfield(Value_data(i), 'prev_belief') && ~isempty(Value_data(i).prev_belief)
                    belief_diff = belief_diff + sum(abs(Value_data(i).initbelief(j,:) - Value_data(i).prev_belief(j,:)));
                end
            end
        end
        belief_diff = belief_diff / (Value_Params.N * Value_Params.M);

        threshold = 0.5;
        normalized_diff = min(belief_diff / threshold, 1.0);
        Value_Params.Temperature = T_base + (T_0 - T_base) * normalized_diff;

        if AddPara.verbose
            fprintf('  [SA_AdaptiveAlpha] Round %d: 信念变化 = %.4f, 初始温度 = %.2f\n', ...
                counter, belief_diff, Value_Params.Temperature);
        end
    end

    % 初始化本轮最优解
    best_SC = Value_data(1).SC;
    best_coalitionstru = Value_data(1).coalitionstru;
    best_utility = 0;
    for j = 1:Value_Params.N
        best_utility = best_utility + UtilityEvaluator.calc_agent_total_utility(best_SC, agents, tasks, Value_Params, Value_data(j), AddPara);
    end


    %% ==================== 2.3 第一轮：生成初始解 ====================
    if counter == 1
        if AddPara.verbose
            fprintf('  [SA] 第1轮：基于低温概率与规则生成的初始联盟结构 (Soft Greedy)...\n');
        end

        SC_global = Value_data(1).SC;
        task_type_demands = Value_Params.task_type_demands;
        resource_confidence = Value_Params.SA_resource_confidence;
        T_init_construction = Value_Params.SA_T_init_construction;

        for i = 1:Value_Params.N
            % 1. 更新视图
            Value_data(i).SC = SC_global;

            % 2. 计算缺口
            [~, resource_gap] = calc_gaps(Value_data(i), Value_Params, AddPara);

            % ⭐ [核心修改] 调用概率函数时，传入 T_init_construction
            probs = SA_Select_probs(Value_data(i), agents, tasks, Value_Params, resource_gap, T_init_construction);

            % 3. 资源分配
            for k = 1:Value_Params.K
                resource_amt = agents(i).resources(k);
                if resource_amt <= 0, continue; end

                % 轮盘赌选择 (基于低温产生的尖锐概率分布)
                prob_vec = probs(k, :);
                cum_prob = cumsum(prob_vec);

                % [安全性检查] 如果概率全为0 (无合适任务)，随机选一个防止报错
                if cum_prob(end) > 1e-9
                    r = rand * cum_prob(end);
                    selected_task = find(cum_prob >= r, 1, 'first');
                else
                    selected_task = randi(Value_Params.M);
                end
                if isempty(selected_task), selected_task = randi(Value_Params.M); end

                % 安检1: 重复检查
                if SC_global{selected_task}(i, k) > 0, continue; end

                % 安检2: 饱和度检查
                curr_alloc = sum(SC_global{selected_task}(:, k));
                belief = Value_data(i).initbelief(selected_task, :);
                expected_demand = WorldSim.calculate_demand_quantile(belief, task_type_demands, resource_confidence);
                can_add = max(0, expected_demand(k) - curr_alloc);

                if can_add > 0
                    % 安检3: 可行性检查
                    SC_candidate = SC_global;
                    SC_candidate{selected_task}(i, k) = resource_amt;

                    Value_data_temp = Value_data;
                    for j=1:Value_Params.N, Value_data_temp(j).SC = SC_candidate; end

                    [isFeasible, ~, ~] = validate_feasibility(Value_data_temp, agents, tasks, ...
                        Value_Params, i, SC_candidate, true, AddPara);

                    if isFeasible
                        SC_global = SC_candidate;
                    end
                end
            end

            % 序贯更新
            for j = 1:Value_Params.N, Value_data(j).SC = SC_global; end
        end

        % --- 数据同步与评估 ---
        for i = 1:Value_Params.N
            Value_data(i).SC = SC_global;
            Value_data(i).resources_matrix = OCFUtils.get_agent_resource_matrix(SC_global, i, Value_Params);
            Value_data(i).coalitionstru = OCFUtils.build_coalitionstru_from_SC(SC_global, Value_Params, agents);
        end

        best_SC = SC_global;
        best_coalitionstru = Value_data(1).coalitionstru;

        % 遍历求和计算初始效用
        best_utility = 0;
        for ii = 1:Value_Params.N
            u_i = UtilityEvaluator.calc_agent_total_utility(SC_global, agents, tasks, Value_Params, Value_data(ii), AddPara);
            best_utility = best_utility + u_i;
        end

        if AddPara.verbose
            fprintf('  [SA] 第1轮：初始联盟生成完成 (Soft Greedy, T=%.1f)，初始主观效用 = %.2f\n', T_init_construction, best_utility);
        end
    end
    %% ==================== 3. SA 内循环：联盟形成 ====================
    % 初始化内循环历史记录
    inner_loop_history = ResultProcessor.init_inner_loop_history();

    while(doneflag == 0)

        % --- 3.1 顺序博弈 ---
        for ii = 1:Value_Params.N
            [Value_data_ii] = Overlap_Coalition_Formation(agents, tasks, Value_data(ii), Value_Params,AddPara);

            Value_data(ii) = Value_data_ii;

            if ii < Value_Params.N
                Value_data(ii + 1).coalitionstru = Value_data_ii.coalitionstru;
                Value_data(ii + 1).SC = Value_data_ii.SC;
            end
        end

        % --- 3.3 SA 温度衰减 ---
        Value_Params.Temperature = Value_Params.alpha * Value_Params.Temperature;

        final_SC = Value_data(Value_Params.N).SC;
        final_coalitionstru = Value_data(Value_Params.N).coalitionstru;

        % --- 3.4 收敛性检测 ---
        if isequal(previous_SC, final_SC)
            k_stable = k_stable + 1;
        else
            k_stable = 0;
        end

        if k_stable >= Value_Params.SA_K_len
            doneflag = 1;
        elseif Value_Params.Temperature < Value_Params.Tmin
            doneflag = 1;
        elseif k_iter >= Value_Params.SA_K_max_inner
            doneflag = 1;
        end

        previous_SC = final_SC;
        k_iter = k_iter + 1;

        % --- 3.5 同步全局状态 ---
        for ii = 1:Value_Params.N
            Value_data(ii).coalitionstru = final_coalitionstru;
            Value_data(ii).SC = final_SC;
            Value_data(ii).resources_matrix = OCFUtils.get_agent_resource_matrix(Value_data(ii).SC,ii,Value_Params);
        end

        % --- 3.7 更新本轮最优解 (主观效用) ---
        current_utility = 0;
        for j = 1:Value_Params.N
            % ⭐ [关键修复] 必须使用 final_SC 来计算当前效用，不能用 SC_global
            % 之前的代码在这里使用了 SC_global，那是这一轮开始时的旧解，导致 SA 失效
            current_utility = current_utility + UtilityEvaluator.calc_agent_total_utility(final_SC, agents, tasks, Value_Params, Value_data(j), AddPara);
        end

        if current_utility > best_utility
            best_utility = current_utility;
            best_SC = final_SC;
            best_coalitionstru = final_coalitionstru;
        end

        % --- 3.8 记录内循环历史数据 ---
        inner_loop_history = ResultProcessor.record_inner_loop_iteration(...
            inner_loop_history, k_iter - 1, Value_Params.Temperature, ...
            current_utility, best_utility, final_SC, Value_Params);
    end

    %% 3.8 恢复本轮最优
    if ~isequal(final_SC, best_SC)
        if AddPara.verbose
            fprintf('  [SA_AdaptiveAlpha] Round %d: 恢复本轮最优解\n', counter);
        end
        final_SC = best_SC;
        final_coalitionstru = best_coalitionstru;
    end

    for ii = 1:Value_Params.N
        Value_data(ii).coalitionstru = best_coalitionstru;
        Value_data(ii).SC = best_SC;
        Value_data(ii).resources_matrix = OCFUtils.get_agent_resource_matrix(Value_data(ii).SC, ii, Value_Params);
    end

    Value_data = update_task_schedule(Value_data, agents, tasks, Value_Params);

    %% 观测与更新
    [Value_data, summatrix] = AgentOps.collect_observations(Value_data, agents, tasks, Value_Params, summatrix, final_SC);

    % ⭐ 保存旧信念 (用于下一轮自适应温度计算)
    for i = 1:Value_Params.N
        Value_data(i).prev_belief = Value_data(i).initbelief;
    end

    Value_data = AgentOps.update_belief_from_observations(Value_data, Value_Params);

    %% ==================== 4. 结果记录与评估 (客观视角) ====================
    % 使用真实参数评估当前联盟结构的性能
    [coalition_utility, total_global_cost, total_completed_value, task_completion_degrees] = ...
        UtilityEvaluator.evaluate_coalition_metrics(final_SC, agents, tasks, Value_Params, eps_val);


    %% 4.8 广播
    for i = 1:Value_Params.N
        for j = 1:Value_Params.N
            Value_data(i).other{j}.initbelief = Value_data(j).initbelief;
        end
    end

    % 记录
    history_data = ResultProcessor.record_history_data(history_data, counter, Value_data, Value_Params, ...
        final_SC, final_coalitionstru, ...
        coalition_utility, total_global_cost, ...
        total_completed_value, task_completion_degrees, ...
        summatrix);

    % 记录本轮的内循环迭代次数
    history_data.k_iter_per_round{counter} = k_iter;

    % 记录自适应温度相关数据
    if counter > 1
        history_data.belief_diff(counter) = belief_diff;
    else
        history_data.belief_diff(counter) = NaN;
    end
    history_data.initial_temperature(counter) = Value_Params.Temperature;

    % --- 记录内循环历史数据 ---
    history_data.inner_loop{counter} = inner_loop_history;
end

%% ==================== 5. 结束 ====================

% 最终一致性检查
if AddPara.verbose
    fprintf('\n[SA_AdaptiveAlpha] 执行最终一致性检查...\n');
end
[is_valid, error_log] = check_coalition_consistency(Value_data, agents, tasks, Value_Params, 'OCF', AddPara.verbose);
if ~is_valid
    warning('[SA_AdaptiveAlpha] 一致性检查发现 %d 处问题', length(error_log));
    history_data.consistency_errors = error_log;
else
    if AddPara.verbose
        fprintf('✅ [SA_AdaptiveAlpha] 所有一致性检查通过！\n');
    end
end

if AddPara.verbose
    fprintf('\n=== 仿真结束 ===\n');
end

end