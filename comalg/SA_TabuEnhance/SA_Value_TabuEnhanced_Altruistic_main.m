function [Value_data, history_data] = SA_Value_TabuEnhanced_Altruistic_main(agents, tasks, AddPara, Value_Params)
% SA_VALUE_TABUENHANCED_ALTRUISTIC_MAIN 基于局部社会效用的模拟退火-禁忌搜索算法
%
% === [核心设计理念 - 局部社会效用（LSU）版本] ===
% 本版本采用完全分布式的利他主义决策机制，核心创新为"局部社会效用"：
%
%   1. Metropolis准则：基于 Preference_gain 计算的个体利他偏好差值
%      - delta_E = 自身效用变化 + 队友效用变化（新增、损失、稳定）
%      - 用于接受/拒绝候选解的日常决策（模拟退火的核心概率接受机制）
%
%   2. 特赦准则（Aspiration Criterion）：基于局部社会效用（Local Social Utility, LSU）
%      - LSU定义：智能体 i 相关利益群体在候选解下的效用总和
%        * 自身效用
%        * 旧联盟成员效用（资源撤出/减少时的任务队友）
%        * 新联盟成员效用（资源增加时的任务队友）
%      - 每个智能体维护自己的最佳历史LSU： best_LSU(i)
%      - 特赦条件：current_LSU(i) > best_LSU(i)
%      - 理论含义：即使当前动作被禁忌表封锁，但只要它能让“局部利益相关群体的总福利”达到历史新高，就无视禁忌，强制允许执行。
%
%   3. 理论依据：分布式多智能体系统，个体基于局部信息和利他性决策
%      - 个体不掌握全局信息，但关心与自己利益相关的成员（熟人社会网络）。
%      - 成员集合随资源交换动态变化，体现真实的社会网络特征。
% ==============================================

%% ==================== 0. 随机数种子设置 ====================
% 为了保证科学实验的可复现性（Reproducibility），固定随机数种子
if isfield(Value_Params, 'seed')
    rng(Value_Params.seed);
end

%% ==================== 1. 初始化阶段 ====================
eps_val = 1e-6;          % 浮点数比较容差，防止因为计算机精度问题导致误判
history_data = struct(); % 初始化历史记录容器，用于追踪随时间变化的算法指标
tabu_tenure = Value_Params.tabu_tenure; % 禁忌步长（即一个解被关进“小黑屋”的迭代次数）

% --- 初始化智能体核心数据结构 (Value_data) ---
% 包括各个Agent分配到的任务、自身资源等初始状态
Value_data = WorldSim.init_value_data(agents, tasks, Value_Params);

% --- 初始化观测、信念与邻居信息 ---
% 分布式系统的关键：Agent不能直接看到全局真实状态，只能通过观测(observe)形成信念(belief)
[Value_data, summatrix] = WorldSim.init_observe_belief_neighbor(Value_data, Value_Params.N, Value_Params.M, Value_Params);

