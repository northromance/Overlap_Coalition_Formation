function [Value_data, history_data] = PGG_TS_main(agents, tasks, AddPara, Value_Params)
% PGG_TS_main - 基于 Algorithm 2: Preference Gravity-Guided Tabu Search
% 严格对应图片流程：Initial -> Loop(Leave -> Gravity -> Exch -> Tabu -> Utility)

%% 0. 参数解析与初始化
if isfield(Value_Params, 'seed'), rng(Value_Params.seed); end
eps_val = 1e-9;
N = Value_Params.N;
M = Value_Params.M;
K = Value_Params.K;

% --- Tabu Search 特定参数 ---
L_tabu = 10;                % Tabu 列表长度
K_len = 20;                 % 稳定性阈值 (k_stable 阈值)
K_max = Value_Params.num_rounds; % 最大迭代次数
TabuList = {};              % 初始化禁忌表为空
Gamma = 100;                % 初始温度 (Boltzmann coefficient)
alpha = 0.98;               % 降温系数


% 初始化输出结构
history_data = struct();
Value_data = init_value_data(agents, tasks, Value_Params); % 封装初始化函数
summatrix = zeros(M, Value_Params.task_type);

% 全局联盟结构 SC (M x N x K 逻辑，此处简化为 Cell 结构以适配你的代码)
SC_global = cell(M, 1);
for m = 1:M, SC_global{m} = zeros(N, K); end

k_iter = 1;
k_stable = 0;

%% 1. 初始联盟结构生成 (Initialization)
% "To get the initial coalition structure SC(1), all initial resources... allocated by P(1)"

fprintf('Generating Initial Coalition Structure based on P(1)...\n');
for i = 1:N
    % 1.1 计算初始偏好重力 F 和 概率 P
    [F_vec, P_vec] = calculate_gravity_and_prob(i, agents, tasks, SC_global, Gamma, Value_Params);
    
    % 1.2 根据 P 进行初始分配 (Initial Allocation)
    SC_global = execute_exchange_operation(i, agents, SC_global, P_vec, tasks);
end

% 记录初始状态
current_utility = UtilityEvaluator.evaluate_coalition_metrics(SC_global, agents, tasks, Value_Params, eps_val);

%% 2. 主循环 (Loop until Stable or Max Iteration)
while k_iter <= K_max && k_stable <= K_len
    
    % 保存本轮原本的 SC，用于回滚
    SC_old_global = SC_global;
    
    % Loop \forall n \in N (遍历每个无人机)
    for i = 1:N
        % -----------------------------------------------------------
        % A. 随机撤离 (Randomly select partial resource to leave)
        % -----------------------------------------------------------
        SC_temp = SC_global; % 临时操作副本
        
        % 简单的撤离逻辑：每个已参与的任务有一定概率撤出部分资源
        p_leave = 0.3; % 随机撤离概率
        for m = 1:M
            for k = 1:K
                if SC_temp{m}(i, k) > eps_val && rand < p_leave
                    % 撤离资源 (设为0，即离开当前联盟)
                    SC_temp{m}(i, k) = 0;
                end
            end
        end
        
        % -----------------------------------------------------------
        % B. 计算偏好重力 F 和 概率向量 P
        % Calculate F_n(k) and P_n(k) by (26) and (27)
        % -----------------------------------------------------------
        % 注意：F 的计算通常依赖于当前的剩余需求和距离
        [F_vec, P_vec] = calculate_gravity_and_prob(i, agents, tasks, SC_temp, Gamma, Value_Params);
        
        % -----------------------------------------------------------
        % C. 执行交换操作 (Make an exchange operation)
        % UAV n make an exchange operation based on selection probability vector P
        % -----------------------------------------------------------
        SC_new_candidate = execute_exchange_operation(i, agents, SC_temp, P_vec, tasks);
        
        % -----------------------------------------------------------
        % D. 禁忌表检查 (Check Tabu List)
        % If SC_new not in Tabu_SC
        % -----------------------------------------------------------
        SC_hash = get_SC_hash(SC_new_candidate); % 将矩阵转为字符串hash以便比较
        is_tabu = is_in_tabu(SC_hash, TabuList);
        
        accepted = false;
        
        if ~is_tabu
            % -------------------------------------------------------
            % E. 效用判断 (Utility Check)
            % If SC_new >_n SC_old (Better utility)
            % -------------------------------------------------------
            % 计算新结构的效用
            new_utility = UtilityEvaluator.evaluate_coalition_metrics(SC_new_candidate, agents, tasks, Value_Params, eps_val);
            
            % 计算效用差 (Delta U)
            delta_u = new_utility - current_utility;
            
            % 如果效用提升 (这里使用全局效用作为 >_n 的代理，也可改为个体效用)
            if delta_u > 0 % 或者 > small_threshold
                % Accept: Update Global SC
                SC_global = SC_new_candidate;
                current_utility = new_utility;
                k_stable = 0; % Reset stability
                accepted = true;
            else
                % Else: Keep old (reject change)
                % SC_global 保持不变 (即等于 SC_old_global 的当前状态)
                % 注意：图片逻辑如果是 else，则 SC(k+1) = SC(k)，且 k_stable + 1
                % 但这是针对 agent 循环内部还是外部？
                % 图片缩进显示 k_stable = k_stable + 1 是在 Else 分支
                % 这意味着如果单个 agent 的移动没有改善，稳定性计数就增加
                 k_stable = k_stable + 1;
            end
        else
             % 如果在禁忌表中，通常直接拒绝 (或者有特赦准则 Aspiration Criterion，图片未显示)
             % 保持不变
             k_stable = k_stable + 1;
        end
        
        % 如果接受了新状态，立即更新 Tabu 表
        if accepted
            TabuList = update_tabu_list(TabuList, SC_hash, L_tabu);
        end
        
    end % End Agent Loop
    
    % -----------------------------------------------------------
    % F. 更新温度和 Tabu (Update Boltzmann & Tabu logic)
    % Update Boltzmann coefficient Gamma(k+1)
    % -----------------------------------------------------------
    Gamma = Gamma * alpha; % 降温
    
    % Update Tabu List based on SC^(k+1) (已经在上面实时更新，或在此处统筹更新)
    
    % 记录历史数据
    history_data = record_history(history_data, k_iter, SC_global, current_utility);
    
    fprintf('Round %d: Utility = %.4f, Stability = %d, Temp = %.4f\n', k_iter, current_utility, k_stable, Gamma);
    
    k_iter = k_iter + 1;
