function [SC_P, SC_Q, R_agent_P, R_agent_Q, R_total_P, R_total_Q] = ...
    compute_coalition_and_resource_changes(Value_data, agents, Value_Params, target, agentID, r)
% 计算 join 前/后的联盟结构与资源分配变化。
% 输出：
%   SC_P/SC_Q    : 操作前/后联盟结构 (M×N)
%   R_agent_P/Q  : 该智能体操作前/后资源分配矩阵 (M×K)
%   R_total_P/Q  : 本函数可汇总到的“该智能体对各任务的贡献”(M×K)

    %% 1) 操作前联盟结构
    SC_P = Value_data.coalitionstru;

    % agentID 兼容：优先按数组下标，否则按 agents(:).id 映射
    agentIdx = agentID;
    if agentIdx < 1 || agentIdx > numel(agents) || ~isstruct(agents(agentIdx))
        agentIdx = find([agents.id] == agentID, 1, 'first');
        if isempty(agentIdx)
            error('compute_coalition_and_resource_changes:AgentNotFound', 'agentID=%d not found in agents.', agentID);
        end
    end

    %% 2) 操作后联盟结构（加入 target）
    SC_Q = SC_P;
    SC_Q(target, agentIdx) = agentID;

    % 若存在 void 行 (M+1)，加入真实任务后清零
    if size(SC_Q, 1) >= Value_Params.M + 1
        SC_Q(Value_Params.M + 1, agentIdx) = 0;
    end

    %% 3) 操作前该智能体资源分配 (M×K)
    if ~isfield(Value_data, 'resources_matrix') || isempty(Value_data.resources_matrix)
        error('compute_coalition_and_resource_changes:MissingResourcesMatrix', ...
            'Value_data.resources_matrix is missing/empty. Please initialize it as a %dx%d matrix before calling.', ...
            Value_Params.M, Value_Params.K);
    end
    R_agent_P = Value_data.resources_matrix;

    %% 4) 操作后该智能体资源分配：r 类资源全给 target
    R_agent_Q = R_agent_P;
    % 约定：Value_data.resources 为 K×1 或 1×K 向量
    if isfield(Value_data, 'resources') && ~isempty(Value_data.resources)
        cap_r = Value_data.resources(r);
    else
        cap_r = agents(agentIdx).resources(r);
    end

    R_agent_Q(:, r) = 0;
    R_agent_Q(target, r) = cap_r;
    
    %% 5) 汇总：仅计算该智能体对各任务的贡献
    R_total_P = zeros(Value_Params.M, Value_Params.K);
    R_total_Q = zeros(Value_Params.M, Value_Params.K);

    for task_idx = 1:Value_Params.M
        if SC_P(task_idx, agentIdx) ~= 0
            R_total_P(task_idx, :) = R_total_P(task_idx, :) + R_agent_P(task_idx, :);
        end
        if SC_Q(task_idx, agentIdx) ~= 0
            R_total_Q(task_idx, :) = R_total_Q(task_idx, :) + R_agent_Q(task_idx, :);
        end
    end

end
