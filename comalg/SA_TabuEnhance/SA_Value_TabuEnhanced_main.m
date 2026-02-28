function [Value_data, history_data] = SA_Value_TabuEnhanced_main(agents, tasks, AddPara, Value_Params)

% SA_VALUE_TABUENHANCED_MAIN 基于模拟退火和禁忌搜索的重叠联盟形成算法主函数
% 这个是结合了模拟退火（SA）和禁忌搜索（Tabu Search）的增强版本，旨在提升联盟形成过程中的全局搜索能力和跳出局部最优的能力。
% 按照Osman框架写的 
% 采用的是全局效用来计算差值（delta_E），并且在禁忌判断中引入了特赦准则（Aspiration Criterion），允许在特定条件下接受禁忌解。
%% ==================== 0. 随机数种子设置 ====================
if isfield(Value_Params, 'seed')
    rng(Value_Params.seed); % 固定种子以复现实验结果
end

%% ==================== 1. 初始化阶段 ====================
eps_val = 1e-6;          % 浮点数比较容差
history_data = struct(); % 初始化历史记录容器
tabu_tenure = Value_Params.tabu_tenure;   % 禁忌期限（根据智能体数量自适应）

% --- 初始化智能体核心数据结构 (Value_data) ---
% 包含 SC (联盟结构矩阵), resources (资源状态), position (位置) 等
Value_data = WorldSim.init_value_data(agents, tasks, Value_Params);

% --- 初始化观测、信念与邻居信息 ---
% summatrix 用于记录观测次数，initbelief 初始化为先验分布
[Value_data, summatrix] = WorldSim.init_observe_belief_neighbor(Value_data, Value_Params.N, Value_Params.M, Value_Params);

%% ==================== 2. 主循环：多轮博弈迭代 ====================


