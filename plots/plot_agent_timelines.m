function plot_agent_timelines(Value_data, agents, tasks, Value_Params)
% plot_agent_timelines: 绘制每个智能体的独立时间线视图
%
% 将所有智能体垂直排列，每个智能体占用一个子图（Subplot），
% 清晰展示其：[飞行/移动] -> [到达/等待] -> [执行] -> [完成] 的全过程，
% 并标注关键时间点（到达、开始、完成）。

    N = Value_Params.N;
    M = Value_Params.M;
    colors = lines(M); % 任务颜色映射
    
    % 创建一个大窗口
    figure('Name', '各智能体任务执行时间线详情', 'Color', 'w', ...
           'Units', 'normalized', 'Position', [0.1, 0.05, 0.5, 0.9]); 
    
    % 计算合适的子图布局 (例如 8个智能体就是 8行1列)
    rows = N;
    cols = 1;
    
    % 寻找全局最大时间，用于统一X轴刻度
    max_global_time = 0;
    for i = 1:N
        sched = Value_data(i).task_schedule;
        if ~isempty(sched.task_sequence)
            max_global_time = max(max_global_time, max(sched.completion_times));
        end
    end
    if max_global_time == 0
        max_global_time = 10; % 默认值防止报错
    end
    
    for i = 1:N
        % 创建子图
        subplot(rows, cols, i);
        hold on;
        
        schedule = Value_data(i).task_schedule;
        
        % 绘制一条中心轴线
        plot([0, max_global_time*1.1], [0, 0], 'k-', 'LineWidth', 0.5, 'Color', [0.8 0.8 0.8]);
        
        if isempty(schedule.task_sequence)
            text(max_global_time/2, 0, 'No Tasks Assigned', ...
                'HorizontalAlignment', 'center', 'Color', [0.5 0.5 0.5], 'FontAngle', 'italic');
        else
            % 遍历任务序列
            for k = 1:numel(schedule.task_sequence)
                tid = schedule.task_sequence(k);
                
                % 获取时间点
                t_comp_prev = 0; 
                if k > 1
                    t_comp_prev = schedule.completion_times(k-1);
                end
                
                t_arr = schedule.arrival_times(k);   % 到达时刻
                t_start = schedule.start_times(k);   % 开始时刻
                t_exec = schedule.execution_times(k);% 执行时长
                t_comp = schedule.completion_times(k); % 完成时刻
                
                % 1. 绘制飞行阶段 (上一任务完成 -> 到达)
                % 用灰色虚线箭头表示
                if t_arr > t_comp_prev + 1e-4
                    quiver(t_comp_prev, 0, t_arr - t_comp_prev, 0, 0, ...
                        'Color', [0.6 0.6 0.6], 'LineStyle', '--', 'MaxHeadSize', 0.5, 'LineWidth', 1);
                end
                
                % 2. 绘制等待阶段 (到达 -> 开始)
                if t_start > t_arr + 0.1
                    w = t_start - t_arr;
                    % 画红色条
                    rectangle('Position', [t_arr, -0.2, w, 0.4], ...
                        'FaceColor', [1.0, 0.8, 0.8], 'EdgeColor', 'none'); % 浅红
                    
                    % 标注到达时间 (垂直线 + 文字)
                    plot([t_arr, t_arr], [-0.5, 0.5], 'r:', 'LineWidth', 0.5);
                    text(t_arr, -0.6, sprintf('Arr:%.1f', t_arr), ...
                        'Rotation', 45, 'FontSize', 7, 'Color', 'r');
                else
                    % 如果没有等待，到达即开始，也标一下到达
                    plot([t_arr, t_arr], [-0.3, 0.3], 'k:', 'LineWidth', 0.5);
                    text(t_arr, -0.6, sprintf('%.1f', t_arr), ...
                        'Rotation', 45, 'FontSize', 7, 'Color', [0.4 0.4 0.4]);
                end
                
                % 3. 绘制执行阶段 (开始 -> 完成)
                % 最小可视宽度
                vis_w = max(t_exec, max_global_time * 0.02);
                rectangle('Position', [t_start, -0.4, vis_w, 0.8], ...
                    'FaceColor', colors(tid, :), 'EdgeColor', 'k');
                
                % 任务标签
                text(t_start + vis_w/2, 0, sprintf('T%d', tid), ...
                    'HorizontalAlignment', 'center', 'Color', 'w', 'FontWeight', 'bold', 'FontSize', 9);
                
                % 4. 标注完成时间
                % text(t_comp, 0.6, sprintf('End:%.1f', t_comp), ...
                %    'Rotation', 45, 'FontSize', 7, 'Color', [0 0.5 0]);
            end
        end
        
        % 设置坐标轴样式
        title(sprintf('Agent %d', i), 'FontSize', 10, 'FontWeight', 'bold', 'Units', 'normalized', 'Position', [0.01, 0.8], 'HorizontalAlignment', 'left');
        yticks([]);
        xlim([0, max_global_time * 1.15]);
        
        % 只在最后一张图显示X轴标签
        if i == N
            xlabel('Time (s)');
        else
            set(gca, 'XTickLabel', []);
        end
        
        box off;
        set(gca, 'YColor', 'none'); % 隐藏Y轴线
    end
end