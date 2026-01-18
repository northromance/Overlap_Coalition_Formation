function agentutility=Value_utility(agents, tasks, numberrow, numbercolumn, numberofcoworker,Value_data,Value_Params)
% 基于资源分配比例的效用计算（逐行中文注释）
% 输入:
%   agents          : 智能体结构体数组
%   tasks           : 任务结构体数组
%   numberrow       : 当前任务所在行（任务ID，M+1 表示虚任务）
%   numbercolumn    : 联盟矩阵中的列索引（对应 agent 在矩阵中的列）
%   numberofcoworker: 当前联盟内成员所在的列索引列表
%   Value_data      : 包含联盟矩阵、belief 等信息的结构体
%   Value_Params    : 全局参数（含 M、K、task_type 等）
% 输出:
%   agentutility    : 当前智能体的效用值

% 如果在空任务集中，直接返回 0
if (numberrow == Value_Params.M+1)
    agentutility = 0;
    return;
end

% 读取资源类型数量 K
K = Value_Params.K;

% 读取任务资源需求（转为行向量）
demand = tasks(numberrow).resource_demand(:)';

% 从联盟矩阵取真实成员 ID（numberofcoworker 给的是列索引）
member_ids = [];
for i = 1:length(numberofcoworker)
    col_idx = numberofcoworker(i);                                  % 当前成员列号
    if col_idx > 0 && col_idx <= size(Value_data.coalitionstru, 2)   % 列号有效
        agent_id_tmp = Value_data.coalitionstru(numberrow, col_idx); % 取出真实 agent ID
        if agent_id_tmp > 0 && agent_id_tmp <= length(agents)       % 过滤无效 ID
            member_ids = [member_ids, agent_id_tmp];                % 收集成员
        end
    end
end

% 若无有效成员，效用为 0
if isempty(member_ids)
    agentutility = 0;
    return;
end

% 当前智能体 ID：优先用联盟矩阵中的真实 ID，异常时退回列索引
agent_id = Value_data.coalitionstru(numberrow, numbercolumn);
if agent_id <= 0 || agent_id > numel(agents)
    agent_id = numbercolumn;                                         % 退化处理
end

% 数值容差，防止除零
eps_val = 1e-9;

% 构建资源分配矩阵 SC_m（行: agent，列: 资源类型）
SC_m = zeros(length(agents), K);
for i = 1:length(member_ids)
    member_id = member_ids(i);                                       % 成员真实 ID
    if isfield(agents(member_id), 'resources')
        member_resources = agents(member_id).resources(:)';           % 资源转行向量
        if length(member_resources) >= K
            SC_m(member_id, :) = member_resources(1:K);              % 取前 K 类
        else
            SC_m(member_id, 1:length(member_resources)) = member_resources; % 不足补 0
        end
    end
end

% 联盟总资源（按列求和）
total_resources = sum(SC_m, 1);

% 资源完成度 D_C，若为 0 则效用为 0
D_C = OCFUtils.calc_task_completion_degree(total_resources, demand, K);
if D_C == 0
    agentutility = 0;
    return;
end

% 资源贡献比例 r_n(C)
r_n_C = OCFUtils.calc_resource_contribution_ratio(SC_m, agent_id, member_ids);

% 期望价值 V_C（按 belief 乘价值向量，长度取 task_types）
task_types = Value_Params.task_type;
if isempty(task_types)
    task_types = numel(tasks(numberrow).WORLD.value);                % 未设定则取 WORLD.value 长度
end
values = tasks(numberrow).WORLD.value;                               % 任务价值候选
tlen = min(task_types, numel(values));                                % 实际类型数
V_C = sum(values(1:tlen) .* Value_data.initbelief(numberrow,1:tlen)); % 期望价值

% 收益 = r_n(C) × V_C × D_C
revenue = r_n_C * V_C * D_C;

% 计算到达时间：单程距离 / 速度（不含返回）
arrival_times = zeros(1, numel(member_ids));
for idx = 1:numel(member_ids)
    mid = member_ids(idx);                                           % 成员 ID
    start_xy_member = [agents(mid).x, agents(mid).y];                 % 成员起点
    one_way_dist = OCFUtils.compute_route_distance(start_xy_member, numberrow, tasks, false); % 起点->任务
    v_member = eps_val;
    if isfield(agents(mid), 'vel') && ~isempty(agents(mid).vel)
        v_member = max(agents(mid).vel, eps_val);                    % 成员速度
    end
    arrival_times(idx) = one_way_dist / v_member;                    % 成员到达时间
end

% 同步开始时间：取最晚到达者
sync_start_time = max(arrival_times);

% 当前智能体到达时间（防御性处理）
my_idx = find(member_ids == agent_id, 1);
if isempty(my_idx)
    my_arrival = 0;
else
    my_arrival = arrival_times(my_idx);
end

% 等待时间 = 同步开始时间 - 自己到达时间
wait_time = max(0, sync_start_time - my_arrival);

% 任务执行时间：取需求中最耗时的资源时长（与 SA_Main 规则一致）
task_exec_time = 0;
if isfield(tasks(numberrow), 'duration_by_resource') && ~isempty(tasks(numberrow).duration_by_resource)
    task_exec_time = max(tasks(numberrow).duration_by_resource(:));
elseif isfield(tasks(numberrow), 'duration')
    task_exec_time = tasks(numberrow).duration;
end

% 往返距离与飞行时间（起点->任务->返回起点）
start_xy = [agents(agent_id).x, agents(agent_id).y];                 % 我的起点坐标
total_distance = OCFUtils.compute_route_distance(start_xy, numberrow, tasks); % 闭环距离
v_agent = eps_val;
if isfield(agents(agent_id), 'vel') && ~isempty(agents(agent_id).vel)
    v_agent = max(agents(agent_id).vel, eps_val);                    % 我的速度
end
fly_time = total_distance / v_agent;                                 % 总飞行时间

% 能耗系数：飞行、等待、执行
alpha_fly = agents(agent_id).fuel;                                   % 飞行能耗（燃料率）                                     % 等待能耗（默认半速）
alpha_wait = agents(agent_id).wait_fuel;                         % 优先使用显式等待油耗
beta = agents(agent_id).beta;


% 总成本 = 飞行能耗 + 等待能耗 + 执行能耗
cost = fly_time * alpha_fly + wait_time * alpha_wait + task_exec_time * beta;

% 最终效用（小于 0 则截断为 0）
if (revenue - cost) > 0
    agentutility = revenue - cost;
else
    agentutility = 0;
end

end
