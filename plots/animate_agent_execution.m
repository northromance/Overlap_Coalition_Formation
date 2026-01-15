function animate_agent_execution(agents, tasks, Value_data, options)
%ANIMATE_AGENT_EXECUTION 动态显示机器人执行任务过程
%   显示每个机器人从起点出发，按任务序列访问任务，最后返回起点的动画
%   左侧：地图动画  右侧：任务时间轴
%
% 输入:
%   agents    - 智能体结构体数组
%   tasks     - 任务结构体数组
%   Value_data - 包含任务调度信息的结构体数组
%   options   - 可选参数结构体:
%       .speed_factor   - 动画速度因子（默认1.0，越大越快）
%       .trail_length   - 轨迹长度（默认inf，显示全部轨迹）
%       .show_time      - 是否显示时间（默认true）
%       .save_video     - 是否保存视频（默认false）
%       .video_filename - 视频文件名（默认'agent_execution.mp4'）

    %% 参数处理
    if nargin < 4
        options = struct();
    end
    
    % 默认参数
    speed_factor = get_option(options, 'speed_factor', 1.0);
    trail_length = get_option(options, 'trail_length', inf);
    show_time = get_option(options, 'show_time', true);
    save_video = get_option(options, 'save_video', false);
    video_filename = get_option(options, 'video_filename', 'agent_execution.mp4');
    
    N = length(agents);
    M = length(tasks);
    
    %% 计算全局时间范围
    max_completion_time = 0;
    for i = 1:N
        if ~isempty(Value_data(i).task_schedule) && ...
           ~isempty(Value_data(i).task_schedule.completion_times)
            seq = Value_data(i).task_schedule.task_sequence;
            if ~isempty(seq)
                last_task = seq(end);
                last_completion = Value_data(i).task_schedule.completion_times(end);
                % 计算返回时间
                return_dist = norm([tasks(last_task).x - agents(i).x, ...
                                   tasks(last_task).y - agents(i).y]);
                return_time = return_dist / max(agents(i).vel, 1e-9);
                total_time = last_completion + return_time;
                max_completion_time = max(max_completion_time, total_time);
            end
        end
    end
    
    if max_completion_time == 0
        fprintf('警告：没有任务被分配，无法显示动画。\n');
        return;
    end
    
    %% 创建图形 - 使用更宽的窗口
    fig = figure('Name', '机器人任务执行动画', 'NumberTitle', 'off', ...
                 'Color', 'w', 'Position', [50, 50, 1400, 700]);
    
    %% 左侧：地图动画
    ax_map = subplot(1, 2, 1);
    hold on;
    axis equal;
    grid on;
    
    % 设置坐标轴范围
    all_x = [arrayfun(@(a) a.x, agents), arrayfun(@(t) t.x, tasks)];
    all_y = [arrayfun(@(a) a.y, agents), arrayfun(@(t) t.y, tasks)];
    margin = 10;
    xlim([min(all_x) - margin, max(all_x) + margin]);
    ylim([min(all_y) - margin, max(all_y) + margin]);
    
    xlabel('X轴 (m)', 'FontSize', 11);
    ylabel('Y轴 (m)', 'FontSize', 11);
    title('机器人执行路径', 'FontSize', 12);
    
    % 绘制任务点
    for j = 1:M
        plot(tasks(j).x, tasks(j).y, 'p', 'MarkerSize', 18, ...
            'MarkerFaceColor', [1 0.8 0.2], 'MarkerEdgeColor', 'k', 'LineWidth', 1.5);
        text(tasks(j).x + 3, tasks(j).y + 3, sprintf('T_{%d}', j), ...
            'FontSize', 10, 'FontWeight', 'bold', 'Interpreter', 'tex');
    end
    
    % 绘制起点和初始化动态元素
    colors = lines(N);
    agent_markers = gobjects(N, 1);
    trail_lines = gobjects(N, 1);
    trail_data = cell(N, 1);
    
    for i = 1:N
        % 起点
        plot(agents(i).x, agents(i).y, 's', 'MarkerSize', 10, ...
            'MarkerFaceColor', colors(i,:), 'MarkerEdgeColor', 'k', 'LineWidth', 1.5);
        text(agents(i).x - 5, agents(i).y - 5, sprintf('R_{%d}', i), ...
            'FontSize', 9, 'Color', colors(i,:), 'FontWeight', 'bold', 'Interpreter', 'tex');
        
        % 动态标记
        agent_markers(i) = plot(agents(i).x, agents(i).y, 'o', 'MarkerSize', 10, ...
            'MarkerFaceColor', colors(i,:), 'MarkerEdgeColor', 'w', 'LineWidth', 2);
        trail_lines(i) = plot(agents(i).x, agents(i).y, '-', 'Color', [colors(i,:) 0.5], ...
            'LineWidth', 2);
        trail_data{i} = [agents(i).x, agents(i).y];
    end
    
    % 时间显示
    if show_time
        time_text = text(min(all_x) - margin + 5, max(all_y) + margin - 5, ...
            't = 0.0 s', 'FontSize', 11, 'FontWeight', 'bold');
    end
    
    %% 右侧：任务时间轴面板
    ax_timeline = subplot(1, 2, 2);
    hold on;
    
    % 预计算每个智能体的路径和时间轴数据
    agent_paths = cell(N, 1);
    agent_times = cell(N, 1);
    timeline_data = cell(N, 1);  % 存储时间轴绘图数据
    
    for i = 1:N
        [path_points, time_points] = compute_agent_path(agents(i), tasks, Value_data(i));
        agent_paths{i} = path_points;
        agent_times{i} = time_points;
        timeline_data{i} = compute_timeline_data(agents(i), tasks, Value_data(i), max_completion_time);
    end
    
    % 绘制时间轴背景
    bar_height = 0.6;
    row_spacing = 1.2;
    timeline_indicators = gobjects(N, 1);  % 时间指示线
    phase_highlights = cell(N, 1);         % 当前阶段高亮
    
    for i = 1:N
        y_pos = (N - i) * row_spacing;
        
        % 绘制机器人标签
        text(-max_completion_time * 0.08, y_pos, sprintf('R_{%d}', i), ...
            'FontSize', 11, 'FontWeight', 'bold', 'Color', colors(i,:), ...
            'HorizontalAlignment', 'right', 'Interpreter', 'tex');
        
        % 绘制时间轴基线
        plot([0, max_completion_time], [y_pos - bar_height/2, y_pos - bar_height/2], ...
            'Color', [0.8 0.8 0.8], 'LineWidth', 1);
        
        % 绘制任务方框
        tdata = timeline_data{i};
        for k = 1:length(tdata.phases)
            phase = tdata.phases(k);
            x_start = phase.start_time;
            x_width = phase.end_time - phase.start_time;
            
            if x_width > 0
                % 根据阶段类型设置颜色
                if strcmp(phase.type, 'travel')
                    face_color = [0.9 0.9 0.9];  % 灰色 - 移动
                    edge_color = colors(i,:);
                elseif strcmp(phase.type, 'execute')
                    face_color = [colors(i,:) * 0.3 + 0.7];  % 浅色 - 执行
                    edge_color = colors(i,:);
                else  % return
                    face_color = [0.95 0.95 0.95];
                    edge_color = [0.5 0.5 0.5];
                end
                
                rectangle('Position', [x_start, y_pos - bar_height/2, x_width, bar_height], ...
                    'FaceColor', face_color, 'EdgeColor', edge_color, 'LineWidth', 1.5);
                
                % 任务标签
                if ~isempty(phase.task_id) && x_width > max_completion_time * 0.03
                    text(x_start + x_width/2, y_pos, sprintf('T_{%d}', phase.task_id), ...
                        'FontSize', 9, 'HorizontalAlignment', 'center', ...
                        'VerticalAlignment', 'middle', 'Interpreter', 'tex');
                end
            end
        end
        
        % 当前阶段高亮框（初始隐藏）
        phase_highlights{i} = rectangle('Position', [0, y_pos - bar_height/2, 0.1, bar_height], ...
            'FaceColor', 'none', 'EdgeColor', 'r', 'LineWidth', 2.5, 'Visible', 'off');
    end
    
    % 时间指示竖线
    time_indicator_line = plot([0, 0], [-0.5, N * row_spacing - 0.3], ...
        'r-', 'LineWidth', 2);
    
    % 设置时间轴坐标
    xlim([-max_completion_time * 0.12, max_completion_time * 1.05]);
    ylim([-0.8, N * row_spacing - 0.2]);
    xlabel('时间 (s)', 'FontSize', 11);
    title('任务执行时间轴', 'FontSize', 12);
    set(ax_timeline, 'YTick', []);
    grid on;
    ax_timeline.XGrid = 'on';
    ax_timeline.YGrid = 'off';
    
    % 图例
    legend_h = gobjects(3, 1);
    legend_h(1) = patch([0 1 1 0], [0 0 1 1], [0.9 0.9 0.9], 'EdgeColor', 'k');
    legend_h(2) = patch([0 1 1 0], [0 0 1 1], [0.85 0.85 1], 'EdgeColor', 'b');
    legend_h(3) = patch([0 1 1 0], [0 0 1 1], [0.95 0.95 0.95], 'EdgeColor', [0.5 0.5 0.5]);
    set(legend_h, 'Visible', 'off');
    legend(legend_h, {'移动中', '执行任务', '返回起点'}, ...
        'Location', 'northeast', 'FontSize', 9);
    
    %% 视频设置
    if save_video
        v = VideoWriter(video_filename, 'MPEG-4');
        v.FrameRate = 30;
        open(v);
    end
    
    %% 动画主循环
    dt = 0.5 / speed_factor;
    frame_pause = 0.03 / speed_factor;
    
    t = 0;
    while t <= max_completion_time
        % 更新左侧地图
        for i = 1:N
            pos = interpolate_position(t, agent_paths{i}, agent_times{i});
            set(agent_markers(i), 'XData', pos(1), 'YData', pos(2));
            
            trail_data{i} = [trail_data{i}; pos];
            if ~isinf(trail_length) && size(trail_data{i}, 1) > trail_length
                trail_data{i} = trail_data{i}(end-trail_length+1:end, :);
            end
            set(trail_lines(i), 'XData', trail_data{i}(:,1), 'YData', trail_data{i}(:,2));
        end
        
        % 更新时间显示
        if show_time
            set(time_text, 'String', sprintf('t = %.1f s', t));
        end
        
        % 更新右侧时间轴
        set(time_indicator_line, 'XData', [t, t]);
        
        % 更新当前阶段高亮
        for i = 1:N
            y_pos = (N - i) * row_spacing;
            tdata = timeline_data{i};
            current_phase = [];
            
            for k = 1:length(tdata.phases)
                phase = tdata.phases(k);
                if t >= phase.start_time && t <= phase.end_time
                    current_phase = phase;
                    break;
                end
            end
            
            if ~isempty(current_phase)
                set(phase_highlights{i}, 'Position', ...
                    [current_phase.start_time, y_pos - bar_height/2, ...
                     current_phase.end_time - current_phase.start_time, bar_height], ...
                    'Visible', 'on');
            else
                set(phase_highlights{i}, 'Visible', 'off');
            end
        end
        
        drawnow;
        
        if save_video
            frame = getframe(fig);
            writeVideo(v, frame);
        end
        
        pause(frame_pause);
        t = t + dt;
    end
    
    %% 最终状态
    for i = 1:N
        set(agent_markers(i), 'XData', agents(i).x, 'YData', agents(i).y);
        set(phase_highlights{i}, 'Visible', 'off');
    end
    
    if show_time
        set(time_text, 'String', sprintf('t = %.1f s (完成)', max_completion_time));
    end
    
    set(time_indicator_line, 'XData', [max_completion_time, max_completion_time]);
    
    axes(ax_map);
    title('机器人执行路径 - 完成', 'FontSize', 12);
    
    if save_video
        close(v);
        fprintf('视频已保存: %s\n', video_filename);
    end
    
    fprintf('动画播放完成。总时间: %.1f s\n', max_completion_time);
