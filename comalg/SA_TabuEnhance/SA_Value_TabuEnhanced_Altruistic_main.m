function [Value_data, history_data] = SA_Value_TabuEnhanced_Altruistic_main(agents, tasks, AddPara, Value_Params)

% SA_VALUE_TABUENHANCED_ALTRUISTIC_MAIN 基于局部社会效用的模拟退火-禁忌搜索算法
% 
% ??? [核心设计理念 - 局部社会效用（LSU）版本] ???
% 本版本采用完全分布式的利他主义决策机制，核心创新为"局部社会效用"：
%   
%   1. Metropolis准则：基于 Preference_gain 计算的个体利他偏好差值
%      - delta_E = 自身效用变化 + 队友效用变化（新增、损失、稳定）
%      - 用于接受/拒绝候选解的日常决策
%   
%   2. 特赦准则：基于局部社会效用（Local Social Utility, LSU）
%      - LSU定义：智能体 i 相关利益群体在候选解下的效用总和
%        * 自身效用
%        * 旧联盟成员效用（资源撤出/减少时的任务队友）
%        * 新联盟成员效用（资源增加时的任务队友）
%      - 每个智能体维护自己的 best_LSU(i)
%      - 特赦条件：current_LSU(i) > best_LSU(i)
%      - 理论含义：当局部利益相关群体的总福利达到历史新高时，允许突破禁忌约束
%   
%   3. 理论依据：分布式多智能体系统，个体基于局部信息和利他性决策
%      - 个体不掌握全局信息，但关心与自己利益相关的成员
%      - 成员集合随资源交换动态变化，体现真实的社会网络特征
%
% 与全局效用版本的区别：
%   - 全局版本：所有智能体优化全局目标 Σu_i（集中式）
%   - LSU版本：每个智能体优化相关利益群体目标（分布式+利他性）
%   - 特赦差异：全局版本用全局最优，LSU版本用局部社会最优
% ??? [设计理念结束] ???

%% ==================== 0. 随机数种子设置 ====================
if isfield(Value_Params, 'seed')
    rng(Value_Params.seed); % 固定种子以复现实验结果
end

%% ==================== 1. 初始化阶段 ====================
eps_val = 1e-6;          % 浮点数比较容差
history_data = struct(); % 初始化历史记录容器
tabu_tenure = 20;        % 禁忌期限

% --- 初始化智能体核心数据结构 (Value_data) ---
Value_data = WorldSim.init_value_data(agents, tasks, Value_Params);

% --- 初始化观测、信念与邻居信息 ---
[Value_data, summatrix] = WorldSim.init_observe_belief_neighbor(Value_data, Value_Params.N, Value_Params.M, Value_Params);

%% ==================== 2. 主循环：多轮博弈迭代 ====================

