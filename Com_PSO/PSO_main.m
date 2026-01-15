function [Value_data, history_data] = PSO_main(agents, tasks, AddPara, Value_Params)
% PSO_MAIN - PSO-based scaffold (placeholder for future Qin2025 logic).
%   Optimizes total utility via particle swarm on membership + resource
%   allocation encoding. Unknown/advanced parts are left as TODO for later.
%
%   Inputs:
%     agents        - struct array describing agents (positions, resources)
%     tasks         - struct array describing tasks (locations, demands)
%     AddPara       - algorithm control parameters (kept for interface)
%     Value_Params  - shared parameter structure (see init_value_params)
%
%   Outputs:
%     Value_data    - coalition formation results (compatible with plots)
%     history_data  - minimal iteration history (best-only)
%
%   Notes:
%     - Fitness: sum(task.value * completion_ratio) with simple resource
%       penalty. TODO: extend with能耗/等待/路径成本等细节。
%     - Encoding: [membership (M×N) | resource alloc (M×N×K)].

    if nargin < 4
        error('Qin2025_main requires agents, tasks, AddPara, Value_Params.');
    end

    % Dimensions
    M = Value_Params.M;
    N = Value_Params.N;
    K = Value_Params.K;

    % ---------------- PSO hyperparameters (tunable) ----------------
    pso.swarm_size = 20;
    pso.max_iter = 30;
    pso.w = 0.7;            % inertia
    pso.c1 = 1.4;           % cognitive
    pso.c2 = 1.4;           % social
    pso.p_thresh = 0.5;     % membership threshold
    pso.lambda_gap = 0.1;   % resource gap penalty weight

    % Encoding sizes
    len_mem = M * N;
    len_res = M * N * K;
    dim = len_mem + len_res;

    % Swarm init
    positions = rand(pso.swarm_size, dim);
    velocities = zeros(pso.swarm_size, dim);

    % Personal/global best
    pbest_pos = positions;
    pbest_fit = -inf(pso.swarm_size, 1);
    gbest_fit = -inf;
    gbest_pos = positions(1, :);
    gbest_solution = struct();

    for iter = 1:pso.max_iter
        for s = 1:pso.swarm_size
            [fitness, sol] = evaluate_particle(positions(s, :), agents, tasks, Value_Params, pso);

            % Update personal best
            if fitness > pbest_fit(s)
                pbest_fit(s) = fitness;
                pbest_pos(s, :) = positions(s, :);
            end

            % Update global best
            if fitness > gbest_fit
                gbest_fit = fitness;
                gbest_pos = positions(s, :);
                gbest_solution = sol;
            end
        end

        % Velocity & position update
        r1 = rand(pso.swarm_size, dim);
        r2 = rand(pso.swarm_size, dim);
        velocities = pso.w * velocities ...
                   + pso.c1 * r1 .* (pbest_pos - positions) ...
                   + pso.c2 * r2 .* (repmat(gbest_pos, pso.swarm_size, 1) - positions);

        positions = positions + velocities;

        % Clamp membership to [0,1], resources to non-negative
        positions(:, 1:len_mem) = min(max(positions(:, 1:len_mem), 0), 1);
        positions(:, len_mem+1:end) = max(positions(:, len_mem+1:end), 0);
    end

    % Build outputs from best solution
    if isempty(fieldnames(gbest_solution))
        % Fallback: decode gbest_pos if no solution stored (should not happen)
        [~, gbest_solution] = evaluate_particle(gbest_pos, agents, tasks, Value_Params, pso);
    end

    [Value_data, history_data] = build_outputs(gbest_solution, gbest_fit, agents, tasks, Value_Params);
end

% -------------------------------------------------------------------------
function [fitness, sol] = evaluate_particle(position, agents, tasks, Value_Params, pso)
    M = Value_Params.M;
    N = Value_Params.N;
    K = Value_Params.K;

    len_mem = M * N;
    mem_vec = position(1:len_mem);
    res_vec = position(len_mem+1:end);

    % Decode membership and resource allocation
    mem_mat = reshape(mem_vec, [M, N]);
    membership = mem_mat > pso.p_thresh;

    res_tensor = reshape(res_vec, [M, N, K]);
    res_tensor = max(res_tensor, 0);  % ensure non-negative

    % Ensure resource feasibility per agent (scale down if over-used)
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

    % Build SC cells and coalition matrix
    SC = cell(M, 1);
    coalitionstru = zeros(M, N);
    agentresources = zeros(N, M, K);
    for m = 1:M
        alloc_m = squeeze(res_tensor(m, :, :)); % N x K
        if size(alloc_m, 1) == 1
            alloc_m = reshape(alloc_m, [N, K]);
        end
        % Zero out resources for non-members
        member_row = membership(m, :)';
        alloc_m(~member_row, :) = 0;

        SC{m} = alloc_m;
        % coalitionstru stores agent IDs for members
        coalitionstru(m, member_row) = [agents(member_row).id];
        agentresources(:, m, :) = alloc_m;
    end

    % Compute fitness: sum of task utilities minus resource gap penalty
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
        % Completion ratio using existing helper
        completion(m) = calc_task_completion_degree(alloc_m, demand, K);

        % Resource gap penalty (sum of unmet demand)
        allocated_sum = sum(alloc_m, 1);
        gap = max(demand - allocated_sum, 0);
        gap_penalties(m) = sum(gap);

        task_utils(m) = tasks(m).value * completion(m);
    end

    total_utility = sum(task_utils);
    total_penalty = pso.lambda_gap * sum(gap_penalties);
    fitness = total_utility - total_penalty;

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
    % Minimal Value_data compatible with compare_results / display
    Value_data = struct();
    Value_data(1).coalitionstru = sol.coalitionstru;
    Value_data(1).SC = sol.SC;
    Value_data(1).agentresources = sol.agentresources;
    Value_data(1).totalvalue = sol.total_utility;  % for direct utility read
    Value_data(1).algorithm = "Qin2025_PSO";

    % Optional fields left empty for later refinement
    Value_data(1).energy_cost = [];

    % Minimal history_data (single round)
    history_data = struct();
    history_data.rounds(1).task_utilities = sol.task_utils;
    history_data.rounds(1).task_completion = sol.completion;
    history_data.rounds(1).coalition_structure = sol.coalitionstru;
    history_data.rounds(1).SC = sol.SC;
    history_data.rounds(1).total_utility = sol.total_utility;
    history_data.rounds(1).fitness = best_fitness;

    % TODO: add belief/observation/trajectory details if needed later.
end
