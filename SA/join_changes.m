function [SC_P, SC_Q, R_agent_P, R_agent_Q] = join_changes(Value_data, agents, Value_Params, target, agentID, r)
    % join_changes 计算 join 操作前后的全局结构与个体状态变化。
    % 输入与输出定义同原函数...

    M = Value_Params.M;
    % K = Value_Params.K; % K 在此函数内部不再直接需要，被工具函数封装了
    
    %% 0. 索引转换与校验
    % 确保获取的是矩阵中的行索引
    if agentID >= 1 && agentID <= numel(agents) && isstruct(agents(agentID)) && agents(agentID).id == agentID
        agentIdx = agentID;
    else
        agentIdx = find([agents.id] == agentID, 1, 'first');
        if isempty(agentIdx)
            error('join_changes:AgentNotFound', 'agentID=%d not found.', agentID);
        end
    end

    %% 1. 获取操作前状态 (P)
    SC_P = Value_data.SC; % 引用当前状态
    
    % [凝练点] 直接调用工具函数提取操作前的个体矩阵
    R_agent_P = OCFUtils.get_agent_resource_matrix(SC_P, agentIdx, Value_Params);

    %% 2. 构建操作后状态 (Q)
    SC_Q = SC_P; % 复制 Cell 数组 (MATLAB Copy-on-Write 机制，开销较小)
    
    % 获取该资源类型的可用量（假设全量投入）
    cap_r = Value_data.resources(r); % 注意：这里 Value_data.resources 应为当前 agent 的资源，需确认数据源
    % 如果 Value_data.resources 是全局参数，需改为 agents(agentIdx).resources(r)

    % 执行 Join：更新目标任务的分配矩阵
    % 注意：如果 SC_P{target} 是空的，这里可能需要先初始化 zeros(N, K)
    if isempty(SC_Q{target})
        SC_Q{target} = zeros(Value_Params.N, Value_Params.K);
    end
    SC_Q{target}(agentIdx, r) = cap_r;

    %% 3. 获取操作后状态 (Q) 的个体视图
    % [凝练点] 再次调用工具函数提取操作后的个体矩阵
    R_agent_Q = OCFUtils.get_agent_resource_matrix(SC_Q, agentIdx, Value_Params);
end