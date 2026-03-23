function [Value_data, history_data] = Huo2025_main(agents, tasks, AddPara, Value_Params)
% HUO2025_MAIN 顺序决策版 Huo2025 联盟形成算法
%
% 改造要点：
%   - 去除并发决策 + 共识协议，改为顺序扫描（仿 Qi2023）
%   - 每个智能体依次决策，立即更新 SC_global，消除震荡
%   - 保留非重叠联盟约束（每个智能体只能加入一个任务）
%
% 输入:
%   agents       - 智能体结构体数组
%   tasks        - 任务结构体数组
%   AddPara      - 附加参数（enable_belief_update, verbose）
%                  verbose: 0=静默 1=轮次进度 2=迭代进度 3=详细
%   Value_Params - 全局参数
%
% 输出:
%   Value_data   - 最终系统状态
%   history_data - 历史记录（用于画图）

%% ==================== 0. 随机数种子 ====================
if isfield(Value_Params, 'seed')
    rng(Value_Params.seed);
end

N = Value_Params.N;
M = Value_Params.M;
K = Value_Params.K;
task_types = Value_Params.task_type;
if isempty(task_types)
    task_types = numel(tasks(1).WORLD.value);
end

%% ==================== 1. 初始化 ====================
history_data = struct();

% 初始化每个智能体的内部状态
for i = 1:N
    Value_data(i).agentID        = agents(i).id;
    Value_data(i).agentIndex     = i;
    Value_data(i).coalitionstru  = zeros(M+1, N);
    Value_data(i).initbelief     = zeros(M+1, task_types);
    Value_data(i).observe        = zeros(M, task_types);
    Value_data(i).preobserve     = zeros(M, task_types);
    Value_data(i).resources_matrix = zeros(M, K);
    Value_data(i).SC             = cell(M, 1);
    for m = 1:M
        Value_data(i).SC{m} = zeros(N, K);
    end
    Value_data(i).task_schedule.task_sequence    = [];
    Value_data(i).task_schedule.arrival_times    = [];
    Value_data(i).task_schedule.start_times      = [];
    Value_data(i).task_schedule.mission_end_time = [];
    Value_data(i).task_schedule.execution_times  = [];
    Value_data(i).task_schedule.completion_times = [];
    Value_data(i).task_schedule.total_flight_time     = 0;
    Value_data(i).task_schedule.total_execution_time  = 0;
    Value_data(i).task_schedule.total_energy          = 0;
end

% 全局累计观测矩阵
summatrix = zeros(M, task_types);

% 初始信念：均匀分布
for i = 1:N
    for j = 1:M
        Value_data(i).initbelief(j, :) = ones(1, task_types) / task_types;
    end
end

% 单一共享 SC_global：每个智能体随机选一个任务，全部资源投入
SC_global = cell(M, 1);
for m = 1:M
    SC_global{m} = zeros(N, K);
end
for i = 1:N
    t = randi(M);
    SC_global{t}(i, :) = agents(i).resources(1:K);
end

% 同步到所有 Value_data
for i = 1:N
    Value_data(i).SC = SC_global;
    for j = 1:M
        Value_data(i).resources_matrix(j, :) = SC_global{j}(i, :);
    end
end

if AddPara.verbose >= 1
    fprintf('[Huo2025] 初始化完成：N=%d, M=%d, K=%d, 轮数=%d\n', N, M, K, Value_Params.num_rounds);
end

