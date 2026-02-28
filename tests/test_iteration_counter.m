%% test_iteration_counter.m
% 测试迭代次数统计功能
% 验证所有算法的 history_data.k_iter_per_round 字段是否正确

clear; clc; close all;

fprintf('========================================\n');
fprintf('  迭代次数统计功能测试\n');
fprintf('========================================\n\n');

%% 设置路径
script_dir = fileparts(mfilename('fullpath'));
project_root = fileparts(script_dir);
addpath(genpath(project_root));

%% 加载最新结果文件
results_dir = fullfile(project_root, 'results');
if ~exist(results_dir, 'dir')
    error('结果文件夹不存在，请先运行 Compare_Algorithms.m 生成数据');
end

mat_files = dir(fullfile(results_dir, 'comparison_*.mat'));
if isempty(mat_files)
    error('未找到结果文件，请先运行 Compare_Algorithms.m 生成数据');
end

% 按修改时间排序，获取最新文件
[~, idx] = sort([mat_files.datenum], 'descend');
result_file = fullfile(mat_files(idx(1)).folder, mat_files(idx(1)).name);

fprintf('加载结果文件: %s\n\n', mat_files(idx(1)).name);
load(result_file);

%% 测试所有算法的迭代次数记录
alg_names = fieldnames(results);
test_passed = true;

fprintf('========================================\n');
fprintf('  测试结果\n');
fprintf('========================================\n\n');

for i = 1:length(alg_names)
    alg_field = alg_names{i};
    alg_result = results.(alg_field);

    fprintf('[%s]\n', alg_result.name);

    % 检查是否有 error 字段
    if isfield(alg_result, 'error')
        fprintf('  ⚠ 算法执行有错误，跳过\n\n');
        continue;
    end

    % 检查是否有 history_data 字段
    if ~isfield(alg_result, 'history_data') || isempty(alg_result.history_data)
        fprintf('  ❌ 缺少 history_data 字段\n\n');
        test_passed = false;
        continue;
    end

    hist_data = alg_result.history_data;

    % 检查是否有 k_iter_per_round 字段
    if ~isfield(hist_data, 'k_iter_per_round') || isempty(hist_data.k_iter_per_round)
        fprintf('  ❌ 缺少 k_iter_per_round 字段\n\n');
        test_passed = false;
        continue;
    end

    % 提取并验证迭代次数数据
    num_rounds = length(hist_data.k_iter_per_round);
    k_iters = zeros(1, num_rounds);

    for r = 1:num_rounds
        k_iters(r) = hist_data.k_iter_per_round{r};
    end

    % 计算统计信息
    mean_k_iter = mean(k_iters);
    min_k_iter = min(k_iters);
    max_k_iter = max(k_iters);

    fprintf('  ✓ k_iter_per_round 字段存在\n');
    fprintf('  - 轮数: %d\n', num_rounds);
    fprintf('  - 平均迭代次数: %.2f\n', mean_k_iter);
    fprintf('  - 最小迭代次数: %d\n', min_k_iter);
    fprintf('  - 最大迭代次数: %d\n', max_k_iter);
    fprintf('  - 每轮迭代次数: [%s]\n\n', num2str(k_iters));
end

%% 测试总结
fprintf('========================================\n');
fprintf('  测试总结\n');
fprintf('========================================\n\n');

if test_passed
    fprintf('✅ 所有测试通过！迭代次数统计功能正常工作。\n');
else
    fprintf('❌ 部分测试失败，请检查算法实现。\n');
end

fprintf('\n提示: 运行 Plot_Results.m 并设置 plot_config.iterations = true 来查看迭代次数可视化。\n');
