function plot_algorithm_comparison(results, comparison_stats, num_algorithms)
% PLOT_ALGORITHM_COMPARISON 绘制算法对比图表 (适配极简版统计结构)
%
% 输入:
%   results          - 包含所有算法结果的结构体 (含 history_data)
%   comparison_stats - compare_results 输出的统计结构体
%   num_algorithms   - 算法数量

    alg_names = fieldnames(results);
    
    % --- 1. 提取数据用于绘图 ---
    names_list = {};
    utilities = [];
    costs = [];              % [新增] 成本
    completed_values = [];   % 完成价值
    comp_times = [];
    coalitions = [];         % 联盟数
    avg_rates = [];          % 平均完成率
    colors = [];
    
    for i = 1:num_algorithms
        alg_name = alg_names{i};
        
        % 检查统计结果是否存在
        if ~isfield(comparison_stats, alg_name)
            continue;
        end
        stats = comparison_stats.(alg_name);
        
        if stats.has_error
            continue;
        end
        
        names_list{end+1} = stats.name;
        
        % 提取核心标量
        utilities(end+1) = stats.total_utility;
        costs(end+1) = stats.total_cost;
        completed_values(end+1) = stats.total_completion_score;
        comp_times(end+1) = stats.computation_time;
        coalitions(end+1) = stats.num_coalitions;
        avg_rates(end+1) = stats.avg_task_completion * 100; % 转换为百分比
        
        % 提取颜色
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
    
    %% --- 2. 创建综合柱状对比图 (2行3列) ---
    figure('Name', '算法性能综合对比', 'Position', [100, 100, 1400, 900]);
    
    % 辅助绘图函数 (内部使用)
    plot_bar = @(idx, data, title_str, y_label, fmt) ...
        local_plot_bar(idx, data, title_str, y_label, fmt, names_list, colors, valid_count);

    % 子图1: 总效用 (Utility)
    plot_bar(1, utilities, '总效用对比 (Utility)', '效用值', '%.1f');
    
    % 子图2: 总成本 (Cost) - [新增]
    plot_bar(2, costs, '总成本对比 (Cost)', '成本值', '%.1f');

    % 子图3: 总完成价值 (Total Value)
    plot_bar(3, completed_values, '总完成价值 (Total Value)', '价值', '%.1f');
    
    % 子图4: 计算时间 (Time)
    plot_bar(4, comp_times, '计算时间对比 (Time)', '时间 (s)', '%.2fs');
    
    % 子图5: 联盟数量 (# Coalitions)
    plot_bar(5, coalitions, '执行任务数 (# Coalitions)', '数量', '%d');
    
    % 子图6: 平均完成率 (Avg Rate)
    plot_bar(6, avg_rates, '平均任务完成率 (Avg Rate)', '完成率 (%)', '%.1f%%');
    
    sgtitle('多算法性能指标综合对比', 'FontSize', 14, 'FontWeight', 'bold');
    
    %% --- 3. 创建雷达图 (如果算法 >= 2) ---
    if valid_count >= 2
        figure('Name', '算法性能雷达图', 'Position', [150, 150, 800, 600]);
        
        % 准备雷达图数据（归一化到 0-1）
        radar_data = zeros(valid_count, 5);
        
        % 维度1: 总效用 (越大越好)
        if max(utilities) > 0, radar_data(:, 1) = utilities' / max(utilities); end
        
        % 维度2: 成本优势 (越小越好 -> 1/Cost 归一化)
        % 处理成本为0的情况防止除零
        safe_costs = costs; safe_costs(safe_costs==0) = 1e-6; 
        inv_costs = 1 ./ safe_costs;
        if max(inv_costs) > 0, radar_data(:, 2) = inv_costs' / max(inv_costs); end
        
        % 维度3: 总价值 (越大越好)
        if max(completed_values) > 0, radar_data(:, 3) = completed_values' / max(completed_values); end
        
        % 维度4: 平均完成率 (已经是0-100，除以100即可，或者归一化到最大值)
        radar_data(:, 4) = avg_rates' / 100; 
        
        % 维度5: 计算速度 (越快越好 -> 1/Time 归一化)
        speeds = 1 ./ (comp_times + 1e-6);
        if max(speeds) > 0, radar_data(:, 5) = speeds' / max(speeds); end
        
        % 标签
        radar_labels = {'总效用', '成本优势(1/Cost)', '总价值', '平均完成率', '计算速度'};
        
        % 绘图逻辑
        angles = linspace(0, 2*pi, 6); % 5个点 + 闭合点
        hold on;
        for i = 1:valid_count
            data_point = [radar_data(i, :), radar_data(i, 1)]; % 闭合
            plot(angles, data_point, 'o-', 'LineWidth', 2, ...
                 'Color', colors(i, :), 'MarkerFaceColor', colors(i, :), ...
                 'DisplayName', names_list{i});
        end
        
        % 网格与修饰
        for r = 0.2:0.2:1, plot(angles, r * ones(size(angles)), ':', 'Color', [0.7 0.7 0.7]); end
        ax = gca; ax.XTick = angles(1:end-1); ax.XTickLabel = radar_labels; ax.YLim = [0, 1.2];
        legend('Location', 'northeastoutside');
        title('算法综合性能雷达图 (归一化)', 'FontSize', 12, 'FontWeight', 'bold');
        axis equal; grid on; hold off;
    end
    
    %% --- 4. 绘制历史演化曲线 (Total Value History) ---
    % 检查是否有历史数据
    value_histories = {};
    utility_histories = {};
    hist_names = {};
    hist_colors = [];
    
    for i = 1:num_algorithms
        alg_name = alg_names{i};
        res = results.(alg_name);
        
        % 直接检查 rounds 结构
        if isfield(res, 'history_data') && isfield(res.history_data, 'rounds')
            rounds = res.history_data.rounds;
            if ~isempty(rounds)
                % 利用 MATLAB 结构体数组提取特性: [struct.field]
                % 提取总完成价值
                if isfield(rounds, 'total_completed_value')
                    vals = [rounds.total_completed_value];
                    value_histories{end+1} = vals;
                end
                
                % 提取总效用 (也画一张图)
                if isfield(rounds, 'coalition_utility') % 这里的 utility 是标量
                    utils = [rounds.coalition_utility];
                    utility_histories{end+1} = utils;
                end
                
                hist_names{end+1} = res.name;
                if isfield(res, 'color'), hist_colors(end+1, :) = res.color; 
                else, hist_colors(end+1, :) = [0 0 0]; end
            end
        end
    end
    
    % 绘制 完成价值 演化图
    if ~isempty(value_histories)
        figure('Name', '收敛曲线', 'Position', [200, 200, 1200, 500]);
        
        subplot(1, 2, 1);
        hold on;
        for k = 1:length(value_histories)
            plot(value_histories{k}, 'LineWidth', 2, 'Color', hist_colors(k,:), 'DisplayName', hist_names{k});
        end
        xlabel('迭代轮次 (Round)'); ylabel('总完成价值');
        title('总完成价值收敛曲线');
        grid on; legend('Location', 'best'); hold off;
        
        % 绘制 总效用 演化图
        subplot(1, 2, 2);
        hold on;
        for k = 1:length(utility_histories)
            plot(utility_histories{k}, 'LineWidth', 2, 'Color', hist_colors(k,:), 'DisplayName', hist_names{k});
        end
        xlabel('迭代轮次 (Round)'); ylabel('全局净效用');
        title('全局净效用收敛曲线');
        grid on; legend('Location', 'best'); hold off;
    end
    
    fprintf('✔ 对比图表绘制完成\n');
end

%% 辅助函数：绘制单个柱状子图
function local_plot_bar(idx, data, title_str, y_label, fmt, names, colors, count)
    subplot(2, 3, idx);
    b = bar(data);
    b.FaceColor = 'flat';
    for k = 1:count
        b.CData(k,:) = colors(k,:);
    end
    set(gca, 'XTickLabel', names, 'XTick', 1:count);
    xtickangle(45);
    ylabel(y_label);
    title(title_str);
    grid on;
    
    % 添加数值标签
    for k = 1:count
        text(k, data(k), sprintf(fmt, data(k)), ...
             'HorizontalAlignment', 'center', 'VerticalAlignment', 'bottom');
    end
end