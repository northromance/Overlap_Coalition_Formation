function deltaU = overlap_coalition_utility(tasks, agents, Intial_coalitionstru, After_coalitionstru, agentID, Value_Params, Value_data)
    % overlap_coalition_utility
    % 目的：按论文/推导中的 BMBT 偏好判别式，计算
    %   deltaU = LHS(SC_Q, SC_P) - RHS(SC_Q, SC_P)
    % 若 deltaU > 0，则认为 SC_Q ≻_n SC_P。
    %
    % 你给出的判别式：
    %   SC_Q ≻_n SC_P  ⟺
    %     u_n(SC_Q)
    %     + Σ_{g∈Mem(A_j)\{n}} [u_g(SC_Q)-u_g(SC_P)]
    %     + Σ_{o∈Mem(A(n))\{n}} u_o(SC_Q)
    %     >
    %     u_n(SC_P)
    %     + Σ_{h∈Mem(A_i)\{n}} [u_h(SC_P)-u_h(SC_Q)]
    %     + Σ_{o∈Mem(A(n))\{n}} u_o(SC_P)
    %
    % 本函数的“集合”在工程里的落地映射：
    %   - SC_P = Intial_coalitionstru，SC_Q = After_coalitionstru
    %   - Mem(A_j)：n 在 SC_Q 中“新增加入”的任务行（new_tasks）对应行上的成员集合
    %   - Mem(A_i)：n 在 SC_P 中“离开”的任务行（source_tasks）对应行上的成员集合
    %   - Mem(A(n))：n 在 SC_Q 中参与的所有任务行的成员并集
    %
    % 注意：个体效用 u_x(·) 由 overlap_coalition_self_utility 计算。

    M = Value_Params.M;
    
    %% ==================== 1) 计算 u_n(SC_Q) 与 u_n(SC_P) ====================
    % u_n(SC_Q)：智能体 n 在新结构 SC_Q 上，对其参与的所有任务效用求和
    u_n_Q = 0;
    % rows_n_Q：n 在 SC_Q 中参与的“真实任务行”(1..M)
    rows_n_Q = find(After_coalitionstru(1:M, agentID) == agentID);
    for idx = 1:length(rows_n_Q)
        task_row = rows_n_Q(idx);
        u_n_Q = u_n_Q + overlap_coalition_self_utility(agentID, task_row, After_coalitionstru, agents, tasks, Value_Params, Value_data);
    end
    
    % rows_n_P：n 在 SC_P 中参与的“真实任务行”(1..M)
    rows_n_P = find(Intial_coalitionstru(1:M, agentID) == agentID);

    % u_n(SC_P)：智能体 n 在原结构 SC_P 上，对其参与的所有任务效用求和
    u_n_P = 0;
    for idx = 1:length(rows_n_P)
        task_row = rows_n_P(idx);
        u_n_P = u_n_P + overlap_coalition_self_utility(agentID, task_row, Intial_coalitionstru, agents, tasks, Value_Params, Value_data);
    end
    
    %% ==================== 2) LHS 第二项：新增任务行的“其他成员效用差” ====================
    % new_tasks：n 在 SC_Q 中新增加入的任务行（相对 SC_P）
    new_tasks = setdiff(rows_n_Q, rows_n_P);
    
    % sum_new_coalition_delta：Σ_{g∈Mem(A_j)\{n}} [u_g(SC_Q)-u_g(SC_P)]
    sum_new_coalition_delta = 0;
    for idx = 1:length(new_tasks)
        A_j = new_tasks(idx);
        % Mem(A_j)：任务行 A_j 上的成员集合（SC_Q 下），并排除 n
        members_Aj = find(After_coalitionstru(A_j, :) ~= 0);
        members_Aj(members_Aj == agentID) = [];
        for k = 1:length(members_Aj)
            g = members_Aj(k);
            % u_g_Q / u_g_P：同一成员 g 在同一任务行 A_j 下，在 SC_Q 与 SC_P 的效用
            u_g_Q = overlap_coalition_self_utility(g, A_j, After_coalitionstru, agents, tasks, Value_Params, Value_data);
            u_g_P = overlap_coalition_self_utility(g, A_j, Intial_coalitionstru, agents, tasks, Value_Params, Value_data);
            sum_new_coalition_delta = sum_new_coalition_delta + (u_g_Q - u_g_P);
        end
    end

    %% ==================== 3) RHS 第二项：离开任务行的“其他成员效用差” ====================
    % source_tasks：n 在 SC_P 中存在、但在 SC_Q 中不再参与的任务行（即“离开”的任务）
    source_tasks = setdiff(rows_n_P, rows_n_Q);
    % sum_source_coalition_delta：Σ_{h∈Mem(A_i)\{n}} [u_h(SC_P)-u_h(SC_Q)]
    sum_source_coalition_delta = 0;
    for idx = 1:length(source_tasks)
        A_i = source_tasks(idx);
        % Mem(A_i)：任务行 A_i 上的成员集合（SC_P 下），并排除 n
        members_Ai = find(Intial_coalitionstru(A_i, :) ~= 0);
        members_Ai(members_Ai == agentID) = [];
        for k = 1:length(members_Ai)
            h = members_Ai(k);
            % u_h_P / u_h_Q：同一成员 h 在同一任务行 A_i 下，在 SC_P 与 SC_Q 的效用
            u_h_P = overlap_coalition_self_utility(h, A_i, Intial_coalitionstru, agents, tasks, Value_Params, Value_data);
            u_h_Q = overlap_coalition_self_utility(h, A_i, After_coalitionstru, agents, tasks, Value_Params, Value_data);
            sum_source_coalition_delta = sum_source_coalition_delta + (u_h_P - u_h_Q);
        end
    end
    
    %% ==================== 4) 构造 Mem(A(n))：n 相关联盟成员并集 ====================
    % all_members_An：Mem(A(n))\{n}
    % 定义：在 SC_Q 中，n 参与的所有任务行上出现过的成员的并集（排除 n 自身）
    all_members_An = [];
    for idx = 1:length(rows_n_Q)
        task_row = rows_n_Q(idx);
        members_task = find(After_coalitionstru(task_row, :) ~= 0);
        all_members_An = union(all_members_An, members_task);
    end
    all_members_An(all_members_An == agentID) = [];
    
    %% ==================== 5) LHS 第三项：Mem(A(n)) 成员在 SC_Q 下的效用和 ====================
    % sum_An_members_Q：Σ_{o∈Mem(A(n))\{n}} u_o(SC_Q)
    sum_An_members_Q = 0;
    for k = 1:length(all_members_An)
        o = all_members_An(k);
        % rows_o_Q：成员 o 在 SC_Q 中参与的所有真实任务行
        rows_o_Q = find(After_coalitionstru(1:M, o) == o);
        for idx = 1:length(rows_o_Q)
            task_row = rows_o_Q(idx);
            sum_An_members_Q = sum_An_members_Q + overlap_coalition_self_utility(o, task_row, After_coalitionstru, agents, tasks, Value_Params, Value_data);
        end
    end

    %% ==================== 6) RHS 第三项：Mem(A(n)) 成员在 SC_P 下的效用和 ====================
    % sum_An_members_P：Σ_{o∈Mem(A(n))\{n}} u_o(SC_P)
    % 说明：这里使用同一组 Mem(A(n))（由 SC_Q 确定的并集），但在 SC_P 下计算效用。
    sum_An_members_P = 0;
    for k = 1:length(all_members_An)
        o = all_members_An(k);
        % rows_o_P：成员 o 在 SC_P 中参与的所有真实任务行
        rows_o_P = find(Intial_coalitionstru(1:M, o) == o);
        for idx = 1:length(rows_o_P)
            task_row = rows_o_P(idx);
            sum_An_members_P = sum_An_members_P + overlap_coalition_self_utility(o, task_row, Intial_coalitionstru, agents, tasks, Value_Params, Value_data);
        end
    end
    
    %% ==================== 7) 汇总：deltaU = LHS - RHS ====================
    % LHS = u_n(SC_Q) + 新联盟其他成员效用差 + Mem(A(n))成员效用(新结构)
    % RHS = u_n(SC_P) + 原联盟其他成员效用差 + Mem(A(n))成员效用(原结构)
    lhs = u_n_Q + sum_new_coalition_delta + sum_An_members_Q;
    rhs = u_n_P + sum_source_coalition_delta + sum_An_members_P;
    deltaU = lhs - rhs;



end
