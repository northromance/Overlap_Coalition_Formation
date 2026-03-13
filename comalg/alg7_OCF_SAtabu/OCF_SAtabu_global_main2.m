function [Value_data, history_data] = OCF_SAtabu_global_main2(agents, tasks, AddPara, Value_Params)
feature('DefaultCharacterSet', 'UTF-8');
% SA_VALUE_TABUENHANCED_GLOBAL_MAIN 基于全局社会效用的模拟退火-禁忌搜索算法
%
% === [核心修改说明 - 全局社会效用（GSU）版本] ===
% 本版本引入了全局最优偏好机制，核心思想为“全局社会效用”：
%
%   1. Metropolis 准则：基于 Preference_gain 而非全局效用差值
%      - delta_E = SC_candidate 的全局社会效用 - SC_current 的全局社会效用
%      - 用于接受/拒绝候选解的概率性判定，是模拟退火的核心概率接受机制
%
%   2. 愿望准则（Aspiration Criterion）基于全局社会效用（Global Social Utility, GSU）
%      - GSU 定义：所有 N 个智能体在候选解下的效用总和
%      - 每个智能体维护自己观测到的历史最优 GSU（best_GSU），这里将其统一为全局变量
%      - 愿望条件：current_GSU > best_GSU
%      - 直观含义：即使当前候选解被禁忌，只要它能将全局社会效用提升到历史新高，就允许禁忌失效，强制执行
% ==============================================

%% ==================== 0. 随机数初始化 ====================
% 为了保证数值实验的可复现性（Reproducibility），固定随机数种子
if isfield(Value_Params, 'seed')
    rng(Value_Params.seed);
end

%% ==================== 1. 初始化阶段 ====================
eps_val = 1e-6;          % 浮点数比较容差
history_data = struct();
tabu_tenure = Value_Params.tabu_tenure; % 禁忌长度

Value_data = WorldSim.init_value_data(agents, tasks, Value_Params);
[Value_data, summatrix] = WorldSim.init_observe_belief_neighbor(Value_data, Value_Params.N, Value_Params.M, Value_Params);

