function [Value_data, history_data] = Qi2023_main(agents, tasks, AddPara, Value_Params)
% =========================================================================
%  Qi2023算法：PGG-TS (Preference Gravity-Guided Tabu Search)
%  基于偏好重力引导的禁忌搜索分布式重叠联盟形成算法
% =========================================================================
%
%  算法来源：
%  ------------------------------------------------------------------------
%  Qi et al., "A Task-Driven Sequential Overlapping Coalition Formation 
%  Game for Resource Allocation in Heterogeneous UAV Networks"
%  IEEE Transactions on Mobile Computing, 2023
%
%  算法主要功能 (Algorithm 2: PGG-TS)：
%  ------------------------------------------------------------------------
%  1. 计算每个UAV对每个任务的偏好重力 F_n^(z)
%  2. 将偏好重力转换为选择概率 P_n^(z)（Softmax with Boltzmann）
%  3. UAV根据概率选择任务进行资源分配
%  4. 使用禁忌搜索避免循环
%  5. 只接受改进解（贪婪策略），迭代直到联盟结构稳定或达到最大迭代次数
%  注：Boltzmann系数仅用于调节选择概率的探索/利用平衡，不用于接受劣解
%
%  输入参数：
%  ------------------------------------------------------------------------
%  agents, tasks, AddPara, Value_Params（标准接口）
%
%  输出参数：
%  ------------------------------------------------------------------------
%  Value_data：结果结构体
%  history_data：算法运行历史
%
% =========================================================================

    %% ==================== 0. 随机数种子设置（确保可复现性）====================
    % 修复：在算法开始时设置随机数种子，确保结果可复现
    if isfield(Value_Params, 'seed')
        rng(Value_Params.seed);
    end

    %% 参数提取
    N = Value_Params.N;  % UAV数量
    M = Value_Params.M;  % 任务数量
    K = Value_Params.K;  % 资源类型数量
    
    % PGG-TS算法特定参数
    if isfield(Value_Params, 'num_rounds')
        Kmax = Value_Params.num_rounds;  % 最大迭代次数
    else
        Kmax = 50;
    end
    Ltabu = 5;           % 禁忌表长度
    Klen = 10;           % 稳定迭代阈值（连续Klen次无改进则停止）
    G0 = 1.0;            % 初始Boltzmann系数
    alpha_G = 0.95;      % Boltzmann系数衰减率（仅用于选择概率）
    
    % Qi2023论文效用函数参数（从Value_Params读取，若无则使用默认值）
    if isfield(Value_Params, 'Qi_beta_m')
        beta_m = Value_Params.Qi_beta_m;
    else
        beta_m = 1.0;        % Sigmoid函数陡峭度参数
    end
    if isfield(Value_Params, 'Qi_C_req')
        C_req = Value_Params.Qi_C_req;
    else
        C_req = 0.5;         % 需求阈值
    end
    if isfield(Value_Params, 'Qi_omega')
        omega = Value_Params.Qi_omega;
    else
        omega = 0.1;         % Sigmoid函数偏移参数
    end
    if isfield(Value_Params, 'Qi_omega_1')
        omega_1 = Value_Params.Qi_omega_1;
    else
        omega_1 = 1.0;       % 资源完成度权重
    end
    if isfield(Value_Params, 'Qi_omega_2')
        omega_2 = Value_Params.Qi_omega_2;
    else
        omega_2 = 0.01;      % 距离成本权重
    end
    if isfield(Value_Params, 'Qi_omega_3')
        omega_3 = Value_Params.Qi_omega_3;
    else
        omega_3 = 0.001;     % 能量损耗权重
    end
    
    %% 初始化
    % 联盟结构：SC(m, n, k) = 1 表示UAV n的资源类型k分配给任务m
    SC = zeros(M, N, K);  % 当前联盟结构
    
    % 任务剩余资源需求 L_m^(less)
    L_less = zeros(M, K);
    for j = 1:M
        L_less(j, :) = tasks(j).resource_demand(:)';
    end
    
    % 任务收益 B_m
    B = zeros(M, 1);
    for j = 1:M
        B(j) = tasks(j).value;
    end
    
    % 距离矩阵
    dist_matrix = zeros(N, M);
    for i = 1:N
        for j = 1:M
            dist_matrix(i, j) = sqrt((agents(i).x - tasks(j).x)^2 + ...
                                     (agents(i).y - tasks(j).y)^2);
        end
    end
    
    % UAV资源
    agent_resources = zeros(N, K);
    for i = 1:N
        res = agents(i).resources(:)';
        if length(res) >= K
            agent_resources(i, :) = res(1:K);
        else
            agent_resources(i, 1:length(res)) = res;
        end
    end
    
    % 禁忌表（存储最近的联盟结构哈希值）
    TabuSC = [];
    
    % Boltzmann系数
    G = G0;
    
    % 迭代计数
    k = 1;
    kstable = 0;
    
    % 历史记录
    utility_history = zeros(Kmax, 1);
    
    %% 计算初始偏好重力和选择概率，形成初始联盟
    [F, P] = calc_preference_gravity(agent_resources, L_less, B, dist_matrix, G, N, M, K);
    
    % 根据初始概率分配资源
    SC = allocate_by_probability(P, agent_resources, L_less, N, M, K);
    
    % 更新剩余需求
    L_less = update_remaining_demand(SC, agent_resources, tasks, M, K);
    
    %% 主循环
    while k <= Kmax && kstable <= Klen
        
        % 对每个UAV进行操作
        for n = 1:N
            % 随机选择一种资源类型进行重分配
            z = randi(K);
            
            % 如果该UAV有这种资源
            if agent_resources(n, z) > 0
                % 找到当前该资源分配给的任务
                current_task = find(SC(:, n, z) > 0, 1);
                
                % 离开当前联盟（如果有）
                if ~isempty(current_task)
                    SC(current_task, n, z) = 0;
                    L_less(current_task, z) = L_less(current_task, z) + agent_resources(n, z);
                end
                
                % 重新计算偏好重力和选择概率
                [F, P] = calc_preference_gravity(agent_resources, L_less, B, dist_matrix, G, N, M, K);
                
                % 根据概率选择新任务
                prob_vec = P(n, :, z);
                prob_vec = prob_vec / (sum(prob_vec) + 1e-10);  % 归一化
                
                % 轮盘赌选择
                new_task = roulette_selection(prob_vec);
                
                if new_task > 0 && new_task <= M
                    % 创建新联盟结构
                    SC_new = SC;
                    SC_new(new_task, n, z) = 1;
                    
                    % 计算新结构的哈希值
                    hash_new = calc_SC_hash(SC_new);
                    
                    % 检查是否在禁忌表中
                    if ~ismember(hash_new, TabuSC)
                        % 比较UAV n的个体效用变化（按比例分配）
                        individual_utility_new = calc_individual_utility_for_agent(n, SC_new, agent_resources, tasks, dist_matrix, N, M, K, beta_m, C_req, omega, omega_1, omega_2, omega_3);
                        individual_utility_old = calc_individual_utility_for_agent(n, SC, agent_resources, tasks, dist_matrix, N, M, K, beta_m, C_req, omega, omega_1, omega_2, omega_3);
                        
                        if individual_utility_new > individual_utility_old
                            % 只接受改进的解（贪婪策略）
                            SC = SC_new;
                            L_less = update_remaining_demand(SC, agent_resources, tasks, M, K);
                            kstable = 0;
                        else
                            % 拒绝较差解，恢复原状
                            if ~isempty(current_task)
                                SC(current_task, n, z) = 1;
                                L_less(current_task, z) = L_less(current_task, z) - agent_resources(n, z);
                            end
                            kstable = kstable + 1;
                        end
                    else
                        % 在禁忌表中，恢复原状
                        if ~isempty(current_task)
                            SC(current_task, n, z) = 1;
                            L_less(current_task, z) = L_less(current_task, z) - agent_resources(n, z);
                        end
                        kstable = kstable + 1;
                    end
                end
            end
        end
        
        % 更新Boltzmann系数 (公式28)
        G = G * alpha_G;
        
        % 更新禁忌表
        hash_current = calc_SC_hash(SC);
        TabuSC = [TabuSC, hash_current];
        if length(TabuSC) > Ltabu
            TabuSC = TabuSC(end-Ltabu+1:end);
        end
        
        % 记录当前效用
        utility_history(k) = calc_coalition_utility(SC, agent_resources, tasks, dist_matrix, N, M, K, beta_m, C_req, omega, omega_1, omega_2, omega_3);
        
        k = k + 1;
    end
    
    %% 构造输出结构
    % 将SC转换为标准格式
    coalitionstru = zeros(M, N);
    agentresources = zeros(N, M, K);
    
    for j = 1:M
        for i = 1:N
            if any(SC(j, i, :) > 0)
                coalitionstru(j, i) = 1;
                for z = 1:K
                    if SC(j, i, z) > 0
                        agentresources(i, j, z) = agent_resources(i, z);
                    end
                end
            end
        end
    end
    
    % 计算总效用
    totalvalue = calc_coalition_utility(SC, agent_resources, tasks, dist_matrix, N, M, K, beta_m, C_req, omega, omega_1, omega_2, omega_3);
    
    %% 输出
    Value_data = struct();
    Value_data.totalvalue = totalvalue;
    Value_data.coalitionstru = coalitionstru;
    Value_data.agentresources = agentresources;
    Value_data.num_coalitions = sum(sum(coalitionstru, 2) > 0);
    Value_data.avg_coalition_size = mean(sum(coalitionstru, 2));
    
    history_data = struct();
    history_data.algorithm = 'Qi2023_PGG_TS';
    history_data.final_utility = totalvalue;
    history_data.iterations = k - 1;
    history_data.utility_history = utility_history(1:k-1);
    
