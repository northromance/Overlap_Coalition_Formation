function plot_task_schedule_gantt(Value_data, agents, tasks, Value_Params)
% plot_task_schedule_gantt: 绘制任务执行调度甘特图
%
% 输入参数：
%   Value_data   - 智能体数据结构数组（需包含task_schedule字段）
%   agents       - 智能体结构体数组
%   tasks        - 任务结构体数组
%   Value_Params - 参数结构体
%
% 绘制内容：
%   - 横轴：时间
%   - 纵轴：智能体
%   - 每个任务用不同颜色的条形表示

    figure('Name', '任务执行调度甘特图', 'Position', [100, 100, 1200, 600]);
    
    N = Value_Params.N;
    M = Value_Params.M;
    
    % 为每个任务分配颜色
    colors = lines(M);
    
    hold on;
    
    % 找到最大完成时间用于设置x轴范围
    max_time = 0;
    
    for i = 1:N
        schedule = Value_data(i).task_schedule;
        
        if isempty(schedule.task_sequence)
            continue;
        end
        
        y_base = N - i + 1;  % 从上到下排列智能体
        bar_height = 0.6;
        
        for ii = 1:numel(schedule.task_sequence)
            task_id = schedule.task_sequence(ii);
            start_time = schedule.start_times(ii);
            exec_time = schedule.execution_times(ii);
            comp_time = schedule.completion_times(ii);
            
            % 更新最大时间
            max_time = max(max_time, comp_time);
            
            % 绘制飞行阶段（虚线）
            if ii == 1
                % 第一个任务从时间0开始飞行
                fly_start = 0;
            else
                fly_start = schedule.completion_times(ii-1);
            end
            
            % 飞行+等待阶段（浅色）
            if start_time > fly_start
                rectangle('Position', [fly_start, y_base - bar_height/4, start_time - fly_start, bar_height/2], ...
                    'FaceColor', [colors(task_id, :), 0.3], ...
                    'EdgeColor', 'none');
            end
            
            % 执行阶段（深色实心）
            rectangle('Position', [start_time, y_base - bar_height/2, exec_time, bar_height], ...
                'FaceColor', colors(task_id, :), ...
                'EdgeColor', 'k', ...
                'LineWidth', 1);
            
            % 在条形中显示任务ID
            text(start_time + exec_time/2, y_base, sprintf('T%d', task_id), ...
                'HorizontalAlignment', 'center', ...
                'VerticalAlignment', 'middle', ...
                'FontWeight', 'bold', ...
                'Color', 'w');
        end
    end
    
    % 设置坐标轴
    xlim([0, max_time * 1.1]);
    ylim([0.3, N + 0.7]);
    
    % 设置Y轴标签
    yticks(1:N);
    yticklabels(arrayfun(@(x) sprintf('Agent %d', N - x + 1), 1:N, 'UniformOutput', false));
    
    xlabel('时间', 'FontSize', 12);
    ylabel('智能体', 'FontSize', 12);
    title('任务执行调度甘特图', 'FontSize', 14);
    
    % 添加图例
    legend_handles = gobjects(M, 1);
    for m = 1:M
        legend_handles(m) = patch(NaN, NaN, colors(m, :), 'DisplayName', sprintf('任务 %d', m));
    end
    legend(legend_handles, 'Location', 'eastoutside');
    
    grid on;
    hold off;
end
