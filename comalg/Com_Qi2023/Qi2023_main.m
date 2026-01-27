function [Value_data, history_data] = Qi2023_main(agents, tasks, AddPara, Value_Params)
% Qi2023_OCF_main - 基于 Qi2023 PGG-TS 思路的重叠联盟形成算法（无信念更新版）
% 接口与 SA_Value_main 保持一致，输出 Value_data 与 history_data。
%
% 关键差异：
%   1) 不进行贝叶斯信念更新，始终使用初始信念/预设期望。
%   2) 决策流程：随机撤离 -> 偏好重力计算 -> Softmax 概率分配。
%   3) 仍保留观测收集以生成 summatrix，便于统计对齐。
%
% 输入：
%   agents, tasks, AddPara, Value_Params（同 SA_Value_main）
% 输出：
%   Value_data, history_data

%% 0. 随机种子（保证可复现）
if isfield(Value_Params, 'seed')
    rng(Value_Params.seed);
end

eps_val = 1e-9;
N = Value_Params.N;
M = Value_Params.M;
K = Value_Params.K;

%% 1. 初始化 Value_data 与观测矩阵
history_data = struct();
summatrix = zeros(M, Value_Params.task_type);

for i = 1:N
    Value_data(i).agentID = agents(i).id;
    Value_data(i).agentIndex = i;
    Value_data(i).iteration = 0;
    Value_data(i).unif = 0;
    Value_data(i).coalitionstru = zeros(M + 1, N);   % 成员矩阵
    Value_data(i).initbelief = zeros(M + 1, Value_Params.task_type); % 初始信念
    Value_data(i).cost_data = [];
    Value_data(i).resources_matrix = zeros(M, K);   % 局部视图
    Value_data(i).SC = cell(M, 1);                  % 全局视图
    for m = 1:M
        Value_data(i).SC{m} = zeros(N, K);
        Value_data(i).SC{m}(i, :) = Value_data(i).resources_matrix(m, :);
    end
    Value_data(i).other = cell(N, 1);               % 其他智能体的信念快照

    % 任务执行时序结构
    Value_data(i).task_schedule = struct();
    Value_data(i).task_schedule.task_sequence = [];
    Value_data(i).task_schedule.arrival_times = [];
    Value_data(i).task_schedule.start_times = [];
    Value_data(i).task_schedule.mission_end_time = [];
    Value_data(i).task_schedule.execution_times = [];
    Value_data(i).task_schedule.completion_times = [];
    Value_data(i).task_schedule.total_flight_time = 0;
    Value_data(i).task_schedule.total_wait_time = 0;
    Value_data(i).task_schedule.total_execution_time = 0;
    Value_data(i).task_schedule.total_energy = 0;
    Value_data(i).selectProb = zeros(K, M);
end

% void 任务行（M+1）：初始全部在空闲行
for k = 1:N
    Value_data(k).coalitionstru(M+1, :) = 0;
    Value_data(k).coalitionstru(M+1, k) = agents(k).id;
end

% 初始信念（均匀分布）
for i = 1:N
    for j = 1:M
        Value_data(i).initbelief(j, :) = ones(1, Value_Params.task_type) / Value_Params.task_type;
    end
end
% 互相缓存信念
for i = 1:N
    for j = 1:N
        Value_data(i).other{j}.initbelief = Value_data(j).initbelief;
    end
end

% 观测计数
for i = 1:N
    for j = 1:M
        Value_data(i).observe(j, :) = 0;
        Value_data(i).preobserve(j, :) = 0;
    end
end

% 初始资源上限
for i = 1:N
    Value_data(i).resources = agents(i).resources;
end

%% 2. 迭代主循环
p_leave = 0.2;            % 随机撤离概率
softmax_tau = 1.0;        % Softmax 温度

