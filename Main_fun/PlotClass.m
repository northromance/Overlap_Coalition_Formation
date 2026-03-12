classdef PlotClass
    % PlotClass 用于存储项目中的绘图函数
    % 包括结果展示图、环境地图、执行动态展示以及算法对比图
    
    methods(Static)
        function plot_SA_allocation(Value_data, tasks, Value_Params, varargin)
            % plot_SA_allocation 绘制 SA 算法资源分配详情柱状图
            
            alg_display_name = 'SA_Value';
            if ~isempty(varargin) && ~isempty(varargin{1})
                alg_display_name = char(varargin{1});
            end
            fprintf('正在绘制 %s 资源分配详情图...\n', alg_display_name);
            
            % 1. 读取数据
            SC = Value_data(1).SC; 
            
            N = Value_Params.N;
            M = Value_Params.M;
            K = Value_Params.K;
            
            % 2. 创建图窗
            figure('Name', sprintf('%s Resource Allocation Detail', alg_display_name), ...
                   'NumberTitle', 'off', 'Color', 'w', ...
                   'Position', [100, 100, 1200, 800]);
            
            rows = ceil(sqrt(M));
            cols = ceil(M / rows);
            agent_colors = lines(N); 
            
            for m = 1:M
                subplot(rows, cols, m);
                hold on;
                allocation_data = SC{m}'; 
                b = bar(1:K, allocation_data, 'stacked', 'FaceColor', 'flat');
                for k = 1:K
                    for n = 1:N
                        b(n).CData = agent_colors(n, :);
                    end
                end
                demand = tasks(m).resource_demand; 
                plot(1:K, demand, 'r-o', 'LineWidth', 1.5, ...
                    'MarkerFaceColor', 'w', 'MarkerSize', 4);
                title(sprintf('Task %d  Val:%.0f  Pri:%d', m, tasks(m).value, tasks(m).priority), 'FontSize', 10);
                if m > (rows-1)*cols, xlabel('Resource Type'); end
                if mod(m-1, cols) == 0, ylabel('Amount'); end
                grid on; box on;
                max_val = max(max(sum(allocation_data, 2)), max(demand));
                ylim([0, max_val * 1.2 + 0.1]); 
                xticks(1:K);
                if m == 1
                    legend_str = arrayfun(@(x) sprintf('Agent %d', x), 1:N, 'UniformOutput', false);
                    legend_str{end+1} = 'Demand';
                    legend([b, findobj(gca, 'Type', 'line')], legend_str, ...
                           'Location', 'bestoutside', 'FontSize', 8, 'NumColumns', 1);
                end
                hold off;
            end
            sgtitle(sprintf('Resource Allocation Breakdown by Task (%s Algorithm)', alg_display_name), 'Interpreter', 'none');
        end

        function print_agent_capabilities(agents)
            % print_agent_capabilities 在命令行打印各智能体的初始资源能力
            
            fprintf('\n=================================================\n');
            fprintf('          Agent Resource Capabilities\n');
            fprintf('          智能体资源能力清单\n');
            fprintf('=================================================\n');
            if isempty(agents)
                fprintf('No agents found.\n');
                return;
            end
            K = length(agents(1).resources);
            header_str = sprintf(' %4s ', 'R');
            for k = 1:K
                header_str = [header_str, sprintf('  Type%d', k)];
            end
            fprintf('Agent ID |%s\n', header_str);
            fprintf('%s\n', repmat('-', 1, 10 + 7*K));
            for i = 1:length(agents)
                % [关键修复] 每次循环前初始化一次字符串
                res_str = ''; 
                for k = 1:K
                    res_str = [res_str, sprintf('%6d ', agents(i).resources(k))];
                end
                fprintf('   %3d   |%s\n', agents(i).id, res_str);
            end
            fprintf('=================================================\n\n');
        end

        function plot_env(agents, tasks, Value_Params)
            % plot_env 绘制环境地图，显示智能体初始位置和任务位置
            figure('Name', 'Environment Map', 'Color', 'w');
            hold on; grid on; box on;
            task_coords = zeros(length(tasks), 2);
            for t = 1:length(tasks)
                if isfield(tasks, 'loc') && numel(tasks(t).loc) >= 2
                    task_coords(t, :) = tasks(t).loc(1:2);
                elseif isfield(tasks, 'x') && isfield(tasks, 'y')
                    task_coords(t, :) = [tasks(t).x, tasks(t).y];
                else
                    error('tasks 缺少坐标字段 loc 或 x/y，无法绘制环境图');
                end
            end
            if ~isempty(task_coords)
                scatter(task_coords(:,1), task_coords(:,2), 50, 'b', 'filled', ...
                    'MarkerEdgeColor', 'k', 'DisplayName', 'Tasks');
                text(task_coords(:,1)+0.5, task_coords(:,2)+0.5, ...
                    arrayfun(@(x) sprintf('T%d', x), 1:length(tasks), 'UniformOutput', false), ...
                    'FontSize', 8);
            end
            agent_coords = zeros(length(agents), 2);
            for i = 1:length(agents)
                agent_coords(i, :) = [agents(i).x, agents(i).y];
            end
            scatter(agent_coords(:,1), agent_coords(:,2), 60, 'r', 's', 'filled', ...
                 'MarkerEdgeColor', 'k', 'DisplayName', 'Agents Start');
            xlabel('X Coordinate (km)');
            ylabel('Y Coordinate (km)');
            title('Multi-Agent Environment Map');
            legend('Location', 'bestoutside');
            all_coords = [task_coords; agent_coords];
            if ~isempty(all_coords)
                xlim([min(all_coords(:,1))-5, max(all_coords(:,1))+5]);
                ylim([min(all_coords(:,2))-5, max(all_coords(:,2))+5]);
            end
            axis equal;
            hold off;
        end
        
        function plot_execution_animation(Value_data, agents, tasks, Value_Params, varargin)
            % plot_execution_animation 动态展示算法执行结果
            % 左图显示空间路径，右图显示甘特图时间进度
            
            fprintf('正在准备动态执行演示图...\n');
            
            N = Value_Params.N;
            
            % --- 0. 读取每个智能体的初始位置 ---
            agent_start_pos = zeros(N, 2);
            for i = 1:N
                agent_start_pos(i, :) = [agents(i).x, agents(i).y];
            end

            % --- 1. 数据预处理 ---
            max_time = 0;
            agent_schedules = cell(N, 1); 
            agent_mission_ends = zeros(N, 1); 
            
            % 确保任务坐标读取正确
            task_locs = zeros(length(tasks), 2);
            for m = 1:length(tasks)
                if isfield(tasks, 'loc') && ~isempty(tasks(m).loc)
                    task_locs(m,:) = tasks(m).loc;
                else
                    task_locs(m,:) = [tasks(m).x, tasks(m).y];
                end
            end
            
            for i = 1:N
                if ~isfield(Value_data(i), 'task_schedule') || isempty(Value_data(i).task_schedule)
                    agent_schedules{i} = struct('task_id', {}, 'start_t', {}, 'finish_t', {}, 'loc', {});
                    agent_mission_ends(i) = 0;
                    continue; 
                end
                
                ts = Value_data(i).task_schedule;
                n_tasks = length(ts.task_sequence);
                schedule = struct('task_id', {}, 'start_t', {}, 'finish_t', {}, 'loc', {});
                
                if n_tasks > 0
                    if isempty(ts.completion_times)
                         agent_schedules{i} = schedule;
                         continue; 
                    end
                    
                    for j = 1:n_tasks
                        tid = ts.task_sequence(j);
                        schedule(j).task_id = tid;
                        schedule(j).start_t = ts.start_times(j);
                        schedule(j).finish_t = ts.completion_times(j);
                        schedule(j).loc = task_locs(tid, :);
                    end
                    
                    mission_end = ts.mission_end_time;
                    agent_mission_ends(i) = mission_end;
                    max_time = max(max_time, mission_end);
                else
                    agent_mission_ends(i) = 0;
                end
                agent_schedules{i} = schedule;
            end
            
            if max_time == 0
                warning('没有任务被分配，执行时间为 0，无法生成动画。');
                return;
            end
            
            % --- 2. 初始化图形界面 ---
            fig_anim = figure('Name', 'Dynamic Execution Output', 'Color', 'w', ...
                'Position', [100, 100, 1400, 700]); 
            
            % 颜色定义
            agent_colors = lines(N);
            color_future = [0.9 0.9 0.9]; % 浅灰色
            color_wait   = [1 1 0];       % 黄色（等待中）
            color_active = [0 1 0];       % 绿色（执行中）
            
            % --- 左侧：地图视图初始化 ---
            ax_map = subplot(1, 2, 1);
            hold(ax_map, 'on'); grid(ax_map, 'on'); box(ax_map, 'on');
            title(ax_map, 'Agent Trajectories (Map View)');
            xlabel(ax_map, 'X (km)'); ylabel(ax_map, 'Y (km)');
            
            scatter(ax_map, task_locs(:,1), task_locs(:,2), 40, 'b', 'filled', 'MarkerEdgeColor', 'k');
            text(ax_map, task_locs(:,1)+1, task_locs(:,2)+1, arrayfun(@(x) sprintf('T%d', x), 1:length(tasks), 'UniformOutput', false), 'FontSize', 8);
            plot(ax_map, agent_start_pos(:,1), agent_start_pos(:,2), 's', ...
                'MarkerSize', 8, 'MarkerEdgeColor', 'r', 'LineWidth', 1);
            
            all_coords = [task_locs; agent_start_pos];
            margin = 10;
            xlim(ax_map, [min(all_coords(:,1))-margin, max(all_coords(:,1))+margin]);
            ylim(ax_map, [min(all_coords(:,2))-margin, max(all_coords(:,2))+margin]);
            axis(ax_map, 'equal');
            
            h_agents_marker = gobjects(N, 1);
            h_agents_trail = gobjects(N, 1);
            agent_paths_history = cell(N,1); 
            
            for i = 1:N
                start_p = agent_start_pos(i, :);
                h_agents_trail(i) = plot(ax_map, start_p(1), start_p(2), '-', ...
                    'Color', [agent_colors(i,:) 0.5], 'LineWidth', 1.5); 
                h_agents_marker(i) = plot(ax_map, start_p(1), start_p(2), 'o', ...
                    'MarkerSize', 10, 'MarkerFaceColor', agent_colors(i,:), ...
                    'MarkerEdgeColor', 'k', 'LineWidth', 2);
                agent_paths_history{i} = start_p;
            end
            
            % --- 右侧：时间线视图初始化 ---
            ax_timeline = subplot(1, 2, 2);
            hold(ax_timeline, 'on'); grid(ax_timeline, 'on'); box(ax_timeline, 'on');
            title(ax_timeline, 'Execution Timeline (Gantt View)');
            xlabel(ax_timeline, 'Time (s)'); ylabel(ax_timeline, 'Agent ID');
            
            ylim(ax_timeline, [0, N + 1]);
            xlim(ax_timeline, [0, max_time * 1.1]);
            set(ax_timeline, 'YTick', 1:N, 'YDir', 'reverse'); 
            
            task_patches = cell(N, 1);
            bar_height = 0.6;
            
            for i = 1:N
                sched = agent_schedules{i};
                num_tasks_i = length(sched);
                task_patches{i} = gobjects(num_tasks_i, 1);
                for j = 1:num_tasks_i
                    x_corners = [sched(j).start_t, sched(j).finish_t, sched(j).finish_t, sched(j).start_t];
                    y_corners = [i - bar_height/2, i - bar_height/2, i + bar_height/2, i + bar_height/2];
                    task_patches{i}(j) = patch(ax_timeline, x_corners, y_corners, color_future, ...
                        'EdgeColor', 'k', 'LineWidth', 0.5);
                    text(ax_timeline, mean([sched(j).start_t, sched(j).finish_t]), i, ...
                        sprintf('T%d', sched(j).task_id), 'HorizontalAlignment', 'center', 'FontSize', 8, 'Color', 'k');
                end
            end
            
            h_time_line = plot(ax_timeline, [0, 0], ylim(ax_timeline), 'r-', 'LineWidth', 2);
            h_suptitle = sgtitle(fig_anim, sprintf('Simulation Time: 0.0 / %.1f s', max_time), 'FontSize', 14, 'FontWeight', 'bold');
            
            %% --- 3. 动画主循环 ---
            fps = 30;               
            duration_sec = 30; % 动画时长 30s
            total_frames = fps * duration_sec;
            time_step = max_time / total_frames;
            
            fprintf('开始播放动画... (总模拟时间: %.1fs, 动画时长: %ds)\n', max_time, duration_sec);
            
            current_sim_time = 0;
            
            while current_sim_time <= max_time + time_step
                
                set(h_suptitle, 'String', sprintf('Simulation Time: %.1f / %.1f s', min(current_sim_time, max_time), max_time));
                set(h_time_line, 'XData', [current_sim_time, current_sim_time]);
                
                for i = 1:N
                    sched = agent_schedules{i};
                    num_tasks_i = length(sched);
                    
                    current_pos = agent_start_pos(i, :); 
                    agent_state = 'idle';
                    
                    if num_tasks_i > 0
                        % --- 状态判断逻辑 ---
                        
                        % 1. 在第一个任务之前
                        if current_sim_time < sched(1).start_t
                            p_start = agent_start_pos(i, :);
                            p_end = sched(1).loc;
                            t_available_start = 0; % 默认 0 时刻开始出发
                            t_task_start = sched(1).start_t;
                            
                            % 按显式速度计算到达时间
                            dist = norm(p_end - p_start);
                            v = agents(i).vel; if v==0, v=1e-5; end
                            t_travel_needed = dist / v;
                            t_arrival = t_available_start + t_travel_needed;
                            
                            if current_sim_time < t_arrival
                                % 在路上 (Traveling)
                                ratio = (current_sim_time - t_available_start) / t_travel_needed;
                                ratio = max(0, min(1, ratio));
                                current_pos = p_start + ratio * (p_end - p_start);
                                agent_state = 'traveling';
                            else
                                % 已经到达，正在等待任务开始 (Waiting)
                                current_pos = p_end;
                                agent_state = 'waiting';
                            end
                            
                        % 2. 最后一个任务之后（返航）
                        elseif current_sim_time >= sched(end).finish_t
                             t_return_start = sched(end).finish_t;
                             t_return_end = agent_mission_ends(i); % 这里已经包含返程结束时间
                             
                             if current_sim_time < t_return_end
                                 p_start = sched(end).loc;
                                 p_end = agent_start_pos(i, :);
                                 t_travel_total = t_return_end - t_return_start; % 这里是实际返航时间
                                 
                                 if t_travel_total > 0
                                     ratio = (current_sim_time - t_return_start) / t_travel_total;
                                     ratio = max(0, min(1, ratio));
                                     current_pos = p_start + ratio * (p_end - p_start);
                                     agent_state = 'returning';
                                 else
                                     current_pos = p_end;
                                 end
                             else
                                 current_pos = agent_start_pos(i, :);
                                 agent_state = 'finished_cycle';
                             end
                             
                        % 3. 任务过程中间
                        else
                            for j = 1:num_tasks_i
                                % A. 正在执行任务
                                if current_sim_time >= sched(j).start_t && current_sim_time < sched(j).finish_t
                                    current_pos = sched(j).loc;
                                    agent_state = 'executing';
                                    break;
                                    
                                % B. 任务间移动（从 Task j 到 Task j+1）
                                elseif j < num_tasks_i && current_sim_time >= sched(j).finish_t && current_sim_time < sched(j+1).start_t
                                    p_start = sched(j).loc;
                                    p_end = sched(j+1).loc;
                                    t_prev_finish = sched(j).finish_t;
                                    
                                    % 计算理论到达时间
                                    dist = norm(p_end - p_start);
                                    v = agents(i).vel; if v==0, v=1e-5; end
                                    t_travel_needed = dist / v;
                                    t_arrival = t_prev_finish + t_travel_needed;
                                    
                                    if current_sim_time < t_arrival
                                        % 在路上
                                        ratio = (current_sim_time - t_prev_finish) / t_travel_needed;
                                        ratio = max(0, min(1, ratio));
                                        current_pos = p_start + ratio * (p_end - p_start);
                                        agent_state = 'traveling';
                                    else
                                        % 已到达，等待中
                                        current_pos = p_end;
                                        agent_state = 'waiting';
                                    end
                                    break;
                                end
                            end
                        end
                    end
                    
                    % Update Marker
                    set(h_agents_marker(i), 'XData', current_pos(1), 'YData', current_pos(2));
                    
                    % 根据状态改变 Marker 颜色样式（可选）
                    if strcmp(agent_state, 'waiting')
                        set(h_agents_marker(i), 'MarkerFaceColor', 'y'); % 等待时黄色
                    elseif strcmp(agent_state, 'executing')
                        set(h_agents_marker(i), 'MarkerFaceColor', 'g'); % 执行时绿色
                    else
                        set(h_agents_marker(i), 'MarkerFaceColor', agent_colors(i,:)); % 默认颜色
                    end
                    
                    % Update Trail
                    if strcmp(agent_state, 'traveling') || strcmp(agent_state, 'returning')
                         agent_paths_history{i} = [agent_paths_history{i}; current_pos];
                         set(h_agents_trail(i), 'XData', agent_paths_history{i}(:,1), 'YData', agent_paths_history{i}(:,2));
                    end

                    % Update Timeline Colors
                    for j = 1:num_tasks_i
                        if current_sim_time < sched(j).start_t
                             % [优化] 若当前时间已超过理论到达时间，则可能处于等待状态
                             % 这里时间线图只显示执行状态，不单独显示等待状态，避免图面过杂
                             set(task_patches{i}(j), 'FaceColor', color_future);
                        elseif current_sim_time >= sched(j).start_t && current_sim_time < sched(j).finish_t
                            set(task_patches{i}(j), 'FaceColor', color_active); 
                        else
                            set(task_patches{i}(j), 'FaceColor', agent_colors(i,:)); 
                        end
                    end
                    
                end % end agent loop
                
                drawnow;
                pause(1/fps); % 控制播放速度
                current_sim_time = current_sim_time + time_step;
                
                if ~ishandle(fig_anim), break; end
                
            end 
            
            fprintf('动画播放完成。\n');
        end
        
        
        function plot_algorithm_comparison(results, comparison_stats, num_algorithms, tasks, Value_Params, WORLD)
            % PLOT_ALGORITHM_COMPARISON 绘制算法对比图
            
            alg_names = fieldnames(results);

            % 推断任务类型价值向量（用于期望价值计算）
            has_tasks = (nargin >= 4) && exist('tasks', 'var') && ~isempty(tasks);
            has_world_values = (nargin >= 6) && exist('WORLD', 'var') && isstruct(WORLD) && isfield(WORLD, 'value');
            type_values = [];
            if has_world_values
                type_values = WORLD.value(:)'; % 1 x T
            elseif (nargin >= 5) && exist('Value_Params', 'var') && isfield(Value_Params, 'task_value')
                type_values = Value_Params.task_value(:)';
            elseif has_tasks && isfield(tasks, 'type') && isfield(tasks, 'value')
                max_type = max([tasks.type]);
                type_values = zeros(1, max_type);
                for tt = 1:max_type
                    idx = find([tasks.type] == tt, 1, 'first');
                    if ~isempty(idx)
                        type_values(tt) = tasks(idx).value;
                    end
                end
            end

            % --- 1. 提取数据用于绘图 ---
            names_list = {};
            utilities = [];
            costs = [];
            completed_values = [];
            comp_times = [];
            coalitions = [];
            avg_rates = [];
            colors = [];
            
            for i = 1:num_algorithms
                alg_name = alg_names{i};
                
                % 检查统计结果是否存在
                if ~isfield(comparison_stats, alg_name)
                    continue;
                end
                stats = comparison_stats.(alg_name);
                
                if stats.has_error
                    continue;
                end
                
                names_list{end+1} = stats.name;
                
                % 提取需要的变量
                utilities(end+1) = stats.total_utility;
                costs(end+1) = stats.total_cost;
                completed_values(end+1) = stats.total_completion_score;
                comp_times(end+1) = stats.computation_time;
                coalitions(end+1) = stats.num_coalitions;
                avg_rates(end+1) = stats.avg_task_completion * 100; % 转为百分比
                
                % 提取颜色
                if isfield(results.(alg_name), 'color')
                    colors(end+1, :) = results.(alg_name).color;
                else
                    colors(end+1, :) = [0.5, 0.5, 0.5];
                end
            end
            
            valid_count = length(names_list);
            
            if valid_count == 0
                fprintf('警告: 没有有效的算法结果可用于绘图\n');
                return;
            end
            
            %% --- 2. 绘制综合柱状对比图 (2行3列) ---
            figure('Name', '算法性能综合对比', 'Position', [100, 100, 1400, 900]);
            
            % 子图绘制函数
            plot_bar = @(idx, data, title_str, y_label, fmt) ...
                PlotClass.local_plot_bar(idx, data, title_str, y_label, fmt, names_list, colors, valid_count);
            
            % 子图1: 总效用
            plot_bar(1, utilities, '总效用对比 (Utility)', '效用值', '%.1f');
            
            % 子图2: 总成本
            plot_bar(2, costs, '总成本对比 (Cost)', '成本值', '%.1f');
            
            % 子图3: 总完成价值
            plot_bar(3, completed_values, '总完成价值 (Total Value)', '价值', '%.1f');
            
            % 子图4: 运行时间
            plot_bar(4, comp_times, '运行时间对比 (Time)', '时间 (s)', '%.2fs');
            
            % 子图5: 联盟数量
            plot_bar(5, coalitions, '执行任务数 (# Coalitions)', '数量', '%d');
            
            % 子图6: 平均完成率
            plot_bar(6, avg_rates, '平均任务完成率 (Avg Rate)', '完成率 (%)', '%.1f%%');
            
            sgtitle('多算法关键指标综合对比', 'FontSize', 14, 'FontWeight', 'bold');
            
            %% --- 3. 绘制雷达图（至少两个算法） ---
            if valid_count >= 2
                figure('Name', '算法性能雷达图', 'Position', [150, 150, 800, 600]);
                
                % 准备雷达图数据，统一归一化到 0-1
                radar_data = zeros(valid_count, 5);
                
                % 维度1: 总效用（越大越好）
                if max(utilities) > 0, radar_data(:, 1) = utilities' / max(utilities); end
                
                % 维度2: 成本效率（越小越好 -> 1/Cost 归一化）
                safe_costs = costs; safe_costs(safe_costs==0) = 1e-6;
                inv_costs = 1 ./ safe_costs;
                if max(inv_costs) > 0, radar_data(:, 2) = inv_costs' / max(inv_costs); end
                
                % 维度3: 总价值（越大越好）
                if max(completed_values) > 0, radar_data(:, 3) = completed_values' / max(completed_values); end
                
                % 维度4: 平均完成率
                radar_data(:, 4) = avg_rates' / 100;
                
                % 维度5: 运行速度（越快越好 -> 1/Time 归一化）
                speeds = 1 ./ (comp_times + 1e-6);
                if max(speeds) > 0, radar_data(:, 5) = speeds' / max(speeds); end
                
                % 标签
                radar_labels = {'总效用', '成本效率(1/Cost)', '总价值', '平均完成率', '运行速度'};
                
                % 绘图
                angles = linspace(0, 2*pi, 6);
                hold on;
                for i = 1:valid_count
                    data_point = [radar_data(i, :), radar_data(i, 1)];
                    plot(angles, data_point, 'o-', 'LineWidth', 2, ...
                        'Color', colors(i, :), 'MarkerFaceColor', colors(i, :), ...
                        'DisplayName', names_list{i});
                end
                
                % 背景网格
                for r = 0.2:0.2:1, plot(angles, r * ones(size(angles)), ':', 'Color', [0.7 0.7 0.7]); end
                ax = gca; ax.XTick = angles(1:end-1); ax.XTickLabel = radar_labels; ax.YLim = [0, 1.2];
                legend('Location', 'northeastoutside');
                title('算法综合性能雷达图（归一化）', 'FontSize', 12, 'FontWeight', 'bold');
                axis equal; grid on; hold off;
            end
            
            %% --- 4. 绘制历史演化曲线 ---
            value_histories = {};
            utility_histories = {};
            completion_rate_histories = {};
            hist_names = {};
            hist_colors = [];
            
            for i = 1:num_algorithms
                alg_name = alg_names{i};
                res = results.(alg_name);
                
                if isfield(res, 'history_data') && isfield(res.history_data, 'rounds')
                    rounds = res.history_data.rounds;
                    if ~isempty(rounds)
                        if isfield(rounds, 'total_completed_value')
                            vals = [rounds.total_completed_value];
                            value_histories{end+1} = vals;
                        end
                        
                        if isfield(rounds, 'coalition_utility')
                            utils = [rounds.coalition_utility];
                            utility_histories{end+1} = utils;
                        end

                        if isfield(rounds, 'task_completion_degrees')
                            comp_rates = zeros(1, length(rounds));
                            for rr = 1:length(rounds)
                                deg = rounds(rr).task_completion_degrees;
                                if isempty(deg)
                                    comp_rates(rr) = NaN;
                                else
                                    comp_rates(rr) = mean(deg) * 100;
                                end
                            end
                            completion_rate_histories{end+1} = comp_rates;
                        end
                        
                        hist_names{end+1} = res.name;
                        if isfield(res, 'color'), hist_colors(end+1, :) = res.color;
                        else, hist_colors(end+1, :) = [0 0 0]; end
                    end
                end
            end
            
            if ~isempty(value_histories) || ~isempty(utility_histories) || ~isempty(completion_rate_histories)
                total_plots = (~isempty(value_histories)) + (~isempty(utility_histories)) + (~isempty(completion_rate_histories));
                fig_width = 500 * total_plots;
                figure('Name', '历史演化过程', 'Position', [200, 200, fig_width, 500]);
                
                plot_idx = 1;
                
                if ~isempty(value_histories)
                    subplot(1, total_plots, plot_idx);
                    hold on;
                    for k = 1:length(value_histories)
                        plot(value_histories{k}, 'LineWidth', 2, 'Color', hist_colors(k,:), 'DisplayName', hist_names{k});
                    end
                    xlabel('外层迭代 (Round)'); ylabel('总完成价值');
                    title('总完成价值演化曲线');
                    grid on; legend('Location', 'best'); hold off;
                    plot_idx = plot_idx + 1;
                end
                
                if ~isempty(utility_histories)
                    subplot(1, total_plots, plot_idx);
                    hold on;
                    for k = 1:length(utility_histories)
                        plot(utility_histories{k}, 'LineWidth', 2, 'Color', hist_colors(k,:), 'DisplayName', hist_names{k});
                    end
                    xlabel('外层迭代 (Round)'); ylabel('全局总效用');
                    title('全局总效用演化曲线');
                    grid on; legend('Location', 'best'); hold off;
                    plot_idx = plot_idx + 1;
                end
                
                if ~isempty(completion_rate_histories)
                    subplot(1, total_plots, plot_idx);
                    hold on;
                    for k = 1:length(completion_rate_histories)
                        plot(completion_rate_histories{k}, 'LineWidth', 2, 'Color', hist_colors(k,:), 'DisplayName', hist_names{k});
                    end
                    xlabel('外层迭代 (Round)'); ylabel('平均任务完成度 (%)');
                    title('任务完成度演化曲线');
                    grid on; legend('Location', 'best'); hold off;
                end
            end
          

            %% --- 6. 绘制任务期望价值演化图（期望 = 价值 × 概率分布）
            if has_tasks && ~isempty(type_values)
                for alg_idx = 1:num_algorithms
                    alg_name = alg_names{alg_idx};
                    res = results.(alg_name);

                    if ~(isfield(res, 'history_data') && isfield(res.history_data, 'rounds') && ~isempty(res.history_data.rounds))
                        continue;
                    end
                    rounds = res.history_data.rounds;
                    if ~isfield(rounds, 'beliefs') || isempty(rounds(1).beliefs)
                        continue;
                    end

                    [num_agents, num_tasks, belief_types] = size(rounds(1).beliefs);
                    if isempty(type_values)
                        type_values = 1:belief_types;
                    end
                    % 若维度不一致，则截断或补零到匹配长度
                    tv = type_values;
                    if length(tv) > belief_types, tv = tv(1:belief_types); end
                    if length(tv) < belief_types, tv = [tv, zeros(1, belief_types - length(tv))]; end

                    num_rounds = length(rounds);
                    exp_value_mean = zeros(num_tasks, num_rounds);

                    for r = 1:num_rounds
                        if ~isfield(rounds(r), 'beliefs') || isempty(rounds(r).beliefs)
                            continue;
                        end
                        beliefs_r = rounds(r).beliefs; % N x M x T
                        for tsk = 1:num_tasks
                            bmat = squeeze(beliefs_r(:, tsk, :)); % N x T
                            if isempty(bmat)
                                continue;
                            end
                            exp_agents = bmat * tv(:); % N x 1
                            exp_value_mean(tsk, r) = mean(exp_agents);
                        end
                    end

                    rows = ceil(sqrt(num_tasks));
                    cols = ceil(num_tasks / rows);
                    figure('Name', ['任务期望价值演化 - ', res.name], 'Position', [180, 180, 1200, 800]);
                    tiledlayout(rows, cols, 'Padding', 'compact', 'TileSpacing', 'compact');

                    for tsk = 1:num_tasks
                        nexttile;
                        hold on;
                        plot(1:num_rounds, exp_value_mean(tsk, :), 'LineWidth', 2, 'Color', [0.2 0.5 0.9], 'DisplayName', '平均期望价值');
                        if isfield(tasks, 'value') && length(tasks) >= tsk
                            yline(tasks(tsk).value, '--r', 'LineWidth', 1.4, 'DisplayName', '真实价值');
                        end
                        xlabel('外层迭代');
                        ylabel('期望价值');
                        title(sprintf('任务 %d', tsk));
                        grid on;
                        legend('Location', 'southoutside', 'Orientation', 'horizontal');
                        hold off;
                    end
                end
            end

            fprintf('对比图绘制完成。\n');
        end
        
        %% 局部辅助函数：绘制单个柱状图
        function local_plot_bar(idx, data, title_str, y_label, fmt, names, colors, count)
            subplot(2, 3, idx);
            b = bar(data);
            b.FaceColor = 'flat';
            for k = 1:count
                b.CData(k,:) = colors(k,:);
            end
            set(gca, 'XTickLabel', names, 'XTick', 1:count);
            xtickangle(45);
            ylabel(y_label);
            title(title_str);
            grid on;
            
            % 显示数值标签
            for k = 1:count
                text(k, data(k), sprintf(fmt, data(k)), ...
                    'HorizontalAlignment', 'center', 'VerticalAlignment', 'bottom');
            end
        end
    end
end