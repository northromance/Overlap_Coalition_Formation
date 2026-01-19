function [t_fly_total, T_exec_total, totalDistance, requiredEnergy, orderedTasks, task_arrival_times, t_wait_total] = ...
    energy_cost(agentIdx, assignedTasks, agents, tasks, Value_Params, R_agent, SC)
% 计算智能体执行任务序列的时间和能量消耗（固定速度+等待模型）
%
% 输出参数：
%   t_fly_total       - 总飞行时间（固定速度飞行）
%   T_exec_total      - 总执行时间（该智能体实际执行任务的时间）
%   totalDistance     - 总飞行距离
%   requiredEnergy    - 总能量消耗
%   orderedTasks      - 按优先级排序后的任务序列
%   task_arrival_times- 各任务的同步开始时间（实际开始执行的时刻）
%   t_wait_total      - 总等待时间（先到达后等待其他智能体的时间）
%
% 同步机制说明（固定速度+等待模型）：
%   1. 每个智能体以固定速度飞行，不调整速度
%   2. 先到达的智能体在任务点等待后到达的智能体
%   3. 所有参与者到齐后，同步开始执行任务
%   4. 执行完成后，所有参与者同时离开前往下一个任务
%
% 能量模型：
%   总能量 = 飞行时间 × α_fly + 等待时间 × α_wait + 执行时间 × β
%   其中 α_wait 默认为 α_fly × 0.5（悬停能耗约为飞行的一半）

    tol = 1e-9;  % 数值容差
    enable_sync = (nargin >= 7) && ~isempty(SC);  % 是否启用同步机制
    
    % 1. 按priority排序当前智能体的任务
    orderedTasks = OCFUtils.sort_tasks_by_priority(assignedTasks, tasks);
    
    % 2. 计算路径距离
    startXY = [agents(agentIdx).x, agents(agentIdx).y];
    totalDistance = OCFUtils.compute_route_distance(startXY, orderedTasks, tasks);
    
    % 3. 获取能量模型参数
    alpha_fly = agents(agentIdx).fuel;   % 飞行能耗系数
    alpha_wait = agents(agentIdx).wait_fuel;

    beta = agents(agentIdx).beta;        % 执行能耗系数
    v = agents(agentIdx).vel;            % 固定飞行速度
    
    % 4. 计算飞行时间、等待时间和执行时间
    if ~enable_sync
        % 无同步模式：简单计算
        t_fly_total = totalDistance / max(v, tol);
        t_wait_total = 0;
        task_arrival_times = zeros(numel(orderedTasks), 1);
        
        % 计算执行时间
        T_exec_total = 0;
        for ii = 1:numel(orderedTasks)
            m = orderedTasks(ii);
            R_row = [];
            if nargin >= 6 && ~isempty(R_agent)
                R_row = R_agent(m, :);
            end
            T_exec_total = T_exec_total + OCFUtils.calc_exec_time(tasks(m), R_row, Value_Params, tol);
        end
    else
        % 同步模式：使用全局调度计算
        [t_fly_total, t_wait_total, T_exec_total, task_arrival_times] = calc_with_global_sync(...
            agentIdx, orderedTasks, agents, tasks, Value_Params, SC, R_agent, tol);
    end
    
    % 5. 计算总能量
    requiredEnergy = t_fly_total * alpha_fly + t_wait_total * alpha_wait + T_exec_total * beta;
end

