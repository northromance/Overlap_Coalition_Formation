function [Value_data, history_data] = SA_Value_TabuEnhanced_global_main(agents, tasks, AddPara, Value_Params)
% SA_VALUE_TABUENHANCED_GLOBAL_MAIN 基于全局社会效用的模拟退火-禁忌搜索算法
%
% === [核心设计理念 - 全局社会效用（GSU）版本] ===
% 本版本采用完全利他主义决策机制，核心创新为"全局社会效用"：
%
%   1. Metropolis准则：基于 Preference_gain 计算的全局效用差值
%      - delta_E = SC_candidate 下全体智能体效用之和 - SC_current 下全体智能体效用之和
%      - 用于接受/拒绝候选解的日常决策（模拟退火的核心概率接受机制）
%
%   2. 特赦准则（Aspiration Criterion）：基于全局社会效用（Global Social Utility, GSU）
%      - GSU定义：所有 N 个智能体在候选解下的效用总和
%      - 每个智能体维护自己观测到的历史最佳GSU：best_LSU(i)（账本含义升级为全局最优）
%      - 特赦条件：current_GSU > best_LSU(i)
%      - 理论含义：即使当前动作被禁忌表封锁，只要它能将全体智能体的社会总福利推向历史新高，就无视禁忌，强制允许执行。
% ==============================================

%% ==================== 0. 随机数种子设置 ====================
% 为了保证科学实验的可复现性（Reproducibility），固定随机数种子
if isfield(Value_Params, 'seed')
    rng(Value_Params.seed);
end

%% ==================== 1. 初始化阶段 ====================
eps_val = 1e-6;          % 浮点数比较容差
history_data = struct();
tabu_tenure = Value_Params.SA_Tabu_tenure; % 禁忌期限

Value_data = WorldSim.init_value_data(agents, tasks, Value_Params);
[Value_data, summatrix] = WorldSim.init_observe_belief_neighbor(Value_data, Value_Params.N, Value_Params.M, Value_Params);

