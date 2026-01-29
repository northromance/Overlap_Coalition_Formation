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

fprintf('\n=== Shi2024 OCF Algorithm Start ===\n');
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

fprintf('Belief update: %s\n', mat2str(enable_belief_update));
fprintf('Agents: %d, Tasks: %d, Resources: %d, Rounds: %d\n', N, M, K, num_rounds);

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
    fprintf('\n========== Round %d/%d ==========\n', round, num_rounds);

    %% Step 1: 联盟形成
    if round == 1
        % 第一轮：初始化策略
        fprintf('--- Initial Coalition Formation ---\n');
        SC = initial_coalition_formation(N, M, SC, agents, tasks, Value_Params, Value_data, AddPara, tol);
    else
        % 后续轮：迭代优化
        fprintf('--- Coalition Optimization ---\n');
        SC = optimize_coalitions(N, M, SC, agents, tasks, Value_Params, Value_data, AddPara, tol);
    end

    % 更新 Value_data 中的 SC
    for i = 1:N
        Value_data(i).SC = SC;

        % 更新 resources_matrix
        for j = 1:M
            Value_data(i).resources_matrix(j, :) = SC{j}(i, :);
        end

        % 更新 coalitionstru（使用统一的构建函数）
        Value_data(i).coalitionstru = OCFUtils.build_coalitionstru_from_SC(SC, agents, N, M, tol);
    end

    %% Step 2: 观测收集
    if enable_belief_update
        [Value_data, summatrix] = AgentOps.collect_observations(Value_data, agents, tasks, Value_Params, summatrix, SC);
    end

    %% Step 3: 记录历史数据
    history_data = record_round_data(history_data, round, SC, Value_data, agents, tasks, Value_Params, AddPara, summatrix, tol);

    %% Step 4: 信念更新
    if enable_belief_update && round < num_rounds
        Value_data = AgentOps.update_belief_from_observations(Value_data, Value_Params);
        fprintf('Beliefs updated for next round.\n');
    end
end

%% 最终结果处理
fprintf('\n=== Final Results ===\n');

% 计算每个智能体的最终效用和成本
for i = 1:N
    Value_data(i).SC = SC;

    % 获取任务列表
    task_list = OCFUtils.get_agent_tasks_fast(SC, i, tol);
    task_list = task_list(task_list <= M);

    if ~isempty(task_list)
        ordered_tasks = OCFUtils.sort_tasks_by_priority(task_list, tasks);
        Value_data(i).task_schedule.task_sequence = ordered_tasks;

        % 计算时间和成本
        [t_fly, t_wait, t_exec, start_times, exec_times, comp_times, mission_end] = ...
            WorldSim.calc_with_global_sync(i, ordered_tasks, agents, tasks, Value_Params, SC, tol);

        Value_data(i).task_schedule.total_flight_time = t_fly;
        Value_data(i).task_schedule.total_execution_time = t_exec;
        Value_data(i).task_schedule.start_times = start_times;
        Value_data(i).task_schedule.execution_times = exec_times;
        Value_data(i).task_schedule.completion_times = comp_times;
        Value_data(i).task_schedule.mission_end_time = mission_end;

        % 计算总能量消耗
        alpha_fly = agents(i).fuel;
        alpha_wait = agents(i).wait_fuel;
        beta = agents(i).beta;
        E_total = alpha_fly * t_fly + alpha_wait * t_wait + beta * t_exec;
        Value_data(i).task_schedule.total_energy = E_total;

        fprintf('Agent %d: Tasks=%d, Utility=%.2f, Energy=%.2f\n', ...
            i, length(task_list), ...
            UtilityEvaluator.calc_agent_total_utility(SC, agents, tasks, Value_Params, Value_data(i), AddPara), ...
            E_total);
    end
end

% 全局统计
total_utility = calc_global_utility(SC, agents, tasks, Value_Params, Value_data, AddPara);
fprintf('\nGlobal Total Utility: %.2f\n', total_utility);
fprintf('Total Rounds: %d\n', num_rounds);

%% 最终数据一致性检查
fprintf('\n[Shi2024] 执行最终数据一致性检查...\n');
[is_valid_data, error_log_data] = check_data_consistency(Value_data, Value_Params);
[is_valid_ocf, error_log_ocf] = check_OCF_consistency(Value_data, agents, Value_Params);

