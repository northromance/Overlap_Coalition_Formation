function [Value_data, history_data] = Qi2023_main(agents, tasks, AddPara, Value_Params)
% Qi2023_main - 基于偏好引力的禁忌搜索算法 (PGG-TS) v1.1
% 参考文献: Qi et al. 2023
%
% 核心思想：
%   - 任务信息未知，智能体只能根据信念（belief）估计期望需求
%   - 使用期望需求计算效用和资源分配
%   - 每轮结束后进行观测，更新信念（可通过开关控制）
%   - 基于新信念进行下一轮的重叠联盟形成
%
% 输入参数：
%   agents       - 智能体数据结构
%   tasks        - 任务数据结构
%   AddPara      - 附加参数结构体
%                  .enable_belief_update - 信念更新开关（true=启用，false=仅用初始信念）
%   Value_Params - 系统参数结构体
%
% 输出参数：
%   Value_data   - 更新后的智能体数据
%   history_data - 历史数据记录
%
% 版本历史：
%   v1.0 - 初始版本
%   v1.1 - 添加信念更新开关，支持仅使用初始信念运行

%% 0. 参数设置与初始化
if isfield(Value_Params, 'seed'), rng(Value_Params.seed); end
eps_val = 1e-9;
N = Value_Params.N;
M = Value_Params.M;
K = Value_Params.K;

% 禁忌搜索参数（由 Compare_Algorithms.m 统一注入）
L_tabu = Value_Params.Qi_L_tabu;               % 禁忌表长度
K_len = Value_Params.Qi_K_len;                 % 稳定性阈值（无改进迭代次数）
K_max_inner = Value_Params.Qi_K_max_inner;     % 每轮最大迭代次数

% Boltzmann 系数参数（由 Compare_Algorithms.m 统一注入）
Gamma_init = Value_Params.Qi_Gamma_init;       % 初始 Boltzmann 系数
Gamma_max = Value_Params.Qi_Gamma_max;         % 最大 Boltzmann 系数
Gamma = Gamma_init;                            % 当前 Boltzmann 系数

% 读取信念更新开关（默认启用）
if isfield(AddPara, 'enable_belief_update')
    enable_belief_update = AddPara.enable_belief_update;
else
    enable_belief_update = true;  % 默认启用信念更新
end
if AddPara.verbose
    fprintf('[Qi2023] 信念更新开关: %s\n', mat2str(enable_belief_update));
end

% 使用标准初始化
history_data = struct();
Value_data = WorldSim.init_value_data(agents, tasks, Value_Params);

 [Value_data, summatrix] = WorldSim.init_observe_belief_neighbor(Value_data, N, M, Value_Params);

% 全局联盟结构 SC
SC_global = cell(M, 1);
for m = 1:M, SC_global{m} = zeros(N, K); end

if AddPara.verbose
    fprintf('[Qi2023] 开始PGG-TS算法，共%d轮...\n', Value_Params.num_rounds);
end

