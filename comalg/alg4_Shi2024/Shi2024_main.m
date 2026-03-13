function [Value_data, history_data] = Shi2024_main(agents, tasks, AddPara, Value_Params)
% SHI2024_MAIN Overlapping Coalition Formation (OCF) Algorithm
% 基于重叠联盟形成的任务分配算法
%
% 算法流程：
%   多轮迭代，每轮包括：
%   1. 联盟形成（初始化或优化）
%   2. 观测收集
%   3. 信念更新（可选）
%
% 输入:
%   agents       - 智能体结构体数组
%   tasks        - 任务结构体数组
%   AddPara      - 附加参数（包含信念更新开关）
%   Value_Params - 全局参数
%
% 输出:
%   Value_data   - 最终的智能体数据结构
%   history_data - 历史数据记录

if AddPara.verbose
    fprintf('\n=== Shi2024 OCF Algorithm Start ===\n');
end
if isfield(Value_Params, 'seed'), rng(Value_Params.seed); end

%% 参数初始化
N = Value_Params.N;
M = Value_Params.M;
K = Value_Params.K;
tol = 1e-9;
num_rounds = Value_Params.num_rounds;

% 信念更新开关
enable_belief_update = false;
if isfield(AddPara, 'enable_belief_update')
    enable_belief_update = AddPara.enable_belief_update;
end

if AddPara.verbose
    fprintf('Belief update: %s\n', mat2str(enable_belief_update));
    fprintf('Agents: %d, Tasks: %d, Resources: %d, Rounds: %d\n', N, M, K, num_rounds);
end

%% 初始化数据结构
Value_data = WorldSim.init_value_data(agents, tasks, Value_Params);

% 初始化全局联盟结构 SC
SC = cell(M, 1);
for m = 1:M
    SC{m} = zeros(N, K);
end

% 历史数据记录
history_data = struct();
history_data.rounds = struct('round_num', {}, 'coalition_utility', {}, ...
    'total_global_cost', {}, 'total_completed_value', {}, ...
    'task_completion_degrees', {}, 'SC', {}, 'coalitionstru', {}, ...
    'summatrix', {}, 'beliefs', {});

% 观测数据累积矩阵
summatrix = zeros(M, Value_Params.task_type);

%% 多轮迭代
for round = 1:num_rounds
    if AddPara.verbose
        fprintf('\n========== Round %d/%d ==========\n', round, num_rounds);
    end

    %% Step 1: 联盟形成
    if round == 1
        % 第一轮：初始化策略
        if AddPara.verbose
            fprintf('--- Initial Coalition Formation ---\n');
        end
        [SC, k_iter] = initial_coalition_formation(N, M, SC, agents, tasks, Value_Params, Value_data, AddPara, tol);
    else
        % 后续轮：迭代优化
        if AddPara.verbose
            fprintf('--- Coalition Optimization ---\n');
        end
        [SC, k_iter] = optimize_coalitions(N, M, SC, agents, tasks, Value_Params, Value_data, AddPara, tol);
    end

    % 更新 Value_data 中的 SC
    for i = 1:N
        Value_data(i).SC = SC;

        % 更新 resources_matrix
        for j = 1:M
            Value_data(i).resources_matrix(j, :) = SC{j}(i, :);
        end

        % 更新 coalitionstru（使用统一的构建函数）
        Value_data(i).coalitionstru = OCFUtils.build_coalitionstru_from_SC(SC, Value_Params, agents);
    end

    %% Step 2: 观测收集
    if enable_belief_update
        [Value_data, summatrix] = AgentOps.collect_observations(Value_data, agents, tasks, Value_Params, summatrix, SC);
    end

    %% Step 3: 记录历史数据
    history_data = record_round_data(history_data, round, SC, Value_data, agents, tasks, Value_Params, AddPara, summatrix, tol);

    % 记录本轮的内循环迭代次数
    history_data.k_iter_per_round{round} = k_iter;

    %% Step 4: 信念更新
    if enable_belief_update && round < num_rounds
        Value_data = AgentOps.update_belief_from_observations(Value_data, Value_Params);
        if AddPara.verbose
            fprintf('Beliefs updated for next round.\n');
        end
    end
