function [Value_data, incremental_join] = join_operation(Value_data, agents, tasks, Value_Params, probs)


incremental_join = 0;
agentID = Value_data.agentID;

% resources_matrix：若不存在/维度不对则初始化（不要每次都清零）
if ~isfield(Value_data, 'resources_matrix') || isempty(Value_data.resources_matrix) || ...
        any(size(Value_data.resources_matrix) ~= [Value_Params.M, Value_Params.K])
    Value_data.resources_matrix = zeros(Value_Params.M, Value_Params.K);
end

% verbose：打印调试信息（默认开，可在 Value_Params.verbose 关闭）
verbose = true;
if isfield(Value_Params, 'verbose')
    verbose = logical(Value_Params.verbose);
end

% 主流程：对每种资源类型 r 抽一个候选任务 -> 可行性 -> 计算ΔU -> 接受则退出
for r = 1:Value_Params.K
    
    % r 类型资源下，对各任务的选择概率
    row = probs(r, :);
    row_sum = sum(row);
    if row_sum <= 0
        continue;
    end
    
    % cumulative sampling（不依赖 randsample）
    edges = cumsum(row);
    x = rand() * edges(end);
    
    % 抽样得到候选任务 target
    target = find(edges >= x, 1, 'first');
    if isempty(target)
        continue;
    end
    
    % 只允许加入真实任务 1..M
    if target < 1 || target > Value_Params.M
        error('超出边界');
    end
    
    
    %% 1) 生成操作前/后的联盟结构与资源分配

    [SC_P, SC_Q, R_agent_P, R_agent_Q, ~, ~] = ...
        compute_coalition_and_resource_changes(Value_data, agents, Value_Params, target, agentID, r);
    
    %% 2) 可行性检测：不可行直接跳过，继续下一种资源类型
    [feasible, feasInfo] = validate_join_feasibility(Value_data, agents, tasks, Value_Params, agentID, SC_P, SC_Q, R_agent_P, R_agent_Q, target, r);
    if ~feasible
        if verbose
            fprintf('智能体%d: 加入任务%d(资源类型%d)不可行，原因=%s\n', agentID, target, r, feasInfo.reason);
            if isfield(feasInfo, 'totalAllocatedByType')
                fprintf('  totalAllocatedByType=%s, capacityByType=%s\n', mat2str(feasInfo.totalAllocatedByType'), mat2str(feasInfo.capacityByType'));
            end
            if strcmp(feasInfo.reason, 'energy_insufficient')
                if isfield(feasInfo, 'requiredEnergy') && isfield(feasInfo, 'energyCapacity')
                    fprintf('  requiredEnergy=%.4f, energyCapacity=%.4f, model=%s\n', ...
                        feasInfo.requiredEnergy, feasInfo.energyCapacity, feasInfo.energyModel);
                end
                if isfield(feasInfo, 't_wait_total') || isfield(feasInfo, 'T_exec_total')
                    tWait = NaN;
                    tExec = NaN;
                    if isfield(feasInfo, 't_wait_total'), tWait = feasInfo.t_wait_total; end
                    if isfield(feasInfo, 'T_exec_total'), tExec = feasInfo.T_exec_total; end
                    fprintf('  t_wait_total=%.4f, T_exec_total=%.4f\n', tWait, tExec);
                end
                if isfield(feasInfo, 'routeDistance')
                    fprintf('  routeDistance=%.4f, taskSequence=%s\n', feasInfo.routeDistance, mat2str(feasInfo.taskSequenceByPriority));
                end
            end
        end
        continue;
    end

    % 3) 写入“操作后资源矩阵”，用于效用计算
    Value_data.resources_matrix = R_agent_Q;
    
    %% 4) 计算ΔU：overlap_coalition_utility 返回 LHS(SC_Q,SC_P)-RHS(SC_Q,SC_P)
    delta_U = overlap_coalition_utility(tasks, agents, SC_P, SC_Q, agentID, Value_Params, Value_data);
    
    
    %% 5) 决策：ΔU>0 必接收；否则按 SA 概率接受差解
    accept_join = false;
    
    if delta_U > 0
        % 如果效用差大于0，直接加入联盟
        accept_join = true;
        fprintf('智能体%d: 加入任务%d(资源类型%d), ΔU=%.4f > 0\n', agentID, target, r, delta_U);
    else
        % 如果效用差 <= 0，使用模拟退火概率判断是否加入联盟（可能接受差解）
        T = Value_Params.Temperature;  % 从参数中获取温度

        P_join = exp(delta_U / T);  % 接受概率
        
        % 根据随机数判断是否加入联盟
        if rand() < P_join
            accept_join = true;
            fprintf('智能体%d: 加入任务%d(资源类型%d), ΔU=%.4f, SA接受概率=%.4f\n', ...
                agentID, target, r, delta_U, P_join);
        else
            fprintf('智能体%d: 拒绝加入任务%d(资源类型%d), ΔU=%.4f, SA拒绝\n', ...
                agentID, target, r, delta_U);
        end
    end
    
    %% ========== 执行决策 ==========
    if accept_join
        % 接受：更新联盟结构并结束本次 join_operation
        Value_data.coalitionstru = SC_Q;
        incremental_join = 1;
        
        % 打印关键变化
        fprintf('  资源分配变化: 任务%d获得资源类型%d的数量%.2f\n', ...
            target, r, R_agent_Q(target, r));

        % 一旦找到可接受的加入操作就跳出
        break;
    else
        % 拒绝：回滚资源分配，继续下一种资源类型
        Value_data.resources_matrix = R_agent_P;
    end
    
    
end