end

%% ========================================================================
%  辅助函数
%% ========================================================================

function [F, P] = calc_preference_gravity(agent_resources, L_less, B, dist_matrix, G, N, M, K)
% 计算偏好重力 F_n^(z) 和选择概率 P_n^(z)
% 公式(26): F_n^(z)(m) = B_m * L_m^(less,z) / (d_nm^2 + epsilon)
% 公式(27): P_n^(z)(m) = exp(G * F_n^(z)(m)) / sum(exp(G * F_n^(z)))

    epsilon = 1e-6;  % 避免除零
    F = zeros(N, M, K);
    P = zeros(N, M, K);
    
    for n = 1:N
        for z = 1:K
            if agent_resources(n, z) > 0
                for m = 1:M
                    % 偏好重力：任务收益 × 剩余需求 / 距离^2
                    F(n, m, z) = B(m) * max(L_less(m, z), 0) / (dist_matrix(n, m)^2 + epsilon);
                end
                
                % Softmax转换为概率
                F_vec = squeeze(F(n, :, z));
                F_max = max(F_vec);
                exp_F = exp(G * (F_vec - F_max));  % 数值稳定
                P(n, :, z) = exp_F / (sum(exp_F) + epsilon);
            end
        end
    end
end

function SC = allocate_by_probability(P, agent_resources, L_less, N, M, K)
% 根据选择概率分配资源形成初始联盟

    SC = zeros(M, N, K);
    remaining = L_less;
    
    for n = 1:N
        for z = 1:K
            if agent_resources(n, z) > 0
                % 根据概率选择任务
                prob_vec = P(n, :, z);
                prob_vec = prob_vec / (sum(prob_vec) + 1e-10);
                
                % 优先选择有需求的任务
                for m = 1:M
                    if remaining(m, z) <= 0
                        prob_vec(m) = 0;
                    end
                end
                
                if sum(prob_vec) > 0
                    prob_vec = prob_vec / sum(prob_vec);
                    selected_task = roulette_selection(prob_vec);
                    
                    if selected_task > 0
                        SC(selected_task, n, z) = 1;
                        remaining(selected_task, z) = remaining(selected_task, z) - agent_resources(n, z);
                    end
                end
            end
        end
    end
