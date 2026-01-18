function agentutility=Value_utility(agents, tasks, numberrow, numbercolumn, numberofcoworker,Value_data,Value_Params)
% 基于资源分配比例的效用计算
% utility = r_n(C) × V_C × D_C - cost
% r_n(C): 资源贡献比例
% V_C: 期望价值
% D_C: 资源完成度

% 如果在空任务集中，效用为0
if (numberrow == Value_Params.M+1)
    agentutility = 0;
    return;
end

% 获取资源类型数量K

K = Value_Params.K;


% 获取任务的资源需求
demand = tasks(numberrow).resource_demand(:)';

% 从联盟矩阵中获取真正的成员agent ID列表
% numberofcoworker是列索引，需要从coalitionstru中获取实际的agent ID
member_ids = [];
for i = 1:length(numberofcoworker)
    col_idx = numberofcoworker(i);
    if col_idx > 0 && col_idx <= size(Value_data.coalitionstru, 2)
        agent_id = Value_data.coalitionstru(numberrow, col_idx);
        if agent_id > 0 && agent_id <= length(agents)
            member_ids = [member_ids, agent_id];
        end
    end
end

% 如果没有有效成员，效用为0
if isempty(member_ids)
    agentutility = 0;
    return;
end

% 当前智能体ID（从联盟矩阵读取，更稳健）
agent_id = Value_data.coalitionstru(numberrow, numbercolumn);
if agent_id <= 0 || agent_id > numel(agents)
    agent_id = numbercolumn;  % 退回到列索引
end

eps_val = 1e-9;

% 构建资源分配矩阵（用于计算贡献比例和完成度）
SC_m = zeros(length(agents), K);
for i = 1:length(member_ids)
    member_id = member_ids(i);
    if isfield(agents(member_id), 'resources')
        member_resources = agents(member_id).resources(:)';
        if length(member_resources) >= K
            SC_m(member_id, :) = member_resources(1:K);
        else
            SC_m(member_id, 1:length(member_resources)) = member_resources;
        end
    end
end

% 计算联盟总资源（SC_m 按列求和）
total_resources = sum(SC_m, 1);

% 计算资源完成度 D_C
D_C = OCFUtils.calc_task_completion_degree(total_resources, demand, K);
if D_C == 0
    agentutility = 0;
    return;
end

% 计算资源贡献比例 r_n(C)
r_n_C = OCFUtils.calc_resource_contribution_ratio(SC_m, agent_id, member_ids);

% 计算期望价值 V_C（基于belief，支持可变任务类型）
task_types = Value_Params.task_type;
if isempty(task_types)
    task_types = numel(tasks(numberrow).WORLD.value);
end
values = tasks(numberrow).WORLD.value;
tlen = min(task_types, numel(values));
V_C = sum(values(1:tlen) .* Value_data.initbelief(numberrow,1:tlen));

% 计算收益 = r_n(C) × V_C × D_C
revenue = r_n_C * V_C * D_C;


% Travel/energy cost: flight + waiting + execution (round trip)
arrival_times = zeros(1, numel(member_ids));
for idx = 1:numel(member_ids)
    mid = member_ids(idx);
    start_xy_member = [agents(mid).x, agents(mid).y];
    one_way_dist = OCFUtils.compute_route_distance(start_xy_member, numberrow, tasks, false);
    v_member = eps_val;
    if isfield(agents(mid), 'vel') && ~isempty(agents(mid).vel)
        v_member = max(agents(mid).vel, eps_val);
    end
    arrival_times(idx) = one_way_dist / v_member;
end
sync_start_time = max(arrival_times);
my_idx = find(member_ids == agent_id, 1);
if isempty(my_idx)
    my_arrival = 0;
else
    my_arrival = arrival_times(my_idx);
end
wait_time = max(0, sync_start_time - my_arrival);

task_exec_time = 0;
if isfield(tasks(numberrow), 'duration_by_resource') && ~isempty(tasks(numberrow).duration_by_resource)
    task_exec_time = max(tasks(numberrow).duration_by_resource(:));
elseif isfield(tasks(numberrow), 'duration')
    task_exec_time = tasks(numberrow).duration;
end

start_xy = [agents(agent_id).x, agents(agent_id).y];
total_distance = OCFUtils.compute_route_distance(start_xy, numberrow, tasks);
v_agent = eps_val;
if isfield(agents(agent_id), 'vel') && ~isempty(agents(agent_id).vel)
    v_agent = max(agents(agent_id).vel, eps_val);
end
fly_time = total_distance / v_agent;

alpha_fly = agents(agent_id).fuel;
alpha_wait = alpha_fly * 0.5;
beta = 0;
if isfield(agents, 'beta') && isfield(agents(agent_id), 'beta')
    beta = agents(agent_id).beta;
end
cost = fly_time * alpha_fly + wait_time * alpha_wait + task_exec_time * beta;

if (revenue - cost) > 0
    agentutility = revenue - cost;
else
    agentutility = 0;
end

end


