function [SC_P, SC_Q, R_agent_P, R_agent_Q, R_total_P, R_total_Q] = ...
    compute_coalition_and_resource_changes(Value_data, agents, Value_Params, target, agentID, r)
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
%   R_total_P/Q  - （保留用于兼容）与R_agent_P/Q相同

    M = Value_Params.M;
    K = Value_Params.K;

    % agentID 转换为数组索引
    agentIdx = agentID;
    if agentIdx < 1 || agentIdx > numel(agents) || ~isstruct(agents(agentIdx))
        agentIdx = find([agents.id] == agentID, 1, 'first');
        if isempty(agentIdx)
            error('compute_coalition_and_resource_changes:AgentNotFound', 'agentID=%d not found in agents.', agentID);
        end
    end

    %% 1) 操作前资源联盟结构 SC_P（深拷贝cell数组）
    if ~isfield(Value_data, 'SC') || isempty(Value_data.SC)
        error('compute_coalition_and_resource_changes:MissingSC', 'Value_data.SC is missing or empty.');
    end
    
    SC_P = cell(M, 1);
    for m = 1:M
        SC_P{m} = Value_data.SC{m};  % 复制每个任务的资源分配矩阵
    end

    %% 2) 操作后资源联盟结构 SC_Q（智能体agentID对任务target分配资源类型r）
    SC_Q = cell(M, 1);
    for m = 1:M
        SC_Q{m} = SC_P{m};  % 先复制
    end
    
    % 获取该智能体资源类型r的可用量
    if isfield(Value_data, 'resources') && ~isempty(Value_data.resources)
        cap_r = Value_data.resources(r);
    else
        cap_r = agents(agentIdx).resources(r);
    end
    
    % join操作：智能体agentIdx把资源类型r的全部容量分配给target任务
    % 首先清空该智能体在所有任务上的资源类型r分配
    for m = 1:M
        SC_Q{m}(agentIdx, r) = 0;
    end
    % 然后把所有资源类型r分配给target任务
    SC_Q{target}(agentIdx, r) = cap_r;

    %% 3) 提取该智能体操作前/后对各任务的资源分配 (M×K矩阵)
    % R_agent_P(m, k) = 智能体agentIdx在操作前对任务m分配的资源类型k的数量
    R_agent_P = zeros(M, K);
    R_agent_Q = zeros(M, K);
    
    for m = 1:M
        R_agent_P(m, :) = SC_P{m}(agentIdx, :);  % 从SC_P中提取该智能体的分配
        R_agent_Q(m, :) = SC_Q{m}(agentIdx, :);  % 从SC_Q中提取该智能体的分配
    end
    
    %% 4) R_total_P/Q 保持与 R_agent_P/Q 相同（用于兼容旧接口）
    R_total_P = R_agent_P;
    R_total_Q = R_agent_Q;

end