for counter = 1:Value_Params.num_rounds

    %% 2.2 SA 初始化 (本轮博弈前的准备)
    k_iter = 1;                         % 内循环迭代计数器
    previous_SC = Value_data(1).SC;     % 用于检测状态是否变化的基准
    k_stable = 0;                       % 稳定计数器 (连续多少次状态未变)
    doneflag = 0;                       % 内循环结束标志

    % --- 温度调度策略 ---
    % 采用指数衰减策略，随着轮数 (counter) 增加，初始温度 T 逐轮降低
    % 意味着后期的博弈探索性降低，更倾向于利用 (Exploitation)
    Value_Params.Temperature = max(Value_Params.SA_T_base_round, Value_Params.SA_T0_round * Value_Params.SA_beta_round^(counter-1));
    % Value_Params.Temperature = 200;

    if AddPara.verbose
        fprintf('  [SA] Round %d: 初始温度 = %.2f\n', counter, Value_Params.Temperature);
    end

    % 初始化本轮“主观最优”记录变量
    best_SC = Value_data(1).SC;
    % ⭐⭐⭐ [关键修复开始] ⭐⭐⭐
    % 在每一轮开始时，必须基于“当前的信念”重新计算继承下来的 SC 的效用。
    % 否则 Round 2 的新效用会和 Round 1 的旧效用（基于旧信念）进行错误比较。
    best_utility = 0;
    for j = 1:Value_Params.N
        best_utility = best_utility + UtilityEvaluator.calc_agent_total_utility(best_SC, agents, tasks, Value_Params, Value_data(j), AddPara);
    end

    %% ==================== 2.25 初始化禁忌列表 ====================
    % 禁忌列表用于存储最近访问过的联盟结构，防止算法陷入循环
    tabu_list = {};                          % 禁忌列表（存储SC的哈希值）

    if AddPara.verbose
        fprintf('  [Tabu] 禁忌期限 = %d\n', tabu_tenure);
    end

    %% ==================== 2.3 第一轮特有：生成初始解 (Soft Greedy) ====================
    % 在第1轮，为了避免从完全随机开始，使用启发式规则快速构建一个可行的初始解
    if counter == 1
        if AddPara.verbose
            fprintf('  [SA] 第1轮：基于低温概率与规则生成的初始联盟结构 (Soft Greedy)...\n');
        end

        SC_global = Value_data(1).SC;
        task_type_demands = Value_Params.task_type_demands;
        resource_confidence = Value_Params.SA_resource_confidence; % 初始置信度
        T_init_construction = Value_Params.SA_T_init_construction; % 构造阶段使用极低温度，接近贪婪选择

        for i = 1:Value_Params.N
            Value_data(i).SC = SC_global;

            % 计算当前资源缺口 (Gap)
            [~, resource_gap] = calc_gaps(Value_data(i), Value_Params, AddPara);

            % 基于缺口计算选择概率 (Probabilities)
            probs = SA_Select_probs(Value_data(i), agents, tasks, Value_Params, resource_gap, T_init_construction);

            for k = 1:Value_Params.K
                resource_amt = agents(i).resources(k);
                if resource_amt <= 0, continue; end % 无资源则跳过

                % 轮盘赌采样目标任务
                prob_vec = probs(k, :);
                cum_prob = cumsum(prob_vec);
                if cum_prob(end) > 1e-9
                    r = rand * cum_prob(end);
                    selected_task = find(cum_prob >= r, 1, 'first');
                else
                    selected_task = randi(Value_Params.M);
                end

                % --- 查重检测 ---
                % 如果该资源已经在该任务中，则跳过 (防止重复叠加)
                if SC_global{selected_task}(i, k) > 0, continue; end

                % --- 需求估算 ---
                curr_alloc = sum(SC_global{selected_task}(:, k));
                belief = Value_data(i).initbelief(selected_task, :);
                expected_demand = WorldSim.calculate_demand_quantile(belief, task_type_demands, resource_confidence);

                % 仅当预期还有缺口时才尝试加入
                can_add = max(0, expected_demand(k) - curr_alloc);

                if can_add > 0
                    % 构造候选 SC
                    SC_candidate = SC_global;
                    SC_candidate{selected_task}(i, k) = resource_amt;

                    % 临时同步数据以进行可行性检测
                    Value_data_temp = Value_data;
                    for j=1:Value_Params.N, Value_data_temp(j).SC = SC_candidate; end

                    % 可行性检测 (能量、路径、载重)
                    [isFeasible, ~, ~] = validate_feasibility(Value_data_temp, agents, tasks, ...
                        Value_Params, i, SC_candidate, true, AddPara);

                    if isFeasible
                        SC_global = SC_candidate; % 接受变更
                    end
                end
            end
            % 每一位智能体操作完，暂存状态
            for j = 1:Value_Params.N, Value_data(j).SC = SC_global; end
        end

        % --- 初始化结束后的全网同步 ---
        for i = 1:Value_Params.N
            Value_data(i).SC = SC_global;
            Value_data(i).resources_matrix = OCFUtils.get_agent_resource_matrix(SC_global, i, Value_Params);
            Value_data(i).coalitionstru = OCFUtils.build_coalitionstru_from_SC(SC_global, Value_Params, agents);
        end

        best_SC = SC_global;

        for ii = 1:Value_Params.N
            u_i = UtilityEvaluator.calc_agent_total_utility(SC_global, agents, tasks, Value_Params, Value_data(ii), AddPara);
            best_utility = best_utility + u_i;
        end

        if AddPara.verbose
            fprintf('  [SA] 第1轮：初始主观效用 = %.2f\n', best_utility);
        end
    end

    %% ==================== 3. SA 外循环 (核心博弈过程 - Osman框架) ====================
    % 初始化内循环历史记录
    inner_loop_history = ResultProcessor.init_inner_loop_history();

    % 初始化当前状态的效用
    current_utility = 0;
    for j = 1:Value_Params.N
        current_utility = current_utility + UtilityEvaluator.calc_agent_total_utility(Value_data(j).SC, agents, tasks, Value_Params, Value_data(j), AddPara);
    end

    while(doneflag == 0)

        % --- 3.1 顺序博弈 (Sequential Game) ---
        % 智能体按照 1 到 N 的顺序依次决策，每个智能体生成一个候选解

        for ii = 1:Value_Params.N

            % 步骤1: 生成候选解
            % 调用候选解生成函数（暂时用原函数替代）
            [SC_candidate, ~] = generate_candidate_solution_tabu(Value_data(ii), agents, tasks, Value_Params, AddPara);

            % 步骤2: 计算候选解的效用
            candidate_utility = 0;
            Value_data_temp = Value_data;
            for jj = 1:Value_Params.N
                Value_data_temp(jj).SC = SC_candidate;
                candidate_utility = candidate_utility + UtilityEvaluator.calc_agent_total_utility(SC_candidate, agents, tasks, Value_Params, Value_data_temp(jj), AddPara);
            end

            % 步骤3: 禁忌判断
            candidate_hash = get_SC_hash(SC_candidate, Value_Params);
            is_tabu = is_in_tabu_list(candidate_hash, tabu_list);

            accept = false;

            if is_tabu
                % 特赦准则 (Aspiration Criterion)
                if candidate_utility > best_utility
                    accept = true;
                    if AddPara.verbose
                        fprintf('      [Agent %d] 特赦接受禁忌解 (效用=%.2f > 最优=%.2f)\n', ii, candidate_utility, best_utility);
                    end
                elseif AddPara.verbose
                    fprintf('      [Agent %d] 拒绝禁忌解 (效用=%.2f)\n', ii, candidate_utility);
                end
            else
                % Metropolis准则 (SA判断)
                delta_E = candidate_utility - current_utility;
                fprintf('  ΔE=%.2f, T=%.2f, P=%.4f\n', delta_E, Value_Params.Temperature, exp(delta_E/Value_Params.Temperature));
                if delta_E >= 0
                    accept = true;
                else
                    prob = exp(delta_E / Value_Params.Temperature);
                    if rand < prob
                        accept = true;
                        if AddPara.verbose
                            fprintf('      [Agent %d] 概率接受恶化解 (ΔE=%.2f, prob=%.4f)\n', ii, delta_E, prob);
                        end
                    end
                end
            end

            % 步骤5: 执行更新
            if accept
                % 更新当前解
                for jj = 1:Value_Params.N
                    Value_data(jj).SC = SC_candidate;
                    Value_data(jj).coalitionstru = OCFUtils.build_coalitionstru_from_SC(SC_candidate, Value_Params, agents);
                    Value_data(jj).resources_matrix = OCFUtils.get_agent_resource_matrix(SC_candidate, jj, Value_Params);
                end
                current_utility = candidate_utility;

                % 更新禁忌列表（添加当前移动）
                if ~is_tabu
                    tabu_list = update_tabu_list(tabu_list, candidate_hash, tabu_tenure);
                end

                % 更新历史最优解
                if current_utility > best_utility
                    best_utility = current_utility;
                    best_SC = SC_candidate;
                    if AddPara.verbose
                        fprintf('      [Agent %d] 更新最优解 (效用=%.2f)\n', ii, best_utility);
                    end
                end

                % 传递给下一个智能体
                if ii < Value_Params.N
                    Value_data(ii + 1).SC = SC_candidate;
                    Value_data(ii + 1).coalitionstru = Value_data(ii).coalitionstru;
                end
            end

        end  % end for ii (智能体循环)

        % 记录本次迭代的历史数据
        inner_loop_history = ResultProcessor.record_inner_loop_iteration(...
            inner_loop_history, k_iter, ...
            Value_Params.Temperature, current_utility, best_utility, Value_data(1).SC, Value_Params);

        % --- 3.2 完成迭代后的操作 ---

        % 3.2.1 降温 (Cooling) - 每次外循环后降温
        Value_Params.Temperature = Value_Params.alpha * Value_Params.Temperature;

        % 获取本轮结束后的最终状态
        final_SC = Value_data(Value_Params.N).SC;
        final_coalitionstru = Value_data(Value_Params.N).coalitionstru;

        % --- 3.2.2 收敛检测 (Convergence Check) ---
        if isequal(previous_SC, final_SC)
            k_stable = k_stable + 1; % 状态未变，稳定计数器+1
        else
            k_stable = 0;            % 状态改变，重置计数器
        end

        % 判断是否退出外循环
        if k_stable >= Value_Params.SA_K_len        % 连续多次未变
            doneflag = 1;
        elseif Value_Params.Temperature < Value_Params.Tmin % 温度过低
            doneflag = 1;
        elseif k_iter >= Value_Params.SA_Tabu_K_max_outer  % 外循环最大迭代次数
            doneflag = 1;
            % 说明：每次外循环包含 N 个智能体的顺序博弈
            % 总操作次数 = 外循环次数 × N
            % 例如：20 × 6 = 120 次/轮，5轮共600次操作
        end

        previous_SC = final_SC;
        k_iter = k_iter + 1;

        % --- 3.2.3 全网状态同步 ---
        % 确保下一轮迭代开始前，所有智能体对 SC 达成共识
        for ii = 1:Value_Params.N
            Value_data(ii).coalitionstru = final_coalitionstru;
            Value_data(ii).SC = final_SC;
            Value_data(ii).resources_matrix = OCFUtils.get_agent_resource_matrix(Value_data(ii).SC, ii, Value_Params);
        end

        if AddPara.verbose
            fprintf('  [SA-Outer] Iter %d: T=%.2f, Utility=%.2f, Best=%.2f\n', ...
                k_iter, Value_Params.Temperature, current_utility, best_utility);
        end

    end  % end while (外循环)

    % 重新计算并缓存任务时间表 (Task Schedule) 和路径成本
    Value_data = update_task_schedule(Value_data, agents, tasks, Value_Params);

    %% ==================== 4. 观测与信念更新 ====================

    % --- 4.1 收集观测数据 ---
    % 智能体基于 final_SC 执行任务，观测任务的真实反馈
    [Value_data, summatrix] = AgentOps.collect_observations(Value_data, agents, tasks, Value_Params, summatrix, final_SC);

    % --- 4.2 贝叶斯信念更新 ---
    % 利用 Dirichlet 分布更新对任务需求的认知 (Belief)
    Value_data = AgentOps.update_belief_from_observations(Value_data, Value_Params);

    %% ==================== 5. 结果评估 (客观/上帝视角) ====================

    % 使用真实参数评估当前联盟结构的性能
    [coalition_utility, total_global_cost, total_completed_value, task_completion_degrees] = ...
        UtilityEvaluator.evaluate_coalition_metrics(final_SC, agents, tasks, Value_Params, eps_val);




    %% 4.8 信念广播
    % 模拟智能体之间的通信，交换信念参数
    for i = 1:Value_Params.N
        for j = 1:Value_Params.N
            Value_data(i).other{j}.initbelief = Value_data(j).initbelief;
        end
    end

    % --- 记录本轮历史数据 ---
    history_data = ResultProcessor.record_history_data(history_data, counter, Value_data, Value_Params, ...
        final_SC, final_coalitionstru, ...
        coalition_utility, total_global_cost, ...
        total_completed_value, task_completion_degrees, ...
        summatrix);

    % --- 记录内循环历史数据 ---
    history_data.inner_loop{counter} = inner_loop_history;

    % 记录本轮的内循环迭代次数
    history_data.k_iter_per_round{counter} = k_iter;