if ~is_valid_data || ~is_valid_ocf
    warning('[Shi2024] 数据一致性检查发现问题，请查看上方日志！');
end

%% 最终可行性验证
fprintf('\n[Shi2024] 执行最终可行性验证...\n');
fprintf('==============================================\n');
all_feasible = true;
for i = 1:N
    % 获取资源分配矩阵
    R_agent_Q = zeros(M, K);
    task_list = OCFUtils.get_agent_tasks_fast(SC, i, tol);
    for t_idx = 1:length(task_list)
        t = task_list(t_idx);
        if t <= M
            R_agent_Q(t, :) = SC{t}(i, :);
        end
    end

    % 验证可行性
    [isFeasible, info, cost_data] = validate_feasibility(Value_data(i), agents, tasks, Value_Params, i, SC, R_agent_Q);

    if ~isFeasible
        fprintf('❌ Agent %d 不可行: %s\n', i, info.reason);
        all_feasible = false;
    else
        fprintf('✅ Agent %d 可行: 能量 %.2f/%.2f, 任务数 %d\n', ...
            i, cost_data.requiredEnergy, agents(i).Emax, length(cost_data.assignedTasks));
    end
end

if all_feasible
    fprintf('✅ [可行性验证] 所有智能体的分配方案均可行！\n');
else
    fprintf('🚫 [可行性验证] 发现不可行的分配方案！\n');
    warning('[Shi2024] 可行性验证失败，请检查算法逻辑！');
end
fprintf('==============================================\n');

fprintf('\n=== Shi2024 OCF Algorithm End ===\n\n');

end


%% ========== 主要函数 ==========

function SC = initial_coalition_formation(N, M, SC, agents, tasks, Value_Params, Value_data, AddPara, tol)
% 初始化联盟形成：每个智能体选择最大效用的任务

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
        for t = task_list_temp'
            if t <= M
                R_agent_Q(t, :) = SC_temp{t}(j, :);
            end
        end

        % 验证可行性
        [isFeasible, ~, cost_data] = validate_feasibility(Value_data(j), agents, tasks, Value_Params, j, SC_temp, R_agent_Q);

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
        fprintf('  Agent %d joins Task %d (utility: %.2f, energy: %.2f)\n', ...
            j, best_task, best_utility, best_cost_data.requiredEnergy);
    end
end

end


function SC = optimize_coalitions(N, M, SC, agents, tasks, Value_Params, Value_data, AddPara, tol)
% 迭代优化联盟结构

SC_prev = SC;
iteration = 0;
max_iterations = 50;