%% ==================== 2. 外循环（轮次迭代） ====================
for counter = 1:Value_Params.num_rounds
    %% 2.2 SA 初始化
    k_iter = 1;                     % 内循环迭代计数
    previous_SC = Value_data(1).SC; % 上一轮联盟结构
    k_stable = 0;
    doneflag = 0;

    % 分轮温度调度：初始温度随轮次指数衰减
    Value_Params.Temperature = max(Value_Params.T_min_round, ...
        Value_Params.T0_round * Value_Params.T_decay^(counter-1));
    if AddPara.verbose
        fprintf('  [SA-Altruistic] Round %d: 初始温度 = %.2f\n', counter, Value_Params.Temperature);
    end

    % --- 初始化 GSU 最优记录 ---
    % GSU 是全局变量，表示所有智能体总效用之和，因此只需要计算一次，所有智能体共享
    best_SC = Value_data(1).SC;

    % 构造空SC作为GSU基准，用于初始化状态
    SC_empty = cell(Value_Params.M, 1);
    for m = 1:Value_Params.M
        SC_empty{m} = zeros(Value_Params.N, Value_Params.K);
    end
    % 计算一次，GSU 的值与 agent_idx 无关，因此任意传一个 agent 即可
    best_GSU = calculate_local_social_utility(SC_empty, best_SC, 1, agents, tasks, Value_Params, Value_data(1), AddPara);

    %% ==================== 2.25 初始化禁忌表 ====================
    % 禁忌表用于防止算法在局部状态之间反复震荡，从而避免局部循环
    tabu_list = {};
    if AddPara.verbose
        fprintf('  [Tabu] 禁忌长度 = %d\n', tabu_tenure);
    end

    %% ==================== 2.3 第一轮执行：构造初始解 (Soft Greedy) ====================
    % 在第1轮，为了加快收敛速度，使用带温度控制的“软贪婪”策略构造一个质量较好的初始联盟结构
    if counter == 1
        if AddPara.verbose
            fprintf('  [SA] 第1轮，使用软贪婪策略构造初始联盟结构 (Soft Greedy)...\n');
        end
        SC_global = Value_data(1).SC;
        task_type_demands = Value_Params.task_type_demands;
        resource_confidence = Value_Params.resource_confidence; % 资源需求置信度（处理不确定性）
        T_init_construction = Value_Params.T_init_construction;

        % 依次遍历每个智能体，根据当前资源缺口(gap)进行资源投放
        for i = 1:Value_Params.N
            Value_data(i).SC = SC_global;
            % 根据当前联盟结构计算当前资源缺口
            [~, resource_gap] = calc_gaps(Value_data(i), Value_Params, AddPara);

            % 使用软最大策略（softmax）生成概率分布，优先选择更偏向于缺口大的任务
            probs = SA_Select_probs(Value_data(i), agents, tasks, Value_Params, resource_gap, T_init_construction);

            for k = 1:Value_Params.K % 遍历每一类资源
                resource_amt = agents(i).resources(k);
                if resource_amt <= 0, continue; end % 如果没有第k类资源则跳过

                % 按概率选择任务（封装在 OCFUtils.sample_task_from_probs 中）
                selected_task = OCFUtils.sample_task_from_probs(probs(k, :), Value_Params.M);
                if isempty(selected_task), continue; end

                % 如果当前该任务已经投过该类资源，则跳过
                if SC_global{selected_task}(i, k) > 0, continue; end

                % 根据置信需求判断是否需要补充该类资源
                curr_alloc = sum(SC_global{selected_task}(:, k));
                belief = Value_data(i).initbelief(selected_task, :);
                expected_demand = WorldSim.calculate_demand_quantile(belief, task_type_demands, resource_confidence);
                can_add = max(0, expected_demand(k) - curr_alloc);

                % 如果该任务还需要该类资源，则尝试投放
                if can_add > 0
                    SC_candidate = SC_global;
                    SC_candidate{selected_task}(i, k) = resource_amt;

                    % 验证该动作是否合法（如不超过资源容量等硬约束）
                    Value_data_temp = Value_data;
                    for j = 1:Value_Params.N, Value_data_temp(j).SC = SC_candidate; end
                    [isFeasible, ~, ~] = validate_feasibility(Value_data_temp, agents, tasks, ...
                        Value_Params, i, SC_candidate, true, AddPara);
                    if isFeasible
                        SC_global = SC_candidate; % 若合法则接受该步
                    end
                end
            end
            % 同步当前全局状态到所有Agent
            for j = 1:Value_Params.N, Value_data(j).SC = SC_global; end
        end

        % 贪婪分配完成后，构造最终内部数据结构（资源矩阵、联盟结构）
        for i = 1:Value_Params.N
            Value_data(i).SC = SC_global;
            Value_data(i).resources_matrix = OCFUtils.get_agent_resource_matrix(SC_global, i, Value_Params);
            Value_data(i).coalitionstru = OCFUtils.build_coalitionstru_from_SC(SC_global, Value_Params, agents);
        end

        % 对构造出的初始解重新计算全局GSU，并更新一次全局最优记录
        best_SC = SC_global;
        best_GSU = calculate_local_social_utility(SC_empty, SC_global, 1, agents, tasks, Value_Params, Value_data(1), AddPara);
    end

    %% ==================== 3. SA 内循环（核心搜索过程 - 禁忌增强版） ====================
    inner_loop_history = ResultProcessor.init_inner_loop_history();

    % 记录当前状态的全局效用（上帝视角），用于画图/分析
    current_utility_global = 0;
    for j = 1:Value_Params.N
        current_utility_global = current_utility_global + UtilityEvaluator.calc_agent_total_utility(Value_data(j).SC, agents, tasks, Value_Params, Value_data(j), AddPara);
    end

    % [新增/修改 1: 每轮搜索开始前，初始化“精英解”，逐步记录目前最好的全局状态]
    elite_global_utility = current_utility_global;
    elite_SC = Value_data(1).SC;
    elite_coalitionstru = Value_data(1).coalitionstru;

    while(doneflag == 0)
        % --- 3.1 顺序扫描：N个Agent轮流决策 ---
        for ii = 1:Value_Params.N
            % 步骤1：为当前 ii 智能体生成一个局部候选解（可能撤出某些任务，加入某些任务）
            [SC_candidate, ~] = generate_candidate_solution_tabu(Value_data(ii), agents, tasks, Value_Params, AddPara);

            % 步骤3：禁忌判断 (Tabu Check)
            candidate_hash = get_SC_hash(SC_candidate, Value_Params); % 对分配结构进行哈希编码，唯一标识
            is_tabu = is_in_tabu_list(candidate_hash, tabu_list);     % 判断该解是否在禁忌表中

            % GSU 是全局变量，与 agent_idx 无关，因此当前只算一次，用于同时支持禁忌/非禁忌、接受概率判断
            SC_current = Value_data(ii).SC;
            current_GSU = calculate_local_social_utility(SC_current, SC_candidate, 1, agents, tasks, Value_Params, Value_data(ii), AddPara);

            accept = false;

            if is_tabu
                % === [GSU 愿望准则：当前候选解的全局效用超过历史最优时，允许突破禁忌强制接受] ===
                if current_GSU > best_GSU
                    accept = true;
                    if AddPara.verbose
                        fprintf('      [Agent %d] GSU愿望准则触发，接受禁忌解 (GSU=%.2f > 历史=%.2f)\n', ...
                            ii, current_GSU, best_GSU);
                    end
                else
                    if AddPara.verbose
                        fprintf('      [Agent %d] 拒绝禁忌解 (GSU=%.2f)\n', ii, current_GSU);
                    end
                end
            else
                % === [Fang et al. 2026 四分支接受概率公式] ===
                % P_a(T, CS*, CS') 定义：
                %   ΔU1 = u_i(CS') - u_i(CS)              : 智能体 i 自身效用变化
                %   ΔU2 = Σ_{o≠i}[u_o(CS') - u_o(CS)]    : 其余所有智能体效用变化之和
                %
                %   Case 1: ΔU1>0 且 ΔU2>0  → P = 1           (双方均受益，确定性接受)
                %   Case 2: ΔU1≤0 且 ΔU2>0  → P = exp(ΔU1/T)  (自损利他，按个体损失概率接受)
                %   Case 3: ΔU1>0 且 ΔU2≤0  → P = exp(ΔU2/T)  (自利损他，按他人损失概率接受)
                %   Case 4: ΔU1≤0 且 ΔU2≤0  → P = exp((ΔU1+ΔU2)/T) (双方均损，按总损失概率接受)

                % --- 计算 ΔU1：智能体 ii 自身效用变化 ---
                AddPara_silent = AddPara; AddPara_silent.verbose = false;
                temp_cand_i = Value_data(ii); temp_cand_i.SC = SC_candidate;
                temp_curr_i = Value_data(ii); temp_curr_i.SC = SC_current;
                u_ii_cand = UtilityEvaluator.calc_agent_total_utility(SC_candidate, agents, tasks, Value_Params, temp_cand_i, AddPara_silent);
                u_ii_curr = UtilityEvaluator.calc_agent_total_utility(SC_current,   agents, tasks, Value_Params, temp_curr_i, AddPara_silent);
                delta_U1 = u_ii_cand - u_ii_curr;

                % --- 计算 ΔU2：其余智能体效用变化之和 = delta_GSU - ΔU1 ---
                delta_U2 = global_utility_diff(tasks, agents, SC_current, SC_candidate, ii, Value_Params, Value_data(ii));
      

                % --- 四分支概率判断 ---
                T_cur = Value_Params.Temperature;
                if delta_U1 > 1e-4 && delta_U2 > 1e-4
                    % Case 1: 双方均受益 → 确定性接受
                    accept = true;
                    prob   = 1;
                elseif delta_U1 <= 1e-4 && delta_U2 > 1e-4
                    % Case 2: 自损利他 → exp(ΔU1/T)
                    prob   = exp(delta_U1 / T_cur);
                    accept = (rand < prob);
                elseif delta_U1 > 1e-4 && delta_U2 <= 1e-4
                    % Case 3: 自利损他 → exp(ΔU2/T)
                    prob   = exp(delta_U2 / T_cur);
                    accept = (rand < prob);
                else
                    % Case 4: 双方均损 → exp((ΔU1+ΔU2)/T) = exp(delta_GSU/T)
                    prob   = exp((delta_U1+ delta_U2)/ T_cur);
                    accept = (rand < prob);
                end

                if AddPara.verbose && accept && prob < 1
                    fprintf('      [Agent %d] 概率接受 (ΔU1=%.2f, ΔU2=%.2f, prob=%.4f)\n', ...
                        ii, delta_U1, delta_U2, prob);
                end
            end

            % 步骤5：执行解的更新
            if accept
                % 5.1 广播 SC + coalitionstru 到全体智能体（统一看板）
                % coalitionstru 只构建一次，避免 N 次重复计算
                new_coalitionstru = OCFUtils.build_coalitionstru_from_SC(SC_candidate, Value_Params, agents);
                for jj = 1:Value_Params.N
                    Value_data(jj).SC            = SC_candidate;
                    Value_data(jj).coalitionstru = new_coalitionstru;
                end
                % 更新当前行动者 ii 的 resources_matrix
                % 其余智能体的 resources_matrix 在本轮末尾统一同步，保证统计一致
                Value_data(ii).resources_matrix = OCFUtils.get_agent_resource_matrix(SC_candidate, ii, Value_Params);

                % 5.2 将新接受的状态加入禁忌表
                if ~is_tabu
                    tabu_list = update_tabu_list(tabu_list, candidate_hash, tabu_tenure);
                end

                % 5.3 检查并更新全局 GSU 最优记录
                % current_GSU 已在步骤3前算好，直接复用，避免重复计算
                if current_GSU > best_GSU
                    best_GSU = current_GSU;
                    if AddPara.verbose
                        fprintf('      [Agent %d 更新] 新的全局GSU最优 (GSU=%.2f)\n', ii, best_GSU);
                    end
                end
                % 注意：coalitionstru 已在 5.1 广播给全体，因此无需在此重复处理
            end
        end  % end for ii

        % 模拟退火降温：Temperature = alpha * Temperature
        Value_Params.Temperature = Value_Params.alpha * Value_Params.Temperature;

        % 获取最终共享联盟结构
        final_SC = Value_data(Value_Params.N).SC;
        final_coalitionstru = Value_data(Value_Params.N).coalitionstru;

        % [新增/修改 2: 当前全局状态同步后，准确计算一次全局效用，用于记录]
        for ii = 1:Value_Params.N
            Value_data(ii).coalitionstru = final_coalitionstru;
            Value_data(ii).SC = final_SC;
            Value_data(ii).resources_matrix = OCFUtils.get_agent_resource_matrix(final_SC, ii, Value_Params);
        end

        current_utility_global = 0;
        for j = 1:Value_Params.N
            current_utility_global = current_utility_global + UtilityEvaluator.calc_agent_total_utility(final_SC, agents, tasks, Value_Params, Value_data(j), AddPara);
        end

        % 精英保留策略：如果当前轮产生了新的历史最高全局效用，则保存
        if current_utility_global > elite_global_utility
            elite_global_utility = current_utility_global;
            elite_SC = final_SC;
            elite_coalitionstru = final_coalitionstru;
            if AddPara.verbose
                fprintf('    [Elite] 更新！发现本轮迭代历史最优全局效用: %.2f (Iter: %d)\n', elite_global_utility, k_iter);
            end
        end

        % 记录内循环（退火过程中的每一步）历史信息
        inner_loop_history = ResultProcessor.record_inner_loop_iteration(...
            inner_loop_history, k_iter, ...
            Value_Params.Temperature, current_utility_global, elite_global_utility, final_SC, Value_Params);

        % 判断是否稳定
        if isequal(previous_SC, final_SC)
            k_stable = k_stable + 1;
        else
            k_stable = 0;
        end

        % 退出条件：稳定次数达到 / 温度过低 / 达到最大迭代数
        if k_stable >= Value_Params.K_stable_max
            doneflag = 1;
        elseif Value_Params.Temperature < Value_Params.Tmin
            doneflag = 1;
        elseif k_iter >= Value_Params.max_inner_iter
            doneflag = 1;
        end

        % 更新上一轮状态
        previous_SC = final_SC;
        
        if AddPara.verbose
            fprintf('  [SA-Outer] Iter %d: T=%.2f, Utility=%.2f, Best=%.2f\n', ...
                k_iter, Value_Params.Temperature, current_utility_global, elite_global_utility);
        end
        k_iter = k_iter + 1;
    end  % end while

    % [新增/修改 3: 强制在每轮结束时回滚到本轮搜索过程中发现的最优精英解，作为最终输出]
    if AddPara.verbose
        fprintf('  [SA-Done] Round %d 退火结束，执行精英解回滚 (Utility: %.2f)\n', counter, elite_global_utility);
    end
    final_SC = elite_SC;
    final_coalitionstru = elite_coalitionstru;
    for ii = 1:Value_Params.N
        Value_data(ii).coalitionstru = final_coalitionstru;
        Value_data(ii).SC = final_SC;
        Value_data(ii).resources_matrix = OCFUtils.get_agent_resource_matrix(final_SC, ii, Value_Params);
    end
    % =========================================================================

    % 更新任务执行状态，并计算当前执行时序（Schedule）
    Value_data = update_task_schedule(Value_data, agents, tasks, Value_Params);

    %% ==================== 4. 观测与信念更新 ====================
    % 基于精英解 final_SC 进行观测并更新信念
    [Value_data, summatrix] = AgentOps.collect_observations(Value_data, agents, tasks, Value_Params, summatrix, final_SC);
    Value_data = AgentOps.update_belief_from_observations(Value_data, Value_Params);

    %% ==================== 5. 计算联盟效用（上帝视角） ====================
    [coalition_utility, total_global_cost, total_completed_value, task_completion_degrees] = ...
        UtilityEvaluator.evaluate_coalition_metrics(final_SC, agents, tasks, Value_Params, eps_val);

    %% 4.8 信念广播
    for i = 1:Value_Params.N
        for j = 1:Value_Params.N
            Value_data(i).other{j}.initbelief = Value_data(j).initbelief;
        end
    end

    % --- 记录每轮运行关键历史数据，用于后续画图分析 ---
    history_data = ResultProcessor.record_history_data(history_data, counter, Value_data, Value_Params, ...
        final_SC, final_coalitionstru, ...
        coalition_utility, total_global_cost, ...
        total_completed_value, task_completion_degrees, ...
        summatrix);
    history_data.inner_loop{counter} = inner_loop_history;

    % 记录每轮内循环迭代次数
    history_data.k_iter_per_round{counter} = k_iter;

    % 记录该轮全局社会效用（GSU）最优值，便于后续分析
    history_data.best_GSU{counter} = best_GSU;
end

%% ==================== 6. 最终结果一致性检查 ====================
if AddPara.verbose
    fprintf('\n[SA_Value_Altruistic] 执行结束，进行一致性检查...\n');
end
% OCF 一致性检查，确保最终联盟分配没有违反资源容量、任务调度等约束
[is_valid, error_log] = check_coalition_consistency(Value_data, agents, tasks, Value_Params, 'OCF', AddPara.verbose);
if ~is_valid
    warning('[SA_Value_Altruistic] 一致性检查发现 %d 个问题', length(error_log));
    history_data.consistency_errors = error_log;
else
    if AddPara.verbose
        fprintf('  [SA_Value_Altruistic] 所有一致性检查通过。\n');
    end
end
end

%% ==================== 内部辅助函数 ====================

% 生成联盟结构的哈希值，用于将当前解编码成唯一字符串，便于禁忌表检索
function hash_str = get_SC_hash(SC, Value_Params)
hash_parts = {};
eps_val = 1e-9;
for m = 1:Value_Params.M
    SC_m = SC{m};
    % 只记录所有非0元素，对应实际资源投放动作
    [rows, cols] = find(SC_m > eps_val);
    for idx = 1:length(rows)
        i = rows(idx); % Agent i
        k = cols(idx); % Resource k
        amount = SC_m(i, k);
        hash_parts{end+1} = sprintf('%d-%d-%d-%.4f', m, i, k, amount);
    end
end
hash_parts = sort(hash_parts); % 排序保证相同联盟结构生成相同哈希
if isempty(hash_parts)
    hash_str = 'EMPTY';
else
    hash_str = strjoin_custom(hash_parts, '|');
end
end

% 判断是否在禁忌表中
function is_tabu = is_in_tabu_list(hash_str, tabu_list)
is_tabu = ~isempty(tabu_list) && any(strcmp(tabu_list, hash_str));
end

% 更新禁忌表，先进先出（FIFO）
function tabu_list = update_tabu_list(tabu_list, hash_str, tabu_tenure)
tabu_list{end+1} = hash_str;
% 如果超过长度限制，移除最早进入的解
if length(tabu_list) > tabu_tenure
    tabu_list = tabu_list(2:end);
end
end

% 字符串拼接自定义函数，兼容低版本 MATLAB（无 strjoin 时）
function result = strjoin_custom(cell_array, delimiter)
if isempty(cell_array)
    result = '';
    return;
end
result = cell_array{1};
for i = 2:length(cell_array)
    result = [result, delimiter, cell_array{i}];
end
end

function [SC_candidate, move_description] = generate_candidate_solution_tabu(Value_data_i, agents, tasks, Value_Params, AddPara)
agent_idx = Value_data_i.agentIndex;
M = Value_Params.M;
K = Value_Params.K;
eps_val = 1e-9;
current_T = Value_Params.Temperature;

confidence = Value_Params.resource_confidence;  % 统一使用 Value_Params.resource_confidence

p_leave = Value_Params.p_leave;  % 离开概率，统一由 Value_Params.p_leave 控制

% --- 步骤 A：随机移除部分已分配资源 ---
SC_temp = Value_data_i.SC;
for m = 1:M
    for k = 1:K
        if SC_temp{m}(agent_idx, k) > eps_val && rand < p_leave
            if AddPara.verbose
                fprintf('      [-] [移除] Agent #%-2d 从 任务 M=%-2d 撤出 资源 k=%-2d | 数量: %.2f\n', ...
                    agent_idx, m, k, SC_temp{m}(agent_idx, k));
            end
            SC_temp{m}(agent_idx, k) = 0;
        end
    end
end

% 更新当前结构，准备生成下一种分配
Value_data_i.SC = SC_temp;
% 计算当前系统资源缺口（Gaps）
[~, resource_gap] = calc_gaps(Value_data_i, Value_Params, AddPara);
% 使用 softmax 生成选择概率，增强探索能力
probs = SA_Select_probs(Value_data_i, agents, tasks, Value_Params, resource_gap, current_T);
SC_new = SC_temp;
task_type_demands = Value_Params.task_type_demands;

% --- 步骤 B：重新分配资源，形成候选解 ---
for k = 1:K
    total_capacity = agents(agent_idx).resources(k);
    if total_capacity <= eps_val, continue; end
    
    % 按概率选择目标任务（封装在 OCFUtils.sample_task_from_probs 中）
    selected_task = OCFUtils.sample_task_from_probs(probs(k, :), M);
    if isempty(selected_task), continue; end
    % 已经对该任务投放过该类资源则跳过
    if SC_new{selected_task}(agent_idx, k) > eps_val, continue; end

    % 判断该任务是否仍然需要该类资源
    curr_alloc = sum(SC_new{selected_task}(:, k));
    belief = Value_data_i.initbelief(selected_task, :);
    expected_demand = WorldSim.calculate_demand_quantile(belief, task_type_demands, confidence);
    can_add = max(0, expected_demand(k) - curr_alloc);
    
    if can_add > eps_val
        SC_candidate_temp = SC_new;
        SC_candidate_temp{selected_task}(agent_idx, k) = total_capacity; % 全量投放
        
        % 封装成全体状态数组
        Value_data_array = repmat(Value_data_i, Value_Params.N, 1);
        for j = 1:Value_Params.N
            Value_data_array(j).agentIndex = j;
            Value_data_array(j).SC = SC_candidate_temp;
        end
        
        % 调用可行性检查
        [isFeasible, info, ~] = validate_feasibility(Value_data_array, agents, tasks, ...
            Value_Params, agent_idx, SC_candidate_temp, true, AddPara);
            
        if isFeasible
            SC_new = SC_candidate_temp;
            if AddPara.verbose
                fprintf('      [+] [加入] Agent #%-2d 向 任务 M=%-2d 投入 资源 k=%-2d | 数量: %.2f\n', ...
                    agent_idx, selected_task, k, total_capacity);
            end
        else
            if AddPara.verbose
                fprintf('      [x] [拒绝] Agent #%-2d 向 任务 M=%-2d 投入 资源 k=%-2d 失败 | 原因: %s\n', ...
                    agent_idx, selected_task, k, info.reason);
            end
        end
    end
end

SC_candidate = SC_new;
move_description = sprintf('SA_Tabu_Altruistic_Agent_%d', agent_idx);
end

% 计算全局社会效用 (Global Social Utility, GSU)
% GSU = 所有 N 个智能体在 SC_candidate 下的效用总和
% SC_old 参数保留是为了兼容原有调用接口，本版本中未使用，因为这里只关心候选状态
function GSU = calculate_local_social_utility(SC_old, SC_candidate, agent_idx, agents, tasks, Value_Params, Value_data, AddPara) %#ok<INUSL>
    % 遍历全体 N 个智能体，累加各自在 SC_candidate 下的效用，得到全局社会效用
    GSU = 0;
    for j = 1:Value_Params.N
        % 优先使用智能体 j 的主观 belief（从 agent_idx 的 other 字段中获取）
        % 如果没有记录，则退化为 agent_idx 的 belief 作为近似
        if j == agent_idx
            agent_belief = Value_data.initbelief;
        elseif length(Value_data.other) >= j && ~isempty(Value_data.other{j})
            agent_belief = Value_data.other{j}.initbelief;
        else
            agent_belief = Value_data.initbelief; % 近似替代
        end

        temp_data.agentIndex = j;
        temp_data.initbelief = agent_belief;
        temp_data.SC = SC_candidate;
        GSU = GSU + UtilityEvaluator.calc_agent_total_utility(SC_candidate, agents, tasks, Value_Params, temp_data, AddPara);
    end
end

% 计算当前解与候选解之间的全局效用差值 (Preference Gain)
% delta_E = GSU(SC_candidate) - GSU(SC_current)
% 即候选联盟结构下所有智能体总效用 减去 当前联盟结构下所有智能体总效用
function delta_E = global_utility_diff(tasks, agents, SC_current, SC_candidate, agent_idx, Value_Params, Value_data_i) %#ok<INUSL>
    AddPara_silent.verbose = false;

    % 计算候选解下的全局社会效用
    GSU_candidate = 0;
    for j = 1:Value_Params.N
        if j == agent_idx
            agent_belief = Value_data_i.initbelief;
        elseif length(Value_data_i.other) >= j && ~isempty(Value_data_i.other{j})
            agent_belief = Value_data_i.other{j}.initbelief;
        else
            agent_belief = Value_data_i.initbelief;
        end
        temp_data.agentIndex = j;
        temp_data.initbelief = agent_belief;
        temp_data.SC = SC_candidate;
        GSU_candidate = GSU_candidate + UtilityEvaluator.calc_agent_total_utility(SC_candidate, agents, tasks, Value_Params, temp_data, AddPara_silent);
    end

    % 计算当前解下的全局社会效用
    GSU_current = 0;
    for j = 1:Value_Params.N
        if j == agent_idx
            agent_belief = Value_data_i.initbelief;
        elseif length(Value_data_i.other) >= j && ~isempty(Value_data_i.other{j})
            agent_belief = Value_data_i.other{j}.initbelief;
        else
            agent_belief = Value_data_i.initbelief;
        end
        temp_data.agentIndex = j;
        temp_data.initbelief = agent_belief;
        temp_data.SC = SC_current;
        GSU_current = GSU_current + UtilityEvaluator.calc_agent_total_utility(SC_current, agents, tasks, Value_Params, temp_data, AddPara_silent);
    end

    % 全局效用差值：正值表示候选解更优，负值表示候选解更差
    delta_E = GSU_candidate - GSU_current;
end