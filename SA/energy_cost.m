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
    orderedTasks = sort_tasks_by_priority(assignedTasks, tasks);
    
    % 2. 计算路径距离
    startXY = [agents(agentIdx).x, agents(agentIdx).y];
    pts = [startXY; get_task_positions(orderedTasks, tasks); startXY];
    totalDistance = sum(sqrt(sum(diff(pts).^2, 2)));
    
    % 3. 获取能量模型参数
    alpha_fly = agents(agentIdx).fuel;   % 飞行能耗系数
    alpha_wait = alpha_fly * 0.5;        % 等待能耗系数（悬停，约为飞行的一半）
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
            T_exec_total = T_exec_total + calc_exec_time(tasks(m), R_row, Value_Params, tol);
        end
    else
        % 同步模式：使用全局调度计算
        [t_fly_total, t_wait_total, T_exec_total, task_arrival_times] = calc_with_global_sync(...
            agentIdx, orderedTasks, agents, tasks, Value_Params, SC, R_agent, tol);
    end
    
    % 5. 计算总能量
    requiredEnergy = t_fly_total * alpha_fly + t_wait_total * alpha_wait + T_exec_total * beta;
end

%% ========== 全局同步调度核心函数 ==========

function [t_fly_total, t_wait_total, t_exec_total, arrivals] = calc_with_global_sync(...
    agentIdx, myOrderedTasks, agents, tasks, Value_Params, SC, R_agent, tol)
% 使用全局调度机制计算飞行时间、等待时间、执行时间和到达时间
%
% 固定速度+等待模型：
%   1. 每个智能体以固定速度飞行
%   2. 计算每个智能体的实际到达时间
%   3. 同步开始时间 = max(所有参与者的到达时间)
%   4. 等待时间 = 同步开始时间 - 自己的到达时间
%
% 返回值：
%   t_fly_total  - 该智能体的总飞行时间（固定速度）
%   t_wait_total - 该智能体的总等待时间（等待其他智能体）
%   t_exec_total - 该智能体的总执行时间
%   arrivals     - 各任务的同步开始时间

    N = Value_Params.N;  % 智能体数量
    M = Value_Params.M;  % 任务数量
    
    % --- 初始化所有智能体的状态 ---
    % agent_state(i).pos       - 当前位置 [x, y]
    % agent_state(i).ready_time - 可以出发前往下一个任务的时刻
    agent_state = struct('pos', {}, 'ready_time', {});
    for i = 1:N
        agent_state(i).pos = [agents(i).x, agents(i).y];  % 初始位置
        agent_state(i).ready_time = 0;                    % 初始时刻可以出发
    end
    
    % --- 获取全局任务优先级顺序 ---
    all_tasks = 1:M;
    global_order = sort_tasks_by_priority(all_tasks, tasks);
    
    % --- 记录每个任务的信息（用于返回） ---
    task_sync_start = zeros(M, 1);    % 任务m的同步开始时间
    task_exec_time = zeros(M, 1);     % 任务m的联盟执行时间
    
    % --- 按全局优先级顺序处理每个任务 ---
    for order_idx = 1:M
        task_id = global_order(order_idx);
        task_pos = [tasks(task_id).x, tasks(task_id).y];
        
        % 找到该任务的所有参与者
        participants = get_participants(SC, task_id, N, tol);
        
        if isempty(participants)
            continue;  % 没有智能体参与，跳过
        end
        
        % --- 计算每个参与者的到达时间（固定速度飞行） ---
        arrival_times = zeros(numel(participants), 1);
        for k = 1:numel(participants)
            agent_id = participants(k);
            v = agents(agent_id).vel;  % 固定速度
            
            % 飞行距离和时间
            dist = norm(task_pos - agent_state(agent_id).pos);
            fly_time = dist / max(v, tol);
            
            % 到达时间 = 可出发时刻 + 飞行时间
            arrival_times(k) = agent_state(agent_id).ready_time + fly_time;
        end
        
        % --- 同步开始时间 = 所有参与者中最晚到达的时间 ---
        sync_start = max(arrival_times);
        task_sync_start(task_id) = sync_start;
        
        % --- 计算该任务的执行时间（联盟并行执行，取最长） ---
        t_exec = calc_coalition_exec_time(SC, task_id, tasks(task_id), Value_Params, tol);
        task_exec_time(task_id) = t_exec;
        
        % --- 更新所有参与者的状态 ---
        % 所有参与者在sync_start时刻开始执行，sync_start + t_exec时刻完成
        for k = 1:numel(participants)
            agent_id = participants(k);
            agent_state(agent_id).pos = task_pos;              % 更新位置
            agent_state(agent_id).ready_time = sync_start + t_exec;  % 完成后可以出发
        end
    end
    
    % --- 计算当前智能体(agentIdx)的详细时间 ---
    t_fly_total = 0;    % 总飞行时间
    t_wait_total = 0;   % 总等待时间
    t_exec_total = 0;   % 总执行时间
    arrivals = zeros(numel(myOrderedTasks), 1);
    
    current_pos = [agents(agentIdx).x, agents(agentIdx).y];
    current_ready_time = 0;  % 当前可出发时刻
    v = agents(agentIdx).vel;
    
    for ii = 1:numel(myOrderedTasks)
        task_id = myOrderedTasks(ii);
        task_pos = [tasks(task_id).x, tasks(task_id).y];
        
        % --- 飞行时间（固定速度） ---
        dist = norm(task_pos - current_pos);
        fly_time = dist / max(v, tol);
        t_fly_total = t_fly_total + fly_time;
        
        % --- 我的到达时间 ---
        my_arrival = current_ready_time + fly_time;
        
        % --- 同步开始时间（从全局调度获取） ---
        sync_start = task_sync_start(task_id);
        arrivals(ii) = sync_start;
        
        % --- 等待时间 = 同步开始 - 我的到达 ---
        wait_time = max(0, sync_start - my_arrival);
        t_wait_total = t_wait_total + wait_time;
        
        % --- 该智能体在该任务上的执行时间 ---
        if ~isempty(SC) && task_id <= numel(SC) && ~isempty(SC{task_id})
            SC_m = SC{task_id};
            R_row = SC_m(agentIdx, :);
        else
            R_row = R_agent(task_id, :);
        end
        my_exec_time = calc_exec_time(tasks(task_id), R_row, Value_Params, tol);
        t_exec_total = t_exec_total + my_exec_time;
        
        % --- 更新状态 ---
        % 使用联盟执行时间来更新ready_time（所有人一起完成）
        coalition_exec = task_exec_time(task_id);
        current_ready_time = sync_start + coalition_exec;
        current_pos = task_pos;
    end
    
    % --- 加上返回起点的飞行时间 ---
    return_dist = norm([agents(agentIdx).x, agents(agentIdx).y] - current_pos);
    t_fly_total = t_fly_total + return_dist / max(v, tol);
