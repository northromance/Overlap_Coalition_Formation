classdef PlotClass
    % PlotClass 用于存储项目中的绘图函数
    % 包含了环境地图绘制、任务分配结果静态展示以及动态执行过程动画展示
    
    methods(Static)
        function plot_SA_allocation(Value_data, tasks, Value_Params)
            % plot_SA_allocation 绘制SA算法的资源分配堆叠柱状图
            % (此处保持不变，为节省篇幅省略，请保留您原有的代码)
            % ... [保留原有的 plot_SA_allocation 代码] ...
             fprintf('正在绘制 SA_Value 资源分配详情...\n');
            
            % 1. 提取数据
            SC = Value_data(1).SC; 
            
            N = Value_Params.N;
            M = Value_Params.M;
            K = Value_Params.K;
            
            % 2. 创建画布
            figure('Name', 'SA_Value Resource Allocation Detail', ...
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
                title(sprintf('Task %d (Value: %.0f)', m, tasks(m).value), 'FontSize', 10);
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
            sgtitle('Resource Allocation Breakdown by Task (SA\_Value Algorithm)');
        end

        function print_agent_capabilities(agents)
            % (此处保持不变)
            % ... [保留原有的 print_agent_capabilities 代码] ...
            fprintf('\n=================================================\n');
            fprintf('          Agent Resource Capabilities\n');
            fprintf('          智能体资源能力上限清单\n');
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
                res_str = '';
                for k = 1:K
                    res_str = [res_str, sprintf('%6d ', agents(i).resources(k))];
                end
                fprintf('   %3d   |%s\n', agents(i).id, res_str);
            end
            fprintf('=================================================\n\n');
        end

        function plot_env(agents, tasks, Value_Params)
            % (此处保持不变)
            % ... [保留原有的 plot_env 代码] ...
            figure('Name', 'Environment Map', 'Color', 'w');
            hold on; grid on; box on;
            task_coords = vertcat(tasks.loc); 
            if isempty(task_coords) && isfield(tasks, 'x')
                 task_coords = [[tasks.x]', [tasks.y]'];
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
        
        %% ========================================================================
        %  New Animation Function
        %  新增动态执行过程动画函数
        %% ========================================================================
        function plot_execution_animation(Value_data, agents, tasks, Value_Params)
            % plot_execution_animation 动态展示算法执行结果
            % 左图：机器人路径动画；右图：垂直甘特图时间线动画
            
            fprintf('正在准备动态执行演示动画...\n');
            
            N = Value_Params.N;
            
            % --- 0. 获取每个智能体的起始位置 ---
            agent_start_pos = zeros(N, 2);
            for i = 1:N
                agent_start_pos(i, :) = [agents(i).x, agents(i).y];
            end

            % --- 1. 数据预处理 ---
            max_time = 0;
            agent_schedules = cell(N, 1); 
            agent_mission_ends = zeros(N, 1); 
            
            % 确保任务坐标提取正确
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
                warning('没有任务被分配或执行时间为0，无法生成动画。');
                return;
            end
            
            % --- 2. 初始化图形界面 ---
            fig_anim = figure('Name', 'Dynamic Execution Output', 'Color', 'w', ...
                'Position', [100, 100, 1400, 700]); 
            
            % 颜色定义
            agent_colors = lines(N);
            color_future = [0.9 0.9 0.9]; % 浅灰色
            color_wait   = [1 1 0];       % 黄色 (等待中)
            color_active = [0 1 0];       % 亮绿色 (执行中)
            
            % --- 左侧：地图动画初始化 ---
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
            
            % --- 右侧：时间轴甘特图初始化 ---
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
            
            fprintf('开始播放动画... (总模拟时长: %.1fs, 动画时长: %ds)\n', max_time, duration_sec);
            
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
                        % --- 状态判定逻辑 ---
                        
                        % 1. 在第一个任务之前
                        if current_sim_time < sched(1).start_t
                            p_start = agent_start_pos(i, :);
                            p_end = sched(1).loc;
                            t_available_start = 0; % 假设从0时刻开始出发
                            t_task_start = sched(1).start_t;
                            
                            % 计算理论上的“最大速度到达时间”
                            dist = norm(p_end - p_start);
                            v = agents(i).vel; if v==0, v=1e-5; end
                            t_travel_needed = dist / v;
                            t_arrival = t_available_start + t_travel_needed;
                            
                            if current_sim_time < t_arrival
                                % 正在路上 (Traveling)
                                ratio = (current_sim_time - t_available_start) / t_travel_needed;
                                ratio = max(0, min(1, ratio));
                                current_pos = p_start + ratio * (p_end - p_start);
                                agent_state = 'traveling';
                            else
                                % 已经到达，正在等待任务开始 (Waiting)
                                current_pos = p_end;
                                agent_state = 'waiting';
                            end
                            
                        % 2. 最后一个任务之后 (返航)
                        elseif current_sim_time >= sched(end).finish_t
                             t_return_start = sched(end).finish_t;
                             t_return_end = agent_mission_ends(i); % 这是已经包含飞行时间的时刻
                             
                             if current_sim_time < t_return_end
                                 p_start = sched(end).loc;
                                 p_end = agent_start_pos(i, :);
                                 t_travel_total = t_return_end - t_return_start; % 这就是纯飞行时间
                                 
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
                             
                        % 3. 任务中间
                        else
                            for j = 1:num_tasks_i
                                % A. 正在执行任务
                                if current_sim_time >= sched(j).start_t && current_sim_time < sched(j).finish_t
                                    current_pos = sched(j).loc;
                                    agent_state = 'executing';
                                    break;
                                    
                                % B. 任务间隙 (从 Task j 到 Task j+1)
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
                                        % 正在路上
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
                    
                    % 根据状态改变 Marker 颜色或样式 (可选)
                    if strcmp(agent_state, 'waiting')
                        set(h_agents_marker(i), 'MarkerFaceColor', 'y'); % 等待时变黄
                    elseif strcmp(agent_state, 'executing')
                        set(h_agents_marker(i), 'MarkerFaceColor', 'g'); % 执行时变绿
                    else
                        set(h_agents_marker(i), 'MarkerFaceColor', agent_colors(i,:)); % 正常颜色
                    end
                    
                    % Update Trail
                    if strcmp(agent_state, 'traveling') || strcmp(agent_state, 'returning')
                         agent_paths_history{i} = [agent_paths_history{i}; current_pos];
                         set(h_agents_trail(i), 'XData', agent_paths_history{i}(:,1), 'YData', agent_paths_history{i}(:,2));
                    end

                    % Update Timeline Colors
                    for j = 1:num_tasks_i
                        if current_sim_time < sched(j).start_t
                             % [优化] 如果当前时间已经超过了该任务的理论到达时间，说明在等待
                             % 这里简化处理，甘特图只显示执行状态，不显示等待状态，以免太乱
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
    end 
end