%% 主循环：多轮迭代（每轮包括：联盟形成 → 观测 → 信念更新）
for round = 1:Value_Params.num_rounds

    if AddPara.verbose
        fprintf('[Qi2023] === 第 %d/%d 轮 ===\n', round, Value_Params.num_rounds);
    end

    % 每轮重置禁忌搜索参数和Boltzmann系数
    k_iter = 1;
    k_stable = 0;
    TabuList = {};
    Gamma = Gamma_init;  % 重置为初始值

    %% 1. 联盟形成阶段（基于当前信念和上一轮的联盟结构）

    if round == 1
        if AddPara.verbose
            fprintf('[Qi2023] 第1轮：根据概率生成初始联盟结构...\n');
        end
        % 第一轮：根据概率为每个智能体分配初始联盟
        % 参考论文：To get the initial coalition structure SC(1),
        % all initial resources carried by UAVs are allocated to the tasks
        % by Pn(z)(1)dsafdfsaf

        for i = 1:N
            Value_data(i).SC = SC_global;

            % 计算资源缺口和选择概率（使用Qi2023的偏好重力公式）
            [~, resource_gap] = calc_gaps(Value_data(i), Value_Params, AddPara);
            probs = Qi2023_Select_probs(Value_data(i), agents, tasks, Value_Params, resource_gap, Gamma);

            % 根据概率分配所有资源（添加可行性检查）
            SC_global = execute_exchange_operation(i, agents, tasks, SC_global, probs, Value_Params, Value_data, AddPara);

            % 更新所有智能体的SC（顺序传递）
            for j = 1:N
                Value_data(j).SC = SC_global;
            end
        end
    else
        if AddPara.verbose
            fprintf('[Qi2023] 第%d轮：基于更新后的信念和上一轮联盟结构继续优化...\n', round);
        end
    end

    % 记录初始状态（使用期望效用）
    current_utility = 0;
    for i = 1:N
        Value_data(i).SC = SC_global;
        current_utility = current_utility + UtilityEvaluator.calc_agent_total_utility(SC_global, agents, tasks, Value_Params, Value_data(i), AddPara);
    end
    if AddPara.verbose
        fprintf('[Qi2023] 第 %d 轮初始效用（期望）: %.4f\n', round, current_utility);
    end

    %% 2. 禁忌搜索内循环：优化当前联盟结构
    % 初始化内循环历史记录
    inner_loop_history = ResultProcessor.init_inner_loop_history();

    % 按照论文 Algorithm 2 的流程：
    % Loop ∀n ∈ N: 遍历所有智能体
    %   - UAV n 执行操作（离开、引力计算、交换）
    %   - 禁忌检查与效用检查
    %   - Update Boltzmann coefficient Γ(k+1)  <-- 每个智能体操作后立即更新
    %   - Update TabuSC
    %   - k = k + 1  <-- 每个智能体操作后立即递增
    % End loop if k_stable > K_len or k > K_max

    while k_iter <= K_max_inner && k_stable <= K_len

        % 遍历所有智能体（论文中的 Loop ∀n ∈ N）
        for i = 1:N
            
            % ========== A. 离开操作：随机移除部分资源 ==========
            SC_temp = SC_global;
            p_leave = Value_Params.SA_p_leave;  % 离开概率（统一由 Value_Params.SA_p_leave 控制）
            for m = 1:M
                for k = 1:K
                    % 只有当资源量大于阈值(eps_val) 且 随机数小于 p_leave 时才执行
                    if SC_temp{m}(i, k) > eps_val && rand < p_leave
                        % 记录被移走的资源数值
                        removed_amount = SC_temp{m}(i, k);
                        if AddPara.verbose
                            fprintf('  [离开操作] 智能体 #%-2d 撤出 -> 任务 M=%-2d | 资源 k=%-2d | 数量: %6.2f\n', ...
                                i, m, k, removed_amount);
                        end
                        SC_temp{m}(i, k) = 0;
                    end
                end
            end

            % ========== B. 引力计算：计算选择概率（Qi2023偏好重力公式）==========
            Value_data(i).SC = SC_temp;
            [~, resource_gap] = calc_gaps(Value_data(i), Value_Params, AddPara);
            probs = Qi2023_Select_probs(Value_data(i), agents, tasks, Value_Params, resource_gap, Gamma);

            % ========== C. 交换操作：重新分配资源 ==========
            SC_new_candidate = execute_exchange_operation(i, agents, tasks, SC_temp, probs, Value_Params, Value_data, AddPara);

            % ========== D. 禁忌检查 ==========
            SC_hash = get_SC_hash(SC_new_candidate);
            is_tabu = is_in_tabu(SC_hash, TabuList);

            % ========== E. 效用检查与 SC 更新 ==========
            if ~is_tabu
                % 更新智能体 i 的 Value_data，用于 Preference_gain 计算
                Value_data(i).SC = SC_new_candidate;

                % 使用 Preference_gain 计算效用差值
                % Delta U = (Self_Q - Self_P) + Sum(Gain_g) - Sum(Loss_h) + Sum(Diff_o)
                delta_u = Preference_gain(tasks, agents, SC_global, SC_new_candidate, i, Value_Params, Value_data(i));

                if delta_u > 0
                    % 接受新的联盟结构: SC(k+1) = SC_new
                    SC_global = SC_new_candidate;

                    % 重新计算总效用
                    current_utility = 0;
                    for j = 1:N
                        Value_data(j).SC = SC_global;
                        current_utility = current_utility + UtilityEvaluator.calc_agent_total_utility(SC_global, agents, tasks, Value_Params, Value_data(j), AddPara);
                    end

                    % 重置稳定计数器（论文: k_stable = 0）
                    k_stable = 0;
                    
                    % 更新禁忌列表
                    TabuList = update_tabu_list(TabuList, SC_hash, L_tabu);
                else
                    % 拒绝新解: SC(k+1) = SC(k)
                    Value_data(i).SC = SC_global;
                    % 论文: k_stable = k_stable + 1
                    k_stable = k_stable + 1;
                end
            end

            % ========== F. 更新 Boltzmann 系数（论文公式28）==========
            % Γ(k+1) = Γ(k) + k · (Γ_max - Γ(k)) / K_max
            % 注意：每个智能体操作后立即更新，不是等所有 N 个智能体完成后才更新
            Gamma = Gamma + k_iter * (Gamma_max - Gamma) / K_max_inner;

            % ========== G. 迭代计数器递增 ==========
            k_iter = k_iter + 1;

            % ========== H. 记录内循环历史数据 ==========
            inner_loop_history = ResultProcessor.record_inner_loop_iteration(...
                inner_loop_history, k_iter - 1, Gamma, ...
                current_utility, current_utility, SC_global, Value_Params);

            % ========== I. 提前终止检查（论文终止条件）==========
            if k_iter > K_max_inner || k_stable > K_len
                if AddPara.verbose
                    fprintf('[Qi2023] 提前终止: k_iter=%d, k_stable=%d\n', k_iter, k_stable);
                end
                break;
            end

            % 定期打印日志
            if mod(k_iter, 10) == 0 && AddPara.verbose
                fprintf('[Qi2023] 第 %d 轮, 迭代 %d: 效用（期望）= %.4f, 稳定性 = %d, Gamma = %.2f\n', ...
                    round, k_iter, current_utility, k_stable, Gamma);
            end

        end  % end for i (遍历所有智能体)



    end  % end while (主循环)

    if AddPara.verbose
        fprintf('[Qi2023] 第 %d 轮在 %d 次迭代后收敛, 效用（期望）= %.4f, 最终Gamma = %.2f\n', ...
            round, k_iter-1, current_utility, Gamma);
    end

    % 更新所有智能体的 SC
    for i = 1:N
        Value_data(i).SC = SC_global;
    end

    %% 3. 观测阶段：智能体对参与的任务进行观测
    if AddPara.verbose
        fprintf('[Qi2023] 第 %d 轮：进行观测...\n', round);
    end
    [Value_data, summatrix] = AgentOps.collect_observations(Value_data, agents, tasks, Value_Params, summatrix, SC_global);

    %% 4. 信念更新阶段：基于观测结果更新信念（贝叶斯更新）
    % 根据开关决定是否更新信念
    if enable_belief_update
        if AddPara.verbose
            fprintf('[Qi2023] 第 %d 轮：更新信念...\n', round);
        end
        Value_data = AgentOps.update_belief_from_observations(Value_data, Value_Params);
    else
        if AddPara.verbose
            fprintf('[Qi2023] 第 %d 轮：跳过信念更新（使用初始信念）\n', round);
        end
    end

    %% 5. 同步联盟结构：保存当前联盟结构到所有智能体
    % 关键：下一轮将基于这个保存的联盟结构继续优化，而不是从头开始
    final_SC = SC_global;
    for ii = 1:N
        Value_data(ii).SC = final_SC;

        % 更新 resources_matrix（与 Shi2024 保持一致）
        for j = 1:M
            Value_data(ii).resources_matrix(j, :) = final_SC{j}(ii, :);
        end

        % 更新 coalitionstru（使用统一的构建函数）
        Value_data(ii).coalitionstru = OCFUtils.build_coalitionstru_from_SC(final_SC,Value_Params, agents);
    end

    %% 6. 信念广播：智能体之间共享信念
    % 根据开关决定是否广播更新后的信念
    if enable_belief_update
        for i = 1:N
            for j = 1:N
                Value_data(i).other{j}.initbelief = Value_data(j).initbelief;
            end
        end
    end

    %% 7. 记录历史数据（使用真实需求进行最终评估）
    [coalition_utility, total_cost, total_completed_value, task_completion_degrees] = ...
        UtilityEvaluator.evaluate_coalition_metrics(SC_global, agents, tasks, Value_Params, eps_val);

    coalitionstru = cell(M, 1);
    for m = 1:M
        participants = find(any(SC_global{m} > eps_val, 2));
        coalitionstru{m} = participants';
    end

    history_data = ResultProcessor.record_history_data(history_data, round, Value_data, Value_Params, ...
        SC_global, coalitionstru, coalition_utility, total_cost, ...
        total_completed_value, task_completion_degrees, summatrix);

    % --- 记录内循环历史数据 ---
    history_data.inner_loop{round} = inner_loop_history;

    % 记录本轮的内循环迭代次数
    history_data.k_iter_per_round{round} = k_iter;
