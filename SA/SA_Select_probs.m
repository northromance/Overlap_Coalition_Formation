function probs = SA_Select_probs(Value_data, agents, tasks, Value_Params, resource_gap, current_T)
% SA_SELECT_PROBS 基于模拟退火温度的动态概率选择 (Boltzmann分布)
%
% 功能描述:
%   结合了启发式评价(距离、优先级、供需)与模拟退火的温度(T)。
%   利用 Softmax (Boltzmann) 形式将评分转化为概率。
%
%   公式逻辑: P(j) = exp( Score(j) / T ) / sum( exp( Score(i) / T ) )
%
%   - 当 T 很高 (高温) 时: exp(Score/T) 趋近于 exp(0) = 1。
%     结果: 概率趋向于均匀分布 (Uniform Distribution) -> 强探索能力。
%
%   - 当 T 很低 (低温) 时: 差异被指数级放大。
%     结果: 高分任务的概率趋近于 1，低分趋近于 0 -> 强开发能力 (Greedy)。
%
% 输入:
%   ... (同前) ...
%   current_T    - 当前模拟退火的温度 (Scalar)
%
% 输出:
%   probs        - (KxM 矩阵) 概率分布矩阵

    agentID = Value_data.agentID;
    K = Value_Params.K;
    M = Value_Params.M;
    
    % 初始化
    probs = zeros(K, M);
    eps_val = 1e-9; % 防止除零
    
    %% ==================== 1. 准备归一化因子 ====================
    % 这一步保持不变，确保不同量纲的物理量能公平竞争
    
    max_priority = max([tasks.priority]);
    if max_priority <= eps_val, max_priority = 1; end
    
    max_remaining_demand = max(resource_gap(:));
    if max_remaining_demand <= eps_val, max_remaining_demand = 1; end
    
    max_agent_resource = max(Value_data.resources);
    if max_agent_resource <= eps_val, max_agent_resource = 1; end
    
    % 计算当前智能体到所有任务的距离
    dists = arrayfun(@(task) sqrt((task.x - agents(agentID).x)^2 + (task.y - agents(agentID).y)^2), tasks);
    max_distance = max(dists);
    if max_distance <= eps_val, max_distance = 1; end
    
    %% ==================== 2. 计算得分并结合温度 ====================
    
    % 为了防止数值溢出或温度过高导致全部变为1，这里可以设置一个调节系数
    % 如果你的 Score 是 0~1 之间，而 T 是 100，Score/T 会非常小。
    % 建议引入一个 Scaling Factor (比如 10) 让初始阶段也有微弱的倾向性，
    % 或者完全依赖 T 的自然衰减。此处保持纯净物理意义，暂不加额外系数。
    
    % 确保温度不为0 (防止除以0)
    effective_T = max(current_T, 1e-2); 
    
    for r = 1:K
        scores = zeros(1, M); % 暂存当前资源下，所有任务的“启发式得分”
        
        for j = 1:M
            % --- A. 提取特征 (与 Select_probs 逻辑一致) ---
            
            % 1. 紧缺程度
            rem_demand = 0;
            if ~isempty(resource_gap)
                rem_demand = max(resource_gap(j, r), 0);
            end
            feat_demand = rem_demand / max_remaining_demand;
            
            % 2. 供给能力
            feat_supply = Value_data.resources(r) / max_agent_resource;
            
            % 3. 距离成本
            task_dist = dists(j);
            if task_dist <= eps_val, task_dist = eps_val; end
            feat_dist = task_dist / max_distance;
            
            % 4. 优先级
            feat_prio = tasks(j).priority / max_priority;
            
            % --- B. 综合打分 (Score Calculation) ---
            % 这是一个“好坏”的度量，值越大越好。范围通常在 [0, 1] 左右。
            % Score ~ (优先级^2 * 缺口 * 供给) / 距离
            
            score_val = (feat_prio^2 * feat_demand * feat_supply) / (feat_dist + eps_val);
            
            scores(j) = score_val;
        end
        
        % --- C. Boltzmann 变换 (关键修改) ---
        % 将 Score 转化为与温度相关的概率
        % 公式: P ~ exp( Score / T )
        
        % [数值稳定性处理]
        % 如果 Score/T 很大，exp 会溢出。
        % 技巧: exp(x_i) / sum(exp(x_j)) == exp(x_i - max(x)) / sum(exp(x_j - max(x)))
        % 这一步不会改变概率结果，但能防止 NaN。
        
        raw_exponent = scores / effective_T;
        shifted_exponent = raw_exponent - max(raw_exponent); % 减去最大值
        
        exp_values = exp(shifted_exponent);
        sum_exp = sum(exp_values);
        
        if sum_exp > eps_val
            probs(r, :) = exp_values / sum_exp;
        else
            % 如果所有得分都极低（例如没有资源匹配），均匀分布或全0
            if sum(scores) == 0
                 probs(r, :) = 0; % 确实没有可行任务
            else
                 probs(r, :) = ones(1, M) / M; % 兜底
            end
        end
    end
end