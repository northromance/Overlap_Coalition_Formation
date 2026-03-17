function Plot_InnerLoop_Evolution(result_file, algorithm_name, round_number)
% PLOT_INNERLOOP_EVOLUTION 绘制SA/Qi算法内循环的演化过程
%
% 功能：
%   可视化指定算法在指定轮次的内循环迭代过程，包括：
%   - 温度/Gamma变化曲线
%   - 当前效用和最优效用的演化
%   - 联盟数量变化
%   - 迭代次数统计
%
% 使用方法1：直接运行（使用配置区参数）
%   Plot_InnerLoop_Evolution
%
% 使用方法2：指定参数调用
%   Plot_InnerLoop_Evolution(result_file, algorithm_name, round_number)
%
% 输入参数：
%   result_file    - 结果文件路径（MAT文件）
%   algorithm_name - 算法标识（支持名称/算法ID/结果索引）
%   round_number   - 轮次编号（1到num_rounds）
%
% 示例：
%   Plot_InnerLoop_Evolution  % 使用配置区参数
%   Plot_InnerLoop_Evolution('results/comparison_xxx.mat', 'OCF_SAtabu_global', 1)
%   Plot_InnerLoop_Evolution('results/comparison_xxx.mat', 'Qi2023', 5)
%   Plot_InnerLoop_Evolution('results/comparison_xxx.mat', 7, 5)
%   Plot_InnerLoop_Evolution('results/comparison_xxx.mat', 'alg2', 3)

%% ==================== 配置区 ====================
% 当不提供参数时，使用此配置区的设置

if nargin == 0
    % 1. 选择要加载的结果文件
    % 选项 A: 自动加载最新文件（推荐）
    auto_load_latest = true;

    % 选项 B: 手动指定文件（当 auto_load_latest = false 时使用）
    manual_result_file = 'results/comparison_N6_M10_Qi+OCFSAtabu_20260313_213738.mat';

    % 2. 选择算法
    % 可选值: 'OCF_SAtabu_global', 'Qi2023', 7, 3, 'alg1', 'alg2'
    algorithm_name = 'OCF_SAtabu_global';

    % 3. 选择轮次
    round_number = 40;

    % --- 自动加载逻辑 ---
    if auto_load_latest
        result_files = dir('results/comparison_*.mat');
        if isempty(result_files)
            error('未找到结果文件。请先运行 Compare_Algorithms.m');
        end

        % 按时间排序，选择最新的
        [~, idx] = max([result_files.datenum]);
        result_file = fullfile(result_files(idx).folder, result_files(idx).name);

        fprintf('【自动加载】使用最新结果文件:\n');
        fprintf('  %s\n', result_files(idx).name);
        fprintf('  修改时间: %s\n\n', datestr(result_files(idx).datenum));
    else
        result_file = manual_result_file;
        fprintf('【手动指定】使用结果文件:\n');
        fprintf('  %s\n\n', result_file);
    end

    fprintf('【配置参数】\n');
    fprintf('  算法: %s\n', algorithm_name);
    fprintf('  轮次: %d\n\n', round_number);
end

%% ==================== 参数检查 ====================
if nargin > 0 && nargin < 3
    error('需要0个参数（使用配置区）或3个参数（result_file, algorithm_name, round_number）');
end

%% 加载数据
fprintf('正在加载结果文件: %s\n', result_file);
data = load(result_file);

%% 查找指定算法（兼容新旧结果结构）
alg_list = {};

if isfield(data, 'enabled_algorithms') && ~isempty(data.enabled_algorithms)
    if iscell(data.enabled_algorithms)
        alg_list = data.enabled_algorithms;
    elseif isstruct(data.enabled_algorithms)
        alg_list = num2cell(data.enabled_algorithms);
    end
end

