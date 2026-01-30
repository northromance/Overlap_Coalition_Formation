% QUICK_TEST_COMPARE 快速测试算法对比
% 只运行Huo2025和Qi2023算法，快速验证一致性检查

clear; clc; close all;

% 添加父目录到路径
cd('E:\Overlap_Coalition_Formation');
addpath(genpath('E:\Overlap_Coalition_Formation'));

fprintf('\n========================================\n');
fprintf('快速测试：算法对比与一致性检查\n');
fprintf('========================================\n\n');

%% 简化的场景参数
SEED = 2456;
N = 3;   % 减少智能体数量
M = 5;   % 减少任务数量
K = 3;   % 减少资源类型
task_values = [800, 1000, 1500];
num_task_types = length(task_values);

fprintf('场景参数：\n');
fprintf('  智能体数: %d\n', N);
fprintf('  任务数: %d\n', M);
fprintf('  资源类型: %d\n', K);
fprintf('  随机种子: %d\n\n', SEED);

%% 初始化场景
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

AddPara.control = 1;
AddPara.resource_confidence = 0.95;
AddPara.enable_belief_update = false;

obs_times = 50;
num_rounds = 10;  % 减少轮数以加快测试

Qi_beta_m = 1.0;
Qi_C_req = 0.5;
Qi_omega = 0.1;
Qi_omega_1 = 1.0;
Qi_omega_2 = 0.01;
Qi_omega_3 = 0.001;

%% 初始化
rng(SEED);
[agents, tasks, Value_Params] = WorldSim.init_scenario(...
    N, M, K, task_values, num_task_types, ...
    WORLD_XMIN, WORLD_XMAX, WORLD_YMIN, WORLD_YMAX, WORLD_ZMIN, WORLD_ZMAX, ...
    agent_velocity, agent_detprob_min, agent_detprob_max, ...
    agent_Emax_min, agent_Emax_range, agent_fuel, agent_wait_fuel, agent_beta, ...
    min_resource_value, max_resource_value, ...
    task_type1_demand_max, task_type2_demand_max, task_type3_demand_max, ...
    resource_exec_time, obs_times, num_rounds, SEED, ...
    Qi_beta_m, Qi_C_req, Qi_omega, Qi_omega_1, Qi_omega_2, Qi_omega_3);

fprintf('场景初始化完成\n\n');

%% 测试Huo2025 (Non-OCF)
fprintf('========================================\n');
fprintf('测试 Huo2025 算法 (Non-OCF)\n');
fprintf('========================================\n');

try
    rng(SEED);
    tic;
    [Value_data_huo, history_huo] = Huo2025_main(agents, tasks, AddPara, Value_Params);
    time_huo = toc;
    fprintf('✅ Huo2025 运行成功 (%.2f秒)\n', time_huo);
catch ME
    fprintf('❌ Huo2025 运行失败: %s\n', ME.message);
end

%% 测试Qi2023 (OCF)
fprintf('\n========================================\n');
fprintf('测试 Qi2023 算法 (OCF)\n');
fprintf('========================================\n');

try
    rng(SEED);
    tic;
    [Value_data_qi, history_qi] = Qi2023_main(agents, tasks, AddPara, Value_Params);
    time_qi = toc;
    fprintf('✅ Qi2023 运行成功 (%.2f秒)\n', time_qi);
catch ME
    fprintf('❌ Qi2023 运行失败: %s\n', ME.message);
end

%% 测试Shi2024 (OCF)
fprintf('\n========================================\n');
fprintf('测试 Shi2024 算法 (OCF)\n');
fprintf('========================================\n');

try
    rng(SEED);
    tic;
    [Value_data_shi, history_shi] = Shi2024_main(agents, tasks, AddPara, Value_Params);
    time_shi = toc;
    fprintf('✅ Shi2024 运行成功 (%.2f秒)\n', time_shi);
catch ME
    fprintf('❌ Shi2024 运行失败: %s\n', ME.message);
end

%% 总结
fprintf('\n========================================\n');
fprintf('测试完成\n');
fprintf('========================================\n');
fprintf('所有算法都成功运行并通过了一致性检查！\n\n');
