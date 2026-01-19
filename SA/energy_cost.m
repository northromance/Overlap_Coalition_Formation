function [t_fly_total, T_exec_total, totalDistance, requiredEnergy, orderedTasks, task_start_times, t_wait_total, start_times, execution_times, completion_times] = energy_cost(agentIdx, assignedTasks, agents, tasks, Value_Params, R_agent, SC)
% energy_cost 计算智能体执行任务序列的时间和能量消耗（固定速度+等待模型）
% 输出：
%   t_fly_total        总飞行时间
%   T_exec_total       总执行时间（个人）
%   totalDistance      总飞行距离（闭环）
%   requiredEnergy     总能量消耗
%   orderedTasks       按 priority 排序后的任务序列
%   task_start_times   任务统一开始时间（同步起点）
%   t_wait_total       总等待时间
%   start_times        同上（便于兼容，等于 task_start_times）
%   execution_times    每个任务个人执行时长
%   completion_times   每个任务完成/离开时间

    tol = 1e-9;

    % 1. 按优先级排序当前智能体的任务
    orderedTasks = OCFUtils.sort_tasks_by_priority(assignedTasks, tasks);

    % 2. 计算路径距离（闭环）
    startXY = [agents(agentIdx).x, agents(agentIdx).y];
    totalDistance = OCFUtils.compute_route_distance(startXY, orderedTasks, tasks);

    % 3. 能量模型参数
    alpha_fly = agents(agentIdx).fuel;
    alpha_wait = agents(agentIdx).wait_fuel;
    beta = agents(agentIdx).beta;

    % 4. 初始化输出
    num_tasks = numel(orderedTasks);
    start_times = zeros(num_tasks, 1);
    execution_times = zeros(num_tasks, 1);
    completion_times = zeros(num_tasks, 1);
    task_start_times = start_times;
    t_wait_total = 0;

    enable_sync = (nargin >= 7) && ~isempty(SC);

    if ~enable_sync
        % 无同步模式：顺序执行
        t_fly_total = 0;
        T_exec_total = 0;
        curr_pos = startXY;
        curr_time = 0;
        v = agents(agentIdx).vel;

        for ii = 1:num_tasks
            task_id = orderedTasks(ii);
            task_pos = [tasks(task_id).x, tasks(task_id).y];
            dist = norm(task_pos - curr_pos);
            fly_time = dist / max(v, tol);
            t_fly_total = t_fly_total + fly_time;

            start_t = curr_time + fly_time;
            start_times(ii) = start_t;

            R_row = [];
            if nargin >= 6 && ~isempty(R_agent)
                R_row = R_agent(task_id, :);
            end
            exec_t = OCFUtils.calc_exec_time(tasks(task_id), R_row, Value_Params, tol);
            execution_times(ii) = exec_t;
            completion_times(ii) = start_t + exec_t;

            curr_time = completion_times(ii);
            curr_pos = task_pos;
            T_exec_total = T_exec_total + exec_t;
        end

        % 返回起点的飞行
        return_dist = norm(startXY - curr_pos);
        t_fly_total = t_fly_total + return_dist / max(agents(agentIdx).vel, tol);
    else
        % 同步模式：使用全局调度
        [t_fly_total, t_wait_total, T_exec_total, start_times, execution_times, completion_times] = calc_with_global_sync(...
            agentIdx, orderedTasks, agents, tasks, Value_Params, SC, R_agent, tol);
    end

    task_start_times = start_times;
    requiredEnergy = t_fly_total * alpha_fly + t_wait_total * alpha_wait + T_exec_total * beta;
end