%% ==================== 2. 主循环：多轮博弈迭代 ====================
for counter = 1:Value_Params.num_rounds
    %% 2.2 SA 初始化
    k_iter = 1;                     % 迭代计数器
    previous_SC = Value_data(1).SC; % 收敛检测基准
    k_stable = 0;
    doneflag = 0;

    % 轮间温度调度：初始温度随轮数指数衰减
    Value_Params.Temperature = max(Value_Params.SA_T_base_round, ...
        Value_Params.SA_T0_round * Value_Params.SA_beta_round^(counter-1));
    if AddPara.verbose
        fprintf('  [SA-Altruistic] Round %d: 初始温度 = %.2f\n', counter, Value_Params.Temperature);
    end

    % --- 初始化 GSU 最优账本 ---
    % GSU 是全局标量（所有智能体效用之和），只需计算一次，由全体智能体共享
    best_SC = Value_data(1).SC;

    % 构造空SC作为GSU基准（无任务分配状态）
    SC_empty = cell(Value_Params.M, 1);
    for m = 1:Value_Params.M
        SC_empty{m} = zeros(Value_Params.N, Value_Params.K);
    end
    % 仅计算一次：GSU与调用者agent_idx无关，结果对全体智能体相同
    best_GSU = calculate_local_social_utility(SC_empty, best_SC, 1, agents, tasks, Value_Params, Value_data(1), AddPara);

    %% ==================== 2.25 初始化禁忌列表 ====================
    % 禁忌表用于防止退火搜索在两个相近状态之间反复横跳（局部死循环）
    tabu_list = {};
    if AddPara.verbose
        fprintf('  [Tabu] 禁忌期限 = %d\n', tabu_tenure);
    end

    %% ==================== 2.3 第一轮特有：生成初始解 (Soft Greedy) ====================
    % 在第1轮，为了加快收敛，不使用纯随机分配，而是用“软贪心”策略给出一个质量较好的初始解
    if counter == 1
        if AddPara.verbose
            fprintf('  [SA] 第1轮：基于低温概率生成初始联盟结构 (Soft Greedy)...\n');
        end
        SC_global = Value_data(1).SC;
        task_type_demands = Value_Params.task_type_demands;
        resource_confidence = Value_Params.SA_resource_confidence; % 资源需求的置信度（抵御不确定性）
        T_init_construction = Value_Params.SA_T_init_construction;

        % 轮询每个智能体，根据当前需求缺口(gap)进行初步的资源投放
        for i = 1:Value_Params.N
            Value_data(i).SC = SC_global;
            % 根据分位数计算当前资源需求
            [~, resource_gap] = calc_gaps(Value_data(i), Value_Params, AddPara);

            % 基于轮盘赌（概率由softmax生成）选择任务，偏向于缺口大的任务
            probs = SA_Select_probs(Value_data(i), agents, tasks, Value_Params, resource_gap, T_init_construction);

            for k = 1:Value_Params.K % 遍历每种类型
                resource_amt = agents(i).resources(k);
                if resource_amt <= 0, continue; end % 如果没有第k种资源，跳过

                % 轮盘赌选择（封装在 OCFUtils.sample_task_from_probs 中）
                selected_task = OCFUtils.sample_task_from_probs(probs(k, :), Value_Params.M);
                if isempty(selected_task), continue; end

                % 如果已在此任务中投入了该资源，跳过
                if SC_global{selected_task}(i, k) > 0, continue; end

                % 计算期望需求量，判断是否还能塞得下资源
                curr_alloc = sum(SC_global{selected_task}(:, k));
                belief = Value_data(i).initbelief(selected_task, :);
                expected_demand = WorldSim.calculate_demand_quantile(belief, task_type_demands, resource_confidence);
                can_add = max(0, expected_demand(k) - curr_alloc);

                % 如果该任务还需要资源，尝试投入
                if can_add > 0
                    SC_candidate = SC_global;
                    SC_candidate{selected_task}(i, k) = resource_amt;

                    % 验证该动作是否满足系统硬约束（例如不可超越最大容量等）
                    Value_data_temp = Value_data;
                    for j=1:Value_Params.N, Value_data_temp(j).SC = SC_candidate; end
                    [isFeasible, ~, ~] = validate_feasibility(Value_data_temp, agents, tasks, ...
                        Value_Params, i, SC_candidate, true, AddPara);
                    if isFeasible
                        SC_global = SC_candidate; % 如果合法，真正采纳该解
                    end
                end
            end
            % 同步当前全局状态给所有Agent
            for j = 1:Value_Params.N, Value_data(j).SC = SC_global; end
        end

        % 软贪心分配结束后，构建最终的内部数据结构（矩阵、联盟归属等）
        for i = 1:Value_Params.N
            Value_data(i).SC = SC_global;
            Value_data(i).resources_matrix = OCFUtils.get_agent_resource_matrix(SC_global, i, Value_Params);
            Value_data(i).coalitionstru = OCFUtils.build_coalitionstru_from_SC(SC_global, Value_Params, agents);
        end

        % 根据生成的初始解重新计算全局GSU，仅算一次并广播给全体智能体
        best_SC = SC_global;
        best_GSU = calculate_local_social_utility(SC_empty, SC_global, 1, agents, tasks, Value_Params, Value_data(1), AddPara);
    end

    %% ==================== 3. SA 外循环 (核心博弈过程 - 利他主义版本) ====================
    inner_loop_history = ResultProcessor.init_inner_loop_history();

    % 记录当前状态的全局效用（上帝视角，仅供绘图/评估）
    current_utility_global = 0;
    for j = 1:Value_Params.N
        current_utility_global = current_utility_global + UtilityEvaluator.calc_agent_total_utility(Value_data(j).SC, agents, tasks, Value_Params, Value_data(j), AddPara);
    end

    % ? [新增/修改点 1: 每轮物理执行前，初始化“上帝照相机”，起步就是目前的最佳] ?
    elite_global_utility = current_utility_global;
    elite_SC = Value_data(1).SC;
    elite_coalitionstru = Value_data(1).coalitionstru;

    while(doneflag == 0)
        % --- 3.1 顺序博弈：N个Agent依次决策 ---
        for ii = 1:Value_Params.N
            % 步骤1: 智能体 ii 根据自身局部信息生成一个变异候选解（撤出某些任务，加入新任务）
            [SC_candidate, ~] = generate_candidate_solution_tabu(Value_data(ii), agents, tasks, Value_Params, AddPara);

            % 步骤3: 禁忌判断 (Tabu Check)
            candidate_hash = get_SC_hash(SC_candidate, Value_Params); % 对分配矩阵进行哈希，生成唯一指纹
            is_tabu = is_in_tabu_list(candidate_hash, tabu_list);     % 判断新解是否在禁忌表中

            % GSU 是全局标量，与 agent_idx 无关，提前计算一次，两条分支（禁忌/非禁忌）均可复用
            SC_current = Value_data(ii).SC;
            current_GSU = calculate_local_social_utility(SC_current, SC_candidate, 1, agents, tasks, Value_Params, Value_data(ii), AddPara);

            accept = false;

            if is_tabu
                % === [GSU 特赦准则：当前候选解的全局效用超过历史最优时，无视禁忌强制接受] ===
                if current_GSU > best_GSU
                    accept = true;
                    if AddPara.verbose
                        fprintf('      [Agent %d] GSU特赦接受禁忌解 (GSU=%.2f > 最优=%.2f)\n', ...
                            ii, current_GSU, best_GSU);
                    end
                else
                    if AddPara.verbose
                        fprintf('      [Agent %d] 拒绝禁忌解 (GSU=%.2f)\n', ii, current_GSU);
                    end
                end
            else
                % === [全局效用 Metropolis 准则] ===
                % 如果不在禁忌表中，进入标准的模拟退火判定流

                % 计算全局效用差值（Delta Energy）
                delta_E_altruistic = global_utility_diff(tasks, agents, SC_current, SC_candidate, ii, Value_Params, Value_data(ii));
                % 取消频繁打印 delta E，保持日志干净
                % fprintf('  [ΔE] Round=%d Iter=%d Agent=%d  delta_E=%.4f  T=%.4f\n', counter, k_iter, ii, delta_E_altruistic, Value_Params.Temperature);

                % === [利他主义 Metropolis 准则结束] ===
                if delta_E_altruistic > 1e-4
                    % 如果是“好解”（利他偏好提升或不变），无条件接受
                    accept = true;
                elseif delta_E_altruistic < 0
                    % 如果是"劣解"（dE<0），按照玻尔兹曼概率接受 (概率随温降减小)
                    % dE=0 不进入此分支，避免 exp(0/T)=1 导致中性解被无条件接受
                    % 这给予了系统跳出局部最优（Local Optima）的能力
                    prob = exp(delta_E_altruistic / Value_Params.Temperature);
                    if rand < prob
                        accept = true;
                        if AddPara.verbose
                            fprintf('      [Agent %d] 概率接受恶化解 (利他ΔE=%.2f, prob=%.4f)\n', ii, delta_E_altruistic, prob);
                        end
                    else
                        accept = false;
                    end
                end
            end

            % 步骤5: 执行解的更新
            if accept
                % 5.1 广播 SC + coalitionstru 给全体智能体（共享黑板）
                % coalitionstru 仅构建一次，避免 N 次重复计算相同结果
                new_coalitionstru = OCFUtils.build_coalitionstru_from_SC(SC_candidate, Value_Params, agents);
                for jj = 1:Value_Params.N
                    Value_data(jj).SC            = SC_candidate;
                    Value_data(jj).coalitionstru = new_coalitionstru;
                end
                % 仅更新当前智能体 ii 的 resources_matrix
                % 其余智能体的 resources_matrix 在本迭代末的全局同步步骤中统一更新
                Value_data(ii).resources_matrix = OCFUtils.get_agent_resource_matrix(SC_candidate, ii, Value_Params);

                % 5.2 将新接受的状态加入禁忌表
                if ~is_tabu
                    tabu_list = update_tabu_list(tabu_list, candidate_hash, tabu_tenure);
                end

                % 5.3 检查并更新全局GSU最优账本
                % current_GSU 已在步骤3提前计算，直接复用，无需重复调用
                if current_GSU > best_GSU
                    best_GSU = current_GSU;
                    if AddPara.verbose
                        fprintf('      [Agent %d 触发] 更新全局GSU最优 (GSU=%.2f)\n', ii, best_GSU);
                    end
                end
                % 注：coalitionstru 已在 5.1 广播给全体，无需在此重复传递
            end
        end  % end for ii (本轮所有智能体决策完毕)

        % 核心动作：退火降温。Temperature = alpha * Temperature
        Value_Params.Temperature = Value_Params.alpha * Value_Params.Temperature;

        % 提取最终的联盟矩阵结构
        final_SC = Value_data(Value_Params.N).SC;
        final_coalitionstru = Value_data(Value_Params.N).coalitionstru;

        % ? [新增/修改点 2: 提前全网状态同步，然后准确计算这一步的全局效用，并拍照！] ?
        for ii = 1:Value_Params.N
            Value_data(ii).coalitionstru = final_coalitionstru;
            Value_data(ii).SC = final_SC;
            Value_data(ii).resources_matrix = OCFUtils.get_agent_resource_matrix(final_SC, ii, Value_Params);
        end

        current_utility_global = 0;
        for j = 1:Value_Params.N
            current_utility_global = current_utility_global + UtilityEvaluator.calc_agent_total_utility(final_SC, agents, tasks, Value_Params, Value_data(j), AddPara);
        end

        % 【上帝照相机按下快门】：如果当前的波动画出了新高，立刻缓存
        if current_utility_global > elite_global_utility
            elite_global_utility = current_utility_global;
            elite_SC = final_SC;
            elite_coalitionstru = final_coalitionstru;
            if AddPara.verbose
                fprintf('    [Elite] 咔嚓！发现本轮计算内部历史最高全局效用: %.2f (Iter: %d)\n', elite_global_utility, k_iter);
            end
        end

        % 记录内部迭代(降温过程中的一步)的历史数据 (修复了旧版记录不更新的问题)
        inner_loop_history = ResultProcessor.record_inner_loop_iteration(...
            inner_loop_history, k_iter, ...
            Value_Params.Temperature, current_utility_global, elite_global_utility, final_SC, Value_Params);

        % 收敛检测
        if isequal(previous_SC, final_SC)
            k_stable = k_stable + 1;
        else
            k_stable = 0;
        end

        % 退出条件：连续收敛 / 温度过低 / 达到最大迭代次数
        if k_stable >= Value_Params.SA_K_len
            doneflag = 1;
        elseif Value_Params.Temperature < Value_Params.Tmin
            doneflag = 1;
        elseif k_iter >= Value_Params.Tabu_MaxIter
            doneflag = 1;
        end

        % 滚动更新旧状态
        previous_SC = final_SC;
        
        if AddPara.verbose
            fprintf('  [SA-Outer] Iter %d: T=%.2f, Utility=%.2f, Best=%.2f\n', ...
                k_iter, Value_Params.Temperature, current_utility_global, elite_global_utility);
        end
        k_iter = k_iter + 1;
    end  % end while (SA退火内循环结束)

    % ? [新增/修改点 3: 强制丢弃结尾波动的劣解，回滚至本轮脑内推演发现的最高分方案作为物理落地的起点] ?
    if AddPara.verbose
        fprintf('  [SA-Done] Round %d 脑内推演结束，强行采纳并执行最优方案 (Utility: %.2f)\n', counter, elite_global_utility);
    end
    final_SC = elite_SC;
    final_coalitionstru = elite_coalitionstru;
    for ii = 1:Value_Params.N
        Value_data(ii).coalitionstru = final_coalitionstru;
        Value_data(ii).SC = final_SC;
        Value_data(ii).resources_matrix = OCFUtils.get_agent_resource_matrix(final_SC, ii, Value_Params);
    end
    % =========================================================================

    % 本轮任务分配结果已定，重新计算并缓存具体执行的时间表 (Schedule)
    Value_data = update_task_schedule(Value_data, agents, tasks, Value_Params);

    %% ==================== 4. 观测与信念更新 ====================
    % 基于精英方案（final_SC）进行物理模拟和观测
    [Value_data, summatrix] = AgentOps.collect_observations(Value_data, agents, tasks, Value_Params, summatrix, final_SC);
    Value_data = AgentOps.update_belief_from_observations(Value_data, Value_Params);

    %% ==================== 5. 结果评估（客观/上帝视角） ====================
    [coalition_utility, total_global_cost, total_completed_value, task_completion_degrees] = ...
        UtilityEvaluator.evaluate_coalition_metrics(final_SC, agents, tasks, Value_Params, eps_val);

    %% 4.8 信念广播
    for i = 1:Value_Params.N
        for j = 1:Value_Params.N
            Value_data(i).other{j}.initbelief = Value_data(j).initbelief;
        end
    end

    % --- 记录本轮的所有关键历史数据，用于后续画图或复盘 ---
    history_data = ResultProcessor.record_history_data(history_data, counter, Value_data, Value_Params, ...
        final_SC, final_coalitionstru, ...
        coalition_utility, total_global_cost, ...
        total_completed_value, task_completion_degrees, ...
        summatrix);
    history_data.inner_loop{counter} = inner_loop_history;

    % 记录本轮的内循环迭代次数
    history_data.k_iter_per_round{counter} = k_iter;

    % 单独记录全局社会效用（GSU）的演化数据
    history_data.best_GSU{counter} = best_GSU;
