% tests/test_join_operation.m
% 最小测试：验证 join_operation 的输入/输出与更新逻辑

clear; clc;

% addpath SA
thisFile = mfilename('fullpath');
[thisDir, ~, ~] = fileparts(thisFile);
projectRoot = fileparts(thisDir);
addpath(fullfile(projectRoot, 'SA'));

rng(1);

% ------------------ 构造最小环境 ------------------
Value_Params.M = 3;
Value_Params.K = 2;
Value_Params.N = 1;
Value_Params.Temperature = 1;

agents(1).id = 1;
agents(1).x = 0;
agents(1).y = 0;
agents(1).resources = [1; 1];

for j = 1:Value_Params.M
    tasks(j).id = j;
    tasks(j).x = j;
    tasks(j).y = 0;
    tasks(j).resource_demand = [1 1];
end

Value_data.agentID = 1;
Value_data.resources = agents(1).resources;
Value_data.initbelief = repmat([1/3 1/3 1/3], Value_Params.M, 1);

% coalitionstru: (M+1) x N，最后一行是空任务
Value_data.coalitionstru = zeros(Value_Params.M + 1, Value_Params.N);
Value_data.coalitionstru(Value_Params.M + 1, 1) = 1;

% ------------------ Case 1: 一定接受，且任务选择确定 ------------------
Value_Params.preferenceFcn = @(tasks_, agents_, before_, after_, agentID_, params_, vd_, target_) 1; %#ok<NASGU>

probs = [0 1 0;   % r=1 一定选任务2
         0 1 0];  % r=2 一定选任务2

[vd1, inc1] = join_operation(Value_data, agents, tasks, Value_Params, probs);
assert(inc1 == 1, 'Case1 failed: incremental_join should be 1');
assert(vd1.coalitionstru(2, 1) == 1, 'Case1 failed: agent should join task 2');
assert(vd1.coalitionstru(Value_Params.M+1, 1) == 0, 'Case1 failed: void task row should be cleared');
disp('Case1 passed');

% ------------------ Case 2: 一定拒绝（delta=-Inf） ------------------
Value_Params.preferenceFcn = @(tasks_, agents_, before_, after_, agentID_, params_, vd_, target_) -inf;

Value_data2 = Value_data;
[vd2, inc2] = join_operation(Value_data2, agents, tasks, Value_Params, probs);
assert(inc2 == 0, 'Case2 failed: incremental_join should be 0');
assert(all(vd2.coalitionstru(1:Value_Params.M, 1) == 0), 'Case2 failed: should not join any task');
assert(vd2.coalitionstru(Value_Params.M+1, 1) == 1, 'Case2 failed: void task row should remain');
disp('Case2 passed');

% ------------------ Case 3: 不同资源类型选不同任务，应可重叠加入 ------------------
Value_Params.preferenceFcn = @(tasks_, agents_, before_, after_, agentID_, params_, vd_, target_) 1;

probs3 = [1 0 0;  % r=1 选任务1
          0 0 1]; % r=2 选任务3

Value_data3 = Value_data;
[vd3, inc3] = join_operation(Value_data3, agents, tasks, Value_Params, probs3);
assert(inc3 == 1, 'Case3 failed: incremental_join should be 1');
assert(vd3.coalitionstru(1, 1) == 1, 'Case3 failed: should join task 1');
assert(vd3.coalitionstru(3, 1) == 1, 'Case3 failed: should join task 3');
assert(vd3.coalitionstru(Value_Params.M+1, 1) == 0, 'Case3 failed: void task row should be cleared');
disp('Case3 passed');

disp('All join_operation tests passed.');