for counter = 1:Value_Params.num_rounds

    %% 2.2 SA 初始化 (本轮博弈前的准备)
    k_iter = 1;
    previous_SC = Value_data(1).SC;
    k_stable = 0;
    doneflag = 0;

    % --- 温度调度策略 ---
    Value_Params.Temperature = max(Value_Params.SA_T_base_round, Value_Params.SA_T0_round * Value_Params.SA_beta_round^(counter-1));

    if AddPara.verbose
        fprintf('  [SA-Altruistic] Round %d: 初始温度 = %.2f\n', counter, Value_Params.Temperature);
    end

    % ??? [局部社会效用（LSU）初始化] ???
    % 初始化每个智能体的最优局部社会效用记录
    best_SC = Value_data(1).SC;
    best_coalitionstru = Value_data(1).coalitionstru;
    
    % 初始化个体LSU最优值（每个智能体独立维护）
    best_LSU = zeros(Value_Params.N, 1);
    SC_empty = cell(Value_Params.M, 1);
    for m = 1:Value_Params.M
        SC_empty{m} = zeros(Value_Params.N, Value_Params.K);
    end
    
    for j = 1:Value_Params.N
        % 初始状态的LSU（从空状态到当前状态）
        best_LSU(j) = calculate_local_social_utility(SC_empty, best_SC, j, agents, tasks, Value_Params, Value_data(j), AddPara);
    end
    
    % 同时计算全局效用用于记录（但不用于决策）
    best_utility_global = 0;
    for j = 1:Value_Params.N
        best_utility_global = best_utility_global + UtilityEvaluator.calc_agent_total_utility(best_SC, agents, tasks, Value_Params, Value_data(j), AddPara);
    end
    % ??? [局部社会效用（LSU）初始化结束] ???

    %% ==================== 2.25 初始化禁忌列表 ====================
    tabu_list = {};

    if AddPara.verbose
        fprintf('  [Tabu] 禁忌期限 = %d\n', tabu_tenure);
    end

    %% ==================== 2.3 第一轮特有：生成初始解 (Soft Greedy) ====================
    if counter == 1
        if AddPara.verbose
            fprintf('  [SA] 第1轮：基于低温概率生成初始联盟结构 (Soft Greedy)...\n');
        end

        SC_global = Value_data(1).SC;
        task_type_demands = Value_Params.task_type_demands;
        resource_confidence = Value_Params.SA_resource_confidence;
        T_init_construction = Value_Params.SA_T_init_construction;

        for i = 1:Value_Params.N
            Value_data(i).SC = SC_global;
            [~, resource_gap] = calc_gaps(Value_data(i), Value_Params, AddPara);
            probs = SA_Select_probs(Value_data(i), agents, tasks, Value_Params, resource_gap, T_init_construction);

            for k = 1:Value_Params.K
                resource_amt = agents(i).resources(k);
                if resource_amt <= 0, continue; end

                prob_vec = probs(k, :);
                cum_prob = cumsum(prob_vec);
                if cum_prob(end) > 1e-9
                    r = rand * cum_prob(end);
                    selected_task = find(cum_prob >= r, 1, 'first');
                else
                    selected_task = randi(Value_Params.M);
                end
                if isempty(selected_task), selected_task = randi(Value_Params.M); end

                if SC_global{selected_task}(i, k) > 0, continue; end

                curr_alloc = sum(SC_global{selected_task}(:, k));
                belief = Value_data(i).initbelief(selected_task, :);
                expected_demand = WorldSim.calculate_demand_quantile(belief, task_type_demands, resource_confidence);
                can_add = max(0, expected_demand(k) - curr_alloc);

                if can_add > 0
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
            for j = 1:Value_Params.N, Value_data(j).SC = SC_global; end
        end

        for i = 1:Value_Params.N
            Value_data(i).SC = SC_global;
            Value_data(i).resources_matrix = OCFUtils.get_agent_resource_matrix(SC_global, i, Value_Params);
            Value_data(i).coalitionstru = OCFUtils.build_coalitionstru_from_SC(SC_global, Value_Params, agents);
        end

        best_SC = SC_global;
        best_coalitionstru = Value_data(1).coalitionstru;
        
        % 重新计算初始LSU
        for ii = 1:Value_Params.N
            best_LSU(ii) = calculate_local_social_utility(SC_empty, SC_global, ii, agents, tasks, Value_Params, Value_data(ii), AddPara);
        end
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

    % 初始化当前状态的全局效用（仅用于记录）
    current_utility_global = 0;
    for j = 1:Value_Params.N
        current_utility_global = current_utility_global + UtilityEvaluator.calc_agent_total_utility(Value_data(j).SC, agents, tasks, Value_Params, Value_data(j), AddPara);
    end

    while(doneflag == 0)

        % --- 3.1 顺序博弈 (Sequential Game) - 利他主义决策 ---
        SC_before_inner = Value_data(1).SC;
        utility_before_inner = current_utility_global;

        for ii = 1:Value_Params.N

            % 步骤1: 生成候选解
            [SC_candidate, ~] = generate_candidate_solution_tabu(Value_data(ii), agents, tasks, Value_Params, AddPara);

            % 步骤2: 计算候选解的全局效用（仅用于记录和特赦判断）
            candidate_utility_global = 0;
            Value_data_temp = Value_data;
            for jj = 1:Value_Params.N
                Value_data_temp(jj).SC = SC_candidate;
            end
            for jj = 1:Value_Params.N
                candidate_utility_global = candidate_utility_global + UtilityEvaluator.calc_agent_total_utility(SC_candidate, agents, tasks, Value_Params, Value_data_temp(jj), AddPara);
            end

            % 步骤3: 禁忌判断
            candidate_hash = get_SC_hash(SC_candidate, Value_Params);
            is_tabu = is_in_tabu_list(candidate_hash, tabu_list);

            accept = false;
            accept_reason = '';

            if is_tabu
                % ??? [局部社会效用（LSU）特赦准则] ???
                % 计算当前智能体的局部社会效用
                SC_current = Value_data(ii).SC;
                current_LSU = calculate_local_social_utility(SC_current, SC_candidate, ii, agents, tasks, Value_Params, Value_data(ii), AddPara);
                
                % 特赦条件：当前LSU超过该智能体的历史最优LSU
                if current_LSU > best_LSU(ii)
                    accept = true;
                    accept_reason = 'Tabu-Aspiration-LSU';
                    if AddPara.verbose
                        fprintf('      [Agent %d] LSU特赦接受禁忌解 (LSU=%.2f > 最优=%.2f)\n', ...
                            ii, current_LSU, best_LSU(ii));
                    end
                else
                    accept = false;
                    accept_reason = 'Tabu-Reject';
                    if AddPara.verbose
                        fprintf('      [Agent %d] 拒绝禁忌解 (LSU=%.2f)\n', ii, current_LSU);
                    end
                end
                % ??? [局部社会效用（LSU）特赦准则结束] ???
            else
                % ??? [利他主义Metropolis准则] ???
                % 使用 Preference_gain 计算智能体 ii 的利他偏好差值
                SC_current = Value_data(ii).SC;
                delta_E_altruistic = Preference_gain(tasks, agents, SC_current, SC_candidate, ii, Value_Params, Value_data(ii));
                % ??? [利他主义Metropolis准则结束] ???

                if delta_E_altruistic >= 0  % 利他偏好改进或持平
                    accept = true;
                    accept_reason = 'Metropolis-Improve-Altruistic';
                else  % 利他偏好恶化
                    prob = exp(delta_E_altruistic / Value_Params.Temperature);
                    if rand < prob
                        accept = true;
                        accept_reason = 'Metropolis-Accept-Altruistic';
                        if AddPara.verbose
                            fprintf('      [Agent %d] 概率接受恶化解 (利他ΔE=%.2f, prob=%.4f)\n', ii, delta_E_altruistic, prob);
                        end
                    else
                        accept = false;
                        accept_reason = 'Metropolis-Reject';
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
                current_utility_global = candidate_utility_global;

                % 更新禁忌列表
                if ~is_tabu
                    tabu_list = update_tabu_list(tabu_list, candidate_hash, tabu_tenure);
                end

                % ? 更新个体LSU最优记录
                SC_current = Value_data(ii).SC;  % 更新前的状态
                current_LSU = calculate_local_social_utility(SC_current, SC_candidate, ii, agents, tasks, Value_Params, Value_data(ii), AddPara);
                if current_LSU > best_LSU(ii)
                    best_LSU(ii) = current_LSU;
                    if AddPara.verbose
                        fprintf('      [Agent %d] 更新个体LSU最优 (LSU=%.2f)\n', ii, best_LSU(ii));
                    end
                end
                
                % ? 同时更新全局最优（用于记录）
                if candidate_utility_global > best_utility_global
                    best_utility_global = candidate_utility_global;
                    best_SC = SC_candidate;
                    best_coalitionstru = Value_data(1).coalitionstru;
                    if AddPara.verbose
                        fprintf('      [Agent %d] 更新全局最优解 (全局效用=%.2f)\n', ii, best_utility_global);
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
            Value_Params.Temperature, current_utility_global, best_utility_global, Value_data(1).SC, Value_Params);

        % --- 3.2 完成迭代后的操作 ---
        Value_Params.Temperature = Value_Params.alpha * Value_Params.Temperature;
        final_SC = Value_data(Value_Params.N).SC;
        final_coalitionstru = Value_data(Value_Params.N).coalitionstru;

        % --- 3.2.2 收敛检测 ---
        if isequal(previous_SC, final_SC)
            k_stable = k_stable + 1;
        else
            k_stable = 0;
        end

        if k_stable >= Value_Params.SA_K_len
            doneflag = 1;
        elseif Value_Params.Temperature < Value_Params.Tmin
            doneflag = 1;
        elseif k_iter >= Value_Params.SA_Tabu_K_max_outer
            doneflag = 1;
        end

        previous_SC = final_SC;
        k_iter = k_iter + 1;

        % --- 3.2.3 全网状态同步 ---
        for ii = 1:Value_Params.N
            Value_data(ii).coalitionstru = final_coalitionstru;
            Value_data(ii).SC = final_SC;
            Value_data(ii).resources_matrix = OCFUtils.get_agent_resource_matrix(Value_data(ii).SC, ii, Value_Params);
        end

        if AddPara.verbose
            fprintf('  [SA-Outer] Iter %d: T=%.2f, Utility=%.2f, Best=%.2f\n', ...
                k_iter, Value_Params.Temperature, current_utility_global, best_utility_global);
        end

    end  % end while (外循环)

    % 重新计算并缓存任务时间表
    Value_data = update_task_schedule(Value_data, agents, tasks, Value_Params);

    %% ==================== 4. 观测与信念更新 ====================
    [Value_data, summatrix] = AgentOps.collect_observations(Value_data, agents, tasks, Value_Params, summatrix, final_SC);
    Value_data = AgentOps.update_belief_from_observations(Value_data, Value_Params);

    %% ==================== 5. 结果评估 (客观/上帝视角) ====================
    [coalition_utility, total_global_cost, total_completed_value, task_completion_degrees] = ...
        UtilityEvaluator.evaluate_coalition_metrics(final_SC, agents, tasks, Value_Params, eps_val);

    %% 4.8 信念广播
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

    history_data.inner_loop{counter} = inner_loop_history;
    
    % 记录局部社会效用信息
    history_data.best_LSU{counter} = best_LSU;
