function [incremental,curnumberrow,Value_data]=Overlap_Coalition_Formation(agents, tasks, Value_data, Value_Params,counter)


%% 随机选择资源离开联盟（支持重叠联盟：agent 可同时属于多个任务）
% 获取当前 agent 在多少任务中（可能为 0..M）
currentRows = find(Value_data.coalitionstru(:, Value_data.agentID) == Value_data.agentID);

% 先随机选择一个当前已加入的任务（如果有），并立即执行退出操作
% 这样实现确定性的“先选任务再退出”的行为，符合重叠联盟资源分配需求
if ~isempty(currentRows)
    idx = randi(length(currentRows));
    left_row = currentRows(idx);
else
    left_row = [];
end

% 立即执行退出操作：将对应位置置 0，表示完全退出该任务
if ~isempty(left_row)
    Value_data.coalitionstru(left_row, Value_data.agentID) = 0;
end

%% 根据选择向量选择资源加入联盟（评估所有可能加入的任务，包括保持不变）

incremental = 0;

%% 备份当前状态
backup.coalition = Value_data.coalitionstru;
backup.iteration = Value_data.iteration;
backup.unif = Value_data.unif;

%% 获取当前智能体位置
[currentRow, currentCol] = find(Value_data.coalitionstru == Value_data.agentID);

%% 随机选择资源离开联盟

%% 离开操作与加入操作
% 计算选择概率
probs = compute_select_probabilities(Value_data, agents, tasks, Value_Params);
Value_data.selectProb = probs; % 可选存储

try
    Value_data_before = Value_data.coalitionstru;

    % 1) 按概率执行离开操作：返回更新后的 Value_data 与增量标志
    [Value_data, incremental_leave] = leave_operation(Value_data, agents, tasks, Value_Params, probs);

    % 2) 按概率执行加入操作：在离开后的结构上再尝试加入，返回新的增量标志
    [Value_data, incremental_join] = join_operation(Value_data, agents, tasks, Value_Params, probs);

    % 只要有一次操作改变了联盟结构，则认为本轮有增量
    if ~isequal(Value_data_before, Value_data.coalitionstru) || incremental_leave || incremental_join
        incremental = 1;
    else
        incremental = 0;
    end
catch
    incremental = 0;
end

%% 更新联盟结构
if incremental == 0
    % 保持原联盟
    Value_data.coalitionstru = backup.coalition;
else
    % 执行联盟变更：基于备份先移除已选择的退出任务（若有），然后加入最佳任务
    Value_data.coalitionstru = backup.coalition;
    if ~isempty(left_row)
        Value_data.coalitionstru(left_row, Value_data.agentID) = 0;
    else
        % 若没有预选退出任务，尝试移除当前所处的第一个位置（回退兼容单任务场景）
        if ~isempty(currentRow)
            Value_data.coalitionstru(currentRow(1), currentCol(1)) = 0;
        end
    end
    Value_data.coalitionstru(bestTask, Value_data.agentID) = Value_data.agentID;
end

end