end

%% ==================== 6. 结束与最终检查 ====================
if AddPara.verbose
    fprintf('\n[SA_Value_Altruistic] 执行最终一致性检查...\n');
end
% OCF一致性检查，确保最终给出的分配解没有违反物理定律（如资源超售、无中生有等）
[is_valid, error_log] = check_coalition_consistency(Value_data, agents, tasks, Value_Params, 'OCF', AddPara.verbose);
if ~is_valid
    warning('[SA_Value_Altruistic] 一致性检查发现 %d 处问题', length(error_log));
    history_data.consistency_errors = error_log;
else
    if AddPara.verbose
        fprintf('  [SA_Value_Altruistic] 所有一致性检查通过！\n');
    end
end
end

%% ==================== 内部辅助函数 ====================

% 【计算分配结构的哈希值】将当前的矩阵转化成唯一字符串，用于禁忌表比对
function hash_str = get_SC_hash(SC, Value_Params)
hash_parts = {};
eps_val = 1e-9;
for m = 1:Value_Params.M
    SC_m = SC{m};
    % 仅记录矩阵中非0的元素（即有实际资源分配的动作）
    [rows, cols] = find(SC_m > eps_val);
    for idx = 1:length(rows)
        i = rows(idx); % Agent i
        k = cols(idx); % Resource k
        amount = SC_m(i, k);
        hash_parts{end+1} = sprintf('%d-%d-%d-%.4f', m, i, k, amount);
    end