end

if AddPara.verbose
    fprintf('[Qi2023] 算法完成 %d 轮。\n', Value_Params.num_rounds);
end

%% 最终数据同步：确保所有智能体的数据结构完全一致
if AddPara.verbose
    fprintf('\n[Qi2023] 执行最终数据同步...\n');
end
for ii = 1:N
    Value_data(ii).SC = SC_global;

    % 更新 resources_matrix
    for j = 1:M
        Value_data(ii).resources_matrix(j, :) = SC_global{j}(ii, :);
    end

    % 更新 coalitionstru（使用统一的构建函数）
    Value_data(ii).coalitionstru = OCFUtils.build_coalitionstru_from_SC(SC_global, Value_Params, agents);
end

% 调试输出：显示最终的 coalitionstru
if AddPara.verbose
    fprintf('[Qi2023] 最终 coalitionstru (Agent 1 视图):\n');
    for j = 1:M
        participants = find(Value_data(1).coalitionstru(j, :) > 0);
        if ~isempty(participants)
            fprintf('  任务 %d: 智能体 %s, 值: %s\n', j, mat2str(participants), mat2str(Value_data(1).coalitionstru(j, participants)));
        end
    end
    void_agents = find(Value_data(1).coalitionstru(M+1, :) > 0);
    if ~isempty(void_agents)
        fprintf('  Void任务: 智能体 %s\n', mat2str(void_agents));
    end
