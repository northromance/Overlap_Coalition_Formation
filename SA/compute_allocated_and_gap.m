function [allocated_resources, resource_gap] = compute_allocated_and_gap(Value_data, agents, tasks, Value_Params)
    % 初始化变量
    N = Value_Params.N; % 智能体数量
    M = Value_Params.M; % 任务数量
    K = Value_Params.K; % 资源类型数量

    % 初始化已分配的资源矩阵
    allocated_resources = zeros(N, K); % 每个智能体每种资源类型已分配的资源量

    % 初始化资源缺口矩阵
    resource_gap = zeros(M, K); % 每个任务每种资源类型的缺口

    % 遍历每个智能体
    for i = 1:N
        % 获取当前智能体的联盟任务分配结构
        coalition_tasks = Value_data(i).coalitionstru; % 当前智能体的联盟分配结构
        
        % 遍历每个任务 j，检查智能体是否参与了该任务
        for j = 1:M
            if coalition_tasks(j, i) > 0  % 如果智能体 i 被分配了任务 j（即该位置不为0）
                % 遍历资源类型 r，计算智能体 i 对每种资源类型的已分配资源量
                for r = 1:K
                    % 根据智能体的资源能力添加到已分配资源矩阵
                    allocated_resources(i, r) = allocated_resources(i, r) + agents(i).resources(r);
                end
            end
        end
    end

    % 计算资源缺口
    for j = 1:M
        % 遍历每个任务 j
        for r = 1:K
            % 任务资源需求：根据任务的需求量
            task_resource_demand = tasks(j).resource_demand(r);

            % 计算当前任务资源缺口：任务的资源需求减去已分配的资源
            total_allocated = sum(allocated_resources(:, r));  % 当前资源类型的已分配资源总量
            resource_gap(j, r) = task_resource_demand - total_allocated;  % 计算缺口
        end
    end
end
