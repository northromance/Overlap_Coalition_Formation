function probs = Qi2023_Select_probs(Value_data, agents, tasks, Value_Params, resource_gap, Gamma)
% QI2023_SELECT_PROBS 基于偏好重力的概率计算（Qi2023算法专用）
%
% 功能描述:
%   使用论文中的偏好重力公式计算任务选择概率
%   P_n^(z)(k) = [p_{n,1}^(z)(k), ..., p_{n,m}^(z)(k), ..., p_{n,M}^(z)(k)]
%
%   p_{m,n}^(z)(k) = exp[f_{m,n}^(z)(k) * Gamma(k)] / sum_m exp[f_{m,n}^(z)(k) * Gamma(k)]
%
%   其中 f_{m,n}^(z)(k) 是偏好重力函数：
%   - 对于基本资源(z_b): f = (beta_m)^2 * L * c_m^(z_b)(k) * delta_n^(z_b) / d_{m,n}
%   - 对于消耗资源(z_c): f = (beta_m)^2 * R * c_m^(z_c)(k) * mu_n^(z_c) / d_{m,n}
%
% 输入:
%   Value_data   - 当前智能体的状态结构体
%   agents       - 智能体列表
%   tasks        - 任务列表
%   Value_Params - 全局参数
%   resource_gap - (MxK 矩阵) 每个任务在每种资源上的剩余需求量
%   Gamma        - Boltzmann系数（控制探索与开发的权衡）
%
% 输出:
%   probs        - (KxM 矩阵) 概率分布矩阵
%                  probs(z, m) 表示资源类型z选择任务m的概率

    agentID = Value_data.agentID;
    K = Value_Params.K;
    M = Value_Params.M;

    % 初始化概率矩阵
    probs = zeros(K, M);

    % 小常数，防止除零
    eps_val = 1e-9;

    %% 计算偏好重力 f_{m,n}^(z)(k)
    for z = 1:K  % 遍历每种资源类型

        f_values = zeros(1, M);  % 存储每个任务的偏好重力值

        for m = 1:M  % 遍历每个任务

            % 1. 任务优先级 beta_m（归一化到[0,1]）
            beta_m = tasks(m).priority;
            max_priority = max([tasks.priority]);
            if max_priority > 0
                beta_m = beta_m / max_priority;
            end

            % 2. 资源缺口 c_m^(z)(k)
            % L: 对于基本资源，使用剩余需求
            % R: 对于消耗资源，使用剩余需求
            c_m_z = max(resource_gap(m, z), 0);

            % 归一化资源缺口
            max_gap = max(resource_gap(:, z));
            if max_gap > eps_val
                c_m_z = c_m_z / max_gap;
            end

            % 3. 智能体资源容量 delta_n^(z_b) 或 mu_n^(z_c)
            % 使用智能体拥有的资源量
            agent_capacity = Value_data.resources(z);
            max_capacity = max(Value_data.resources); % 用智能体拥有的某种最大资源归一化
            if max_capacity > eps_val
                agent_capacity = agent_capacity / max_capacity;
            end

            % 4. 距离 d_{m,n}
            d_mn = sqrt((tasks(m).x - agents(agentID).x)^2 + ...
                        (tasks(m).y - agents(agentID).y)^2);
            d_mn = max(d_mn, eps_val);  % 防止除零

            % 归一化距离
            max_dist = 0;
            for j = 1:M
                dist_j = sqrt((tasks(j).x - agents(agentID).x)^2 + ...
                             (tasks(j).y - agents(agentID).y)^2);
                max_dist = max(max_dist, dist_j);
            end
            if max_dist > eps_val
                d_mn = d_mn / max_dist;
            end

            % 5. 计算偏好重力 f_{m,n}^(z)(k)
            % 公式: f = (beta_m)^2 * c_m^(z) * agent_capacity / d_{m,n}f
            f_mn_z = (beta_m^2) * c_m_z * agent_capacity / d_mn;

            f_values(m) = f_mn_z;
        end

        %% 使用Boltzmann分布计算概率
        % p_{m,n}^(z)(k) = exp[f_{m,n}^(z)(k) * Gamma(k)] / sum_m exp[f_{m,n}^(z)(k) * Gamma(k)]

        % 计算指数项
        exp_values = exp(f_values * Gamma);

        % 归一化得到概率
        sum_exp = sum(exp_values);
        probs(z, :) = exp_values / sum_exp;

    end

