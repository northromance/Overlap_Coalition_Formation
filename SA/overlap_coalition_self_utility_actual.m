function individual_utility = overlap_coalition_self_utility_actual(n, task_m, SC, agents, tasks, Value_Params)
% =========================================================================
% OVERLAP_COALITION_SELF_UTILITY_ACTUAL: 计算智能体在特定任务联盟中的个体效用（使用实际需求）
%
% 与 overlap_coalition_self_utility 的区别：
%   - 使用任务的实际资源需求，而不是基于信念的期望需求
%   - 使用任务的实际价值，而不是基于信念的期望价值
%   - 用于计算最终的真实联盟效用
%
% 基于公式:
%   utility_n(C) = r_n(C) × V_C × D_C - (t_m^(wait) × α + T_exec(n,m) × β)
%
% 输入参数:
%   n - 智能体ID
%   task_m - 任务索引
%   SC - 资源联盟结构（cell数组，长度M），SC{m}是N×K矩阵
%   agents - 智能体信息数组
%   tasks - 任务信息数组
%   Value_Params - 参数结构体 (包含K, M, N, alpha, beta等)
%
% 输出参数:
%   individual_utility - 智能体n在任务task_m中的效用值（基于实际需求和价值）
% =========================================================================

%% 空任务检查
if task_m < 1 || task_m > Value_Params.M
    individual_utility = 0;
    return;
end

%% 1. 获取参与该任务的联盟成员（从SC中判断）
% member_idx：有任何资源分配给task_m的智能体列表
member_idx = [];
for i = 1:Value_Params.N
    if any(SC{task_m}(i, :) > 0)
        member_idx = [member_idx, i];
    end
end

if isempty(member_idx)
    individual_utility = 0;
    return;
end

%% 2. 使用任务的实际资源需求（不是期望需求）
actual_demand = tasks(task_m).resource_demand;

%% 3. 计算任务完成度 D_C = (1/Z_c) * Σ(allocated_j / actual_demand_j)
Z_c = nnz(actual_demand > 1e-9);
if Z_c == 0
    individual_utility = 0;
    return;
end

D_C = 0;
for j = 1:Value_Params.K
    actual_R_j_m = actual_demand(j);
    if actual_R_j_m > 1e-9
        % 计算联盟中所有成员对资源类型j的分配总量（从SC中读取）
        total_allocated_j = sum(SC{task_m}(:, j));
        % 单个资源类型的完成度，超过需求则截断到1.0
        resource_ratio = min(total_allocated_j / actual_R_j_m, 1.0);
        D_C = D_C + resource_ratio;
    end
end
D_C = D_C / Z_c;

%% 4. 计算资源贡献比例 r_n(C) = |A_m^(n)| / Σ|A_m^(i)|
% |A_m^(n)|: 智能体n对任务m的资源分配量（向量的模）
A_m_n_vec = SC{task_m}(n, :);  % 智能体n对任务m的资源分配向量 (1×K)
A_m_n = norm(A_m_n_vec);       % 计算模

% 计算联盟总资源
total_A_m = 0;
for i = member_idx
    agent_vec = SC{task_m}(i, :);
    total_A_m = total_A_m + norm(agent_vec);
end

r_n_C = 0;
if total_A_m > 0
    r_n_C = A_m_n / total_A_m;
end

%% 5. 使用任务的实际价值（不是期望价值）
V_C = tasks(task_m).value;

%% 6. 计算能量消耗
% 找到智能体n参与的所有任务（从SC判断）
agent_tasks = [];
for m = 1:Value_Params.M
    if any(SC{m}(n, :) > 0)
        agent_tasks = [agent_tasks, m];
    end
end

% 准备资源分配矩阵（M×K），用于确定使用的资源类型
R_agent = zeros(Value_Params.M, Value_Params.K);
for m = 1:Value_Params.M
    R_agent(m, :) = SC{m}(n, :);  % 从SC中提取智能体n的资源分配
end

% 调用统一的能量成本计算函数
if ismember(task_m, agent_tasks)
    [t_wait_total, T_exec_total_all, ~, ~, orderedTasks] = ...
        energy_cost(n, agent_tasks, agents, tasks, Value_Params, R_agent);
    
    % 找到task_m在排序后的位置
    task_m_pos = find(orderedTasks == task_m, 1);
    
    % 只累计到task_m为止的执行时间
    T_exec = 0;
    tol = 1e-9;
    for ii = 1:task_m_pos
        m = orderedTasks(ii);
        
        % 获取该任务的资源分配
        allocRow = R_agent(m, :);
        
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
            if isfield(tasks, 'duration')
                T_exec = T_exec + tasks(m).duration;
            else
                T_exec = T_exec + 1.0;
            end
        end
    end
    
    t_m_wait = t_wait_total;
    alpha = agents(n).fuel;
    beta = agents(n).beta;
else
    t_m_wait = 0;
    T_exec = 0;
    alpha = agents(n).fuel;
    beta = agents(n).beta;
end

%% 7. 计算最终效用（基于实际需求和价值）
revenue = r_n_C * V_C * D_C;
cost_flight = t_m_wait * alpha;
cost_execution = T_exec * beta;
total_cost = cost_flight + cost_execution;

individual_utility = revenue - total_cost;

end