end

%% ==================== 6. 结束与最终检查 ====================


% --- 最终一致性检查 ---
% 验证 SC、coalitionstru 和 resources_matrix 是否逻辑互洽
if AddPara.verbose
    fprintf('\n[SA_Value] 执行最终一致性检查...\n');
end

[is_valid, error_log] = check_coalition_consistency(Value_data, agents, tasks, Value_Params, 'OCF', AddPara.verbose);

if ~is_valid
    warning('[SA_Value] 一致性检查发现 %d 处问题', length(error_log));
    history_data.consistency_errors = error_log;
else
    if AddPara.verbose
        fprintf('✅ [SA_Value] 所有一致性检查通过！\n');
    end
end

end

%% ==================== 内部辅助函数 (Internal Helper Functions) ====================

function hash_str = get_SC_hash(SC, Value_Params)
% GET_SC_HASH 计算联盟结构SC的哈希值（稀疏表示，仅记录非零元素）

hash_parts = {};
eps_val = 1e-9;

for m = 1:Value_Params.M
    SC_m = SC{m};
    [rows, cols] = find(SC_m > eps_val);

    for idx = 1:length(rows)
        i = rows(idx);
        k = cols(idx);
        amount = SC_m(i, k);

        % 格式: "m-i-k-amount"
        hash_parts{end+1} = sprintf('%d-%d-%d-%.4f', m, i, k, amount);
    end
