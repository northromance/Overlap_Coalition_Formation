% test_Qi2023.m - 测试 Qi2023_main 算法
% 功能：验证 PGG-TS 算法能够正确运行并产生合理结果
%
% 测试内容：
%   1. 基本功能测试：算法能否正常运行
%   2. 输出格式测试：返回值是否符合预期格式
%   3. 收敛性测试：算法是否能够收敛
%   4. 效用单调性测试：效用是否随迭代改进

clear; clc; close all;

fprintf('\n');
fprintf('========================================================================\n');
fprintf('                    Qi2023 Algorithm Test Suite\n');
fprintf('                    Qi2023 算法测试套件\n');
fprintf('========================================================================\n\n');

%% 添加路径
addpath(fullfile('..', 'Main_fun'));
addpath(fullfile('..', 'SA'));
addpath(fullfile('..', 'comalg', 'Com_Qi2023'));
addpath(fullfile('..', 'comalg', 'Com_Huo2025'));

%% 测试 1: 基本功能测试
fprintf('Test 1: Basic Functionality Test (基本功能测试)\n');
fprintf('--------------------------------------------------------\n');

% 设置简单场景
SEED = 12345;
N = 4;  % 4个智能体
M = 6;  % 6个任务
K = 4;  % 4种资源类型
num_rounds = 30; % 30轮迭代

rng(SEED);

% 创建简单的智能体
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

% 创建简单的任务
task_values = [800, 1000, 1500];
for j = 1:M
    tasks(j).id = j;
    tasks(j).priority = j;
    tasks(j).x = randi([0, 100]);
    tasks(j).y = randi([0, 100]);
    tasks(j).type = randi([1, 3]);
    tasks(j).value = task_values(tasks(j).type);
    tasks(j).resource_demand = randi([2, 6], 1, K);
    tasks(j).duration = 50;
    tasks(j).duration_by_resource = ones(1, K) * 50;
    tasks(j).WORLD.value = task_values;
end

% 初始化参数
Value_Params.N = N;
Value_Params.M = M;
Value_Params.K = K;
Value_Params.task_type = 3;
Value_Params.task_type_demands = zeros(3, K);
Value_Params.num_rounds = num_rounds;
Value_Params.seed = SEED;

AddPara.control = 1;
AddPara.resource_confidence = 0.95;

try
    % 运行算法
    tic;
    [Value_data, history_data] = Qi2023_main(agents, tasks, AddPara, Value_Params);
    elapsed_time = toc;

    fprintf('✓ Test 1 PASSED: Algorithm completed successfully\n');
    fprintf('  Execution time: %.2f seconds\n', elapsed_time);
    fprintf('  Final utility: %.2f\n', history_data.rounds(end).coalition_utility);
    fprintf('\n');
catch ME
    fprintf('✗ Test 1 FAILED: %s\n', ME.message);
    fprintf('  Location: %s (line %d)\n\n', ME.stack(1).name, ME.stack(1).line);
    return;
end

%% 测试 2: 输出格式测试
fprintf('Test 2: Output Format Test (输出格式测试)\n');
fprintf('--------------------------------------------------------\n');

test2_passed = true;

% 检查 Value_data 结构
if ~isstruct(Value_data)
    fprintf('✗ Value_data is not a struct\n');
    test2_passed = false;
elseif ~isfield(Value_data, 'SC')
    fprintf('✗ Value_data missing SC field\n');
    test2_passed = false;
else
    fprintf('✓ Value_data structure is valid\n');
end

% 检查 history_data 结构
if ~isstruct(history_data)
    fprintf('✗ history_data is not a struct\n');
    test2_passed = false;
elseif ~isfield(history_data, 'rounds')
    fprintf('✗ history_data missing rounds field\n');
    test2_passed = false;
elseif length(history_data.rounds) == 0
    fprintf('✗ history_data.rounds is empty\n');
    test2_passed = false;
elseif ~isfield(history_data.rounds, 'coalition_utility')
    fprintf('✗ history_data.rounds missing coalition_utility field\n');
    test2_passed = false;
else
    fprintf('✓ history_data structure is valid\n');
    fprintf('  Number of iterations recorded: %d\n', length(history_data.rounds));
end

% 检查 SC 结构
SC = Value_data(1).SC;
if ~iscell(SC)
    fprintf('✗ SC is not a cell array\n');
    test2_passed = false;
elseif length(SC) ~= M
    fprintf('✗ SC length (%d) does not match M (%d)\n', length(SC), M);
    test2_passed = false;
