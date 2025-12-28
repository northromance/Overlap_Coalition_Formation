% tests/test_join_operation.m
% 最小测试：验证 join_operation 的输入/输出与更新逻辑

clear; clc;

% addpath SA
thisFile = mfilename('fullpath');
[thisDir, ~, ~] = fileparts(thisFile);
projectRoot = fileparts(thisDir);
addpath(fullfile(projectRoot, 'SA'));

rng(1);

fprintf('Running test_join_operation...\n');

% ------------------ 构造最小环境 ------------------
Value_Params.M = 3;
Value_Params.K = 2;
Value_Params.N = 1;
Value_Params.Temperature = 1;
% 说明：validate_join_feasibility 当前能量模型使用 agents(i).fuel 与 agents(i).beta。
% Value_Params.alpha/beta 不再参与能量可行性计算（保留字段不影响）。
Value_Params.alpha = 1.0;
Value_Params.beta = 1.0;

agents(1).id = 1;
agents(1).x = 0;
agents(1).y = 0;
agents(1).vel = 1;   % 速度（与 validate_join_feasibility 兼容）
agents(1).speed = agents(1).vel; % 兼容 overlap_coalition_self_utility 中的 speed 字段
agents(1).fuel = 1;
agents(1).beta = 1;
agents(1).resources = [1; 1];
agents(1).Emax = 1e9; % 默认给足，避免影响非能量相关用例

for j = 1:Value_Params.M
    tasks(j).id = j;
    tasks(j).priority = j; % 数值越小优先级越高（这里用自然序）
    tasks(j).x = j;
    tasks(j).y = 0;
    tasks(j).WORLD.value = [300 500 1000];
    tasks(j).value = 300;
    tasks(j).resource_demand = [1 1];
    tasks(j).duration_by_resource = [0 0];
    tasks(j).duration = sum(tasks(j).duration_by_resource); % 默认不给执行时长，避免影响其它用例
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

% ------------------ Case 2: 概率全为0 -> 不应加入任何任务 ------------------
Value_data2 = Value_data;
probs2 = zeros(Value_Params.K, Value_Params.M); % 所有资源类型都无可选任务
[vd2, inc2] = join_operation(Value_data2, agents, tasks, Value_Params, probs2);
assert(inc2 == 0, 'Case2 failed: incremental_join should be 0');
assert(all(vd2.coalitionstru(1:Value_Params.M, 1) == 0), 'Case2 failed: should not join any task');
assert(vd2.coalitionstru(Value_Params.M+1, 1) == 1, 'Case2 failed: void task row should remain');
disp('Case2 passed');

% ------------------ Case 3: 不同资源类型选不同任务，但一旦接受就跳出 ------------------
Value_Params.preferenceFcn = @(tasks_, agents_, before_, after_, agentID_, params_, vd_, target_) 1;

probs3 = [1 0 0;  % r=1 选任务1
          0 0 1]; % r=2 选任务3

Value_data3 = Value_data;
[vd3, inc3] = join_operation(Value_data3, agents, tasks, Value_Params, probs3);
assert(inc3 == 1, 'Case3 failed: incremental_join should be 1');
assert(vd3.coalitionstru(1, 1) == 1, 'Case3 failed: should join task 1');
assert(vd3.coalitionstru(3, 1) == 0, 'Case3 failed: should NOT also join task 3 (break after first accept)');
assert(vd3.coalitionstru(Value_Params.M+1, 1) == 0, 'Case3 failed: void task row should be cleared');
disp('Case3 passed');

% ------------------ Case 4: 携带量约束触发 -> 可行性检测应强制拒绝 ------------------
fprintf('Case4: capacity constraint should be rejected (feasibility gate)\n');
Value_Params.preferenceFcn = @(tasks_, agents_, before_, after_, agentID_, params_, vd_, target_) 1;

Value_data4 = Value_data;
% 注意：当前 compute_coalition_and_resource_changes 会“搬运”资源而不是叠加，
% 因此这里通过缩小 Value_data4.resources 作为携带量上限来触发不可行。
Value_data4.resources = [0; 1]; % r=1 容量为0，任何 r=1 分配都会超额
Value_data4.resources_matrix = zeros(Value_Params.M, Value_Params.K);
Value_data4.coalitionstru = zeros(Value_Params.M + 1, Value_Params.N);
Value_data4.coalitionstru(Value_Params.M + 1, 1) = 1; % 初始在 void

% r=1 一定选任务2（会导致 r=1 总分配=2 > capacity=1）
probs4 = [0 1 0;
         0 0 0];

[vd4, inc4] = join_operation(Value_data4, agents, tasks, Value_Params, probs4);
assert(inc4 == 0, 'Case4 failed: incremental_join should be 0 due to infeasible join');
assert(vd4.coalitionstru(2, 1) == 0, 'Case4 failed: agent should not join task 2');
assert(sum(vd4.resources_matrix(:, 1)) <= Value_data4.resources(1) + 1e-9, 'Case4 failed: capacity constraint violated');
disp('Case4 passed');

% ------------------ Case 5: 能量不足 -> 任务序列 + 回到起点不可达，应强制拒绝 ------------------
fprintf('Case5: energy insufficient should be rejected (sequence + return-to-start)\n');

Value_Params.preferenceFcn = @(tasks_, agents_, before_, after_, agentID_, params_, vd_, target_) 1;

agents5 = agents;
agents5(1).Emax = 100; % 总能量预算（单位与模型一致：t_wait_total*fuel + T_exec_total*beta，t_wait_total=distance/vel）

tasks5 = tasks;
tasks5(1).x = 1000; tasks5(1).y = 0;
tasks5(2).x = 2000; tasks5(2).y = 0;
tasks5(3).x = 3000; tasks5(3).y = 0;
tasks5(1).priority = 1;
tasks5(2).priority = 2;
tasks5(3).priority = 3;
tasks5(1).duration_by_resource = [10 10];
tasks5(2).duration_by_resource = [10 10];
tasks5(3).duration_by_resource = [10 10];
tasks5(1).duration = sum(tasks5(1).duration_by_resource);
tasks5(2).duration = sum(tasks5(2).duration_by_resource);
tasks5(3).duration = sum(tasks5(3).duration_by_resource);

Value_data5 = Value_data;
Value_data5.coalitionstru = zeros(Value_Params.M + 1, Value_Params.N);
Value_data5.coalitionstru(1, 1) = 1;                % 已经在任务1
Value_data5.coalitionstru(Value_Params.M + 1, 1) = 0; % 不在 void
Value_data5.resources_matrix = zeros(Value_Params.M, Value_Params.K);

% r=1 一定选任务2（加入后序列：任务1 -> 任务2 -> 起点，距离极大，能量不足）
probs5 = [0 1 0;
          0 0 0];

[vd5, inc5] = join_operation(Value_data5, agents5, tasks5, Value_Params, probs5);
assert(inc5 == 0, 'Case5 failed: incremental_join should be 0 due to energy infeasibility');
assert(vd5.coalitionstru(2, 1) == 0, 'Case5 failed: agent should not join task 2');
disp('Case5 passed');

disp('All join_operation tests passed.');
