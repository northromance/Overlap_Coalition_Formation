% tests/test_task_priorities.m
% 目的：验证 Main.m 中任务优先级 tasks(j).priority 的生成逻辑，并打印每个任务的优先级

clear; clc;

% 为了可复现，固定随机种子（与 Main.m 一致的 SEED）
SEED = 24375;
rng(SEED, 'twister');

% 与 Main.m 一致的关键参数
M = 10;
K = 6;
num_resources = 6;
num_task_types = 3;

WORLD.XMIN=0; WORLD.XMAX=100;
WORLD.YMIN=0; WORLD.YMAX=100;
WORLD.value=[300,500,1000];

task_type_demands_range = [0, 5];
task_type_duration = [100, 150, 200];

% 随机生成任务类型资源需求
task_type_demands = randi(task_type_demands_range, num_task_types, num_resources);

% ====== 复制 Main.m 的“任务优先级 + 初始化”逻辑 ======
% 数值越小优先级越高
task_priorities = randperm(M);

for j = 1:M
    tasks(j).id = j;
    tasks(j).priority = task_priorities(j);
    tasks(j).x = round(rand(1) * (WORLD.XMAX - WORLD.XMIN) + WORLD.XMIN);
    tasks(j).y = round(rand(1) * (WORLD.YMAX - WORLD.YMIN) + WORLD.YMIN);
    tasks(j).value = WORLD.value(randi(length(WORLD.value), 1, 1));
    tasks(j).type = randi(num_task_types, 1, 1);
    tasks(j).resource_demand = task_type_demands(tasks(j).type, :);
    tasks(j).duration = task_type_duration(tasks(j).type);
end

% ====== 断言：priority 是 1..M 的不重复排列 ======
priorities = [tasks.priority];
assert(numel(priorities) == M, 'priority length mismatch');
assert(numel(unique(priorities)) == M, 'priorities must be unique');
assert(all(sort(priorities) == 1:M), 'priorities must be a permutation of 1..M');

% ====== 打印：每个任务的优先级 ======
disp('Task priorities (smaller = higher):');
for j = 1:M
    fprintf('  Task %d: priority = %d\n', tasks(j).id, tasks(j).priority);
end

disp('test_task_priorities passed');
