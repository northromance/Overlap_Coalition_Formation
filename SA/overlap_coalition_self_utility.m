function individual_utility = overlap_coalition_self_utility(n, task_m, SC, agents, tasks, Value_Params, agent_belief)
% Compute utility of agent n for task task_m within coalition SC.
% utility_n(C) = r_n(C) * V_C * D_C - (t_wait * alpha + T_exec * beta)

    if task_m < 1 || task_m > Value_Params.M
        individual_utility = 0;
        return;
    end

    % Coalition members for this task
    member_idx = find(any(SC{task_m} > 0, 2))';
    if isempty(member_idx)
        individual_utility = 0;
        return;
    end

    % Expected resource demand using quantile or expectation
    if isfield(Value_Params, 'task_type_demands') && ~isempty(Value_Params.task_type_demands)
        b = agent_belief(task_m, :);
        num_types = size(Value_Params.task_type_demands, 1);
        use_b = b(1:num_types);
        if isfield(Value_Params, 'resource_confidence') && Value_Params.resource_confidence > 0
            expected_demand = WorldSim.calculate_demand_quantile(use_b, Value_Params.task_type_demands, Value_Params.resource_confidence);
        else
            expected_demand = use_b * Value_Params.task_type_demands;
        end
    else
        expected_demand = tasks(task_m).resource_demand;
    end

    % Completion degree
    D_C = WorldSim.calc_task_completion_degree(SC{task_m}, expected_demand, Value_Params.K);
    if D_C == 0
        individual_utility = 0;
        return;
    end

    % Resource contribution ratio r_n(C)
    r_n_C = OCFUtils.calc_resource_contribution_ratio(SC{task_m}, n, member_idx);

    % Expected value V_C
    b = agent_belief(task_m, :);
    v = tasks(task_m).WORLD.value;
    V_C = sum(v .* b(1:length(v)));

    % Energy costs
    [t_fly, t_wait, T_exec] = calc_energy_cost(n, task_m, SC, agents, tasks, Value_Params);

    revenue = r_n_C * V_C * D_C;
    alpha_fly = agents(n).fuel;
    alpha_wait = agents(n).wait_fuel;
    cost = t_fly * alpha_fly + t_wait * alpha_wait + T_exec * agents(n).beta;
    individual_utility = revenue - cost;
end

%% Helper functions
function [t_fly, t_wait, T_exec] = calc_energy_cost(n, task_m, SC, agents, tasks, Value_Params)
    % Total fly/wait/execute time for agent n up to and including task_m
    agent_tasks = find(cellfun(@(x) any(x(n, :) > 0), SC))';
    if isempty(agent_tasks) || ~ismember(task_m, agent_tasks)
        t_fly = 0;
        t_wait = 0;
        T_exec = 0;
        return;
    end

    % Resource allocation matrix for this agent
    R_agent = zeros(Value_Params.M, Value_Params.K);
    for m = 1:Value_Params.M
        R_agent(m, :) = SC{m}(n, :);
    end

    % Use existing energy_cost routine
    [t_fly, ~, ~, ~, orderedTasks, ~, t_wait] = energy_cost(n, agent_tasks, agents, tasks, Value_Params, R_agent, SC);

    % Execution time up to task_m
    task_pos = find(orderedTasks == task_m, 1);
    T_exec = calc_exec_time_to_task(orderedTasks(1:task_pos), R_agent, tasks, Value_Params);
end

function T = calc_exec_time_to_task(task_list, R_agent, tasks, Value_Params)
    T = 0;
    tol = 1e-9;
    for ii = 1:numel(task_list)
        m = task_list(ii);
        used = R_agent(m, :) > tol;
        if isfield(tasks, 'duration_by_resource')
            dur = tasks(m).duration_by_resource(:)';
            dur = dur(1:min(numel(dur), Value_Params.K));
            used = used(1:numel(dur));
            T = T + sum(dur(used));
        elseif isfield(tasks, 'duration')
            T = T + tasks(m).duration;
        else
            T = T + 1.0;
        end
    end
end
