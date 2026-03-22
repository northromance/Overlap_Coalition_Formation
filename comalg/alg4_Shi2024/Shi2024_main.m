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
%                  verbose: 0=静默 1=轮次进度 2=迭代进度 3=详细
%   Value_Params - 全局参数
%
% 输出:
%   Value_data   - 最终的智能体数据结构
%   history_data - 历史数据记录

if AddPara.verbose >= 1
    fprintf('\n=== Shi2024 OCF Algorithm Start ===\n');
end
if isfield(Value_Params, 'seed'), rng(Value_Params.seed); end

%% 参数初始化
N = Value_Params.N;
M = Value_Params.M;
K = Value_Params.K;
tol = 1e-9;
num_rounds = Value_Params.num_rounds;

% 信念更新开关（默认开启，与 Qi2023/OCF_SAtabu 对齐）
enable_belief_update = true;
if isfield(AddPara, 'enable_belief_update')
    enable_belief_update = AddPara.enable_belief_update;
end

if AddPara.verbose >= 2
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
    if AddPara.verbose >= 1
        fprintf('\n[Shi2024] === 第 %d/%d 轮 ===\n', round, num_rounds);
    end

    %% Step 1: 联盟形成
    if round == 1
        % 第一轮：初始化策略
        if AddPara.verbose >= 2
            fprintf('--- Initial Coalition Formation ---\n');
        end
        [SC, k_iter] = initial_coalition_formation(N, M, SC, agents, tasks, Value_Params, Value_data, AddPara, tol);
    else
        % 后续轮：迭代优化
        if AddPara.verbose >= 2
            fprintf('--- Coalition Optimization ---\n');
        end
        [SC, k_iter] = optimize_coalitions(N, M, SC, agents, tasks, Value_Params, Value_data, AddPara, tol);
    end

    % 更新 Value_data 中的 SC
    for i = 1:N
        Value_data(i).SC = SC;

        % 更新 resources_matrix
        for j = 1:M
            Value_data(i).resources_matrix(j, :) = SC{j}(i, :); % 第j个任务 然后第i个智能体分配了多少
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
        if AddPara.verbose >= 2
            fprintf('Beliefs updated for next round.\n');
        end
    end
end

%% 最终结果处理
if AddPara.verbose >= 2
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

        if AddPara.verbose >= 3
            fprintf('Agent %d: Tasks=%d, Utility=%.2f, Energy=%.2f\n', ...
                i, length(task_list), ...
                UtilityEvaluator.calc_agent_total_utility(SC, agents, tasks, Value_Params, Value_data(i), AddPara), ...
                E_total);
        end
    end
end

% 全局统计
if AddPara.verbose >= 2
    [total_utility, ~, ~, ~] = UtilityEvaluator.evaluate_coalition_metrics(SC, agents, tasks, Value_Params, tol);
    fprintf('\nGlobal Total Utility: %.2f\n', total_utility);
    fprintf('Total Rounds: %d\n', num_rounds);
end

%% 最终一致性检查（使用统一的检查函数）
if AddPara.verbose >= 2
    fprintf('\n[Shi2024] 执行最终一致性检查...\n');
end
[is_valid, error_log] = check_coalition_consistency(Value_data, agents, tasks, Value_Params, 'OCF', AddPara.verbose >= 2);

if ~is_valid
    warning('[Shi2024] 联盟一致性检查发现 %d 处问题，请查看上方日志！', length(error_log));
    % 将错误日志保存到历史数据中以便后续分析
    history_data.consistency_errors = error_log;
else
    if AddPara.verbose >= 2
        fprintf('[Shi2024] 所有一致性检查通过！\n');
    end
end

if AddPara.verbose >= 1
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

    % 加入最佳任务（只要可行任务存在即加入，允许负效用，后续迭代可通过Quit退出）
    if best_task > 0
        SC{best_task}(j, :) = agents(j).resources';
        if AddPara.verbose >= 3
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
Gamma = Value_Params.Qi_Gamma_init;        % Boltzmann 系数（每轮重置，与 Qi2023 对齐）
Gamma_max = Value_Params.Qi_Gamma_max;     % Boltzmann 系数上限

% 探索阶段使用静默模式，避免大量"试错"日志淹没有效信息
AddPara_silent = AddPara;
AddPara_silent.verbose = 0;

% 禁忌表：containers.Map（O(1) 查找）+ FIFO 队列（限制表长）
tabu_map = containers.Map('KeyType','double','ValueType','logical');
tabu_queue = {};  % 按插入顺序记录 key，用于 FIFO 淘汰

