function Value_data = update_task_schedule(Value_data, agents, tasks, Value_Params)
% UPDATE_TASK_SCHEDULE 更新智能体的任务执行序列和时间信息
%
% 功能：
%   遍历所有智能体，根据当前的联盟结构 (SC) 和资源分配 (R_agent)，
%   调用 energy_cost 函数计算物理过程（飞行、等待、执行），
%   并将详细的时间轴数据（开始时间、完成时间等）保存到 Value_data.task_schedule 中。
%
% 输入：
%   Value_data   - 包含智能体状态（SC, resources_matrix等）
%   agents       - 智能体属性
%   tasks        - 任务属性
%   Value_Params - 全局参数
%
% 输出：
%   Value_data   - 更新了 .task_schedule 字段的结构体

    tol = 1e-9;  % 数值容差
    N = Value_Params.N;
    M = Value_Params.M;
    
    for i = 1:N
        % 获取当前智能体视角的联盟结构和资源分配
        SC = Value_data(i).SC;
        R_agent = Value_data(i).resources_matrix;
        
        % 1. 获取该智能体参与的所有任务 ID
        % 逻辑：在 SC 中查找第 i 行（代表自己）资源投入 > 0 的任务
        assigned_tasks = find(cellfun(@(x) any(x(i, :) > tol), SC))';
        
        % 2. 如果没有任务，清空调度表并跳过
        if isempty(assigned_tasks)
            Value_data(i).task_schedule = empty_schedule();
            continue;
        end
        
        % 3. 调用核心物理引擎 energy_cost
        % 作用：模拟飞行和同步过程，计算总指标和关键时间点
        % 输入：assigned_tasks (未排序), SC (启用同步机制)
        % 输出：
        %   t_flight: 总飞行时间
        %   T_exec:   个人总执行时间
        %   energy:   总能量消耗
        %   ordered_tasks: 按优先级排序后的任务序列
        %   task_arrival_times: 各任务的【同步开始时间】(即所有人到齐的时刻)
        %   t_wait:   总等待时间
        [t_flight, T_exec, ~, energy, ordered_tasks, task_arrival_times, t_wait] = ...
            energy_cost(i, assigned_tasks, agents, tasks, Value_Params, R_agent, SC);
        
        % 4. 重建详细时间轴
        % energy_cost 返回的是宏观数据，这里将其展开为每个任务的具体时间段
        num_tasks = numel(ordered_tasks);
        start_times = zeros(num_tasks, 1);      % 任务开始时刻 (Start)
        execution_times = zeros(num_tasks, 1);  % 任务持续时长 (Duration)
        completion_times = zeros(num_tasks, 1); % 任务结束时刻 (End)
        
        current_time = 0; % 模拟时钟
        current_pos = [agents(i).x, agents(i).y]; % 初始位置
        v_max = agents(i).vel;
        
        for ii = 1:num_tasks
            task_idx = ordered_tasks(ii);
            task_pos = [tasks(task_idx).x, tasks(task_idx).y];
            
            % 计算个人到达时刻 (仅用于逻辑校验，实际使用 task_arrival_times)
            % my_arrival = current_time + 飞行时间
            my_arrival = current_time + norm(task_pos - current_pos) / max(v_max, tol);
            
            % 确定【开始时间】
            % 如果 energy_cost 返回了同步后的开始时间，则使用它（包含了等待队友的时间）
            % 否则（无同步模式），开始时间 = 我到达的时间
            if ii <= numel(task_arrival_times) && task_arrival_times(ii) > 0
                start_times(ii) = task_arrival_times(ii);
            else
                start_times(ii) = my_arrival;
            end
            
            % 计算【执行时长】
            % 注意：这里计算的是联盟层面的执行时间（决定了何时能离开）
            execution_times(ii) = calc_task_exec_time(SC, task_idx, tasks(task_idx), R_agent, Value_Params, tol);
            
            % 计算【结束时间】
            completion_times(ii) = start_times(ii) + execution_times(ii);
            
            % 更新状态，准备前往下一站
            current_time = completion_times(ii);
            current_pos = task_pos;
        end
        
        % 5. 存储详细数据到 Value_data
        Value_data(i).task_schedule.task_sequence = ordered_tasks;
        Value_data(i).task_schedule.arrival_times = task_arrival_times;
        Value_data(i).task_schedule.start_times = start_times;
        Value_data(i).task_schedule.execution_times = execution_times;
        Value_data(i).task_schedule.completion_times = completion_times;
        Value_data(i).task_schedule.total_flight_time = t_flight;
        Value_data(i).task_schedule.total_wait_time = t_wait;  % 记录等待时间
        Value_data(i).task_schedule.total_execution_time = T_exec;
        Value_data(i).task_schedule.total_energy = energy;
    end
end

%% 辅助函数：创建空调度结构
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

%% 辅助函数：计算任务的联盟执行时间
function t_exec = calc_task_exec_time(SC, task_idx, task, R_agent, Value_Params, tol)
% 计算逻辑：并行执行模型。
% 任务的完成时间取决于最耗时的那一种资源类型（短板效应）。
% 只要联盟中有任何成员提供了某种资源，该资源类型的耗时就会被计入。

    SC_m = SC{task_idx}; % 获取该任务的联盟资源分配矩阵 (N x K)
    
    % 获取每种资源类型对应的基础耗时
    if isfield(task, 'duration_by_resource') && ~isempty(task.duration_by_resource)
        dur = task.duration_by_resource(:)';
    else
        dur = ones(1, Value_Params.K) * 10; % 默认耗时
    end
    
    % 确定哪些资源类型被使用了
    % sum(SC_m, 1) 计算每种资源的总投入量
    % > tol 表示该资源类型有人提供
    usedTypes = sum(SC_m, 1) > tol;
    
    % 安全截断，防止维度不匹配
    dur = dur(1:min(numel(dur), Value_Params.K));
    usedTypes = usedTypes(1:numel(dur));
    
    % 取被使用资源中的最大耗时作为任务总耗时
    t_exec = max([dur(usedTypes), 0]);
end