if isempty(alg_list)
    % 兼容少量旧结果：从 results.algX 反推可用算法列表
    result_fields = fieldnames(data.results);
    for i = 1:length(result_fields)
        entry = data.results.(result_fields{i});
        if isfield(entry, 'name')
            alg_list{end+1} = struct('name', entry.name); %#ok<AGROW>
        end
    end
end

if isempty(alg_list)
    error('结果文件中没有可识别的算法列表（enabled_algorithms/results.name）。');
end

query_str = lower(strtrim(char(string(algorithm_name))));
enabled_idx = 0;

% 支持输入结果索引：例如 alg2
alg_token = regexp(query_str, '^alg(\d+)$', 'tokens', 'once');
if ~isempty(alg_token)
    idx_try = str2double(alg_token{1});
    if ~isnan(idx_try) && idx_try >= 1 && idx_try <= length(alg_list)
        enabled_idx = idx_try;
    end
end

% 支持输入算法 ID（例如 7）
if enabled_idx == 0
    id_try = str2double(query_str);
    if ~isnan(id_try)
        for i = 1:length(alg_list)
            if isfield(alg_list{i}, 'id') && alg_list{i}.id == id_try
                enabled_idx = i;
                break;
            end
        end
    end
end

% 支持输入名称（精确/包含，大小写不敏感）
if enabled_idx == 0
    for i = 1:length(alg_list)
        if isfield(alg_list{i}, 'name')
            if strcmpi(alg_list{i}.name, char(string(algorithm_name)))
                enabled_idx = i;
                break;
            end
        end
    end
end

if enabled_idx == 0
    for i = 1:length(alg_list)
        if isfield(alg_list{i}, 'name')
            name_i = lower(alg_list{i}.name);
            if contains(name_i, query_str) || contains(query_str, name_i)
                enabled_idx = i;
                break;
            end
        end
    end
end

if enabled_idx == 0
    name_list = cell(1, length(alg_list));
    for i = 1:length(alg_list)
        if isfield(alg_list{i}, 'name')
            if isfield(alg_list{i}, 'id')
                name_list{i} = sprintf('%s(id=%d)', alg_list{i}.name, alg_list{i}.id);
            else
                name_list{i} = alg_list{i}.name;
            end
        else
            name_list{i} = sprintf('alg%d', i);
        end
    end
    error('未找到算法: %s\n可用算法: %s', char(string(algorithm_name)), strjoin(name_list, ', '));
end

selected_alg_name = alg_list{enabled_idx}.name;
selected_alg_id_text = '';
if isfield(alg_list{enabled_idx}, 'id')
    selected_alg_id_text = sprintf(', id=%d', alg_list{enabled_idx}.id);
end
fprintf('找到算法: %s (alg%d%s)\n', selected_alg_name, enabled_idx, selected_alg_id_text);

%% 提取内循环数据
alg_field = sprintf('alg%d', enabled_idx);
alg_result = data.results.(alg_field);

% 检查是否有内循环数据（支持两种路径）
if isfield(alg_result, 'history_data') && isfield(alg_result.history_data, 'inner_loop')
    % 新格式：在history_data中
    inner_loop_data = alg_result.history_data.inner_loop;
elseif isfield(alg_result, 'inner_loop')
    % 旧格式：直接在alg_result中
    inner_loop_data = alg_result.inner_loop;
else
    error('算法 %s 没有记录内循环数据。请确保使用了最新版本的算法代码。', selected_alg_name);
end

if isempty(inner_loop_data)
    error('算法 %s 的内循环数据为空', selected_alg_name);
end

% 检查轮次是否有效
num_rounds = length(inner_loop_data);
if round_number < 1 || round_number > num_rounds
    error('轮次编号 %d 超出范围 [1, %d]', round_number, num_rounds);
end

inner_loop = inner_loop_data{round_number};

% 检查数据完整性
if isempty(inner_loop.iteration)
    error('第 %d 轮的内循环数据为空', round_number);
end

fprintf('正在绘制第 %d/%d 轮的内循环演化过程...\n', round_number, num_rounds);
fprintf('  - 迭代次数: %d\n', length(inner_loop.iteration));

