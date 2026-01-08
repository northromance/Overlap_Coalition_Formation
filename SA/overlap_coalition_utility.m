function deltaU = overlap_coalition_utility(tasks, agents, SC_P, SC_Q, agentID, Value_Params, Value_data)
% 计算 deltaU = LHS(SC_Q, SC_P) - RHS(SC_Q, SC_P)
% 若 deltaU > 0，则 SC_Q ≻_n SC_P

    M = Value_Params.M;
    N = Value_Params.N;
    
    % 获取智能体n在SC_Q和SC_P中参与的任务
    rows_n_Q = find(cellfun(@(x) any(x(agentID, :) > 0), SC_Q));
    rows_n_P = find(cellfun(@(x) any(x(agentID, :) > 0), SC_P));
    
    % 计算 u_n(SC_Q) 与 u_n(SC_P)
    u_n_Q = sum_utility(agentID, rows_n_Q, SC_Q, agents, tasks, Value_Params, Value_data.initbelief);
    u_n_P = sum_utility(agentID, rows_n_P, SC_P, agents, tasks, Value_Params, Value_data.initbelief);
    
    % LHS第二项：新增任务的其他成员效用差
    new_tasks = setdiff(rows_n_Q, rows_n_P);
    sum_new_delta = 0;
    for idx = 1:length(new_tasks)
        A_j = new_tasks(idx);
        members = get_members(SC_Q, A_j, N);
        members(members == agentID) = [];
        for k = 1:length(members)
            g = members(k);
            sum_new_delta = sum_new_delta + ...
                overlap_coalition_self_utility(g, A_j, SC_Q, agents, tasks, Value_Params, Value_data.other{g}.initbelief) - ...
                overlap_coalition_self_utility(g, A_j, SC_P, agents, tasks, Value_Params, Value_data.other{g}.initbelief);
        end
    end

    % RHS第二项：离开任务的其他成员效用差
    source_tasks = setdiff(rows_n_P, rows_n_Q);
    sum_source_delta = 0;
    for idx = 1:length(source_tasks)
        A_i = source_tasks(idx);
        members = get_members(SC_P, A_i, N);
        members(members == agentID) = [];
        for k = 1:length(members)
            h = members(k);
            sum_source_delta = sum_source_delta + ...
                overlap_coalition_self_utility(h, A_i, SC_P, agents, tasks, Value_Params, Value_data.other{h}.initbelief) - ...
                overlap_coalition_self_utility(h, A_i, SC_Q, agents, tasks, Value_Params, Value_data.other{h}.initbelief);
        end
    end
    
    % 构造 Mem(A(n))：n相关联盟成员并集
    all_members_An = [];
    for idx = 1:length(rows_n_Q)
        all_members_An = union(all_members_An, get_members(SC_Q, rows_n_Q(idx), N));
    end
    all_members_An(all_members_An == agentID) = [];
    
    % LHS/RHS第三项：Mem(A(n))成员效用和
    sum_An_Q = 0;
    sum_An_P = 0;
    for k = 1:length(all_members_An)
        o = all_members_An(k);
        tasks_o_Q = find(cellfun(@(x) any(x(o, :) > 0), SC_Q));
        tasks_o_P = find(cellfun(@(x) any(x(o, :) > 0), SC_P));
        sum_An_Q = sum_An_Q + sum_utility(o, tasks_o_Q, SC_Q, agents, tasks, Value_Params, Value_data.other{o}.initbelief);
        sum_An_P = sum_An_P + sum_utility(o, tasks_o_P, SC_P, agents, tasks, Value_Params, Value_data.other{o}.initbelief);
    end
    
    % 汇总
    lhs = u_n_Q + sum_new_delta + sum_An_Q;
    rhs = u_n_P + sum_source_delta + sum_An_P;
    deltaU = lhs - rhs;
end

function members = get_members(SC, task_m, N)
    members = find(any(SC{task_m} > 0, 2))';
end

function total = sum_utility(agent, task_list, SC, agents, tasks, Value_Params, belief)
    total = 0;
    for idx = 1:length(task_list)
        total = total + overlap_coalition_self_utility(agent, task_list(idx), SC, agents, tasks, Value_Params, belief);
    end
end