end

%% ========== 基础工具函数 ==========

function ordered = sort_tasks_by_priority(task_list, tasks)
% 按优先级对任务列表排序（优先级数值越小越先执行）
    if isempty(task_list)
        ordered = [];
        return;
    end
    if isfield(tasks, 'priority')
        priorities = arrayfun(@(t) tasks(t).priority, task_list);
        [~, idx] = sort(priorities);
        ordered = task_list(idx);
    else
        ordered = sort(task_list);
    end
end

function pos = get_task_positions(task_list, tasks)
% 获取任务列表中所有任务的位置坐标
    n = numel(task_list);
    pos = zeros(n, 2);
    for ii = 1:n
        pos(ii, :) = [tasks(task_list(ii)).x, tasks(task_list(ii)).y];
    end
end

function participants = get_participants(SC, task_idx, N, tol)
% 获取指定任务的所有参与者（智能体）ID列表
    if isempty(SC) || task_idx > numel(SC)
        participants = [];
        return;
    end
    participants = find(any(SC{task_idx} > tol, 2))';
end

function t_exec = calc_exec_time(task, R_row, Value_Params, tol)
% 计算单智能体执行任务的时间（并行模型：取使用资源中最长时间）
    if ~isempty(R_row)
        used = R_row > tol;
    else
        used = true(1, Value_Params.K);
    end
    
    if isfield(task, 'duration_by_resource')
        dur = task.duration_by_resource(:)';
        if isscalar(dur)
            t_exec = dur;
        else
            dur = dur(1:min(numel(dur), Value_Params.K));
            used = used(1:numel(dur));
            t_exec = max([dur(used), 0]);
        end
    elseif isfield(task, 'duration')
        t_exec = task.duration;
    else
        t_exec = 1.0;
    end
end

function t_exec = calc_coalition_exec_time(SC, task_idx, task, Value_Params, tol)
% 计算联盟执行任务的时间（取所有参与者中最长的执行时间）
    alloc = SC{task_idx};
    exec_times = [];
    for i = 1:Value_Params.N
        if any(alloc(i, :) > tol)
            exec_times = [exec_times, calc_exec_time(task, alloc(i, :), Value_Params, tol)];
        end
    end
    t_exec = max([exec_times, 0]);
end