end

%% 最终结果处理
if AddPara.verbose
    fprintf('\n=== Final Results ===\n');
end

% 计算每个智能体的最终效用和成本
all_agents_results = WorldSim.calc_all_agents_with_global_sync(agents, tasks, Value_Params, SC, tol);
for i = 1:N
    Value_data(i).SC = SC;

    % 获取任务列表
    task_list = OCFUtils.get_agent_tasks_fast(SC, i, tol);
    task_list = task_list(task_list <= M);

    if ~isempty(task_list)
        Value_data(i).task_schedule.task_sequence = all_agents_results(i).task_sequence;

        % 使用批量计算的结果
        Value_data(i).task_schedule.total_flight_time = all_agents_results(i).t_fly_total;
        Value_data(i).task_schedule.total_execution_time = all_agents_results(i).t_exec_total;
        Value_data(i).task_schedule.start_times = all_agents_results(i).start_times;
        Value_data(i).task_schedule.execution_times = all_agents_results(i).execution_times;
        Value_data(i).task_schedule.completion_times = all_agents_results(i).completion_times;
        Value_data(i).task_schedule.mission_end_time = all_agents_results(i).mission_end_time;

        % 计算总能量消耗
        alpha_fly = agents(i).fuel;
        alpha_wait = agents(i).wait_fuel;
        beta = agents(i).beta;
        E_total = alpha_fly * all_agents_results(i).t_fly_total ...
            + alpha_wait * all_agents_results(i).t_wait_total ...
            + beta * all_agents_results(i).t_exec_total;
        Value_data(i).task_schedule.total_energy = E_total;

        if AddPara.verbose
            fprintf('Agent %d: Tasks=%d, Utility=%.2f, Energy=%.2f\n', ...
                i, length(task_list), ...
                UtilityEvaluator.calc_agent_total_utility(SC, agents, tasks, Value_Params, Value_data(i), AddPara), ...
                E_total);
        end
    end
end

% 全局统计
total_utility = calc_global_utility(SC, agents, tasks, Value_Params, Value_data, AddPara);
if AddPara.verbose
    fprintf('\nGlobal Total Utility: %.2f\n', total_utility);
    fprintf('Total Rounds: %d\n', num_rounds);
end

%% 最终一致性检查（使用统一的检查函数）
if AddPara.verbose
    fprintf('\n[Shi2024] 执行最终一致性检查...\n');
end
[is_valid, error_log] = check_coalition_consistency(Value_data, agents, tasks, Value_Params, 'OCF', AddPara.verbose);

if ~is_valid
    warning('[Shi2024] 联盟一致性检查发现 %d 处问题，请查看上方日志！', length(error_log));
    % 将错误日志保存到历史数据中以便后续分析
    history_data.consistency_errors = error_log;
else
    if AddPara.verbose
        fprintf('✅ [Shi2024] 所有一致性检查通过！\n');
    end
end

if AddPara.verbose
    fprintf('\n=== Shi2024 OCF Algorithm End ===\n\n');
end

end


%% ========== 主要函数 ==========

function [SC, k_iter] = initial_coalition_formation(N, M, SC, agents, tasks, Value_Params, Value_data, AddPara, tol)
% 初始化联盟形成：每个智能体选择最大效用的任务
% 基于贪婪算法形成一个初始解
% 返回联盟结构 SC 和迭代次数 k_iter = 1（因为是一次性构建）

