function task_utilities = calculate_coalition_utilities(SC, agents, tasks, Value_Params, Value_data)
% 计算每个任务的联盟总效用（基于实际需求和价值）

    M = Value_Params.M;
    N = Value_Params.N;
    task_utilities = zeros(M, 1);

    for m = 1:M
        participants = find(any(SC{m} > 0, 2))';
        if isempty(participants)
            continue;
        end
        
        for i = participants
            task_utilities(m) = task_utilities(m) + ...
                overlap_coalition_self_utility_actual(i, m, SC, agents, tasks, Value_Params);
        end
    end
end
