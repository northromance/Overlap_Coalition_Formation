function [incremental, current_task_idx, Value_data] = Value_order(agents, tasks, Value_data, Value_Params)
    %% 1. 初始化与状态备份
    incremental = 0; 
    agentID = Value_data.agentID;
    M = Value_Params.M;
    % --- 备份原始状态 (Snapshot) ---
    AValue_data = Value_data; % 深拷贝备份
    
    %% 2. 获取当前状态与基准效用
    [current_task_idx, agent_col_idx] = find(Value_data.coalitionstru == agentID);
    
    % 计算当前效用 (Base Utility)
    cur_teammates = find(Value_data.coalitionstru(current_task_idx, :) ~= 0);
    curagentutility = Value_utility(agents, tasks, current_task_idx, agent_col_idx, ...
        cur_teammates, Value_data, Value_Params, Value_data.SC);
    
    %% 3. 试探所有可能的任务 (What-If Analysis)
    candidateagentutility = zeros(1, M + 1); 
    
    for j = 1 : M + 1
        % A. 重置到初始状态
        Value_data.coalitionstru = AValue_data.coalitionstru; 
        Value_data.SC = AValue_data.SC;
        Value_data.resources_matrix = AValue_data.resources_matrix;
        
        % B. 模拟移动
        % 更新成员结构
        Value_data.coalitionstru(current_task_idx, agent_col_idx) = 0;
        Value_data.coalitionstru(j, agent_col_idx) = agentID; 
        
        % 更新资源结构
        [~, SC_Q, ~, R_agent_Q] = StateTran.calc_move_changes(...
            Value_data, agents, Value_Params, current_task_idx, j, agent_col_idx);
        
        % 同步资源数据
        Value_data.SC = SC_Q;
        Value_data.resources_matrix = R_agent_Q;
        
        % C. 计算假设效用
        sim_teammates = find(Value_data.coalitionstru(j, :) ~= 0); % 当前小组成员
        candidateagentutility(j) = Value_utility(...
            agents, tasks, j, agent_col_idx, sim_teammates, ...
            Value_data, Value_Params, SC_Q);
    end
    
    %% 4. 决策逻辑 (Unified Decision Making)
    [max_utility, best_task_idx] = max(candidateagentutility);
    
    % 默认目标为保持现状
    target_task_idx = current_task_idx; 
    
    if max_utility == 0
        % 情况 A: 无利可图 -> 强制休息 (Void任务)
        target_task_idx = M + 1; 
        % incremental 保持 0
        
    elseif max_utility > curagentutility
        % 情况 B: 发现更优 -> 迁移 (Best任务)
        target_task_idx = best_task_idx;
        incremental = 1;
        
        % [修改]：此处不要修改 Value_data，因为马上要回滚。
        % 具体的 iteration 更新移到第 5 步回滚之后。
    end
    
    %% 5. 执行最终更新 (Final Execution)
    % [关键步骤] 先回滚到干净的初始状态 (SC, Resources, Stats 等全部恢复)
    Value_data = AValue_data; 
    
    % 如果目标任务就是当前任务，无需任何操作，直接返回备份状态即可
    if target_task_idx == current_task_idx
        return;
    end
    
    % --- 统一执行移动操作 ---
    % 1. 计算资源变化
    [~, SC_Q, ~, R_agent_Q] = StateTran.calc_move_changes(...
        Value_data, agents, Value_Params, current_task_idx, target_task_idx, agent_col_idx);
    
    % 2. 应用资源变化
    Value_data.SC = SC_Q;
    Value_data.resources_matrix = R_agent_Q;
    % 3. 应用成员结构变化
    Value_data.coalitionstru(current_task_idx, agent_col_idx) = 0;
    Value_data.coalitionstru(target_task_idx, agent_col_idx) = agentID;
    
    % --- [修复] 在回滚和物理移动完成后，再更新统计数据 ---
    % 只有当这是一个“有效进化”（incremental=1）时才更新计数
    if incremental == 1
        Value_data.iteration = Value_data.iteration + 1; 
        Value_data.unif = rand(1); 
    end
    
end