function [Value_data, history_data] = OCF_SAtabu_global_main(agents, tasks, AddPara, Value_Params)
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
    % 当 T_decay=1（默认）时，每轮从 T0_round 全温度重启，各轮独立探索；
    % 若需轮间渐进降温，可将 T_decay 改为 0.9~0.95，届时 T_min_round 作为下界生效
    Value_Params.Temperature = max(Value_Params.T_min_round, ...
        Value_Params.T0_round * Value_Params.T_decay^(counter-1));
    if AddPara.verbose
        fprintf('  [SA-Altruistic] Round %d: 初始温度 = %.2f\n', counter, Value_Params.Temperature);
    end

    % --- 初始化 GSU 最优记录（用于禁忌表愿望准则）---
    % 构造空SC作为基准，计算当前轮起始 SC 的 GSU
    SC_empty = cell(Value_Params.M, 1);
    for m = 1:Value_Params.M
        SC_empty{m} = zeros(Value_Params.N, Value_Params.K);
    end
    best_GSU = calculate_local_social_utility(SC_empty, Value_data(1).SC, 1, agents, tasks, Value_Params, Value_data(1), AddPara);

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

        % 对构造出的初始解重新计算全局GSU，并更新 best_GSU
        best_GSU = calculate_local_social_utility(SC_empty, SC_global, 1, agents, tasks, Value_Params, Value_data(1), AddPara);
    end

    %% ==================== 3. SA 内循环（核心搜索过程 - 禁忌增强版） ====================
    inner_loop_history = ResultProcessor.init_inner_loop_history();

    % [温度校准用] 累积本轮所有非禁忌劣解的 |ΔE|，用于统计均值以校准 T0
    delta_E_log = [];  % 只在第1轮第1迭代时收集

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
            % 一次调用同时得到 delta_E 和 GSU_candidate，避免重复计算 GSU(SC_candidate)
            [delta_E_altruistic, current_GSU] = global_utility_diff(tasks, agents, SC_current, SC_candidate, ii, Value_Params, Value_data(ii));

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
                % === [全局效用 Metropolis 准则] ===
                % 如果不在禁忌表中，则按照标准模拟退火准则判断是否接受

                % delta_E_altruistic 已在禁忌判断前统一计算，此处直接复用
                % 可选打印 delta E，调试时打开日志可观察
                % fprintf('  [ΔE] Round=%d Iter=%d Agent=%d  delta_E=%.4f  T=%.4f\n', counter, k_iter, ii, delta_E_altruistic, Value_Params.Temperature);

                % === [标准 Metropolis 准则实现] ===
                if delta_E_altruistic > 1e-4
                    % 如果是”优解”（社会效用更高或不变），则直接接受
                    accept = true;
                elseif delta_E_altruistic < 0
                    % 如果是”劣解”，则按照 Metropolis 概率接受
                    % dE=0 的情况留给上面分支处理；exp(0/T)=1 会导致等价解总被接受
                    % 这样可以让系统跳出局部最优（Local Optima）
                    delta_E_log(end+1) = abs(delta_E_altruistic); % 记录劣解 |ΔE| 供温度校准
                    prob = exp(delta_E_altruistic / Value_Params.Temperature);
                    if rand < prob
                        accept = true;
                        if AddPara.verbose
                            fprintf('      [Agent %d] 概率接受劣解 (全局ΔE=%.2f, prob=%.4f)\n', ii, delta_E_altruistic, prob);
                        end
                    else
                        accept = false;
                    end
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

                % 5.3 更新 GSU 最优记录（用于禁忌愿望准则）
                if current_GSU > best_GSU
                    best_GSU = current_GSU;
                    if AddPara.verbose
                        fprintf('      [Agent %d] 新的 GSU 最优 = %.2f\n', ii, best_GSU);
                    end
                end
            end
        end  % end for ii

        % 模拟退火降温：Temperature = alpha * Temperature
        Value_Params.Temperature = Value_Params.alpha * Value_Params.Temperature;

        % 广播机制已保证所有 agent 的 SC 同步，取任意 agent 的 SC 均等价，此处取 agent N
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

        % 记录内循环（退火过程中的每一步）历史信息
        inner_loop_history = ResultProcessor.record_inner_loop_iteration(...
            inner_loop_history, k_iter, ...
            Value_Params.Temperature, current_utility_global, current_utility_global, final_SC, Value_Params);

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
            fprintf('  [SA-Outer] Iter %d: T=%.2f, Utility=%.2f, BestGSU=%.2f\n', ...
                k_iter, Value_Params.Temperature, current_utility_global, best_GSU);
        end
        k_iter = k_iter + 1;
    end  % end while

    % [温度校准] 第1轮结束时输出 |ΔE| 统计，帮助校准 T0_round
    if counter == 1 && ~isempty(delta_E_log)
        dE_mean = mean(delta_E_log);
        dE_med  = median(delta_E_log);
        dE_p90  = prctile(delta_E_log, 90);
        fprintf('  [T校准] |ΔE| 统计（劣解，共%d次）: 均值=%.1f  中位=%.1f  90%%分位=%.1f\n', ...
            numel(delta_E_log), dE_mean, dE_med, dE_p90);
        fprintf('         建议 T0: 均值接受率30%% → T0=%.0f;  50%% → T0=%.0f\n', ...
            dE_mean/log(1/0.3), dE_mean/log(2));
        fprintf('         当前 T0=%.0f，初始接受率≈%.1f%%\n', ...
            Value_Params.T0_round, 100*exp(-dE_mean/Value_Params.T0_round));
    end

    % 更新任务执行状态，并计算当前执行时序（Schedule）
    Value_data = update_task_schedule(Value_data, agents, tasks, Value_Params);

    %% ==================== 4. 观测与信念更新 ====================
    [Value_data, summatrix] = AgentOps.collect_observations(Value_data, agents, tasks, Value_Params, summatrix, final_SC);
    Value_data = AgentOps.update_belief_from_observations(Value_data, Value_Params);

    %% ==================== 5. 计算联盟效用（上帝视角） ====================
    [coalition_utility, total_global_cost, total_completed_value, task_completion_degrees] = ...
        UtilityEvaluator.evaluate_coalition_metrics(final_SC, agents, tasks, Value_Params, eps_val);

    %% 信念广播
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

% 生成联盟结构的哈希值（与 Qi2023 保持一致，使用 mat2str 固定顺序展开，无需排序）
function hash_str = get_SC_hash(SC, Value_Params)
temp_vec = [];
for m = 1:Value_Params.M
    temp_vec = [temp_vec; SC{m}(:)];
end
hash_str = mat2str(temp_vec);
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
% 同时返回 GSU_candidate 和 GSU_current，供调用方复用，避免重复计算 GSU(SC_candidate)
function [delta_E, GSU_candidate, GSU_current] = global_utility_diff(tasks, agents, SC_current, SC_candidate, agent_idx, Value_Params, Value_data_i) %#ok<INUSL>
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