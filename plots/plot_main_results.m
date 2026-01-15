function plot_main_results(agents, tasks, lianmengchengyuan, history_data, N, M, num_rounds, task_values, Value_data)
%PLOT_MAIN_RESULTS Main visualization entry point.

    % 1. Task Expected Revenue Evolution (One Figure with Subplots)
    draw_expected_revenue_evolution(history_data, N, M, num_rounds, task_values);

    % 2. Agent Execution Routes (Static Map)
    if nargin >= 9 && ~isempty(Value_data)
        draw_agent_execution_routes(agents, tasks, Value_data);
    else
        fprintf('Warning: Value_data not provided, skipping route plots.\n');
    end

end

%% Function 1: Task Expected Revenue Evolution
function draw_expected_revenue_evolution(history_data, N, M, num_rounds, task_values)
    % Calculate data
    sumprob = struct();
    for i = 1:N
        for j = 1:M
            for k = 1:num_rounds
                if k > length(history_data.rounds), break; end 
                
                belief_probs = history_data.rounds(k).agents(i).belief(j, :);
                % value = sum(prob * value)
                sumprob(i, j).value(k) = belief_probs(1) * task_values(1) + ...
                                         belief_probs(2) * task_values(2) + ...
                                         belief_probs(3) * task_values(3);
            end
        end
    end
    
    % Create Figure
    figure('Name', 'Task Expected Revenue Evolution', 'NumberTitle', 'off', 'Color', 'w');
    
    % Grid layout
    cols = ceil(sqrt(M));
    rows = ceil(M / cols);
    
    plot_interval = max(1, floor(num_rounds / 20));
    time = 1:plot_interval:num_rounds;
    
    % Markers/Colors
    markers = {'+', 'o', '*', 'x', 's', 'd', '^', 'v', '>', '<'};
    colors = lines(N);

    for j = 1:M
        subplot(rows, cols, j);
        hold on;
        
        legendLabels = cell(1, N);
        for i = 1:N
            data_points = sumprob(i, j).value(time);
            % Use standard tex for r_{i}
            plot(time, data_points, ...
                'LineStyle', '-', ...
                'Marker', markers{mod(i - 1, length(markers)) + 1}, ... 
                'Color', colors(i, :), ...
                'LineWidth', 1.2, ...
                'MarkerSize', 4);
            legendLabels{i} = sprintf('r_{%d}', i);
        end
        
        hold off;
        grid on;
        xlabel('Iterations');
        ylabel('Exp. Revenue');
        title(sprintf('Task %d', j));
        
        % Only show legend in first subplot to avoid clutter
        if j == 1
           legend(legendLabels, 'Location', 'best', 'NumColumns', 2, 'Interpreter', 'tex');
        end
    end
    
    sgtitle('Task Expected Revenue Evolution');
end

%% Function 2: Agent Execution Routes
function draw_agent_execution_routes(agents, tasks, Value_data)
    figure('Name', 'Agent Execution Routes', 'NumberTitle', 'off', 'Color', 'w');
    hold on;
    axis equal;
    grid on;
    
    % 1. Draw Tasks
    for j = 1:length(tasks)
        plot(tasks(j).x, tasks(j).y, 'p', 'MarkerSize', 15, ...
            'MarkerFaceColor', [1 0.8 0.2], 'MarkerEdgeColor', 'k');
        text(tasks(j).x + 2, tasks(j).y + 2, sprintf('T_{%d}', j), ...
            'FontSize', 12, 'FontWeight', 'bold', 'Interpreter', 'tex');
    end
    
    % 2. Draw Routes
    colors = lines(length(agents));
    
    for i = 1:length(agents)
        start_pos = [agents(i).x, agents(i).y];
        
        % Start Position
        plot(start_pos(1), start_pos(2), 'o', 'MarkerSize', 8, ...
            'MarkerFaceColor', colors(i,:), 'MarkerEdgeColor', 'k');
        text(start_pos(1) - 4, start_pos(2), sprintf('r_{%d}', i), ...
            'FontSize', 10, 'Color', colors(i,:), 'FontWeight', 'bold', 'Interpreter', 'tex');
            
        % Route
        if ~isempty(Value_data(i).task_schedule) && ~isempty(Value_data(i).task_schedule.task_sequence)
            seq = Value_data(i).task_schedule.task_sequence;
            
            % Path: Start -> T_a -> ... -> Start
            path_x = [start_pos(1)];
            path_y = [start_pos(2)];
            
            for k = 1:length(seq)
                tid = seq(k);
                path_x(end+1) = tasks(tid).x;
                path_y(end+1) = tasks(tid).y;
            end
            
            % Return to start
            path_x(end+1) = start_pos(1);
            path_y(end+1) = start_pos(2);
            
            % Line
            plot(path_x, path_y, '-', 'Color', [colors(i,:) 0.6], 'LineWidth', 1.5);
            
            % Arrows
            for k = 1:length(path_x)-1
                p1 = [path_x(k), path_y(k)];
                p2 = [path_x(k+1), path_y(k+1)];
                mid = (p1 + p2) / 2;
                dp = p2 - p1;
                
                len = norm(dp);
                if len > 0
                   dp = dp / len * 5; 
                   quiver(mid(1), mid(2), dp(1), dp(2), 0, ...
                       'Color', colors(i,:), 'MaxHeadSize', 0.8, 'AutoScale', 'off', 'LineWidth', 1.2);
                end
            end
        end
    end
    
    xlabel('x-axis (m)');
    ylabel('y-axis (m)');
    title('Agent Execution Routes');
end