%% ==================== 2. 主循环：多轮博弈迭代 ====================
% 每一轮(round)代表一次完整的环境演进或任务重分配周期
for counter = 1:Value_Params.num_rounds

    %% 2.2 SA 初始化 (本轮博弈前的准备)
    k_iter = 1;                     % 当前退火迭代次数
    previous_SC = Value_data(1).SC; % 记录上一时刻的联盟结构(Service Coalition, SC)
    k_stable = 0;                   % 记录系统连续保持稳定（未发生状态转移）的步数
    doneflag = 0;                   % 提前结束退火的标志位

    % --- 温度调度策略 (Temperature Schedule) ---
    % 退火温度随轮数递减，保证初期探索(Exploration)率高，后期利用(Exploitation)率高
    Value_Params.Temperature = max(Value_Params.SA_T_base_round, ...
        Value_Params.SA_T0_round * Value_Params.SA_beta_round^(counter-1));
    if AddPara.verbose
        fprintf('  [SA-Altruistic] Round %d: 初始温度 = %.2f\n', counter, Value_Params.Temperature);
    end

    % === [局部社会效用（LSU）初始化] ===
    % 初始化每个智能体的最优局部社会效用记录
    best_SC = Value_data(1).SC;     % 全局最优联盟结构缓存
    best_coalitionstru = Value_data(1).coalitionstru;

    % 初始化个体LSU最优值（每个智能体独立维护自己的账本）
    best_LSU = zeros(Value_Params.N, 1);

    % 构造一个空的SC用于基准比较（假设一开始什么任务都没分配）
    SC_empty = cell(Value_Params.M, 1);
    for m = 1:Value_Params.M
        SC_empty{m} = zeros(Value_Params.N, Value_Params.K); % N个Agent, K种资源
    end

    % 计算并记录初始状态下，每个Agent的局部社会效用
    for j = 1:Value_Params.N
        best_LSU(j) = calculate_local_social_utility(SC_empty, best_SC, j, agents, tasks, Value_Params, Value_data(j), AddPara);
    end

    % 计算系统当前的全局总效用（上帝视角，仅用于日志和性能评估，不参与Agent的分布式决策）
    best_utility_global = 0;
    for j = 1:Value_Params.N
        best_utility_global = best_utility_global + UtilityEvaluator.calc_agent_total_utility(best_SC, agents, tasks, Value_Params, Value_data(j), AddPara);
    end
    % === [局部社会效用（LSU）初始化结束] ===

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

                % 轮盘赌选择
                prob_vec = probs(k, :);
                cum_prob = cumsum(prob_vec);
                if cum_prob(end) > 1e-9
                    r = rand * cum_prob(end);
                    selected_task = find(cum_prob >= r, 1, 'first');
                else
                    selected_task = randi(Value_Params.M); % 概率全为0时随机挑一个
                end
                if isempty(selected_task), selected_task = randi(Value_Params.M); end

                % 如果已经在此任务中投入了该资源，跳过
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

        % 更新历史最优记录
        best_SC = SC_global;
        best_coalitionstru = Value_data(1).coalitionstru;

        % 根据生成的初始解重新计算每个Agent的局部社会效用(LSU)
        for ii = 1:Value_Params.N
            best_LSU(ii) = calculate_local_social_utility(SC_empty, SC_global, ii, agents, tasks, Value_Params, Value_data(ii), AddPara);
        end

        % 重新计算上帝视角的全局效用
        best_utility_global = 0;
        for ii = 1:Value_Params.N
            best_utility_global = best_utility_global + UtilityEvaluator.calc_agent_total_utility(SC_global, agents, tasks, Value_Params, Value_data(ii), AddPara);
        end
        if AddPara.verbose
            fprintf('  [SA] 第1轮：初始全局效用 = %.2f\n', best_utility_global);
        end
    end

    %% ==================== 3. SA 外循环 (核心博弈过程 - 利他主义版本) ====================
    inner_loop_history = ResultProcessor.init_inner_loop_history();

    % 记录当前状态的全局效用（上帝视角，仅供绘图/评估）
    current_utility_global = 0;
    for j = 1:Value_Params.N
        current_utility_global = current_utility_global + UtilityEvaluator.calc_agent_total_utility(Value_data(j).SC, agents, tasks, Value_Params, Value_data(j), AddPara);
    end

    % doneflag 控制退火是否收敛
    while(doneflag == 0)
        % --- 3.1 顺序博弈 (Sequential Game) - 利他主义决策 ---
        % 在每一个降温步中，N个Agent轮流根据自身逻辑更新策略（这模拟了异步/顺序的决策过程）
        SC_before_inner = Value_data(1).SC;
        utility_before_inner = current_utility_global;

        for ii = 1:Value_Params.N
            % 步骤1: 智能体 ii 根据自身局部信息生成一个变异候选解（撤出某些任务，加入新任务）
            [SC_candidate, ~] = generate_candidate_solution_tabu(Value_data(ii), agents, tasks, Value_Params, AddPara);


            % 步骤3: 禁忌判断 (Tabu Check)
            candidate_hash = get_SC_hash(SC_candidate, Value_Params); % 对分配矩阵进行哈希，生成唯一指纹
            is_tabu = is_in_tabu_list(candidate_hash, tabu_list);     % 判断新解是否在禁忌表中

            accept = false;
            accept_reason = '';

            if is_tabu
                % === [局部社会效用（LSU）特赦准则] ===
                % 如果候选解在禁忌表里，原本应该被拒绝。但是如果它足够好，可以触发“特赦”
                SC_current = Value_data(ii).SC;
                % 计算采用该候选解后，智能体 ii 及其周边队友的综合利益(LSU)
                current_LSU = calculate_local_social_utility(SC_current, SC_candidate, ii, agents, tasks, Value_Params, Value_data(ii), AddPara);

                % 特赦条件：当前LSU打破了该智能体的历史最优记录
                if current_LSU > best_LSU(ii)
                    accept = true;
                    accept_reason = 'Tabu-Aspiration-LSU';
                    if AddPara.verbose
                        fprintf('      [Agent %d] LSU特赦接受禁忌解 (LSU=%.2f > 最优=%.2f)\n', ...
                            ii, current_LSU, best_LSU(ii));
                    end
                else
                    % 未触发特赦，坚决拒绝该禁忌解
                    accept = false;
                    accept_reason = 'Tabu-Reject';
                    if AddPara.verbose
                        fprintf('      [Agent %d] 拒绝禁忌解 (LSU=%.2f)\n', ii, current_LSU);
                    end
                end
                % === [局部社会效用（LSU）特赦准则结束] ===
            else
                % === [利他主义 Metropolis 准则] ===
                % 如果不在禁忌表中，进入标准的模拟退火判定流
                SC_current = Value_data(ii).SC;

                % 计算利他偏好差值（Delta Energy）。
                % Preference_gain 函数不仅考虑个体自己的利益得失，还考虑被它动作影响到的队友的得失。
                delta_E_altruistic = Preference_gain(tasks, agents, SC_current, SC_candidate, ii, Value_Params, Value_data(ii));

                % === [利他主义 Metropolis 准则结束] ===
                if delta_E_altruistic >= 0
                    % 如果是“好解”（利他偏好提升或不变），无条件接受
                    accept = true;
                    accept_reason = 'Metropolis-Improve-Altruistic';
                else
                    % 如果是“劣解”，按照玻尔兹曼概率接受 (概率随温降减小)
                    % 这给予了系统跳出局部最优（Local Optima）的能力
                    prob = exp(delta_E_altruistic / Value_Params.Temperature);
                    if rand < prob
                        accept = true;
                        accept_reason = 'Metropolis-Accept-Altruistic';
                        if AddPara.verbose
                            fprintf('      [Agent %d] 概率接受恶化解 (利他ΔE=%.2f, prob=%.4f)\n', ii, delta_E_altruistic, prob);
                        end
                    else
                        accept = false; % 运气不佳，拒绝劣解
                        accept_reason = 'Metropolis-Reject';
                    end
                end
            end

            % 步骤5: 执行解的更新
            if accept
                % 5.1 更新当前解到所有Agent的数据结构中（表示行动已落实）
                for jj = 1:Value_Params.N
                    Value_data(jj).SC = SC_candidate;
                    Value_data(jj).coalitionstru = OCFUtils.build_coalitionstru_from_SC(SC_candidate, Value_Params, agents);
                    Value_data(jj).resources_matrix = OCFUtils.get_agent_resource_matrix(SC_candidate, jj, Value_Params);
                end

                % 5.2 将新接受的状态加入禁忌表（注意：如果是通过特赦接受的原本就在禁忌表中的解，不需要重新加入）
                if ~is_tabu
                    tabu_list = update_tabu_list(tabu_list, candidate_hash, tabu_tenure);
                end

                % 5.3 检查并更新个体LSU历史最优账本
                SC_current = Value_data(ii).SC;
                current_LSU = calculate_local_social_utility(SC_current, SC_candidate, ii, agents, tasks, Value_Params, Value_data(ii), AddPara);
                if current_LSU > best_LSU(ii)
                    best_LSU(ii) = current_LSU;
                    if AddPara.verbose
                        fprintf('      [Agent %d] 更新个体LSU最优 (LSU=%.2f)\n', ii, best_LSU(ii));
                    end
                end

                % 5.5 状态传递机制，确保下一个Agent能基于最新的系统状态进行决策
                if ii < Value_Params.N
                    Value_data(ii + 1).SC = SC_candidate;
                    Value_data(ii + 1).coalitionstru = Value_data(ii).coalitionstru;
                end
            end
        end  % end for ii (本轮所有智能体决策完毕)

        % 记录内部迭代(降温过程中的一步)的历史数据
        inner_loop_history = ResultProcessor.record_inner_loop_iteration(...
            inner_loop_history, k_iter, ...
            Value_Params.Temperature, current_utility_global, best_utility_global, Value_data(1).SC, Value_Params);

        % --- 3.2 完成一轮全员顺序博弈后的操作 ---

        % 核心动作：退火降温。Temperature = alpha * Temperature
        Value_Params.Temperature = Value_Params.alpha * Value_Params.Temperature;

        % 提取最终的联盟矩阵结构
        final_SC = Value_data(Value_Params.N).SC;
        final_coalitionstru = Value_data(Value_Params.N).coalitionstru;

        % --- 3.2.2 收敛检测 (Stopping Criteria) ---
        % 判断1：如果全员博弈完一轮后，系统状态与上一轮毫无变化，稳定计数器+1
        if isequal(previous_SC, final_SC)
            k_stable = k_stable + 1;
        else
            k_stable = 0; % 一旦有变化，计数器清零
        end

        % 满足以下三个条件之一，退出本轮的退火过程：
        % 1. 系统连续 SA_K_len 步不再发生状态转移（已收敛到均衡点）
        % 2. 系统温度降至绝对低温 Tmin
        % 3. 迭代步数达到了设定的上限 SA_Tabu_K_max_outer
        if k_stable >= Value_Params.SA_K_len
            doneflag = 1;
        elseif Value_Params.Temperature < Value_Params.Tmin
            doneflag = 1;
        elseif k_iter >= Value_Params.SA_Tabu_K_max_outer
            doneflag = 1;
        end

        % 滚动更新旧状态
        previous_SC = final_SC;
        k_iter = k_iter + 1;

        % --- 3.2.3 全网状态同步 ---
        % 收敛后，确保每一个Agent都把状态对齐到最终状态
        for ii = 1:Value_Params.N
            Value_data(ii).coalitionstru = final_coalitionstru;
            Value_data(ii).SC = final_SC;
            Value_data(ii).resources_matrix = OCFUtils.get_agent_resource_matrix(Value_data(ii).SC, ii, Value_Params);
        end
        if AddPara.verbose
            fprintf('  [SA-Outer] Iter %d: T=%.2f, Utility=%.2f, Best=%.2f\n', ...
                k_iter, Value_Params.Temperature, current_utility_global, best_utility_global);
        end
    end  % end while (SA退火外循环结束)

    % 本轮任务分配结果已定，重新计算并缓存具体执行的时间表 (Schedule)
    Value_data = update_task_schedule(Value_data, agents, tasks, Value_Params);

    %% ==================== 4. 观测与信念更新 (Observation & Belief Update) ====================
    % 在执行任务的过程中，Agent能观察到环境的变化，从而更新对任务难度、队友能力的信念
    [Value_data, summatrix] = AgentOps.collect_observations(Value_data, agents, tasks, Value_Params, summatrix, final_SC);
    Value_data = AgentOps.update_belief_from_observations(Value_data, Value_Params);

    %% ==================== 5. 结果评估 (客观/上帝视角) ====================
    % 调用上帝视角的评价函数，计算最终真实的收益、成本、任务完成度
    [coalition_utility, total_global_cost, total_completed_value, task_completion_degrees] = ...
        UtilityEvaluator.evaluate_coalition_metrics(final_SC, agents, tasks, Value_Params, eps_val);

    %% 4.8 信念广播 (Belief Broadcasting)
    % 将更新后的信念在网络中传播（让Agent了解别人的最新看法）
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

    % 单独记录局部社会效用的演化数据
    history_data.best_LSU{counter} = best_LSU;
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
is_tabu = false;
for i = 1:length(tabu_list)
    if strcmp(tabu_list{i}, hash_str)
        is_tabu = true;
        return;
    end
