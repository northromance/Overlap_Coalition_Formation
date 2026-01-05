function [SC_P, SC_Q, R_agent_P, R_agent_Q] = ...
    join_changes(Value_data, agents, Value_Params, target, agentID, r)
% 计算 join 前/后的资源联盟结构与资源分配变化。
% 
% 输入：
%   Value_data   - 包含SC（cell数组）、coalitionstru等字段
%   agents       - 智能体结构体数组
%   Value_Params - 参数结构（M, N, K等）
%   target       - 目标任务索引（要加入的任务）
%   agentID      - 当前智能体ID
%   r            - 资源类型索引（该次加入操作使用的资源类型）
%
% 输出：
%   SC_P/SC_Q    - 操作前/后资源联盟结构（cell数组，长度M）
%                  SC{m}是N×K矩阵，表示任务m上各智能体的资源分配
%   R_agent_P/Q  - 该智能体操作前/后对各任务的资源分配矩阵 (M×K)

    M = Value_Params.M;
    K = Value_Params.K;
    N = Value_Params.N;

    % agentID 转换为数组索引
    agentIdx = agentID;
    if agentIdx < 1 || agentIdx > numel(agents) || ~isstruct(agents(agentIdx))
        agentIdx = find([agents.id] == agentID, 1, 'first');
        if isempty(agentIdx)
            error('compute_coalition_and_resource_changes:AgentNotFound', 'agentID=%d not found in agents.', agentID);
        end
    end

    %% 1) 操作前资源联盟结构 SC_P（深拷贝）
    SC_P = Value_data.SC;

    %% 2) 操作后资源联盟结构 SC_Q（智能体agentID对任务target分配资源类型r）
    SC_Q = cell(M, 1);
    for m = 1:M
        SC_Q{m} = SC_P{m};  % 先复制
    end
    
    % 获取该智能体资源类型r的可用量
    cap_r = Value_data.resources(r);
    
    % join操作：智能体agentIdx将资源类型r分配给target任务
    % 注意：资源可复用（重叠联盟），无需清除其他任务的分配
    SC_Q{target}(agentIdx, r) = cap_r;

    %% 3) 提取该智能体操作前/后对各任务的资源分配 (M×K矩阵)
    % R_agent_P(m, k) = 智能体agentIdx在操作前对任务m分配的资源类型k的数量
    R_agent_P = zeros(M, K);
    R_agent_Q = zeros(M, K);
    
    for m = 1:M
        R_agent_P(m, :) = SC_P{m}(agentIdx, :);  % 从 SC_P 中提取该智能体的分配
        R_agent_Q(m, :) = SC_Q{m}(agentIdx, :);  % 从 SC_Q 中提取该智能体的分配
    end

end
