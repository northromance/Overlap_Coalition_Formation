

clear;
clc;
close all;
tic

%% 初始化参数
SEED=24375;
rand('seed',SEED);
addpath("SA\")

% 世界空间
WORLD.XMIN=0;
WORLD.XMAX=100;
WORLD.YMIN=0;
WORLD.YMAX=100;
WORLD.ZMIN=0;
WORLD.ZMAX=0;
WORLD.value=[300,500,1000];

% 基本参数
N = 6;  % 智能体数
M = 4;  % 任务数
K = 6;  % 资源类型数

num_resources = 6;
num_task_types = 3;

max_resource_value = 8;
min_resource_value = 0;

Emax_init = 1000;

task_type_demands_range = [0, 5];


AddPara.control = 1;

%% 初始化任务类型的资源需求
task_type_demands = randi(task_type_demands_range, num_task_types, num_resources);

%% 初始化资源执行时间
resource_exec_time = [30 40 50 60 35 45];

% 计算各任务类型的资源执行时间分布
task_type_duration_by_resource = zeros(num_task_types, num_resources);
for t = 1:num_task_types
    needed = task_type_demands(t, :) > 0;
    task_type_duration_by_resource(t, needed) = resource_exec_time(needed);
end

% 同步更新每个任务类型的总执行时间（由资源类型执行时间求和得到）
task_type_duration = sum(task_type_duration_by_resource, 2)';

%% 初始化任务和智能体
% 任务
task_priorities = randperm(M);
for j = 1:M
    tasks(j).id = j;
    tasks(j).priority = task_priorities(j);
    tasks(j).x = round(rand(1) * (WORLD.XMAX - WORLD.XMIN) + WORLD.XMIN);
    tasks(j).y = round(rand(1) * (WORLD.YMAX - WORLD.YMIN) + WORLD.YMIN);
    tasks(j).value = WORLD.value(randi(length(WORLD.value), 1, 1));
    tasks(j).type = randi(num_task_types, 1, 1);
    tasks(j).resource_demand = task_type_demands(tasks(j).type, :);
    tasks(j).duration_by_resource = task_type_duration_by_resource(tasks(j).type, :);
    tasks(j).duration = sum(tasks(j).duration_by_resource);
    tasks(j).WORLD = WORLD;
end

% 智能体
for i = 1:N
    agents(i).id = i;
    agents(i).vel = 2;
    agents(i).fuel = 1;
    agents(i).x = round(rand(1) * (WORLD.XMAX - WORLD.XMIN) + WORLD.XMIN);
    agents(i).y = round(rand(1) * (WORLD.YMAX - WORLD.YMIN) + WORLD.YMIN);
    agents(i).detprob = 1;
    agents(i).resources = randi([min_resource_value, max_resource_value], num_resources, 1);
    agents(i).Emax = 2000+Emax_init*rand();
    agents(i).beta = 1;
end



Value_Params=Value_init(N,M,K);
Value_Params.task_type_demands = task_type_demands;

%% 生成连接图
[p, result] = Value_graph(agents, Value_Params);

S = result(1, :);
E = result(2, :);

% 邻接矩阵
G = zeros(N);
for j=1:size(result,2)
    G(result(1,j),result(2,j))=1;
end
Graph=G+G';

%% 运行联盟形成算法
[Value_data,Rcost,cost_sum,net_profit, initial_coalition]= SA_Value_main(agents,tasks,Graph,AddPara,Value_Params);

toc

%% 打印联盟结构和资源分配
fprintf('\n========================================\n');
fprintf('          联盟形成结果\n');
fprintf('========================================\n\n');

% 输出5张表：任务需求/已分配、智能体资源/已分配、任务序列

resNames = arrayfun(@(k) sprintf('R%d', k), 1:K, 'UniformOutput', false);
taskNames = arrayfun(@(m) sprintf('T%d', m), 1:M, 'UniformOutput', false);
agentNames = arrayfun(@(i) sprintf('A%d', i), 1:N, 'UniformOutput', false);

% 表1：任务资源需求
task_demand = zeros(M, K);
for m = 1:M
    if isfield(tasks(m), 'resource_demand') && ~isempty(tasks(m).resource_demand)
        task_demand(m, :) = tasks(m).resource_demand(:)';
    end
end
fprintf('【表1：任务-资源需求 (行=任务, 列=资源类型)】\n');
disp(array2table(task_demand, 'VariableNames', resNames, 'RowNames', taskNames));

coal = Value_data(1).coalitionstru;
if size(coal, 1) > M
    coal = coal(1:M, :);
end

hasSC = isfield(Value_data(1), 'SC') && ~isempty(Value_data(1).SC);

% 表2：任务已分配资源
task_allocated = zeros(M, K);
if hasSC
    for m = 1:M
        if m <= numel(Value_data(1).SC) && ~isempty(Value_data(1).SC{m})
            task_allocated(m, :) = sum(Value_data(1).SC{m}, 1);
        end
    end
end
fprintf('\n【表2：任务-已分配资源 (行=任务, 列=资源类型)】\n');
disp(array2table(task_allocated, 'VariableNames', resNames, 'RowNames', taskNames));

% 表3：智能体具备资源
agent_owned = zeros(N, K);
for i = 1:N
    agent_owned(i, :) = agents(i).resources(:)';
end
fprintf('\n【表3：智能体-具备资源 (行=智能体, 列=资源类型)】\n');
disp(array2table(agent_owned, 'VariableNames', resNames, 'RowNames', agentNames));

% 表4：智能体已分配资源
agent_allocated = zeros(N, K);
if hasSC
    for m = 1:M
        if m <= numel(Value_data(1).SC) && ~isempty(Value_data(1).SC{m})
            agent_allocated = agent_allocated + Value_data(1).SC{m};
        end
    end
end
fprintf('\n【表4：智能体-已分配资源 (行=智能体, 列=资源类型)】\n');
disp(array2table(agent_allocated, 'VariableNames', resNames, 'RowNames', agentNames));

% 表5：智能体任务序列
seqVarNames = arrayfun(@(t) sprintf('Seq%d', t), 1:M, 'UniformOutput', false);
agent_task_seq = nan(N, M);
num_tasks = zeros(N, 1);
for i = 1:N
    assigned_tasks = find(coal(:, i)' ~= 0);
    num_tasks(i) = numel(assigned_tasks);
    if ~isempty(assigned_tasks)
        agent_task_seq(i, 1:numel(assigned_tasks)) = assigned_tasks;
    end
end
T_seq = array2table(agent_task_seq, 'VariableNames', seqVarNames, 'RowNames', agentNames);
T_seq.NumTasks = num_tasks;
T_seq = movevars(T_seq, 'NumTasks', 'Before', 1);
fprintf('\n【表5：智能体-任务序列 (行=智能体, 列=第n个参与任务；NumTasks=任务数)】\n');
disp(T_seq);

fprintf('\n========================================\n\n');

%% 提取联盟成员
for j=1:Value_Params.M
    lianmengchengyuan(j).member=find(Value_data(1).coalitionstru(j,:)~=0);
end

%% 绘图
plot_main_results(agents, tasks, lianmengchengyuan, G, Value_data, N, M);
