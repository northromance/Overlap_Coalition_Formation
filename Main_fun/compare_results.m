function comparison_stats = compare_results(results, agents, tasks, Value_Params)
% COMPARE_RESULTS 对比分析多个算法的结果
%
% 输入:
%   results - 包含所有算法结果的结构体
%   agents - 智能体数组
%   tasks - 任务数组
%   Value_Params - 算法参数
%
% 输出:
%   comparison_stats - 包含各算法性能指标的结构体

    % 获取算法数量
    alg_names = fieldnames(results);
    num_algorithms = length(alg_names);
    
    comparison_stats = struct();
    
    for i = 1:num_algorithms
        alg_name = alg_names{i};
        alg_result = results.(alg_name);
        
        % 基本信息
        comparison_stats.(alg_name).name = alg_result.name;
        comparison_stats.(alg_name).computation_time = alg_result.computation_time;
        
        % 检查是否有错误
        if isfield(alg_result, 'error')
            comparison_stats.(alg_name).has_error = true;
            comparison_stats.(alg_name).error_message = alg_result.error.message;
            continue;
        end
        
        comparison_stats.(alg_name).has_error = false;
        
        % 提取Value_data和history_data
        Value_data = alg_result.Value_data;
        history_data = [];
        if isfield(alg_result, 'history_data')
            history_data = alg_result.history_data;
        end
        
        %% 1. 总效用
        total_utility = 0;
        
        if isfield(Value_data, 'totalvalue')
            % 直接有totalvalue字段（如Huo2025）
            total_utility = Value_data(1).totalvalue;
        elseif ~isempty(history_data) && isfield(history_data, 'rounds')
            % 从history_data获取最后一轮的task_utilities
            num_rounds = length(history_data.rounds);
            if num_rounds > 0 && isfield(history_data.rounds(num_rounds), 'task_utilities')
                total_utility = sum(history_data.rounds(num_rounds).task_utilities);
            end
        end
        
        % 如果上面没获取到，尝试从SC计算
        if total_utility == 0 && isfield(Value_data, 'SC')
            % SA算法：从SC计算总效用
            try
                SC = Value_data(1).SC;
                M_tasks = min(length(SC), length(tasks));
                for m = 1:M_tasks
                    if ~isempty(SC{m})
                        participants = find(any(SC{m} > 0, 2))';
                        if ~isempty(participants)
                            for ag_idx = participants
                                % 计算智能体对任务的效用贡献
                                allocated = SC{m}(ag_idx, :);
                                actual_demand = tasks(m).resource_demand;
                                task_value = tasks(m).value;
                                
                                % 计算资源贡献比例
                                contrib_ratio = 0;
                                valid_resources = 0;
                                for k = 1:length(actual_demand)
                                    if actual_demand(k) > 1e-9
                                        valid_resources = valid_resources + 1;
                                        contrib_ratio = contrib_ratio + min(allocated(k) / actual_demand(k), 1.0);
                                    end
                                end
                                if valid_resources > 0
                                    contrib_ratio = contrib_ratio / valid_resources;
                                    total_utility = total_utility + task_value * contrib_ratio;
                                end
                            end
                        end
                    end
                end
            catch ME
                fprintf('警告: 计算总效用时出错 - %s\n', ME.message);
            end
        end
        
        comparison_stats.(alg_name).total_utility = total_utility;
        
        %% 2. 联盟结构分析
        coal = Value_data(1).coalitionstru;
        M = size(coal, 1);
        N = size(coal, 2);
        
        % 裁剪至任务数
        if M > length(tasks)
            coal = coal(1:length(tasks), :);
            M = length(tasks);
        end
        
        % 统计联盟数量（有智能体参与的任务）
        num_coalitions = 0;
        coalition_sizes = [];
        for j = 1:M
            members = find(coal(j, :) ~= 0);
            if ~isempty(members)
                num_coalitions = num_coalitions + 1;
                coalition_sizes(end+1) = length(members);
            end
        end
        comparison_stats.(alg_name).num_coalitions = num_coalitions;
        
        % 联盟大小统计
        if ~isempty(coalition_sizes)
            comparison_stats.(alg_name).avg_coalition_size = mean(coalition_sizes);
            comparison_stats.(alg_name).max_coalition_size = max(coalition_sizes);
            comparison_stats.(alg_name).min_coalition_size = min(coalition_sizes);
        else
            comparison_stats.(alg_name).avg_coalition_size = 0;
            comparison_stats.(alg_name).max_coalition_size = 0;
            comparison_stats.(alg_name).min_coalition_size = 0;
        end
        
        %% 3. 任务完成度和资源匹配度分析
        comparison_stats.(alg_name).completed_tasks = num_coalitions;
        comparison_stats.(alg_name).task_completion_rate = num_coalitions / length(tasks) * 100;
        
        % 计算每个任务的资源完成度 D_C
        task_completion_degrees = zeros(M, 1);
        
        % 判断是否有SC（资源联盟结构）
        if isfield(Value_data, 'SC') && ~isempty(Value_data(1).SC)
            % SA算法：从SC计算每个任务的完成度
            SC = Value_data(1).SC;
            for j = 1:min(M, length(SC))
                if ~isempty(SC{j})
                    task_demand = tasks(j).resource_demand;
                    % 使用通用函数计算任务完成度
                    task_completion_degrees(j) = OCFUtils.calc_task_completion_degree(SC{j}, task_demand, Value_Params.K);
                end
            end
        elseif isfield(Value_data, 'agentresources') && ~isempty(Value_data(1).agentresources)
            % 其他算法：从agentresources计算
            agentresources = Value_data(1).agentresources;
            agentresources_size = size(agentresources);
            num_dims = ndims(agentresources);
            
            for j = 1:M
                members = find(coal(j, :) ~= 0);
                if ~isempty(members)
                    task_demand = tasks(j).resource_demand;
                    % 收集分配的资源
                    allocated = zeros(1, Value_Params.K);
                    for k = 1:Value_Params.K
                        if num_dims >= 3
                            for ag_idx = members
                                if ag_idx <= agentresources_size(1) && j <= agentresources_size(2) && k <= agentresources_size(3)
                                    allocated(k) = allocated(k) + agentresources(ag_idx, j, k);
                                end
                            end
                        elseif num_dims == 2
                            % 2维情况：假设总资源已分配
                            if j <= agentresources_size(2)
                                allocated(k) = task_demand(k);  % 近似值
                            end
                        end
                    end
                    % 使用通用函数计算任务完成度
                    task_completion_degrees(j) = OCFUtils.calc_task_completion_degree(allocated, task_demand, Value_Params.K);
                end
            end
        end
        
        % 统计任务完成情况（使用求和归一化方式）
        comparison_stats.(alg_name).task_completion_degrees = task_completion_degrees;  % 各任务完成度明细
        comparison_stats.(alg_name).total_completion_score = sum(task_completion_degrees);  % 总完成分数（等效完成任务数）
        comparison_stats.(alg_name).normalized_completion_rate = (sum(task_completion_degrees) / M) * 100;  % 归一化完成率
        comparison_stats.(alg_name).avg_task_completion = mean(task_completion_degrees(task_completion_degrees > 0));  % 有联盟任务的平均完成度
        comparison_stats.(alg_name).fully_completed_tasks = sum(task_completion_degrees >= 0.999);  % 完全完成的任务数
        comparison_stats.(alg_name).partially_completed_tasks = sum(task_completion_degrees > 0 & task_completion_degrees < 0.999);  % 部分完成的任务数
        
        % 处理NaN情况
        if isnan(comparison_stats.(alg_name).avg_task_completion)
            comparison_stats.(alg_name).avg_task_completion = 0;
        end
        
        %% 4. 资源利用率
        total_resources_available = 0;
        total_resources_allocated = 0;
        
        for ag_idx = 1:length(agents)
            total_resources_available = total_resources_available + sum(agents(ag_idx).resources);
        end
        
        % 优先使用SC结构计算资源分配
        if isfield(Value_data, 'SC') && ~isempty(Value_data(1).SC)
            SC = Value_data(1).SC;
            for m = 1:min(length(SC), M)
                if ~isempty(SC{m})
                    total_resources_allocated = total_resources_allocated + sum(SC{m}(:));
                end
            end
        elseif isfield(Value_data, 'agentresources') && ~isempty(Value_data(1).agentresources)
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
                        % 2维情况
                        total_resources_allocated = total_resources_allocated + ...
                            Value_data(1).agentresources(ag_idx, task_idx);
                    end
                end
            end
        end
        
        if total_resources_available > 0
            comparison_stats.(alg_name).resource_utilization = ...
                total_resources_allocated / total_resources_available * 100;
        else
            comparison_stats.(alg_name).resource_utilization = 0;
        end
        
        %% 5. 智能体参与度
        agent_participation = zeros(1, N);
        for ag_idx = 1:N
            agent_participation(ag_idx) = sum(coal(:, ag_idx) ~= 0);
        end
        
        comparison_stats.(alg_name).avg_agent_participation = mean(agent_participation);
        comparison_stats.(alg_name).max_agent_participation = max(agent_participation);
        comparison_stats.(alg_name).agent_participation_std = std(agent_participation);
        
        %% 6. 能量消耗统计（如果有相关数据）
        if isfield(Value_data, 'energy_cost')
            comparison_stats.(alg_name).total_energy_cost = sum(Value_data(1).energy_cost);
            comparison_stats.(alg_name).avg_energy_per_task = ...
                comparison_stats.(alg_name).total_energy_cost / num_coalitions;
        else
            comparison_stats.(alg_name).total_energy_cost = NaN;
            comparison_stats.(alg_name).avg_energy_per_task = NaN;
        end
        
        %% 7. 任务价值统计
        total_value_achieved = 0;
        total_value_possible = 0;
        
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
        
        %% 8. 效用效率（效用/计算时间）
        if comparison_stats.(alg_name).computation_time > 0
            comparison_stats.(alg_name).utility_efficiency = ...
                comparison_stats.(alg_name).total_utility / ...
                comparison_stats.(alg_name).computation_time;
        else
            comparison_stats.(alg_name).utility_efficiency = Inf;
        end
        
        %% 9. 资源匹配度
        total_demand = 0;
        total_allocated = 0;
        
        if isfield(Value_data, 'agentresources') && ~isempty(Value_data(1).agentresources)
            agentresources_size = size(Value_data(1).agentresources);
            num_dims = ndims(Value_data(1).agentresources);
        else
            agentresources_size = [0, 0, 0];
            num_dims = 0;
        end
        
        for j = 1:M
            members = find(coal(j, :) ~= 0);
            if ~isempty(members)
                task_demand = tasks(j).resource_demand;
                for k = 1:Value_Params.K
                    total_demand = total_demand + task_demand(k);
                    if num_dims >= 3
                        for ag_idx = members
                            % 检查索引是否在范围内
                            if ag_idx <= agentresources_size(1) && j <= agentresources_size(2) && k <= agentresources_size(3)
                                total_allocated = total_allocated + ...
                                    Value_data(1).agentresources(ag_idx, j, k);
                            end
                        end
                    elseif num_dims == 2
                        % 2维情况：假设是 (agent, task) 格式
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
