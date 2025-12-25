function deltaU = overlap_coalition_utility(tasks, agents, Intial_coalitionstru, After_coalitionstru, agentID, Value_Params, Value_data)
    % overlap_coalition_utility: 基于BMBT序计算联盟结构的效用（LHS部分）
    % 
    % 实现公式（BMBT序左边）：
    %   deltaU = u_n(SC_Q) + sum_{g in Mem(A_j)\{n}} [u_g(SC_Q) - u_g(SC_P)] 
    %                      + sum_{o in Mem(A(n))\{n}} u_o(SC_Q)
    %
    % 输入：
    %   Intial_coalitionstru (SC_P): 初始联盟结构矩阵
    %   After_coalitionstru  (SC_Q): 更新后联盟结构矩阵
    %   agentID (n): 决策智能体ID
    % 输出：
    %   deltaU: 三项之和

    M = Value_Params.M;
    
    % ========== 第一项：u_n(SC_Q) ==========
    % 智能体 n 在新结构中的总效用
    u_n_Q = 0;
    rows_n_Q = find(After_coalitionstru(1:M, agentID) == agentID);
    for idx = 1:length(rows_n_Q)
        task_row = rows_n_Q(idx);
        u_n_Q = u_n_Q + overlap_coalition_self_utility(agentID, task_row, After_coalitionstru, agents, tasks, Value_Params, Value_data);
    end
    
    rows_n_P = find(Intial_coalitionstru(1:M, agentID) == agentID);
    
    % ========== 第二项：sum_{g in Mem(A_j)\{n}} [u_g(SC_Q) - u_g(SC_P)] ==========
    % 新联盟成员效用差
    new_tasks = setdiff(rows_n_Q, rows_n_P);
    
    sum_new_coalition_delta = 0;
    for idx = 1:length(new_tasks)
        A_j = new_tasks(idx);
        % Mem(A_j) \ {n}：新联盟中除n外的其他成员
        members_Aj = find(After_coalitionstru(A_j, :) ~= 0);
        members_Aj(members_Aj == agentID) = [];
        for k = 1:length(members_Aj)
            g = members_Aj(k);
            u_g_Q = overlap_coalition_self_utility(g, A_j, After_coalitionstru, agents, tasks, Value_Params, Value_data);
            u_g_P = overlap_coalition_self_utility(g, A_j, Intial_coalitionstru, agents, tasks, Value_Params, Value_data);
            sum_new_coalition_delta = sum_new_coalition_delta + (u_g_Q - u_g_P);
        end
    end
    
    % ========== 第三项：A(n) 中其他联盟成员的效用（新结构） ==========
    % 关联联盟成员效用
    % A(n) 定义：n 参与的所有sum_{o in Mem(A(n))\{n}} u_o(SC_Q) ==========
    all_members_An = [];
    for idx = 1:length(rows_n_Q)
        task_row = rows_n_Q(idx);
        members_task = find(After_coalitionstru(task_row, :) ~= 0);
        all_members_An = union(all_members_An, members_task);
    end
    all_members_An(all_members_An == agentID) = [];
    
    sum_An_members_Q = 0;
    for k = 1:length(all_members_An)
        o = all_members_An(k);
        rows_o_Q = find(After_coalitionstru(1:M, o) == o);
        for idx = 1:length(rows_o_Q)
            task_row = rows_o_Q(idx);
            sum_An_members_Q = sum_An_members_Q + overlap_coalition_self_utility(o, task_row, After_coalitionstru, agents, tasks, Value_Params, Value_data);
        end
    end
    
    % ========== 三项之和 ==========
    deltaU = u_n_Q + sum_new_coalition_delta + sum_An_members_Q;
end
