% QUICK_TEST_CONSISTENCY 快速测试一致性检查函数
%
% 功能：快速验证 check_coalition_consistency 函数的基本功能
%
% 使用方法：
%   在MATLAB命令窗口中运行：
%   cd E:\Overlap_Coalition_Formation\test
%   quick_test_consistency

clear; clc;

% 添加必要的路径
addpath('E:\Overlap_Coalition_Formation');

fprintf('\n========================================\n');
fprintf('快速测试：联盟一致性检查函数\n');
fprintf('========================================\n\n');

%% 创建简单的测试数据
fprintf('创建测试数据...\n');

% 参数设置
Value_Params.N = 3;  % 3个智能体
Value_Params.M = 2;  % 2个任务
Value_Params.K = 2;  % 2种资源

% 创建智能体
agents = struct('id', {}, 'resources', {}, 'Emax', {}, 'position', {});
for i = 1:Value_Params.N
    agents(i).id = i;
    agents(i).resources = [10, 10];
    agents(i).Emax = 1000;
    agents(i).position = [i*10, i*10];
end

% 创建任务
tasks = struct('id', {}, 'position', {}, 'priority', {});
for j = 1:Value_Params.M
    tasks(j).id = j;
    tasks(j).position = [j*20, j*20];
    tasks(j).priority = j;
end

% 创建合法的联盟结构
SC = cell(Value_Params.M, 1);
SC{1} = zeros(Value_Params.N, Value_Params.K);
SC{2} = zeros(Value_Params.N, Value_Params.K);

% Task 1: Agent 1, 2 参与
SC{1}(1, :) = [5, 5];
SC{1}(2, :) = [4, 4];

% Task 2: Agent 2, 3 参与
SC{2}(2, :) = [6, 6];
SC{2}(3, :) = [5, 5];

% 创建coalitionstru
coalitionstru = zeros(Value_Params.M, Value_Params.N);
coalitionstru(1, 1:2) = [1, 2];
coalitionstru(2, 1:2) = [2, 3];

% 创建Value_data
Value_data = struct('SC', {}, 'coalitionstru', {}, 'resources_matrix', {});
for i = 1:Value_Params.N
    Value_data(i).SC = SC;
    Value_data(i).coalitionstru = coalitionstru;

    % 创建个体资源矩阵
    Value_data(i).resources_matrix = zeros(Value_Params.M, Value_Params.K);
    for j = 1:Value_Params.M
        if i <= size(SC{j}, 1)
            Value_data(i).resources_matrix(j, :) = SC{j}(i, :);
        end
    end
end

fprintf('测试数据创建完成。\n\n');

%% 测试：正常情况
fprintf('【测试】正常情况 - 合法的OCF联盟结构\n');
fprintf('----------------------------------------\n');

try
    [is_valid, error_log] = check_coalition_consistency(...
        Value_data, agents, tasks, Value_Params, 'OCF');

    if is_valid
        fprintf('\n✅ 测试通过：检查函数正常工作！\n');
    else
        fprintf('\n❌ 测试失败：正常数据应该通过检查\n');
        fprintf('错误数量：%d\n', length(error_log));
    end
catch ME
    fprintf('\n❌ 测试失败：函数执行出错\n');
    fprintf('错误信息：%s\n', ME.message);
    fprintf('错误位置：%s\n', ME.stack(1).name);
end

fprintf('\n========================================\n');
fprintf('快速测试完成\n');
fprintf('========================================\n\n');

fprintf('提示：如果测试通过，说明检查函数基本功能正常。\n');
fprintf('      要运行完整测试，请执行：test_coalition_consistency\n\n');
