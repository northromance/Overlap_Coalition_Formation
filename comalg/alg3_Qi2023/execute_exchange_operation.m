function SC_new = execute_exchange_operation(agent_idx, agents, tasks, SC_current, probs, Value_Params, Value_data, AddPara)
% EXECUTE_EXCHANGE_OPERATION 执行资源交换操作：不可拆分但可复用的资源分配
%
% 修改后的核心逻辑：
%   - 资源是原子化的（全额投入），但具有"可复用性"（Non-consumable） [cite: 188, 189]
%   - 智能体决定参与一个新任务时，不再撤回已在其他任务中投入的该类资源
%   - 最终形成重叠联盟结构 (Overlapping Coalition Structure) [cite: 120, 155]
%   - 【新增】每次投入资源前进行可行性检查（包括能量约束和队友检查）

SC_new = SC_current;
M = Value_Params.M;
K = Value_Params.K;

% 获取置信度参数
confidence = 0.9;
if nargin >= 8 && isfield(AddPara, 'resource_confidence')
    confidence = AddPara.resource_confidence;
end

% 遍历该智能体持有的 K 种资源类型
for k = 1:K
    resource_amt = agents(agent_idx).resources(k);
    if resource_amt <= 0, continue; end

    %% 1. 采样选择目标任务
    prob_vec = probs(k, :);
    cum_prob = cumsum(prob_vec);
    if cum_prob(end) > 0
        r = rand * cum_prob(end);
        selected_task = find(cum_prob >= r, 1, 'first');
    else
        selected_task = randi(M);
    end
    if isempty(selected_task), selected_task = randi(M); end

    %% 2. 【关键修改】不再清空旧分配
    % 文献中不可消耗资源的交换定义为"加入"或"离开"
    % 这里我们保留该智能体在其他任务 m (m ~= selected_task) 上的资源 k 投入
    % 这体现了资源的"复用性"：同一个设备同时在多个任务联盟中发挥作用 [cite: 267]

    %% 3. 投入逻辑
    % 检查该智能体是否已经参与了此任务
    if SC_new{selected_task}(agent_idx, k) > 0
        if AddPara.verbose
            fprintf('  [状态保持] 智能体 #%-2d 资源 k=%-2d 已在任务 M=%-2d 中复用\n', agent_idx, k, selected_task);
        end
        continue;
    end

    % 计算目标任务的期望需求缺口
    curr_alloc = sum(SC_new{selected_task}(:, k));

    % 获取当前智能体的信念
    if length(Value_data) == 1
        % 如果传入的是单个智能体的 Value_data
        belief = Value_data.initbelief(selected_task, :);
    else
        % 如果传入的是 Value_data 数组
        belief = Value_data(agent_idx).initbelief(selected_task, :);
    end

    task_type_demands = Value_Params.task_type_demands;
    expected_demand = WorldSim.calculate_demand_quantile(belief, task_type_demands, confidence);
    demand_k = expected_demand(k);

    can_add = max(0, demand_k - curr_alloc);

    % 如果有缺口，则尝试将资源"复用"到该任务中
    if can_add > 0
        % 创建候选 SC（尝试投入资源）
        SC_candidate = SC_new;
        SC_candidate{selected_task}(agent_idx, k) = resource_amt;

        %% 【新增】可行性检查（包括能量约束和队友检查）
        % 需要构建完整的 Value_data 结构用于检查
        if length(Value_data) == 1
            % 如果传入的是单个智能体的 Value_data，需要构建完整数组
            Value_data_temp = Value_data;
            Value_data_temp.SC = SC_candidate;
            Value_data_array = repmat(Value_data_temp, Value_Params.N, 1);
            for j = 1:Value_Params.N
                Value_data_array(j).agentID = j;
                Value_data_array(j).SC = SC_candidate;
            end
        else
            % 如果传入的是 Value_data 数组，直接使用并更新 SC
            Value_data_array = Value_data;
            for j = 1:Value_Params.N
                Value_data_array(j).SC = SC_candidate;
            end
        end

        % 调用 validate_feasibility 检查可行性（启用队友检查）
        [isFeasible, info, ~] = validate_feasibility(Value_data_array, agents, tasks, ...
            Value_Params, agent_idx, SC_candidate, true, AddPara);

        if isFeasible
            % 可行，接受新的分配
            SC_new = SC_candidate;
            if AddPara.verbose
                fprintf('  [资源复用] Agent #%-2d -> Task M=%-2d | ResType k=%-2d | Amount: %-6.2f | 可行 ✓\n', ...
                    agent_idx, selected_task, k, resource_amt);
            end
        else
            % 不可行，拒绝投入
            if AddPara.verbose
                fprintf('  [拒绝投入] Agent #%-2d -> Task M=%-2d | ResType k=%-2d | 原因: %s ✗\n', ...
                    agent_idx, selected_task, k, info.reason);
            end
        end
    else
        if AddPara.verbose
            fprintf('  [复用跳过] 智能体 #%-2d | 资源类型 k=%-2d | 任务 M=%-2d 需求已饱和，无需复用投入\n', ...
                agent_idx, k, selected_task);
        end
    end
end
end
