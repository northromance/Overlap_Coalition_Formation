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

% Resolve paths from this script's location (independent of MATLAB current folder)
% Plot_Results.m 位于项目根目录，script_dir 即为项目根目录
script_dir = fileparts(mfilename('fullpath'));

%% ==================== 配置区 ====================

% 1. 选择要加载的结果文件
% 选项 A: 自动加载最新文件（推荐）
auto_load_latest = true;

% 选项 B: 手动指定文件（当 auto_load_latest = false 时使用）
result_file = fullfile(script_dir, 'results', 'comparison_results_seed2456_20260203_164611.mat');

% 2. 画图配置
plot_config = struct();
plot_config.comparison = true;      % 算法对比图（2行3列柱状图）
plot_config.radar     = true;       % 雷达图（需至少2个算法）
plot_config.history   = true;       % 历史演化曲线（效用/价值/完成率）
plot_config.belief    = true;       % 任务期望价值演化图
plot_config.allocation = true;      % 算法资源分配图
plot_config.animation = false;      % 执行动画（耗时）
plot_config.environment = false;    % 环境图
plot_config.print_stats = true;     % 打印统计信息
plot_config.iterations = true;      % 迭代次数图

% 3. 图形保存配置
save_figures = false;               % 是否保存图片
figure_format = 'png';              % 图片格式：'png', 'pdf', 'eps', 'fig'
figure_dpi = 300;                   % 分辨率

%% ==================== 加载数据 ====================

% 如果选择自动加载最新文件
if auto_load_latest
    % 优先从当前目录的 results 文件夹查找，如果不存在则查找上级目录
    results_dirs = {
        fullfile(script_dir, 'results')
    };
    mat_files = [];
    for d = 1:length(results_dirs)
        if exist(results_dirs{d}, 'dir')
            mat_files = [mat_files; dir(fullfile(results_dirs{d}, 'comparison_*.mat'))]; %#ok<AGROW>
        end
    end

    if isempty(mat_files)
        error('未找到任何结果文件，请先运行 Compare_Algorithms.m 生成数据');
    end

    % 按修改时间排序，获取最新文件
    [~, idx] = sort([mat_files.datenum], 'descend');
    result_file = fullfile(mat_files(idx(1)).folder, mat_files(idx(1)).name);

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

        if isfield(stats, 'avg_task_completion')
            fprintf('  平均任务完成率: %.2f%%\n', stats.avg_task_completion * 100);
        end
    end

    fprintf('\n================================\n\n');
end

%% ==================== 绘制图形 ====================

% 1. 算法对比图
if plot_config.comparison
    fprintf('正在绘制算法对比图...\n');

    PlotClass.plot_algorithm_comparison(results, comparison_stats, ...
        length(fieldnames(results)), tasks, Value_Params, WORLD, plot_config);

    if save_figures
        saveas(gcf, sprintf('results/comparison_%s', scenario_info.timestamp), figure_format);
    end

    fprintf('✓ 算法对比图完成\n');
end

% 2. 各算法资源分配图
if plot_config.allocation
    fprintf('正在绘制资源分配图...\n');

    alg_names = fieldnames(results);
    plotted_count = 0;

    % 打印智能体能力（一次即可）
    PlotClass.print_agent_capabilities(agents);

    for i = 1:length(alg_names)
        alg_field = alg_names{i};
        alg_result = results.(alg_field);

        if isfield(alg_result, 'error')
            fprintf('  - 跳过 %s: 算法执行有错误\n', alg_result.name);
            continue;
        end

        if ~isfield(alg_result, 'Value_data') || isempty(alg_result.Value_data)
            if isfield(alg_result, 'name')
                fprintf('  - 跳过 %s: 缺少 Value_data\n', alg_result.name);
            end
            continue;
        end

        current_value_data = alg_result.Value_data;
        can_plot = false;

        % 兼容主流算法（SA/Huo/Qi/Shi）：使用 SC
        if isstruct(current_value_data) && isfield(current_value_data, 'SC')
            can_plot = true;
        % 兼容基线格式：agentresources (N x M x K) -> SC{m}(N x K)
        elseif isstruct(current_value_data) && isfield(current_value_data, 'agentresources')
            agent_res = current_value_data(1).agentresources;
            if ndims(agent_res) == 3
                [n_agents, n_tasks, n_res] = size(agent_res);
                SC = cell(n_tasks, 1);
                for t = 1:n_tasks
                    SC{t} = reshape(agent_res(:, t, :), [n_agents, n_res]);
                end
                current_value_data = struct('SC', {SC});
                can_plot = true;
            end
        end

        if ~can_plot
            fprintf('  - 跳过 %s: 不含可视化所需分配字段(SC/agentresources)\n', alg_result.name);
            continue;
        end

        fprintf('  - 绘制 %s 资源分配图...\n', alg_result.name);
        PlotClass.plot_SA_allocation(current_value_data, tasks, Value_Params, alg_result.name);

        if save_figures
            safe_alg_name = regexprep(alg_result.name, '[^a-zA-Z0-9_-]', '_');
            saveas(gcf, sprintf('results/allocation_%s_%s', safe_alg_name, scenario_info.timestamp), figure_format);
        end

        plotted_count = plotted_count + 1;
    end

    if plotted_count > 0
        fprintf('✓ 资源分配图完成 (共 %d 个算法)\n', plotted_count);
    else
        fprintf('⚠ 未找到可绘制资源分配图的算法结果\n');
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

