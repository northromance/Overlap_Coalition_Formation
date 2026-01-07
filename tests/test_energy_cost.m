%% test_energy_cost.m
% 测试 energy_cost.m 函数的各项功能 - 固定速度+等待模型
% =========================================================================
% 测试内容：
%   1. 基础功能测试（单智能体，无同步）
%   2. 同步机制测试（多智能体协同任务）
%   3. 等待时间验证（先到等待机制）
% =========================================================================

clear;
clc;
close all;

% 添加路径
addpath('../SA');

fprintf('========================================\n');
fprintf('   energy_cost.m 功能测试\n');
fprintf('   模型: 固定速度+等待\n');
fprintf('========================================\n\n');

%% 测试1: 基础功能测试（单智能体，无同步）
fprintf('测试1: 基础功能 - 单智能体顺序执行\n');
fprintf('----------------------------------------\n');

% 初始化测试数据
N = 3;  % 3个智能体
M = 4;  % 4个任务
K = 3;  % 3种资源类型

% 创建智能体
agents(1).id = 1;
agents(1).x = 0;
agents(1).y = 0;
agents(1).vel = 10;  % 速度 10 单位/时间
agents(1).fuel = 1.0;  % α_fly 飞行能耗系数
agents(1).beta = 0.5;  % 执行能耗系数
agents(1).resources = [4; 3; 5];

agents(2).id = 2;
agents(2).x = 20;
agents(2).y = 30;
agents(2).vel = 8;
agents(2).fuel = 1.2;
agents(2).beta = 0.6;
agents(2).resources = [3; 4; 4];

agents(3).id = 3;
agents(3).x = 50;
agents(3).y = 60;
agents(3).vel = 12;
agents(3).fuel = 0.8;
agents(3).beta = 0.4;
agents(3).resources = [5; 5; 3];

% 创建任务
tasks(1).id = 1;
tasks(1).x = 30;
tasks(1).y = 40;
tasks(1).priority = 1;  % 优先级最高
tasks(1).duration = 10;
tasks(1).duration_by_resource = [5, 3, 2];
tasks(1).value = 800;

tasks(2).id = 2;
tasks(2).x = 60;
tasks(2).y = 50;
tasks(2).priority = 3;
tasks(2).duration = 15;
tasks(2).duration_by_resource = [6, 5, 4];
tasks(2).value = 1000;

tasks(3).id = 3;
tasks(3).x = 80;
tasks(3).y = 20;
tasks(3).priority = 2;
tasks(3).duration = 12;
tasks(3).duration_by_resource = [4, 4, 4];
tasks(3).value = 1200;

tasks(4).id = 4;
tasks(4).x = 40;
tasks(4).y = 70;
tasks(4).priority = 4;
tasks(4).duration = 8;
tasks(4).duration_by_resource = [3, 3, 2];
tasks(4).value = 600;

% 初始化参数
task_type_demands = [3, 2, 2; 4, 3, 3; 5, 4, 4];
Value_Params = init_value_params(N, M, K, 3, task_type_demands, ...
                                  100.0, 0.95, 0.01, 5, 20, 20, 0.7);

% 测试智能体1执行任务[1, 3]（按优先级排序后仍为[1,3]，因为priority 1<2）
agent_idx = 1;
assigned_tasks = [1, 3];
R_agent = zeros(M, K);
R_agent(1, :) = [1, 1, 0];  % 任务1使用资源类型1和2
R_agent(3, :) = [1, 0, 1];  % 任务3使用资源类型1和3

fprintf('智能体 %d 执行任务 [%s]\n', agent_idx, num2str(assigned_tasks));
fprintf('起始位置: (%.1f, %.1f)\n', agents(agent_idx).x, agents(agent_idx).y);
fprintf('速度: %.1f, α_fly=%.1f, β=%.1f\n', agents(agent_idx).vel, agents(agent_idx).fuel, agents(agent_idx).beta);

% 新接口: [t_fly, T_exec, dist, energy, ordered, arrivals, t_wait]
% 单智能体无协同任务，不需要SC参数
[t_fly, t_exec, dist, energy, ordered, arrivals, t_wait] = ...
    energy_cost(agent_idx, assigned_tasks, agents, tasks, Value_Params, R_agent);

