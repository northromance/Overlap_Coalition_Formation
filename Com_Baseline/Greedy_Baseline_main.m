function [Value_data, history_data] = Greedy_Baseline_main(agents, tasks, AddPara, Value_Params)
% GREEDY_BASELINE_MAIN 贪心基线算法（示例对比算法）
%
% 算法描述：
%   简单的贪心策略，按任务优先级顺序处理：
%   1. 对每个任务，选择距离最近且资源充足的智能体
%   2. 如果单个智能体资源不足，添加更多智能体形成联盟
%   3. 分配资源直到满足任务需求或资源耗尽
%
% 输入：
%   agents - 智能体结构体数组
%   tasks - 任务结构体数组
%   AddPara - 附加参数
%   Value_Params - 算法参数
%
% 输出：
%   Value_data - 包含联盟结构和效用的结果
%   history_data - 算法运行历史数据（可选）

    %% 提取参数
    N = Value_Params.N;  % 智能体数量
    M = Value_Params.M;  % 任务数量
    K = Value_Params.K;  % 资源类型数量
    
    %% 初始化输出结构
    coalitionstru = zeros(M, N);         % 联盟结构矩阵 (M×N)
    agentresources = zeros(N, M, K);     % 资源分配矩阵 (N×M×K)
    
    % 跟踪智能体剩余资源
    remaining_resources = zeros(N, K);
    for i = 1:N
        remaining_resources(i, :) = agents(i).resources';
    end
    
    %% 按优先级排序任务
    [~, task_order] = sort([tasks.priority]);
    
    %% 贪心分配
    for idx = 1:M
        j = task_order(idx);  % 当前处理的任务ID
        
        % 获取任务需求
        task_demand = tasks(j).resource_demand;  % 1×K
        allocated_resources = zeros(1, K);       % 已分配的资源
        
        % 计算所有智能体到任务的距离
        distances = zeros(1, N);
        for i = 1:N
            distances(i) = sqrt((agents(i).x - tasks(j).x)^2 + ...
                               (agents(i).y - tasks(j).y)^2);
        end
        
        % 按距离从近到远排序智能体
        [~, agent_order] = sort(distances);
        
        % 逐个添加智能体，直到满足任务需求
        for agent_idx = 1:N
            i = agent_order(agent_idx);
            
            % 检查是否还需要更多资源
            still_needed = task_demand - allocated_resources;
            if all(still_needed <= 0)
                break;  % 任务需求已满足
            end
            
            % 检查该智能体是否有可贡献的资源
            can_contribute = false;
            for k = 1:K
                if still_needed(k) > 0 && remaining_resources(i, k) > 0
                    can_contribute = true;
                    break;
                end
            end
            
            if can_contribute
                % 将该智能体加入联盟
                coalitionstru(j, i) = 1;
                
                % 分配资源
                for k = 1:K
                    needed = still_needed(k);
                    available = remaining_resources(i, k);
                    
                    if needed > 0 && available > 0
                        allocation = min(needed, available);
                        agentresources(i, j, k) = allocation;
                        remaining_resources(i, k) = remaining_resources(i, k) - allocation;
                        allocated_resources(k) = allocated_resources(k) + allocation;
                    end
                end
            end
        end
    end
    
    %% 计算总效用
    totalvalue = 0;
    for j = 1:M
        members = find(coalitionstru(j, :) ~= 0);
        if ~isempty(members)
            % 获取任务需求和已分配资源
            allocated = squeeze(sum(agentresources(:, j, :), 1))';  % 1×K
            demand = tasks(j).resource_demand;  % 1×K
            
            % 计算任务完成度 D_C（使用统一函数）
            D_C = OCFUtils.calc_task_completion_degree(allocated, demand, K);
            
            % 计算距离成本
            total_distance = 0;
            for i = members
                dist = sqrt((agents(i).x - tasks(j).x)^2 + ...
                           (agents(i).y - tasks(j).y)^2);
                total_distance = total_distance + dist;
            end
            
            % 统一效用公式：效用 = 任务价值 × 完成度 - 距离成本
            % 距离成本系数设为0.1（与其他算法一致）
            distance_cost = total_distance * 0.1;
            utility = tasks(j).value * D_C - distance_cost;
            totalvalue = totalvalue + utility;
        end
    end
    
    %% 后处理：按优先级构建闭环路径并扣除能耗
    agent_paths = cell(1, N);
    total_energy_cost = 0;
    for n = 1:N
        % 参与任务集合
        task_ids = find(coalitionstru(:, n) ~= 0);
        if isempty(task_ids)
            agent_paths{n} = [];
            continue;
        end
        
        % 按任务优先级降序排序（数值越大优先级越高）
        priorities = [tasks(task_ids).priority];
        [~, idx_sort] = sort(priorities, 'descend');
        sorted_tasks = task_ids(idx_sort);
        agent_paths{n} = sorted_tasks;
        
        % 闭环路径：Depot -> tasks -> Depot
        curr_pos = [agents(n).x, agents(n).y];
        dist_n = 0;
        for t_idx = 1:length(sorted_tasks)
            tid = sorted_tasks(t_idx);
            tgt = [tasks(tid).x, tasks(tid).y];
            dist_n = dist_n + norm(curr_pos - tgt);
            curr_pos = tgt;
        end
        dist_n = dist_n + norm(curr_pos - [agents(n).x, agents(n).y]);
        
        % 能耗成本
        fuel_cost = 1;
        if isfield(agents, 'fuel')
            fuel_cost = agents(n).fuel;
        end
        total_energy_cost = total_energy_cost + dist_n * fuel_cost;
    end
    
    % 扣除能耗
    totalvalue = totalvalue - total_energy_cost;
    
    %% 构造输出
    Value_data(1).totalvalue = totalvalue;
    Value_data(1).coalitionstru = coalitionstru;
    Value_data(1).agentresources = agentresources;
    Value_data(1).energy_cost = total_energy_cost;
    Value_data(1).agent_paths = agent_paths;
    
    % 可选：添加更多统计信息
    Value_data(1).num_coalitions = sum(sum(coalitionstru, 2) > 0);
    Value_data(1).avg_coalition_size = mean(sum(coalitionstru, 2));
    
    %% 历史数据（简化版本）
    history_data = struct();
    history_data.algorithm = 'Greedy_Baseline';
    history_data.final_utility = totalvalue;
    history_data.task_assignment_order = task_order;
    
end