is_qi = contains(lower(selected_alg_name), 'qi');
is_tabu = contains(lower(selected_alg_name), 'tabu') || contains(lower(selected_alg_name), 'ocf_satabu');

if is_qi
    fprintf('  - 初始Gamma: %.2f\n', inner_loop.temperature(1));
    fprintf('  - 最终Gamma: %.2f\n', inner_loop.temperature(end));
else
    fprintf('  - 初始温度: %.2f\n', inner_loop.temperature(1));
    fprintf('  - 最终温度: %.2f\n', inner_loop.temperature(end));
end

fprintf('  - 初始效用: %.2f\n', inner_loop.current_utility(1));
fprintf('  - 最终效用: %.2f\n', inner_loop.current_utility(end));
fprintf('  - 最优效用: %.2f\n', inner_loop.best_utility(end));

%% 创建图形窗口
fig = figure('Name', sprintf('%s - Round %d - Inner Loop Evolution', selected_alg_name, round_number), ...
    'Position', [100, 100, 1400, 900]);

%% 子图1: 温度/Gamma变化
subplot(2, 2, 1);
plot(inner_loop.iteration, inner_loop.temperature, 'b-', 'LineWidth', 2);
grid on;
xlabel('迭代次数 (Iteration)', 'FontSize', 11);

% 根据算法类型设置标签
if is_qi
    ylabel('Gamma系数 (Boltzmann Coefficient)', 'FontSize', 11);
    title_str = sprintf('Gamma增长曲线 (初始=%.1f)', inner_loop.temperature(1));
elseif is_tabu
    ylabel('温度 (Temperature)', 'FontSize', 11);
    if isfield(data, 'Value_Params') && isfield(data.Value_Params, 'alpha')
        title_str = sprintf('温度衰减曲线 - SA+Tabu (alpha=%.2f)', data.Value_Params.alpha);
    elseif isfield(data, 'Value_Params') && isfield(data.Value_Params, 'T_decay')
        title_str = sprintf('温度衰减曲线 - SA+Tabu (T_decay=%.2f)', data.Value_Params.T_decay);
    else
        title_str = '温度衰减曲线 - SA+Tabu';
    end
else
    ylabel('温度 (Temperature)', 'FontSize', 11);
    if isfield(data, 'Value_Params') && isfield(data.Value_Params, 'alpha')
        title_str = sprintf('温度衰减曲线 (alpha=%.2f)', data.Value_Params.alpha);
    elseif isfield(data, 'Value_Params') && isfield(data.Value_Params, 'T_decay')
        title_str = sprintf('温度衰减曲线 (T_decay=%.2f)', data.Value_Params.T_decay);
    else
        title_str = '温度衰减曲线';
    end
end
title(title_str, 'FontSize', 12, 'FontWeight', 'bold');

% 添加起始和终止标注
hold on;
plot(inner_loop.iteration(1), inner_loop.temperature(1), 'ro', 'MarkerSize', 8, 'MarkerFaceColor', 'r');
plot(inner_loop.iteration(end), inner_loop.temperature(end), 'go', 'MarkerSize', 8, 'MarkerFaceColor', 'g');

if is_qi
    text(inner_loop.iteration(1), inner_loop.temperature(1), sprintf('  Γ₀=%.2f', inner_loop.temperature(1)), ...
        'FontSize', 10, 'Color', 'r', 'VerticalAlignment', 'bottom');
    text(inner_loop.iteration(end), inner_loop.temperature(end), sprintf('  Γ_f=%.2f', inner_loop.temperature(end)), ...
        'FontSize', 10, 'Color', 'g', 'VerticalAlignment', 'top');