end

%% ==================== 6. 结束与最终检查 ====================
if AddPara.verbose
    fprintf('\n[SA_Value_Altruistic] 执行最终一致性检查...\n');
end

[is_valid, error_log] = check_coalition_consistency(Value_data, agents, tasks, Value_Params, 'OCF', AddPara.verbose);

if ~is_valid
    warning('[SA_Value_Altruistic] 一致性检查发现 %d 处问题', length(error_log));
    history_data.consistency_errors = error_log;
else
    if AddPara.verbose
        fprintf('? [SA_Value_Altruistic] 所有一致性检查通过！\n');
    end
end

end

%% ==================== 内部辅助函数 (与原版本相同) ====================

function hash_str = get_SC_hash(SC, Value_Params)
hash_parts = {};
eps_val = 1e-9;

for m = 1:Value_Params.M
    SC_m = SC{m};
    [rows, cols] = find(SC_m > eps_val);
    for idx = 1:length(rows)
        i = rows(idx);
        k = cols(idx);
        amount = SC_m(i, k);
        hash_parts{end+1} = sprintf('%d-%d-%d-%.4f', m, i, k, amount);
    end
end

hash_parts = sort(hash_parts);
if isempty(hash_parts)
    hash_str = 'EMPTY';
else
    hash_str = strjoin_custom(hash_parts, '|');
