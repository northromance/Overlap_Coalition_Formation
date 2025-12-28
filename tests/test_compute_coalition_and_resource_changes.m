% tests/test_compute_coalition_and_resource_changes.m
% 验证 compute_coalition_and_resource_changes 的资源分配/汇总逻辑：
% - join 只移动 r 列资源到 target（该列其它任务清零）
% - R_total_* 不再按联盟结构把 agents(i).resources 全部算进来

clear; clc;

thisFile = mfilename('fullpath');
[thisDir, ~, ~] = fileparts(thisFile);
projectRoot = fileparts(thisDir);
addpath(fullfile(projectRoot, 'SA'));

fprintf('Running test_compute_coalition_and_resource_changes...\n');

Value_Params.M = 3;
Value_Params.K = 2;
Value_Params.N = 2;

agents(1).id = 1;
agents(1).resources = [5; 7];
agents(2).id = 2;
agents(2).resources = [4; 6];

Value_data.agentID = 1;
Value_data.resources = agents(1).resources;

% coalitionstru: (M+1) x N，最后一行是空任务
Value_data.coalitionstru = zeros(Value_Params.M + 1, Value_Params.N);
% 智能体1当前在任务1和3（允许重叠）
Value_data.coalitionstru(1, 1) = 1;
Value_data.coalitionstru(3, 1) = 1;
% 智能体1不在 void 行
Value_data.coalitionstru(Value_Params.M + 1, 1) = 0;

% 资源分配矩阵：该智能体的 M×K 分配
% r=1(第一列)当前分散在任务1与3，总量=5
% r=2(第二列)给任务1=2, 任务2=1
Value_data.resources_matrix = zeros(Value_Params.M, Value_Params.K);
Value_data.resources_matrix(1, 1) = 2;
Value_data.resources_matrix(3, 1) = 3;
Value_data.resources_matrix(1, 2) = 2;
Value_data.resources_matrix(2, 2) = 1;

agentID = 1;
r = 1;
target = 2;

[SC_P, SC_Q, R_agent_P, R_agent_Q, R_total_P, R_total_Q] = ...
    compute_coalition_and_resource_changes(Value_data, agents, Value_Params, target, agentID, r);

% 1) 操作前保持不变
assert(isequal(R_agent_P, Value_data.resources_matrix), 'R_agent_P should equal original resources_matrix');

% 2) 操作后：仅 r 列被“全集中”到 target
expected_Q = R_agent_P;
expected_Q(:, r) = 0;
expected_Q(target, r) = agents(1).resources(r);
assert(isequal(R_agent_Q, expected_Q), 'R_agent_Q should move all type-r resources to target and zero others');

% 3) 联盟结构：target 行加入，且 void 行不应被置 1
assert(SC_Q(target, 1) == 1, 'SC_Q should include agent in target row');
assert(SC_Q(Value_Params.M + 1, 1) == 0, 'SC_Q should keep void row cleared');

% 4) R_total_*：只基于该智能体自身分配进行汇总（不应把 agents(i).resources 当成已分配资源）
% 由于智能体1在 SC_P 的任务1/3，所以 R_total_P 仅在这些行等于 R_agent_P
assert(all(R_total_P(1, :) == R_agent_P(1, :)), 'R_total_P row1 mismatch');
assert(all(R_total_P(2, :) == 0), 'R_total_P row2 should be zero (agent not in task2 before)');
assert(all(R_total_P(3, :) == R_agent_P(3, :)), 'R_total_P row3 mismatch');

% 操作后智能体1在任务1/2/3，所以三行都应等于 R_agent_Q
assert(all(R_total_Q(1, :) == R_agent_Q(1, :)), 'R_total_Q row1 mismatch');
assert(all(R_total_Q(2, :) == R_agent_Q(2, :)), 'R_total_Q row2 mismatch');
assert(all(R_total_Q(3, :) == R_agent_Q(3, :)), 'R_total_Q row3 mismatch');

fprintf('test_compute_coalition_and_resource_changes passed.\n');