end
hash_parts = sort(hash_parts); % 必须排序以保证相同的分配总是生成相同的哈希
if isempty(hash_parts)
    hash_str = 'EMPTY';
else
    hash_str = strjoin_custom(hash_parts, '|');
end
end

% 【禁忌列表检查】
function is_tabu = is_in_tabu_list(hash_str, tabu_list)
is_tabu = ~isempty(tabu_list) && any(strcmp(tabu_list, hash_str));
end

% 【禁忌列表更新】先进先出队列(FIFO)
function tabu_list = update_tabu_list(tabu_list, hash_str, tabu_tenure)
tabu_list{end+1} = hash_str;
% 如果超出期限，踢出最早加入黑名单的解
if length(tabu_list) > tabu_tenure
    tabu_list = tabu_list(2:end);
end
end

% 【字符串拼接自定义函数】替代较高版本MATLAB的strjoin或防止兼容性问题
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

confidence = 0.9;
if isfield(AddPara, 'resource_confidence'), confidence = AddPara.resource_confidence; end

    p_leave = Value_Params.SA_p_leave;  % 离开概率（统一由 Value_Params.SA_p_leave 控制）

% --- 步骤 A：随机撤出部分任务资源 ---
SC_temp = Value_data_i.SC;
for m = 1:M
    for k = 1:K
        if SC_temp{m}(agent_idx, k) > eps_val && rand < p_leave
            if AddPara.verbose
                fprintf('      [-] [撤出] Agent #%-2d 从 任务 M=%-2d 撤出 资源 k=%-2d | 数量: %.2f\n', ...
                    agent_idx, m, k, SC_temp{m}(agent_idx, k));
            end
            SC_temp{m}(agent_idx, k) = 0;
        end
    end