end

function task_idx = roulette_selection(prob_vec)
% 轮盘赌选择

    if sum(prob_vec) < 1e-10
        task_idx = 0;
        return;
    end
    
    cumsum_prob = cumsum(prob_vec);
    r = rand();
    task_idx = find(cumsum_prob >= r, 1);
    
    if isempty(task_idx)
        task_idx = length(prob_vec);
    end
end

function L_less = update_remaining_demand(SC, agent_resources, tasks, M, K)
% 更新任务剩余资源需求

    L_less = zeros(M, K);
    for m = 1:M
        demand = tasks(m).resource_demand(:)';
        if length(demand) < K
            demand = [demand, zeros(1, K - length(demand))];
        end
        
        allocated = zeros(1, K);
        for n = 1:size(SC, 2)
            for z = 1:K
                if SC(m, n, z) > 0
                    allocated(z) = allocated(z) + agent_resources(n, z);
                end
            end
        end
        
        L_less(m, :) = max(demand - allocated, 0);
    end
end

function hash = calc_SC_hash(SC)
% 计算联盟结构的哈希值（用于禁忌表）

    hash = sum(SC(:) .* (1:numel(SC))');
end

function utility = calc_coalition_utility(SC, agent_resources, tasks, dist_matrix, N, M, K, beta_m, C_req, omega, omega_1, omega_2, omega_3)
% 计算联盟结构的总效用
% 使用Qi2023论文公式：U_m(A_m) = 1 / (1 + exp(-beta_m * (C_m - C_req + omega/beta_m)))
% 其中 C_m(A_m) = D + omega_1*r(A_m) - omega_2*t_wait - omega_3*sum(e_n)
    
    utility = 0;
    
    for m = 1:M
        % 找到参与任务m的UAV
        members = [];
        allocated = zeros(1, K);
        
        for n = 1:N
            if any(SC(m, n, :) > 0)
                members = [members, n];
                for z = 1:K
                    if SC(m, n, z) > 0
                        allocated(z) = allocated(z) + agent_resources(n, z);
                    end
                end
            end
        end
        
        if ~isempty(members)
            % 获取任务需求
            demand = tasks(m).resource_demand(:)';
            if length(demand) < K
                demand = [demand, zeros(1, K - length(demand))];
            end
            
            % 计算资源完成度 r(A_m)
            r_A_m = WorldSim.calc_task_completion_degree(allocated, demand, K);
            
            % 计算距离成本（作为等待时间的近似）
            total_dist = 0;
            for n = members
                total_dist = total_dist + dist_matrix(n, m);
            end
            t_wait = total_dist;  % 距离作为等待时间的代理
            
            % 计算能量损耗（距离 × 联盟规模的简化模型）
            energy_cost = total_dist * length(members);
            
            % 计算联盟能力 C_m(A_m)
            D = tasks(m).value / 1000;  % 归一化任务价值作为基础能力
            C_m = D + omega_1 * r_A_m - omega_2 * t_wait - omega_3 * energy_cost;
            
            % 计算联盟效用（Sigmoid函数）
            U_m = 1.0 / (1.0 + exp(-beta_m * (C_m - C_req + omega / beta_m)));
            
            % 将效用转换回任务价值尺度
            task_utility = tasks(m).value * U_m;
            utility = utility + task_utility;
        end
    end
end

function individual_utility = calc_individual_utility_for_agent(agent_id, SC, agent_resources, tasks, dist_matrix, N, M, K, beta_m, C_req, omega, omega_1, omega_2, omega_3)
% 计算单个UAV的个体效用（按资源贡献比例从所有参与的任务中获得）
% 公式: u_n = sum_m [ (|A_m^(n)| / sum_{n'∈Mem(A_m)} |A_m^(n')|) * U_m(A_m) ]

    individual_utility = 0;
    
    for m = 1:M
        % 检查该UAV是否参与任务m
        if ~any(SC(m, agent_id, :) > 0)
            continue;
        end
        
        % 找到参与任务m的所有UAV
        members = [];
        allocated = zeros(1, K);
        contributions = zeros(N, 1);  % 每个UAV的贡献量
        
        for n = 1:N
            if any(SC(m, n, :) > 0)
                members = [members, n];
                agent_alloc = zeros(1, K);
                for z = 1:K
                    if SC(m, n, z) > 0
                        agent_alloc(z) = agent_resources(n, z);
                        allocated(z) = allocated(z) + agent_resources(n, z);
                    end
                end
                % 计算该UAV的贡献量 |A_m^(n)|
                contributions(n) = norm(agent_alloc);
            end
        end
        
        % 计算任务m的总效用（使用Qi2023论文的Sigmoid函数）
        demand = tasks(m).resource_demand(:)';
        if length(demand) < K
            demand = [demand, zeros(1, K - length(demand))];
        end
        r_A_m = WorldSim.calc_task_completion_degree(allocated, demand, K);
        
        total_dist = 0;
        for n = members
            total_dist = total_dist + dist_matrix(n, m);
        end
        
        % 计算联盟能力和效用
        t_wait = total_dist;
        energy_cost = total_dist * length(members);
        D = tasks(m).value / 1000;
        C_m = D + omega_1 * r_A_m - omega_2 * t_wait - omega_3 * energy_cost;
        sigmoid_U = 1.0 / (1.0 + exp(-beta_m * (C_m - C_req + omega / beta_m)));
        U_m = tasks(m).value * sigmoid_U;
        
        % 按比例分配：该UAV从任务m获得的效用
        total_contribution = sum(contributions);
        if total_contribution > 1e-10
            individual_utility = individual_utility + (contributions(agent_id) / total_contribution) * U_m;
        end
    end
end
