

clear;
clc;
close all;
tic

%% 初始化参数
SEED=24375;                    % 随机数种子，用于结果可复现
rand('seed',SEED);
addpath("SA\")                % 添加SA文件夹到搜索路径

% 世界空间参数
WORLD.XMIN=0;                  % X轴最小值
WORLD.XMAX=100;                % X轴最大值
WORLD.YMIN=0;                  % Y轴最小值
WORLD.YMAX=100;                % Y轴最大值
WORLD.ZMIN=0;                  % Z轴最小值（2D环境中未使用）
WORLD.ZMAX=0;                  % Z轴最大值（2D环境中未使用）
WORLD.value=[300,500,1000];    % 任务价值候选集

% 基本参数
N = 8;                          % 智能体数量
M = 5;                          % 任务数量
K = 6;                          % 资源类型数量
num_resources = K;              % 资源种类数量（与K保持一致）
num_task_types = 3;             % 任务类型数量
max_resource_value = 8;         % 智能体资源的最大随机值
min_resource_value = 4;         % 智能体资源的最小随机值
Emax_init = 1000;               % 智能体最大能量的初始化基准值
task_type_demands_range = [6, 8];  % 任务类型对每种资源需求量的随机范围0
AddPara.control = 1;            % 控制参数（用于算法流程控制）

% 资源执行时间参数
resource_exec_time = [30 40 50 60 35 45];  % 每种资源类型所需的执行时间

% 智能体属性参数
agent_velocity = 2;             % 智能体移动速度
agent_detprob = 0.9;            % 智能体检测概率（任务成功率）
agent_Emax_min = 1000;           % 智能体最大能量最小值
agent_Emax_range = 50;          % 智能体最大能量随机范围
agent_fuel = 1;                 % 智能体燃料消耗率
agent_beta = 1;                 % 智能体执行能耗系数

% 模拟退火算法参数
SA_Temperature = 100.0;         % 初始温度
SA_alpha = 0.95;                % 温度衰减率
SA_Tmin = 0.01;                 % 最小温度
SA_max_stable_iterations = 5;   % 最大稳定迭代次数

%% 初始化任务类型的资源需求
% task_type_demands: 任务类型资源需求矩阵 (T×K)
%   - 行：任务类型 (1~num_task_types)
%   - 列：资源类型 (1~K)
%   - 值：该任务类型对该资源类型的需求量
task_type_demands = randi(task_type_demands_range, num_task_types, num_resources);

%% 初始化资源执行时间
% 计算各任务类型的资源执行完所需的全部时间
task_type_duration_by_resource = zeros(num_task_types, num_resources);
for t = 1:num_task_types
    needed = task_type_demands(t, :) > 0;  % 找出该任务类型需要的资源
    task_type_duration_by_resource(t, needed) = resource_exec_time(needed);
end

% 同步更新每个任务类型的总执行时间（由资源类型执行时间求和得到）
% task_type_duration: 各任务类型的总执行时间 (1×T向量)
task_type_duration = sum(task_type_duration_by_resource, 2)';

%% 初始化任务和智能体
% 任务结构体数组初始化
task_priorities = randperm(M);  % 生成任务优先级的随机排列
for j = 1:M
    tasks(j).id = j;                        % 任务ID
    tasks(j).priority = task_priorities(j); % 任务优先级（1~M的排列）
    tasks(j).x = round(rand(1) * (WORLD.XMAX - WORLD.XMIN) + WORLD.XMIN);  % 任务X坐标
    tasks(j).y = round(rand(1) * (WORLD.YMAX - WORLD.YMIN) + WORLD.YMIN);  % 任务Y坐标
    tasks(j).value = WORLD.value(randi(length(WORLD.value), 1, 1));        % 任务价值（从候选集随机选择）
    tasks(j).type = randi(num_task_types, 1, 1);                           % 任务类型（1~num_task_types）
    tasks(j).resource_demand = task_type_demands(tasks(j).type, :);        % 任务的资源需求（1×K向量）
    tasks(j).duration_by_resource = task_type_duration_by_resource(tasks(j).type, :);  % 按资源分解的执行时间
    tasks(j).duration = sum(tasks(j).duration_by_resource);                % 任务总执行时间
    tasks(j).WORLD = WORLD;                                                % 任务所在世界空间参数
end

% 智能体结构体数组初始化
for i = 1:N
    agents(i).id = i;                       % 智能体ID
    agents(i).vel = agent_velocity;         % 智能体移动速度
    agents(i).x = round(rand(1) * (WORLD.XMAX - WORLD.XMIN) + WORLD.XMIN);  % 智能体X坐标
    agents(i).y = round(rand(1) * (WORLD.YMAX - WORLD.YMIN) + WORLD.YMIN);  % 智能体Y坐标
    agents(i).detprob = agent_detprob;      % 检测概率（任务成功率）
    agents(i).resources = randi([min_resource_value, max_resource_value], num_resources, 1);  % 智能体拥有的各类资源量（K×1向量）
    agents(i).Emax = agent_Emax_min + agent_Emax_range*rand(); % 智能体最大能量值
    agents(i).fuel = agent_fuel;            % 智能体燃料消耗率
    agents(i).beta = agent_beta;            % 执行能耗系数
end

%% 初始化算法参数结构
Value_Params = init_value_params(N, M, K, task_type_demands, ...
                                  SA_Temperature, SA_alpha, SA_Tmin, SA_max_stable_iterations);

%% 运行联盟形成算法
[Value_data,Rcost,cost_sum,net_profit]= SA_Value_main(agents,tasks,AddPara,Value_Params);

toc

%% 打印联盟结构和资源分配
fprintf('\n========================================\n');
fprintf('          联盟形成结果\n');
fprintf('========================================\n\n');

% 输出5张表：任务需求/已分配、智能体资源/已分配、任务序列

% 生成表格的行列名称
resNames = arrayfun(@(k) sprintf('Res%d', k), 1:K, 'UniformOutput', false);  % 资源类型列名：Res1, Res2, ..., Res6
taskNames = arrayfun(@(m) sprintf('T%d', m), 1:M, 'UniformOutput', false);   % 任务行名：T1, T2, ..., T10
agentNames = arrayfun(@(i) sprintf('A%d', i), 1:N, 'UniformOutput', false);  % 智能体行名：A1, A2, ..., A6

% 表1：任务资源需求矩阵 (M×K)
task_demand = zeros(M, K);
for m = 1:M
    if isfield(tasks(m), 'resource_demand') && ~isempty(tasks(m).resource_demand)
        task_demand(m, :) = tasks(m).resource_demand(:)';  % 提取每个任务的资源需求
    end
end
fprintf('【表1：任务-资源需求 (行=任务, 列=资源类型)】\n');
disp(array2table(task_demand, 'VariableNames', resNames, 'RowNames', taskNames));

% 提取联盟结构矩阵
coal = Value_data(1).coalitionstru;  % 联盟结构矩阵（M×N），元素为任务-智能体分配关系
if size(coal, 1) > M
    coal = coal(1:M, :);  % 如果行数超过任务数，截取前M行
end

% 检查是否存在资源分配数据
hasSC = isfield(Value_data(1), 'SC') && ~isempty(Value_data(1).SC);  % SC: 资源分配cell数组

% 表2：任务已分配资源矩阵 (M×K)
% 统计所有智能体对每个任务分配的各类资源总量
task_allocated = zeros(M, K);
if hasSC
    for m = 1:M
        if m <= numel(Value_data(1).SC) && ~isempty(Value_data(1).SC{m})
            task_allocated(m, :) = sum(Value_data(1).SC{m}, 1);  % SC{m}是N×K矩阵，按列求和得到任务m的总分配资源
        end
    end
end
fprintf('\n【表2：任务-已分配资源 (行=任务, 列=资源类型)】\n');
disp(array2table(task_allocated, 'VariableNames', resNames, 'RowNames', taskNames));

% 表3：智能体具备资源矩阵 (N×K)
% 显示每个智能体初始拥有的各类资源数量
agent_owned = zeros(N, K);
for i = 1:N
    agent_owned(i, :) = agents(i).resources(:)';  % 提取智能体i的资源向量
end
fprintf('\n【表3：智能体-具备资源 (行=智能体, 列=资源类型)】\n');
disp(array2table(agent_owned, 'VariableNames', resNames, 'RowNames', agentNames));

% 表4：智能体已分配资源矩阵 (N×K)
% 统计每个智能体在所有任务上总共分配的各类资源量
agent_allocated = zeros(N, K);
if hasSC
    for m = 1:M
        if m <= numel(Value_data(1).SC) && ~isempty(Value_data(1).SC{m})
            agent_allocated = agent_allocated + Value_data(1).SC{m};  % 累加各任务上的资源分配
        end
    end
end
fprintf('\n【表4：智能体-已分配资源 (行=智能体, 列=资源类型)】\n');
disp(array2table(agent_allocated, 'VariableNames', resNames, 'RowNames', agentNames));

% 表5：智能体任务序列表
% 显示每个智能体参与的任务序列和任务总数
seqVarNames = arrayfun(@(t) sprintf('Seq%d', t), 1:M, 'UniformOutput', false);  % 列名：Seq1, Seq2, ...
agent_task_seq = nan(N, M);  % 初始化为NaN，表示未分配任务
num_tasks = zeros(N, 1);     % 记录每个智能体的任务数量
for i = 1:N
    assigned_tasks = find(coal(:, i)' ~= 0);  % 找到智能体i参与的所有任务ID
    num_tasks(i) = numel(assigned_tasks);      % 任务数量
    if ~isempty(assigned_tasks)
        agent_task_seq(i, 1:numel(assigned_tasks)) = assigned_tasks;  % 填充任务序列
    end
end
T_seq = array2table(agent_task_seq, 'VariableNames', seqVarNames, 'RowNames', agentNames);
T_seq.NumTasks = num_tasks;                    % 添加任务数量列
T_seq = movevars(T_seq, 'NumTasks', 'Before', 1);  % 将任务数量列移到第一列
fprintf('\n【表5：智能体-任务序列 (行=智能体, 列=第n个参与任务；NumTasks=任务数)】\n');
disp(T_seq);

% 表6：未执行任务列表
% 找出没有分配任何智能体的任务
unassigned_tasks = [];
for m = 1:M
    if sum(coal(m, :)) == 0  % 该任务没有任何智能体参与
        unassigned_tasks = [unassigned_tasks, m];
    end
end
fprintf('\n【表6：未执行任务列表】\n');
if isempty(unassigned_tasks)
    fprintf('所有任务均已分配智能体执行。\n');
else
    fprintf('以下任务未分配智能体：');
    fprintf(' T%d', unassigned_tasks);
    fprintf('\n共 %d 个任务未执行。\n', length(unassigned_tasks));
end

% 表7：每个任务的资源匹配详情（需求 vs 已分配 vs 缺口）
fprintf('\n【表7：任务资源匹配详情 (需求/已分配/缺口)】\n');
for m = 1:M
    fprintf('\n--- 任务 T%d (优先级=%d, 类型=%d) ---\n', m, tasks(m).priority, tasks(m).type);
    
    % 构建该任务的资源对比表
    match_table = table();
    match_table.ResourceType = resNames';  % 资源类型列
    match_table.Demand = task_demand(m, :)';  % 需求列
    match_table.Allocated = task_allocated(m, :)';  % 已分配列
    match_table.Gap = task_demand(m, :)' - task_allocated(m, :)';  % 缺口列
    match_table.Status = cell(K, 1);  % 状态列
    
    % 标注状态：满足/不足/过量
    for r = 1:K
        gap = match_table.Gap(r);
        if gap < 0
            match_table.Status{r} = '过量';
        elseif gap > 0
            match_table.Status{r} = '不足';
        else
            match_table.Status{r} = '满足';
        end
    end
    
    disp(match_table);
end

fprintf('\n========================================\n\n');

%% 提取联盟成员
% 为每个任务提取参与该任务的智能体集合
for j=1:Value_Params.M
    lianmengchengyuan(j).member=find(Value_data(1).coalitionstru(j,:)~=0);  % 找到任务j的联盟成员（智能体ID列表）
end

%% 绘图
% 可视化联盟形成结果、智能体-任务分配等
plot_main_results(agents, tasks, lianmengchengyuan, Value_data, N, M);
