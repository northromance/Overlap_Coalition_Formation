%% quick_test_energy.m
% 快速测试 energy_cost.m 的基本功能和同步机制 - 固定速度+等待模型

clear;
addpath('../SA');

%% 快速测试设置
N = 2; M = 2; K = 3;

% 智能体
agents(1) = struct('id', 1, 'x', 0, 'y', 0, 'vel', 10, 'fuel', 1, 'beta', 0.5);
agents(2) = struct('id', 2, 'x', 50, 'y', 50, 'vel', 8, 'fuel', 1, 'beta', 0.5);

% 任务
tasks(1) = struct('id', 1, 'x', 30, 'y', 40, 'priority', 1, ...
                  'duration', 10, 'duration_by_resource', [4, 3, 3]);
tasks(2) = struct('id', 2, 'x', 70, 'y', 20, 'priority', 2, ...
                  'duration', 15, 'duration_by_resource', [5, 5, 5]);

% 参数
Value_Params = struct('N', N, 'M', M, 'K', K);

%% 测试1: 无同步（单智能体执行）
fprintf('=== 测试1: 单智能体执行 (固定速度+等待模型) ===\n');
R = zeros(M, K);
R(1, :) = [1, 1, 0];
R(2, :) = [1, 0, 1];

% 新接口: [t_fly, T_exec, dist, energy, ordered, arrivals, t_wait]
[t_fly, t_exec, dist, energy, ordered, arrivals, t_wait] = ...
    energy_cost(1, [1, 2], agents, tasks, Value_Params, R);

fprintf('任务序列: %s\n', mat2str(ordered));
fprintf('飞行时间: %.2f, 等待时间: %.2f, 执行时间: %.2f\n', t_fly, t_wait, t_exec);
fprintf('总距离: %.2f, 能量: %.2f\n', dist, energy);
fprintf('任务开始时间: %s\n\n', mat2str(arrivals, 2));

%% 测试2: 同步机制（协同任务）
fprintf('=== 测试2: 双智能体同步到任务2 (固定速度+等待) ===\n');

% 创建联盟结构
SC = cell(M, 1);
SC{1} = zeros(N, K);
SC{2} = zeros(N, K);
SC{2}(1, :) = [2, 1, 0];  % 任务2: 智能体1参与
SC{2}(2, :) = [1, 1, 1];  % 任务2: 智能体2也参与（需同步）

R1 = zeros(M, K);
R1(2, :) = SC{2}(1, :);

R2 = zeros(M, K);
R2(2, :) = SC{2}(2, :);

% 智能体1到任务2
[t1, exec1, ~, E1, ~, arr1, wait1] = energy_cost(1, [2], agents, tasks, Value_Params, R1, SC);
% 智能体2到任务2
[t2, exec2, ~, E2, ~, arr2, wait2] = energy_cost(2, [2], agents, tasks, Value_Params, R2, SC);

fprintf('智能体1: 飞行=%.2f, 等待=%.2f, 同步开始=%.2f\n', t1, wait1, arr1(1));
fprintf('智能体2: 飞行=%.2f, 等待=%.2f, 同步开始=%.2f\n', t2, wait2, arr2(1));
fprintf('开始时间差: %.4f\n', abs(arr1(1) - arr2(1)));

if abs(arr1(1) - arr2(1)) < 0.01
    fprintf('? 同步成功! 两个智能体同时开始任务\n');
else
    fprintf('? 同步有差异\n');
end

% 验证等待时间
d1 = norm([70, 20] - [0, 0]);   % 智能体1距离
d2 = norm([70, 20] - [50, 50]); % 智能体2距离
t1_arrive = d1 / 10;  % 智能体1到达时间
t2_arrive = d2 / 8;   % 智能体2到达时间
sync_time = max(t1_arrive, t2_arrive);

fprintf('\n理论验证:\n');
fprintf('  智能体1: 距离=%.2f, 速度=10, 到达=%.2f, 等待=%.2f\n', ...
        d1, t1_arrive, sync_time - t1_arrive);
fprintf('  智能体2: 距离=%.2f, 速度=8, 到达=%.2f, 等待=%.2f\n', ...
        d2, t2_arrive, sync_time - t2_arrive);
fprintf('  同步开始时间 = max(%.2f, %.2f) = %.2f\n', t1_arrive, t2_arrive, sync_time);

fprintf('\n模型说明:\n');
fprintf('  ? 固定速度飞行: 智能体以自己的速度飞行\n');
fprintf('  ? 先到等待: 先到的在任务点悬停等待\n');
fprintf('  ? 等待能耗 = 飞行能耗 × 0.5\n');
