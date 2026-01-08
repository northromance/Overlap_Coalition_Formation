function individual_utility = overlap_coalition_self_utility_actual(n, task_m, SC, agents, tasks, Value_Params)
% 计算智能体在特定任务联盟中的个体效用（基于实际需求和价值）
% utility_n(C) = r_n(C) × V_C × D_C - (t_wait × α + T_exec × β)

    if task_m < 1 || task_m > Value_Params.M
        individual_utility = 0;
        return;
    end

    % 获取联盟成员
    member_idx = find(any(SC{task_m} > 0, 2))';
    if isempty(member_idx)
        individual_utility = 0;
        return;
    end

    % 使用实际资源需求
    actual_demand = tasks(task_m).resource_demand;

    % 计算完成度 D_C
    D_C = calc_completion_degree(SC{task_m}, actual_demand, Value_Params.K);
    if D_C == 0
        individual_utility = 0;
        return;
    end

    % 计算资源贡献比例 r_n(C)
    r_n_C = calc_contribution_ratio(SC{task_m}, n, member_idx);

    % 使用实际价值
    V_C = tasks(task_m).value;

    % 计算能量消耗
    [t_wait, T_exec] = calc_energy_cost(n, task_m, SC, agents, tasks, Value_Params);

    % 计算最终效用
    revenue = r_n_C * V_C * D_C;
    cost = t_wait * agents(n).fuel + T_exec * agents(n).beta;
    individual_utility = revenue - cost;
end

%% ========== 辅助函数 ==========

function D_C = calc_completion_degree(SC_m, demand, K)
    Z_c = nnz(demand > 1e-9);
    if Z_c == 0
        D_C = 0;
        return;
    end
    
    D_C = 0;
    for j = 1:K
        if demand(j) > 1e-9
            ratio = min(sum(SC_m(:, j)) / demand(j), 1.0);
            D_C = D_C + ratio;
        end
    end
    D_C = D_C / Z_c;
end

function r_n = calc_contribution_ratio(SC_m, n, members)
    A_n = norm(SC_m(n, :));
    total = sum(arrayfun(@(i) norm(SC_m(i, :)), members));
    r_n = A_n / max(total, 1e-9);
end

function [t_wait, T_exec] = calc_energy_cost(n, task_m, SC, agents, tasks, Value_Params)
    agent_tasks = find(cellfun(@(x) any(x(n, :) > 0), SC))';
    
    if isempty(agent_tasks) || ~ismember(task_m, agent_tasks)
        t_wait = 0;
        T_exec = 0;
        return;
    end
    
    R_agent = zeros(Value_Params.M, Value_Params.K);
    for m = 1:Value_Params.M
        R_agent(m, :) = SC{m}(n, :);
    end
    
    [t_wait, ~, ~, ~, orderedTasks] = energy_cost(n, agent_tasks, agents, tasks, Value_Params, R_agent, SC);
    
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