for counter = 1:Value_Params.num_rounds

    % 使用统一的 SC 视图（取第一个智能体的 SC）
    SC_global = Value_data(1).SC;

    % 2.1 对每个智能体 / 每个资源维度执行 “随机撤离 + 偏好分配”
    for i = 1:N
        agent_pos = [agents(i).x, agents(i).y];
        for k = 1:K
            % ---------- 随机撤离 ----------
            % 找到当前分配的任务
            current_task = 0;
            for t = 1:M
                if SC_global{t}(i, k) > eps_val
                    current_task = t;
                    break;
                end
            end
            if current_task > 0 && rand < p_leave
                SC_global{current_task}(i, k) = 0;
            end

            % ---------- 偏好重力计算 ----------
            F = zeros(1, M + 1); % 最后一位对应“保持空闲/void”
            for t = 1:M
                demand_k = tasks(t).resource_demand(k);
                allocated_k = sum(SC_global{t}(:, k));
                remaining_k = max(demand_k - allocated_k, 0);
                if remaining_k < eps_val
                    F(t) = 0;
                    continue;
                end

                % 期望价值：使用初始信念与任务类型价值/任务价值
                if isfield(Value_Params, 'task_value') && ~isempty(Value_Params.task_value)
                    tv = Value_Params.task_value(:)';
                    belief = Value_data(i).initbelief(t, :);
                    expected_value = sum(belief .* tv(1:length(belief)));
                elseif isfield(tasks(t), 'value')
                    expected_value = tasks(t).value;
                else
                    expected_value = 1;
                end

                % 距离
                if isfield(tasks, 'loc') && ~isempty(tasks(t).loc)
                    task_pos = tasks(t).loc;
                else
                    task_pos = [tasks(t).x, tasks(t).y];
                end
                dist_sq = sum((agent_pos - task_pos).^2) + 1e-6;

                % 偏好重力
                F(t) = expected_value * remaining_k / dist_sq;
            end
            % 空闲选项（保持资源不分配）
            F(M + 1) = 1e-3;

            % ---------- Softmax 概率 ----------
            P = softmax_vec(F / softmax_tau);

            % ---------- 轮盘赌选择 ----------
            r = rand;
            cumP = cumsum(P);
            sel = find(r <= cumP, 1, 'first');
            if isempty(sel), sel = M + 1; end

            % ---------- 更新分配 ----------
            % 先清空该资源在所有任务中的占用
            for t = 1:M
                SC_global{t}(i, k) = 0;
            end

            if sel <= M
                demand_k = tasks(sel).resource_demand(k);
                allocated_k = sum(SC_global{sel}(:, k));
                remaining_k = max(demand_k - allocated_k, 0);
                assign_amt = min(agents(i).resources(k), remaining_k);
                SC_global{sel}(i, k) = assign_amt;
            end
        end
    end

    % 2.2 同步到每个智能体的视图与 coalitionstru
    coalitionstru = zeros(M + 1, N);
    for i = 1:N
        Value_data(i).SC = SC_global;
        % 重建 resources_matrix
        Value_data(i).resources_matrix = OCFUtils.get_agent_resource_matrix(SC_global, i, Value_Params);

        % 成员矩阵：若在某任务有任意资源投入，则标记；否则归入 void
        assigned_tasks = OCFUtils.get_agent_tasks_fast(SC_global, Value_data(i).agentID, eps_val);
        if isempty(assigned_tasks)
            coalitionstru(M + 1, i) = agents(i).id;
        else
            for t = assigned_tasks'
                coalitionstru(t, i) = agents(i).id;
            end
        end
        Value_data(i).coalitionstru = coalitionstru;
    end

    % 2.3 更新任务日程（路径/能耗）
    Value_data = update_task_schedule(Value_data, agents, tasks, Value_Params);

    % 2.4 观测收集（保持格式一致，但不更新信念）
    [Value_data, summatrix] = AgentOps.collect_observations(Value_data, agents, tasks, Value_Params, summatrix, SC_global);
    % 不调用 AgentOps.update_belief_from_observations，以保持固定信念

    %% 3. 评估与记录
    [coalition_utility, total_global_cost, total_completed_value, task_completion_degrees] = ...
        UtilityEvaluator.evaluate_coalition_metrics(SC_global, agents, tasks, Value_Params, eps_val);

    history_data = ResultProcessor.record_history_data(history_data, counter, Value_data, Value_Params, ...
        SC_global, coalitionstru, ...
        coalition_utility, total_global_cost, ...
        total_completed_value, task_completion_degrees, ...
        summatrix);

    % 简单日志
    fprintf('[Qi2023_OCF] round %d: utility=%.2f, cost=%.2f, value=%.2f, avg_comp=%.2f%%\n', ...
        counter, coalition_utility, total_global_cost, total_completed_value, mean(task_completion_degrees) * 100);
end

% 数据一致性自检
[is_valid, ~] = check_OCF_consistency(Value_data, agents, Value_Params);
if ~is_valid
    warning('Qi2023_OCF_main: 数据一致性检查未通过，请检查输入或算法实现。');
end

end

%% Softmax 辅助函数
function p = softmax_vec(x)
    x = x - max(x);             % 数值稳定
    ex = exp(x);
    p = ex / sum(ex);
end

