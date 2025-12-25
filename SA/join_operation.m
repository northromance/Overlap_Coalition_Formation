function [Value_data, incremental_join] = join_operation(Value_data, agents, tasks, Value_Params, probs)


incremental_join = 0;
agentID = Value_data.agentID;
Value_data.resources_matrix = zeros(Value_Params.M, Value_Params.K); % Assuming 6 resource types and M tasks

% 逐资源类型抽样候选任务
for r = 1:Value_Params.K
    
    % 根据之前的计算每个机器人对于该类型 选择某个任务的概率
    row = probs(r, :); % prob 6行 4列
    row_sum = sum(row); % 计算是否有该类型的选择概率
    if row_sum <= 0
        continue;
    end
    
    % 依照顺序选择一种任务
    % cumulative sampling（避免依赖 randsample）
    edges = cumsum(row);
    x = rand() * edges(end);
    
    % 选择出了target应该将r类型资源加入到target任务中
    target = find(edges >= x, 1, 'first');
    if isempty(target)
        continue;
    end
    
    % 只允许加入真实任务 1..M
    if target < 1 || target > Value_Params.M
        error('超出边界');
    end
    
    
    %% ========== 生成操作前后的联盟结构和资源分配矩阵 ==========
    % SC_P: 操作前联盟结构, SC_Q: 操作后联盟结构
    % R_agent_P/Q: 个体资源分配, R_total_P/Q: 联盟总资源
    [SC_P, SC_Q, R_agent_P, R_agent_Q, R_total_P, R_total_Q] = ...
        compute_coalition_and_resource_changes(Value_data, agents, Value_Params, target, agentID, r);
    
    % 更新Value_data中的资源矩阵（记录当前智能体的资源分配）
    Value_data.resources_matrix = R_agent_Q;
    
    %% ========== 计算效用差 ==========
    % 计算操作前的联盟结构效用 (基于SC_P)
    utility_before = overlap_coalition_utility(tasks, agents, SC_P, SC_Q, agentID, Value_Params, Value_data);
    
    % 计算操作后的联盟结构效用 (基于SC_Q)
    utility_after = overlap_coalition_utility(tasks, agents, SC_P, SC_Q, agentID, Value_Params, Value_data);
    
    % 计算效用差（ΔU）
    delta_U = utility_after - utility_before;
    
    %% ========== 决策过程（基于BMBT偏好和模拟退火） ==========
    accept_join = false;
    
    if delta_U > 0
        % 如果效用差大于0，直接加入联盟
        accept_join = true;
        fprintf('智能体%d: 加入任务%d(资源类型%d), ΔU=%.4f > 0\n', agentID, target, r, delta_U);
    else
        % 如果效用差不大于0，使用模拟退火概率判断是否加入联盟
        T = Value_Params.Temperature;  % 从参数中获取温度
        P_join = exp(delta_U / T);  % 计算加入联盟的概率
        
        % 根据随机数判断是否加入联盟
        if rand() < P_join
            accept_join = true;
            fprintf('智能体%d: 加入任务%d(资源类型%d), ΔU=%.4f, SA接受概率=%.4f\n', ...
                agentID, target, r, delta_U, P_join);
        else
            fprintf('智能体%d: 拒绝加入任务%d(资源类型%d), ΔU=%.4f, SA拒绝\n', ...
                agentID, target, r, delta_U);
        end
    end
    
    %% ========== 执行决策 ==========
    if accept_join
        % 接受加入操作，更新联盟结构为SC_Q
        Value_data.coalitionstru = SC_Q;
        incremental_join = incremental_join + 1;
        
        % 打印资源分配变化
        fprintf('  资源分配变化: 任务%d获得资源类型%d的数量%.2f\n', ...
            target, r, R_agent_Q(target, r));
    else
        % 拒绝加入，恢复原资源分配状态SC_P
        Value_data.resources_matrix = R_agent_P;
    end
    
    
end

