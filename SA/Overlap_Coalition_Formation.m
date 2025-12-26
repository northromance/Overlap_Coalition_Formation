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


% 计算更新之前的联盟
Value_data_before = Value_data.coalitionstru;

% 1) 基于每种资源类型的选择概率尝试加入任务
[Value_data, incremental_join] = join_operation(Value_data, agents, tasks, Value_Params, probs);

% 1) 再尝试离开一个任务（若有）
[Value_data, incremental_leave] = leave_operation(Value_data, agents, tasks, Value_Params, probs);

% 只要有一次操作改变了联盟结构，则认为本轮有增量
if ~isequal(Value_data_before, Value_data.coalitionstru) || incremental_leave || incremental_join
    incremental = 1;
else
    incremental = 0;
end

incremental = 0;


% 若本轮没有产生增量，则回退到备份联盟结构
if incremental == 0
    Value_data.coalitionstru = backup.coalition;
end

end