fprintf('\n结果:\n');
fprintf('  排序后任务: [%s] (按优先级)\n', num2str(ordered));
fprintf('  总飞行时间: %.2f\n', t_fly);
fprintf('  总等待时间: %.2f (单智能体无等待)\n', t_wait);
fprintf('  总执行时间: %.2f\n', t_exec);
fprintf('  总飞行距离: %.2f\n', dist);
fprintf('  总能量消耗: %.2f\n', energy);

% 手动验证（单智能体无等待）
d1 = norm([tasks(1).x, tasks(1).y] - [agents(1).x, agents(1).y]);
d2 = norm([tasks(3).x, tasks(3).y] - [tasks(1).x, tasks(1).y]);
expected_dist = d1 + d2;
expected_t_fly = expected_dist / agents(agent_idx).vel;

% 执行时间取使用资源的最大duration
dur1 = tasks(1).duration_by_resource;
dur3 = tasks(3).duration_by_resource;
used1 = R_agent(1, :) > 1e-9;
used3 = R_agent(3, :) > 1e-9;
expected_t_exec1 = max(dur1(used1));  % 任务1使用资源1,2，取max(5,3)=5
expected_t_exec3 = max(dur3(used3));  % 任务3使用资源1,3，取max(4,4)=4
expected_t_exec = expected_t_exec1 + expected_t_exec3;

alpha_fly = agents(agent_idx).fuel;
alpha_wait = alpha_fly * 0.5;
beta = agents(agent_idx).beta;
expected_energy = expected_t_fly * alpha_fly + 0 * alpha_wait + expected_t_exec * beta;

fprintf('\n验证 (固定速度+等待模型):\n');
fprintf('  预期距离: %.2f, 实际: %.2f, 误差: %.6f\n', ...
        expected_dist, dist, abs(expected_dist - dist));
fprintf('  预期飞行时间: %.2f, 实际: %.2f, 误差: %.6f\n', ...
        expected_t_fly, t_fly, abs(expected_t_fly - t_fly));
fprintf('  预期执行时间: max(5,3)+max(4,4)=%.2f, 实际: %.2f, 误差: %.6f\n', ...
        expected_t_exec, t_exec, abs(expected_t_exec - t_exec));
fprintf('  预期能量: %.2f×%.1f + %.2f×%.1f + %.2f×%.1f = %.2f\n', ...
        expected_t_fly, alpha_fly, 0, alpha_wait, expected_t_exec, beta, expected_energy);

if abs(expected_dist - dist) < 1e-6 && abs(expected_energy - energy) < 0.01
    fprintf('? 测试1通过!\n\n');
else
    fprintf('? 测试1失败!\n\n');
end

%% 测试2: 同步机制测试（多智能体协同任务）
fprintf('\n测试2: 同步机制 - 多智能体协同执行\n');
fprintf('----------------------------------------\n');

% 创建联盟结构 SC
SC = cell(M, 1);
for m = 1:M
    SC{m} = zeros(N, K);
end

% 任务1: 智能体1 单独执行
SC{1}(1, :) = [2, 1, 0];

% 任务2: 智能体1 + 智能体2 协同执行（需要同步！）
SC{2}(1, :) = [1, 1, 0];
SC{2}(2, :) = [2, 0, 1];

% 任务3: 智能体3 单独执行
SC{3}(3, :) = [3, 2, 2];

% 任务4: 智能体2 单独执行
SC{4}(2, :) = [1, 1, 1];

fprintf('联盟结构:\n');
fprintf('  任务1 (优先级1): 智能体1 单独执行\n');
fprintf('  任务2 (优先级3): 智能体1 + 智能体2 协同执行\n');
fprintf('  任务3 (优先级2): 智能体3 单独执行\n');
fprintf('  任务4 (优先级4): 智能体2 单独执行\n\n');

% 测试智能体1（参与任务1和2，任务2需要同步）
agent_idx = 1;
assigned_tasks = [1, 2];
R_agent_1 = zeros(M, K);
R_agent_1(1, :) = SC{1}(1, :);
R_agent_1(2, :) = SC{2}(1, :);

fprintf('智能体1执行任务 [1, 2]:\n');
fprintf('  起始位置: (%.1f, %.1f), 速度: %.1f\n', agents(1).x, agents(1).y, agents(1).vel);