end

% 更新数据准备新一轮分配
Value_data_i.SC = SC_temp;
% 计算当前的系统任务供需缺口(Gaps)
[~, resource_gap] = calc_gaps(Value_data_i, Value_Params, AddPara);
% 使用softmax或其他选择策略，计算各个任务被选中的概率
probs = SA_Select_probs(Value_data_i, agents, tasks, Value_Params, resource_gap, current_T);
SC_new = SC_temp;
task_type_demands = Value_Params.task_type_demands;

% --- 步骤 B：将空闲（或可复用）的资源重新分配 ---
for k = 1:K
    total_capacity = agents(agent_idx).resources(k);
    if total_capacity <= eps_val, continue; end
    
    % 基于轮盘赌挑选目标任务（封装在 OCFUtils.sample_task_from_probs 中）
    selected_task = OCFUtils.sample_task_from_probs(probs(k, :), M);
    if isempty(selected_task), continue; end
    % 已参与该任务则跳过
    if SC_new{selected_task}(agent_idx, k) > eps_val, continue; end

    % 检查该任务是否还需要该资源
    curr_alloc = sum(SC_new{selected_task}(:, k));
    belief = Value_data_i.initbelief(selected_task, :);
    expected_demand = WorldSim.calculate_demand_quantile(belief, task_type_demands, confidence);
    can_add = max(0, expected_demand(k) - curr_alloc);
    
    if can_add > eps_val
        SC_candidate_temp = SC_new;
        SC_candidate_temp{selected_task}(agent_idx, k) = total_capacity; % 全量投入
        
        % 包装成全量数组
        Value_data_array = repmat(Value_data_i, Value_Params.N, 1);
        for j = 1:Value_Params.N
            Value_data_array(j).agentIndex = j;
            Value_data_array(j).SC = SC_candidate_temp;
        end
        
        % 调用可行性检测
        [isFeasible, info, ~] = validate_feasibility(Value_data_array, agents, tasks, ...
            Value_Params, agent_idx, SC_candidate_temp, true, AddPara);
            
        if isFeasible
            SC_new = SC_candidate_temp;
            if AddPara.verbose
                fprintf('      [+] [复用] Agent #%-2d 向 任务 M=%-2d 投入 资源 k=%-2d | 数量: %.2f\n', ...
                    agent_idx, selected_task, k, total_capacity);
            end
        else
            if AddPara.verbose
                fprintf('      [x] [拒绝] Agent #%-2d 尝试向 任务 M=%-2d 投入 资源 k=%-2d 失败 | 原因: %s\n', ...
                    agent_idx, selected_task, k, info.reason);
            end
        end
    end