end
end

function is_tabu = is_in_tabu_list(hash_str, tabu_list)
is_tabu = false;
for i = 1:length(tabu_list)
    if strcmp(tabu_list{i}, hash_str)
        is_tabu = true;
        return;
    end
end
end

function tabu_list = update_tabu_list(tabu_list, hash_str, tabu_tenure)
tabu_list{end+1} = hash_str;
if length(tabu_list) > tabu_tenure
    tabu_list = tabu_list(2:end);
end
end

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

% 获取离开概率参数
if isfield(Value_Params, 'SA_p_leave')
    p_leave = Value_Params.SA_p_leave;
elseif isfield(AddPara, 'p_leave')
    p_leave = AddPara.p_leave;
else
    p_leave = 0.1;
end

SC_temp = SC_current;

for m = 1:M
    for k = 1:K
        if SC_temp{m}(agent_idx, k) > eps_val && rand < p_leave
            removed_amount = SC_temp{m}(agent_idx, k);
            SC_temp{m}(agent_idx, k) = 0;
            if AddPara.verbose
                fprintf('      [离开] Agent #%-2d 撤出任务 M=%-2d | 资源 k=%-2d | 数量: %6.2f\n', ...
                    agent_idx, m, k, removed_amount);
            end
        end
    end
end

Value_data_i.SC = SC_temp;
[~, resource_gap] = calc_gaps(Value_data_i, Value_Params, AddPara);
probs = SA_Select_probs(Value_data_i, agents, tasks, Value_Params, resource_gap, current_T);

