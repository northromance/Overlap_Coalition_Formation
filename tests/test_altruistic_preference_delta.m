% tests/test_altruistic_preference_delta.m
% 验证 SA_altruistic_preference_delta 的输出符号与 join_operation 的默认行为

clear; clc;

% addpath SA
thisFile = mfilename('fullpath');
[thisDir, ~, ~] = fileparts(thisFile);
projectRoot = fileparts(thisDir);
addpath(fullfile(projectRoot, 'SA'));

rng(1);

Value_Params.M = 2;
Value_Params.K = 1;
Value_Params.N = 2;
Value_Params.Temperature = 1;

% 使用可控 utilityFcn，避免依赖 tasks.WORLD / agents.completionRate
% 这里定义 u(agent,SC) = agent 加入的任务数量（1..M 行里出现次数）
Value_Params.utilityFcn = @(agentID, SC, tasks, agents, params, vd) sum(SC(1:params.M, agentID) == agentID);

agents(1).id = 1; agents(1).x = 0; agents(1).y = 0; agents(1).resources = 1;
agents(2).id = 2; agents(2).x = 0; agents(2).y = 0; agents(2).resources = 1;

tasks(1).id = 1; tasks(1).x = 0; tasks(1).y = 0; tasks(1).resource_demand = 1;
tasks(2).id = 2; tasks(2).x = 0; tasks(2).y = 0; tasks(2).resource_demand = 1;

Value_data.agentID = 1;
Value_data.resources = 1;
Value_data.initbelief = repmat([1/3 1/3 1/3], Value_Params.M, 1);

% SC_P: agent2 在任务1，agent1 在空任务
SC_P = zeros(Value_Params.M + 1, Value_Params.N);
SC_P(1, 2) = 2;
SC_P(Value_Params.M + 1, 1) = 1;

% SC_Q: agent1 加入任务1
SC_Q = SC_P;
SC_Q(1, 1) = 1;
SC_Q(Value_Params.M + 1, 1) = 0;

% delta 应该 >0
Delta = SA_altruistic_preference_delta(tasks, agents, SC_P, SC_Q, 1, Value_Params, Value_data, 1);
assert(Delta > 0, 'Expected delta>0 for a join that increases agent utility under the toy utilityFcn');
disp('Preference delta test passed');

% 再验证 join_operation 在未提供 preferenceFcn 时，默认使用 SA_altruistic_preference_delta
Value_data2 = Value_data;
Value_data2.coalitionstru = SC_P;
probs = [1 0]; % K=1, 必选任务1（1xM 矩阵）

[vd_after, inc] = join_operation(Value_data2, agents, tasks, Value_Params, probs);
assert(inc == 1, 'Expected join_operation incremental_join=1 with positive delta');
assert(vd_after.coalitionstru(1, 1) == 1, 'Expected agent1 to join task1');
assert(vd_after.coalitionstru(Value_Params.M+1, 1) == 0, 'Expected void row cleared');
disp('join_operation default preference test passed');
