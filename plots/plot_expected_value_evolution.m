function plot_expected_value_evolution(history_data, tasks, Value_Params)
% PLOT_EXPECTED_VALUE_EVOLUTION - 绘制各任务的期望收益演化（6个子图）
%
% 输入参数：
%   history_data - 历史记录数据结构体
%   tasks - 任务信息数组
%   Value_Params - 参数结构体

M = Value_Params.M;
N = Value_Params.N;
num_rounds = Value_Params.num_rounds;
task_values = tasks(1).WORLD.value;  % [1000, 1500, 2000]
num_types = length(task_values);

% 选择中文字体
chFont = local_pick_chinese_font();

% 创建图形
figure('Name', '任务期望收益演化', 'NumberTitle', 'off', 'Position', [100, 100, 1400, 900]);

% 为每个任务创建子图
for m = 1:M
    subplot(ceil(M/3), 3, m);
    hold on;
    
    % 提取该任务的信念演化数据（取所有智能体的平均信念）
    belief_evolution = zeros(num_rounds, num_types);
    expected_value_evolution = zeros(num_rounds, 1);
    
    for r = 1:num_rounds
        % 计算所有智能体对任务m的平均信念
        avg_belief = zeros(1, num_types);
        for i = 1:N
            agent_belief = history_data.rounds(r).agents(i).belief(m, :);
            avg_belief = avg_belief + agent_belief;
        end
        avg_belief = avg_belief / N;
        
        belief_evolution(r, :) = avg_belief;
        
        % 计算期望价值
        expected_value_evolution(r) = sum(avg_belief .* task_values);
    end
    
    % 绘制期望价值曲线
    plot(1:num_rounds, expected_value_evolution, '-o', ...
         'LineWidth', 2.5, 'MarkerSize', 6, ...
         'Color', [0.2, 0.6, 0.9], 'MarkerFaceColor', [0.2, 0.6, 0.9]);
    
    % 添加真实价值参考线
    true_value = tasks(m).value;
    yline(true_value, '--r', sprintf('真实价值=%d', true_value), ...
          'FontName', chFont, 'FontSize', 9, 'LineWidth', 2, ...
          'LabelHorizontalAlignment', 'left');
    
    % 设置坐标轴
    xlabel('游戏轮次', 'FontName', chFont, 'FontSize', 11);
    ylabel('期望价值', 'FontName', chFont, 'FontSize', 11);
    title(sprintf('任务T%d (类型%d, 真实价值=%d)', m, tasks(m).type, tasks(m).value), ...
          'FontName', chFont, 'FontSize', 12);
    grid on;
    
    % 设置y轴范围
    ylim([min(task_values)-100, max(task_values)+100]);
    
    % 在最后一个点添加数值标注
    final_expected = expected_value_evolution(end);
    text(num_rounds, final_expected, sprintf('%.1f', final_expected), ...
         'FontName', 'Times New Roman', 'FontSize', 9, ...
         'Color', [0.2, 0.6, 0.9], ...
         'HorizontalAlignment', 'left', 'VerticalAlignment', 'bottom');
    
    % 显示偏差
    bias = final_expected - true_value;
    if abs(bias) > 1
        text(num_rounds*0.5, true_value + (max(task_values)-min(task_values))*0.1, ...
             sprintf('最终偏差: %+.1f', bias), ...
             'FontName', chFont, 'FontSize', 9, ...
             'Color', [0.8, 0.2, 0.2], ...
             'HorizontalAlignment', 'center', 'BackgroundColor', [1, 1, 0.8]);
    end
    
    hold off;
end

sgtitle('各任务期望收益演化 (基于智能体平均信念)', ...
        'FontName', chFont, 'FontSize', 15, 'FontWeight', 'bold');

% 打印统计摘要
fprintf('\n========================================\n');
fprintf('     任务期望收益演化摘要\n');
fprintf('========================================\n\n');
fprintf('任务 | 真实价值 | 初始期望 | 最终期望 | 初始偏差 | 最终偏差 | 改进\n');
fprintf('-----|---------|---------|---------|---------|---------|------\n');

for m = 1:M
    % 计算初始和最终的平均期望价值
    initial_avg_belief = zeros(1, num_types);
    final_avg_belief = zeros(1, num_types);
    
    for i = 1:N
        initial_avg_belief = initial_avg_belief + history_data.rounds(1).agents(i).belief(m, :);
        final_avg_belief = final_avg_belief + history_data.rounds(num_rounds).agents(i).belief(m, :);
    end
    initial_avg_belief = initial_avg_belief / N;
    final_avg_belief = final_avg_belief / N;
    
    initial_expected = sum(initial_avg_belief .* task_values);
    final_expected = sum(final_avg_belief .* task_values);
    true_value = tasks(m).value;
    
    initial_bias = initial_expected - true_value;
    final_bias = final_expected - true_value;
    improvement = abs(initial_bias) - abs(final_bias);
    
    fprintf(' T%d  |   %4d   |  %7.1f |  %7.1f |  %+7.1f |  %+7.1f | %+6.1f\n', ...
            m, true_value, initial_expected, final_expected, ...
            initial_bias, final_bias, improvement);
end

fprintf('\n平均绝对偏差:\n');
total_initial_bias = 0;
total_final_bias = 0;
for m = 1:M
    initial_avg_belief = zeros(1, num_types);
    final_avg_belief = zeros(1, num_types);
    
    for i = 1:N
        initial_avg_belief = initial_avg_belief + history_data.rounds(1).agents(i).belief(m, :);
        final_avg_belief = final_avg_belief + history_data.rounds(num_rounds).agents(i).belief(m, :);
    end
    initial_avg_belief = initial_avg_belief / N;
    final_avg_belief = final_avg_belief / N;
    
    initial_expected = sum(initial_avg_belief .* task_values);
    final_expected = sum(final_avg_belief .* task_values);
    
    total_initial_bias = total_initial_bias + abs(initial_expected - tasks(m).value);
    total_final_bias = total_final_bias + abs(final_expected - tasks(m).value);
end

fprintf('  初始: %.1f\n', total_initial_bias / M);
fprintf('  最终: %.1f\n', total_final_bias / M);
fprintf('  改进: %.1f (%.1f%%)\n', ...
        (total_initial_bias - total_final_bias) / M, ...
        (total_initial_bias - total_final_bias) / total_initial_bias * 100);
fprintf('========================================\n\n');

end

function fontName = local_pick_chinese_font()
% 选择支持中文的字体
preferred = {'Microsoft YaHei', 'SimHei', 'SimSun', 'Microsoft JhengHei', 'Arial Unicode MS'};
available = listfonts();
fontName = 'Helvetica';
for i = 1:numel(preferred)
    if any(strcmpi(available, preferred{i}))
        fontName = preferred{i};
        return;
    end
end
end
