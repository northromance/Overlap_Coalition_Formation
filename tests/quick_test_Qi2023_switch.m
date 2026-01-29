% quick_test_Qi2023_switch.m
% 快速验证 Qi2023 信念更新开关功能
% 版本: Qi2023_v1.1

clear; clc;
fprintf('快速测试 Qi2023 信念更新开关...\n\n');

%% 添加必要的路径
addpath(fullfile('..', 'Main_fun'));
addpath(fullfile('..', 'SA'));
addpath(fullfile('..', 'comalg', 'Com_Qi2023'));
addpath(fullfile('..', 'comalg', 'Com_Huo2025'));

%% 设置简单测试参数
Value_Params = struct();
Value_Params.N = 3;              % 3个智能体
Value_Params.M = 2;              % 2个任务
Value_Params.K = 2;              % 2种资源
Value_Params.seed = 123;
Value_Params.obs_times = 10;
Value_Params.num_rounds = 3;     % 仅3轮快速测试
Value_Params.task_type = 2;

rng(Value_Params.seed);

% 生成智能体数据结构（按照 test_Qi2023.m 的格式）
N = Value_Params.N;
M = Value_Params.M;
K = Value_Params.K;

for i = 1:N
    agents(i).id = i;
    agents(i).x = randi([0, 100]);
    agents(i).y = randi([0, 100]);
    agents(i).vel = 2;
    agents(i).detprob = 0.95;
    agents(i).resources = randi([1, 4], K, 1);
    agents(i).Emax = 300;
    agents(i).fuel = 1;
    agents(i).wait_fuel = 0.5;
    agents(i).beta = 1;
end

% 生成任务数据结构
task_values = [800, 1000];
for j = 1:M
    tasks(j).id = j;
    tasks(j).priority = j;
    tasks(j).x = randi([0, 100]);
    tasks(j).y = randi([0, 100]);
    tasks(j).type = randi([1, 2]);
    tasks(j).value = task_values(tasks(j).type);
    tasks(j).resource_demand = randi([2, 6], 1, K);
    tasks(j).duration = 50;
    tasks(j).duration_by_resource = ones(1, K) * 50;
    tasks(j).WORLD.value = task_values;
end

%% 测试1: 启用信念更新
fprintf('=== 测试1: 启用信念更新 ===\n');
AddPara1 = struct();
AddPara1.enable_belief_update = true;
AddPara1.control = 1;
AddPara1.resource_confidence = 0.95;

try
    [Value_data1, history_data1] = Qi2023_main(agents, tasks, AddPara1, Value_Params);
    fprintf('✓ 测试1通过 - 最终效用: %.2f\n\n', history_data1.rounds(end).coalition_utility);
catch ME
    fprintf('✗ 测试1失败: %s\n\n', ME.message);
    rethrow(ME);
end

%% 测试2: 禁用信念更新
fprintf('=== 测试2: 禁用信念更新 ===\n');
AddPara2 = struct();
AddPara2.enable_belief_update = false;
AddPara2.control = 1;
AddPara2.resource_confidence = 0.95;

rng(Value_Params.seed);  % 重置随机种子

try
    [Value_data2, history_data2] = Qi2023_main(agents, tasks, AddPara2, Value_Params);
    fprintf('✓ 测试2通过 - 最终效用: %.2f\n\n', history_data2.rounds(end).coalition_utility);
catch ME
    fprintf('✗ 测试2失败: %s\n\n', ME.message);
    rethrow(ME);
end

%% 测试3: 未设置开关（测试默认行为）
fprintf('=== 测试3: 未设置开关（默认行为） ===\n');
AddPara3 = struct();
AddPara3.control = 1;
AddPara3.resource_confidence = 0.95;
% 注意：不设置 enable_belief_update

rng(Value_Params.seed);

try
    [Value_data3, history_data3] = Qi2023_main(agents, tasks, AddPara3, Value_Params);
    fprintf('✓ 测试3通过 - 最终效用: %.2f\n\n', history_data3.rounds(end).coalition_utility);
catch ME
    fprintf('✗ 测试3失败: %s\n\n', ME.message);
    rethrow(ME);
end

%% 总结
fprintf('========================================\n');
fprintf('所有测试通过！\n');
fprintf('========================================\n');
fprintf('测试1 (启用): 效用 = %.2f\n', history_data1.rounds(end).coalition_utility);
fprintf('测试2 (禁用): 效用 = %.2f\n', history_data2.rounds(end).coalition_utility);
fprintf('测试3 (默认): 效用 = %.2f\n', history_data3.rounds(end).coalition_utility);
fprintf('\n信念更新开关功能验证成功！\n');
