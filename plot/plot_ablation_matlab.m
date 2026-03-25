function [n_values, seeds, utility, completion] = plot_ablation_matlab(mat_path)
%PLOT_ABLATION_MATLAB MATLAB版本的消融实验读取与绘图脚本
%
% 作用：
%   读取 Batch_Ablation.m 生成的 .mat 文件，提取 belief_on / belief_off
%   两种条件下的：
%     1) final_utility
%     2) final_task_completion
%   并绘制 2×N 的散点对比图。
%
% 用法：
%   plot_ablation_matlab();
%   plot_ablation_matlab('D:/xxx/ablation_xxx.mat');
%   [n_values, seeds, utility, completion] = plot_ablation_matlab(...);
%
% 说明：
%   这份 MATLAB 版不是照搬 Python 里的 h5py 底层 HDF5 解析，
%   而是直接使用 MATLAB 自己的 load 来读取 v7.3 的 .mat。
%   这样更适合你在 MATLAB 里逐层检查：
%       ablation_results{ni, si, ci}
%   到底有哪些字段、每一步数据是否正确。
%
% 约定：
%   ablation_results 的维度应为 (num_N, num_seeds, 2)
%   其中第3维：1 = belief_on, 2 = belief_off
%
% 作者：OpenAI

    % =========================
    % 顶部可调参数区
    % =========================
    SCRIPT_DIR = fileparts(mfilename('fullpath'));
    ROOT_DIR   = fileparts(SCRIPT_DIR);
    FIGURES_DIR = fullfile(ROOT_DIR, 'figures', 'paper');
    SEARCH_DIRS = {
        fullfile(ROOT_DIR, 'results', 'batch', 'ablation'), ...
        fullfile(ROOT_DIR, 'results', 'batch')
    };

    STYLE_ON.color    = [46, 109, 180] / 255;  % #2E6DB4
    STYLE_ON.marker   = 'o';
    STYLE_ON.size     = 60;
    STYLE_ON.label    = 'belief\_on';

    STYLE_OFF.color   = [192, 57, 43] / 255;   % #C0392B
    STYLE_OFF.marker  = 'x';
    STYLE_OFF.size    = 70;
    STYLE_OFF.label   = 'belief\_off';
    STYLE_OFF.linew   = 1.8;

    CONN_LINE.color   = [170, 170, 170] / 255; % #AAAAAA
    CONN_LINE.linew   = 0.9;

    ROW_YLABELS = {'Coalition Utility', 'Task Completion Rate'};
    ROW_TITLES  = {'最终联盟效用', '平均任务完成率'};

    PLOT_GLOBAL.subplot_w = 3.4;
    PLOT_GLOBAL.subplot_h = 3.2;
    PLOT_GLOBAL.xlabel_fontsize = 10;
    PLOT_GLOBAL.ylabel_fontsize = 10;
    PLOT_GLOBAL.title_fontsize  = 11;
    PLOT_GLOBAL.tick_fontsize   = 9;
    PLOT_GLOBAL.legend_fontsize = 9;
    PLOT_GLOBAL.show_grid       = true;
    PLOT_GLOBAL.save_dpi        = 150;

    % =========================
    % 1) 找文件
    % =========================
    if nargin < 1 || isempty(mat_path)
        mat_path = find_mat_file(SEARCH_DIRS);
    else
        if ~isfile(mat_path)
            error('指定文件不存在: %s', mat_path);
        end
    end

    fprintf('\n加载数据（MATLAB load 直接解析）...\n');

    % =========================
    % 2) 读取 MAT 文件
    % =========================
    S = load(mat_path, 'ablation_config', 'ablation_results');

    if ~isfield(S, 'ablation_config')
        error('MAT 文件中缺少变量 ablation_config');
    end
    if ~isfield(S, 'ablation_results')
        error('MAT 文件中缺少变量 ablation_results');
    end

    cfg = S.ablation_config;
    results = S.ablation_results;

    if ~isfield(cfg, 'N_values')
        error('ablation_config 中缺少字段 N_values');
    end
    if ~isfield(cfg, 'seeds')
        error('ablation_config 中缺少字段 seeds');
    end

    n_values = double(cfg.N_values(:)).';
    seeds    = double(cfg.seeds(:)).';

    num_N = numel(n_values);
    num_S = numel(seeds);
    num_C = 2;

    if ~iscell(results)
        error('ablation_results 不是 cell array，请检查 Batch_Ablation.m 的保存格式。');
    end

    result_size = size(results);
    fprintf('  ablation_results MATLAB size = [%s]\n', num2str(result_size));
    fprintf('  期望至少为 [%d %d %d]\n', num_N, num_S, num_C);

    utility    = nan(num_N, num_S, num_C);
    completion = nan(num_N, num_S, num_C);

    maxN = min(num_N, size(results, 1));
    maxS = min(num_S, size(results, 2));
    if ndims(results) < 3
        maxC = 1;
    else
        maxC = min(num_C, size(results, 3));
    end

    % =========================
    % 3) 抽取核心字段
    % =========================
    for ni = 1:maxN
        for si = 1:maxS
            for ci = 1:maxC
                entry = results{ni, si, ci};

                if isempty(entry) || ~isstruct(entry)
                    continue;
                end

                % success 字段存在且不为 1 时，跳过
                if isfield(entry, 'success')
                    succ = double(entry.success);
                    if isempty(succ) || isnan(succ) || succ ~= 1
                        continue;
                    end
                end

                if isfield(entry, 'final_utility')
                    utility(ni, si, ci) = safe_scalar(entry.final_utility);
                end

                if isfield(entry, 'final_task_completion')
                    completion(ni, si, ci) = safe_scalar(entry.final_task_completion);
                end
            end
        end
    end

    fprintf('  N_values   = %s\n', mat2str(n_values));
    fprintf('  seeds      = %s\n', mat2str(seeds));
    fprintf('  utility    有效: on=%d off=%d\n', ...
        sum(~isnan(utility(:, :, 1)), 'all'), ...
        sum(~isnan(utility(:, :, 2)), 'all'));
    fprintf('  completion 有效: on=%d off=%d\n', ...
        sum(~isnan(completion(:, :, 1)), 'all'), ...
        sum(~isnan(completion(:, :, 2)), 'all'));

    if all(isnan(completion), 'all')
        fprintf('\n⚠ 警告: 未找到 final_task_completion 字段（旧版 .mat 可能不含此字段）。\n');
        fprintf('  任务完成率子图将为空。重新运行 Batch_Ablation.m 可修复。\n');
    end

    % =========================
    % 4) 绘图
    % =========================
    [~, basename, ~] = fileparts(mat_path);
    parts = split(string(basename), '_');
    if numel(parts) >= 2
        ts = strjoin(parts(end-1:end), '_');
    else
        ts = "ts";
    end

    save_path = fullfile(FIGURES_DIR, sprintf('ablation_scatter_%s.png', ts));
    fprintf('\n绘图 → %s\n', save_path);

    plot_ablation_scatter(n_values, seeds, utility, completion, save_path, ...
        STYLE_ON, STYLE_OFF, CONN_LINE, ROW_YLABELS, ROW_TITLES, PLOT_GLOBAL);

    fprintf('\n完成。\n');
