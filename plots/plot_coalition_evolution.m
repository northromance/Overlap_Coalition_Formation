function plot_coalition_evolution(history_data, tasks, Value_Params)
%PLOT_COALITION_EVOLUTION 绘制任务完成度演化图（基于D_C）
%
% 输入参数：
%   history_data  - 历史记录结构体（包含每轮的task_completion）
%   tasks         - 任务数组
%   Value_Params  - 参数结构体（包含N, M, K, num_rounds等）

N = Value_Params.N;  % 智能体数量
M = Value_Params.M;  % 任务数量
K = Value_Params.K;  % 资源类型数量
num_rounds = Value_Params.num_rounds;  % 总轮数

chFont = local_pick_chinese_font();

%% 绘制任务完成度演化图（基于D_C）
figure('Name', '任务完成度演化', 'NumberTitle', 'off', 'Position', [100, 100, 1400, 800]);

% 为每个任务创建一个子图
for m = 1:M
    subplot(ceil(M/3), 3, m);
    hold on;
    
    % 提取每轮该任务的完成度D_C
    task_completion = zeros(num_rounds, 1);
    for round = 1:num_rounds
        if isfield(history_data.rounds(round), 'task_completion')
            task_completion(round) = history_data.rounds(round).task_completion(m);
        end
    end
    
    % 绘制完成度曲线（转换为百分比）
    plot(1:num_rounds, task_completion * 100, '-o', 'LineWidth', 2.5, 'MarkerSize', 6, ...
         'Color', [0.2 0.6 0.9], 'MarkerFaceColor', [0.2 0.6 0.9]);
    
    % 添加参考线
    yline(100, '--r', '目标完成度', 'FontName', chFont, 'FontSize', 9, 'LineWidth', 1.5);
    
    % 设置坐标轴
    xlabel('游戏轮次', 'FontName', chFont, 'FontSize', 11);
    ylabel('任务完成度 D_C (%)', 'FontName', chFont, 'FontSize', 11);
    title(sprintf('任务T%d (类型%d, 价值=%d)', m, tasks(m).type, tasks(m).value), ...
          'FontName', chFont, 'FontSize', 12);
    grid on;
    ylim([0, 120]);
    
    % 在最后一个点添加数值标注
    if task_completion(end) > 0
        text(num_rounds, task_completion(end)*100, sprintf('%.1f%%', task_completion(end)*100), ...
             'FontName', 'Times New Roman', 'FontSize', 9, 'Color', [0.8 0.2 0.2], ...
             'HorizontalAlignment', 'left', 'VerticalAlignment', 'bottom');
    end
    
    hold off;
end

sgtitle('任务完成度演化 (基于联盟资源分配D_C)', 'FontName', chFont, 'FontSize', 15, 'FontWeight', 'bold');

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