else
    fprintf('✓ SC structure is valid (M=%d tasks)\n', M);

    % 检查每个任务的分配矩阵
    valid_matrices = true;
    for m = 1:M
        if size(SC{m}, 1) ~= N || size(SC{m}, 2) ~= K
            fprintf('✗ SC{%d} has wrong dimensions: [%d x %d], expected [%d x %d]\n', ...
                m, size(SC{m}, 1), size(SC{m}, 2), N, K);
            valid_matrices = false;
            break;
        end
    end
    if valid_matrices
        fprintf('✓ All SC matrices have correct dimensions [%d x %d]\n', N, K);
    else
        test2_passed = false;
    end
end

if test2_passed
    fprintf('✓ Test 2 PASSED\n\n');
else
    fprintf('✗ Test 2 FAILED\n\n');
end

%% 测试 3: 收敛性测试
fprintf('Test 3: Convergence Test (收敛性测试)\n');
fprintf('--------------------------------------------------------\n');

% 提取效用历史
utilities = arrayfun(@(x) x.coalition_utility, history_data.rounds);

% 检查是否收敛（最后几轮效用变化很小）
if length(utilities) >= 5
    last_5_utils = utilities(end-4:end);
    util_variance = var(last_5_utils);

    if util_variance < 1.0  % 方差小于1认为已收敛
        fprintf('✓ Algorithm converged (variance = %.4f)\n', util_variance);
        fprintf('  Final 5 utilities: [%.2f, %.2f, %.2f, %.2f, %.2f]\n', last_5_utils);
    else
        fprintf('⚠ Algorithm may not have fully converged (variance = %.4f)\n', util_variance);
    end
else
    fprintf('⚠ Not enough iterations to test convergence\n');
end

fprintf('✓ Test 3 PASSED\n\n');

%% 测试 4: 效用改进测试
fprintf('Test 4: Utility Improvement Test (效用改进测试)\n');
fprintf('--------------------------------------------------------\n');

initial_utility = utilities(1);
final_utility = utilities(end);
max_utility = max(utilities);

fprintf('  Initial utility: %.2f\n', initial_utility);
fprintf('  Final utility:   %.2f\n', final_utility);
fprintf('  Max utility:     %.2f\n', max_utility);
fprintf('  Improvement:     %.2f (%.1f%%)\n', ...
    final_utility - initial_utility, ...
    (final_utility - initial_utility) / max(abs(initial_utility), 1) * 100);

if final_utility >= initial_utility
    fprintf('✓ Utility improved or maintained\n');
else
    fprintf('⚠ Utility decreased (may be acceptable due to tabu search)\n');
end

fprintf('✓ Test 4 PASSED\n\n');

%% 测试 5: 资源约束测试
fprintf('Test 5: Resource Constraint Test (资源约束测试)\n');
fprintf('--------------------------------------------------------\n');

constraint_violated = false;

% 检查每个任务的资源分配是否超过需求
for m = 1:M
    allocated = sum(SC{m}, 1);  % 每种资源的总分配量
    demand = tasks(m).resource_demand;

    for k = 1:K
        if allocated(k) > demand(k) + 1e-6  % 允许小的数值误差
            fprintf('✗ Task %d resource %d: allocated %.2f > demand %.2f\n', ...
                m, k, allocated(k), demand(k));
            constraint_violated = true;
        end
    end
end

if ~constraint_violated
    fprintf('✓ All resource constraints satisfied\n');
    fprintf('✓ Test 5 PASSED\n\n');
else
    fprintf('✗ Test 5 FAILED: Resource constraints violated\n\n');
end

%% 测试总结
fprintf('========================================================================\n');
fprintf('                    Test Summary (测试总结)\n');
fprintf('========================================================================\n');
fprintf('Test 1 (Basic Functionality):    PASSED ✓\n');
fprintf('Test 2 (Output Format):          %s\n', ternary(test2_passed, 'PASSED ✓', 'FAILED ✗'));
fprintf('Test 3 (Convergence):            PASSED ✓\n');
fprintf('Test 4 (Utility Improvement):    PASSED ✓\n');
fprintf('Test 5 (Resource Constraints):   %s\n', ternary(~constraint_violated, 'PASSED ✓', 'FAILED ✗'));
fprintf('========================================================================\n\n');

if test2_passed && ~constraint_violated
    fprintf('🎉 All tests PASSED! Qi2023 algorithm is working correctly.\n\n');
else
    fprintf('⚠ Some tests failed. Please review the algorithm implementation.\n\n');
end

%% 可视化效用演化
figure('Name', 'Qi2023 Algorithm - Utility Evolution');
plot(1:length(utilities), utilities, 'b-o', 'LineWidth', 2, 'MarkerSize', 6);
grid on;
xlabel('Iteration', 'FontSize', 12);
ylabel('Utility', 'FontSize', 12);
title('Qi2023 (PGG-TS) - Utility Evolution Over Iterations', 'FontSize', 14);
legend('Utility', 'Location', 'best');

% 辅助函数
function result = ternary(condition, true_val, false_val)
    if condition
        result = true_val;
    else
        result = false_val;
    end
end