end

% Output Stable Structure
Value_data(1).SC = SC_global; % 将结果存回 Value_data

end

%% ================= 辅助函数 =================

function [F, P] = calculate_gravity_and_prob(agent_idx, agents, tasks, SC, Gamma, Value_Params)
    % 实现图片中的 F_n(z) 和 P_n(z) 计算
    M = Value_Params.M;
    K = Value_Params.K;
    F = zeros(M, K); % M个任务，K种资源
    
    agent_pos = [agents(agent_idx).x, agents(agent_idx).y];
    
    % 1. 计算偏好重力 F (Gravity)
    % F ~ (Expected Value * Remaining Demand) / Distance^2
    for m = 1:M
        task_pos = [tasks(m).x, tasks(m).y];
        dist_sq = sum((agent_pos - task_pos).^2) + 1e-6;
        
        for k = 1:K
            % 计算剩余需求 (Remaining Demand)
            current_allocated = sum(SC{m}(:, k));
            demand = tasks(m).resource_demand(k);
            rem_demand = max(0, demand - current_allocated);
            
            % 这里的 Value 可以是任务价值，也可以是 agent 的信念价值
            task_val = tasks(m).value; 
            
            % 公式: F = V * Rem / Dist^2
            F(m, k) = (task_val * rem_demand) / dist_sq;
        end
    end
    
    % 2. 计算概率 P (Softmax)
    % P ~ exp(F / Gamma)
    P = zeros(M, K);
    for k = 1:K
        vec = F(:, k);
        % Softmax 稳定性处理
        vec = vec - max(vec); 
        exp_vec = exp(vec / Gamma);
        P(:, k) = exp_vec / sum(exp_vec);
    end
end

function SC_new = execute_exchange_operation(agent_idx, agents, SC_current, P_prob, tasks)
    % 轮盘赌选择新任务并分配资源
    SC_new = SC_current;
    M = length(SC_current);
    K = size(SC_current{1}, 2);
    
    for k = 1:K
        resource_amt = agents(agent_idx).resources(k);
        if resource_amt <= 0, continue; end
        
        % 轮盘赌 (Roulette Wheel Selection)
        cum_prob = cumsum(P_prob(:, k));
        r = rand;
        selected_task = find(cum_prob >= r, 1, 'first');
        
        if isempty(selected_task), selected_task = randi(M); end
        
        % 分配资源到选定任务
        % 注意：这里是一个简化的 "Exchange"，实际可能需要考虑资源约束
        % 先清空该 agent 在该资源上的所有分配 (因为前面已经 Leave 了一部分，这里重新分配剩余的)
        for m = 1:M
            SC_new{m}(agent_idx, k) = 0;
        end
        
        % 分配到新任务 (不超过需求上限)
        curr_alloc = sum(SC_new{selected_task}(:, k));
        demand = tasks(selected_task).resource_demand(k);
        can_add = max(0, demand - curr_alloc);
        
        act_add = min(resource_amt, can_add);
        SC_new{selected_task}(agent_idx, k) = act_add;
    end
end

function hash_str = get_SC_hash(SC)
    % 简单的 Hash 生成，用于 Tabu 比较
    % 将 Cell 数组转换为长向量并转字符串
    % 注意：对于大矩阵，建议使用更高效的 Hash 算法 (如 DataHash)
    temp_vec = [];
    for m = 1:length(SC)
        temp_vec = [temp_vec; SC{m}(:)];
    end
    hash_str = mat2str(temp_vec); % 或使用 num2hex 等
end

function is_in = is_in_tabu(sc_hash, tabu_list)
    is_in = false;
    for i = 1:length(tabu_list)
        if strcmp(sc_hash, tabu_list{i})
            is_in = true;
            return;
        end
    end
end

function tabu_list = update_tabu_list(tabu_list, sc_hash, L_tabu)
    tabu_list{end+1} = sc_hash;
    if length(tabu_list) > L_tabu
        tabu_list(1) = []; % 移除最旧的 (FIFO)
    end
end

% ... (init_value_data, record_history 等辅助函数保持原代码风格)
function Value_data = init_value_data(agents, tasks, Value_Params)
   % 复制你原代码中的初始化部分
   N = Value_Params.N;
   for i=1:N
       Value_data(i).agentID = agents(i).id;
       % ... 其他初始化 ...
   end
end

function history_data = record_history(hist, k, SC, util)
    hist(k).SC = SC;
    hist(k).utility = util;
end