end
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
SC_current = Value_data_i.SC;
M = Value_Params.M;
K = Value_Params.K;
eps_val = 1e-9;
current_T = Value_Params.Temperature;

if isfield(AddPara, 'resource_confidence')
    confidence = AddPara.resource_confidence;
else
    confidence = 0.9;
end

% 获取离开概率参数 p_leave
if isfield(Value_Params, 'SA_p_leave')
    p_leave = Value_Params.SA_p_leave;
elseif isfield(AddPara, 'p_leave')
    p_leave = AddPara.p_leave;
else
    p_leave = 0.1;
end
SC_temp = SC_current;

% --- 步骤 A：随机撤出当前拥有的部分任务资源 ---
for m = 1:M
    for k = 1:K
        if SC_temp{m}(agent_idx, k) > eps_val && rand < p_leave
            removed_amount = SC_temp{m}(agent_idx, k);
            SC_temp{m}(agent_idx, k) = 0; % 撤回资源
            
            % 【打印：撤出资源】
            if AddPara.verbose
                fprintf('      [-] [撤出] Agent #%-2d 从 任务 M=%-2d 撤出 资源 k=%-2d | 数量: %.2f\n', ...
                    agent_idx, m, k, removed_amount);
            end
        end
    end
end

% 更新数据准备进行新一轮分配
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
    if total_capacity <= eps_val, continue; end % 如果没有这种能力，直接跳过
    
    % 基于累积分布概率挑选目标任务
    prob_vec = probs(k, :);
    cum_prob = cumsum(prob_vec);
    if cum_prob(end) > eps_val
        r = rand * cum_prob(end);
        selected_task = find(cum_prob >= r, 1, 'first');
    else
        selected_task = randi(M);
    end
    if isempty(selected_task), selected_task = randi(M); end
    
    % 防局部重叠：不能在一个任务上“自我复用”两次
    if SC_new{selected_task}(agent_idx, k) > eps_val
        continue;
    end
    
    % 检查该任务是否还需要该资源
    curr_alloc = sum(SC_new{selected_task}(:, k));
    belief = Value_data_i.initbelief(selected_task, :);
    expected_demand = WorldSim.calculate_demand_quantile(belief, task_type_demands, confidence);
    demand_k = expected_demand(k);
    
    % 只要任务还有一丁点缺口，我们就考虑投入
    can_add = max(0, demand_k - curr_alloc);
    
    if can_add > eps_val
        SC_candidate_temp = SC_new;
        invest_amt = total_capacity; % 不可分割，全量投入
        SC_candidate_temp{selected_task}(agent_idx, k) = invest_amt;
        
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
            SC_new = SC_candidate_temp; % 采纳方案
            
            % 【打印：加入资源（成功）】
            if AddPara.verbose
                fprintf('      [+] [复用] Agent #%-2d 向 任务 M=%-2d 投入 资源 k=%-2d | 数量: %.2f\n', ...
                    agent_idx, selected_task, k, invest_amt);
            end
            
        else
            % 【打印：被拒绝的原因（可选但极力推荐，便于排错）】
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
% 【计算局部社会效用 (Local Social Utility)】
   function LSU = calculate_local_social_utility(SC_old, SC_candidate, agent_idx, agents, tasks, Value_Params, Value_data, AddPara)
    % CALCULATE_LOCAL_SOCIAL_UTILITY 计算局部社会效用（Local Social Utility, LSU）
    %
    % 【核心修复版：引入时间耦合/蝴蝶效应侦测】
    % 在多机器人协同中，智能体 i 的路径/时间表发生任何变动，都会导致它参与的所有任务的到达时间偏移。
    % 这会直接影响在这些任务中等待 i 的其他机器人的等待耗电量 (t_wait_total)。
    % 因此，相关利益群体不仅包括“资源增减”的任务队友，还必须包括“资源不变但时间表受波及”的稳定任务队友。
    %
    % 输入：
    %   SC_old       : 旧联盟结构（当前状态）
    %   SC_candidate : 新联盟结构（候选状态）
    %   agent_idx    : 当前决策的智能体索引
    %   agents/tasks : 物理属性与参数
    %   Value_data   : 智能体信念数据
    %   AddPara      : 附加参数
    %
    % 输出：
    %   LSU : 局部社会效用（智能体 i 及其所有受波及队友在 SC_candidate 下的效用总和）

    eps_val = 1e-6;

    %% ==================== 1 & 2. 识别受波及任务并提取利益共同体 ====================
    related_members = [];

    for m = 1:Value_Params.M
        % 计算智能体在任务 m 上的总资源投入量（各种资源之和）
        old_investment = sum(SC_old{m}(agent_idx, :));
        new_investment = sum(SC_candidate{m}(agent_idx, :));

        % 只要在旧状态 OR 新状态中参与了该任务，该任务的队友就算作利益相关者
        if old_investment > eps_val || new_investment > eps_val
            % 把该任务在旧状态和新状态下的所有参与者都捞出来
            members_old = OCFUtils.get_participants(SC_old, m, eps_val);
            members_new = OCFUtils.get_participants(SC_candidate, m, eps_val);

            % 合并该任务的关联成员并压入总集合
            task_members = [members_old(:)', members_new(:)'];
            related_members = [related_members, task_members];
        end
    end

    % 全局去重（防止一个人同时在两个受影响任务里被重复计算）
    related_members = unique(related_members);
    
    % 排除自己（因为智能体自身的效用在下一步会单独计算）
    related_members(related_members == agent_idx) = [];

    %% ==================== 3. 计算并合并 LSU ====================
    % 最终公式：LSU = 自身效用 + sum(受波及队友们的效用)

    % 3.1 独立计算自己的效用 (在候选解 SC_candidate 状态下)
    Value_data_temp = Value_data;
    Value_data_temp.SC = SC_candidate;
    self_utility = UtilityEvaluator.calc_agent_total_utility(SC_candidate, agents, tasks, Value_Params, Value_data_temp, AddPara);

    % 3.2 循环计算被卷入的各个队友的效用
    teammates_utility = 0;
    for k = 1:length(related_members)
        teammate_id = related_members(k);

        % 分布式博弈的体现：我无法直接得知队友怎么看，只能根据脑海中的“关于队友想法的信念(belief)”来代入计算
        if isfield(Value_data, 'other') && length(Value_data.other) >= teammate_id && ~isempty(Value_data.other{teammate_id})
            teammate_belief = Value_data.other{teammate_id}.initbelief;
        else
            % 兜底方案：如果不知道队友的想法，就假设队友和我看法一样(同质化预设)
            teammate_belief = Value_data.initbelief;
        end

        % 伪造一个临时数据对象，让估值函数误以为是 teammate_id 正在计算它的效用
        temp_data.agentIndex = teammate_id;
        temp_data.initbelief = teammate_belief;
        temp_data.SC = SC_candidate;

        % 评出在新的联盟状态下，该队友的预计得分 (这里底层的 calc_agent_total_utility 会捕捉到时间延误/电量消耗带来的惩罚)
        teammate_utility = UtilityEvaluator.calc_agent_total_utility(SC_candidate, agents, tasks, Value_Params, temp_data, AddPara);
        teammates_utility = teammates_utility + teammate_utility;
    end

    % 3.3 汇总返回
    LSU = self_utility + teammates_utility;
end