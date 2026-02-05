function [Value_data, history_data] = TSA_Qi_Combined_main(agents, tasks, AddPara, Value_Params)
% TSA_Qi_Combined_main - 最终修正版
% 修复了哈希敏感度，优化了 O(N^2) 的计算瓶颈

%% 0. 参数设置与初始化
if isfield(Value_Params, 'seed'), rng(Value_Params.seed); end
eps_val = 1e-9;
N = Value_Params.N;
M = Value_Params.M;
K = Value_Params.K;

% --- TSA 参数 ---
L_tabu = 10;
K_len = 20;
K_max_inner = 50;
T_sa = 100;
alpha_sa = 0.8;
T_min = Value_Params.Tmin;
best_utility_in_round = 0;
current_utility = 0;

Gamma_init = Value_Params.Qi_Gamma_init;       % 初始 Boltzmann 系数
Gamma_max = Value_Params.Qi_Gamma_max;         % 最大 Boltzmann 系数
Gamma = Gamma_init;                            % 当前 Boltzmann 系数

history_data = struct();
Value_data = WorldSim.init_value_data(agents, tasks, Value_Params);
[Value_data, summatrix] = WorldSim.init_observe_belief_neighbor(Value_data, N, M, Value_Params);

SC_global = cell(M, 1);
for m = 1:M, SC_global{m} = zeros(N, K); end

