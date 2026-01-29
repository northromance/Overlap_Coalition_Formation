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

% 禁忌搜索参数
L_tabu = 10;                % 禁忌表长度
K_len = 20;                 % 稳定性阈值（无改进迭代次数）
K_max_inner = 100;          % 每轮最大迭代次数

% Boltzmann系数参数（用于偏好重力概率计算）
Gamma_init = 1;             % 初始Boltzmann系数
Gamma_max = 100;            % 最大Boltzmann系数
Gamma = Gamma_init;         % 当前Boltzmann系数

% 读取信念更新开关（默认启用）
if isfield(AddPara, 'enable_belief_update')
    enable_belief_update = AddPara.enable_belief_update;
else
    enable_belief_update = true;  % 默认启用信念更新
end
fprintf('[Qi2023] 信念更新开关: %s\n', mat2str(enable_belief_update));

% 使用标准初始化
history_data = struct();
Value_data = WorldSim.init_value_data(agents, tasks, Value_Params);

% 初始化观测矩阵（与SA算法保持一致）
for i = 1:N
    for j = 1:M
        for k = 1:Value_Params.task_type
            Value_data(i).observe(j, k) = 0;        % 当前轮的观测计数
            Value_data(i).preobserve(j, k) = 0;     % 累计的历史观测计数
        end
    end
end

% 初始化全局观测汇总矩阵
summatrix = zeros(M, Value_Params.task_type);

% 初始化信念分布（均匀先验）
for i = 1:N
    for j = 1:M
        Value_data(i).initbelief(j, 1:end) = ones(Value_Params.task_type, 1) / Value_Params.task_type;
    end
end

% 初始化邻居信念（用于信息共享）
for i = 1:N
    for j = 1:N
        Value_data(i).other{j}.initbelief = Value_data(j).initbelief;
    end
end

% 全局联盟结构 SC
SC_global = cell(M, 1);
for m = 1:M, SC_global{m} = zeros(N, K); end

fprintf('[Qi2023] 开始PGG-TS算法，共%d轮...\n', Value_Params.num_rounds);

%% 主循环：多轮迭代（每轮包括：联盟形成 → 观测 → 信念更新）
for round = 1:Value_Params.num_rounds

    fprintf('[Qi2023] === 第 %d/%d 轮 ===\n', round, Value_Params.num_rounds);

    % 每轮重置禁忌搜索参数和Boltzmann系数
    k_iter = 1;
    k_stable = 0;
    TabuList = {};
    Gamma = Gamma_init;  % 重置为初始值

    %% 1. 联盟形成阶段（基于当前信念和上一轮的联盟结构）

    if round == 1
        fprintf('[Qi2023] 第1轮：根据概率生成初始联盟结构...\n');
        % 第一轮：根据概率为每个智能体分配初始联盟
        % 参考论文：To get the initial coalition structure SC(1),
        % all initial resources carried by UAVs are allocated to the tasks
        % by Pn(z)(1)dsafdfsaf

        for i = 1:N
            Value_data(i).SC = SC_global;

            % 计算资源缺口和选择概率（使用Qi2023的偏好重力公式）
            [~, resource_gap] = calc_gaps(Value_data(i), Value_Params, AddPara);
            probs = Qi2023_Select_probs(Value_data(i), agents, tasks, Value_Params, resource_gap, Gamma);

            % 根据概率分配所有资源
            SC_global = execute_exchange_operation(i, agents, SC_global, probs, Value_Params, Value_data(i), AddPara);

            % 更新所有智能体的SC（顺序传递）
            for j = 1:N
                Value_data(j).SC = SC_global;
            end
        end
    else
        fprintf('[Qi2023] 第%d轮：基于更新后的信念和上一轮联盟结构继续优化...\n', round);
    end

    % 记录初始状态（使用期望效用）
    current_utility = 0;
    for i = 1:N
        Value_data(i).SC = SC_global;
        current_utility = current_utility + UtilityEvaluator.calc_agent_total_utility(SC_global, agents, tasks, Value_Params, Value_data(i), AddPara);
    end
    fprintf('[Qi2023] 第 %d 轮初始效用（期望）: %.4f\n', round, current_utility);

    %% 2. 禁忌搜索内循环：优化当前联盟结构
    while k_iter <= K_max_inner && k_stable <= K_len

        improved_this_iter = false;

        % 遍历所有智能体
        for i = 1:N
            % A. 离开操作：随机移除部分资源
            SC_temp = SC_global;
            p_leave = 0.3;
            for m = 1:M
                for k = 1:K
                    if SC_temp{m}(i, k) > eps_val && rand < p_leave
                        SC_temp{m}(i, k) = 0;
                    end
                end
            end

            % B. 引力计算：计算选择概率（使用Qi2023的偏好重力公式）
            Value_data(i).SC = SC_temp;
            [~, resource_gap] = calc_gaps(Value_data(i), Value_Params, AddPara);
            probs = Qi2023_Select_probs(Value_data(i), agents, tasks, Value_Params, resource_gap, Gamma);

            % C. 交换操作：重新分配资源（使用期望需求）
            SC_new_candidate = execute_exchange_operation(i, agents, SC_temp, probs, Value_Params, Value_data(i), AddPara);

            % D. 禁忌检查
            SC_hash = get_SC_hash(SC_new_candidate);
            is_tabu = is_in_tabu(SC_hash, TabuList);

            if ~is_tabu
                % E. 效用检查（使用 Preference_gain 计算效用差）
                % 不是简单的新旧效用差，而是考虑智能体自身和队友的效用变化
                % Delta U = (Self_Q - Self_P) + Sum(Gain_g) - Sum(Loss_h) + Sum(Diff_o)

                % 更新智能体 i 的 Value_data，用于 Preference_gain 计算
                Value_data(i).SC = SC_new_candidate;

                % 使用 Preference_gain 计算效用差值
                delta_u = Preference_gain(tasks, agents, SC_global, SC_new_candidate, i, Value_Params, Value_data(i));

                if delta_u > 0
                    % 接受新的联盟结构
                    SC_global = SC_new_candidate;

                    % 重新计算总效用
                    current_utility = 0;
                    for j = 1:N
                        Value_data(j).SC = SC_global;
                        current_utility = current_utility + UtilityEvaluator.calc_agent_total_utility(SC_global, agents, tasks, Value_Params, Value_data(j), AddPara);
                    end

                    k_stable = 0;
                    improved_this_iter = true;
                    TabuList = update_tabu_list(TabuList, SC_hash, L_tabu);
                else
                    % 恢复智能体 i 的 SC
                    Value_data(i).SC = SC_global;
                end
            end
        end

        if ~improved_this_iter
            k_stable = k_stable + 1;
        end

        % F. 更新Boltzmann系数（探索与开发的权衡）
        % Gamma(k+1) = Gamma(k) + k * (Gamma_max - Gamma(k)) / K_max
        Gamma = Gamma + k_iter * (Gamma_max - Gamma) / K_max_inner;

        if mod(k_iter, 10) == 0
            fprintf('[Qi2023] 第 %d 轮, 迭代 %d: 效用（期望）= %.4f, 稳定性 = %d, Gamma = %.2f\n', ...
                round, k_iter, current_utility, k_stable, Gamma);
        end

        k_iter = k_iter + 1;
    end

    fprintf('[Qi2023] 第 %d 轮在 %d 次迭代后收敛, 效用（期望）= %.4f, 最终Gamma = %.2f\n', ...
        round, k_iter-1, current_utility, Gamma);

    % 更新所有智能体的 SC
    for i = 1:N
        Value_data(i).SC = SC_global;
    end

    %% 3. 观测阶段：智能体对参与的任务进行观测
    fprintf('[Qi2023] 第 %d 轮：进行观测...\n', round);
    [Value_data, summatrix] = AgentOps.collect_observations(Value_data, agents, tasks, Value_Params, summatrix, SC_global);

    %% 4. 信念更新阶段：基于观测结果更新信念（贝叶斯更新）
    % 根据开关决定是否更新信念
    if enable_belief_update
        fprintf('[Qi2023] 第 %d 轮：更新信念...\n', round);
        Value_data = AgentOps.update_belief_from_observations(Value_data, Value_Params);
    else
        fprintf('[Qi2023] 第 %d 轮：跳过信念更新（使用初始信念）\n', round);
    end

    %% 5. 同步联盟结构：保存当前联盟结构到所有智能体
    % 关键：下一轮将基于这个保存的联盟结构继续优化，而不是从头开始
    final_SC = SC_global;
    for ii = 1:N
        Value_data(ii).SC = final_SC;
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
end