[t_fly_1, t_exec_1, dist_1, energy_1, ordered_1, arrival_times_1, t_wait_1] = ...
    energy_cost(agent_idx, assigned_tasks, agents, tasks, Value_Params, R_agent_1, SC);

fprintf('  排序后任务: [%s] (按优先级: 1→2)\n', num2str(ordered_1));
fprintf('  飞行时间: %.2f, 等待时间: %.2f, 执行时间: %.2f\n', t_fly_1, t_wait_1, t_exec_1);
fprintf('  任务同步开始时间: [%.2f, %.2f]\n', arrival_times_1(1), arrival_times_1(2));

% 测试智能体2（参与任务2和4，任务2需要与智能体1同步）
agent_idx = 2;
assigned_tasks = [2, 4];
R_agent_2 = zeros(M, K);
R_agent_2(2, :) = SC{2}(2, :);
R_agent_2(4, :) = SC{4}(2, :);

fprintf('\n智能体2执行任务 [2, 4]:\n');
fprintf('  起始位置: (%.1f, %.1f), 速度: %.1f\n', agents(2).x, agents(2).y, agents(2).vel);

[t_fly_2, t_exec_2, dist_2, energy_2, ordered_2, arrival_times_2, t_wait_2] = ...
    energy_cost(agent_idx, assigned_tasks, agents, tasks, Value_Params, R_agent_2, SC);

fprintf('  排序后任务: [%s] (按优先级: 2→4)\n', num2str(ordered_2));
fprintf('  飞行时间: %.2f, 等待时间: %.2f, 执行时间: %.2f\n', t_fly_2, t_wait_2, t_exec_2);
fprintf('  任务同步开始时间: [%.2f, %.2f]\n', arrival_times_2(1), arrival_times_2(2));

fprintf('\n同步验证 (任务2):\n');
fprintf('  智能体1在任务2的同步开始时间: %.2f\n', arrival_times_1(2));
fprintf('  智能体2在任务2的同步开始时间: %.2f\n', arrival_times_2(1));
fprintf('  时间差: %.6f\n', abs(arrival_times_1(2) - arrival_times_2(1)));

if abs(arrival_times_1(2) - arrival_times_2(1)) < 1e-3
    fprintf('? 同步机制工作正常 - 两个智能体同时开始任务2!\n');
else
    fprintf('? 同步失败 - 开始时间不一致\n');
end

%% 测试3: 等待时间验证（先到等待机制）
fprintf('\n\n测试3: 等待时间验证 - 先到等待机制\n');
fprintf('----------------------------------------\n');

% 创建一个需要等待的场景
% 智能体A很近（快速到达），智能体B很远（慢速到达）
agents_test(1).id = 1;
agents_test(1).x = 10;
agents_test(1).y = 10;
agents_test(1).vel = 20;  % 快速
agents_test(1).fuel = 1.0;
agents_test(1).beta = 0.5;

agents_test(2).id = 2;
agents_test(2).x = 80;
agents_test(2).y = 80;
agents_test(2).vel = 5;   % 慢速
agents_test(2).fuel = 1.0;
agents_test(2).beta = 0.5;

tasks_test(1).id = 1;
tasks_test(1).x = 50;
tasks_test(1).y = 50;
tasks_test(1).priority = 1;
tasks_test(1).duration = 5;
tasks_test(1).duration_by_resource = [2, 2, 1];

SC_test = cell(1, 1);
SC_test{1} = zeros(2, K);
SC_test{1}(1, :) = [1, 1, 0];  % 智能体1参与
SC_test{1}(2, :) = [1, 0, 1];  % 智能体2参与

Value_Params_test = Value_Params;
Value_Params_test.N = 2;
Value_Params_test.M = 1;

fprintf('场景: 快速智能体与慢速智能体协同\n');
fprintf('  智能体1: 位置(10,10), 速度20 → 任务(50,50)\n');
fprintf('  智能体2: 位置(80,80), 速度5  → 任务(50,50)\n\n');

% 计算理论到达时间
d1_test = norm([50, 50] - [10, 10]);  % ≈ 56.57
d2_test = norm([50, 50] - [80, 80]);  % ≈ 42.43
t1_theory = d1_test / 20;  % 快速智能体 ≈ 2.83
t2_theory = d2_test / 5;   % 慢速智能体 ≈ 8.49