end

% 排序以确保相同SC产生相同哈希
hash_parts = sort(hash_parts);

% 拼接成字符串
if isempty(hash_parts)
    hash_str = 'EMPTY';
else
    hash_str = strjoin_custom(hash_parts, '|');
end
end

function is_tabu = is_in_tabu_list(hash_str, tabu_list)
% IS_IN_TABU_LIST 检查哈希值是否在禁忌列表中
is_tabu = ~isempty(tabu_list) && any(strcmp(tabu_list, hash_str));
end

function tabu_list = update_tabu_list(tabu_list, hash_str, tabu_tenure)
% UPDATE_TABU_LIST 更新禁忌列表（FIFO队列）

% 添加新元素，超出期限时移除最早元素
tabu_list{end+1} = hash_str;
if length(tabu_list) > tabu_tenure
    tabu_list = tabu_list(2:end);
end
end

function result = strjoin_custom(cell_array, delimiter)
% STRJOIN_CUSTOM 字符串拼接（兼容旧版MATLAB）
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
% GENERATE_CANDIDATE_SOLUTION_TABU 为单个智能体生成候选解
% 流程: 1)离开操作（随机移除资源） 2)计算选择概率 3)交换操作（重分配资源） 4)可行性检查

%% ==================== 参数初始化 ====================
agent_idx = Value_data_i.agentIndex;  % 当前智能体索引
SC_current = Value_data_i.SC;         % 当前联盟结构