end

%% 辅助函数：获取选项值
function val = get_option(options, field, default)
    if isfield(options, field)
        val = options.(field);
    else
        val = default;
    end
end

%% 辅助函数：计算时间轴数据
function tdata = compute_timeline_data(agent, tasks, value_data, max_time)
    tdata.phases = [];
    
    if isempty(value_data.task_schedule) || ...
       isempty(value_data.task_schedule.task_sequence)
        return;
    end
    
    seq = value_data.task_schedule.task_sequence;
    arrival_times = value_data.task_schedule.arrival_times;
    start_times = value_data.task_schedule.start_times;
    completion_times = value_data.task_schedule.completion_times;
    
    vel = max(agent.vel, 1e-9);
    start_pos = [agent.x, agent.y];
    current_pos = start_pos;
    current_time = 0;
    
    for k = 1:length(seq)
        task_id = seq(k);
        task_pos = [tasks(task_id).x, tasks(task_id).y];
        
        % 移动阶段
        travel_time = norm(task_pos - current_pos) / vel;
        if k <= length(arrival_times) && arrival_times(k) > 0
            arrival = arrival_times(k);
        else
            arrival = current_time + travel_time;
        end
        
        if arrival > current_time
            phase.type = 'travel';
            phase.start_time = current_time;
            phase.end_time = arrival;
            phase.task_id = task_id;
            tdata.phases = [tdata.phases, phase];
        end
        
        % 执行阶段
        if k <= length(start_times) && k <= length(completion_times)
            exec_start = max(arrival, start_times(k));
            exec_end = completion_times(k);
            
            if exec_end > exec_start
                phase.type = 'execute';
                phase.start_time = exec_start;
                phase.end_time = exec_end;
                phase.task_id = task_id;
                tdata.phases = [tdata.phases, phase];
            end
            current_time = exec_end;
        else
            current_time = arrival;
        end
        
        current_pos = task_pos;
    end
    
    % 返回起点阶段
    return_time = norm(start_pos - current_pos) / vel;
    if return_time > 0
        phase.type = 'return';
        phase.start_time = current_time;
        phase.end_time = current_time + return_time;
        phase.task_id = [];
        tdata.phases = [tdata.phases, phase];
    end