%% ==================== 2. 主循环：多轮博弈与演化 ====================
for counter = 1:Value_Params.num_rounds

    if AddPara.verbose >= 1
        fprintf('[Huo2025] === 第 %d/%d 轮 ===\n', counter, Value_Params.num_rounds);
    end

    % 记录每轮开始时的信念
    for i = 1:N
        for j = 1:M
            Value_data(i).tasks(j).prob(counter, :) = Value_data(i).initbelief(j, :);
        end
    end

    % --- 内循环：顺序扫描联盟形成 ---
    k_iter   = 1;
    k_stable = 0;
    TabuList = {};   % 每轮重置禁忌表
    inner_loop_history = ResultProcessor.init_inner_loop_history();

    while true
        SC_before_sweep = SC_global;

        % 顺序扫描：每个智能体依次决策，立即更新 SC_global
        for i = 1:N
            [SC_global, moved, TabuList] = Value_order(agents, tasks, SC_global, i, Value_data(i), Value_Params, AddPara, TabuList);
            if moved
                for jj = 1:N
                    Value_data(jj).SC = SC_global;
                end
            end
        end

        % 稳定性判断
        if isequal(SC_before_sweep, SC_global)
            k_stable = k_stable + 1;
        else
            k_stable = 0;
        end

        % 记录内循环历史
        iter_utility = 0;
        for jj = 1:N
            iter_utility = iter_utility + UtilityEvaluator.calc_agent_total_utility( ...
                SC_global, agents, tasks, Value_Params, Value_data(jj), AddPara);
        end
        inner_loop_history = ResultProcessor.record_inner_loop_iteration( ...
            inner_loop_history, k_iter, k_stable, iter_utility, iter_utility, SC_global, Value_Params);

        k_iter = k_iter + 1;

        if AddPara.verbose >= 2 && mod(k_iter, 10) == 0
            fprintf('[Huo2025]   迭代 %d: 效用=%.4f, k_stable=%d\n', k_iter, iter_utility, k_stable);
        end

        if k_stable >= Value_Params.Huo_K_stable_max || k_iter >= Value_Params.max_inner_iter
            break;
        end
    end

    if AddPara.verbose >= 2
        converge_reason = '稳定';
        if k_iter >= Value_Params.max_inner_iter, converge_reason = '达到最大迭代'; end
        fprintf('[Huo2025] 第 %d 轮收敛（%s），迭代次数=%d，最终效用=%.4f\n', ...
            counter, converge_reason, k_iter, iter_utility);
    end

    history_data.inner_loop{counter}       = inner_loop_history;
    history_data.k_iter_per_round{counter} = k_iter;

    % --- 轮末：提取最终结果 ---
    Final_SC           = SC_global;
    final_coalitionstru = OCFUtils.build_coalitionstru_from_SC(Final_SC, Value_Params, agents);

    % 观测 + 信念更新
    [Value_data, summatrix] = AgentOps.collect_observations(Value_data, agents, tasks, Value_Params, summatrix, Final_SC);
    Value_data = AgentOps.update_belief_from_observations(Value_data, Value_Params);

    % 同步 SC 回所有 Value_data
    for i = 1:N
        Value_data(i).SC = SC_global;
        for j = 1:M
            Value_data(i).resources_matrix(j, :) = SC_global{j}(i, :);
        end
        Value_data(i).coalitionstru = OCFUtils.build_coalitionstru_from_SC(SC_global, Value_Params, agents);
    end

    % 评估
    [coalition_utility, Rcost, total_completed_value, task_completion_degrees] = ...
        UtilityEvaluator.evaluate_coalition_metrics(Final_SC, agents, tasks, Value_Params, 1e-9);

    history_data = ResultProcessor.record_history_data(history_data, counter, Value_data, Value_Params, ...
        Final_SC, final_coalitionstru, coalition_utility, Rcost, total_completed_value, task_completion_degrees, summatrix);

end % End of For (Rounds)

% 补全任务时序信息
Value_data = update_task_schedule(Value_data, agents, tasks, Value_Params);

%% ==================== 3. 最终一致性检查 ====================
if AddPara.verbose >= 2
    fprintf('\n[Huo2025] 执行最终一致性检查...\n');
end
[is_valid, error_log] = check_coalition_consistency(Value_data, agents, tasks, Value_Params, 'Non-OCF', AddPara.verbose >= 2);

if ~is_valid
    warning('[Huo2025] 联盟一致性检查发现 %d 处问题，请查看上方日志！', length(error_log));
    history_data.consistency_errors = error_log;
else
    if AddPara.verbose >= 2
        fprintf('[Huo2025] 所有一致性检查通过！\n');
    end
end

end