M = Value_Params.M;
K = Value_Params.K;
eps_val = 1e-9;

% 获取温度参数（用于SA_Select_probs）
current_T = Value_Params.Temperature;

% 获取置信度参数
if isfield(AddPara, 'resource_confidence')
    confidence = AddPara.resource_confidence;
else
    confidence = 0.9;
end

%% ==================== 步骤1: 离开操作（Leave Operation）====================
% 随机移除该智能体在某些任务中的部分资源
% 这有助于跳出局部最优，探索新的联盟组合

SC_temp = SC_current;
p_leave = Value_Params.SA_p_leave;  % 离开概率（统一由 Value_Params.SA_p_leave 控制）

for m = 1:M
    for k = 1:K
        % 只有当资源量大于阈值且随机数小于p_leave时才移除
        if SC_temp{m}(agent_idx, k) > eps_val && rand < p_leave
            if AddPara.verbose
                fprintf('      [离开] Agent #%-2d 撤出任务 M=%-2d | 资源 k=%-2d | 数量: %6.2f\n', ...
                    agent_idx, m, k, SC_temp{m}(agent_idx, k));
            end
            SC_temp{m}(agent_idx, k) = 0;
        end
    end
end

%% ==================== 步骤2: 计算资源缺口和选择概率 ====================
% 更新 Value_data_i 以反映离开操作后的状态
Value_data_i.SC = SC_temp;

