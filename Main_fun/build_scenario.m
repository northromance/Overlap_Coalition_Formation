function [WORLD, tasks, agents, task_type_demands] = build_scenario(seed, cfg)
% build_scenario  统一场景生成函数（随机序列与各实验脚本原有内联代码完全对齐）
%
% 用法：
%   [WORLD, tasks, agents, task_type_demands] = build_scenario(seed, cfg)
%
% 输入：
%   seed — 随机种子（整数）
%   cfg  — 场景参数结构体，必须包含以下字段：
%            N, M, K                           维度
%            num_task_types                    任务类型数
%            task_values                       [1×num_task_types] 各类型任务价值
%            task_type1_demand_max             类型1任务各维资源需求上限
%            task_type2_demand_max             类型2任务各维资源需求上限
%            task_type3_demand_max             类型3任务各维资源需求上限
%            resource_exec_time                [1×K] 各资源类型的执行时间
%            WORLD_XMIN, WORLD_XMAX            环境 X 轴范围
%            WORLD_YMIN, WORLD_YMAX            环境 Y 轴范围
%            WORLD_ZMIN, WORLD_ZMAX            环境 Z 轴范围（通常为 0）
%            agent_velocity                    智能体速度
%            agent_detprob_min, agent_detprob_max  探测概率范围
%            agent_Emax_min, agent_Emax_range  最大能量范围
%            agent_fuel                        飞行燃料系数 varpi
%            agent_wait_fuel                   等待燃料系数 gamma
%            agent_beta                        执行成本系数 beta
%            min_resource_value, max_resource_value  智能体资源能力范围
%
% 输出：
%   WORLD              — 环境结构体（含边界与任务价值列表）
%   tasks              — [1×M] 任务结构体数组
%   agents             — [1×N] 智能体结构体数组
%   task_type_demands  — [num_task_types×K] 各类型任务资源需求模板（供 Value_Params 注入）
%
% 注意：函数在入口处重置随机种子，保证与各脚本原有内联代码产生完全相同的随机序列。

rng('default');
rng(seed);

N              = cfg.N;
M              = cfg.M;
K              = cfg.K;
num_task_types = cfg.num_task_types;

%% Build WORLD struct
WORLD.XMIN  = cfg.WORLD_XMIN;  WORLD.XMAX = cfg.WORLD_XMAX;
WORLD.YMIN  = cfg.WORLD_YMIN;  WORLD.YMAX = cfg.WORLD_YMAX;
WORLD.ZMIN  = cfg.WORLD_ZMIN;  WORLD.ZMAX = cfg.WORLD_ZMAX;
WORLD.value = cfg.task_values;

%% Task type demands（不同任务类型的资源需求模板）
task_type_demands = zeros(num_task_types, K);
task_type_demands(1, :) = randi([0, cfg.task_type1_demand_max], 1, K);
task_type_demands(2, :) = randi([0, cfg.task_type2_demand_max], 1, K);
task_type_demands(3, :) = randi([0, cfg.task_type3_demand_max], 1, K);

%% Task durations by resource（各任务类型在各资源上的执行时间）
task_type_duration_by_resource = zeros(num_task_types, K);
for t = 1:num_task_types
    needed = task_type_demands(t, :) > 0;
    task_type_duration_by_resource(t, needed) = cfg.resource_exec_time(needed);
end

%% Tasks generation（生成 M 个任务）
task_priorities = randperm(M);
tasks = struct();
for j = 1:M
    tasks(j).id       = j;
    tasks(j).priority = task_priorities(j);
    tasks(j).x = round(rand() * (WORLD.XMAX - WORLD.XMIN) + WORLD.XMIN);
    tasks(j).y = round(rand() * (WORLD.YMAX - WORLD.YMIN) + WORLD.YMIN);
    tasks(j).type     = randi(num_task_types, 1, 1);
    tasks(j).value    = WORLD.value(tasks(j).type);
    tasks(j).resource_demand      = task_type_demands(tasks(j).type, :);
    tasks(j).duration_by_resource = task_type_duration_by_resource(tasks(j).type, :);
    tasks(j).duration = max(tasks(j).duration_by_resource);
    tasks(j).WORLD    = WORLD;
end

%% Agents generation（生成 N 个智能体）
agents = struct();
for i = 1:N
    agents(i).id        = i;
    agents(i).vel       = cfg.agent_velocity;
    agents(i).x = round(rand() * (WORLD.XMAX - WORLD.XMIN) + WORLD.XMIN);
    agents(i).y = round(rand() * (WORLD.YMAX - WORLD.YMIN) + WORLD.YMIN);
    agents(i).detprob   = cfg.agent_detprob_min + (cfg.agent_detprob_max - cfg.agent_detprob_min) * rand();
    agents(i).resources = randi([cfg.min_resource_value, cfg.max_resource_value], K, 1);
    agents(i).Emax      = cfg.agent_Emax_min + cfg.agent_Emax_range * rand();
    agents(i).fuel      = cfg.agent_fuel;
    agents(i).wait_fuel = cfg.agent_wait_fuel;
    agents(i).beta      = cfg.agent_beta;
end
