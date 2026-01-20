function [t_fly_total, t_wait_total, t_exec_total, start_times, execution_times, completion_times] = calc_with_global_sync(...
    agentIdx, myOrderedTasks, agents, tasks, Value_Params, SC, R_agent, tol)
% CALC_WITH_GLOBAL_SYNC 计算基于全局同步机制的时间与能耗，并返回详细时间表
%
% 输入：
%   agentIdx       - 当前计算的智能体ID
%   myOrderedTasks - 该智能体的任务序列（已按优先级排序）
%   ... (其他标准参数)
%
% 输出：
%   t_fly_total     - 总飞行时间
%   t_wait_total    - 总等待时间（含“等到齐”和“等完工”）
%   t_exec_total    - 总有效执行时间
%   start_times     - [向量] 每个任务的统一开始时刻
%   execution_times - [向量] 每个任务的个体有效执行时长
%   completion_times- [向量] 每个任务的统一结束/离开时刻

    %% ========== 参数提取 ==========
    N = Value_Params.N;
    M = Value_Params.M;
    
    %% ========== 阶段一：全局状态模拟 (God View) ==========
    % 目的：推演全世界的运行时间表，确定每个任务的“法定开始时间”和“法定结束时间”。
    
    % 1. 初始化虚拟状态
    agent_state = struct('pos', {}, 'ready_time', {});
    for i = 1:N
        agent_state(i).pos = [agents(i).x, agents(i).y];
        agent_state(i).ready_time = 0;
    end
    
    % 2. 全局排序
    all_tasks = 1:M;
    global_order = OCFUtils.sort_tasks_by_priority(all_tasks, tasks);
    
    % 3. 记录全局时间锚点
    task_sync_start = zeros(M, 1);    % 任务 m 的统一开始时刻
    task_coalition_dur = zeros(M, 1); % 任务 m 的联盟总耗时（法定执行时长）
    
    % 4. 模拟推演
    for order_idx = 1:M
        task_id = global_order(order_idx);
        task_pos = [tasks(task_id).x, tasks(task_id).y];
        
        participants = OCFUtils.get_participants(SC, task_id, tol);
        if isempty(participants), continue; end
        
        % --- 计算每个参与者的到达时刻 ---
        arrival_times = zeros(numel(participants), 1);
        for k = 1:numel(participants)
            p_id = participants(k);
            v = agents(p_id).vel;
            
            dist = norm(task_pos - agent_state(p_id).pos);
            fly_time = dist / max(v, tol);
            
            arrival_times(k) = agent_state(p_id).ready_time + fly_time;
        end
        
        % --- 确定同步开始时间 (木桶效应) ---
        sync_start = max(arrival_times);
        task_sync_start(task_id) = sync_start;
        
        % --- 计算联盟总耗时 ---
        t_coalition = OCFUtils.calc_coalition_exec_time(SC, task_id, tasks(task_id), Value_Params, tol);
        task_coalition_dur(task_id) = t_coalition;
        
        % --- 更新参与者状态 (强制同步离开) ---
        for k = 1:numel(participants)
            p_id = participants(k);
            agent_state(p_id).pos = task_pos;
            agent_state(p_id).ready_time = sync_start + t_coalition; 
        end
    end
    
    %% ========== 阶段二：计算目标智能体的详细指标 (Agent View) ==========
    
    t_fly_total = 0;
    t_wait_total = 0;
    t_exec_total = 0;
    
    % 初始化详细记录数组
    num_my_tasks = numel(myOrderedTasks);
    start_times = zeros(num_my_tasks, 1);      % 记录开始时刻
    execution_times = zeros(num_my_tasks, 1);  % 记录有效执行时长
    completion_times = zeros(num_my_tasks, 1); % 记录结束/离开时刻
    
    % 重置状态，专门跑一遍 agentIdx 的路径
    curr_pos = [agents(agentIdx).x, agents(agentIdx).y];
    curr_clock = 0; 
    v = agents(agentIdx).vel;
    
    for ii = 1:num_my_tasks
        task_id = myOrderedTasks(ii);
        task_pos = [tasks(task_id).x, tasks(task_id).y];
        
        % --- 1. 飞行阶段 ---
        dist = norm(task_pos - curr_pos);
        fly_time = dist / max(v, tol);
        t_fly_total = t_fly_total + fly_time;
        
        my_arrival = curr_clock + fly_time;
        
        % --- 2. 获取全局时间锚点 ---
        sync_start = task_sync_start(task_id);       
        coalition_dur = task_coalition_dur(task_id); 
        
        % --- 3. 计算“到达等待” ---
        wait_pre_start = max(0, sync_start - my_arrival);
        
        % --- 4. 计算“执行时间” ---
        if ~isempty(SC) && task_id <= numel(SC) && ~isempty(SC{task_id})
            R_row = SC{task_id}(agentIdx, :);
        else
            R_row = R_agent(task_id, :);
        end
        my_exec_time = OCFUtils.calc_exec_time(tasks(task_id), R_row, Value_Params, tol);
        t_exec_total = t_exec_total + my_exec_time;
        
        % --- 5. 计算“完工等待” ---
        wait_post_exec = max(0, coalition_dur - my_exec_time);
        
        % --- 6. 累加总等待 ---
        t_wait_total = t_wait_total + wait_pre_start + wait_post_exec;
        
        % --- 7. 更新状态前往下一站 ---
        % 离开时刻 = 开始时刻 + 联盟总耗时
        curr_clock = sync_start + coalition_dur;
        curr_pos = task_pos;
        
        % ========== [新增] 详细时间记录 ==========
        start_times(ii) = sync_start;           % 任务统一开始的时间
        execution_times(ii) = my_exec_time;     % 我实际干活的时间
        completion_times(ii) = curr_clock;      % 我离开任务的时间 (含完工等待)
    end
    
    % --- 8. 返回基地的飞行 ---
    return_dist = norm([agents(agentIdx).x, agents(agentIdx).y] - curr_pos);
    t_fly_total = t_fly_total + return_dist / max(v, tol);
end