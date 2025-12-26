% tests/test_validate_join_feasibility.m
% 测试 validate_join_feasibility 函数的所有约束是否正确工作

clear; clc;

% 添加路径
thisFile = mfilename('fullpath');
[thisDir, ~, ~] = fileparts(thisFile);
projectRoot = fileparts(thisDir);
addpath(fullfile(projectRoot, 'SA'));

rng(42);

fprintf('========== 测试 validate_join_feasibility 函数 ==========\n\n');

%% ==================== 基础环境构造 ====================
Value_Params.M = 3;
Value_Params.K = 2;
Value_Params.N = 2;
Value_Params.alpha = 1.0;
Value_Params.beta = 1.0;

agents(1).id = 1;
agents(1).x = 0;
agents(1).y = 0;
agents(1).vel = 10;
agents(1).fuel = 1;
agents(1).resources = [5; 5];
agents(1).energy = 100;

agents(2).id = 2;
agents(2).x = 10;
agents(2).y = 0;
agents(2).vel = 10;
agents(2).resources = [3; 3];
agents(2).energy = 80;

for j = 1:Value_Params.M
    tasks(j).id = j;
    tasks(j).priority = j;
    tasks(j).x = 10 * j;
    tasks(j).y = 0;
    tasks(j).resource_demand = [2 2];
    tasks(j).duration = 5;
end

Value_data.agentID = 1;
Value_data.resources = agents(1).resources;

agentID = 1;
target = 1;
r = 1;

%% ==================== Case 1: 完全可行（所有约束满足） ====================
fprintf('Case 1: 完全可行的加入操作\n');

SC_P = zeros(Value_Params.M + 1, Value_Params.N);
SC_P(Value_Params.M + 1, 1) = 1; % 在空任务行

SC_Q = zeros(Value_Params.M + 1, Value_Params.N);
SC_Q(1, 1) = 1; % 加入任务1

R_agent_P = zeros(Value_Params.M, Value_Params.K);
R_agent_Q = zeros(Value_Params.M, Value_Params.K);
R_agent_Q(1, :) = [2 2]; % 分配给任务1

[feasible1, info1] = validate_join_feasibility(Value_data, agents, tasks, Value_Params, ...
    agentID, SC_P, SC_Q, R_agent_P, R_agent_Q, target, r);

assert(feasible1 == true, 'Case1 failed: should be feasible');
fprintf('  ? 可行性检查通过\n');
fprintf('  info: agentID=%d, target=%d, energyEnabled=%d\n', ...
    info1.agentID, info1.target, info1.energyFeasibilityEnabled);
if isfield(info1, 'requiredEnergy')
    fprintf('  能量: required=%.2f, capacity=%.2f, model=%s\n', ...
        info1.requiredEnergy, info1.energyCapacity, info1.energyModel);
end
fprintf('\n');

%% ==================== Case 2: 负资源分配（违反约束1） ====================
fprintf('Case 2: 负资源分配应被拒绝\n');

R_agent_Q_neg = zeros(Value_Params.M, Value_Params.K);
R_agent_Q_neg(1, 1) = -1; % 负数

[feasible2, info2] = validate_join_feasibility(Value_data, agents, tasks, Value_Params, ...
    agentID, SC_P, SC_Q, R_agent_P, R_agent_Q_neg, target, r);

assert(feasible2 == false, 'Case2 failed: negative allocation should be rejected');
assert(strcmp(info2.reason, 'negative_allocation'), 'Case2 failed: wrong reason');
fprintf('  ? 正确拒绝，原因: %s\n', info2.reason);
fprintf('  minAllocated=%.2f\n\n', info2.minAllocated);

%% ==================== Case 3: 携带量超额（违反约束2） ====================
fprintf('Case 3: 资源携带量超额应被拒绝\n');

R_agent_Q_exceed = zeros(Value_Params.M, Value_Params.K);
R_agent_Q_exceed(1, 1) = 3;
R_agent_Q_exceed(2, 1) = 3; % 总计6 > capacity=5

SC_Q_multi = zeros(Value_Params.M + 1, Value_Params.N);
SC_Q_multi(1, 1) = 1;
SC_Q_multi(2, 1) = 1;

[feasible3, info3] = validate_join_feasibility(Value_data, agents, tasks, Value_Params, ...
    agentID, SC_P, SC_Q_multi, R_agent_P, R_agent_Q_exceed, target, r);

