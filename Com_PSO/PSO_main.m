function [Value_data, history_data] = PSO_main(agents, tasks, AddPara, Value_Params)
% PSO_MAIN - 粒子群占位实现（Qin2025 预留）
% 目标：在“成员关系 + 资源分配 + 执行优先级”编码上优化任务分配，
%      结合类 TSP 闭环路径成本（Depot-Task-Depot）和信念期望效用。
% 核心要素：
%   - 编码：
%       Layer1 成员矩阵 (M×N, [0,1] 阈值化)
%       Layer2 资源分配张量 (M×N×K, 非负)
%       Layer3 执行优先级矩阵 (M×N, 连续，排序决定路径顺序)
%   - 适应度：期望效用和 - 资源缺口罚 - 行驶成本
%   - 输出：保留 coalitionstru/SC/agentresources/totalvalue，并记录 agent_paths

    if nargin < 4
        error('PSO_main requires agents, tasks, AddPara, Value_Params.');
    end

    % ---------------- 维度信息 ----------------
    M = Value_Params.M;
    N = Value_Params.N;
    K = Value_Params.K;

    % ---------------- PSO 超参（可调） ----------------
    pso.swarm_size   = 20;
    pso.max_iter     = 30;
    pso.w            = 0.7;   % 惯性权重
    pso.c1           = 1.4;   % 个体学习因子
    pso.c2           = 1.4;   % 群体学习因子
    pso.p_thresh     = 0.5;   % 成员阈值
    pso.lambda_gap   = 0.1;   % 资源缺口罚权重
    pso.travel_weight = 1.0;  % 行驶成本权重（可按需调节）

    % ---------------- 编码长度 ----------------
    len_mem = M * N;      % 成员矩阵
    len_res = M * N * K;  % 资源张量
    len_seq = M * N;      % 优先级矩阵
    dim = len_mem + len_res + len_seq;

    % ---------------- 粒子群初始化 ----------------
    positions  = rand(pso.swarm_size, dim);
    velocities = zeros(pso.swarm_size, dim);

    pbest_pos = positions;
    pbest_fit = -inf(pso.swarm_size, 1);
    gbest_fit = -inf;
    gbest_pos = positions(1, :);
    gbest_solution = struct();

    for iter = 1:pso.max_iter
        for s = 1:pso.swarm_size
            [fitness, sol] = evaluate_particle(positions(s, :), agents, tasks, Value_Params, pso);

            % 个体最优
            if fitness > pbest_fit(s)
                pbest_fit(s) = fitness;
                pbest_pos(s, :) = positions(s, :);
            end

            % 全局最优
            if fitness > gbest_fit
                gbest_fit = fitness;
                gbest_pos = positions(s, :);
                gbest_solution = sol;
            end
        end

        % 速度 / 位置更新
        r1 = rand(pso.swarm_size, dim);
        r2 = rand(pso.swarm_size, dim);
        velocities = pso.w * velocities ...
                   + pso.c1 * r1 .* (pbest_pos - positions) ...
                   + pso.c2 * r2 .* (repmat(gbest_pos, pso.swarm_size, 1) - positions);

        positions = positions + velocities;

        % 截断：成员段 [0,1]，资源段/优先级段保持非负
        positions(:, 1:len_mem) = min(max(positions(:, 1:len_mem), 0), 1);
        positions(:, len_mem+1:end) = max(positions(:, len_mem+1:end), 0);
    end

    % 兜底：若未记录解，直接用 gbest_pos 解码
    if isempty(fieldnames(gbest_solution))
        [~, gbest_solution] = evaluate_particle(gbest_pos, agents, tasks, Value_Params, pso);
    end

    [Value_data, history_data] = build_outputs(gbest_solution, gbest_fit);
end