SC_new = SC_temp;
task_type_demands = Value_Params.task_type_demands;

for k = 1:K
    resource_amt = agents(agent_idx).resources(k);
    if resource_amt <= eps_val, continue; end

    prob_vec = probs(k, :);
    cum_prob = cumsum(prob_vec);
    if cum_prob(end) > eps_val
        r = rand * cum_prob(end);
        selected_task = find(cum_prob >= r, 1, 'first');
    else
        selected_task = randi(M);
    end
    if isempty(selected_task), selected_task = randi(M); end

    if SC_new{selected_task}(agent_idx, k) > eps_val
        if AddPara.verbose
            fprintf('      [状态保持] Agent #%-2d 资源 k=%-2d 已在任务 M=%-2d 中\n', ...
                agent_idx, k, selected_task);
        end
        continue;
    end

    curr_alloc = sum(SC_new{selected_task}(:, k));
    belief = Value_data_i.initbelief(selected_task, :);
    expected_demand = WorldSim.calculate_demand_quantile(belief, task_type_demands, confidence);
    demand_k = expected_demand(k);
    can_add = max(0, demand_k - curr_alloc);

    if can_add > eps_val
        SC_candidate_temp = SC_new;
        SC_candidate_temp{selected_task}(agent_idx, k) = resource_amt;
        Value_data_array = repmat(Value_data_i, Value_Params.N, 1);
        for j = 1:Value_Params.N
            Value_data_array(j).agentIndex = j;
            Value_data_array(j).SC = SC_candidate_temp;
        end

        [isFeasible, info, ~] = validate_feasibility(Value_data_array, agents, tasks, ...
            Value_Params, agent_idx, SC_candidate_temp, true, AddPara);

        if isFeasible
            SC_new = SC_candidate_temp;
            if AddPara.verbose
                fprintf('      [资源投入] Agent #%-2d -> 任务 M=%-2d | 资源 k=%-2d | 数量: %6.2f ?\n', ...
                    agent_idx, selected_task, k, resource_amt);
            end
        else
            if AddPara.verbose
                fprintf('      [拒绝投入] Agent #%-2d -> 任务 M=%-2d | 资源 k=%-2d | 原因: %s ?\n', ...
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

SC_candidate = SC_new;
move_description = sprintf('SA_Tabu_Altruistic_Agent_%d', agent_idx);
end

function LSU = calculate_local_social_utility(SC_old, SC_candidate, agent_idx, agents, tasks, Value_Params, Value_data, AddPara)
% CALCULATE_LOCAL_SOCIAL_UTILITY 计算局部社会效用（Local Social Utility, LSU）
%
% LSU 定义：智能体 i 相关利益群体在 SC_candidate 状态下的效用总和，包括：
%   1. 智能体 i 自身
%   2. 旧联盟成员：在 SC_old 中与 i 共同承担任务、但 i 在 SC_candidate 中撤出或减少资源的任务队友
%   3. 新联盟成员：在 SC_candidate 中与 i 共同承担任务、且 i 增加了资源投入的任务队友
%
% 输入：
%   SC_old       : 旧联盟结构（当前状态）
%   SC_candidate : 新联盟结构（候选状态）
%   agent_idx    : 智能体索引
%   agents       : 智能体数据
%   tasks        : 任务数据
%   Value_Params : 参数结构
%   Value_data   : 智能体信念数据
%   AddPara      : 附加参数
%
% 输出：
%   LSU : 局部社会效用（所有相关成员在 SC_candidate 状态下的效用总和）

    eps_val = 1e-6;
    
    %% ==================== 1. 识别受影响的任务 ====================
    % 找出所有资源投入发生变化的任务
    affected_tasks_old = [];  % 旧联盟任务（资源减少或撤出）
    affected_tasks_new = [];  % 新联盟任务（资源增加）
    
    for m = 1:Value_Params.M
        % 计算智能体在该任务上的资源总投入
        old_investment = sum(SC_old{m}(agent_idx, :));
        new_investment = sum(SC_candidate{m}(agent_idx, :));
        
        if old_investment > eps_val && new_investment < old_investment - eps_val
            % 资源减少或完全撤出
            affected_tasks_old = [affected_tasks_old, m];
        end
        
        if new_investment > old_investment + eps_val
            % 资源增加
            affected_tasks_new = [affected_tasks_new, m];
        end
    end
    
    %% ==================== 2. 提取所有相关成员（去重） ====================
    related_members = [];
    
    % 2.1 提取旧联盟成员（排除自己）
    for m = affected_tasks_old
        members = OCFUtils.get_participants(SC_old, m, eps_val);
        members(members == agent_idx) = [];  % 排除自己
        if ~isempty(members)
            related_members = [related_members, members(:)'];  % 确保转换为行向量
        end
    end
    
    % 2.2 提取新联盟成员（排除自己）
    for m = affected_tasks_new
        members = OCFUtils.get_participants(SC_candidate, m, eps_val);
        members(members == agent_idx) = [];  % 排除自己
        if ~isempty(members)
            related_members = [related_members, members(:)'];  % 确保转换为行向量
        end
    end
    
    % 2.3 去重（确保每个成员只计算一次）
    related_members = unique(related_members);
    
    %% ==================== 3. 计算LSU ====================
    % LSU = 自身效用 + 所有相关队友的效用（在 SC_candidate 状态下）
    
    % 3.1 计算自身效用
    Value_data_temp = Value_data;
    Value_data_temp.SC = SC_candidate;
    self_utility = UtilityEvaluator.calc_agent_total_utility(SC_candidate, agents, tasks, Value_Params, Value_data_temp, AddPara);
    
    % 3.2 计算所有相关队友的效用
    teammates_utility = 0;
    for k = 1:length(related_members)
        teammate_id = related_members(k);
        
        % 获取队友的信念
        if isfield(Value_data, 'other') && length(Value_data.other) >= teammate_id && ~isempty(Value_data.other{teammate_id})
            teammate_belief = Value_data.other{teammate_id}.initbelief;
        else
            % 兜底：假设队友和我有相同信念
            teammate_belief = Value_data.initbelief;
        end
        
        % 构造临时数据结构
        temp_data.agentIndex = teammate_id;
        temp_data.initbelief = teammate_belief;
        temp_data.SC = SC_candidate;
        
        % 计算队友在候选解下的效用
        teammate_utility = UtilityEvaluator.calc_agent_total_utility(SC_candidate, agents, tasks, Value_Params, temp_data, AddPara);
        teammates_utility = teammates_utility + teammate_utility;
    end
    
    % 3.3 汇总LSU
    LSU = self_utility + teammates_utility;
    
    % 调试输出（可选）
    % fprintf('  [LSU Agent %d] Self=%.2f, Teammates=%.2f (count=%d), Total=%.2f\n', ...
    %     agent_idx, self_utility, teammates_utility, length(related_members), LSU);
end