% 计算资源缺口（基于期望需求）
[~, resource_gap] = calc_gaps(Value_data_i, Value_Params, AddPara);

% 使用SA_Select_probs计算选择概率（结合温度和启发式评价）
probs = SA_Select_probs(Value_data_i, agents, tasks, Value_Params, resource_gap, current_T);

%% ==================== 步骤3: 交换操作（Exchange Operation）====================
% 基于计算的概率，重新分配该智能体的资源
% 核心逻辑：资源是不可拆分但可复用的

SC_new = SC_temp;
task_type_demands = Value_Params.task_type_demands;

% 遍历该智能体持有的K种资源类型
for k = 1:K
    resource_amt = agents(agent_idx).resources(k);
    if resource_amt <= eps_val, continue; end

    % --- 3.1 采样选择目标任务 ---
    prob_vec = probs(k, :);
    cum_prob = cumsum(prob_vec);

    if cum_prob(end) > eps_val
        r = rand * cum_prob(end);
        selected_task = find(cum_prob >= r, 1, 'first');
    else
        selected_task = randi(M);
    end

    % --- 3.2 检查是否已参与该任务 ---
    if SC_new{selected_task}(agent_idx, k) > eps_val
        if AddPara.verbose
            fprintf('      [状态保持] Agent #%-2d 资源 k=%-2d 已在任务 M=%-2d 中\n', ...
                agent_idx, k, selected_task);
        end
        continue;
    end

    % --- 3.3 计算目标任务的期望需求缺口 ---
    curr_alloc = sum(SC_new{selected_task}(:, k));
    belief = Value_data_i.initbelief(selected_task, :);
    expected_demand = WorldSim.calculate_demand_quantile(belief, task_type_demands, confidence);
    can_add = max(0, expected_demand(k) - curr_alloc);

    % --- 3.4 尝试投入资源（如果有缺口）---
    if can_add > eps_val
        % 构造候选SC
        SC_candidate_temp = SC_new;
        SC_candidate_temp{selected_task}(agent_idx, k) = resource_amt;

        % --- 3.5 可行性检查（能量、路径、载重约束）---
        % 构建完整的Value_data数组用于检查
        Value_data_array = repmat(Value_data_i, Value_Params.N, 1);
        for j = 1:Value_Params.N
            Value_data_array(j).agentIndex = j;
            Value_data_array(j).SC = SC_candidate_temp;
        end

        [isFeasible, info, ~] = validate_feasibility(Value_data_array, agents, tasks, ...
            Value_Params, agent_idx, SC_candidate_temp, true, AddPara);

        if isFeasible
            % 可行，接受新的分配
            SC_new = SC_candidate_temp;
            if AddPara.verbose
                fprintf('      [资源投入] Agent #%-2d -> 任务 M=%-2d | 资源 k=%-2d | 数量: %6.2f ✓\n', ...
                    agent_idx, selected_task, k, resource_amt);
            end
        else
            % 不可行，拒绝投入
            if AddPara.verbose
                fprintf('      [拒绝投入] Agent #%-2d -> 任务 M=%-2d | 资源 k=%-2d | 原因: %s ✗\n', ...
                    agent_idx, selected_task, k, info.reason);
            end
        end
    else
        if AddPara.verbose
            fprintf('      [需求饱和] Agent #%-2d | 资源 k=%-2d | 任务 M=%-2d 无需额外投入\n', ...
                agent_idx, k, selected_task);
        end
    end
end

%% ==================== 步骤4: 返回候选解 ====================
SC_candidate = SC_new;
move_description = sprintf('SA_Tabu_Exchange_Agent_%d', agent_idx);

end
