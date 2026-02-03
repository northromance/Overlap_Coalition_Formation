% test_sa_improvements.m - 快速测试 SA 改进算法
%
% 用途：在小规模场景下快速测试改进算法是否正常工作
% 使用方法：直接运行此脚本

clear; clc; close all;

fprintf('========================================\n');
fprintf('  SA 改进算法快速测试\n');
fprintf('========================================\n\n');

%% 1. 设置项目路径
project_root = fileparts(fileparts(mfilename('fullpath')));
addpath(fullfile(project_root, "Main_fun"));
addpath(fullfile(project_root, "SA"));
addpath(fullfile(project_root, "SA", "Improvements"));
addpath(fullfile(project_root, "utils"));

%% 2. 创建小规模测试场景
fprintf('[1/4] 创建测试场景...\n');

% 小规模参数（快速测试）
N = 5;  % 5 个智能体
M = 3;  % 3 个任务
K = 2;  % 2 种资源类型

% 初始化参数
Value_Params = struct();
Value_Params.N = N;
Value_Params.M = M;
Value_Params.K = K;
Value_Params.task_type = 3;
Value_Params.num_rounds = 2;  % 只运行 2 轮（快速测试）
Value_Params.K_len_SA = 3;
Value_Params.K_max_inner_SA = 20;  % 减少迭代次数
Value_Params.Temperature = 50;
Value_Params.alpha = 0.95;
Value_Params.Tmin = 1;
Value_Params.seed = 42;

% 附加参数
AddPara = struct();
AddPara.verbose = true;  % 显示详细信息
AddPara.plot_enabled = false;  % 不绘图（加速测试）

% 生成随机智能体和任务
rng(42);
agents = struct('id', {}, 'resources', {}, 'position', {});
for i = 1:N
    agents(i).id = i;
    agents(i).resources = randi([5, 15], 1, K);  % 随机资源
    agents(i).position = rand(1, 2) * 100;  % 随机位置
end

tasks = struct('id', {}, 'position', {}, 'true_demand', {}, 'value', {});
for j = 1:M
    tasks(j).id = j;
    tasks(j).position = rand(1, 2) * 100;
    tasks(j).true_demand = randi([10, 30], 1, K);
    tasks(j).value = randi([50, 150]);
    tasks(j).type = randi([1, Value_Params.task_type]);
end

fprintf('  ✓ 场景创建完成：%d 智能体，%d 任务，%d 资源类型\n\n', N, M, K);

%% 3. 测试所有改进算法
fprintf('[2/4] 测试改进算法...\n\n');

% 定义要测试的算法
test_algorithms = {
    struct('id', 1,  'name', 'SA_Value (原始)',      'func', @SA_Value_main);
    struct('id', 7,  'name', 'SA_TabuEnhanced',      'func', @SA_Value_TabuEnhanced_main);
    struct('id', 8,  'name', 'SA_AdaptiveAlpha',     'func', @SA_Value_AdaptiveAlpha_main);
    struct('id', 9,  'name', 'SA_ImprovedTemp',      'func', @SA_Value_ImprovedTemp_main);
    struct('id', 10, 'name', 'SA_MultiStart',        'func', @SA_Value_MultiStart_main);
    struct('id', 11, 'name', 'SA_HybridGreedy',      'func', @SA_Value_HybridGreedy_main);
    struct('id', 12, 'name', 'SA_EnhancedNeighbor',  'func', @SA_Value_EnhancedNeighbor_main);
};

results = struct('name', {}, 'success', {}, 'time', {}, 'utility', {}, 'error', {});

for i = 1:length(test_algorithms)
    alg = test_algorithms{i};
    fprintf('  测试 [%d/%d]: %s\n', i, length(test_algorithms), alg.name);

    try
        % 运行算法
        tic;
        [Value_data, history_data] = alg.func(agents, tasks, AddPara, Value_Params);
        elapsed_time = toc;

        % 计算最终效用
        if isfield(history_data, 'total_completed_value') && ~isempty(history_data.total_completed_value)
            final_utility = history_data.total_completed_value(end);
        else
            final_utility = NaN;
        end

        % 记录结果
        results(i).name = alg.name;
        results(i).success = true;
        results(i).time = elapsed_time;
        results(i).utility = final_utility;
        results(i).error = '';

        fprintf('    ✓ 成功 | 时间: %.2f 秒 | 效用: %.2f\n\n', elapsed_time, final_utility);

    catch ME
        % 记录错误
        results(i).name = alg.name;
        results(i).success = false;
        results(i).time = NaN;
        results(i).utility = NaN;
        results(i).error = ME.message;

        fprintf('    ✗ 失败 | 错误: %s\n\n', ME.message);
    end
end

%% 4. 汇总结果
fprintf('[3/4] 测试结果汇总\n');
fprintf('========================================\n');
fprintf('%-25s | %-8s | %-10s | %-10s\n', '算法名称', '状态', '时间(秒)', '效用');
fprintf('----------------------------------------\n');

for i = 1:length(results)
    if results(i).success
        status = '✓ 成功';
        time_str = sprintf('%.2f', results(i).time);
        utility_str = sprintf('%.2f', results(i).utility);
    else
        status = '✗ 失败';
        time_str = 'N/A';
        utility_str = 'N/A';
    end
    fprintf('%-25s | %-8s | %-10s | %-10s\n', results(i).name, status, time_str, utility_str);
end
fprintf('========================================\n\n');

%% 5. 给出建议
fprintf('[4/4] 下一步建议\n');
fprintf('========================================\n');

% 统计成功和失败的算法
num_success = sum([results.success]);
num_failed = length(results) - num_success;

if num_failed == 0
    fprintf('✓ 所有算法测试通过！\n\n');
    fprintf('建议：\n');
    fprintf('  1. 使用 Compare_Algorithms.m 进行完整对比\n');
    fprintf('  2. 参考 quick_compare_configs.m 选择对比配置\n');
    fprintf('  3. 在更大规模场景下测试性能差异\n');
else
    fprintf('⚠ 有 %d 个算法测试失败\n\n', num_failed);
    fprintf('失败的算法：\n');
    for i = 1:length(results)
        if ~results(i).success
            fprintf('  - %s\n', results(i).name);
            fprintf('    错误: %s\n', results(i).error);
        end
    end
    fprintf('\n建议：\n');
    fprintf('  1. 检查失败算法的实现代码\n');
    fprintf('  2. 确保所有依赖函数都已正确添加到路径\n');
    fprintf('  3. 查看详细错误信息进行调试\n');
end

fprintf('========================================\n');
fprintf('\n测试完成！\n');
