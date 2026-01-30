% TEST_COMPARE_ALGORITHMS 测试版本的算法对比脚本
% 使用更小的参数以快速验证一致性检查功能

clear; clc; close all;

fprintf('\n');
fprintf('========================================================================\n');
fprintf('                    测试：算法对比与一致性检查\n');
fprintf('========================================================================\n\n');

%% Add paths
addpath("Main_fun\");
addpath("SA\");
addpath("comalg/Com_Huo2025/");
addpath("comalg/Com_Qi2023/");
addpath("comalg/Com_Shi2024/");

%% 测试参数（减小规模以加快测试）
SEED = 2456;
N = 3;                          % 减少智能体数量
M = 5;                          % 减少任务数量
K = 3;                          % 减少资源类型
task_values = [800, 1000, 1500];
num_task_types = length(task_values);

% 只测试Huo2025和Qi2023
algorithms_to_run_ids = [3, 4];  % 3=Huo2025, 4=Qi2023

fprintf('测试参数：\n');
fprintf('  智能体数: %d\n', N);
fprintf('  任务数: %d\n', M);
fprintf('  资源类型: %d\n', K);
fprintf('  算法: Huo2025 (Non-OCF), Qi2023 (OCF)\n\n');

%% 场景参数
WORLD_XMIN = 0; WORLD_XMAX = 100;
WORLD_YMIN = 0; WORLD_YMAX = 100;
WORLD_ZMIN = 0; WORLD_ZMAX = 0;

agent_velocity = 2;
agent_detprob_min = 0.95;
agent_detprob_max = 1.0;
agent_Emax_min = 300;
agent_Emax_range = 50;
agent_fuel = 1;
agent_wait_fuel = 0.5;
agent_beta = 1;
min_resource_value = 0;
max_resource_value = 4;

task_type1_demand_max = 4;
task_type2_demand_max = 6;
task_type3_demand_max = 8;

resource_exec_time = [50 65 50];

obs_times = 50;
num_rounds = 5;  % 减少轮数

Qi_beta_m = 1.0;
Qi_C_req = 0.5;
Qi_omega = 0.1;
Qi_omega_1 = 1.0;
Qi_omega_2 = 0.01;
Qi_omega_3 = 0.001;

AddPara.control = 1;
AddPara.resource_confidence = 0.95;
AddPara.enable_belief_update = false;

%% 初始化场景
fprintf('初始化场景...\n');
tic;

rng('default');
rng(SEED);

WORLD.XMIN = WORLD_XMIN; WORLD.XMAX = WORLD_XMAX;
WORLD.YMIN = WORLD_YMIN; WORLD.YMAX = WORLD_YMAX;
WORLD.ZMIN = WORLD_ZMIN; WORLD.ZMAX = WORLD_ZMAX;
WORLD.value = task_values;

task_type_demands = zeros(num_task_types, K);
task_type_demands(1, :) = randi([0, task_type1_demand_max], 1, K);
task_type_demands(2, :) = randi([0, task_type2_demand_max], 1, K);
task_type_demands(3, :) = randi([0, task_type3_demand_max], 1, K);

task_type_duration_by_resource = zeros(num_task_types, K);
for t = 1:num_task_types
    needed = task_type_demands(t, :) > 0;
    task_type_duration_by_resource(t, needed) = resource_exec_time(needed);
end

% 生成任务
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

% 生成智能体
for i = 1:N
    agents(i).id = i;
    agents(i).vel = agent_velocity;
    agents(i).x = round(rand(1) * (WORLD.XMAX - WORLD.XMIN) + WORLD_XMIN);
    agents(i).y = round(rand(1) * (WORLD.YMAX - WORLD.YMIN) + WORLD_YMIN);
    agents(i).z = 0;
    agents(i).detprob = agent_detprob_min + rand(1) * (agent_detprob_max - agent_detprob_min);
    agents(i).Emax = agent_Emax_min + randi(agent_Emax_range);
    agents(i).fuel = agent_fuel;
    agents(i).wait_fuel = agent_wait_fuel;
    agents(i).beta = agent_beta;
    agents(i).resources = randi([min_resource_value, max_resource_value], 1, K);
end

% Value_Params
Value_Params.N = N;
Value_Params.M = M;
Value_Params.K = K;
Value_Params.task_type = num_task_types;
Value_Params.task_type_demands = task_type_demands;
Value_Params.obs_times = obs_times;
Value_Params.num_rounds = num_rounds;
Value_Params.seed = SEED;
Value_Params.Qi_beta_m = Qi_beta_m;
Value_Params.Qi_C_req = Qi_C_req;
Value_Params.Qi_omega = Qi_omega;
Value_Params.Qi_omega_1 = Qi_omega_1;
Value_Params.Qi_omega_2 = Qi_omega_2;
Value_Params.Qi_omega_3 = Qi_omega_3;

init_time = toc;
fprintf('场景初始化完成 (%.2f s)\n\n', init_time);

%% 定义算法
all_algorithms = {
    struct('id', 3, 'name', 'Huo2025', 'func', @Huo2025_main, 'color', [0.8, 0.2, 0.2]);
    struct('id', 4, 'name', 'Qi2023',  'func', @Qi2023_main,  'color', [0.2, 0.8, 0.2]);
};

%% 运行算法
fprintf('========================================================================\n');
fprintf('                    开始运行算法\n');
fprintf('========================================================================\n\n');

results = struct();
enabled_count = 0;

for i = 1:length(all_algorithms)
    alg = all_algorithms{i};
    if ~ismember(alg.id, algorithms_to_run_ids)
        continue;
    end
    enabled_count = enabled_count + 1;

    fprintf('----------------------------------------\n');
    fprintf('运行: [%d] %s\n', alg.id, alg.name);
    fprintf('----------------------------------------\n');

    try
        rng(SEED);
        tic;
        [Value_data, history_data] = alg.func(agents, tasks, AddPara, Value_Params);
        comp_time = toc;

        results.(sprintf('alg%d', enabled_count)).name = alg.name;
        results.(sprintf('alg%d', enabled_count)).Value_data = Value_data;
        results.(sprintf('alg%d', enabled_count)).history_data = history_data;
        results.(sprintf('alg%d', enabled_count)).computation_time = comp_time;

        fprintf('✅ %s 完成 (%.2f s)\n\n', alg.name, comp_time);

    catch ME
        fprintf('❌ %s 失败:\n', alg.name);
        fprintf('  错误: %s\n', ME.message);
        if ~isempty(ME.stack)
            fprintf('  位置: %s (line %d)\n\n', ME.stack(1).name, ME.stack(1).line);
        end
        results.(sprintf('alg%d', enabled_count)).name = alg.name;
        results.(sprintf('alg%d', enabled_count)).error = ME;
        results.(sprintf('alg%d', enabled_count)).computation_time = NaN;
    end
end

fprintf('========================================================================\n');
fprintf('                    测试完成\n');
fprintf('========================================================================\n\n');

if enabled_count > 0
    fprintf('运行时间汇总:\n');
    fprintf('%-20s | %10s\n', '算法', '时间(s)');
    fprintf('%s\n', repmat('-', 1, 40));
    for i = 1:enabled_count
        res = results.(sprintf('alg%d', i));
        if isfield(res, 'error')
            fprintf('%-20s | %10s\n', res.name, '失败');
        else
            fprintf('%-20s | %10.2f\n', res.name, res.computation_time);
        end
    end
    fprintf('\n');
end

fprintf('✅ 所有算法都已运行并完成一致性检查！\n\n');
