function Value_data = update_task_schedule(Value_data, agents, tasks, Value_Params)
% UPDATE_TASK_SCHEDULE 更新所有智能体的任务执行序列和时间信息
%
% 使用 WorldSim.calc_all_agents_with_global_sync 一次性计算全部智能体，
% 替代原先逐个调用 energy_cost（energy_cost 内部仍被 validate_feasibility 使用）。
%
% 输出字段写入 Value_data(i).task_schedule，供后续画图/分析使用。

    tol = 1e-9;
    N   = Value_Params.N;
    SC  = Value_data(1).SC;  % 所有智能体共享同一 SC

    % 一次性计算所有智能体的时间数据
    all_results = WorldSim.calc_all_agents_with_global_sync(agents, tasks, Value_Params, SC, tol);

    for i = 1:N
        r = all_results(i);

        if isempty(r.task_sequence)
            Value_data(i).task_schedule = empty_schedule();
            continue;
        end

        % 总能耗 = 飞行能耗 + 等待能耗 + 执行能耗
        total_energy = r.t_fly_total   * agents(i).fuel      + ...
                       r.t_wait_total  * agents(i).wait_fuel + ...
                       r.t_exec_total  * agents(i).beta;

        Value_data(i).task_schedule.task_sequence        = r.task_sequence;
        Value_data(i).task_schedule.arrival_times        = r.start_times;    % 同步开始时刻（与旧接口一致）
        Value_data(i).task_schedule.start_times          = r.start_times;
        Value_data(i).task_schedule.mission_end_time     = r.mission_end_time;
        Value_data(i).task_schedule.execution_times      = r.execution_times;
        Value_data(i).task_schedule.completion_times     = r.completion_times;
        Value_data(i).task_schedule.total_flight_time    = r.t_fly_total;
        Value_data(i).task_schedule.total_wait_time      = r.t_wait_total;
        Value_data(i).task_schedule.total_execution_time = r.t_exec_total;
        Value_data(i).task_schedule.total_energy         = total_energy;
    end
end

function schedule = empty_schedule()
    schedule.task_sequence        = [];
    schedule.arrival_times        = [];
    schedule.start_times          = [];
    schedule.execution_times      = [];
    schedule.completion_times     = [];
    schedule.mission_end_time     = 0;
    schedule.total_flight_time    = 0;
    schedule.total_wait_time      = 0;
    schedule.total_execution_time = 0;
    schedule.total_energy         = 0;
end