end


function plot_ablation_scatter(n_values, seeds, utility, completion, save_path, ...
    STYLE_ON, STYLE_OFF, CONN_LINE, ROW_YLABELS, ROW_TITLES, PLOT_GLOBAL)

    num_N = numel(n_values);
    num_S = numel(seeds);
    x_ticks = 1:num_S;

    fig_w = PLOT_GLOBAL.subplot_w * num_N;
    fig_h = PLOT_GLOBAL.subplot_h * 2;
    fig = figure('Color', 'w', 'Units', 'inches', 'Position', [1, 1, fig_w, fig_h]);

    data_list = {utility, completion};

    for row = 1:2
        data = data_list{row};
        ylabel_text = ROW_YLABELS{row};

        for col = 1:num_N
            ax = subplot(2, num_N, (row-1) * num_N + col);
            hold(ax, 'on');

            % 灰线：连接同一个 seed 的 belief_on / belief_off
            for si = 1:num_S
                y_on  = data(col, si, 1);
                y_off = data(col, si, 2);
                if ~(isnan(y_on) || isnan(y_off))
                    plot(ax, [x_ticks(si), x_ticks(si)], [y_on, y_off], ...
                        '-', 'Color', CONN_LINE.color, 'LineWidth', CONN_LINE.linew);
                end
            end

            % belief_on
            y_on = squeeze(data(col, :, 1));
            valid_on = ~isnan(y_on);
            scatter(ax, x_ticks(valid_on), y_on(valid_on), STYLE_ON.size, ...
                'Marker', STYLE_ON.marker, ...
                'MarkerEdgeColor', STYLE_ON.color, ...
                'MarkerFaceColor', STYLE_ON.color, ...
                'DisplayName', STYLE_ON.label);

            % belief_off
            y_off = squeeze(data(col, :, 2));
            valid_off = ~isnan(y_off);
            scatter(ax, x_ticks(valid_off), y_off(valid_off), STYLE_OFF.size, ...
                'Marker', STYLE_OFF.marker, ...
                'MarkerEdgeColor', STYLE_OFF.color, ...
                'LineWidth', STYLE_OFF.linew, ...
                'DisplayName', STYLE_OFF.label);

            set(ax, 'XTick', x_ticks, ...
                'XTickLabel', compose('%g', seeds), ...
                'FontSize', PLOT_GLOBAL.tick_fontsize, ...
                'Box', 'off');

            xlim(ax, [0.5, num_S + 0.5]);
            xlabel(ax, 'Seed', 'FontSize', PLOT_GLOBAL.xlabel_fontsize);
            ylabel(ax, ylabel_text, 'FontSize', PLOT_GLOBAL.ylabel_fontsize);
            title(ax, sprintf('N = %g', n_values(col)), ...
                'FontSize', PLOT_GLOBAL.title_fontsize, 'FontWeight', 'bold');

            if PLOT_GLOBAL.show_grid
                grid(ax, 'on');
                ax.GridLineStyle = '--';
                ax.GridAlpha = 0.35;
            end

            % 在每一行最左边加竖排行标题
            if col == 1
                text(ax, -0.32, 0.5, ROW_TITLES{row}, ...
                    'Units', 'normalized', ...
                    'Rotation', 90, ...
                    'HorizontalAlignment', 'center', ...
                    'VerticalAlignment', 'middle', ...
                    'FontSize', 9, ...
                    'FontWeight', 'bold');
            end

            hold(ax, 'off');
        end
    end

    sgtitle('消融实验：信念更新机制对比  (belief\_on ● vs belief\_off ✕)', ...
        'FontSize', 12, 'FontWeight', 'bold');

    % 统一图例：放在第1行最后一个子图
    ax_legend = subplot(2, num_N, num_N);
    hold(ax_legend, 'on');
    h_on = scatter(ax_legend, nan, nan, STYLE_ON.size, ...
        'Marker', STYLE_ON.marker, ...
        'MarkerEdgeColor', STYLE_ON.color, ...
        'MarkerFaceColor', STYLE_ON.color, ...
        'DisplayName', STYLE_ON.label);
    h_off = scatter(ax_legend, nan, nan, STYLE_OFF.size, ...
        'Marker', STYLE_OFF.marker, ...
        'MarkerEdgeColor', STYLE_OFF.color, ...
        'LineWidth', STYLE_OFF.linew, ...
        'DisplayName', STYLE_OFF.label);
    legend(ax_legend, [h_on, h_off], 'Location', 'best', ...
        'FontSize', PLOT_GLOBAL.legend_fontsize, 'Box', 'on');
    hold(ax_legend, 'off');

    drawnow;

    out_dir = fileparts(save_path);
    if ~isempty(out_dir) && ~exist(out_dir, 'dir')
        mkdir(out_dir);
    end

    try
        exportgraphics(fig, save_path, 'Resolution', PLOT_GLOBAL.save_dpi);
    catch
        print(fig, save_path, '-dpng', sprintf('-r%d', PLOT_GLOBAL.save_dpi));
    end
    fprintf('  ✓ %s\n', save_path);