end

%% 最终一致性检查（使用统一的检查函数）
if AddPara.verbose
    fprintf('\n[Qi2023] 执行最终一致性检查...\n');
end
[is_valid, error_log] = check_coalition_consistency(Value_data, agents, tasks, Value_Params, 'OCF', AddPara.verbose);

if ~is_valid
    warning('[Qi2023] 联盟一致性检查发现 %d 处问题，请查看上方日志！', length(error_log));
    % 将错误日志保存到历史数据中以便后续分析
    history_data.consistency_errors = error_log;
else
    if AddPara.verbose
        fprintf('✅ [Qi2023] 所有一致性检查通过！\n');
    end
end

end

%% 辅助函数

function SC_new = execute_exchange_operation(agent_idx, agents, tasks, SC_current, probs, Value_Params, Value_data, AddPara)
% EXECUTE_EXCHANGE_OPERATION 执行资源交换操作：不可拆分但可复用的资源分配
%
% 修改后的核心逻辑：
%   - 资源是原子化的（全额投入），但具有"可复用性"（Non-consumable） [cite: 188, 189]
%   - 智能体决定参与一个新任务时，不再撤回已在其他任务中投入的该类资源
%   - 最终形成重叠联盟结构 (Overlapping Coalition Structure) [cite: 120, 155]
%   - 【新增】每次投入资源前进行可行性检查（包括能量约束和队友检查）

SC_new = SC_current;
M = Value_Params.M;
K = Value_Params.K;

% 获取置信度参数
confidence = 0.9;
if nargin >= 8 && isfield(AddPara, 'resource_confidence')
    confidence = AddPara.resource_confidence;
end

