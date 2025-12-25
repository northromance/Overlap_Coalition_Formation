% tests/test_overlap_coalition_formation_smoke.m
% 烟雾测试：验证 Overlap_Coalition_Formation 的输入输出不报错，且 incremental 可返回 0/1

clear; clc;

thisFile = mfilename('fullpath');
[thisDir, ~, ~] = fileparts(thisFile);
projectRoot = fileparts(thisDir);
addpath(fullfile(projectRoot, 'SA'));

rng(1);

Value_Params.M = 2;
Value_Params.K = 2;
Value_Params.N = 1;
Value_Params.Temperature = 1;

agents(1).id = 1;
agents(1).x = 0;
agents(1).y = 0;
agents(1).resources = [2; 2];

for j = 1:Value_Params.M
    tasks(j).id = j;
    tasks(j).x = j;
    tasks(j).y = 0;
    tasks(j).resource_demand = [1 1];
end

Value_data.agentID = 1;
Value_data.iteration = 0;
Value_data.unif = 0;
Value_data.resources = agents(1).resources;
Value_data.initbelief = repmat([1/3 1/3 1/3], Value_Params.M, 1);
Value_data.coalitionstru = zeros(Value_Params.M + 1, Value_Params.N);
Value_data.coalitionstru(Value_Params.M + 1, 1) = 1;

allocated_resources = zeros(Value_Params.N, Value_Params.K);
resource_gap = [1 0;
                0 1];

AddPara = struct();
counter = 1;

% 偏好函数：始终接受（避免依赖 SA_altruistic_utility）
Value_Params.preferenceFcn = @(tasks_, agents_, before_, after_, agentID_, params_, vd_, target_) 1;

[incremental, curnumberrow, Value_data_out] = Overlap_Coalition_Formation(agents, tasks, Value_data, Value_Params, counter, AddPara, allocated_resources, resource_gap);

assert(isnumeric(incremental) && isscalar(incremental), 'incremental should be a scalar');
assert(ismember(incremental, [0 1]), 'incremental should be 0 or 1');
assert(isequal(size(Value_data_out.coalitionstru), size(Value_data.coalitionstru)), 'coalitionstru size should be preserved');

% curnumberrow 当前函数未使用，允许为空或任意

disp('Smoke test passed: Overlap_Coalition_Formation runs.');