fprintf('[Qi2023] 算法完成 %d 轮。\n', Value_Params.num_rounds);

end

%% 辅助函数

function SC_new = execute_exchange_operation(agent_idx, agents, SC_current, probs, Value_Params, Value_data, AddPara)
% EXECUTE_EXCHANGE_OPERATION 执行资源交换操作：不可拆分但可复用的资源分配
%
% 修改后的核心逻辑：
%   - 资源是原子化的（全额投入），但具有“可复用性”（Non-consumable） [cite: 188, 189]
%   - 智能体决定参与一个新任务时，不再撤回已在其他任务中投入的该类资源
%   - 最终形成重叠联盟结构 (Overlapping Coalition Structure) [cite: 120, 155]

SC_new = SC_current;
M = Value_Params.M;
K = Value_Params.K;

% 获取置信度参数
confidence = 0.9;
if nargin >= 7 && isfield(AddPara, 'resource_confidence')
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
    % 文献中不可消耗资源的交换定义为“加入”或“离开” 
    % 这里我们保留该智能体在其他任务 m (m ~= selected_task) 上的资源 k 投入
    % 这体现了资源的“复用性”：同一个设备同时在多个任务联盟中发挥作用 [cite: 267]
    
    %% 3. 投入逻辑
    % 检查该智能体是否已经参与了此任务
    if SC_new{selected_task}(agent_idx, k) > 0
        fprintf('  [状态保持] 智能体 #%-2d 资源 k=%-2d 已在任务 M=%-2d 中复用\n', agent_idx, k, selected_task);
        continue;
    end

    % 计算目标任务的期望需求缺口
    curr_alloc = sum(SC_new{selected_task}(:, k));
    belief = Value_data.initbelief(selected_task, :);
    task_type_demands = Value_Params.task_type_demands;
    expected_demand = WorldSim.calculate_demand_quantile(belief, task_type_demands, confidence);
    demand_k = expected_demand(k);
    
    can_add = max(0, demand_k - curr_alloc);
    
    % 如果有缺口，则将资源“复用”到该任务中
    if can_add > 0
        % 不可拆分资源，按 all-in 模式投入 [cite: 409]
        act_add = resource_amt; 
        SC_new{selected_task}(agent_idx, k) = act_add;

        %% --- 增强版打印信息 ---
        % fprintf('  [资源复用] 智能体 #%-2d | 资源类型 k=%-2d | 全额投入: %-6.2f -> 任务 M=%-2d \n', ...
        %     agent_idx, k, act_add, selected_task);
    else
        % fprintf('  [复用跳过] 智能体 #%-2d | 资源类型 k=%-2d | 任务 M=%-2d 需求已饱和，无需复用投入\n', ...
        %     agent_idx, k, selected_task);
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
