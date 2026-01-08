function Value_data = update_task_schedule(Value_data, agents, tasks, Value_Params)
% 更新智能体的任务执行序列和时间信息

    tol = 1e-9;
    N = Value_Params.N;
    M = Value_Params.M;
    
    for i = 1:N
        SC = Value_data(i).SC;
        R_agent = Value_data(i).resources_matrix;
        
        % 获取参与的任务
        assigned_tasks = find(cellfun(@(x) any(x(i, :) > tol), SC))';
        
        % 无任务时清空
        if isempty(assigned_tasks)
            Value_data(i).task_schedule = empty_schedule();
            continue;
        end
        
        % 调用energy_cost获取时间信息（固定速度+等待模型）
        % 输出: t_fly, T_exec, dist, energy, ordered, arrivals, t_wait
        [t_flight, T_exec, ~, energy, ordered_tasks, task_arrival_times, t_wait] = ...
            energy_cost(i, assigned_tasks, agents, tasks, Value_Params, R_agent, SC);
        
        % 计算详细时间
        num_tasks = numel(ordered_tasks);
        start_times = zeros(num_tasks, 1);
        execution_times = zeros(num_tasks, 1);
        completion_times = zeros(num_tasks, 1);
        
        current_time = 0;
        current_pos = [agents(i).x, agents(i).y];
        v_max = agents(i).vel;
        
        for ii = 1:num_tasks
            task_idx = ordered_tasks(ii);
            task_pos = [tasks(task_idx).x, tasks(task_idx).y];
            
            my_arrival = current_time + norm(task_pos - current_pos) / max(v_max, tol);
            
            if ii <= numel(task_arrival_times) && task_arrival_times(ii) > 0
                start_times(ii) = task_arrival_times(ii);
            else
                start_times(ii) = my_arrival;
            end
            
            execution_times(ii) = calc_task_exec_time(SC, task_idx, tasks(task_idx), R_agent, Value_Params, tol);
            completion_times(ii) = start_times(ii) + execution_times(ii);
            
            current_time = completion_times(ii);
            current_pos = task_pos;
        end
        
        % 存储
        Value_data(i).task_schedule.task_sequence = ordered_tasks;
        Value_data(i).task_schedule.arrival_times = task_arrival_times;
        Value_data(i).task_schedule.start_times = start_times;
        Value_data(i).task_schedule.execution_times = execution_times;
        Value_data(i).task_schedule.completion_times = completion_times;
        Value_data(i).task_schedule.total_flight_time = t_flight;
        Value_data(i).task_schedule.total_wait_time = t_wait;  % 新增：等待时间
        Value_data(i).task_schedule.total_execution_time = T_exec;
        Value_data(i).task_schedule.total_energy = energy;
    end
end

function schedule = empty_schedule()
    schedule.task_sequence = [];
    schedule.arrival_times = [];
    schedule.start_times = [];
    schedule.execution_times = [];
    schedule.completion_times = [];
    schedule.total_flight_time = 0;
    schedule.total_wait_time = 0;  % 新增：等待时间
    schedule.total_execution_time = 0;
    schedule.total_energy = 0;
end

function t_exec = calc_task_exec_time(SC, task_idx, task, R_agent, Value_Params, tol)
    SC_m = SC{task_idx};
    
    if isfield(task, 'duration_by_resource') && ~isempty(task.duration_by_resource)
        dur = task.duration_by_resource(:)';
    else
        dur = ones(1, Value_Params.K) * 10;
    end
    
    % Always calculate usedTypes based on the Coalition Structure (SC) for this task
    % SC_m is N x K matrix of resources allocated to task_idx
    usedTypes = sum(SC_m, 1) > tol;
    
    dur = dur(1:min(numel(dur), Value_Params.K));
    usedTypes = usedTypes(1:numel(dur));
    t_exec = max([dur(usedTypes), 0]);
end