%% 主循环
for round = 1:Value_Params.num_rounds
    k_iter = 1;
    k_stable = 0;
    TabuList = {};
    current_T = T_sa;
    Gamma = Gamma_init;  % 重置为初始值

    %% 1. 初始解生成
    if round == 1
        for i = 1:N
            Value_data(i).SC = SC_global;
            [~, resource_gap] = calc_gaps(Value_data(i), Value_Params, AddPara);
            probs = Qi2023_Select_probs(Value_data(i), agents, tasks, Value_Params, resource_gap, Value_Params.Qi_Gamma_init);
            SC_global = execute_exchange_operation(i, agents, tasks, SC_global, probs, Value_Params, Value_data, AddPara);
            for j = 1:N, Value_data(j).SC = SC_global; end
        end
    end


        % 记录初始状态（使用期望效用）
    current_utility = 0;
    for i = 1:N
        Value_data(i).SC = SC_global;
        current_utility = current_utility + UtilityEvaluator.calc_agent_total_utility(SC_global, agents, tasks, Value_Params, Value_data(i), AddPara);
    end
    if AddPara.verbose
        fprintf('[Qi2023] 第 %d 轮初始效用（期望）: %.4f\n', round, current_utility);
    end



    %% 2. TSA 内循环核心逻辑
    %% 2. TSA 内循环核心逻辑 (修正版)
    inner_loop_history = ResultProcessor.init_inner_loop_history();

    while k_iter <= K_max_inner && k_stable <= K_len && current_T > T_min
        improved_this_iter = false;

        for i = 1:N
            % --- A. 生成候选邻居 ---
            SC_temp = SC_global;

            % 1. 随机撤出 (Leave)
            p_leave = 0.3;
            for m = 1:M
                for k = 1:K
                    if SC_temp{m}(i, k) > eps_val && rand < p_leave
                        SC_temp{m}(i, k) = 0;
                    end
                end
            end

            % 2. 重新分配 (Join/Switch based on Preference)
            Value_data(i).SC = SC_temp;
            [~, resource_gap] = calc_gaps(Value_data(i), Value_Params, AddPara);
            % 使用 Qi2023 偏好概率
            probs_new = Qi2023_Select_probs(Value_data(i), agents, tasks, Value_Params, resource_gap, Value_Params.Qi_Gamma_max);
            SC_new_candidate = execute_exchange_operation(i, agents, tasks, SC_temp, probs_new, Value_Params, Value_data, AddPara);

            % --- B. 计算偏好差 (delta_u) ---
            % 注意：这是智能体决策的依据，不是全网效用的变化量
            delta_u = Preference_gain(tasks, agents, SC_global, SC_new_candidate, i, Value_Params, Value_data(i));

            % --- C. TSA 接受逻辑 ---
            SC_hash = get_SC_hash(SC_new_candidate);
            is_tabu = is_in_tabu(SC_hash, TabuList);

            accept_move = false;
            calculated_new_global_utility = -1; % 标记位，避免重复计算

            if ~is_tabu
                % === 非禁忌状态 ===
                % 使用 delta_u (偏好差) 进行 Metropolis 判决
                if delta_u > 0
                    accept_move = true;
                else
                    % 即使偏好下降，也有概率接受（模拟退火）
                    if rand < exp(delta_u / current_T)
                        accept_move = true;
                    end
                end
            else
                % === 禁忌状态 (执行渴望准则检查) ===
                % 为了检查是否突破历史最优，这里必须计算全网真实效用
                % (虽然计算量大，但只有命中禁忌时才算，频率可控)

                % 临时同步 SC 以计算准确效用
                calculated_new_global_utility = 0;
                for j = 1:N
                    temp_agent = Value_data(j);
                    temp_agent.SC = SC_new_candidate;
                    calculated_new_global_utility = calculated_new_global_utility + ...
                        UtilityEvaluator.calc_agent_total_utility(SC_new_candidate, agents, tasks, Value_Params, temp_agent, AddPara);
                end

                % 渴望准则：如果 全网效用 > 本轮历史最优，则强制接受
                if calculated_new_global_utility > best_utility_in_round + eps_val
                    accept_move = true;
                    if AddPara.verbose, fprintf('    [Aspiration] 突破禁忌! (Util: %.2f > Best: %.2f)\n', calculated_new_global_utility, best_utility_in_round); end
                else
                    accept_move = false; % 未触发渴望准则，拒绝
                end
            end

            % --- D. 执行更新 ---
            if accept_move
                SC_global = SC_new_candidate;

                % 如果之前没算过全网效用（非禁忌路径进来），现在必须算一次以更新 current_utility
                if calculated_new_global_utility == -1
                    current_utility = 0;
                    for j = 1:N
                        % 这里可以复用 Value_data(j) 因为马上要同步了，但为了安全起见还是用临时变量或直接传入 SC
                        % 注意：calc_agent_total_utility 内部依赖 Value_data.SC，所以计算前最好更新一下传入的结构体
                        temp_agent = Value_data(j);
                        temp_agent.SC = SC_global;
                        current_utility = current_utility + ...
                            UtilityEvaluator.calc_agent_total_utility(SC_global, agents, tasks, Value_Params, temp_agent, AddPara);
                    end
                else
                    % 如果在渴望准则里算过了，直接用
                    current_utility = calculated_new_global_utility;
                end

                % 更新本轮全局最优记录
                if current_utility > best_utility_in_round
                    best_utility_in_round = current_utility;
                    improved_this_iter = true;
                end

                % 更新禁忌表
                TabuList = update_tabu_list(TabuList, SC_hash, L_tabu);

                % [必须同步] 确保所有智能体看到最新 SC
                for k = 1:N
                    Value_data(k).SC = SC_global;
                end
            end
        end

        % --- E. 冷却与记录 ---
        current_T = current_T * alpha_sa;
        if ~improved_this_iter
            k_stable = k_stable + 1;
        else
            k_stable = 0;
        end


        % F. 更新Boltzmann系数（探索与开发的权衡）
        % Gamma(k+1) = Gamma(k) + k * (Gamma_max - Gamma(k)) / K_max
        Gamma = Gamma + k_iter * (Gamma_max - Gamma) / K_max_inner;

        inner_loop_history = ResultProcessor.record_inner_loop_iteration(...
            inner_loop_history, k_iter, current_T, ...
            current_utility, best_utility_in_round, SC_global, Value_Params);
        k_iter = k_iter + 1;
    end

    %% 3. 后续处理 (保持不变)
    [Value_data, summatrix] = AgentOps.collect_observations(Value_data, agents, tasks, Value_Params, summatrix, SC_global);
    if AddPara.enable_belief_update
        Value_data = AgentOps.update_belief_from_observations(Value_data, Value_Params);
        for i = 1:N, for j = 1:N, Value_data(i).other{j}.initbelief = Value_data(j).initbelief; end; end
    end

    final_SC = SC_global;
    for ii = 1:N
        Value_data(ii).SC = final_SC;
        Value_data(ii).resources_matrix = OCFUtils.get_agent_resource_matrix(final_SC, ii, Value_Params);
        Value_data(ii).coalitionstru = OCFUtils.build_coalitionstru_from_SC(final_SC, Value_Params, agents);
    end

    [coal_u, cost, c_val, t_deg] = UtilityEvaluator.evaluate_coalition_metrics(SC_global, agents, tasks, Value_Params, eps_val);
    history_data = ResultProcessor.record_history_data(history_data, round, Value_data, Value_Params, ...
        SC_global, Value_data(1).coalitionstru, coal_u, cost, c_val, t_deg, summatrix);
    history_data.inner_loop{round} = inner_loop_history;
end

check_coalition_consistency(Value_data, agents, tasks, Value_Params, 'OCF', AddPara.verbose);
end

%% --- 关键辅助函数修正 ---

function hash_str = get_SC_hash(SC)
% [关键修复] 增加 round 避免浮点数哈希失效
temp_vec = [];
for m = 1:length(SC)
    % 保留3位小数后取整，消除 0.30000001 和 0.3 的差异
    rounded = round(SC{m} * 1000) / 1000;
    temp_vec = [temp_vec; rounded(:)];
end
hash_str = mat2str(temp_vec);
end

function is_in = is_in_tabu(sc_hash, tabu_list)
is_in = any(strcmp(sc_hash, tabu_list));
end

function tabu_list = update_tabu_list(tabu_list, sc_hash, L_tabu)
tabu_list{end+1} = sc_hash;
if length(tabu_list) > L_tabu, tabu_list(1) = []; end
end