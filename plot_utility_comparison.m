function plot_utility_comparison(history_data, tasks, Value_Params, agents, Value_data)
% PLOT_UTILITY_COMPARISON - 对比基于期望需求和实际需求的联盟效用
%
% 输入参数：
%   history_data - 历史记录数据结构体
%   tasks - 任务信息数组
%   Value_Params - 参数结构体
%   agents - 智能体信息数组
%   Value_data - 智能体数据结构

M = Value_Params.M;
N = Value_Params.N;
num_rounds = Value_Params.num_rounds;

% 提取基于实际需求的效用数据（已存储在history_data中）
utility_actual_matrix = zeros(num_rounds, M);
for r = 1:num_rounds
    utility_actual_matrix(r, :) = history_data.rounds(r).task_utilities';
end

% 重新计算基于期望需求的效用数据
utility_expected_matrix = zeros(num_rounds, M);
for r = 1:num_rounds
    SC = history_data.rounds(r).SC;
    
    for m = 1:M
        % 找出参与该任务的智能体
        participating_agents = [];
        for i = 1:N
            if any(SC{m}(i, :) > 0)
                participating_agents = [participating_agents, i];
            end
        end
        
        % 计算基于期望需求的效用
        total_utility = 0;
        for i = participating_agents
            % 获取该轮次智能体i的信念
            agent_belief = history_data.rounds(r).agents(i).belief;
            
            % 扩展信念到M+1行（添加void任务）
            extended_belief = zeros(M+1, Value_Params.task_type);
            extended_belief(1:M, :) = agent_belief;
            
            % 使用期望需求计算效用
            individual_utility = overlap_coalition_self_utility(i, m, SC, agents, tasks, Value_Params, extended_belief);
            total_utility = total_utility + individual_utility;
        end
        
        utility_expected_matrix(r, m) = total_utility;
    end
end

% 创建图形
figure('Position', [100, 100, 1400, 800]);

% 子图1：各任务效用对比（实际 vs 期望）
subplot(2, 1, 1);
colors = lines(M);
hold on;
for m = 1:M
    % 实际需求效用（实线）
    plot(1:num_rounds, utility_actual_matrix(:, m), '-o', ...
         'LineWidth', 2, 'MarkerSize', 5, 'Color', colors(m, :), ...
         'DisplayName', sprintf('T%d-实际', m));
    
    % 期望需求效用（虚线）
    plot(1:num_rounds, utility_expected_matrix(:, m), '--^', ...
         'LineWidth', 1.5, 'MarkerSize', 4, 'Color', colors(m, :), ...
         'DisplayName', sprintf('T%d-期望', m));
end
hold off;
xlabel('迭代轮次', 'FontSize', 11, 'FontWeight', 'bold');
ylabel('联盟效用', 'FontSize', 11, 'FontWeight', 'bold');
title('联盟效用对比：实际需求 vs 期望需求', 'FontSize', 13, 'FontWeight', 'bold');
legend('Location', 'eastoutside', 'FontSize', 9, 'NumColumns', 2);
grid on;
set(gca, 'FontSize', 10);
yline(0, '--k', 'LineWidth', 1.5, 'Alpha', 0.5);

% 子图2：总效用对比
subplot(2, 1, 2);
total_actual = sum(utility_actual_matrix, 2);
total_expected = sum(utility_expected_matrix, 2);
hold on;
plot(1:num_rounds, total_actual, '-o', 'LineWidth', 2.5, 'MarkerSize', 6, ...
     'Color', [0.2, 0.6, 0.8], 'DisplayName', '总效用（实际需求）');
plot(1:num_rounds, total_expected, '--s', 'LineWidth', 2.5, 'MarkerSize', 6, ...
     'Color', [0.8, 0.4, 0.2], 'DisplayName', '总效用（期望需求）');
hold off;
xlabel('迭代轮次', 'FontSize', 11, 'FontWeight', 'bold');
ylabel('系统总效用', 'FontSize', 11, 'FontWeight', 'bold');
title('系统总效用对比', 'FontSize', 13, 'FontWeight', 'bold');
legend('Location', 'best', 'FontSize', 11);
grid on;
set(gca, 'FontSize', 10);
yline(0, '--k', 'LineWidth', 1.5, 'Alpha', 0.5);

% 打印对比摘要
fprintf('\n========================================\n');
fprintf('  效用对比摘要（实际需求 vs 期望需求）\n');
fprintf('========================================\n\n');
fprintf('任务 | 实际-初始 | 实际-最终 | 期望-初始 | 期望-最终 | 差异-初始 | 差异-最终\n');
fprintf('-----|----------|----------|----------|----------|----------|----------\n');
for m = 1:M
    actual_init = utility_actual_matrix(1, m);
    actual_final = utility_actual_matrix(end, m);
    expected_init = utility_expected_matrix(1, m);
    expected_final = utility_expected_matrix(end, m);
    diff_init = actual_init - expected_init;
    diff_final = actual_final - expected_final;
    fprintf(' T%d  |  %7.1f |  %7.1f |  %7.1f |  %7.1f |  %+7.1f |  %+7.1f\n', ...
            m, actual_init, actual_final, expected_init, expected_final, diff_init, diff_final);
end
fprintf('\n系统总效用对比：\n');
fprintf('  实际需求: 初始=%.1f, 最终=%.1f, 变化=%+.1f\n', ...
        total_actual(1), total_actual(end), total_actual(end) - total_actual(1));
fprintf('  期望需求: 初始=%.1f, 最终=%.1f, 变化=%+.1f\n', ...
        total_expected(1), total_expected(end), total_expected(end) - total_expected(1));
fprintf('  差异: 初始=%+.1f, 最终=%+.1f\n', ...
        total_actual(1) - total_expected(1), total_actual(end) - total_expected(end));
fprintf('========================================\n\n');

end