fprintf('理论计算 (固定速度+等待模型):\n');
fprintf('  智能体1到达时间: %.2f (距离=%.2f, 速度=20)\n', t1_theory, d1_test);
fprintf('  智能体2到达时间: %.2f (距离=%.2f, 速度=5)\n', t2_theory, d2_test);
fprintf('  同步开始时间 = max(%.2f, %.2f) = %.2f\n', t1_theory, t2_theory, max(t1_theory, t2_theory));
fprintf('  智能体1等待时间 = %.2f - %.2f = %.2f\n', t2_theory, t1_theory, t2_theory - t1_theory);
fprintf('  智能体2等待时间 = 0 (最后到达)\n\n');

% 测试智能体1
R_test1 = zeros(1, K);
R_test1(1, :) = SC_test{1}(1, :);

[t_fly_test1, t_exec_test1, ~, energy_test1, ~, arrival_test1, t_wait_test1] = ...
    energy_cost(1, [1], agents_test, tasks_test, Value_Params_test, R_test1, SC_test);

fprintf('实际结果:\n');
fprintf('  智能体1: 飞行时间=%.2f, 等待时间=%.2f, 执行时间=%.2f\n', ...
        t_fly_test1, t_wait_test1, t_exec_test1);
fprintf('           同步开始时间=%.2f\n', arrival_test1(1));

% 测试智能体2
R_test2 = zeros(1, K);
R_test2(1, :) = SC_test{1}(2, :);

[t_fly_test2, t_exec_test2, ~, energy_test2, ~, arrival_test2, t_wait_test2] = ...
    energy_cost(2, [1], agents_test, tasks_test, Value_Params_test, R_test2, SC_test);

fprintf('  智能体2: 飞行时间=%.2f, 等待时间=%.2f, 执行时间=%.2f\n', ...
        t_fly_test2, t_wait_test2, t_exec_test2);
fprintf('           同步开始时间=%.2f\n', arrival_test2(1));

fprintf('\n验证:\n');
expected_wait_1 = max(t1_theory, t2_theory) - t1_theory;
expected_wait_2 = max(t1_theory, t2_theory) - t2_theory;

if abs(t_wait_test1 - expected_wait_1) < 0.01 && abs(t_wait_test2 - expected_wait_2) < 0.01
    fprintf('? 等待时间计算正确!\n');
    fprintf('  智能体1等待: 预期%.2f, 实际%.2f\n', expected_wait_1, t_wait_test1);
    fprintf('  智能体2等待: 预期%.2f, 实际%.2f\n', expected_wait_2, t_wait_test2);
else
    fprintf('? 等待时间计算错误\n');
    fprintf('  智能体1等待: 预期%.2f, 实际%.2f, 差=%.4f\n', expected_wait_1, t_wait_test1, abs(expected_wait_1-t_wait_test1));
    fprintf('  智能体2等待: 预期%.2f, 实际%.2f, 差=%.4f\n', expected_wait_2, t_wait_test2, abs(expected_wait_2-t_wait_test2));
end

% 验证能量计算
alpha_fly = 1.0;
alpha_wait = 0.5;
beta = 0.5;
exec_time_1 = max(tasks_test(1).duration_by_resource([1,2]));  % max(2,2)=2
exec_time_2 = max(tasks_test(1).duration_by_resource([1,3]));  % max(2,1)=2

expected_energy_1 = t1_theory * alpha_fly + expected_wait_1 * alpha_wait + exec_time_1 * beta;
expected_energy_2 = t2_theory * alpha_fly + expected_wait_2 * alpha_wait + exec_time_2 * beta;

fprintf('\n能量验证:\n');
fprintf('  智能体1: 预期=%.2f, 实际=%.2f\n', expected_energy_1, energy_test1);
fprintf('  智能体2: 预期=%.2f, 实际=%.2f\n', expected_energy_2, energy_test2);

%% 测试总结
fprintf('\n\n========================================\n');
fprintf('   测试完成 - 固定速度+等待模型\n');
fprintf('========================================\n');
fprintf('模型特点:\n');
fprintf('  ? 每个智能体以固定速度飞行\n');
fprintf('  ? 先到达的智能体在任务点等待\n');
fprintf('  ? 所有参与者到齐后同步开始执行\n');
fprintf('  ? 能量 = 飞行×α + 等待×(0.5α) + 执行×β\n');
