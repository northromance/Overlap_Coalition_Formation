
function [global_net_utility, total_global_cost, total_completed_value, task_completion_degrees] = ...
    evaluate_coalition_metrics(SC_global, agents, tasks, Value_Params, eps_val)
% EVALUATE_COALITION_METRICS 计算全局联盟结构的净效用
%
% 修改说明：
%   根据新的逻辑，不再单独计算每个任务的净效用。
%   全局净效用 = (所有任务的完成价值之和) - (所有智能体的路径总消耗之和)
%
% 输入:
%   SC_global    - (Cell Array) 全局联盟结构 SC
%   agents       - (Struct Array) 智能体
%   tasks        - (Struct Array) 任务
%   Value_Params - (Struct) 参数 (M, N, K)
%   eps_val      - (可选) 容差
%
% 输出:
%   global_net_utility      - (标量) 全局净效用 = total_completed_value - sum(agent_total_costs)
%   agent_total_costs       - (1xN 向量) 每个智能体的总路径成本
%   total_completed_value   - (标量) 所有任务的收益总和 (Value * D_C)
%   task_completion_degrees - (Mx1 向量) 每个任务的完成度
    
    %% 1. 参数初始化
    if nargin < 5 || isempty(eps_val)
        eps_val = 1e-6;
    end
    
    M = Value_Params.M;
    N = Value_Params.N;
    K = Value_Params.K;
    
    % 初始化输出
    task_completion_degrees = zeros(M, 1); 
    total_completed_value = 0;
    total_global_cost = zeros(1, N); % 记录每个智能体的总成本
    
    %% 2. 第一阶段：计算所有任务的收益 (Revenue)
    % 逻辑：遍历任务，只关注完成度和产生的价值
    for j = 1:M
        % 1. 获取参与者
        participants = OCFUtils.get_participants(SC_global, j, eps_val);
        
        if isempty(participants)
            task_completion_degrees(j) = 0;
            continue;
        end
        
        % 2. 获取任务资源矩阵与需求
        SC_task = SC_global{j}; 
        demand = tasks(j).resource_demand(:)';
        
        % 3. 计算投入总资源
        total_resources = sum(SC_task(participants, :), 1);
        
        % 4. 计算完成度 D_C (0~1)
        D_C = WorldSim.calc_task_completion_degree(total_resources, demand, K);
        task_completion_degrees(j) = D_C;
        
        % 5. 累加任务价值 (收益)
        if D_C > 0
            V_C = tasks(j).value;
            total_completed_value = total_completed_value + (V_C * D_C);
        end
    end
    
    %% 3. 第二阶段：计算所有智能体的成本 (Cost)
    % 逻辑：遍历智能体，计算其整条路径的飞行、等待和执行消耗
    % 这样避免了在任务循环中重复计算同一个智能体的路径成本
    
    for i = 1:N
        % 1. 快速检查智能体是否被分配了任务 (从全局结构中判断)
        %    如果该智能体在任何任务中都没有投入资源，则跳过
        %    (这里假设 get_agent_tasks_fast 效率较高，或者可以先检查 SC_global)
        my_raw_tasks = OCFUtils.get_agent_tasks_fast(SC_global, i);
        
        if isempty(my_raw_tasks)
            total_global_cost(i) = 0;
            continue;
        end
        
        % 2. 准备计算路径成本所需的数据
        % 获取该智能体的资源分配矩阵 (N x K) -> 提取第 i 行
        
        % 对任务按优先级排序 (构建路径)
        my_tasks = OCFUtils.sort_tasks_by_priority(my_raw_tasks, tasks);
        
        % 3. 提取成本系数
        alpha_fly = agents(i).fuel;       % 移动消耗系数
        alpha_wait = agents(i).wait_fuel; % 等待消耗系数
        beta = agents(i).beta;            % 执行消耗系数
        
        % 4. 计算路径时间 (核心耗时步骤)
        % 计算飞行时间、等待时间、执行时间
        [t_fly_total, t_wait_total, t_exec_total] = WorldSim.calc_with_global_sync( ...
            i, my_tasks, agents, tasks, Value_Params, SC_global, eps_val);
        
        % 5. 计算并存储该智能体的总成本
        cost_i = t_fly_total * alpha_fly + t_wait_total * alpha_wait + t_exec_total * beta;
        total_global_cost(i) = cost_i;
    end
    
    %% 4. 第三阶段：计算全局净效用
    % 全局效用 = 总收益 - 总成本
    % 成本求和
    total_global_cost = sum(total_global_cost);
    
    % 计算净值 (可以允许为负值，表示成本高于收益；也可以设为 max(..., 0) 取决于你的需求)
    % 这里通常允许为负以反映糟糕的解，或者归零。此处保留原始差值以便优化算法感知梯度。
    global_net_utility = total_completed_value - total_global_cost;
    
    % 如果业务逻辑要求效用非负，取消下面注释：
    % global_net_utility = max(global_net_utility, 0);

end