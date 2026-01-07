function plot_coalition_utility_evolution(history_data, tasks, Value_Params)
% PLOT_COALITION_UTILITY_EVOLUTION - 绘制每个任务的联盟效用随迭代轮次的变化
%
% 输入参数：
%   history_data - 历史记录数据结构体
%   tasks - 任务信息数组
%   Value_Params - 参数结构体

M = Value_Params.M;
num_rounds = Value_Params.num_rounds;

% 提取所有轮次的任务效用数据
utility_matrix = zeros(num_rounds, M);
for r = 1:num_rounds
    utility_matrix(r, :) = history_data.rounds(r).task_utilities';
end

% 创建图形
figure('Position', [100, 100, 1200, 600]);

% 设置颜色映射（为不同任务分配不同颜色）
colors = lines(M);

% 绘制每个任务的效用演化曲线
hold on;
for m = 1:M
    plot(1:num_rounds, utility_matrix(:, m), '-o', ...
         'LineWidth', 2, ...
         'MarkerSize', 6, ...
         'Color', colors(m, :), ...
         'DisplayName', sprintf('任务T%d (类型%d, 价值%d)', ...
                                m, tasks(m).type, tasks(m).value));
end
hold off;

% 设置图形属性
xlabel('迭代轮次', 'FontSize', 12, 'FontWeight', 'bold');
ylabel('联盟效用', 'FontSize', 12, 'FontWeight', 'bold');
title('各任务重叠联盟效用随迭代轮次的演化', 'FontSize', 14, 'FontWeight', 'bold');
legend('Location', 'eastoutside', 'FontSize', 10);
grid on;
set(gca, 'FontSize', 11);

% 设置X轴刻度
xticks(1:max(1, floor(num_rounds/10)):num_rounds);

% 添加零基准线
yline(0, '--k', 'LineWidth', 1.5, 'Alpha', 0.5);

% 调整布局
box on;

% 打印最终效用摘要
fprintf('\n========================================\n');
fprintf('     最终联盟效用摘要\n');
fprintf('========================================\n\n');
fprintf('任务 | 类型 | 价值 | 初始效用 | 最终效用 | 效用变化\n');
fprintf('-----|------|------|---------|---------|--------\n');
for m = 1:M
    initial_utility = utility_matrix(1, m);
    final_utility = utility_matrix(end, m);
    delta_utility = final_utility - initial_utility;
    fprintf(' T%d  |  %d   | %4d | %8.1f | %8.1f | %+8.1f\n', ...
            m, tasks(m).type, tasks(m).value, ...
            initial_utility, final_utility, delta_utility);
end
fprintf('\n总效用: 初始=%.1f, 最终=%.1f, 变化=%+.1f\n', ...
        sum(utility_matrix(1, :)), sum(utility_matrix(end, :)), ...
        sum(utility_matrix(end, :)) - sum(utility_matrix(1, :)));
fprintf('========================================\n\n');

end