end


function x = safe_scalar(v)
% 将标量/单元素数组/空值统一转成 double 标量
    if isempty(v)
        x = nan;
        return;
    end
    v = double(v);
    v = v(:);
    if isempty(v)
        x = nan;
    else
        x = v(1);
    end
end


function mat_path = find_mat_file(search_dirs)
% 自动寻找最新 .mat 文件，优先文件名中含 ablation 的结果
    candidates = strings(0, 1);

    for i = 1:numel(search_dirs)
        d = search_dirs{i};
        if ~exist(d, 'dir')
            continue;
        end
        files = dir(fullfile(d, '*.mat'));
        if isempty(files)
            continue;
        end
        fullpaths = fullfile({files.folder}, {files.name});
        candidates = [candidates; string(fullpaths(:))]; %#ok<AGROW>
    end

    if isempty(candidates)
        error(['找不到 .mat 文件，请先运行 Batch_Ablation.m，', ...
               '或手动把 .mat 路径传给 plot_ablation_matlab(mat_path)。']);
    end

    names_lower = lower(candidates);
    mask = contains(names_lower, 'ablation');
    if any(mask)
        pool = candidates(mask);
    else
        pool = candidates;
    end

    datenums = zeros(numel(pool), 1);
    for i = 1:numel(pool)
        info = dir(pool(i));
        datenums(i) = info.datenum;
    end

    [~, idx] = max(datenums);
    mat_path = char(pool(idx));
    fprintf('自动选择: %s\n', mat_path);
end