while k_iter < max_iterations && k_stable < K_len
    k_iter = k_iter + 1;
    SC_prev_iter = SC;
    if AddPara.verbose >= 2
        fprintf('  Iteration %d:\n', k_iter);
    end

    %% 遍历每个智能体：Leave + Transfer + Join 在工作副本上完成，最终增益门控后广播（与 Qi2023 对齐）
    for j = 1:N
        Value_data(j).SC = SC;
        SC_working = SC;  % agent j 的工作副本，三步操作均在此副本上累积

        % --- A. 随机退出操作：修改工作副本，不广播 ---
        p_leave = Value_Params.p_leave;
        for m = 1:M
            for k = 1:K_resources
                if SC_working{m}(j, k) > tol && rand < p_leave
                    if AddPara.verbose >= 3
                        fprintf('    Agent %d: Leave Task %d [Res %d]\n', j, m, k);
                    end
                    SC_working{m}(j, k) = 0;
                end
            end
        end

        % --- B. 预计算概率分布（基于退出后的工作副本）---
        Value_data(j).SC = SC_working;
        [~, resource_gap] = calc_gaps(Value_data(j), Value_Params, AddPara);
        probs_j = Qi2023_Select_probs(Value_data(j), agents, tasks, Value_Params, resource_gap, Gamma);

        % --- C. Transfer：在工作副本上操作，增益与工作副本比较，不广播 ---
        task_list = OCFUtils.get_agent_tasks_fast(SC_working, j, tol);
        task_list = task_list(task_list <= M);

        for task_idx = 1:length(task_list)
            task_p = task_list(task_idx);

            for k = 1:K_resources
                if SC_working{task_p}(j, k) <= tol, continue; end

                SC_quit = SC_working;
                SC_quit{task_p}(j, k) = 0;

                % 按概率采样目标任务（排除当前任务和已有资源k的任务）
                prob_k = probs_j(k, :);
                prob_k(task_p) = 0;
                for i_excl = 1:M
                    if SC_quit{i_excl}(j, k) > tol
                        prob_k(i_excl) = 0;
                    end
                end

                target_task = sample_from_probs(prob_k);
                if target_task <= 0, continue; end

                SC_cand = SC_quit;
                SC_cand{target_task}(j, k) = agents(j).resources(k);

                [isFeasible_trans, ~, ~] = validate_feasibility(Value_data, agents, tasks, Value_Params, j, SC_cand, true, AddPara_silent);
                if ~isFeasible_trans, continue; end

                % 增益基准：工作副本（含 Leave 累积状态）
                Value_data(j).SC = SC_working;
                gain_transfer = Preference_gain(tasks, agents, SC_working, SC_cand, j, Value_Params, Value_data(j));
                if gain_transfer > 0
                    SC_hash = get_SC_hash(SC_cand);
                    if ~is_in_tabu(SC_hash, tabu_map)
                        if AddPara.verbose >= 3
                            fprintf('    Agent %d: Transfer Task %d->%d [Res %d] (gain=%.4f)\n', j, task_p, target_task, k, gain_transfer);
                        end
                        SC_working = SC_cand;  % 更新工作副本，不广播
                        tabu_queue = update_tabu_list(tabu_map, tabu_queue, SC_hash, L_tabu);
                        % 【优化5】增量更新 resource_gap（替代全量 calc_gaps）
                        % Transfer: task_p 释放资源k，target_task 获得资源k
                        resource_gap(task_p, k) = resource_gap(task_p, k) + agents(j).resources(k);
                        resource_gap(target_task, k) = resource_gap(target_task, k) - agents(j).resources(k);
                        Value_data(j).SC = SC_working;
                        probs_j = Qi2023_Select_probs(Value_data(j), agents, tasks, Value_Params, resource_gap, Gamma);
                    end
                end
            end
        end

        % --- D. Join：在工作副本上操作，增益与工作副本比较，不广播 ---
        for k = 1:K_resources
            if agents(j).resources(k) <= tol, continue; end

            % 按概率采样目标任务（排除已有资源k的任务）
            prob_k = probs_j(k, :);
            for i_excl = 1:M
                if SC_working{i_excl}(j, k) >= tol
                    prob_k(i_excl) = 0;
                end
            end

            target_task = sample_from_probs(prob_k);
            if target_task <= 0, continue; end

            SC_join = SC_working;
            SC_join{target_task}(j, k) = agents(j).resources(k);

            [isFeasible, ~, cost_data] = validate_feasibility(Value_data, agents, tasks, Value_Params, j, SC_join, true, AddPara_silent);
            if ~isFeasible, continue; end

            % 增益基准：工作副本（含 Leave + Transfer 累积状态）
            Value_data(j).SC = SC_working;
            gain_join = Preference_gain(tasks, agents, SC_working, SC_join, j, Value_Params, Value_data(j));
            if gain_join > 0
                SC_hash = get_SC_hash(SC_join);
                if ~is_in_tabu(SC_hash, tabu_map)
                    if AddPara.verbose >= 3
                        fprintf('    Agent %d: Join Task %d [Res %d] (gain=%.4f, energy=%.2f)\n', ...
                            j, target_task, k, gain_join, cost_data.requiredEnergy);
                    end
                    SC_working = SC_join;  % 更新工作副本，不广播
                    tabu_queue = update_tabu_list(tabu_map, tabu_queue, SC_hash, L_tabu);
                end
            end
        end

        % --- E. 最终增益门控：SC_working 整体优于本轮初始 SC 才接受广播（与 Qi2023 step D 对齐）---
        % 对比基准是 agent j 本轮开始时的 SC（SC_working 初始化自此，Leave/Transfer/Join 前未变）
        Value_data(j).SC = SC_working;
        final_gain = Preference_gain(tasks, agents, SC, SC_working, j, Value_Params, Value_data(j));
        if final_gain > 0
            SC = SC_working;
            for ii = 1:N
                Value_data(ii).SC = SC;
            end
        else
            % 拒绝：整体不优于起始状态，SC 不变，只恢复 agent j 的视图
            Value_data(j).SC = SC;
        end

    end  % end for j

    %% 检查收敛和稳定性
    if isequal_SC(SC, SC_prev_iter)
        k_stable = k_stable + 1;
        if AddPara.verbose >= 2
            fprintf('  No change in iteration %d (stable count: %d/%d).\n', k_iter, k_stable, K_len);
        end
        if k_stable >= K_len
            if AddPara.verbose >= 2
                fprintf('  Converged after %d iterations (stability threshold reached).\n', k_iter);
            end
            break;
        end
    else
        k_stable = 0;  % 有改进，重置计数器
    end

    % 更新 Boltzmann 系数（与 Qi2023 对齐）
    % Γ(k+1) = Γ(k) + k · (Γ_max - Γ(k)) / K_max
    Gamma = Gamma + k_iter * (Gamma_max - Gamma) / max_iterations;
    if AddPara.verbose >= 3
        fprintf('  Gamma updated: %.4f\n', Gamma);
    end
