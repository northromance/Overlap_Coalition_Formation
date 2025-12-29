function deltaU = overlap_coalition_utility(tasks, agents, SC_P, SC_Q, agentID, Value_Params, Value_data)
    % overlap_coalition_utility
    % 目的：按论文/推导中的 BMBT 偏好判别式，计算
    %   deltaU = LHS(SC_Q, SC_P) - RHS(SC_Q, SC_P)
    % 若 deltaU > 0，则认为 SC_Q ≻_n SC_P。
    %
    % 输入：
    %   SC_P/SC_Q - 操作前/后的资源联盟结构（cell数组，长度M）
    %               SC{m}是N×K矩阵，表示任务m上各智能体的资源分配
    %
    % 判别式：
    %   SC_Q ≻_n SC_P  ⟺
    %     u_n(SC_Q)
    %     + Σ_{g∈Mem(A_j)\{n}} [u_g(SC_Q)-u_g(SC_P)]
    %     + Σ_{o∈Mem(A(n))\{n}} u_o(SC_Q)
    %     >
    %     u_n(SC_P)
    %     + Σ_{h∈Mem(A_i)\{n}} [u_h(SC_P)-u_h(SC_Q)]
    %     + Σ_{o∈Mem(A(n))\{n}} u_o(SC_P)

    M = Value_Params.M;
    
    % 辅助函数：判断智能体是否参与某任务（该任务上有任何资源分配）
    function participated = is_participating(SC, task_m, agent_n)
        if any(SC{task_m}(agent_n, :) > 0)
            participated = true;
        else
            participated = false;
        end
    end
    
    % 辅助函数：获取任务m的成员列表（有资源分配的智能体）
    function members = get_task_members(SC, task_m, N)
        members = [];
        for n = 1:N
            if any(SC{task_m}(n, :) > 0)
                members = [members, n];
            end
        end
    end
    
    %% ==================== 1) 找出智能体n参与的任务 ====================
    rows_n_Q = [];
    for m = 1:M
        if is_participating(SC_Q, m, agentID)
            rows_n_Q = [rows_n_Q, m];
        end
    end
    
    rows_n_P = [];
    for m = 1:M
        if is_participating(SC_P, m, agentID)
            rows_n_P = [rows_n_P, m];
        end
    end
    
    %% ==================== 2) 计算 u_n(SC_Q) 与 u_n(SC_P) ====================
    u_n_Q = 0;
    for idx = 1:length(rows_n_Q)
        task_row = rows_n_Q(idx);
        u_n_Q = u_n_Q + overlap_coalition_self_utility(agentID, task_row, SC_Q, agents, tasks, Value_Params, Value_data);
    end
    
    u_n_P = 0;
    for idx = 1:length(rows_n_P)
        task_row = rows_n_P(idx);
        u_n_P = u_n_P + overlap_coalition_self_utility(agentID, task_row, SC_P, agents, tasks, Value_Params, Value_data);
    end
    
    %% ==================== 3) LHS 第二项：新增任务的"其他成员效用差" ====================
    new_tasks = setdiff(rows_n_Q, rows_n_P);
    
    sum_new_coalition_delta = 0;
    for idx = 1:length(new_tasks)
        A_j = new_tasks(idx);
        % 获取任务A_j上的成员（SC_Q下），排除n
        members_Aj = get_task_members(SC_Q, A_j, Value_Params.N);
        members_Aj(members_Aj == agentID) = [];
        
        for k = 1:length(members_Aj)
            g = members_Aj(k);
            u_g_Q = overlap_coalition_self_utility(g, A_j, SC_Q, agents, tasks, Value_Params, Value_data);
            u_g_P = overlap_coalition_self_utility(g, A_j, SC_P, agents, tasks, Value_Params, Value_data);
            sum_new_coalition_delta = sum_new_coalition_delta + (u_g_Q - u_g_P);
        end
    end

    %% ==================== 4) RHS 第二项：离开任务的"其他成员效用差" ====================
    source_tasks = setdiff(rows_n_P, rows_n_Q);
    
    sum_source_coalition_delta = 0;
    for idx = 1:length(source_tasks)
        A_i = source_tasks(idx);
        % 获取任务A_i上的成员（SC_P下），排除n
        members_Ai = get_task_members(SC_P, A_i, Value_Params.N);
        members_Ai(members_Ai == agentID) = [];
        
        for k = 1:length(members_Ai)
            h = members_Ai(k);
            u_h_P = overlap_coalition_self_utility(h, A_i, SC_P, agents, tasks, Value_Params, Value_data);
            u_h_Q = overlap_coalition_self_utility(h, A_i, SC_Q, agents, tasks, Value_Params, Value_data);
            sum_source_coalition_delta = sum_source_coalition_delta + (u_h_P - u_h_Q);
        end
    end
    
    %% ==================== 5) 构造 Mem(A(n))：n 相关联盟成员并集 ====================
    all_members_An = [];
    for idx = 1:length(rows_n_Q)
        task_row = rows_n_Q(idx);
        members_task = get_task_members(SC_Q, task_row, Value_Params.N);
        all_members_An = union(all_members_An, members_task);
    end
    all_members_An(all_members_An == agentID) = [];
    
    %% ==================== 6) LHS 第三项：Mem(A(n)) 成员在 SC_Q 下的效用和 ====================
    sum_An_members_Q = 0;
    for k = 1:length(all_members_An)
        o = all_members_An(k);
        % 找出成员o在SC_Q中参与的所有任务
        for m = 1:M
            if is_participating(SC_Q, m, o)
                sum_An_members_Q = sum_An_members_Q + overlap_coalition_self_utility(o, m, SC_Q, agents, tasks, Value_Params, Value_data);
            end
        end
    end

    %% ==================== 7) RHS 第三项：Mem(A(n)) 成员在 SC_P 下的效用和 ====================
    sum_An_members_P = 0;
    for k = 1:length(all_members_An)
        o = all_members_An(k);
        % 找出成员o在SC_P中参与的所有任务
        for m = 1:M
            if is_participating(SC_P, m, o)
                sum_An_members_P = sum_An_members_P + overlap_coalition_self_utility(o, m, SC_P, agents, tasks, Value_Params, Value_data);
            end
        end
    end
    
    %% ==================== 8) 汇总：deltaU = LHS - RHS ====================
    lhs = u_n_Q + sum_new_coalition_delta + sum_An_members_Q;
    rhs = u_n_P + sum_source_coalition_delta + sum_An_members_P;
    deltaU = lhs - rhs;

end
