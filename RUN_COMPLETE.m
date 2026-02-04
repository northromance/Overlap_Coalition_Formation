%% ========================================
%% 内循环可视化 - 最终完整运行代码
%% ========================================
%
% 此脚本将：
% 1. 运行快速测试实验（3轮，SA_Value + Qi2023）
% 2. 自动可视化结果
% 3. 生成对比分析
%
% 使用方法：
%   直接运行此脚本即可
%
% 预计时间：30-60秒
%
%% ========================================

clear; clc; close all;

fprintf('\n');
fprintf('========================================\n');
fprintf('内循环可视化 - 完整运行\n');
fprintf('========================================\n\n');

%% 步骤1: 运行实验
fprintf('【步骤1】运行实验...\n');
fprintf('  算法: SA_Value, Qi2023\n');
fprintf('  轮次: 3轮\n');
fprintf('  预计时间: 30-60秒\n');
fprintf('========================================\n\n');

% 切换到Main_fun目录运行
cd('Main_fun');
Compare_Algorithms;
cd('..');

fprintf('\n========================================\n');
fprintf('✅ 实验完成\n\n');

%% 步骤2: 查找最新结果
fprintf('【步骤2】查找结果文件...\n');

result_files = dir('Main_fun/results/comparison_*.mat');
[~, idx] = max([result_files.datenum]);
result_file = fullfile(result_files(idx).folder, result_files(idx).name);

fprintf('✅ 找到: %s\n', result_files(idx).name);
fprintf('   大小: %.1f KB\n\n', result_files(idx).bytes/1024);

%% 步骤3: 创建figures目录
if ~exist('figures', 'dir')
    mkdir('figures');
end

%% 步骤4: 可视化SA_Value
fprintf('【步骤3】可视化SA_Value第1轮...\n');
fprintf('========================================\n\n');

Plot_InnerLoop_Evolution(result_file, 'SA_Value', 1);

fprintf('\n');

%% 步骤5: 可视化Qi2023
fprintf('【步骤4】可视化Qi2023第1轮...\n');
fprintf('========================================\n\n');

Plot_InnerLoop_Evolution(result_file, 'Qi2023', 1);

fprintf('\n');

%% 步骤6: 生成对比分析
fprintf('【步骤5】生成对比分析...\n');
fprintf('========================================\n\n');

data = load(result_file);

% 提取内循环数据
sa_inner = data.results.alg1.history_data.inner_loop{1};
qi_inner = data.results.alg2.history_data.inner_loop{1};

% 对比分析
fprintf('对比分析 (第1轮):\n');
fprintf('----------------------------------------\n\n');

fprintf('SA_Value:\n');
fprintf('  迭代次数: %d\n', length(sa_inner.iteration));
fprintf('  温度范围: %.2f → %.2f\n', sa_inner.temperature(1), sa_inner.temperature(end));
fprintf('  效用范围: %.2f → %.2f\n', min(sa_inner.current_utility), max(sa_inner.current_utility));
fprintf('  最优效用: %.2f\n', max(sa_inner.best_utility));

% 计算接受劣解
utility_delta_sa = diff(sa_inner.current_utility);
num_worse_sa = sum(utility_delta_sa < -1e-6);
num_better_sa = sum(utility_delta_sa > 1e-6);
fprintf('  接受优解: %d次 (%.1f%%)\n', num_better_sa, 100*num_better_sa/length(utility_delta_sa));
fprintf('  接受劣解: %d次 (%.1f%%)\n', num_worse_sa, 100*num_worse_sa/length(utility_delta_sa));

fprintf('\n');

fprintf('Qi2023:\n');
fprintf('  迭代次数: %d\n', length(qi_inner.iteration));
fprintf('  Gamma范围: %.2f → %.2f\n', qi_inner.temperature(1), qi_inner.temperature(end));
fprintf('  效用范围: %.2f → %.2f\n', min(qi_inner.current_utility), max(qi_inner.current_utility));
fprintf('  最优效用: %.2f\n', max(qi_inner.best_utility));

% 计算效用变化
utility_delta_qi = diff(qi_inner.current_utility);
num_worse_qi = sum(utility_delta_qi < -1e-6);
num_better_qi = sum(utility_delta_qi > 1e-6);
fprintf('  效用提升: %d次 (%.1f%%)\n', num_better_qi, 100*num_better_qi/length(utility_delta_qi));
fprintf('  效用下降: %d次 (%.1f%%)\n', num_worse_qi, 100*num_worse_qi/length(utility_delta_qi));

fprintf('\n----------------------------------------\n\n');

%% 完成
fprintf('========================================\n');
fprintf('✅ 全部完成！\n');
fprintf('========================================\n\n');

fprintf('生成的文件:\n');
fprintf('  结果: %s\n', result_file);
fprintf('  图形: figures/ 目录\n\n');

fprintf('后续操作:\n');
fprintf('  %% 查看其他轮次\n');
fprintf('  Plot_InnerLoop_Evolution(''%s'', ''SA_Value'', 2)\n', result_file);
fprintf('  Plot_InnerLoop_Evolution(''%s'', ''Qi2023'', 3)\n\n', result_file);

fprintf('  %% 运行完整实验（30轮，3个算法）\n');
fprintf('  %% 1. 打开 Main_fun/Compare_Algorithms.m\n');
fprintf('  %% 2. 修改:\n');
fprintf('  %%    algorithms_to_run_ids = [1, 4, 8];\n');
fprintf('  %%    num_rounds = 30;\n');
fprintf('  %% 3. 运行 Compare_Algorithms\n\n');

fprintf('========================================\n');