end
end


function idx = sample_from_probs(prob_vec)
% 按概率向量采样返回一个任务索引，概率全零时返回 0
total = sum(prob_vec);
if total <= 1e-12
    idx = 0;
    return;
end
prob_vec = prob_vec / total;
r = rand();
cumulative = 0;
idx = 0;
for i = 1:length(prob_vec)
    cumulative = cumulative + prob_vec(i);
    if r <= cumulative
        idx = i;
        return;
    end
end
% 浮点误差兜底：返回最后一个非零项
for i = length(prob_vec):-1:1
    if prob_vec(i) > 0
        idx = i;
        return;
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


function h = get_SC_hash(SC)
% 【优化2】快速数值哈希（替代 mat2str，约快 50 倍）
% 返回 double 标量，配合 containers.Map 使用
h = 0;
M = length(SC);
for m = 1:M
    mat = SC{m};
    n = numel(mat);
    h = h + sum(mat(:) .* (m * 1e5 + (1:n)'));
end
end


function is_in = is_in_tabu(sc_hash, tabu_map)
% 【优化3】O(1) 哈希查找（替代 O(L) 线性字符串比较）
is_in = isKey(tabu_map, sc_hash);
end


function tabu_queue = update_tabu_list(tabu_map, tabu_queue, sc_hash, L_tabu)
% 【优化3】containers.Map + FIFO 队列：插入 O(1)，淘汰 O(1)
% tabu_map 为 handle 对象，原地修改无需返回；tabu_queue 为 value 类型需返回
if ~isKey(tabu_map, sc_hash)
    tabu_map(sc_hash) = true;
    tabu_queue{end+1} = sc_hash;
    if length(tabu_queue) > L_tabu
        oldest = tabu_queue{1};
        tabu_queue(1) = [];
        remove(tabu_map, oldest);
    end
end
end


function history_data = record_round_data(history_data, round, SC, Value_data, agents, tasks, Value_Params, AddPara, summatrix, tol)
% 记录每轮的历史数据（口径与 Qi2023/OCF 对齐，统一用 evaluate_coalition_metrics）

% 使用上帝视角统一计算效用、成本、完成度（真实需求）
[total_utility, total_global_cost, total_completed_value, task_completion_degrees] = ...
    UtilityEvaluator.evaluate_coalition_metrics(SC, agents, tasks, Value_Params, tol);

% 构建 coalitionstru
final_coalitionstru = OCFUtils.build_coalitionstru_from_SC(SC, Value_Params, agents);

% 使用 ResultProcessor 记录
history_data = ResultProcessor.record_history_data(history_data, round, Value_data, Value_Params, ...
    SC, final_coalitionstru, total_utility, total_global_cost, ...
    total_completed_value, task_completion_degrees, summatrix);

if AddPara.verbose >= 1
    fprintf('  [Shi2024] 第 %d 轮: Utility=%.2f, Cost=%.2f, Completed=%.2f\n', ...
        round, total_utility, total_global_cost, total_completed_value);
end

end