while iteration < max_iterations
    iteration = iteration + 1;
    SC_prev_iter = SC;

    fprintf('  Iteration %d:\n', iteration);

    % Phase 1: Quit/Transfer 负效用任务
    for j = 1:N
        current_total_utility = UtilityEvaluator.calc_agent_total_utility(SC, agents, tasks, Value_Params, Value_data(j), AddPara);

        task_list = OCFUtils.get_agent_tasks_fast(SC, j, tol);
        task_list = task_list(task_list <= M);

        for task_idx = 1:length(task_list)
            task_p = task_list(task_idx);

            % 尝试退出
            SC_quit = SC;
            SC_quit{task_p}(j, :) = 0;
            utility_after_quit = UtilityEvaluator.calc_agent_total_utility(SC_quit, agents, tasks, Value_Params, Value_data(j), AddPara);

            if utility_after_quit > current_total_utility
                % 尝试转移
                [best_transfer_task, best_transfer_utility] = find_best_transfer(j, task_p, SC, agents, tasks, Value_Params, Value_data, AddPara, tol);

                if best_transfer_task > 0 && best_transfer_utility > current_total_utility
                    fprintf('    Agent %d: Transfer Task %d->%d (%.2f->%.2f)\n', j, task_p, best_transfer_task, current_total_utility, best_transfer_utility);
                    SC{task_p}(j, :) = 0;
                    SC{best_transfer_task}(j, :) = agents(j).resources';
                    current_total_utility = best_transfer_utility;
                else
                    fprintf('    Agent %d: Quit Task %d (%.2f->%.2f)\n', j, task_p, current_total_utility, utility_after_quit);
                    SC{task_p}(j, :) = 0;
                    current_total_utility = utility_after_quit;
                end
            end
        end
    end

    % Phase 2: Join 新任务
    for j = 1:N
        current_total_utility = UtilityEvaluator.calc_agent_total_utility(SC, agents, tasks, Value_Params, Value_data(j), AddPara);

        task_list = OCFUtils.get_agent_tasks_fast(SC, j, tol);
        task_list = task_list(task_list <= M);

        for i = 1:M
            if ismember(i, task_list)
                continue;
            end

            % 尝试加入
            SC_join = SC;
            SC_join{i}(j, :) = agents(j).resources';

            % 获取资源分配矩阵
            R_agent_Q = zeros(M, Value_Params.K);
            task_list_temp = OCFUtils.get_agent_tasks_fast(SC_join, j, tol);
            for t_idx = 1:length(task_list_temp)
                t = task_list_temp(t_idx);
                if t <= M
                    R_agent_Q(t, :) = SC_join{t}(j, :);
                end
            end

            % 验证可行性
            [isFeasible, ~, cost_data] = validate_feasibility(Value_data(j), agents, tasks, Value_Params, j, SC_join, R_agent_Q);

            if ~isFeasible
                continue;
            end

            utility_after_join = UtilityEvaluator.calc_agent_total_utility(SC_join, agents, tasks, Value_Params, Value_data(j), AddPara);

            if utility_after_join > current_total_utility
                fprintf('    Agent %d: Join Task %d (%.2f->%.2f, energy: %.2f)\n', ...
                    j, i, current_total_utility, utility_after_join, cost_data.requiredEnergy);
                SC{i}(j, :) = agents(j).resources';
                current_total_utility = utility_after_join;
            end
        end
    end

    % 检查收敛
    if isequal_SC(SC, SC_prev_iter)
        fprintf('  Converged after %d iterations.\n', iteration);
        break;
    end
end

end


function [best_task, best_utility] = find_best_transfer(agent_id, current_task, SC, agents, tasks, Value_Params, Value_data, AddPara, tol)
% 寻找最佳转移目标任务

M = Value_Params.M;
best_task = -1;
best_utility = -inf;

for i = 1:M
    if i == current_task
        continue;
    end

    % 创建临时 SC
    SC_temp = SC;
    SC_temp{current_task}(agent_id, :) = 0;
    SC_temp{i}(agent_id, :) = agents(agent_id).resources';

    % 获取资源分配矩阵
    R_agent_Q = zeros(M, Value_Params.K);
    task_list_temp = OCFUtils.get_agent_tasks_fast(SC_temp, agent_id, tol);
    for t = task_list_temp'
        if t <= M
            R_agent_Q(t, :) = SC_temp{t}(agent_id, :);
        end
    end

    % 验证可行性
    [isFeasible, ~, ~] = validate_feasibility(Value_data(agent_id), agents, tasks, Value_Params, agent_id, SC_temp, R_agent_Q);

    if ~isFeasible
        continue;
    end

    % 计算转移后的总效用
    utility = UtilityEvaluator.calc_agent_total_utility(SC_temp, agents, tasks, Value_Params, Value_data(agent_id), AddPara);

    if utility > best_utility
        best_utility = utility;
        best_task = i;
    end
end

end


function equal = isequal_SC(SC1, SC2)
% 比较两个 SC 是否相等

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
confidence = 0.9;
if isfield(AddPara, 'resource_confidence')
    confidence = AddPara.resource_confidence;
end

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
final_coalitionstru = OCFUtils.build_coalitionstru_from_SC(SC, agents, N, M, tol);

% 记录信念
belief_snapshot = zeros(N, M, Value_Params.task_type);
for i = 1:N
    belief_snapshot(i, :, :) = Value_data(i).initbelief(1:M, :);
end

% 使用 ResultProcessor 记录
history_data = ResultProcessor.record_history_data(history_data, round, Value_data, Value_Params, ...
    SC, final_coalitionstru, total_utility, total_global_cost, ...
    total_completed_value, task_completion_degrees, summatrix);

fprintf('  Round %d: Utility=%.2f, Cost=%.2f, Completed=%.2f\n', ...
    round, total_utility, total_global_cost, total_completed_value);

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
