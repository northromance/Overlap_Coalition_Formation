function plot_main_results(agents, tasks, lianmengchengyuan, Value_data, N, M)
%PLOT_MAIN_RESULTS Draw coalition structure and expected revenue curves.
%
% Inputs:
%   agents, tasks              : arrays from Main
%   lianmengchengyuan          : struct array with field .member
%   Value_data                 : output from SA_Value_main
%   N, M                       : number of agents/tasks

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
        for k = 1:50
            sumprob(i, j).value(k) = Value_data(i).tasks(j).prob(k, 1) * 300 + ...
                                  Value_data(i).tasks(j).prob(k, 2) * 500 + ...
                                  Value_data(i).tasks(j).prob(k, 3) * 1000;
        end
    end
end

%% 绘制期望收益演化曲线
time = 1:4:50;
markers = {'-+', '-o', '-x', '-*', '-v', '-^', '-s', '-d', '-p', '-h'};
for j = 1:M
    figure('Name', sprintf('Task %d: Expected Revenue', j), 'NumberTitle', 'off');
    hold on;
    legendLabels = cell(1, N);
    for i = 1:N
        plot(time, sumprob(i, j).value(1:4:50), markers{mod(i - 1, length(markers)) + 1});
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
