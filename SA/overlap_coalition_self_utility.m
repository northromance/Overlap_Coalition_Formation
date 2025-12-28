function individual_utility = overlap_coalition_self_utility(n, task_m, coalitionstru, agents, tasks, Value_Params, Value_data)
% =========================================================================
% OVERLAP_COALITION_SELF_UTILITY: 计算智能体在特定任务联盟中的个体效用
%
% 基于公式:
%   utility_n(C) = r_n(C) × V_C × D_C - (t_m^(wait) × α + T_exec(n,m) × β)
%
% 输入参数:
%   n - 智能体ID
%   task_m - 任务索引
%   coalitionstru - 联盟结构矩阵 (M×N)
%   agents - 智能体信息数组
%   tasks - 任务信息数组
%   Value_Params - 参数结构体 (包含K, M, N, alpha, beta等)
%   Value_data - 数据结构体 (包含initbelief, resources_matrix等)
%
% 输出参数:
%   individual_utility - 智能体n在任务task_m中的效用值
% =========================================================================

%% 空任务检查
if task_m < 1 || task_m > Value_Params.M
    individual_utility = 0;
    return;
end

%% 1. 获取参与该任务的联盟成员
member_idx = find(coalitionstru(task_m, :) ~= 0);
if isempty(member_idx)
    individual_utility = 0;
    return;
end

%% 2. 计算基于信念的期望资源需求
% 智能体不知道任务的确切类型，只知道类型的信念分布
% 期望需求 = Σ_t (belief_t × task_type_demands(t, :))
if ~isfield(Value_Params, 'task_type_demands') || isempty(Value_Params.task_type_demands)
    % 回退到确定性需求（兼容旧代码）
    expected_demand = tasks(task_m).resource_demand;
else
    % 基于信念计算期望需求
    b = Value_data.initbelief(task_m, :);  % 任务m的类型信念分布
    num_types = size(Value_Params.task_type_demands, 1);
    expected_demand = zeros(1, Value_Params.K);
    for t = 1:min(num_types, length(b))
        expected_demand = expected_demand + b(t) * Value_Params.task_type_demands(t, :);
    end
end

%% 3. 计算任务完成度 D_C = (1/Z_c) * Σ(allocated_j / expected_demand_j)
% Z_c: 期望需求中非零资源类型数量
Z_c = nnz(expected_demand > 1e-9);
if Z_c == 0
    individual_utility = 0;
    return;
end

D_C = 0;  % 任务完成度
for j = 1:Value_Params.K
    expected_R_j_m = expected_demand(j);  % 任务m对资源类型j的期望需求
    if expected_R_j_m > 1e-9
        % 计算联盟中所有成员对资源类型j的分配总量
        total_allocated_j = 0;
        for i = member_idx
            % 从Value_data.resources_matrix或agents(i).resources获取分配量
            if isfield(Value_data, 'resources_matrix')
                total_allocated_j = total_allocated_j + Value_data.resources_matrix(task_m, j);
            else
                total_allocated_j = total_allocated_j + agents(i).resources(j);
            end
        end
        % 累加完成度比例（基于期望需求）
        D_C = D_C + (total_allocated_j / expected_R_j_m);
    end
end
D_C = D_C / Z_c;  % 取平均完成度
D_C = min(D_C, 1.0);  % 限制在[0, 1]范围内

%% 4. 计算资源贡献比例 r_n(C) = |A_m^(n)| / Σ|A_m^(i)|
% |A_m^(n)|: 智能体n对任务m的资源分配量（向量的模）
A_m_n = 0;  % 智能体n的资源分配量
total_A_m = 0;  % 联盟总资源分配量

for j = 1:Value_Params.K
    if isfield(Value_data, 'resources_matrix')
        agent_alloc = Value_data.resources_matrix(task_m, j);
    else
        agent_alloc = agents(n).resources(j);
    end
    
    if coalitionstru(task_m, n) == n
        A_m_n = A_m_n + agent_alloc^2;  % 计算模的平方
    end
