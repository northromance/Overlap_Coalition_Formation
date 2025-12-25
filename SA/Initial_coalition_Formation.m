function [coalition] = Initial_coalition_Formation(agents, tasks, Value_data, Value_Params, counter, AddPara)

%% 步骤 2: 备份当前状态
% backup.coalition = Value_data.coalitionstru;
% backup.iteration = Value_data.iteration;
% backup.unif = Value_data.unif;

%% 步骤 3: 遍历每个agent，根据每个agent对应的选择概率决定是否加入任务的联盟
incremental = 0;
coalition = Value_data(1).coalitionstru;  % 获取当前联盟结构


M = Value_Params.M;  % 任务数量
R = Value_Params.K;  % 资源类型数量

for agentIdx = 1:length(agents)
    agentID = agents(agentIdx).id;  % 获取当前agent的ID


    % 初始化选择概率矩阵 (R x M)，每行对应一个资源类型下对所有任务的选择概率
    probs = zeros(R, M);

    %% 计算每个智能体对任务的选择概率
    agent_probs = compute_task_selection_probabilities(agents, tasks, Value_data(agentIdx), Value_Params,probs,M,R);

    % 根据对每种资源根据 agent_probs 概率进行抽样，抽到即为选择哪个任务
    task_idx = choose_task_to_join(agent_probs, agentID, tasks, Value_Params,M,R);

    % 查找task_idx中的不重复任务编号
    unique_task_idx = unique(task_idx);  % 获取task_idx中的唯一任务编号

    % 如果 unique_task_idx 不包含 0，则先将 coalition(M+1, agentID) = 0
    if any(unique_task_idx ~= 0)  % 如果不全是 0
        coalition(Value_Params.M + 1, agentID) = 0;  % 清空特殊任务

        % 遍历每个不重复的任务编号
        for i = 1:length(unique_task_idx)
            current_task_idx = unique_task_idx(i);  % 直接访问不重复任务编号
            % 只处理有效任务编号
            if current_task_idx > 0 && current_task_idx <= Value_Params.M
                % 更新 coalitionstru 矩阵，将智能体 ID 分配给该任务
                coalition(current_task_idx, agentID) = agentID;
                incremental = 1;  % 发生了联盟结构变化
            end
        end
    end
end



%% 根据剩余资源计算每个任务的选择概率
    function probs = compute_task_selection_probabilities(agents, tasks, Value_data, Value_Params, probs, M, R)
        % 示例：基于一个智能体计算每个资源类型下任务的选择概率
        % agents: 所有智能体结构体数组
        % tasks: 任务结构体，包含每个任务的资源需求、类型、坐标等信息
        % Value_data: 包含智能体ID和其他相关数据
        % Value_Params: 包含任务数量（M）和资源类型数量（K）

        % 任务类型的资源需求矩阵（行：任务类型，列：资源类型）
        % 来自 Main.m 中生成的 task_type_demands
        if isfield(Value_Params, 'task_type_demands')
            task_type_demands = Value_Params.task_type_demands;
        else
            % 回退：若未提供按类型的需求矩阵，则退回到原始的确定需求
            task_type_demands = [];
        end

        % 任务类型数（与 belief 维度一致）
        if ~isempty(task_type_demands)
            num_task_types = size(task_type_demands, 1);
        else
            num_task_types = 0;
        end

        % 遍历每个资源类型 r
        for r = 1:R
            % 遍历每个任务 j
            for j = 1:Value_Params.M
                % 根据不同任务类型和当前智能体对任务类型的 belief，计算资源 r 的期望需求
                if num_task_types > 0
                    expected_demand = 0;
                    for c = 1:num_task_types
                        % 当前智能体对任务 j 属于类型 c 的信念（probability）
                        p_c = Value_data.initbelief(j, c);

                        % 类型 c 在资源 r 上的需求
                        d_c_r = task_type_demands(c, r);

                        expected_demand = expected_demand + p_c * d_c_r;
                    end
                    remaining_resource = expected_demand;
                else
                    % 若没有类型化需求矩阵，则退回到任务给定的确定资源需求
                    remaining_resource = tasks(j).resource_demand(r);
                end

                % 获取智能体对资源类型 r 的能力（通过 Value_data.agentID 获取对应智能体）
                agent_resource = agents(Value_data.agentID).resources(r);

                % 获取任务与智能体之间的欧几里得距离
                task_distance = sqrt((tasks(j).x - agents(Value_data.agentID).x)^2 + ...
                    (tasks(j).y - agents(Value_data.agentID).y)^2);

                % 计算该任务在资源类型 r 下的选择概率，公式为：剩余资源需求 * 智能体资源量 / 距离
                task_probability = remaining_resource * agent_resource / task_distance;

                % 将计算得到的选择概率存储到 probs 矩阵的相应位置
                probs(r, j) = task_probability;
            end

            % 检查该资源类型下所有任务的选择概率总和是否为零
            total_prob = sum(probs(r, :));

            if total_prob > 0
                % 如果概率总和大于 0，则归一化每个资源类型 r 对应的任务选择概率，使得选择概率之和为 1
                probs(r, :) = probs(r, :) / total_prob;
            end
            % 如果 total_prob == 0，保持原始概率不变
        end
    end





%% 根据选择概率来选择任务
    function task_idx = choose_task_to_join(agent_probs, agentID, tasks, Value_Params, M, R)
        % agent_probs: R x M 矩阵，存储每种资源类型下的任务选择概率
        % agentID: 当前智能体的 ID
        % tasks: 任务结构体，包含每个任务的资源需求、类型、坐标等信息
        % Value_Params: 包含任务数量（M）和空任务的编号（M+1）

        % 初始化任务选择索引数组，表示每个资源类型的任务选择
        task_idx = zeros(R, 1);  % 每个资源类型选择的任务编号

        % 遍历每种资源类型 r
        for r = 1:R
            % 获取该资源类型下的任务选择概率
            probs = agent_probs(r, :);  % 当前资源类型下对所有任务的选择概率

            % 检查该资源类型的所有任务概率是否都为零
            if all(probs == 0)
                % 如果该资源类型的所有任务概率都为零，说明智能体没有该资源能力
                % 将该资源类型的任务选择设置为 "空任务" (即任务编号 M + 1)
                task_idx(r) = Value_Params.M + 1;
            else
                % 进行概率抽样
                rand_value = rand;  % 生成一个[0,1]之间的随机数
                cumulative_prob = cumsum(probs) / sum(probs);  % 累积概率

                % 根据随机值选择任务
                task_idx(r) = find(cumulative_prob >= rand_value, 1);  % 找到第一个累计概率大于随机值的任务
            end
        end

        % 返回任务选择结果
        % task_idx 现在是 R x 1 的向量，表示每个资源类型选择的任务编号
    end

end