% -------------------------------------------------------------------------
function [fitness, sol] = evaluate_particle(position, agents, tasks, Value_Params, pso)
    % 解码三段式编码
    M = Value_Params.M;
    N = Value_Params.N;
    K = Value_Params.K;

    len_mem = M * N;
    len_res = M * N * K;
    len_seq = M * N;

    mem_vec = position(1:len_mem);
    res_vec = position(len_mem+1:len_mem+len_res);
    seq_vec = position(len_mem+len_res+1:end);

    % 成员矩阵 & 资源张量
    mem_mat = reshape(mem_vec, [M, N]);
    membership = mem_mat > pso.p_thresh;

    res_tensor = reshape(res_vec, [M, N, K]);
    res_tensor = max(res_tensor, 0);  % 资源非负

    % 优先级矩阵（连续值，排序用）
    seq_mat = reshape(seq_vec, [M, N]);

    % 资源修复：对每个智能体/资源类型按上限缩放
    for n = 1:N
        for k = 1:K
            total_alloc = sum(res_tensor(:, n, k));
            cap = agents(n).resources(k);
            if total_alloc > cap && total_alloc > 0
                scale = cap / total_alloc;
                res_tensor(:, n, k) = res_tensor(:, n, k) * scale;
            end
        end
    end

    % 构建 SC / coalitionstru / agentresources
    SC = cell(M, 1);
    coalitionstru = zeros(M, N);
    agentresources = zeros(N, M, K);
    for m = 1:M
        alloc_m = squeeze(res_tensor(m, :, :)); % N x K
        if size(alloc_m, 1) == 1
            alloc_m = reshape(alloc_m, [N, K]);
        end
        member_row = membership(m, :)';
        alloc_m(~member_row, :) = 0;  % 非成员贡献清零

        SC{m} = alloc_m;
        coalitionstru(m, member_row) = [agents(member_row).id];
        agentresources(:, m, :) = alloc_m;
    end

    % 路径构建与行驶成本（Depot -> Tasks -> Depot，按优先级降序）
    agent_paths = cell(N, 1);
    total_travel_cost = 0;
    for n = 1:N
        task_indices = find(coalitionstru(:, n));
        if isempty(task_indices)
            agent_paths{n} = [];
            continue;
        end
        % 按优先级（seq_mat）降序排序
        my_priorities = seq_mat(task_indices, n);
        [~, sort_idx] = sort(my_priorities, 'descend');
        sorted_tasks = task_indices(sort_idx);
        agent_paths{n} = sorted_tasks;

        % 闭环路径距离
        curr_pos = [agents(n).x, agents(n).y];
        dist_n = 0;
        for t = 1:length(sorted_tasks)
            tgt = sorted_tasks(t);
            target_pos = [tasks(tgt).x, tasks(tgt).y];
            dist_n = dist_n + norm(curr_pos - target_pos);
            curr_pos = target_pos;
        end
        dist_n = dist_n + norm(curr_pos - [agents(n).x, agents(n).y]);
        total_travel_cost = total_travel_cost + dist_n * agents(n).fuel;
    end

    % 期望效用（基于信念）+ 资源缺口罚
    task_utils = zeros(M, 1);
    gap_penalties = zeros(M, 1);
    completion = zeros(M, 1);
    for m = 1:M
        demand = tasks(m).resource_demand;
        alloc_m = SC{m};
        if isempty(alloc_m)
            completion(m) = 0;
            continue;
        end
        completion(m) = calc_task_completion_degree(alloc_m, demand, K);

        % 资源缺口（未满足量求和）
        allocated_sum = sum(alloc_m, 1);
        gap = max(demand - allocated_sum, 0);
        gap_penalties(m) = sum(gap);

        % 信念期望价值
        belief_row = get_belief_row(Value_Params, m);
        type_values = get_type_values(tasks(m));
        expected_val = sum(belief_row .* type_values);
        task_utils(m) = expected_val * completion(m);
    end

    total_utility = sum(task_utils);
    total_gap_penalty = pso.lambda_gap * sum(gap_penalties);
    total_travel_penalty = pso.travel_weight * total_travel_cost;
    fitness = total_utility - total_gap_penalty - total_travel_penalty;

    % 打包解
    sol.coalitionstru = coalitionstru;
    sol.SC = SC;
    sol.agentresources = agentresources;
    sol.task_utils = task_utils;
    sol.completion = completion;
    sol.total_utility = total_utility;
    sol.total_penalty = total_gap_penalty + total_travel_penalty;
    sol.travel_cost = total_travel_cost;
    sol.agent_paths = agent_paths;
end

% -------------------------------------------------------------------------
function belief_row = get_belief_row(Value_Params, task_idx)
    % 返回任务的信念分布；若不存在则用均匀分布
    if isfield(Value_Params, 'belief') && size(Value_Params.belief, 1) >= task_idx
        belief_row = Value_Params.belief(task_idx, :);
    else
        % 默认按 task_type 数目均匀分布
        ttypes = Value_Params.task_type;
        belief_row = ones(1, ttypes) / max(ttypes, 1);
    end
    % 归一化防止数值问题
    s = sum(belief_row);
    if s > 0
        belief_row = belief_row / s;
    end
end

% -------------------------------------------------------------------------
function type_values = get_type_values(task)
    % 获取任务类型价值向量；若无则退化为任务价值的平铺向量
    if isfield(task, 'type_values')
        type_values = task.type_values;
    elseif isfield(task, 'WORLD') && isfield(task.WORLD, 'value')
        type_values = task.WORLD.value;
    else
        % 退化：用单一价值填充三类
        type_values = repmat(task.value, 1, 3);
    end
end

% -------------------------------------------------------------------------
function [Value_data, history_data] = build_outputs(sol, best_fitness)
    % 构造与 compare_results / 绘图兼容的输出（最小字段）
    Value_data = struct();
    Value_data(1).coalitionstru = sol.coalitionstru;
    Value_data(1).SC = sol.SC;
    Value_data(1).agentresources = sol.agentresources;
    Value_data(1).totalvalue = sol.total_utility;
    Value_data(1).algorithm = "Qin2025_PSO";
    Value_data(1).energy_cost = sol.travel_cost;
    Value_data(1).agent_paths = sol.agent_paths;

    history_data = struct();
    history_data.rounds(1).task_utilities = sol.task_utils;
    history_data.rounds(1).task_completion = sol.completion;
    history_data.rounds(1).coalition_structure = sol.coalitionstru;
    history_data.rounds(1).SC = sol.SC;
    history_data.rounds(1).total_utility = sol.total_utility;
    history_data.rounds(1).fitness = best_fitness;
    history_data.rounds(1).agent_paths = sol.agent_paths;
    history_data.rounds(1).travel_cost = sol.travel_cost;
    history_data.rounds(1).penalty = sol.total_penalty;
end