end

%% 辅助函数：计算智能体完整路径
function [path_points, time_points] = compute_agent_path(agent, tasks, value_data)
    % 起点
    start_pos = [agent.x, agent.y];
    path_points = start_pos;
    time_points = 0;
    
    if isempty(value_data.task_schedule) || ...
       isempty(value_data.task_schedule.task_sequence)
        return;
    end
    
    seq = value_data.task_schedule.task_sequence;
    arrival_times = value_data.task_schedule.arrival_times;
    completion_times = value_data.task_schedule.completion_times;
    
    vel = max(agent.vel, 1e-9);
    
    current_pos = start_pos;
    current_time = 0;
    
    for k = 1:length(seq)
        task_id = seq(k);
        task_pos = [tasks(task_id).x, tasks(task_id).y];
        
        % 到达任务点的时间
        travel_time = norm(task_pos - current_pos) / vel;
        arrival_time = current_time + travel_time;
        
        % 使用调度中的到达时间（如果有）
        if k <= length(arrival_times) && arrival_times(k) > 0
            actual_arrival = arrival_times(k);
        else
            actual_arrival = arrival_time;
        end
        
        % 添加到达点
        path_points = [path_points; task_pos];
        time_points = [time_points; actual_arrival];
        
        % 添加完成点（如果有等待或执行时间）
        if k <= length(completion_times)
            path_points = [path_points; task_pos];
            time_points = [time_points; completion_times(k)];
            current_time = completion_times(k);
        else
            current_time = actual_arrival;
        end
        
        current_pos = task_pos;
    end
    
    % 返回起点
    return_time = norm(start_pos - current_pos) / vel;
    path_points = [path_points; start_pos];
    time_points = [time_points; current_time + return_time];
end

%% 辅助函数：插值计算位置
function pos = interpolate_position(t, path_points, time_points)
    if isempty(time_points) || t <= time_points(1)
        pos = path_points(1, :);
        return;
    end
    
    if t >= time_points(end)
        pos = path_points(end, :);
        return;
    end
    
    % 找到当前时间段
    idx = find(time_points <= t, 1, 'last');
    
    if idx >= length(time_points)
        pos = path_points(end, :);
        return;
    end
    
    % 线性插值
    t1 = time_points(idx);
    t2 = time_points(idx + 1);
    p1 = path_points(idx, :);
    p2 = path_points(idx + 1, :);
    
    if t2 - t1 < 1e-9
        pos = p2;
    else
        alpha = (t - t1) / (t2 - t1);
        pos = p1 + alpha * (p2 - p1);
    end
end