else
    text(inner_loop.iteration(1), inner_loop.temperature(1), sprintf('  T₀=%.2f', inner_loop.temperature(1)), ...
        'FontSize', 10, 'Color', 'r', 'VerticalAlignment', 'bottom');
    text(inner_loop.iteration(end), inner_loop.temperature(end), sprintf('  T_f=%.2f', inner_loop.temperature(end)), ...
        'FontSize', 10, 'Color', 'g', 'VerticalAlignment', 'top');
end
hold off;

%% 子图2: 效用演化
subplot(2, 2, 2);
plot(inner_loop.iteration, inner_loop.current_utility, 'b-', 'LineWidth', 1.5, 'DisplayName', '当前效用');
hold on;
plot(inner_loop.iteration, inner_loop.best_utility, 'r-', 'LineWidth', 2, 'DisplayName', '最优效用');
grid on;
xlabel('迭代次数 (Iteration)', 'FontSize', 11);
ylabel('效用 (Utility)', 'FontSize', 11);
title('效用演化曲线', 'FontSize', 12, 'FontWeight', 'bold');
legend('Location', 'best', 'FontSize', 10);

% 标注最优点
[max_util, max_idx] = max(inner_loop.best_utility);
plot(inner_loop.iteration(max_idx), max_util, 'r*', 'MarkerSize', 12, 'LineWidth', 2);
text(inner_loop.iteration(max_idx), max_util, sprintf('  最优: %.2f', max_util), ...
    'FontSize', 10, 'Color', 'r', 'VerticalAlignment', 'bottom');
hold off;

%% 子图3: 联盟数量变化
subplot(2, 2, 3);
plot(inner_loop.iteration, inner_loop.num_coalitions, 'g-', 'LineWidth', 2);
grid on;
xlabel('迭代次数 (Iteration)', 'FontSize', 11);
ylabel('联盟数量 (Number of Coalitions)', 'FontSize', 11);
title('联盟数量变化', 'FontSize', 12, 'FontWeight', 'bold');
ylim([0, max(inner_loop.num_coalitions) + 1]);

% 添加平均线
avg_coalitions = mean(inner_loop.num_coalitions);
hold on;
yline(avg_coalitions, 'r--', sprintf('平均: %.1f', avg_coalitions), 'LineWidth', 1.5, 'FontSize', 10);
hold off;

%% 子图4: 效用增量分析
subplot(2, 2, 4);

% 计算效用增量
utility_delta = diff(inner_loop.current_utility);
utility_delta = [0, utility_delta];  % 第一个迭代的增量为0

% 分离正增量和负增量
positive_delta = utility_delta;
positive_delta(positive_delta < 0) = 0;
negative_delta = utility_delta;
negative_delta(negative_delta > 0) = 0;

% 绘制柱状图
bar(inner_loop.iteration, positive_delta, 'FaceColor', [0.2, 0.8, 0.2], 'EdgeColor', 'none', 'DisplayName', '效用提升');
hold on;
bar(inner_loop.iteration, negative_delta, 'FaceColor', [0.8, 0.2, 0.2], 'EdgeColor', 'none', 'DisplayName', '效用下降');
grid on;
xlabel('迭代次数 (Iteration)', 'FontSize', 11);
ylabel('效用增量 (ΔUtility)', 'FontSize', 11);

% 根据算法类型设置标题
if is_qi
    title('效用变化分析 (禁忌搜索)', 'FontSize', 12, 'FontWeight', 'bold');
elseif is_tabu
    title('效用变化分析 (SA+Tabu混合)', 'FontSize', 12, 'FontWeight', 'bold');
else
    title('效用变化分析 (SA接受劣解)', 'FontSize', 12, 'FontWeight', 'bold');
end
legend('Location', 'best', 'FontSize', 10);

% 统计接受劣解的次数
num_accept_worse = sum(utility_delta < -1e-6);
num_accept_better = sum(utility_delta > 1e-6);
num_no_change = sum(abs(utility_delta) <= 1e-6);