for j = 1:N
    best_task = -1;
    best_utility = -inf;
    best_cost_data = [];

    % 遍历所有任务
    for i = 1:M
        % 创建临时 SC
        SC_temp = SC;
        SC_temp{i}(j, :) = agents(j).resources';

        % 获取资源分配矩阵
        R_agent_Q = zeros(M, Value_Params.K);
        task_list_temp = OCFUtils.get_agent_tasks_fast(SC_temp, j, tol);
        for idx = 1:length(task_list_temp)
            t = task_list_temp(idx);
            if t <= M
                R_agent_Q(t, :) = SC_temp{t}(j, :);
            end
        end

        % 验证可行性（启用队友检查）
        [isFeasible, ~, cost_data] = validate_feasibility(Value_data, agents, tasks, Value_Params, j, SC_temp, true, AddPara);

        if ~isFeasible
            continue;
        end

        % 计算加入后的总效用
        utility = UtilityEvaluator.calc_agent_total_utility(SC_temp, agents, tasks, Value_Params, Value_data(j), AddPara);

        if utility > best_utility
            best_utility = utility;
            best_task = i;
            best_cost_data = cost_data;
        end
    end

    % 加入最佳任务
    if best_task > 0 && best_utility > 0
        SC{best_task}(j, :) = agents(j).resources';
        if AddPara.verbose
            fprintf('  Agent %d joins Task %d (utility: %.2f, energy: %.2f)\n', ...
                j, best_task, best_utility, best_cost_data.requiredEnergy);
        end
    end
end

% 初始化联盟形成是一次性过程，迭代次数为 1
k_iter = 1;

end


function [SC, k_iter] = optimize_coalitions(N, M, SC, agents, tasks, Value_Params, Value_data, AddPara, tol)
% 迭代优化联盟结构 (解耦式：基于单种资源的细粒度调度)
k_iter = 0;  % 内循环迭代计数器
k_stable = 0;  % 稳定性计数器
max_iterations = Value_Params.max_inner_iter;      
K_len = Value_Params.Shi_K_stable_max;             
K_resources = Value_Params.K; % 获取资源种类总数
L_tabu = Value_Params.Qi_L_tabu;           % 禁忌表长度（与 Qi2023 共用参数）

% 探索阶段使用静默模式，避免大量"试错"日志淹没有效信息
AddPara_silent = AddPara;
AddPara_silent.verbose = false;

% 禁忌表（跨迭代累积，避免重复访问相同 SC 状态）
TabuList = {};

