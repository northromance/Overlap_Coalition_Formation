function [incremental,curnumberrow,Value_data]=Overlap_Coalition_Formation(agents, tasks, Value_data, Value_Params,counter,AddPara, allocated_resources, resource_gap)

% 兼容输出：默认认为当前在空任务(M+1)
curnumberrow = Value_Params.M + 1;
incremental = 0;

% 消除未使用输入参数的静态检查告警（不影响逻辑）
unusedCounter = counter; %#ok<NASGU>
if isstruct(AddPara)
    unusedCounter = unusedCounter + 0; %#ok<NASGU>
end

%% 备份当前状态
backup.coalition = Value_data.coalitionstru;
backup.iteration = Value_data.iteration;
backup.unif = Value_data.unif;
% 同步备份资源联盟结构，保证“无增量时”可回滚到一致状态
if isfield(Value_data, 'SC')
    backup.SC = Value_data.SC;
end
if isfield(Value_data, 'resources_matrix')
    backup.resources_matrix = Value_data.resources_matrix;
end

%% 确保资源联盟结构 SC / resources_matrix 存在（部分测试用例可能未初始化）
if ~isfield(Value_data, 'resources_matrix') || isempty(Value_data.resources_matrix) || ...
        any(size(Value_data.resources_matrix) ~= [Value_Params.M, Value_Params.K])
    Value_data.resources_matrix = zeros(Value_Params.M, Value_Params.K);
end

if ~isfield(Value_data, 'SC') || isempty(Value_data.SC)
    Value_data.SC = cell(Value_Params.M, 1);
    for m = 1:Value_Params.M
        Value_data.SC{m} = zeros(Value_Params.N, Value_Params.K);
        Value_data.SC{m}(Value_data.agentID, :) = Value_data.resources_matrix(m, :);
    end
end

%% 获取当前智能体位置（仅用于给 curnumberrow 赋值）
currentRows = find(Value_data.coalitionstru(:, Value_data.agentID) == Value_data.agentID);
if ~isempty(currentRows)
    curnumberrow = currentRows(1);
end

%% 随机选择资源离开联盟

%% 离开操作与加入操作
% 首先计算智能体在每种资源任务下选择任务的概率

probs = compute_select_probabilities(Value_data, agents, tasks, Value_Params, allocated_resources, resource_gap);

Value_data.selectProb = probs; % 可选存储


% 备份更新之前的资源联盟结构SC
Value_data_before_SC = Value_data.SC;

% 1) 基于每种资源类型的选择概率尝试加入任务
[Value_data, incremental_join] = join_operation(Value_data, agents, tasks, Value_Params, probs);

% 2) 执行 leave：在 join 之后继续尝试离开一个任务（若可行且被接受）
[Value_data, incremental_leave] = leave_operation(Value_data, agents, tasks, Value_Params, probs);

% 检查SC是否发生改变：比较操作前后的资源分配矩阵
SC_changed = false;
for m = 1:Value_Params.M
    if ~isequal(Value_data_before_SC{m}, Value_data.SC{m})
        SC_changed = true;
        break;
    end
end

% 只要SC改变了或者有增量标志，则认为本轮有增量
if SC_changed || incremental_leave || incremental_join
    incremental = 1;
else
    incremental = 0;
end


% 若本轮没有产生增量，则回退到备份联盟结构
if incremental == 0
    Value_data.coalitionstru = backup.coalition;
    if isfield(backup, 'SC')
        Value_data.SC = backup.SC;
    end
    if isfield(backup, 'resources_matrix')
        Value_data.resources_matrix = backup.resources_matrix;
    end
end

end


