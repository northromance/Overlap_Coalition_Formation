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

%% 2. 计算任务完成度 D_C = (1/Z_c) * Σ(Σ A_j^(i) / R_j^(m))
% Z_c: 任务所需的资源类型数量
Z_c = nnz(tasks(task_m).resource_demand);  % 非零资源类型数量
if Z_c == 0
    individual_utility = 0;
    return;
end

D_C = 0;  % 任务完成度
for j = 1:Value_Params.K
    R_j_m = tasks(task_m).resource_demand(j);  % 任务m对资源类型j的需求
    if R_j_m > 0
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
        % 累加完成度比例
        D_C = D_C + (total_allocated_j / R_j_m);
    end
end
D_C = D_C / Z_c;  % 取平均完成度
D_C = min(D_C, 1.0);  % 限制在[0, 1]范围内

%% 3. 计算资源贡献比例 r_n(C) = |A_m^(n)| / Σ|A_m^(i)|
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

%% 4. 计算联盟总价值 V_C (基于信念的期望价值)
b = Value_data.initbelief(task_m, :);  % 任务m的信念分布
v = tasks(task_m).WORLD.value;         % 任务m的价值向量
V_C = v(1) * b(1) + v(2) * b(2) + v(3) * b(3);  % 期望价值

%% 5. 计算飞行时间 t_m^(wait) (基于任务序列的累积飞行时间)
% 找到智能体n参与的所有任务（按某种顺序）
agent_tasks = find(coalitionstru(:, n) == n);  % 智能体n参与的任务列表
task_order = sort(agent_tasks);  % 按任务索引排序（实际应按优先级或序列排序）

% 计算到任务task_m的累积飞行时间
t_m_wait = 0;
if ~isempty(task_order)
    % 找到task_m在序列中的位置
    task_pos = find(task_order == task_m, 1);
    if ~isempty(task_pos)
        % 从初始位置飞到第一个任务
        if task_pos >= 1
            prev_x = agents(n).x;
            prev_y = agents(n).y;
            for k = 1:task_pos
                cur_task = task_order(k);
                cur_x = tasks(cur_task).x;
                cur_y = tasks(cur_task).y;
                % 计算飞行距离和时间
                distance = sqrt((cur_x - prev_x)^2 + (cur_y - prev_y)^2);
                t_m_wait = t_m_wait + distance / agents(n).speed;  % 假设有speed字段
                prev_x = cur_x;
                prev_y = cur_y;
            end
        end
    end
end

%% 6. 计算执行时间 T_exec(n, m) (所有任务的累积执行时间)
T_exec = 0;
for k = 1:length(task_order)
    cur_task = task_order(k);
    % 任务执行时间可能存储在tasks(cur_task).duration字段
    if isfield(tasks, 'duration')
        T_exec = T_exec + tasks(cur_task).duration;
    else
        T_exec = T_exec + 1.0;  % 默认执行时间
    end
    
    % 如果到达task_m则停止累加
    if cur_task == task_m
        break;
    end
end

%% 7. 获取成本参数
alpha = Value_Params.alpha;  % 每小时飞行燃油消耗
beta = Value_Params.beta;    % 每小时执行任务能耗

%% 8. 计算最终效用
% utility_n(C) = r_n(C) × V_C × D_C - (t_m^(wait) × α + T_exec × β)
revenue = r_n_C * V_C * D_C;            % 收益部分
cost_flight = t_m_wait * alpha;         % 飞行成本
cost_execution = T_exec * beta;         % 执行成本
total_cost = cost_flight + cost_execution;

individual_utility = revenue - total_cost;

end