while k_iter < max_iterations && k_stable < K_len
    k_iter = k_iter + 1;
    SC_prev_iter = SC;
    if AddPara.verbose
        fprintf('  Iteration %d:\n', k_iter);
    end
    
    %% Phase 1: Quit/Transfer (利他偏好增益判断，单种资源粒度)
    for j = 1:N
        Value_data(j).SC = SC;  % 确保信念数据同步
        task_list = OCFUtils.get_agent_tasks_fast(SC, j, tol);
        task_list = task_list(task_list <= M);

        for task_idx = 1:length(task_list)
            task_p = task_list(task_idx);

            for k = 1:K_resources
                if SC{task_p}(j, k) > tol
                    SC_quit = SC;
                    SC_quit{task_p}(j, k) = 0;

                    % 【Transfer 独立评估】以当前 SC 为基准，遍历所有目标任务
                    best_transfer_task = -1;
                    best_transfer_gain = 0;  % 必须严格 > 0 才接受

                    for i_trans = 1:M
                        if i_trans == task_p, continue; end
                        if SC_quit{i_trans}(j, k) > tol, continue; end

                        SC_temp = SC_quit;
                        SC_temp{i_trans}(j, k) = agents(j).resources(k);

                        [isFeasible_trans, ~, ~] = validate_feasibility(Value_data, agents, tasks, Value_Params, j, SC_temp, true, AddPara_silent);
                        if isFeasible_trans
                            % 利他偏好增益：SC(当前) → SC_temp(转移后)
                            gain_transfer = Preference_gain(tasks, agents, SC, SC_temp, j, Value_Params, Value_data(j));
                            if gain_transfer > best_transfer_gain
                                best_transfer_gain = gain_transfer;
                                best_transfer_task = i_trans;
                            end
                        end
                    end

                    % 计算单纯退出的利他增益
                    gain_quit = Preference_gain(tasks, agents, SC, SC_quit, j, Value_Params, Value_data(j));

                    % 结算优先级：Transfer > Quit > 不动（禁忌检查）
                    if best_transfer_task > 0
                        SC_cand = SC_quit;
                        SC_cand{best_transfer_task}(j, k) = agents(j).resources(k);
                        SC_hash = get_SC_hash(SC_cand);
                        if ~is_in_tabu(SC_hash, TabuList)
                            if AddPara.verbose
                                fprintf('    Agent %d: Transfer Task %d->%d [Res %d] (gain=%.4f)\n', j, task_p, best_transfer_task, k, best_transfer_gain);
                            end
                            SC = SC_cand;
                            Value_data(j).SC = SC;
                            TabuList = update_tabu_list(TabuList, SC_hash, L_tabu);
                        end
                    elseif gain_quit > 0
                        SC_hash = get_SC_hash(SC_quit);
                        if ~is_in_tabu(SC_hash, TabuList)
                            if AddPara.verbose
                                fprintf('    Agent %d: Quit Task %d [Res %d] (gain=%.4f)\n', j, task_p, k, gain_quit);
                            end
                            SC = SC_quit;
                            Value_data(j).SC = SC;
                            TabuList = update_tabu_list(TabuList, SC_hash, L_tabu);
                        end
                    end
                    % else: 保持不动
                end
            end
        end
    end

    %% Phase 2: Join 新任务 (利他偏好增益判断，概率加权任务顺序)
    for j = 1:N
        Value_data(j).SC = SC;

        % 计算资源缺口与概率分布
        [~, resource_gap] = calc_gaps(Value_data(j), Value_Params, AddPara);
        T_explore = Value_Params.T0_round;
        probs = SA_Select_probs(Value_data(j), agents, tasks, Value_Params, resource_gap, T_explore);

        for k = 1:K_resources
            if agents(j).resources(k) <= tol, continue; end

            % 确定性概率降序排列
            prob_k = probs(k, :);
            [~, task_order] = sort(-(prob_k * (M + 1) + (M:-1:1)));

            for i_idx = 1:M
                i = task_order(i_idx);
                if SC{i}(j, k) >= tol, continue; end  % 资源已投入，跳过

                SC_join = SC;
                SC_join{i}(j, k) = agents(j).resources(k);

                [isFeasible, ~, cost_data] = validate_feasibility(Value_data, agents, tasks, Value_Params, j, SC_join, true, AddPara_silent);
                if ~isFeasible, continue; end

                % 利他偏好增益：SC(当前) → SC_join(加入后)
                gain_join = Preference_gain(tasks, agents, SC, SC_join, j, Value_Params, Value_data(j));
                if gain_join > 0
                    SC_hash = get_SC_hash(SC_join);
                    if ~is_in_tabu(SC_hash, TabuList)
                        if AddPara.verbose
                            fprintf('    Agent %d: Join Task %d [Res %d] (gain=%.4f, energy=%.2f)\n', ...
                                j, i, k, gain_join, cost_data.requiredEnergy);
                        end
                        SC{i}(j, k) = agents(j).resources(k);
                        Value_data(j).SC = SC;
                        TabuList = update_tabu_list(TabuList, SC_hash, L_tabu);
                    end
                end
            end
        end
    end
    
    %% 检查收敛和稳定性
    if isequal_SC(SC, SC_prev_iter)
        k_stable = k_stable + 1;
        if AddPara.verbose
            fprintf('  No change in iteration %d (stable count: %d/%d).\n', k_iter, k_stable, K_len);
        end
        if k_stable >= K_len
            if AddPara.verbose
                fprintf('  Converged after %d iterations (stability threshold reached).\n', k_iter);
            end
            break;
        end
    else
        k_stable = 0;  % 有改进，重置计数器
    end
end
end


function equal = isequal_SC(SC1, SC2)
% 比较两个 SC 是否完全相等
if length(SC1) ~= length(SC2)
    equal = false;
    return;
end
equal = true;
for i = 1:length(SC1)
    if ~isequal(SC1{i}, SC2{i})
        equal = false;
        return;
    end
end
end


function hash_str = get_SC_hash(SC)
% GET_SC_HASH 计算联盟结构的哈希字符串，用于禁忌检查
temp_vec = [];
for m = 1:length(SC)
    temp_vec = [temp_vec; SC{m}(:)]; %#ok<AGROW>