end
A_m_n = sqrt(A_m_n);  % 资源向量的模

% 计算联盟总资源
for i = member_idx
    agent_total = 0;
    for j = 1:Value_Params.K
        if isfield(Value_data, 'resources_matrix')
            agent_total = agent_total + Value_data.resources_matrix(task_m, j)^2;
        else
            agent_total = agent_total + agents(i).resources(j)^2;
        end
    end
    total_A_m = total_A_m + sqrt(agent_total);
end

r_n_C = 0;
if total_A_m > 0
    r_n_C = A_m_n / total_A_m;  % 资源贡献比例
end

%% 5. 计算联盟总价值 V_C (基于信念的期望价值)
b = Value_data.initbelief(task_m, :);  % 任务m的信念分布
v = tasks(task_m).WORLD.value;         % 任务m的价值向量
V_C = v(1) * b(1) + v(2) * b(2) + v(3) * b(3);  % 期望价值

%% 6. 计算能量消耗（调用统一的能量成本计算函数）
% 找到智能体n参与的所有任务（只考虑真实任务1..M）
agent_tasks = find(coalitionstru(1:Value_Params.M, n) == n);

% 准备资源分配矩阵（用于确定使用的资源类型）
if isfield(Value_data, 'resources_matrix')
    R_agent = Value_data.resources_matrix;
else
    R_agent = [];  % 无资源矩阵时，函数将假设使用所有资源类型
end

% 调用统一的能量成本计算函数，但只计算到task_m为止
% 先找到task_m在任务列表中的位置
if ismember(task_m, agent_tasks)
    % 计算完整的任务序列
    [t_wait_total, T_exec_total_all, ~, ~, orderedTasks] = ...
        compute_agent_energy_cost(n, agent_tasks, agents, tasks, Value_Params, R_agent);
    
    % 找到task_m在排序后的位置
    task_m_pos = find(orderedTasks == task_m, 1);
    
    % 只累计到task_m为止的执行时间
    T_exec = 0;
    tol = 1e-9;
    for ii = 1:task_m_pos
        m = orderedTasks(ii);
        
        % 获取该任务的资源分配
        if ~isempty(R_agent)
            allocRow = R_agent(m, :);
        else
            allocRow = agents(n).resources(:)';
        end
        
        % 确定使用了哪些资源类型
        usedTypes = (allocRow > tol);
        
        % 获取任务执行时间
        if isfield(tasks, 'duration_by_resource')
            dur = tasks(m).duration_by_resource;
            if isscalar(dur)
                T_exec = T_exec + dur * nnz(usedTypes);
            else
                dur = dur(:)';
                if numel(dur) ~= Value_Params.K
                    dur = dur(1:min(numel(dur), Value_Params.K));
                    usedTypes = usedTypes(1:numel(dur));
                end
                T_exec = T_exec + sum(dur(usedTypes));
            end
        else
            % 兼容：无duration_by_resource则使用duration
            if isfield(tasks, 'duration')
                T_exec = T_exec + tasks(m).duration;
            else
                T_exec = T_exec + 1.0;
            end
        end
    end
    
    t_m_wait = t_wait_total;  % 移动时间（整个路径）
    alpha = agents(n).fuel;
    beta = agents(n).beta;
else
    % task_m不在任务列表中，成本为0
    t_m_wait = 0;
    T_exec = 0;
    alpha = agents(n).fuel;
    beta = agents(n).beta;
end

%% 7. 计算最终效用
% utility_n(C) = r_n(C) × V_C × D_C - (t_m^(wait) × α + T_exec × β)
revenue = r_n_C * V_C * D_C;            % 收益部分
cost_flight = t_m_wait * alpha;         % 飞行成本
cost_execution = T_exec * beta;         % 执行成本
total_cost = cost_flight + cost_execution;

individual_utility = revenue - total_cost;

end
