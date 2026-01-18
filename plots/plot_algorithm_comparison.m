function plot_algorithm_comparison(results, comparison_stats, num_algorithms)
% PLOT_ALGORITHM_COMPARISON 绘制算法对比图表
%
% 输入:
%   results - 包含所有算法结果的结构体
%   comparison_stats - 算法性能统计
%   num_algorithms - 算法数量

    alg_names = fieldnames(results);
    
    % 提取数据用于绘图
    names_list = {};
    utilities = [];
    completed_values = [];
    comp_times = [];
    coalitions = [];
    completion_rates = [];
    resource_utils = [];
    colors = [];
    
    for i = 1:num_algorithms
        alg_name = alg_names{i};
        stats = comparison_stats.(alg_name);
        
        if stats.has_error
            continue;
        end
        
        names_list{end+1} = stats.name;
        utilities(end+1) = stats.total_utility;
        if isfield(stats, 'completed_value')
            completed_values(end+1) = stats.completed_value;
        else
            completed_values(end+1) = stats.total_value_achieved;
        end
        comp_times(end+1) = stats.computation_time;
        coalitions(end+1) = stats.num_coalitions;
        completion_rates(end+1) = stats.normalized_completion_rate;  % 使用归一化完成率（考虑资源满足度）
        resource_utils(end+1) = stats.resource_utilization;
        
        if isfield(results.(alg_name), 'color')
            colors(end+1, :) = results.(alg_name).color;
        else
            colors(end+1, :) = [0.5, 0.5, 0.5];
        end
    end
    
    valid_count = length(names_list);
    
    if valid_count == 0
        fprintf('警告: 没有有效的算法结果用于绘图\n');
        return;
    end
    
    %% 创建综合对比图
    figure('Name', '算法性能对比', 'Position', [100, 100, 1400, 900]);
    
    %% 子图1: 总效用对比
    subplot(2, 3, 1);
    bar_colors = colors;
    b = bar(utilities);
    b.FaceColor = 'flat';
    for k = 1:valid_count
        b.CData(k,:) = bar_colors(k,:);
    end
    set(gca, 'XTickLabel', names_list, 'XTick', 1:valid_count);
    xtickangle(45);
    ylabel('总效用');
    title('总效用对比');
    grid on;
    
    % 在柱状图上添加数值标签
    for k = 1:valid_count
        text(k, utilities(k), sprintf('%.1f', utilities(k)), ...
             'HorizontalAlignment', 'center', 'VerticalAlignment', 'bottom');
    end
    
    %% 子图2: 计算时间对比
    subplot(2, 3, 2);
    b = bar(comp_times);
    b.FaceColor = 'flat';
    for k = 1:valid_count
        b.CData(k,:) = bar_colors(k,:);
    end
    set(gca, 'XTickLabel', names_list, 'XTick', 1:valid_count);
    xtickangle(45);
    ylabel('时间 (秒)');
    title('计算时间对比');
    grid on;
    
    for k = 1:valid_count
        text(k, comp_times(k), sprintf('%.2fs', comp_times(k)), ...
             'HorizontalAlignment', 'center', 'VerticalAlignment', 'bottom');
    end
    
    %% 子图3: 联盟数量对比
    subplot(2, 3, 3);
    b = bar(coalitions);
    b.FaceColor = 'flat';
    for k = 1:valid_count
        b.CData(k,:) = bar_colors(k,:);
    end
    set(gca, 'XTickLabel', names_list, 'XTick', 1:valid_count);
    xtickangle(45);
    ylabel('联盟数量');
    title('形成联盟数量对比');
    grid on;
    
    for k = 1:valid_count
        text(k, coalitions(k), sprintf('%d', coalitions(k)), ...
             'HorizontalAlignment', 'center', 'VerticalAlignment', 'bottom');
    end
    
    %% 子图4: 任务完成率对比
    subplot(2, 3, 4);
    b = bar(completion_rates);
    b.FaceColor = 'flat';
    for k = 1:valid_count
        b.CData(k,:) = bar_colors(k,:);
    end
    set(gca, 'XTickLabel', names_list, 'XTick', 1:valid_count);
    xtickangle(45);
    ylabel('完成率 (%)');
    title('任务完成率对比');
    grid on;
    ylim([0, 110]);
    
    for k = 1:valid_count
        text(k, completion_rates(k), sprintf('%.1f%%', completion_rates(k)), ...
             'HorizontalAlignment', 'center', 'VerticalAlignment', 'bottom');
    end
    
    %% 子图5: 资源利用率对比
    subplot(2, 3, 5);
    b = bar(resource_utils);
    b.FaceColor = 'flat';
    for k = 1:valid_count
        b.CData(k,:) = bar_colors(k,:);
    end
    set(gca, 'XTickLabel', names_list, 'XTick', 1:valid_count);
    xtickangle(45);
    ylabel('利用率 (%)');
    title('资源利用率对比');
    grid on;
    
    for k = 1:valid_count
        text(k, resource_utils(k), sprintf('%.1f%%', resource_utils(k)), ...
             'HorizontalAlignment', 'center', 'VerticalAlignment', 'bottom');
    end
    
    %% 子图6: 完成价值（价值×完成度）
    subplot(2, 3, 6);
    b = bar(completed_values);
    b.FaceColor = 'flat';
    for k = 1:valid_count
        b.CData(k,:) = bar_colors(k,:);
    end
    set(gca, 'XTickLabel', names_list, 'XTick', 1:valid_count);
    xtickangle(45);
    ylabel('完成价值');
    title('完成价值对比');
    grid on;
    for k = 1:valid_count
        text(k, completed_values(k), sprintf('%.1f', completed_values(k)), ...
             'HorizontalAlignment', 'center', 'VerticalAlignment', 'bottom');
    end
    
    % 调整整体布局
    sgtitle('联盟形成算法性能综合对比', 'FontSize', 14, 'FontWeight', 'bold');
    
    %% 如果有多个算法，创建雷达图
    if valid_count >= 2
        figure('Name', '算法性能雷达图', 'Position', [150, 150, 800, 600]);
        
        % 准备雷达图数据（归一化到0-1）
        radar_data = zeros(valid_count, 5);
        
        % 1. 总效用（归一化）
        if max(utilities) > 0
            radar_data(:, 1) = utilities' / max(utilities);
        end
        
        % 2. 计算速度（时间的倒数，归一化）
        speeds = 1 ./ comp_times;
        if max(speeds) > 0
            radar_data(:, 2) = speeds' / max(speeds);
        end
        
        % 3. 任务完成率（已经是百分比，除以100）
        radar_data(:, 3) = completion_rates' / 100;
        
        % 4. 资源利用率（已经是百分比，除以100）
        radar_data(:, 4) = resource_utils' / 100;
        
        % 5. 联盟数量（归一化）
        if max(coalitions) > 0
            radar_data(:, 5) = coalitions' / max(coalitions);
        end
        
        % 雷达图标签
        radar_labels = {'总效用', '计算速度', '任务完成率', '资源利用率', '联盟数量'};
        
        % 绘制雷达图
        angles = linspace(0, 2*pi, 6);
        
        hold on;
        for i = 1:valid_count
            data_point = [radar_data(i, :), radar_data(i, 1)];  % 闭合
            plot(angles, data_point, 'o-', 'LineWidth', 2, ...
                 'Color', colors(i, :), 'MarkerFaceColor', colors(i, :), ...
                 'DisplayName', names_list{i});
        end
        
        % 绘制网格
        for r = 0.2:0.2:1
            plot(angles, r * ones(size(angles)), ':', 'Color', [0.7, 0.7, 0.7]);
        end
        
        % 设置坐标轴
        ax = gca;
        ax.XTick = angles(1:end-1);
        ax.XTickLabel = radar_labels;
        ax.YLim = [0, 1.2];
        
        % 添加图例
        legend('Location', 'northeastoutside');
        title('算法综合性能雷达图', 'FontSize', 12, 'FontWeight', 'bold');
        grid on;
        axis equal;
        hold off;
    end
    
    %% 若存在历史完成价值，则绘制演化曲线
    value_histories = {};
    hist_names = {};
    for i = 1:num_algorithms
        alg_name = alg_names{i};
        res = results.(alg_name);
        if ~isfield(res, 'history_data') || isempty(res.history_data)
            continue;
        end
        hd = res.history_data;
        vals = [];
        if isfield(hd, 'total_value_history') && ~isempty(hd.total_value_history)
            vals = hd.total_value_history;
        elseif isfield(hd, 'rounds')
            try
                num_r = numel(hd.rounds);
                vals = zeros(1, num_r);
                for rr = 1:num_r
                    if isfield(hd.rounds(rr), 'total_completed_value')
                        vals(rr) = hd.rounds(rr).total_completed_value;
                    end
                end
                if all(vals == 0)
                    vals = [];
                end
            catch
                vals = [];
            end
        end
        if ~isempty(vals)
            value_histories{end+1} = vals;
            hist_names{end+1} = res.name;
        end
    end
    
    if ~isempty(value_histories)
        figure('Name', '完成价值演化', 'Position', [200, 200, 900, 500]);
        hold on;
        for i = 1:numel(value_histories)
            plot(value_histories{i}, 'LineWidth', 2, 'DisplayName', hist_names{i});
        end
        xlabel('轮次');
        ylabel('完成价值（价值×完成度）');
        title('完成价值演化对比');
        grid on;
        legend('Location', 'best');
        hold off;
    end
    
    fprintf('? 对比图表绘制完成\n');
    
end
