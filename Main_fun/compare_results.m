function comparison_stats = compare_results(results, agents, tasks, Value_Params)
% COMPARE_RESULTS 对多算法运行结果进行全面的对比分析与指标统计。
% 该函数能够兼容不同算法的数据结构（如是否存在 SC 字段、资源矩阵维度差异等），
% 计算总效用、完成度、资源利用率、能耗等核心指标。
%
% 输入：
%   results      - (Struct) 包含各算法结果的结构体 (key=算法名, value=结果数据)。
%   agents       - (Struct Array) 智能体属性数组。
%   tasks        - (Struct Array) 任务属性数组。
%   Value_Params - (Struct) 全局参数集合 (含 M, N, K 等)。
%
% 输出：
%   comparison_stats - (Struct) 包含各算法详细性能指标的结构体，用于绘图和表格展示。

    % 获取结果集中包含的所有算法名称
    alg_names = fieldnames(results);
    num_algorithms = length(alg_names);
    
    % 初始化输出结构体
    comparison_stats = struct();
    
    % 遍历每个算法进行独立分析
    for i = 1:num_algorithms
        alg_name = alg_names{i};
        alg_result = results.(alg_name);
        
        % --- 0. 基础信息提取 ---
        comparison_stats.(alg_name).name = alg_result.name;               % 算法显示名称
        comparison_stats.(alg_name).computation_time = alg_result.computation_time; % 计算耗时
        
        % 错误检查：如果算法运行失败，记录错误信息并跳过后续计算
        if isfield(alg_result, 'error')
            comparison_stats.(alg_name).has_error = true;
            comparison_stats.(alg_name).error_message = alg_result.error.message;
            continue;
        end
        comparison_stats.(alg_name).has_error = false;
        
        % 提取核心数据结构：Value_data (状态快照) 和 history_data (迭代历史)
        Value_data = alg_result.Value_data;
        history_data = [];
        if isfield(alg_result, 'history_data')
            history_data = alg_result.history_data;
        end
        
        %% ==================== 1. 总效用 (Total Utility) 计算 ====================
        % 逻辑：尝试从多个来源获取总效用，优先级：
        % 1. Value_data.totalvalue (直接存储)
        % 2. history_data 最后一轮的效用和
        % 3. 根据 SC (资源联盟结构) 手动重新计算 (适用于 SA 等未直接存储总值的算法)
        
        total_utility = 0;
        
        if isfield(Value_data, 'totalvalue')
            % 来源1：直接读取字段（常见于 Huo2025 等算法）
            total_utility = Value_data(1).totalvalue;
        elseif ~isempty(history_data) && isfield(history_data, 'rounds')
            % 来源2：从收敛曲线历史中提取最后一轮数据
            num_rounds = length(history_data.rounds);
            if num_rounds > 0 && isfield(history_data.rounds(num_rounds), 'task_utilities')
                total_utility = sum(history_data.rounds(num_rounds).task_utilities);
            end
        end
        
        % 来源3：如果上述方式均为0，且存在详细分配方案 SC，则手动计算
        if total_utility == 0 && isfield(Value_data, 'SC')
                fprintf('警告: 计算总效用时出错 ');
        end
        
        comparison_stats.(alg_name).total_utility = total_utility;
        
        %% ==================== 2. 联盟结构 (Coalition Structure) 分析 ====================
        % coal 矩阵：行代表任务，列代表智能体。非零值表示智能体参与该任务。
        
        coal = Value_data(1).coalitionstru;
        M = size(coal, 1);
        N = size(coal, 2);
        
        % 维度裁剪：确保不超过实际任务列表长度
        if M > length(tasks)
            coal = coal(1:length(tasks), :);
            M = length(tasks);
        end
        
        % 统计联盟数量及各联盟的大小（成员数）
        num_coalitions = 0;
        coalition_sizes = [];
        for j = 1:M
            members = find(coal(j, :) ~= 0); % 查找第 j 个任务的所有成员
            if ~isempty(members)
                num_coalitions = num_coalitions + 1;
                coalition_sizes(end+1) = length(members); %#ok<AGROW>
            end
        end
        comparison_stats.(alg_name).num_coalitions = num_coalitions;
        
        % 计算最大、最小和平均联盟规模
        if ~isempty(coalition_sizes)
            comparison_stats.(alg_name).avg_coalition_size = mean(coalition_sizes);
            comparison_stats.(alg_name).max_coalition_size = max(coalition_sizes);
            comparison_stats.(alg_name).min_coalition_size = min(coalition_sizes);
        else
            comparison_stats.(alg_name).avg_coalition_size = 0;
            comparison_stats.(alg_name).max_coalition_size = 0;
            comparison_stats.(alg_name).min_coalition_size = 0;
        end
        
        %% ==================== 3. 任务完成度 (Completion Degree) 分析 ====================
        % 计算每个任务的资源满足程度 D_C (0~1)，这是衡量分配质量的关键指标。
        
        comparison_stats.(alg_name).completed_tasks = num_coalitions; % 简单计数：有成员即视为处理中
        comparison_stats.(alg_name).task_completion_rate = num_coalitions / length(tasks) * 100; % 覆盖率
        
        task_completion_degrees = zeros(M, 1);
        
        % 分情况计算完成度：优先使用详细的 SC 结构，否则使用 agentresources 矩阵
        if isfield(Value_data, 'SC') && ~isempty(Value_data(1).SC)
            % 情况 A: 算法提供了 SC (N x K 分配矩阵)
            SC = Value_data(1).SC;
            for j = 1:min(M, length(SC))
                if ~isempty(SC{j})
                    task_demand = tasks(j).resource_demand;
                    % 调用通用工具计算完成度
                    task_completion_degrees(j) = OCFUtils.calc_task_completion_degree(SC{j}, task_demand, Value_Params.K);
                end
            end
        elseif isfield(Value_data, 'agentresources') && ~isempty(Value_data(1).agentresources)
            % 情况 B: 算法仅提供了 agentresources 矩阵 (可能是 2D 或 3D)
            agentresources = Value_data(1).agentresources;
            agentresources_size = size(agentresources);
            num_dims = ndims(agentresources);
            
            for j = 1:M
                members = find(coal(j, :) ~= 0);
                if ~isempty(members)
                    task_demand = tasks(j).resource_demand;
                    allocated = zeros(1, Value_Params.K);
                    
                    % 汇总该任务收到的所有资源
                    for k = 1:Value_Params.K
                        if num_dims >= 3
                            % 3D 矩阵: (Agent, Task, ResourceType)
                            for ag_idx = members
                                if ag_idx <= agentresources_size(1) && j <= agentresources_size(2) && k <= agentresources_size(3)
                                    allocated(k) = allocated(k) + agentresources(ag_idx, j, k);
                                end
                            end
                        elseif num_dims == 2
                            % 2D 矩阵: 近似处理，假设行是Agent列是Task，仅作为存在性判断
                            if j <= agentresources_size(2)
                                allocated(k) = task_demand(k); % 无法得知具体类型，做乐观估计
                            end
                        end
                    end
                    task_completion_degrees(j) = OCFUtils.calc_task_completion_degree(allocated, task_demand, Value_Params.K);
                end
            end
        end
        
        % 详细统计指标
        comparison_stats.(alg_name).task_completion_degrees = task_completion_degrees;  % 明细数据
        comparison_stats.(alg_name).total_completion_score = sum(task_completion_degrees);  % 综合得分
        comparison_stats.(alg_name).normalized_completion_rate = (sum(task_completion_degrees) / M) * 100;  % 归一化完成率(考虑质量)
        comparison_stats.(alg_name).avg_task_completion = mean(task_completion_degrees(task_completion_degrees > 0));  % 仅统计参与任务的平均质量
        comparison_stats.(alg_name).fully_completed_tasks = sum(task_completion_degrees >= 0.999);  % 完美完成数
        comparison_stats.(alg_name).partially_completed_tasks = sum(task_completion_degrees > 0 & task_completion_degrees < 0.999);  % 部分完成数
        
        if isnan(comparison_stats.(alg_name).avg_task_completion)
            comparison_stats.(alg_name).avg_task_completion = 0;
        end
        
        %% ==================== 4. 资源利用率 (Resource Utilization) ====================
        % 计算系统总资源的占用比例。
        
        total_resources_available = 0;
        total_resources_allocated = 0;
        
        % 计算所有智能体的初始资源总和
        for ag_idx = 1:length(agents)
            total_resources_available = total_resources_available + sum(agents(ag_idx).resources);
        end
        
        % 计算已分配出去的资源总和
        if isfield(Value_data, 'SC') && ~isempty(Value_data(1).SC)
            SC = Value_data(1).SC;
            for m = 1:min(length(SC), M)
                if ~isempty(SC{m})
                    total_resources_allocated = total_resources_allocated + sum(SC{m}(:)); % 矩阵所有元素求和
                end
            end
        elseif isfield(Value_data, 'agentresources') && ~isempty(Value_data(1).agentresources)
            % 兼容旧数据结构的处理
            agentresources_size = size(Value_data(1).agentresources);
            num_dims = ndims(Value_data(1).agentresources);
            max_agents = min(N, agentresources_size(1));
            max_tasks = min(M, agentresources_size(2));
            for ag_idx = 1:max_agents
                for task_idx = 1:max_tasks
                    if num_dims >= 3
                        total_resources_allocated = total_resources_allocated + ...
                            sum(Value_data(1).agentresources(ag_idx, task_idx, :));
                    else
                        total_resources_allocated = total_resources_allocated + ...
                            Value_data(1).agentresources(ag_idx, task_idx);
                    end
                end
            end
        end
        
        % 计算百分比
        if total_resources_available > 0
            comparison_stats.(alg_name).resource_utilization = ...
                total_resources_allocated / total_resources_available * 100;
        else
            comparison_stats.(alg_name).resource_utilization = 0;
        end
        
        %% ==================== 5. 智能体参与度 (Agent Participation) ====================
        % 统计每个智能体平均参与了多少个任务。
        
        agent_participation = zeros(1, N);
        for ag_idx = 1:N
            agent_participation(ag_idx) = sum(coal(:, ag_idx) ~= 0); % 统计非零项
        end
        
        comparison_stats.(alg_name).avg_agent_participation = mean(agent_participation);
        comparison_stats.(alg_name).max_agent_participation = max(agent_participation);
        comparison_stats.(alg_name).agent_participation_std = std(agent_participation); % 标准差反映负载均衡情况
        
        %% ==================== 6. 能量消耗统计 (Energy Cost) ====================
        % 如果算法记录了移动或计算能耗，进行统计。
        
        if isfield(Value_data, 'energy_cost')
            comparison_stats.(alg_name).total_energy_cost = sum(Value_data(1).energy_cost);
            comparison_stats.(alg_name).avg_energy_per_task = ...
                comparison_stats.(alg_name).total_energy_cost / num_coalitions;
        else
            comparison_stats.(alg_name).total_energy_cost = NaN;
            comparison_stats.(alg_name).avg_energy_per_task = NaN;
        end
        
        %% ==================== 7. 任务价值统计 (Value Achievement) ====================
        % 对比“理论总价值”与“实际获得的加权价值”。
        
        total_value_achieved = 0; % 仅考虑已形成联盟的任务原始价值
        total_value_possible = 0; % 所有任务的理论总价值
        
        for j = 1:M
            total_value_possible = total_value_possible + tasks(j).value;
            members = find(coal(j, :) ~= 0);
            if ~isempty(members)
                total_value_achieved = total_value_achieved + tasks(j).value;
            end
        end
        
        comparison_stats.(alg_name).total_value_achieved = total_value_achieved;
        comparison_stats.(alg_name).total_value_possible = total_value_possible;
        comparison_stats.(alg_name).value_achievement_rate = ...
            total_value_achieved / total_value_possible * 100;
        
        % [更精确的指标] completed_value: 任务价值 * 完成度
        % 这反映了即便任务未100%完成，其部分完成带来的收益
        task_values = arrayfun(@(t) t.value, tasks(1:M));
        completed_value = sum(task_values(:) .* task_completion_degrees(1:M));
        
        comparison_stats.(alg_name).completed_value = completed_value;
        comparison_stats.(alg_name).completed_value_rate = completed_value / total_value_possible * 100;
        comparison_stats.(alg_name).completed_value_by_task = task_values(:) .* task_completion_degrees(1:M);
        
        %% ==================== 8. 效用效率 (Utility Efficiency) ====================
        % ROI 指标：单位计算时间产生的效用。
        
        if comparison_stats.(alg_name).computation_time > 0
            comparison_stats.(alg_name).utility_efficiency = ...
                comparison_stats.(alg_name).total_utility / ...
                comparison_stats.(alg_name).computation_time;
        else
            comparison_stats.(alg_name).utility_efficiency = Inf;
        end
        
        %% ==================== 9. 资源匹配度 (Resource Match Ratio) ====================
        % 全局层面：总分配量 / 总需求量。如果 > 1 说明存在资源浪费或溢出。
        
        total_demand = 0;
        total_allocated = 0;
        
        % 获取资源矩阵维度信息
        if isfield(Value_data, 'agentresources') && ~isempty(Value_data(1).agentresources)
            agentresources_size = size(Value_data(1).agentresources);
            num_dims = ndims(Value_data(1).agentresources);
        else
            agentresources_size = [0, 0, 0];
            num_dims = 0;
        end
        
        % 累加所有任务的需求和分配
        for j = 1:M
            members = find(coal(j, :) ~= 0);
            if ~isempty(members)
                task_demand = tasks(j).resource_demand;
                for k = 1:Value_Params.K
                    total_demand = total_demand + task_demand(k);
                    
                    % 累加分配量 (兼容 2D/3D 格式)
                    if num_dims >= 3
                        for ag_idx = members
                            if ag_idx <= agentresources_size(1) && j <= agentresources_size(2) && k <= agentresources_size(3)
                                total_allocated = total_allocated + ...
                                    Value_data(1).agentresources(ag_idx, j, k);
                            end
                        end
                    elseif num_dims == 2
                        for ag_idx = members
                            if ag_idx <= agentresources_size(1) && j <= agentresources_size(2)
                                total_allocated = total_allocated + ...
                                    Value_data(1).agentresources(ag_idx, j);
                            end
                        end
                    end
                end
            end
        end
        
        if total_demand > 0
            comparison_stats.(alg_name).resource_match_ratio = total_allocated / total_demand;
        else
            comparison_stats.(alg_name).resource_match_ratio = 0;
        end
    end
end