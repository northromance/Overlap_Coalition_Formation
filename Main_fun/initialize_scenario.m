function [agents, tasks, Value_Params, WORLD, scenario_info] = initialize_scenario(SEED)
% INITIALIZE_SCENARIO 初始化联盟形成算法的测试场景
%
% 输入:
%   SEED - 随机数种子，用于结果可复现
%
% 输出:
%   agents - 智能体结构体数组
%   tasks - 任务结构体数组
%   Value_Params - 算法参数结构体
%   WORLD - 世界空间参数结构体
%   scenario_info - 场景信息（包含所有初始化参数）

    % 设置随机数种子
    rand('seed', SEED);
    
    %% 世界空间参数
    WORLD.XMIN = 0;
    WORLD.XMAX = 100;
    WORLD.YMIN = 0;
    WORLD.YMAX = 100;
    WORLD.ZMIN = 0;
    WORLD.ZMAX = 0;
    WORLD.value = [800, 1000, 1500];  % 任务价值候选集
    
    %% 基本参数
    N = 6;                          % 智能体数量
    M = 10;                          % 任务数量
    K = 6;                          % 资源类型数量
    num_resources = K;
    num_task_types = 3;             % 任务类型数量
    max_resource_value = 4;         % 智能体资源的最大随机值
    min_resource_value = 2;         % 智能体资源的最小随机值
    
    %% 资源执行时间参数
    resource_exec_time = [50 65 50 60 35 45];
    
    %% 智能体属性参数
    agent_velocity = 2;
    agent_detprob_min = 0.9;
    agent_detprob_max = 1.0;
    agent_Emax_min = 300;
    agent_Emax_range = 50;
    agent_fuel = 1;
    agent_beta = 1;
    
    %% 模拟退火算法参数
    SA_Temperature = 100.0;
    SA_alpha = 0.95;
    SA_Tmin = 0.01;
    SA_max_stable_iterations = 5;
    
    %% 观测参数
    obs_times = 50;
    num_rounds = 50;
    resource_confidence = 0.7;
    
    %% 初始化任务类型的资源需求
    task_type_demands = zeros(num_task_types, num_resources);
    task_type_demands(1, :) = randi([0, 4], 1, num_resources);  % 类型1：低需求
    task_type_demands(2, :) = randi([0, 6], 1, num_resources);  % 类型2：中等需求
    task_type_demands(3, :) = randi([0, 8], 1, num_resources);  % 类型3：高需求
    
    %% 初始化资源执行时间
    task_type_duration_by_resource = zeros(num_task_types, num_resources);
    for t = 1:num_task_types
        needed = task_type_demands(t, :) > 0;
        task_type_duration_by_resource(t, needed) = resource_exec_time(needed);
    end
    task_type_duration = sum(task_type_duration_by_resource, 2)';
    
    %% 初始化任务
    task_priorities = randperm(M);
    for j = 1:M
        tasks(j).id = j;
        tasks(j).priority = task_priorities(j);
        tasks(j).x = round(rand(1) * (WORLD.XMAX - WORLD.XMIN) + WORLD.XMIN);
        tasks(j).y = round(rand(1) * (WORLD.YMAX - WORLD.YMIN) + WORLD.YMIN);
        tasks(j).type = randi(num_task_types, 1, 1);
        tasks(j).value = WORLD.value(tasks(j).type);
        tasks(j).resource_demand = task_type_demands(tasks(j).type, :);
        tasks(j).duration_by_resource = task_type_duration_by_resource(tasks(j).type, :);
        tasks(j).duration = max(tasks(j).duration_by_resource);
        tasks(j).WORLD = WORLD;
    end
    
    %% 初始化智能体
    for i = 1:N
        agents(i).id = i;
        agents(i).vel = agent_velocity;
        agents(i).x = round(rand(1) * (WORLD.XMAX - WORLD.XMIN) + WORLD.XMIN);
        agents(i).y = round(rand(1) * (WORLD.YMAX - WORLD.YMIN) + WORLD.YMIN);
        agents(i).detprob = agent_detprob_min + (agent_detprob_max - agent_detprob_min) * rand();
        agents(i).resources = randi([min_resource_value, max_resource_value], num_resources, 1);
        agents(i).Emax = agent_Emax_min + agent_Emax_range * rand();
        agents(i).fuel = agent_fuel;
        agents(i).beta = agent_beta;
    end
    
    %% 初始化算法参数结构
    Value_Params = init_value_params(N, M, K, num_task_types, task_type_demands, ...
                                      SA_Temperature, SA_alpha, SA_Tmin, SA_max_stable_iterations, ...
                                      obs_times, num_rounds, resource_confidence);
    
    %% 保存场景信息
    scenario_info.SEED = SEED;
    scenario_info.N = N;
    scenario_info.M = M;
    scenario_info.K = K;
    scenario_info.num_task_types = num_task_types;
    scenario_info.task_type_demands = task_type_demands;
    scenario_info.resource_exec_time = resource_exec_time;
    scenario_info.timestamp = datetime('now');
    
end
