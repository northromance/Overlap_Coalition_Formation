function [Value_data, history_data] = PSO_main(agents, tasks, AddPara, Value_Params)
% PSO_MAIN - 粒子群占位实现（Qin2025 预留）
% 核心：用粒子群优化“成员关系 + 资源分配”编码，最大化任务价值×完成度，并对资源缺口加罚。
% 高级成本/等待/路径等细节留作后续 TODO。
%
% 输入：
%   agents        智能体数组（位置、资源等）
%   tasks         任务数组（位置、需求等）
%   AddPara       控制参数（保留接口，当前未用）
%   Value_Params  公共参数（包含 M/N/K、需求等）
%
% 输出：
%   Value_data    结果结构，兼容 compare_results/绘图
%   history_data  最简历史，仅记录最优一轮
%
% 适应度：sum(任务价值 × 完成度) - lambda_gap × 资源缺口
% 编码：前 M×N 位为成员矩阵，后 M×N×K 位为资源分配张量（非负）

    if nargin < 4
        error('Qin2025_main requires agents, tasks, AddPara, Value_Params.');
    end

    % ---------------- 维度信息 ----------------
    M = Value_Params.M;
    N = Value_Params.N;
    K = Value_Params.K;

    % ---------------- PSO 超参（可调） ----------------
    pso.swarm_size = 20;
    pso.max_iter = 30;
    pso.w = 0.7;            % 惯性权重
    pso.c1 = 1.4;           % 个体学习因子
    pso.c2 = 1.4;           % 群体学习因子
    pso.p_thresh = 0.5;     % 成员阈值（> 阈值视为加入）
    pso.lambda_gap = 0.1;   % 资源缺口罚权重

    % 编码长度：前 len_mem 成员矩阵，后 len_res 资源张量
    len_mem = M * N;
    len_res = M * N * K;
    dim = len_mem + len_res;

    % 初始化粒子群
    positions = rand(pso.swarm_size, dim);
    velocities = zeros(pso.swarm_size, dim);

    % 个体最优 / 全局最优
    pbest_pos = positions;
    pbest_fit = -inf(pso.swarm_size, 1);
    gbest_fit = -inf;
    gbest_pos = positions(1, :);
    gbest_solution = struct();

    for iter = 1:pso.max_iter
        for s = 1:pso.swarm_size
            [fitness, sol] = evaluate_particle(positions(s, :), agents, tasks, Value_Params, pso);

            % 更新个体最优
            if fitness > pbest_fit(s)
                pbest_fit(s) = fitness;
                pbest_pos(s, :) = positions(s, :);
            end

            % 更新全局最优
            if fitness > gbest_fit
                gbest_fit = fitness;
                gbest_pos = positions(s, :);
                gbest_solution = sol;
            end
        end

        % 速度与位置更新（标准 PSO）
        r1 = rand(pso.swarm_size, dim);
        r2 = rand(pso.swarm_size, dim);
        velocities = pso.w * velocities ...
                   + pso.c1 * r1 .* (pbest_pos - positions) ...
                   + pso.c2 * r2 .* (repmat(gbest_pos, pso.swarm_size, 1) - positions);

        positions = positions + velocities;

        % 成员段截断到 [0,1]，资源段截断为非负
        positions(:, 1:len_mem) = min(max(positions(:, 1:len_mem), 0), 1);
        positions(:, len_mem+1:end) = max(positions(:, len_mem+1:end), 0);
    end

    % 如未记录到解，使用 gbest_pos 兜底
    if isempty(fieldnames(gbest_solution))
        [~, gbest_solution] = evaluate_particle(gbest_pos, agents, tasks, Value_Params, pso);
    end

    [Value_data, history_data] = build_outputs(gbest_solution, gbest_fit, agents, tasks, Value_Params);
end

% -------------------------------------------------------------------------
function [fitness, sol] = evaluate_particle(position, agents, tasks, Value_Params, pso)
    % 解码成员矩阵与资源张量
    M = Value_Params.M;
    N = Value_Params.N;
    K = Value_Params.K;

    len_mem = M * N;
    mem_vec = position(1:len_mem);
    res_vec = position(len_mem+1:end);

    mem_mat = reshape(mem_vec, [M, N]);
    membership = mem_mat > pso.p_thresh;

    res_tensor = reshape(res_vec, [M, N, K]);
    res_tensor = max(res_tensor, 0);  % 资源不允许负值

    % 资源上限约束：按机器人/资源类型缩放
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

    % 构建 SC（每任务资源分配）与 coalitionstru（成员矩阵）
    SC = cell(M, 1);
    coalitionstru = zeros(M, N);
    agentresources = zeros(N, M, K);
    for m = 1:M
        alloc_m = squeeze(res_tensor(m, :, :)); % N x K
        if size(alloc_m, 1) == 1
            alloc_m = reshape(alloc_m, [N, K]);
        end
        % 非成员贡献清零
        member_row = membership(m, :)';
        alloc_m(~member_row, :) = 0;

        SC{m} = alloc_m;
        coalitionstru(m, member_row) = [agents(member_row).id];
        agentresources(:, m, :) = alloc_m;
    end

    % 计算适应度：任务效用和 - 资源缺口罚
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
        % 完成度（已有通用函数）
        completion(m) = calc_task_completion_degree(alloc_m, demand, K);

        % 需求缺口（未满足资源量求和）
        allocated_sum = sum(alloc_m, 1);
        gap = max(demand - allocated_sum, 0);
        gap_penalties(m) = sum(gap);

        task_utils(m) = tasks(m).value * completion(m);
    end

    total_utility = sum(task_utils);
    total_penalty = pso.lambda_gap * sum(gap_penalties);
    fitness = total_utility - total_penalty;

    % 打包解
    sol.coalitionstru = coalitionstru;
    sol.SC = SC;
    sol.agentresources = agentresources;
    sol.task_utils = task_utils;
    sol.completion = completion;
    sol.total_utility = total_utility;
    sol.total_penalty = total_penalty;
end

% -------------------------------------------------------------------------
function [Value_data, history_data] = build_outputs(sol, best_fitness, agents, tasks, Value_Params)
    % 构造与 compare_results/绘图兼容的输出（最小字段集）
    Value_data = struct();
    Value_data(1).coalitionstru = sol.coalitionstru;
    Value_data(1).SC = sol.SC;
    Value_data(1).agentresources = sol.agentresources;
    Value_data(1).totalvalue = sol.total_utility;
    Value_data(1).algorithm = "Qin2025_PSO";
    Value_data(1).energy_cost = [];

    % 最简 history（仅一轮）
    history_data = struct();
    history_data.rounds(1).task_utilities = sol.task_utils;
    history_data.rounds(1).task_completion = sol.completion;
    history_data.rounds(1).coalition_structure = sol.coalitionstru;
    history_data.rounds(1).SC = sol.SC;
    history_data.rounds(1).total_utility = sol.total_utility;
    history_data.rounds(1).fitness = best_fitness;

    % TODO: 如需信念/观测/调度时间线，可在此扩展。
end
