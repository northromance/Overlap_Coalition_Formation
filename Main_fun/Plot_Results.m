%% Plot_Results.m
% 专门用于加载已保存的实验结果并进行可视化
% 将数据生成和画图分离，避免每次画图都重新运行算法
%
% 使用方法：
%   1. 修改 result_file 变量指向你要分析的结果文件
%   2. 配置 plot_config 选择要画的图
%   3. 运行此脚本
%
% 作者：根据Compare_Algorithms.m改编
% 日期：2026-02-03

clear; clc; close all;

%% ==================== 配置区 ====================

% 1. 选择要加载的结果文件
% 选项 A: 自动加载最新文件（推荐）
auto_load_latest = false;

% 选项 B: 手动指定文件（当 auto_load_latest = false 时使用）
result_file = '../results/comparison_results_seed2456_20260203_164611.mat';

% 2. 画图配置
plot_config = struct();
plot_config.comparison = true;      % 算法对比图（多子图）
plot_config.allocation = true;      % SA算法资源分配图
plot_config.animation = false;      % 执行动画（耗时）
plot_config.environment = false;    % 环境图
plot_config.print_stats = true;     % 打印统计信息

% 3. 图形保存配置
save_figures = false;               % 是否保存图片
figure_format = 'png';              % 图片格式：'png', 'pdf', 'eps', 'fig'
figure_dpi = 300;                   % 分辨率

%% ==================== 加载数据 ====================

% 如果选择自动加载最新文件
if auto_load_latest
    % 优先从当前目录的 results 文件夹查找，如果不存在则查找上级目录
    if exist('results', 'dir')
        results_dir = 'results';
    else
        results_dir = '../results';
    end
    mat_files = dir(fullfile(results_dir, 'comparison_*.mat'));

    if isempty(mat_files)
        error('未找到任何结果文件，请先运行 Compare_Algorithms.m 生成数据');
    end

    % 按修改时间排序，获取最新文件
    [~, idx] = sort([mat_files.datenum], 'descend');
    result_file = fullfile(results_dir, mat_files(idx(1)).name);

    fprintf('自动加载最新结果文件: %s\n', mat_files(idx(1)).name);
    fprintf('  文件时间: %s\n', mat_files(idx(1)).date);
else
    fprintf('正在加载指定结果文件: %s\n', result_file);
end

if ~exist(result_file, 'file')
    error('结果文件不存在: %s\n请检查文件路径是否正确', result_file);
end

% 加载所有变量
load(result_file);

fprintf('✓ 数据加载成功\n');
fprintf('  - 场景: %d个智能体, %d个任务\n', length(agents), length(tasks));
fprintf('  - 算法数量: %d\n', length(fieldnames(results)));
if isfield(scenario_info, 'SEED')
    fprintf('  - 随机种子: %d\n', scenario_info.SEED);
end

%% ==================== 打印统计信息 ====================

if plot_config.print_stats
    fprintf('\n========== 算法对比统计 ==========\n');

    alg_names = fieldnames(comparison_stats);
    for i = 1:length(alg_names)
        alg_name = alg_names{i};
        stats = comparison_stats.(alg_name);

        fprintf('\n[%s]\n', stats.name);

        if isfield(stats, 'total_utility')
            fprintf('  总效用: %.4f\n', stats.total_utility);
        end

        if isfield(stats, 'total_cost')
            fprintf('  总成本: %.4f\n', stats.total_cost);
        end

        if isfield(stats, 'num_coalitions')
            fprintf('  联盟数量: %d\n', stats.num_coalitions);
        end

        if isfield(stats, 'computation_time')
            fprintf('  运行时间: %.4f 秒\n', stats.computation_time);
        end

        if isfield(stats, 'task_completion_rate')
            fprintf('  任务完成率: %.2f%%\n', stats.task_completion_rate * 100);
        end
    end

    fprintf('\n================================\n\n');
end

%% ==================== 绘制图形 ====================

% 1. 算法对比图
if plot_config.comparison
    fprintf('正在绘制算法对比图...\n');

    PlotClass.plot_algorithm_comparison(results, comparison_stats, ...
        length(fieldnames(results)), tasks, Value_Params, WORLD);

    if save_figures
        saveas(gcf, sprintf('results/comparison_%s', scenario_info.timestamp), figure_format);
    end

    fprintf('✓ 算法对比图完成\n');
end

% 2. SA算法资源分配图
if plot_config.allocation
    fprintf('正在绘制资源分配图...\n');

    % 查找SA_Value算法的结果
    alg_names = fieldnames(results);
    sa_found = false;

    for i = 1:length(alg_names)
        alg_name = alg_names{i};
        if strcmp(results.(alg_name).name, 'SA_Value')
            sa_found = true;

            % 打印智能体能力
            PlotClass.print_agent_capabilities(agents);

            % 绘制分配图
            PlotClass.plot_SA_allocation(results.(alg_name).Value_data, ...
                tasks, Value_Params);

            if save_figures
                saveas(gcf, sprintf('results/allocation_%s', scenario_info.timestamp), figure_format);
            end

            break;
        end
    end

    if sa_found
        fprintf('✓ 资源分配图完成\n');
    else
        fprintf('⚠ 未找到SA_Value算法结果，跳过资源分配图\n');
    end
end

% 3. 执行动画
if plot_config.animation
    fprintf('正在生成执行动画...\n');

    % 查找SA_Value算法的结果
    alg_names = fieldnames(results);
    sa_found = false;

    for i = 1:length(alg_names)
        alg_name = alg_names{i};
        if strcmp(results.(alg_name).name, 'SA_Value')
            sa_found = true;

            PlotClass.plot_execution_animation(results.(alg_name).Value_data, ...
                agents, tasks, Value_Params, WORLD);

            if save_figures
                % 动画通常保存为gif或视频
                fprintf('  提示: 动画保存功能需要在plot_execution_animation中实现\n');
            end

            break;
        end
    end

    if sa_found
        fprintf('✓ 执行动画完成\n');
    else
        fprintf('⚠ 未找到SA_Value算法结果，跳过执行动画\n');
    end
end

% 4. 环境图
if plot_config.environment
    fprintf('正在绘制环境图...\n');

    PlotClass.plot_env(agents, tasks, WORLD);

    if save_figures
        saveas(gcf, sprintf('results/environment_%s', scenario_info.timestamp), figure_format);
    end

    fprintf('✓ 环境图完成\n');
end

%% ==================== 完成 ====================

fprintf('\n所有图形绘制完成！\n');

if save_figures
    fprintf('图片已保存到 results/ 目录\n');
end

fprintf('\n提示：\n');
fprintf('  - 修改 result_file 变量可以加载不同的结果文件\n');
fprintf('  - 修改 plot_config 可以选择要绘制的图形\n');
fprintf('  - 设置 save_figures=true 可以自动保存图片\n');
