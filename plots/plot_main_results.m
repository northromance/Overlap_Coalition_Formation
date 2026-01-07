function plot_main_results(agents, tasks, lianmengchengyuan, history_data, N, M, num_rounds, task_values)
%PLOT_MAIN_RESULTS Draw coalition structure and expected revenue curves.
%
% Inputs:
%   agents, tasks              : arrays from Main
%   lianmengchengyuan          : struct array with field .member
%   history_data               : history data from SA_Value_main
%   N, M                       : number of agents/tasks
%   num_rounds                 : total game rounds
%   task_values                : vector of task values [low, medium, high]

chFont = local_pick_chinese_font();

%% 绘制联盟结构图
figure('Name', 'Coalition Structure', 'NumberTitle', 'off');
PlotValue(agents, tasks, lianmengchengyuan);
axis([0, 100, 0, 100]);
xlabel('x-axis (m)', 'FontName', 'Times New Roman', 'FontSize', 14);
ylabel('y-axis (m)', 'FontName', 'Times New Roman', 'FontSize', 14);
grid on;
title('联盟结构图 (Coalition Structure)', 'FontName', chFont, 'FontSize', 14);

%% 计算期望任务收益
sumprob = struct();
for i = 1:N
    for j = 1:M
        for k = 1:num_rounds
            % 从history_data.rounds按轮读取信念概率
            belief_probs = history_data.rounds(k).agents(i).belief(j, :);
            sumprob(i, j).value(k) = belief_probs(1) * task_values(1) + ...
                                     belief_probs(2) * task_values(2) + ...
                                     belief_probs(3) * task_values(3);
        end
    end
end

%% 绘制期望收益演化曲线
plot_interval = max(1, floor(num_rounds / 12));  % 自动确定绘图间隔，保持图表清晰
time = 1:plot_interval:num_rounds;
markers = {'-+', '-o', '-x', '-*', '-v', '-^', '-s', '-d', '-p', '-h'};
for j = 1:M
    figure('Name', sprintf('Task %d: Expected Revenue', j), 'NumberTitle', 'off');
    hold on;
    legendLabels = cell(1, N);
    for i = 1:N
        plot(time, sumprob(i, j).value(1:plot_interval:num_rounds), markers{mod(i - 1, length(markers)) + 1});
        legendLabels{i} = sprintf('$r_{%d}$', i);
    end
    hold off;

    h = legend(legendLabels);
    set(h, 'Interpreter', 'latex', 'FontName', 'Times New Roman', 'FontSize', 12, 'FontWeight', 'normal');
    xlabel('Index of game', 'FontName', 'Times New Roman', 'FontSize', 14);
    ylabel('Expected task revenue', 'FontName', 'Times New Roman', 'FontSize', 14);
    grid on;
    title(sprintf('任务%d：期望收益演化 (Expected Revenue)', j), 'FontName', chFont, 'FontSize', 14);
end

end

function fontName = local_pick_chinese_font()
% Pick a Windows-available font that can render Chinese.
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
