clear;
clc;

SEED=2437;
rand('seed',SEED);

% 世界空间参数
WORLD.XMIN=0;
WORLD.XMAX=100;
WORLD.YMIN=0;
WORLD.YMAX=100;
WORLD.value=[800,1000,1500];

% 基本参数
M = 6;
K = 6;
num_resources = K;
num_task_types = 3;

% 资源执行时间参数
resource_exec_time = [50 65 50 60 35 45]; 

%% 初始化任务类型的资源需求
task_type_demands = zeros(num_task_types, num_resources);
task_type_demands(1, :) = randi([0, 4], 1, num_resources);
task_type_demands(2, :) = randi([0, 6], 1, num_resources);
task_type_demands(3, :) = randi([0, 8], 1, num_resources);

%% 初始化资源执行时间
task_type_duration_by_resource = zeros(num_task_types, num_resources);
for t = 1:num_task_types
    needed = task_type_demands(t, :) > 0;
    task_type_duration_by_resource(t, needed) = resource_exec_time(needed);
end

%% 初始化任务
task_priorities = randperm(M);
for j = 1:M    
    tasks(j).id = j;
    tasks(j).type = randi(num_task_types, 1, 1);
    tasks(j).resource_demand = task_type_demands(tasks(j).type, :);
    tasks(j).duration_by_resource = task_type_duration_by_resource(tasks(j).type, :);
    tasks(j).duration = max(tasks(j).duration_by_resource);
    
    fprintf('Task T%d: Type=%d, Duration=%d\n', j, tasks(j).type, tasks(j).duration);
    disp('  Needed Resources indices:');
    disp(find(tasks(j).resource_demand > 0));
    disp('  Duration by Resource:');
    disp(tasks(j).duration_by_resource);
end

disp('Resource Execution Times:');
disp(resource_exec_time);