% 遍历该智能体持有的 K 种资源类型
for k = 1:K
    resource_amt = agents(agent_idx).resources(k);
    if resource_amt <= 0, continue; end

    %% 1. 采样选择目标任务
    prob_vec = probs(k, :);
    cum_prob = cumsum(prob_vec);
    if cum_prob(end) > 0
        r = rand * cum_prob(end);
        selected_task = find(cum_prob >= r, 1, 'first');
    else
        selected_task = randi(M);
    end
    if isempty(selected_task), selected_task = randi(M); end

    %% 2. 【关键修改】不再清空旧分配
    % 文献中不可消耗资源的交换定义为"加入"或"离开"
    % 这里我们保留该智能体在其他任务 m (m ~= selected_task) 上的资源 k 投入
    % 这体现了资源的"复用性"：同一个设备同时在多个任务联盟中发挥作用 [cite: 267]

    %% 3. 投入逻辑
    % 检查该智能体是否已经参与了此任务
    if SC_new{selected_task}(agent_idx, k) > 0
        if AddPara.verbose
            fprintf('  [状态保持] 智能体 #%-2d 资源 k=%-2d 已在任务 M=%-2d 中复用\n', agent_idx, k, selected_task);
        end
        continue;
    end

    % 计算目标任务的期望需求缺口
    curr_alloc = sum(SC_new{selected_task}(:, k));

    % 获取当前智能体的信念
    if length(Value_data) == 1
        % 如果传入的是单个智能体的 Value_data
        belief = Value_data.initbelief(selected_task, :);
    else
        % 如果传入的是 Value_data 数组
        belief = Value_data(agent_idx).initbelief(selected_task, :);
    end

    task_type_demands = Value_Params.task_type_demands;
    expected_demand = WorldSim.calculate_demand_quantile(belief, task_type_demands, confidence);
    demand_k = expected_demand(k);

    can_add = max(0, demand_k - curr_alloc);

    % 如果有缺口，则尝试将资源"复用"到该任务中
    if can_add > 0
        % 创建候选 SC（尝试投入资源）
        SC_candidate = SC_new;
        SC_candidate{selected_task}(agent_idx, k) = resource_amt;

        %% 【新增】可行性检查（包括能量约束和队友检查）
        % 需要构建完整的 Value_data 结构用于检查
        if length(Value_data) == 1
            % 如果传入的是单个智能体的 Value_data，需要构建完整数组
            Value_data_temp = Value_data;
            Value_data_temp.SC = SC_candidate;
            Value_data_array = repmat(Value_data_temp, Value_Params.N, 1);
            for j = 1:Value_Params.N
                Value_data_array(j).agentID = j;
                Value_data_array(j).SC = SC_candidate;
            end
        else
            % 如果传入的是 Value_data 数组，直接使用并更新 SC
            Value_data_array = Value_data;
            for j = 1:Value_Params.N
                Value_data_array(j).SC = SC_candidate;
            end
        end

        % 调用 validate_feasibility 检查可行性（启用队友检查）
        [isFeasible, info, ~] = validate_feasibility(Value_data_array, agents, tasks, ...
            Value_Params, agent_idx, SC_candidate, true, AddPara);

        if isFeasible
            % 可行，接受新的分配
            SC_new = SC_candidate;
            if AddPara.verbose
                fprintf('  [资源复用] Agent #%-2d -> Task M=%-2d | ResType k=%-2d | Amount: %-6.2f | 可行 ✓\n', ...
                    agent_idx, selected_task, k, resource_amt);
            end
        else
            % 不可行，拒绝投入
            if AddPara.verbose
                fprintf('  [拒绝投入] Agent #%-2d -> Task M=%-2d | ResType k=%-2d | 原因: %s ✗\n', ...
                    agent_idx, selected_task, k, info.reason);
            end
        end
    else
        if AddPara.verbose
            fprintf('  [复用跳过] 智能体 #%-2d | 资源类型 k=%-2d | 任务 M=%-2d 需求已饱和，无需复用投入\n', ...
                agent_idx, k, selected_task);
        end
    end
end
end

function hash_str = get_SC_hash(SC)
% GET_SC_HASH 计算联盟结构的哈希值用于禁忌检查
temp_vec = [];
for m = 1:length(SC)
    temp_vec = [temp_vec; SC{m}(:)];
end
hash_str = mat2str(temp_vec);
end

function is_in = is_in_tabu(sc_hash, tabu_list)
% IS_IN_TABU 检查当前结构是否在禁忌表中
is_in = false;
for i = 1:length(tabu_list)
    if strcmp(sc_hash, tabu_list{i})
        is_in = true;
        return;
    end
end
end

function tabu_list = update_tabu_list(tabu_list, sc_hash, L_tabu)
% UPDATE_TABU_LIST 更新禁忌表（FIFO队列）
tabu_list{end+1} = sc_hash;
if length(tabu_list) > L_tabu
    tabu_list(1) = [];
end
end
