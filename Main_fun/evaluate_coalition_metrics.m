function [coalition_utility, Rcost, total_completed_value, task_completion_degrees] = ...
    evaluate_coalition_metrics(SC_global, agents, tasks, Value_Params, eps_val)
% EVALUATE_COALITION_METRICS 计算当前联盟结构的效用、成本、完成价值及完成度
%
% 输入:
%   SC_global    - (Cell Array) 全局联盟结构 SC，长度为 M，每个元素为 N x K 矩阵
%   agents       - (Struct Array) 智能体结构体数组 (含 fuel, wait_fuel, beta 等参数)
%   tasks        - (Struct Array) 任务结构体数组 (含 value, resource_demand, priority 等)
%   Value_Params - (Struct) 全局参数 (含 M, N, K 等)
%   eps_val      - (可选) 数值计算容差，默认 1e-6
%
% 输出:
%   coalition_utility     - (Mx1 向量) 每个任务(联盟)的净效用 (总收益 - 总成本)
%                           注意：此处的成本计算基于智能体的全路径成本。
%   Rcost                 - (MxN 矩阵) Rcost(j,i) 表示智能体 i 在参与任务 j 时产生的路径总成本
%   total_completed_value - (标量) 所有任务的加权完成价值总和 sum(Value * D_C)
%   task_completion_degrees - (Mx1 向量) 每个任务的完成度 D_C (0.0 ~ 1.0)

    %% 1. 参数初始化与容错处理
    if nargin < 5 || isempty(eps_val)
        eps_val = 1e-6;
    end
    
    M = Value_Params.M;
    N = Value_Params.N;
    K = Value_Params.K;

    % 初始化输出变量
    coalition_utility = zeros(M, 1);       % 任务净效用
    Rcost = zeros(M, N);                   % 成本矩阵
    task_completion_degrees = zeros(M, 1); % 任务完成度向量 [新增]
    total_completed_value = 0;             % 总价值累加器

    %% 2. 遍历每个任务计算指标
    for j = 1:M
        % --- 步骤 1: 获取当前任务的参与者 ---
        % 利用工具函数从 SC 中找出投入资源 > 0 的智能体 ID
        participants = OCFUtils.get_participants(SC_global, j, eps_val);
        
        % 如果没有参与者，该任务各项指标均为 0，直接跳过
        if isempty(participants)
            coalition_utility(j) = 0;
            task_completion_degrees(j) = 0;
            continue;
        end

        % --- 步骤 2: 准备任务需求与分配数据 ---
        % 获取真实任务需求（强制转为行向量）
        demand = tasks(j).resource_demand(:)';
        SC_task = SC_global{j}; % 当前任务 j 的资源分配矩阵 (N x K)
        
        % --- 步骤 3: 计算任务完成度 D_C ---
        % 计算投入到该任务的总资源量 (sum over agents)
        total_resources = sum(SC_task(participants, :), 1);
        
        % 调用工具函数计算完成度 (0~1)
        D_C = OCFUtils.calc_task_completion_degree(total_resources, demand, K);
        
        % 记录该任务的完成度 [新增输出]
        task_completion_degrees(j) = D_C;

        if D_C == 0
            coalition_utility(j) = 0;
            continue;
        end
        
        V_C = tasks(j).value; % 任务原始价值
        
        % --- 步骤 4: 计算联盟成员的贡献收益与执行成本 ---
        coalition_cost = 0;    % 当前任务的总成本
        coalition_revenue = 0; % 当前任务的总收益
        
        for idx = 1:numel(participants)
            pid = participants(idx); % 获取实际的智能体 ID
            
            % ====== A. 收益 (Revenue) 计算 ======
            % 逻辑：按资源贡献比例分配任务的总实现价值
            % r_n_C: 智能体 pid 在任务 j 中的贡献占比
            r_n_C = OCFUtils.calc_resource_contribution_ratio(SC_task, pid, participants);
            agent_revenue = r_n_C * V_C * D_C;
            
            % ====== B. 成本 (Cost) 计算 ======
            % 提取成本系数
            alpha_fly = agents(pid).fuel;      % 飞行能耗系数
            alpha_wait = agents(pid).wait_fuel;% 等待能耗系数
            beta = agents(pid).beta;           % 执行能耗系数
            
            % 1. 获取该智能体的个体资源矩阵 (从全局 SC 提取)
            % [修正] 这里必须用 pid (智能体ID)，不能用 idx (循环索引)
            R_agent = OCFUtils.get_agent_resource_matrix(SC_global, pid, Value_Params);
            
            % 2. 找出该智能体参与的所有任务 (用于构建路径)
            my_raw_tasks = OCFUtils.get_agent_tasks_fast(SC_global, pid);
            
            % 3. 对任务列表按优先级排序 (模拟实际执行顺序)
            my_tasks = OCFUtils.sort_tasks_by_priority(my_raw_tasks, tasks);
            
            % 4. 计算时间成本
            % 调用外部函数计算基于全局同步约束的各类时间
            [t_fly_total, t_wait_total, t_exec_total] = calc_with_global_sync( ...
                pid, my_tasks, agents, tasks, Value_Params, SC_global, R_agent, eps_val);
            
            % 5. 计算总能量/成本
            agent_cost = t_fly_total * alpha_fly + t_wait_total * alpha_wait + t_exec_total * beta;
            
            % ====== C. 累加与记录 ======
            Rcost(j, pid) = agent_cost; % 记录：智能体 pid 在处理任务 j 这个上下文中的路径总成本
            coalition_revenue = coalition_revenue + agent_revenue;
            coalition_cost = coalition_cost + agent_cost;
        end
        
        % --- 步骤 5: 汇总当前任务结果 ---
        % 计算净效用：总收益 - 总成本 (不允许为负，若亏本则记为0)
        coalition_utility(j) = max(coalition_revenue - coalition_cost, 0);
        
        % 累加加权完成价值 (用于统计总体表现)
        total_completed_value = total_completed_value + V_C * D_C;
    end
end