

clear;
clc;
close all;
tic

%% 初始化参数
SEED=2437;                    % 随机数种子，用于结果可复现
rand('seed',SEED);
addpath("SA\")                % 添加SA文件夹到搜索路径
addpath("plots\")             % 添加绘图/表格函数文件夹到搜索路径

% 世界空间参数
WORLD.XMIN=0;                  % X轴最小值
WORLD.XMAX=100;                % X轴最大值
WORLD.YMIN=0;                  % Y轴最小值
WORLD.YMAX=100;                % Y轴最大值
WORLD.ZMIN=0;                  % Z轴最小值（2D环境中未使用）
WORLD.ZMAX=0;                  % Z轴最大值（2D环境中未使用）
WORLD.value=[800,1000,1500];    % 任务价值候选集

% 基本参数
N = 8;                          % 智能体数量
M = 6;                          % 任务数量
K = 6;                          % 资源类型数量
num_resources = K;              % 资源种类数量（与K保持一致）
num_task_types = 3;             % 任务类型数量
max_resource_value = 4;         % 智能体资源的最大随机值
min_resource_value = 2;         % 智能体资源的最小随机值
Emax_init = 1000;               % 智能体最大能量的初始化基准值
AddPara.control = 1;            % 控制参数（用于算法流程控制）

% 资源执行时间参数
resource_exec_time = [30 40 50 60 35 45];  % 每种资源类型所需的执行时间

% 智能体属性参数
agent_velocity = 2;             % 智能体移动速度
agent_detprob_min = 0.9;       % 智能体检测概率最小值
agent_detprob_max = 1.0;        % 智能体检测概率最大值
agent_Emax_min = 1000;           % 智能体最大能量最小值
agent_Emax_range = 50;          % 智能体最大能量随机范围
agent_fuel = 1;                 % 智能体燃料消耗率
agent_beta = 1;                 % 智能体执行能耗系数

% 模拟退火算法参数
SA_Temperature = 100.0;         % 初始温度
SA_alpha = 0.95;                % 温度衰减率
SA_Tmin = 0.01;                 % 最小温度
SA_max_stable_iterations = 5;   % 最大稳定迭代次数

% 观测参数
obs_times = 20;  % 每个任务的观测次数
num_rounds = 20;  % 游戏总轮数

% ========================================
resource_confidence = 0.7;     % 资源需求计算的置信水平

%% 初始化任务类型的资源需求（为每种类型定义不同的随机范围）
% task_type_demands: 任务类型资源需求矩阵 (T×K)
%   - 行：任务类型 (1~num_task_types)
%   - 列：资源类型 (1~K)
%   - 值：该任务类型对该资源类型的需求量
%
% 类型1（价值800）：低需求任务，每种资源需求 1-2 单位
% 类型2（价值1000）：中等需求任务，每种资源需求 2-3 单位
% 类型3（价值1500）：高需求任务，每种资源需求 3-5 单位

task_type_demands = zeros(num_task_types, num_resources);

% 类型1：低需求 (1-2单位)
task_type_demands(1, :) = randi([3, 4], 1, num_resources);

% 类型2：中等需求 (2-3单位)
task_type_demands(2, :) = randi([5, 6], 1, num_resources);

% 类型3：高需求 (3-5单位)
task_type_demands(3, :) = randi([7, 8], 1, num_resources);

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
    % ========== 任务类型、价值、需求的一致性 ==========
    % 设计原则：类型决定价值和需求
    %   类型1 → 价值300 + 对应需求
    %   类型2 → 价值500 + 对应需求
    %   类型3 → 价值1000 + 对应需求
    % 这样智能体观测到的价值类型和资源需求类型是一致的
    % ================================================
    
    tasks(j).id = j;                        % 任务ID
    tasks(j).priority = task_priorities(j); % 任务优先级（1~M的排列）
    tasks(j).x = round(rand(1) * (WORLD.XMAX - WORLD.XMIN) + WORLD.XMIN);  % 任务X坐标
    tasks(j).y = round(rand(1) * (WORLD.YMAX - WORLD.YMIN) + WORLD.YMIN);  % 任务Y坐标
    
    % 先随机确定类型，然后类型决定价值和需求
    tasks(j).type = randi(num_task_types, 1, 1);                           % 任务类型（1~num_task_types）
    tasks(j).value = WORLD.value(tasks(j).type);                           % 类型决定价值：类型1→300, 类型2→500, 类型3→1000
    tasks(j).resource_demand = task_type_demands(tasks(j).type, :);        % 类型决定资源需求（1×K向量）
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
    agents(i).detprob = agent_detprob_min + (agent_detprob_max - agent_detprob_min) * rand();  % 检测概率在[min, max]范围内随机取值
    agents(i).resources = randi([min_resource_value, max_resource_value], num_resources, 1);  % 智能体拥有的各类资源量（K×1向量）
    agents(i).Emax = agent_Emax_min + agent_Emax_range*rand(); % 智能体最大能量值
    agents(i).fuel = agent_fuel;            % 智能体燃料消耗率
    agents(i).beta = agent_beta;            % 执行能耗系数
end

%% 初始化算法参数结构
Value_Params = init_value_params(N, M, K, num_task_types, task_type_demands, ...
                                  SA_Temperature, SA_alpha, SA_Tmin, SA_max_stable_iterations, ...
                                  obs_times, num_rounds, resource_confidence);

%% 运行联盟形成算法
[Value_data, history_data] = SA_Value_main(agents,tasks,AddPara,Value_Params);

toc

%% 打印联盟结构和资源分配
fprintf('\n========================================\n');
fprintf('          联盟形成结果\n');
fprintf('========================================\n\n');

% 输出表格与统计：调用独立函数
task_demand = display_task_resource_demand(tasks, K, M);

% 提取联盟结构矩阵并裁剪至任务数
coal = Value_data(1).coalitionstru;
if size(coal, 1) > M
    coal = coal(1:M, :);
end

% 任务已分配资源、智能体资源与分配、任务序列、未分配任务、资源匹配详情
task_allocated = display_task_allocated_resources(Value_data, K, M);
agent_owned = display_agent_owned_resources(agents, K, N);
agent_allocated = display_agent_allocated_resources(Value_data, K, N, M);
display_agent_task_sequences(coal, N, M);
display_unassigned_tasks(coal, M);
display_task_resource_match_details(tasks, task_demand, task_allocated, K, M);

fprintf('\n========================================\n\n');

%% 提取联盟成员
% 为每个任务提取参与该任务的智能体集合
for j=1:Value_Params.M
    lianmengchengyuan(j).member=find(Value_data(1).coalitionstru(j,:)~=0);  % 找到任务j的联盟成员（智能体ID列表）
end

%% 打印信念演化和观测统计
display_belief_evolution(history_data, tasks, WORLD, N, M, num_task_types, num_rounds);

% %% 绘图
% % 可视化联盟形成结果、智能体-任务分配等
% plot_main_results(agents, tasks, lianmengchengyuan, history_data, N, M, num_rounds, WORLD.value);

%% 分析分位数需求演化
% 选择要分析的智能体和任务
% agent_id = 1;
% task_id = 3;
% display_quantile_demand_evolution(history_data, tasks, Value_Params, agent_id, task_id);

%% 绘制联盟演化和任务完成度图表
fprintf('绘制联盟演化和任务完成度图表...\n');
plot_coalition_evolution(history_data, tasks, Value_Params);

%% 绘制任务期望收益演化图
fprintf('绘制任务期望收益演化图...\n');
plot_expected_value_evolution(history_data, tasks, Value_Params);

%% 绘制联盟效用演化图（基于实际需求）
fprintf('绘制联盟效用演化图（基于实际需求）...\n');
plot_coalition_utility_evolution(history_data, tasks, Value_Params);

%% 绘制效用对比图（实际需求 vs 期望需求）
fprintf('绘制效用对比图（实际需求 vs 期望需求）...\n');
plot_utility_comparison(history_data, tasks, Value_Params, agents, Value_data);

%% 绘制智能体任务分配图
fprintf('绘制智能体任务分配与资源使用图...\n');
plot_agent_task_assignment(Value_data, agents, tasks, Value_Params);