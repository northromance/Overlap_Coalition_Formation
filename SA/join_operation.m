function [Value_data, incremental_join] = join_operation(Value_data, agents, tasks, Value_Params, probs)
% join_operation - 智能体尝试加入任务（资源分配）
%
% 输入:
%   Value_data   - 当前智能体数据结构
%   agents       - 所有智能体结构数组
%   tasks        - 所有任务结构数组
%   Value_Params - 全局参数（N, M, K, Temperature等）
%   probs        - K×M矩阵，probs(r,j)=资源类型r选择任务j的概率
%
% 输出:
%   Value_data        - 更新后的智能体数据
%   incremental_join  - 是否成功加入（1=成功, 0=失败）

incremental_join = 0;
agentID = Value_data.agentID;
tol = 1e-9;

% agentID -> agents 索引
agentIdx = agentID;

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
    % 输出：SC_P/SC_Q=操作前/后联盟结构；R_agent_P/R_agent_Q=该智能体操作前/后资源分配(M×K)
    % 计算的是加入操作之后整体联盟结构变化和智能体资源分配变化
    % R_agent_P 为操作前个体资源分配矩阵，R_agent_Q 为操作后个体资源分配矩阵
    
    [SC_P, SC_Q, R_agent_P, R_agent_Q] = join_changes(Value_data, agents, Value_Params, target, agentID, r);
    
    %% 2) 可行性检测：不可行直接跳过，继续下一种资源类型
    [feasible, info] = validate_feasibility(Value_data, agents, tasks, Value_Params, agentID, SC_P, SC_Q, R_agent_P, R_agent_Q, target, r);
    if ~feasible
        if verbose
            % 解释不可行原因
            reason_str = info.reason;
            switch reason_str
                case 'agent_not_found'
                    reason_detail = '智能体不存在';
                case 'bad_R_agent_Q_size'
                    reason_detail = '资源矩阵维度错误';
                case 'negative_allocation'
                    reason_detail = '资源分配为负';
                case 'capacity_exceeded'
                    reason_detail = '超出资源容量';
                case 'energy_insufficient'
                    reason_detail = '能量不足';
                otherwise
                    reason_detail = reason_str;
            end
            fprintf('智能体%d: 资源类型%d加入任务%d不可行（原因：%s）\n', agentID, r, target, reason_detail);
        end
        continue;
    end
    
    
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
        % 接受：更新资源联盟结构 SC，并同步更新 coalitionstru（矩阵）
        Value_data.SC = SC_Q;
        Value_data.resources_matrix = R_agent_Q;
        
        % 更新 coalitionstru: (M+1)×N 联盟成员矩阵
        % 作用：记录每个智能体参与了哪些任务
        % 结构：第1-M行对应真实任务，第M+1行对应void任务（未分配任何任务）
        %       coalitionstru(m, i) = agentID 表示智能体i参与任务m
        
        % 1) 找出该智能体有资源分配的所有任务
        %    any(..., 2) 按行检查：只要该任务有任何资源类型分配量>0，就算参与
        assignedTasksPost = find(any(Value_data.resources_matrix > tol, 2));
        
        % 2) 复制当前联盟结构，准备更新
        coalition_after = Value_data.coalitionstru;
        
        % 3) 清空该智能体在所有真实任务上的旧标记
        coalition_after(1:Value_Params.M, agentIdx) = 0;
        
        % 4) 在参与的任务行标记智能体ID
        for mIdx = assignedTasksPost'
            coalition_after(mIdx, agentIdx) = agents(agentIdx).id;
        end
        
        % 5) 处理void任务行（第M+1行）
        if isempty(assignedTasksPost)
            % 如果该智能体未参与任何任务，标记到void行
            coalition_after(Value_Params.M + 1, agentIdx) = agents(agentIdx).id;
        else
            % 如果参与了至少1个任务，清除void标记
            coalition_after(Value_Params.M + 1, agentIdx) = 0;
        end
        
        % 6) 写回更新后的联盟结构
        Value_data.coalitionstru = coalition_after;
        
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

