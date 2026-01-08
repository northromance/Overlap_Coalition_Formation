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
            
            % 绘制飞行阶段（飞行：浅灰色框）
            if ii == 1
                fly_start = 0;
            else
                fly_start = schedule.completion_times(ii-1);
            end
            
            % 获取到达时间 (等待开始时间)
            if isfield(schedule, 'arrival_times')
                arr_time = schedule.arrival_times(ii);
            else
                % 兼容旧数据: 如果没有arrival_times，假设没有等待，到达=开始
                arr_time = start_time;
            end
            
            % 绘制纯飞行阶段 (灰色虚线，非常细)
            if arr_time > fly_start + 1e-4
                % 使用细线连接
                plot([fly_start, arr_time], [y_base, y_base], ...
                    'Color', [0.6, 0.6, 0.6], 'LineStyle', '--', 'LineWidth', 1.5);
            end
            
            % 绘制等待阶段 (统一使用浅红色)
            % 只有当等待时间显著(>0.1s)时才绘制，避免视觉干扰
            if start_time > arr_time + 0.1
                rectangle('Position', [arr_time, y_base - bar_height/3, start_time - arr_time, bar_height*2/3], ...
                    'FaceColor', [1.0, 0.6, 0.6], ... % 浅红色
                    'EdgeColor', 'none');
                
                % 如果等待时间较长，标注 "Wait"
                if start_time - arr_time > max_time * 0.05
                    text((arr_time + start_time)/2, y_base, 'Wait', ...
                        'HorizontalAlignment', 'center', ...
                        'VerticalAlignment', 'middle', ...
                        'FontSize', 8, 'Color', 'k');
                end
            end
            
            % 执行阶段（任务色实心，高度略大）
            % 为防止执行时间极短导致显示为细线，设置一个可视化的最小宽度
            % 仅用于绘图显示，不改变逻辑数据
            min_width = max(max_time * 0.015, 0.5); 
            draw_width = max(exec_time, min_width);
            
            rectangle('Position', [start_time, y_base - bar_height/2, draw_width, bar_height], ...
                'FaceColor', colors(task_id, :), ...
                'EdgeColor', 'k', ...
                'LineWidth', 1);
            
            % 在条形中显示任务ID
            % 只有当宽度足够时才显示文字
            if draw_width > max_time * 0.03 || draw_width > 2.0
                text(start_time + draw_width/2, y_base, sprintf('T%d', task_id), ...
                    'HorizontalAlignment', 'center', ...
                    'VerticalAlignment', 'middle', ...
                    'FontWeight', 'bold', ...
                    'Color', 'w');
            end
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
