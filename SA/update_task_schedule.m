function Value_data = update_task_schedule(Value_data, agents, tasks, Value_Params)
% UPDATE_TASK_SCHEDULE 更新智能体的任务执行序列和时间信息
    tol = 1e-9;
    N = Value_Params.N;
    M = Value_Params.M;
    for i = 1:N
        SC = Value_data(i).SC;
        assigned_tasks = OCFUtils.get_agent_tasks_fast(SC,Value_data(i).agentID,tol);
        if isempty(assigned_tasks)
            Value_data(i).task_schedule = empty_schedule();
            continue;
        end
        % 直接使用 energy_cost 返回的详细时间信息
        [t_flight, T_exec, ~, energy, ordered_tasks, task_arrival_times, t_wait, start_times, execution_times, completion_time, mission_end_time] = energy_cost(i, assigned_tasks, agents, tasks, Value_Params, SC);
        % 存储详细数据到 Value_data
        Value_data(i).task_schedule.task_sequence = ordered_tasks;
        Value_data(i).task_schedule.arrival_times = task_arrival_times;
        Value_data(i).task_schedule.start_times = start_times;
        Value_data(i).task_schedule.mission_end_time = mission_end_time;
        Value_data(i).task_schedule.execution_times = execution_times;
        Value_data(i).task_schedule.completion_times = completion_time;
        Value_data(i).task_schedule.total_flight_time = t_flight;
        Value_data(i).task_schedule.total_wait_time = t_wait;
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
    schedule.total_wait_time = 0;
    schedule.total_execution_time = 0;
    schedule.total_energy = 0;
end