if is_qi
    text(0.05, 0.95, sprintf('效用提升: %d次\n效用下降: %d次\n无变化: %d次', ...
        num_accept_better, num_accept_worse, num_no_change), ...
        'Units', 'normalized', 'FontSize', 10, 'VerticalAlignment', 'top', ...
        'BackgroundColor', 'white', 'EdgeColor', 'black');
elseif is_tabu
    text(0.05, 0.95, sprintf('效用提升: %d次\n接受劣解: %d次\n禁忌拒绝: 见log\n无变化: %d次', ...
        num_accept_better, num_accept_worse, num_no_change), ...
        'Units', 'normalized', 'FontSize', 10, 'VerticalAlignment', 'top', ...
        'BackgroundColor', 'white', 'EdgeColor', 'black');
else
    text(0.05, 0.95, sprintf('接受劣解: %d次\n接受优解: %d次\n无变化: %d次', ...
        num_accept_worse, num_accept_better, num_no_change), ...
        'Units', 'normalized', 'FontSize', 10, 'VerticalAlignment', 'top', ...
        'BackgroundColor', 'white', 'EdgeColor', 'black');
end
hold off;

%% 添加总标题
sgtitle(sprintf('%s - 第%d轮内循环演化 (共%d次迭代)', ...
    strrep(selected_alg_name, '_', '\_'), round_number, length(inner_loop.iteration)), ...
    'FontSize', 14, 'FontWeight', 'bold');

%% 保存图形
save_dir = 'figures';
if ~exist(save_dir, 'dir')
    mkdir(save_dir);
end

timestamp = datestr(now, 'yyyymmdd_HHMMSS');
save_filename = sprintf('%s/%s_Round%d_InnerLoop_%s.png', save_dir, selected_alg_name, round_number, timestamp);
saveas(fig, save_filename);
fprintf('图形已保存到: %s\n', save_filename);

%% 打印统计信息
fprintf('\n========================================\n');
fprintf('内循环统计信息\n');
fprintf('========================================\n');
fprintf('算法: %s\n', selected_alg_name);
fprintf('轮次: %d/%d\n', round_number, num_rounds);
fprintf('----------------------------------------\n');
fprintf('迭代次数: %d\n', length(inner_loop.iteration));

if is_qi
    fprintf('Gamma范围: %.2f → %.2f\n', inner_loop.temperature(1), inner_loop.temperature(end));
else
    fprintf('温度范围: %.2f → %.2f\n', inner_loop.temperature(1), inner_loop.temperature(end));
end

fprintf('效用范围: %.2f → %.2f\n', min(inner_loop.current_utility), max(inner_loop.current_utility));
fprintf('最优效用: %.2f (第%d次迭代)\n', max_util, inner_loop.iteration(max_idx));
fprintf('联盟数量: %d → %d (平均: %.1f)\n', ...
    inner_loop.num_coalitions(1), inner_loop.num_coalitions(end), avg_coalitions);
fprintf('----------------------------------------\n');

if is_qi
    fprintf('效用提升: %d次 (%.1f%%)\n', num_accept_better, 100*num_accept_better/length(utility_delta));
    fprintf('效用下降: %d次 (%.1f%%)\n', num_accept_worse, 100*num_accept_worse/length(utility_delta));
elseif is_tabu
    fprintf('效用提升: %d次 (%.1f%%)\n', num_accept_better, 100*num_accept_better/length(utility_delta));
    fprintf('接受劣解(SA): %d次 (%.1f%%)\n', num_accept_worse, 100*num_accept_worse/length(utility_delta));
    fprintf('(注: 禁忌拒绝次数需查看详细日志)\n');
else
    fprintf('接受优解: %d次 (%.1f%%)\n', num_accept_better, 100*num_accept_better/length(utility_delta));
    fprintf('接受劣解: %d次 (%.1f%%)\n', num_accept_worse, 100*num_accept_worse/length(utility_delta));
end

fprintf('无变化: %d次 (%.1f%%)\n', num_no_change, 100*num_no_change/length(utility_delta));
fprintf('========================================\n');

end
