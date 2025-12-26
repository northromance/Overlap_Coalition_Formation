function [SC_P, SC_Q, R_agent_P, R_agent_Q, R_total_P, R_total_Q] = ...
    compute_coalition_and_resource_changes(Value_data, agents, Value_Params, target, agentID, r)
% COMPUTE_COALITION_AND_RESOURCE_CHANGES 计算联盟结构和资源分配矩阵的变化
%
% 输入参数:
%   Value_data - 包含当前联盟结构和资源分配信息的结构体
%   agents - 所有智能体的信息数组
%   Value_Params - 包含M(任务数), N(智能体数), K(资源类型数)的参数结构体
%   target - 目标任务索引
%   agentID - 当前智能体ID
%   r - 资源类型索引
%
% 输出参数:
%   SC_P - 操作前的联盟结构 (M×N) [Initial Coalition Structure]
%   SC_Q - 操作后的联盟结构 (M×N) [After Coalition Structure]
%   R_agent_P - 操作前该智能体的资源分配 (M×K) [Initial Agent Resources]
%   R_agent_Q - 操作后该智能体的资源分配 (M×K) [After Agent Resources]
%   R_total_P - 操作前联盟总资源 (M×K) [Initial Total Coalition Resources]
%   R_total_Q - 操作后联盟总资源 (M×K) [After Total Coalition Resources]

    %% 1. 操作前的联盟结构 SC_P (Initial Coalition Structure)
    SC_P = Value_data.coalitionstru;

    % agentID 可能是“ID”而非数组索引；这里优先按索引使用，否则按 agents(:).id 映射
    agentIdx = agentID;
    if agentIdx < 1 || agentIdx > numel(agents) || ~isstruct(agents(agentIdx))
        agentIdx = find([agents.id] == agentID, 1, 'first');
        if isempty(agentIdx)
            error('compute_coalition_and_resource_changes:AgentNotFound', 'agentID=%d not found in agents.', agentID);
        end
    end

    %% 2. 操作后的联盟结构（智能体加入任务target）
    SC_Q = SC_P;
    SC_Q(target, agentIdx) = agentID;

    % 若存在空任务行 (M+1)，加入真实任务时清除空任务行
    if size(SC_Q, 1) >= Value_Params.M + 1
        SC_Q(Value_Params.M + 1, agentIdx) = 0;
    end

    %% 3. 操作前的个体资源分配矩阵
    R_agent_P = Value_data.resources_matrix;

    %% 4. 操作后的个体资源分配矩阵（将 r 类型资源分配给 target 任务）
    R_agent_Q = R_agent_P;
    R_agent_Q(target, r) = Value_data.resources(r, 1);
    
    %% 5. 计算联盟总资源分配矩阵变化
    % R_total_P/Q: M×K矩阵，每个任务从所有智能体获得的总资源
    R_total_P = zeros(Value_Params.M, Value_Params.K);  % 操作前联盟总资源
    R_total_Q = zeros(Value_Params.M, Value_Params.K);  % 操作后联盟总资源
    
    % 计算操作前的联盟总资源 R_total_P（遍历所有智能体）
    for task_idx = 1:Value_Params.M
        for agent_idx = 1:Value_Params.N
            if SC_P(task_idx, agent_idx) ~= 0
                for res_type = 1:Value_Params.K
                    R_total_P(task_idx, res_type) = R_total_P(task_idx, res_type) + agents(agent_idx).resources(res_type);
                end
            end
        end
    end
    
    % 计算操作后的联盟总资源 R_total_Q
    for task_idx = 1:Value_Params.M
        for agent_idx = 1:Value_Params.N
            if SC_Q(task_idx, agent_idx) ~= 0
                for res_type = 1:Value_Params.K
                    R_total_Q(task_idx, res_type) = R_total_Q(task_idx, res_type) + agents(agent_idx).resources(res_type);
                end
            end
        end
    end

end