end

SC_candidate = SC_new;
move_description = sprintf('SA_Tabu_Altruistic_Agent_%d', agent_idx);
end

% 【计算全局社会效用 (Global Social Utility, GSU)】
% GSU = 所有 N 个智能体在 SC_candidate 下的效用之和
% SC_old 参数保留以兼容原有调用接口，但本版本不再使用（改为全局求和）
function GSU = calculate_local_social_utility(SC_old, SC_candidate, agent_idx, agents, tasks, Value_Params, Value_data, AddPara) %#ok<INUSL>
    % 遍历全部 N 个智能体，累加各自在 SC_candidate 下的效用 —— 即全局社会效用
    GSU = 0;
    for j = 1:Value_Params.N
        % 尽量使用智能体 j 自身的信念（从 agent_idx 的 other 字段获取）
        % 若无记录，则退用 agent_idx 的信念作为同质化近似
        if j == agent_idx
            agent_belief = Value_data.initbelief;
        elseif length(Value_data.other) >= j && ~isempty(Value_data.other{j})
            agent_belief = Value_data.other{j}.initbelief;
        else
            agent_belief = Value_data.initbelief; % 同质化近似
        end

        temp_data.agentIndex = j;
        temp_data.initbelief = agent_belief;
        temp_data.SC = SC_candidate;
        GSU = GSU + UtilityEvaluator.calc_agent_total_utility(SC_candidate, agents, tasks, Value_Params, temp_data, AddPara);
    end
end

% 【计算新旧联盟之间的全局效用差值 (Preference Gain)】
% delta_E = GSU(SC_candidate) - GSU(SC_current)
% 即：候选联盟结构下所有智能体的效用总和 减去 当前联盟结构下所有智能体的效用总和
% 参数说明：
%   tasks          - 任务描述（保留以兼容调用接口）
%   agents         - 智能体描述
%   SC_current     - 当前联盟结构（cell数组）
%   SC_candidate   - 候选联盟结构（cell数组）
%   agent_idx      - 发起动作的智能体编号（用于获取信念来源）
%   Value_Params   - 全局参数
%   Value_data_i   - agent_idx 的本地数据（含 initbelief 和 other 字段）
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