end


% function probs = Qi2023_Select_probs(Value_data, agents, tasks, Value_Params, resource_gap, Gamma)
% % QI2023_SELECT_PROBS (修复版：增加掩码处理，杜绝无效任务分流，优化计算速度)
% %
% % 核心修复点:
% %   1. 【硬约束】: 如果智能体没有资源，或者任务不需要资源，概率严格为 0。
% %   2. 【数值稳定】: 使用 Shifted Softmax 防止 Gamma 很大时 exp 溢出。
% %   3. 【性能优化】: 将距离计算和最大值归一化移出循环，避免重复计算。
% 
%     agentID = Value_data.agentID;
%     K = Value_Params.K;
%     M = Value_Params.M;
% 
%     probs = zeros(K, M);
%     eps_val = 1e-9;
% 
%     %% --- Step 1: 预计算公共特征 (移出循环以大幅提升速度) ---
% 
%     % 1. 距离向量与归一化
%     % 计算当前智能体到所有任务的距离向量 (1xM)
%     dists = arrayfun(@(t) sqrt((t.x - agents(agentID).x)^2 + (t.y - agents(agentID).y)^2), tasks);
%     max_dist = max(dists);
%     if max_dist <= eps_val, max_dist = 1; end
%     norm_dists = dists / max_dist;
%     % 避免距离极小导致除零
%     norm_dists(norm_dists < eps_val) = eps_val;
% 
%     % 2. 优先级向量 (1xM)
%     prio_vec = [tasks.priority];
%     max_prio = max(prio_vec);
%     if max_prio <= eps_val, max_prio = 1; end
%     norm_prio = prio_vec / max_prio;
% 
%     % 3. 智能体自身资源最大值 (用于归一化)
%     max_agent_res = max(Value_data.resources);
%     if max_agent_res <= eps_val, max_agent_res = 1; end
% 
%     %% --- Step 2: 逐资源计算概率 ---
%     for z = 1:K
%         % 【修复 A】: 供给端硬约束
%         % 如果智能体根本没有第 z 种资源，直接整行概率置 0，continue
%         agent_res_val = Value_data.resources(z);
%         if agent_res_val <= eps_val
%             probs(z, :) = 0; 
%             continue; 
%         end
% 
%         % 归一化当前资源拥有量
%         norm_agent_cap = agent_res_val / max_agent_res;
% 
%         % 获取当前资源对所有任务的需求缺口 (1xM 向量)
%         gaps_z = resource_gap(:, z)'; 
%         gaps_z = max(gaps_z, 0); % 确保非负
% 
%         % 归一化缺口
%         max_gap_z = max(gaps_z);
%         if max_gap_z <= eps_val
%             % 【修复 B】: 需求端硬约束 (前期拦截)
%             % 如果没有任何任务需要此资源，概率全为 0
%             probs(z, :) = 0;
%             continue;
%         end
%         norm_gaps = gaps_z / max_gap_z;
% 
%         % --- 计算偏好重力 f (向量化计算) ---
%         % 公式: f = (beta^2 * gap * capacity) / dist
% 
%         f_values = (norm_prio.^2 .* norm_gaps * norm_agent_cap) ./ norm_dists;
% 
%         % 【修复 C】: 掩码过滤 (Masking) - 解决 Softmax e^0=1 问题
%         % 只有 f > 0 的任务才值得被分配 (即: 有需求 且 有能力)
%         valid_mask = f_values > eps_val;
% 
%         if ~any(valid_mask)
%             probs(z, :) = 0;
%             continue;
%         end
% 
%         % --- Boltzmann 分布 (仅针对有效任务) ---
% 
%         valid_f = f_values(valid_mask);
% 
%         % 【修复 D】: 数值稳定性处理 (Shifted Softmax)
%         % 防止 Gamma * f 很大导致 exp 溢出为 Inf
%         weighted_f = valid_f * Gamma;
%         shifted_f = weighted_f - max(weighted_f); % 减去最大值，保证指数部分 <= 0
% 
%         exp_values = exp(shifted_f);
%         sum_exp = sum(exp_values);
% 
%         % 填充概率 (只填充 valid_mask 为 true 的位置)
%         current_probs = zeros(1, M);
%         if sum_exp > eps_val
%             current_probs(valid_mask) = exp_values / sum_exp;
%         end
% 
%         probs(z, :) = current_probs;
%     end
% end