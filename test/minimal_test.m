% MINIMAL_TEST 最小化测试：验证一致性检查功能
% 直接使用已有的算法输出数据进行测试

clear; clc;

fprintf('\n========================================\n');
fprintf('最小化测试：一致性检查功能验证\n');
fprintf('========================================\n\n');

% 添加路径
addpath(genpath('E:\Overlap_Coalition_Formation'));

%% 创建模拟数据
fprintf('创建模拟测试数据...\n');

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
    agents(i).Emax = 1000;
    agents(i).position = [i*10, i*10];
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
    tasks(j).position = [j*20, j*20];
    tasks(j).x = j*20;
    tasks(j).y = j*20;
    tasks(j).priority = j;
end

%% 测试1：OCF模式（重叠联盟）
fprintf('\n【测试1】OCF模式 - 重叠联盟\n');
fprintf('----------------------------------------\n');

% 创建合法的OCF联盟结构
SC_ocf = cell(M, 1);
SC_ocf{1} = zeros(N, K);
SC_ocf{2} = zeros(N, K);

% Task 1: Agent 1, 2 参与
SC_ocf{1}(1, :) = [5, 5];
SC_ocf{1}(2, :) = [4, 4];

% Task 2: Agent 2, 3 参与（Agent 2重叠参与）
SC_ocf{2}(2, :) = [6, 6];
SC_ocf{2}(3, :) = [5, 5];

% 创建coalitionstru
coalitionstru_ocf = zeros(M, N);
coalitionstru_ocf(1, 1:2) = [1, 2];
coalitionstru_ocf(2, 1:2) = [2, 3];

% 创建Value_data
for i = 1:N
    Value_data_ocf(i).SC = SC_ocf;
    Value_data_ocf(i).coalitionstru = coalitionstru_ocf;
    Value_data_ocf(i).resources_matrix = zeros(M, K);
    for j = 1:M
        if i <= size(SC_ocf{j}, 1)
            Value_data_ocf(i).resources_matrix(j, :) = SC_ocf{j}(i, :);
        end
    end
end

% 执行OCF检查
[is_valid_ocf, error_log_ocf] = check_coalition_consistency(...
    Value_data_ocf, agents, tasks, Value_Params, 'OCF');

if is_valid_ocf
    fprintf('✅ OCF模式检查通过！\n');
else
    fprintf('❌ OCF模式检查失败！\n');
    for i = 1:length(error_log_ocf)
        fprintf('  - %s\n', error_log_ocf{i});
    end
end

%% 测试2：Non-OCF模式（非重叠联盟）
fprintf('\n【测试2】Non-OCF模式 - 非重叠联盟\n');
fprintf('----------------------------------------\n');

% 创建合法的Non-OCF联盟结构（每个智能体只参与一个任务）
SC_nonocf = cell(M, 1);
SC_nonocf{1} = zeros(N, K);
SC_nonocf{2} = zeros(N, K);

% Task 1: Agent 1 参与
SC_nonocf{1}(1, :) = [5, 5];

% Task 2: Agent 2, 3 参与
SC_nonocf{2}(2, :) = [6, 6];
SC_nonocf{2}(3, :) = [5, 5];

% 创建coalitionstru
coalitionstru_nonocf = zeros(M, N);
coalitionstru_nonocf(1, 1) = 1;
coalitionstru_nonocf(2, 1:2) = [2, 3];

% 创建Value_data
for i = 1:N
    Value_data_nonocf(i).SC = SC_nonocf;
    Value_data_nonocf(i).coalitionstru = coalitionstru_nonocf;
    Value_data_nonocf(i).resources_matrix = zeros(M, K);
    for j = 1:M
        if i <= size(SC_nonocf{j}, 1)
            Value_data_nonocf(i).resources_matrix(j, :) = SC_nonocf{j}(i, :);
        end
    end
end

% 执行Non-OCF检查
[is_valid_nonocf, error_log_nonocf] = check_coalition_consistency(...
    Value_data_nonocf, agents, tasks, Value_Params, 'Non-OCF');

if is_valid_nonocf
    fprintf('✅ Non-OCF模式检查通过！\n');
else
    fprintf('❌ Non-OCF模式检查失败！\n');
    for i = 1:length(error_log_nonocf)
        fprintf('  - %s\n', error_log_nonocf{i});
    end
end

%% 总结
fprintf('\n========================================\n');
fprintf('测试总结\n');
fprintf('========================================\n');
fprintf('OCF模式:     %s\n', iif(is_valid_ocf, '✅ 通过', '❌ 失败'));
fprintf('Non-OCF模式: %s\n', iif(is_valid_nonocf, '✅ 通过', '❌ 失败'));
fprintf('\n一致性检查功能验证完成！\n\n');

function result = iif(condition, true_val, false_val)
    if condition
        result = true_val;
    else
        result = false_val;
    end
end
