function delta = SA_altruistic_preference_delta(tasks, agents, SC_P, SC_Q, n, Value_Params, Value_data, targetTask, sourceTask)
% SA_altruistic_preference_delta
% 实现用户给出的利他主义偏好关系：
%
%   SC_Q ?_n SC_P  <=>  LHS(SC_Q,SC_P) > RHS(SC_Q,SC_P)
%
% 其中：
%   - SC_P: 加入/变更前联盟结构
%   - SC_Q: 加入/变更后联盟结构
%   - n:   当前决策智能体
%   - targetTask: A_j（加入/变更作用的目标任务行）
%   - sourceTask: A_i（可选，原任务行；重叠加入场景可为空，默认 M+1）
%
% 返回：
%   delta = LHS - RHS
%   若 delta > 0 表示满足偏好关系（更优），否则可按模拟退火概率接受差解。
%
% 说明：
%   由于工程里未显式定义 Mem/Mcm 集合，本实现采用以下自然映射：
%   - Mem(A_j): SC_Q 在 targetTask 行上的成员集合
%   - Mem(A_i): SC_P 在 sourceTask 行上的成员集合（若提供且在 1..M）
%   - Mcm(A(n)): 在 SC_Q 中与 n 共享任一任务联盟的所有其他成员的并集
%   - u_x(SC): 默认定义为 x 在所有加入的任务上的效用之和。
%            若 Value_Params.utilityFcn 存在，则优先调用该函数用于效用计算，便于测试。

    if nargin < 8 || isempty(targetTask)
        targetTask = [];
    end
    if nargin < 9 || isempty(sourceTask)
        sourceTask = Value_Params.M + 1;
    end

    M = Value_Params.M;

    % 自动推断 targetTask：找出 n 在 SC_Q 新增的任务行（若唯一）
    if isempty(targetTask)
        rowsP = find(SC_P(1:M, n) == n);
        rowsQ = find(SC_Q(1:M, n) == n);
        added = setdiff(rowsQ, rowsP);
        if ~isempty(added)
            targetTask = added(1);
        end
    end

    % ------------ utility helpers ------------
    function u = total_utility(agentID, SC)
        if isfield(Value_Params, 'utilityFcn') && ~isempty(Value_Params.utilityFcn)
            u = Value_Params.utilityFcn(agentID, SC, tasks, agents, Value_Params, Value_data);
            return;
        end

        u = 0;
        rows = find(SC(1:M, agentID) == agentID);
        for kRow = 1:numel(rows)
            u = u + SA_self_utility(agentID, rows(kRow), SC, agents, tasks, Value_Params, Value_data);
        end
    end

    % ------------ compute pieces ------------
    u_n_Q = total_utility(n, SC_Q);
    u_n_P = total_utility(n, SC_P);

    % Mem(A_j) \ {n}
    sum_pos_target = 0;
    if ~isempty(targetTask) && targetTask >= 1 && targetTask <= M
        memAj = find(SC_Q(targetTask, :) ~= 0);
        memAj(memAj == n) = [];
        for k = 1:numel(memAj)
            g = memAj(k);
            diff_g = total_utility(g, SC_Q) - total_utility(g, SC_P);
            sum_pos_target = sum_pos_target + max(diff_g, 0);
        end
    end

    % Mem(A_i) \ {n}
    sum_source_loss = 0;
    if ~isempty(sourceTask) && sourceTask >= 1 && sourceTask <= M
        memAi = find(SC_P(sourceTask, :) ~= 0);
        memAi(memAi == n) = [];
        for k = 1:numel(memAi)
            h = memAi(k);
            sum_source_loss = sum_source_loss + (total_utility(h, SC_P) - total_utility(h, SC_Q));
        end
    end

    % Mcm(A(n)) \ {n}: 与 n 共享任一任务的其他成员并集（在 SC_Q 上定义集合）
    co_members = [];
    rows_n = find(SC_Q(1:M, n) == n);
    for kRowN = 1:numel(rows_n)
        row = rows_n(kRowN);
        mem = find(SC_Q(row, :) ~= 0);
        co_members = union(co_members, mem);
    end
    co_members(co_members == n) = [];

    sum_u_mcm_Q = 0;
    sum_u_mcm_P = 0;
    for k = 1:numel(co_members)
        o = co_members(k);
        sum_u_mcm_Q = sum_u_mcm_Q + total_utility(o, SC_Q);
        sum_u_mcm_P = sum_u_mcm_P + total_utility(o, SC_P);
    end

    % ------------ LHS / RHS / delta ------------
    lhs = u_n_Q + sum_pos_target + sum_u_mcm_Q;
    rhs = u_n_P + sum_source_loss + sum_u_mcm_P;
    delta = lhs - rhs;
end