% 5. 迭代次数图
if plot_config.iterations
    fprintf('正在绘制迭代次数图...\n');

    % 提取迭代次数数据
    alg_names = fieldnames(results);
    iteration_data = struct();

    for i = 1:length(alg_names)
        alg_field = alg_names{i};
        alg_result = results.(alg_field);

        if isfield(alg_result, 'history_data') && ~isempty(alg_result.history_data)
            hist_data = alg_result.history_data;

            % 检查是否有 k_iter_per_round 字段
            if isfield(hist_data, 'k_iter_per_round') && ~isempty(hist_data.k_iter_per_round)
                % 提取所有轮次的迭代次数
                k_iters = zeros(1, length(hist_data.k_iter_per_round));
                for r = 1:length(hist_data.k_iter_per_round)
                    k_iters(r) = hist_data.k_iter_per_round{r};
                end

                iteration_data.(alg_field).name = alg_result.name;
                iteration_data.(alg_field).k_iters = k_iters;
                iteration_data.(alg_field).mean_k_iter = mean(k_iters);
                iteration_data.(alg_field).num_rounds = length(k_iters);
            end
        end
    end

    % 如果没有数据，跳过绘图
    if isempty(fieldnames(iteration_data))
        fprintf('⚠ 未找到迭代次数数据，跳过迭代次数图\n');
    else
        % 绘制柱状图（平均迭代次数）
        figure('Name', 'Average Iterations per Algorithm', 'NumberTitle', 'off');

        alg_fields = fieldnames(iteration_data);
        mean_values = zeros(1, length(alg_fields));
        alg_labels = cell(1, length(alg_fields));

        for i = 1:length(alg_fields)
            mean_values(i) = iteration_data.(alg_fields{i}).mean_k_iter;
            alg_labels{i} = iteration_data.(alg_fields{i}).name;
        end

        bar(mean_values);
        set(gca, 'XTickLabel', alg_labels, 'XTickLabelRotation', 45);
        ylabel('平均迭代次数');
        title('各算法平均迭代次数对比');
        grid on;

        if save_figures
            saveas(gcf, sprintf('results/iterations_avg_%s', scenario_info.timestamp), figure_format);
        end

        % 绘制折线图（每轮迭代次数变化）
        figure('Name', 'Iterations per Round', 'NumberTitle', 'off');

        hold on;
        colors = lines(length(alg_fields));

        for i = 1:length(alg_fields)
            k_iters = iteration_data.(alg_fields{i}).k_iters;
            plot(1:length(k_iters), k_iters, '-o', ...
                'LineWidth', 2, ...
                'MarkerSize', 6, ...
                'Color', colors(i, :), ...
                'DisplayName', iteration_data.(alg_fields{i}).name);
        end

        hold off;
        xlabel('轮次 (Round)');
        ylabel('迭代次数');
        title('各算法迭代次数随轮次的变化');
        legend('Location', 'best');
        grid on;

        if save_figures
            saveas(gcf, sprintf('results/iterations_per_round_%s', scenario_info.timestamp), figure_format);
        end

        fprintf('✓ 迭代次数图完成\n');
    end
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
