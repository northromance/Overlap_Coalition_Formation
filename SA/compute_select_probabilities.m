function probs = compute_select_probabilities(Value_data, agents, tasks, Value_Params, allocated_resources, resource_gap)

% 计算该智能体对于每种类型任务下的 每种任务的选择概率
%% 步骤 2: 备份当前状态
% backup.coalition = Value_data.coalitionstru;
% backup.iteration = Value_data.iteration;
% backup.unif = Value_data.unif;

%% 步骤 3: 遍历每个agent，根据每个agent对应的选择概率决定是否加入任务的联盟
% incremental = 0;
% coalition = Value_data(1).coalitionstru;  % 获取当前联盟结构

agentID = Value_data.agentID;  % 获取当前agent的ID


% 初始化选择概率矩阵 (R x M)，每行对应一个资源类型下对所有任务的选择概率
probs = zeros(Value_Params.K, Value_Params.M);

% ------------------------------
% 输入矩阵维度约定：
% allocated_resources: N x K，每个智能体每种资源已分配/已占用量
% resource_gap:        M x K，每个任务每种资源的剩余需求（缺口）
% ------------------------------
if nargin < 6
    error('compute_select_probabilities:NotEnoughInputs', 'Need allocated_resources and resource_gap.');
end

if ~isempty(allocated_resources)
    if size(allocated_resources, 2) ~= Value_Params.K
        error('compute_select_probabilities:BadAllocatedResourcesSize', 'allocated_resources must be N x K with K=Value_Params.K');
    end
    if agentID > size(allocated_resources, 1)
        error('compute_select_probabilities:AgentIDOutOfRange', 'agentID exceeds allocated_resources rows.');
    end
end

if ~isempty(resource_gap)
    if size(resource_gap, 1) ~= Value_Params.M || size(resource_gap, 2) ~= Value_Params.K
        error('compute_select_probabilities:BadResourceGapSize', 'resource_gap must be M x K with M=Value_Params.M and K=Value_Params.K');
    end
end


% 示例：基于一个智能体计算每个资源类型下任务的选择概率
% agents: 所有智能体结构体数组
% tasks: 任务结构体，包含每个任务的资源需求、类型、坐标等信息
% Value_data: 包含智能体ID和其他相关数据
% Value_Params: 包含任务数量（M）和资源类型数量（K）

% 若未提供 resource_gap，则可以回退到“基于类型需求+belief 的期望需求”或任务确定需求
if isfield(Value_Params, 'task_type_demands')
    task_type_demands = Value_Params.task_type_demands; % 任务不同类型需求
else
    task_type_demands = [];
end

if ~isempty(task_type_demands)
    num_task_types = size(task_type_demands, 1); % 任务类型
else
    num_task_types = 0;
end

% 遍历每个资源类型 r
for r = 1:Value_Params.K
    % 遍历每个任务 j
    for j = 1:Value_Params.M
        % 1) 任务侧：剩余需求（缺口）优先使用 resource_gap
        if ~isempty(resource_gap)
            remaining_demand = max(resource_gap(j, r), 0); % j任务的 r需求
        else
             error('需求计算错误');
        end
        
        
        % 2) 智能体侧：可用于该资源类型的“剩余能力”= 总能力 - 已分配/已占用
        agent_resource_available = Value_data.resources(r);


        % 获取任务与智能体之间的欧几里得距离
        task_distance = sqrt((tasks(j).x - agents(agentID).x)^2 + ...
            (tasks(j).y - agents(agentID).y)^2);
        if task_distance <= 0
            task_distance = eps;
        end

        % 3) 概率权重：剩余需求 * 可用资源 / 距离
        task_probability = remaining_demand * agent_resource_available / task_distance;

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

