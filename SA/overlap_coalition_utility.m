function deltaU = overlap_coalition_utility(tasks, agents, Intial_coalitionstru, After_coalitionstru, agentID, Value_Params, Value_data)

    [curRow, curCol] = find(Intial_coalitionstru == agentID); % 查找智能体原来的位置
    

    [After_curRow, After_curCol] = find(After_coalitionstru == agentID); % 查找智能体移动后的位置
    

    curRow = curRow(1); % 可能有多个匹配，取第一个（通常只有一个）
    After_curRow = After_curRow(1); % 移动后的任务行号


    source_before = 0; % 源联盟中智能体移除前的效用总和
    source_after = 0; % 源联盟中智能体移除后的效用总和
    target_before = 0; % 目标联盟中不包含智能体前的效用总和
    target_after = 0; % 目标联盟中包含智能体后的效用总和


    source_members = find(Intial_coalitionstru(curRow, :) ~= 0); 
    other_target_member  = find(Intial_coalitionstru(After_curRow, :) ~= 0); 
    % 查找目标联盟中该任务行的所有成员（移动后的任务行 After_curRow）
    target_members = find(After_coalitionstru(After_curRow, :) ~= 0); 
    other_source_member = find(After_coalitionstru(curRow, :) ~= 0); 


    for m = source_members % 
        source_before = source_before + Overlap_Coalition_Formation(m, curRow, Intial_coalitionstru, agents, tasks, Value_Params, Value_data); % 计算每个成员的效用并加总
    end

end