assert(feasible3 == false, 'Case3 failed: capacity exceeded should be rejected');
assert(strcmp(info3.reason, 'capacity_exceeded'), 'Case3 failed: wrong reason');
fprintf('  ? 正确拒绝，原因: %s\n', info3.reason);
fprintf('  totalAllocated=%s, capacity=%s\n', ...
    mat2str(info3.totalAllocatedByType'), mat2str(info3.capacityByType'));
fprintf('  exceed=%s\n\n', mat2str(info3.exceedByType'));

%% ==================== Case 4: 仍在空任务行（违反约束3） ====================
fprintf('Case 4: 加入真实任务后仍在空任务行应被拒绝\n');

SC_Q_void = zeros(Value_Params.M + 1, Value_Params.N);
SC_Q_void(1, 1) = 1;
SC_Q_void(Value_Params.M + 1, 1) = 1; % 同时在任务1和空任务行

R_agent_Q_ok = zeros(Value_Params.M, Value_Params.K);
R_agent_Q_ok(1, :) = [2 2];

[feasible4, info4] = validate_join_feasibility(Value_data, agents, tasks, Value_Params, ...
    agentID, SC_P, SC_Q_void, R_agent_P, R_agent_Q_ok, target, r);

assert(feasible4 == false, 'Case4 failed: still in void row should be rejected');
assert(strcmp(info4.reason, 'still_in_void_row'), 'Case4 failed: wrong reason');
fprintf('  ? 正确拒绝，原因: %s\n', info4.reason);
fprintf('  inVoidRowAfter=%d\n\n', info4.inVoidRowAfter);

%% ==================== Case 5: 未真正加入目标任务（违反约束4） ====================
fprintf('Case 5: SC_Q(target,agent)=0 应被拒绝\n');

SC_Q_notjoined = zeros(Value_Params.M + 1, Value_Params.N);
SC_Q_notjoined(2, 1) = 1; % 加入任务2，但target=1

[feasible5, info5] = validate_join_feasibility(Value_data, agents, tasks, Value_Params, ...
    agentID, SC_P, SC_Q_notjoined, R_agent_P, R_agent_Q_ok, target, r);

assert(feasible5 == false, 'Case5 failed: not joined target should be rejected');
assert(strcmp(info5.reason, 'not_joined_target_row'), 'Case5 failed: wrong reason');
fprintf('  ? 正确拒绝，原因: %s\n\n', info5.reason);

%% ==================== Case 6: 能量不足（违反约束5 - 时间模型） ====================
fprintf('Case 6: 能量不足应被拒绝（时间模型 alpha/beta）\n');

Value_data_lowEnergy = Value_data;
Value_data_lowEnergy.energy = 5; % 很低的能量预算

tasks_far = tasks;
tasks_far(1).x = 1000;
tasks_far(1).y = 0;
tasks_far(1).duration = 10;

SC_Q_energy = zeros(Value_Params.M + 1, Value_Params.N);
SC_Q_energy(1, 1) = 1;

R_agent_Q_energy = zeros(Value_Params.M, Value_Params.K);
R_agent_Q_energy(1, :) = [2 2];

[feasible6, info6] = validate_join_feasibility(Value_data_lowEnergy, agents, tasks_far, Value_Params, ...
    agentID, SC_P, SC_Q_energy, R_agent_P, R_agent_Q_energy, target, r);

assert(feasible6 == false, 'Case6 failed: energy insufficient should be rejected');
assert(strcmp(info6.reason, 'energy_insufficient'), 'Case6 failed: wrong reason');
fprintf('  ? 正确拒绝，原因: %s\n', info6.reason);
fprintf('  requiredEnergy=%.2f, energyCapacity=%.2f\n', ...
    info6.requiredEnergy, info6.energyCapacity);
fprintf('  model=%s\n', info6.energyModel);
if isfield(info6, 't_wait_total')
    fprintf('  t_wait_total=%.2f, T_exec_total=%.2f\n', ...
        info6.t_wait_total, info6.T_exec_total);
end
fprintf('  routeDistance=%.2f\n', info6.routeDistance);
fprintf('  taskSequence=%s\n\n', mat2str(info6.taskSequenceByPriority));

%% ==================== Case 7: 任务序列优先级排序 ====================
fprintf('Case 7: 验证任务序列按 priority 排序\n');

tasks_priority = tasks;
tasks_priority(1).priority = 3;
tasks_priority(2).priority = 1;
tasks_priority(3).priority = 2;

SC_Q_multi_tasks = zeros(Value_Params.M + 1, Value_Params.N);
SC_Q_multi_tasks(1, 1) = 1;
SC_Q_multi_tasks(2, 1) = 1;
SC_Q_multi_tasks(3, 1) = 1;

R_agent_Q_multi = zeros(Value_Params.M, Value_Params.K);
R_agent_Q_multi(1, :) = [1 1];
R_agent_Q_multi(2, :) = [1 1];
R_agent_Q_multi(3, :) = [1 1];

Value_data_multi = Value_data;
Value_data_multi.energy = 1000; % 足够的能量

[feasible7, info7] = validate_join_feasibility(Value_data_multi, agents, tasks_priority, Value_Params, ...
    agentID, SC_P, SC_Q_multi_tasks, R_agent_P, R_agent_Q_multi, target, r);

assert(feasible7 == true, 'Case7 failed: should be feasible');
fprintf('  ? 可行性检查通过\n');
fprintf('  assignedTasks=%s\n', mat2str(info7.assignedTasks));
fprintf('  taskSequenceByPriority=%s (应按 priority 排序: [2,3,1])\n', ...
    mat2str(info7.taskSequenceByPriority));
assert(isequal(info7.taskSequenceByPriority, [2 3 1]), ...
    'Case7 failed: task sequence should be sorted by priority');
fprintf('  ? 任务序列排序正确\n\n');

%% ==================== Case 8: 无能量字段时跳过能量检查 ====================
fprintf('Case 8: 无能量字段时应跳过能量检查\n');

% 重建智能体结构，不包含 energy 字段
agents_noEnergy = agents;
for ii = 1:numel(agents_noEnergy)
    if isfield(agents_noEnergy, 'energy')
        agents_noEnergy = rmfield(agents_noEnergy, 'energy');
    end
end

Value_data_noEnergy = Value_data;
if isfield(Value_data_noEnergy, 'energy')
    Value_data_noEnergy = rmfield(Value_data_noEnergy, 'energy');
end
if isfield(Value_data_noEnergy, 'totalEnergy')
    Value_data_noEnergy = rmfield(Value_data_noEnergy, 'totalEnergy');
end

[feasible8, info8] = validate_join_feasibility(Value_data_noEnergy, agents_noEnergy, tasks, Value_Params, ...
    agentID, SC_P, SC_Q, R_agent_P, R_agent_Q, target, r);

assert(feasible8 == true, 'Case8 failed: should be feasible');
assert(info8.energyFeasibilityEnabled == false, ...
    'Case8 failed: energy feasibility should be disabled');
assert(isfield(info8, 'energyFeasibilitySkipped'), ...
    'Case8 failed: should have energyFeasibilitySkipped flag');
fprintf('  ? 正确跳过能量检查\n');
fprintf('  energyFeasibilityEnabled=%d\n\n', info8.energyFeasibilityEnabled);

%% ==================== Case 9: 距离模型回退（无 alpha/beta） ====================
fprintf('Case 9: 无 alpha/beta 时使用距离模型\n');

Value_Params_noAlphaBeta = Value_Params;
Value_Params_noAlphaBeta = rmfield(Value_Params_noAlphaBeta, 'alpha');
Value_Params_noAlphaBeta = rmfield(Value_Params_noAlphaBeta, 'beta');

Value_data_distance = Value_data;
Value_data_distance.energy = 10; % 较低能量预算

[feasible9, info9] = validate_join_feasibility(Value_data_distance, agents, tasks, Value_Params_noAlphaBeta, ...
    agentID, SC_P, SC_Q, R_agent_P, R_agent_Q, target, r);

fprintf('  energyModel=%s\n', info9.energyModel);
assert(strcmp(info9.energyModel, 'distance_fuel'), ...
    'Case9 failed: should use distance_fuel model');
fprintf('  ? 正确使用距离模型\n');
fprintf('  requiredEnergy=%.2f, energyCapacity=%.2f\n', ...
    info9.requiredEnergy, info9.energyCapacity);
fprintf('  fuelCoef=%.2f\n\n', info9.fuelCoef);

%% ==================== 测试总结 ====================
fprintf('========================================\n');
fprintf('所有测试通过! ?\n');
fprintf('validate_join_feasibility 函数验证完成。\n');
fprintf('========================================\n');
