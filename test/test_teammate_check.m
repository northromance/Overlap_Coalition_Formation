% TEST_TEAMMATE_CHECK 测试队友检查功能
%
% 功能：验证 validate_feasibility 中的队友检查是否正常工作
%
% 测试场景：
%   1. 基础功能测试：队友检查能否正确识别不可行情况
%   2. 兼容性测试：不启用队友检查时是否正常工作
%   3. 性能测试：队友检查的性能开销

clear; clc;

fprintf('\n========================================\n');
fprintf('测试：队友检查功能\n');
fprintf('========================================\n\n');

% 添加路径
addpath(genpath('E:\Overlap_Coalition_Formation'));

%% 测试准备：创建测试数据
fprintf('创建测试数据...\n');

% 参数
N = 3;  % 3个智能体
M = 2;  % 2个任务
K = 2;  % 2种资源

Value_Params.N = N;
Value_Params.M = M;
Value_Params.K = K;

% 创建智能体
for i = 1:N
    agents(i).id = i;
    agents(i).resources = [10, 10];
    agents(i).Emax = 100;  % 较小的能量上限，便于测试
    agents(i).x = i*10;
    agents(i).y = i*10;
    agents(i).fuel = 1;
    agents(i).wait_fuel = 0.5;
    agents(i).beta = 1;
    agents(i).vel = 2;
end

% 创建任务
for j = 1:M
    tasks(j).id = j;
    tasks(j).x = j*20;
    tasks(j).y = j*20;
    tasks(j).priority = j;
end

% 创建Value_data
for i = 1:N
    Value_data(i).agentID = i;
    Value_data(i).resources = agents(i).resources;
end

fprintf('测试数据创建完成。\n\n');

%% 测试1：基础功能 - 不启用队友检查
fprintf('【测试1】不启用队友检查\n');
fprintf('----------------------------------------\n');

% 场景：Agent 1 已经接近能量上限，Agent 2 加入会导致 Agent 1 不可行
SC_test1 = cell(M, 1);
SC_test1{1} = zeros(N, K);
SC_test1{2} = zeros(N, K);

% Agent 1 参与 Task 1，已经接近能量上限
SC_test1{1}(1, :) = [8, 8];

% Agent 2 尝试加入 Task 1（不检查队友）
SC_test1{1}(2, :) = [5, 5];

try
    [feasible1, info1, cost1] = validate_feasibility(...
        Value_data(2), agents, tasks, Value_Params, 2, SC_test1, false);

    if feasible1
        fprintf('  Agent 2 加入 Task 1: 可行 ✓（未检查队友）\n');
    else
        fprintf('  Agent 2 加入 Task 1: 不可行 ✗ (原因: %s)\n', info1.reason);
    end
catch ME
    fprintf('  ❌ 测试失败: %s\n', ME.message);
end

%% 测试2：启用队友检查
fprintf('\n【测试2】启用队友检查\n');
fprintf('----------------------------------------\n');

% 相同场景，但启用队友检查
try
    [feasible2, info2, cost2] = validate_feasibility(...
        Value_data(2), agents, tasks, Value_Params, 2, SC_test1, true);

    if feasible2
        fprintf('  Agent 2 加入 Task 1: 可行 ✓\n');
    else
        fprintf('  Agent 2 加入 Task 1: 不可行 ✗\n');
        fprintf('  原因: %s\n', info2.reason);
        if isfield(info2, 'affected_agents')
            fprintf('  受影响的队友: [%s]\n', num2str(info2.affected_agents));
        end
    end
catch ME
    fprintf('  ❌ 测试失败: %s\n', ME.message);
end

%% 测试3：默认参数测试
fprintf('\n【测试3】默认参数（应该启用队友检查）\n');
fprintf('----------------------------------------\n');

try
    % 不传入 check_teammates 参数，应该默认为 true
    [feasible3, info3, cost3] = validate_feasibility(...
        Value_data(2), agents, tasks, Value_Params, 2, SC_test1);

    if feasible3
        fprintf('  默认参数: 可行 ✓\n');
    else
        fprintf('  默认参数: 不可行 ✗ (原因: %s)\n', info3.reason);
    end
catch ME
    fprintf('  ❌ 测试失败: %s\n', ME.message);
end

%% 测试4：性能测试
fprintf('\n【测试4】性能测试\n');
fprintf('----------------------------------------\n');

% 创建一个更复杂的场景
SC_perf = cell(M, 1);
for j = 1:M
    SC_perf{j} = zeros(N, K);
    SC_perf{j}(1, :) = [5, 5];
    SC_perf{j}(2, :) = [4, 4];
end

num_iterations = 100;

% 不检查队友
tic;
for i = 1:num_iterations
    try
        validate_feasibility(Value_data(3), agents, tasks, Value_Params, 3, SC_perf, false);
    catch
    end
end
time_without = toc;

% 检查队友
tic;
for i = 1:num_iterations
    try
        validate_feasibility(Value_data(3), agents, tasks, Value_Params, 3, SC_perf, true);
    catch
    end
end
time_with = toc;

fprintf('  不检查队友: %.4f 秒 (%d 次)\n', time_without, num_iterations);
fprintf('  检查队友:   %.4f 秒 (%d 次)\n', time_with, num_iterations);
fprintf('  性能开销:   %.1f%%\n', (time_with/time_without - 1) * 100);

%% 测试5：兼容性测试 - 与旧版本对比
fprintf('\n【测试5】兼容性测试\n');
fprintf('----------------------------------------\n');

% 测试各种调用方式
test_cases = {
    '6个参数（旧版本兼容）', 6;
    '7个参数，false', 7;
    '7个参数，true', 7;
};

for tc = 1:size(test_cases, 1)
    test_name = test_cases{tc, 1};
    num_params = test_cases{tc, 2};

    try
        if num_params == 6
            [f, ~, ~] = validate_feasibility(Value_data(1), agents, tasks, Value_Params, 1, SC_perf);
        elseif strcmp(test_name, '7个参数，false')
            [f, ~, ~] = validate_feasibility(Value_data(1), agents, tasks, Value_Params, 1, SC_perf, false);
        else
            [f, ~, ~] = validate_feasibility(Value_data(1), agents, tasks, Value_Params, 1, SC_perf, true);
        end
        fprintf('  ✅ %s: 正常\n', test_name);
    catch ME
        fprintf('  ❌ %s: 失败 (%s)\n', test_name, ME.message);
    end
end

%% 总结
fprintf('\n========================================\n');
fprintf('测试完成\n');
fprintf('========================================\n');
fprintf('\n提示：\n');
fprintf('  - 如果测试2显示"不可行"且原因是"teammates_would_become_infeasible"，\n');
fprintf('    说明队友检查功能正常工作。\n');
fprintf('  - 性能开销应该在 10-30%% 之间。\n');
fprintf('  - 所有兼容性测试都应该通过。\n\n');