end
hash_str = mat2str(temp_vec);
end


function is_in = is_in_tabu(sc_hash, tabu_list)
% IS_IN_TABU 检查当前 SC 状态是否在禁忌表中
is_in = false;
for i = 1:length(tabu_list)
    if strcmp(sc_hash, tabu_list{i})
        is_in = true;
        return;
    end
end
end


function tabu_list = update_tabu_list(tabu_list, sc_hash, L_tabu)
% UPDATE_TABU_LIST 更新禁忌表（FIFO 队列，超出长度时移除最旧条目）
tabu_list{end+1} = sc_hash;
if length(tabu_list) > L_tabu
    tabu_list(1) = [];
end
end


function history_data = record_round_data(history_data, round, SC, Value_data, agents, tasks, Value_Params, AddPara, summatrix, tol)
% 记录每轮的历史数据

N = Value_Params.N;
M = Value_Params.M;
K = Value_Params.K;

% 计算全局效用和成本
total_utility = calc_global_utility(SC, agents, tasks, Value_Params, Value_data, AddPara);
total_global_cost = 0;

for i = 1:N
    agent_cost = calc_agent_cost(i, SC, agents, tasks, Value_Params, tol);
    total_global_cost = total_global_cost + agent_cost;
end

% 计算任务完成度
task_completion_degrees = zeros(M, 1);
total_completed_value = 0;
confidence = Value_Params.resource_confidence;  % 统一使用 Value_Params.resource_confidence

for j = 1:M
    belief = Value_data(1).initbelief(j, :);
    demand = WorldSim.calculate_demand_quantile(belief, Value_Params.task_type_demands, confidence);
    participants = OCFUtils.get_participants(SC, j, tol);
    if ~isempty(participants)
        total_resources = sum(SC{j}(participants, :), 1);
        D_C = WorldSim.calc_task_completion_degree(total_resources, demand, K);
        task_completion_degrees(j) = D_C;
        if D_C > tol
            total_completed_value = total_completed_value + tasks(j).value * D_C;
        end
    end
end

% 构建 coalitionstru（使用统一的构建函数）
final_coalitionstru = OCFUtils.build_coalitionstru_from_SC(SC, Value_Params, agents);

% 记录信念
belief_snapshot = zeros(N, M, Value_Params.task_type);
for i = 1:N
    belief_snapshot(i, :, :) = Value_data(i).initbelief(1:M, :);
end

% 使用 ResultProcessor 记录
history_data = ResultProcessor.record_history_data(history_data, round, Value_data, Value_Params, ...
    SC, final_coalitionstru, total_utility, total_global_cost, ...
    total_completed_value, task_completion_degrees, summatrix);

if AddPara.verbose
    fprintf('  Round %d: Utility=%.2f, Cost=%.2f, Completed=%.2f\n', ...
        round, total_utility, total_global_cost, total_completed_value);
end

end


function total_utility = calc_global_utility(SC, agents, tasks, Value_Params, Value_data, AddPara)
% 计算全局总效用

N = Value_Params.N;
total_utility = 0;

for i = 1:N
    agent_utility = UtilityEvaluator.calc_agent_total_utility(SC, agents, tasks, Value_Params, Value_data(i), AddPara);
    total_utility = total_utility + agent_utility;
end

end


function cost = calc_agent_cost(agent_id, SC, agents, tasks, Value_Params, tol)
% 计算智能体的总成本

task_list = OCFUtils.get_agent_tasks_fast(SC, agent_id, tol);
task_list = task_list(task_list <= Value_Params.M);

if isempty(task_list)
    cost = 0;
    return;
end

ordered_tasks = OCFUtils.sort_tasks_by_priority(task_list, tasks);

[t_fly, t_wait, t_exec] = WorldSim.calc_with_global_sync(...
    agent_id, ordered_tasks, agents, tasks, Value_Params, SC, tol);

alpha_fly = agents(agent_id).fuel;
alpha_wait = agents(agent_id).wait_fuel;
beta = agents(agent_id).beta;

cost = alpha_fly * t_fly + alpha_wait * t_wait + beta * t_exec;

end
