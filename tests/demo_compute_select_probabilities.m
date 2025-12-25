% tests/demo_compute_select_probabilities.m
% 最小例子：验证 compute_select_probabilities 是否按“resource_gap + (资源可用量) / 距离”得到正确归一化概率

clear; clc;

% 确保能找到 SA 目录下的函数
thisFile = mfilename('fullpath');
[thisDir, ~, ~] = fileparts(thisFile);
projectRoot = fileparts(thisDir);
addpath(fullfile(projectRoot, 'SA'));

% --------- 构造最小环境 ---------
Value_Params.M = 2;
Value_Params.K = 2;

% 1个智能体
agents(1).id = 1;
agents(1).x = 0;
agents(1).y = 0;
agents(1).resources = [2; 1];  % K=2

% Value_data（与主代码一致：resources / initbelief / agentID）
Value_data.agentID = 1;
Value_data.resources = agents(1).resources;
Value_data.initbelief = [1/3 1/3 1/3; 1/3 1/3 1/3]; % 这里不影响（因为提供了 resource_gap）

% 2个任务：距离都为1（便于手算）
tasks(1).id = 1; tasks(1).x = 1; tasks(1).y = 0; tasks(1).resource_demand = [3 0];
tasks(2).id = 2; tasks(2).x = 0; tasks(2).y = 1; tasks(2).resource_demand = [1 2];

% 已分配资源（N x K）
allocated_resources = zeros(1, 2);

% 剩余需求 resource_gap（M x K）
% 资源1: 任务1缺口3，任务2缺口1 -> 权重比 3:1 (距离相同，资源可用量相同)
% 资源2: 任务1缺口0，任务2缺口2 -> [0, 1]
resource_gap = [3 0;
                1 2];

% --------- 调用并验证 ---------
probs = compute_select_probabilities(Value_data, agents, tasks, Value_Params, allocated_resources, resource_gap);

expected_probs = [0.75 0.25;
                  0    1.00];

tol = 1e-12;
assert(all(abs(probs(:) - expected_probs(:)) < tol), 'Demo1 failed: probs not as expected.');
disp('Demo1 passed: probs matches expected.');

% --------- 验证“已分配资源导致可用量为0”的情况 ---------
allocated_resources2 = [2 0]; % 资源1已占满 -> 资源1行应全0
probs2 = compute_select_probabilities(Value_data, agents, tasks, Value_Params, allocated_resources2, resource_gap);

expected_probs2 = [0 0;
                   0 1];
assert(all(abs(probs2(:) - expected_probs2(:)) < tol), 'Demo2 failed: probs2 not as expected.');
disp('Demo2 passed: allocated_resources affects availability as expected.');
