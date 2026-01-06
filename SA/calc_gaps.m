function [allocated_resources, resource_gap] = calc_gaps(Value_data, agents, tasks, Value_Params)
    % 初始化变量
    N = Value_Params.N; % 智能体数量
    M = Value_Params.M; % 任务数量
    K = Value_Params.K; % 资源类型数量

    % 初始化已分配的资源矩阵
    allocated_resources = zeros(N, K); % 每个智能体每种资源类型已分配的资源量

    % 初始化资源缺口矩阵
    resource_gap = zeros(M, K); % 每个任务每种资源类型的缺口

    % 从SC中读取资源分配情况 (SC是cell数组格式)
    % SC{m} 是一个 N×K 矩阵，表示任务m上N个机器人分配的K种资源类型的数量
    SC = Value_data.SC;  % 该智能体存储的联盟结构
    
    % 计算每个智能体已分配的资源总量
    % allocated_resources(i, r) = 智能体i对所有任务分配的资源类型r的总和
    for i = 1:N
        for r = 1:K
            % 遍历所有任务m，累加智能体i在每个任务上分配的资源类型r
            for m = 1:M
                allocated_resources(i, r) = allocated_resources(i, r) + SC{m}(i, r);
            end
        end
    end

    % 计算每个任务的资源缺口
    % resource_gap(j, r) = 任务j的资源类型r期望需求 - 所有智能体对任务j分配的资源类型r总和
    % 期望需求向量(1×K) = belief(1×T) * task_type_demands(T×K)
    
    % ========== 输入验证（只做一次，避免在循环内重复检查） ==========
    % 检查1：确保 task_type_demands 存在（T×K矩阵，T=任务类型数）
    if ~isfield(Value_Params, 'task_type_demands') || isempty(Value_Params.task_type_demands)
        error('compute_allocated_and_gap:MissingTaskTypeDemands', 'Value_Params.task_type_demands is required to compute expected demands.');
    end
    
    % 赋值类型三种类型需求
    task_type_demands = Value_Params.task_type_demands; % T×K % 
    % 任务类型
    num_types = size(task_type_demands, 1);
    
    % 检查2：确保 task_type_demands 的列数匹配资源类型数K
    if size(task_type_demands, 2) ~= K
        error('compute_allocated_and_gap:DemandKMismatch', 'task_type_demands must be T×K with K=Value_Params.K (%d).', K);
    end
    
    % 检查3：确保 initbelief 存在且行数足够
    if ~isfield(Value_data, 'initbelief') || size(Value_data.initbelief, 1) < M
        error('compute_allocated_and_gap:MissingInitBelief', 'Value_data(1).initbelief must exist and contain beliefs for M tasks.');
    end
    
    % ========== 主循环：计算每个任务的资源缺口 ==========
    for j = 1:M
        % 获取任务j的类型信念分布（1×T行向量）
        belief_j = Value_data.initbelief(j, :);
        belief_j = belief_j(:).'; % 强制转为行向量
        
        % ========== 使用分位数法计算期望需求 ==========
        % 相比期望值法 (belief × demands)，分位数法更保守
        % 基于置信水平确定"有X%把握够用"的需求量
        % =============================================
        if isfield(Value_Params, 'resource_confidence') && Value_Params.resource_confidence > 0
            % 使用分位数法
            expected_demand_vec = calculate_demand_quantile(belief_j(1:num_types), ...
                                                             task_type_demands, ...
                                                             Value_Params.resource_confidence);
        else
            % 回退到期望值法（向后兼容）
            expected_demand_vec = belief_j(1:num_types) * task_type_demands;
        end

        % 计算每种资源类型的缺口
        for r = 1:K
            task_allocated = sum(SC{j}(:, r));  % 任务j已获得的资源r总量
            resource_gap(j, r) = expected_demand_vec(r) - task_allocated;
        end
    end
end
