function [Value_data, history_data] = PSO_main(agents, tasks, AddPara, Value_Params)
% PSO_MAIN 基于粒子群优化的重叠联盟形成算法
%
% 核心改进（参考 SA_TabuEnhanced_Altruistic）：
%   - 使用 calculate_demand_quantile 计算期望需求
%   - 只给有需求的资源分配
%   - 使用 Soft Greedy 初始化策略
%   - 严格的约束处理和可行性检查

%% ==================== 0. 随机数种子设置 ====================
if isfield(Value_Params, 'seed')
    rng(Value_Params.seed);
end

%% ==================== 1. 初始化 ====================
if AddPara.verbose
    fprintf('\n[PSO] 粒子群优化算法开始...\n');
end

eps_val = 1e-6;
history_data = struct();
N = Value_Params.N;
M = Value_Params.M;
K = Value_Params.K;

% PSO 参数
swarm_size = Value_Params.PSO_swarm_size;
w_max = Value_Params.PSO_w_max;
w_min = Value_Params.PSO_w_min;
c1 = Value_Params.PSO_c1;
c2 = Value_Params.PSO_c2;
K_max_inner = Value_Params.PSO_K_max_inner;
K_len = Value_Params.PSO_K_len;

% 初始化智能体数据
Value_data = WorldSim.init_value_data(agents, tasks, Value_Params);
[Value_data, summatrix] = WorldSim.init_observe_belief_neighbor(Value_data, N, M, Value_Params);

% 任务需求模板和置信度（参考SA）
task_type_demands = Value_Params.task_type_demands;
resource_confidence = 0.9;
if isfield(AddPara, 'resource_confidence')
    resource_confidence = AddPara.resource_confidence;
end

%% ==================== 2. 主循环：多轮博弈 ====================
for counter = 1:Value_Params.num_rounds

    if AddPara.verbose
        fprintf('\n[PSO] === Round %d/%d ===\n', counter, Value_Params.num_rounds);
    end

    %% 2.1 初始化粒子群
    particles = struct();

    for p = 1:swarm_size
        % 使用 Soft Greedy 初始化所有粒子
        particles(p).SC = initialize_smart_particle(agents, tasks, Value_Params, Value_data, AddPara, ...
            task_type_demands, resource_confidence, p);

        % 速度初始化为零（离散PSO）
        particles(p).delta_SC = cell(M, 1);
        for m = 1:M
            particles(p).delta_SC{m} = zeros(N, K);
        end

        % 个体历史最优
        particles(p).best_SC = particles(p).SC;
        particles(p).best_fitness = -inf;
        particles(p).fitness = -inf;
    end

    % 全局最优
    global_best_SC = particles(1).SC;
    global_best_fitness = -inf;

    %% 2.2 PSO 主循环
    k_iter = 0;
    k_stable = 0;
    prev_global_best_fitness = -inf;

    % 初始化内循环历史记录
    inner_loop_history = ResultProcessor.init_inner_loop_history();

    while k_iter < K_max_inner && k_stable < K_len
        k_iter = k_iter + 1;

        % 计算惯性权重（线性递减）
        w = w_max - (w_max - w_min) * (k_iter / K_max_inner);

        %% 2.2.1 评估所有粒子的适应度
        for p = 1:swarm_size
            % 确保 SC 满足约束
            particles(p).SC = repair_SC_smart(particles(p).SC, agents, tasks, Value_Params, ...
                Value_data, AddPara, task_type_demands, resource_confidence);

            % 更新 Value_data 以计算适应度
            for i = 1:N
                Value_data(i).SC = particles(p).SC;
                Value_data(i).resources_matrix = OCFUtils.get_agent_resource_matrix(particles(p).SC, i, Value_Params);
                Value_data(i).coalitionstru = OCFUtils.build_coalitionstru_from_SC(particles(p).SC, Value_Params, agents);
            end

            % ⭐ 可行性检查：确保所有智能体满足能量约束
            is_feasible = true;
            for i = 1:N
                [isFeasible_i, ~, ~] = validate_feasibility(Value_data, agents, tasks, ...
                    Value_Params, i, particles(p).SC, true, AddPara);
                if ~isFeasible_i
                    is_feasible = false;
                    break;
                end
            end

            % 计算适应度（总效用）
            if is_feasible
                fitness = 0;
                for i = 1:N
                    fitness = fitness + UtilityEvaluator.calc_agent_total_utility(particles(p).SC, agents, tasks, Value_Params, Value_data(i), AddPara);
                end
                particles(p).fitness = fitness;
            else
                % 不可行解，赋予极低适应度
                particles(p).fitness = -inf;
            end

            % 更新个体最优
            if fitness > particles(p).best_fitness
                particles(p).best_fitness = fitness;
                particles(p).best_SC = particles(p).SC;
            end

            % 更新全局最优
            if fitness > global_best_fitness
                global_best_fitness = fitness;
                global_best_SC = particles(p).SC;

                if AddPara.verbose
                    fprintf('  [PSO] Iter %d: 发现新的全局最优 Fitness=%.2f (Particle %d)\n', ...
                        k_iter, global_best_fitness, p);
                end
            end
        end

        %% 2.2.2 更新所有粒子
        for p = 1:swarm_size
            % 离散PSO更新：基于概率交换操作
            particles(p).SC = update_particle_discrete(particles(p).SC, particles(p).best_SC, ...
                global_best_SC, w, c1, c2, agents, tasks, Value_Params, Value_data, AddPara, ...
                task_type_demands, resource_confidence);
        end

        %% 2.2.3 记录内循环历史
        inner_loop_history = ResultProcessor.record_inner_loop_iteration(...
            inner_loop_history, k_iter, ...
            w, global_best_fitness, global_best_fitness, global_best_SC, Value_Params);

        %% 2.2.4 收敛检测
        if abs(global_best_fitness - prev_global_best_fitness) < eps_val
            k_stable = k_stable + 1;
        else
            k_stable = 0;
        end
        prev_global_best_fitness = global_best_fitness;

        if AddPara.verbose && mod(k_iter, 10) == 0
            fprintf('  [PSO] Iter %d: w=%.3f, Best Fitness=%.2f, Stable=%d/%d\n', ...
                k_iter, w, global_best_fitness, k_stable, K_len);
        end
    end

    %% 2.3 本轮结束：使用全局最优解
    final_SC = global_best_SC;
    final_coalitionstru = OCFUtils.build_coalitionstru_from_SC(final_SC, Value_Params, agents);

    % 更新所有智能体的状态
    for i = 1:N
        Value_data(i).SC = final_SC;
        Value_data(i).resources_matrix = OCFUtils.get_agent_resource_matrix(final_SC, i, Value_Params);
        Value_data(i).coalitionstru = final_coalitionstru;
    end

    % 计算任务时间表
    Value_data = update_task_schedule(Value_data, agents, tasks, Value_Params);

    if AddPara.verbose
        fprintf('  [PSO] Round %d 完成，迭代次数=%d, 最优适应度=%.2f\n', ...
            counter, k_iter, global_best_fitness);
    end

    %% 2.4 观测与信念更新
    [Value_data, summatrix] = AgentOps.collect_observations(Value_data, agents, tasks, Value_Params, summatrix, final_SC);
    Value_data = AgentOps.update_belief_from_observations(Value_data, Value_Params);

    %% 2.5 评估与记录
    [coalition_utility, total_global_cost, total_completed_value, task_completion_degrees] = ...
        UtilityEvaluator.evaluate_coalition_metrics(final_SC, agents, tasks, Value_Params, eps_val);

    % 信念广播
    for i = 1:N
        for j = 1:N
            Value_data(i).other{j}.initbelief = Value_data(j).initbelief;
        end
    end

    % 记录历史数据
    history_data = ResultProcessor.record_history_data(history_data, counter, Value_data, Value_Params, ...
        final_SC, final_coalitionstru, ...
        coalition_utility, total_global_cost, ...
        total_completed_value, task_completion_degrees, ...
        summatrix);

    % 记录内循环历史
    history_data.inner_loop{counter} = inner_loop_history;

    % 记录本轮的内循环迭代次数
    history_data.k_iter_per_round{counter} = k_iter;
end

%% ==================== 3. 最终一致性检查 ====================
if AddPara.verbose
    fprintf('\n[PSO] 执行最终一致性检查...\n');
end

[is_valid, error_log] = check_coalition_consistency(Value_data, agents, tasks, Value_Params, 'OCF', AddPara.verbose);

if ~is_valid
    warning('[PSO] 一致性检查发现 %d 处问题', length(error_log));
    history_data.consistency_errors = error_log;
else
    if AddPara.verbose
        fprintf('  [PSO] 所有一致性检查通过！\n');
    end
end

end

%% ==================== 辅助函数 ====================

function SC = initialize_smart_particle(agents, tasks, Value_Params, Value_data, AddPara, ...
    task_type_demands, resource_confidence, particle_id)
% 智能初始化粒子（参考 SA_TabuEnhanced_Altruistic 的 Soft Greedy 策略）

N = Value_Params.N;
M = Value_Params.M;
K = Value_Params.K;

SC = cell(M, 1);
for m = 1:M
    SC{m} = zeros(N, K);
end

% 温度控制随机性（第一个粒子温度最低，最贪心）
T_init = 0.5 + (particle_id - 1) * 0.1;  % 温度从0.5到更高

% 按智能体顺序分配资源
for i = 1:N
    Value_data(i).SC = SC;

    % 计算资源缺口
    [~, resource_gap] = calc_gaps(Value_data(i), Value_Params, AddPara);

    % 计算选择概率
    probs = SA_Select_probs(Value_data(i), agents, tasks, Value_Params, resource_gap, T_init);

    % 为每种资源选择任务
    for k = 1:K
        resource_amt = agents(i).resources(k);
        if resource_amt <= 0, continue; end

        % 轮盘赌选择任务
        prob_vec = probs(k, :);
        cum_prob = cumsum(prob_vec);
        if cum_prob(end) > 1e-9
            r = rand * cum_prob(end);
            selected_task = find(cum_prob >= r, 1, 'first');
        else
            selected_task = randi(M);
        end

        % 如果已分配，跳过
        if SC{selected_task}(i, k) > 0, continue; end

        % ⭐ 关键检查：计算期望需求
        curr_alloc = sum(SC{selected_task}(:, k));
        belief = Value_data(i).initbelief(selected_task, :);
        expected_demand = WorldSim.calculate_demand_quantile(belief, task_type_demands, resource_confidence);
        can_add = max(0, expected_demand(k) - curr_alloc);

        % ⭐ 只有需求大于0时才分配
        if can_add > 1e-6
            SC_candidate = SC;
            SC_candidate{selected_task}(i, k) = resource_amt;

            % 可行性检查
            Value_data_temp = Value_data;
            for j = 1:N
                Value_data_temp(j).SC = SC_candidate;
            end

            [isFeasible, ~, ~] = validate_feasibility(Value_data_temp, agents, tasks, ...
                Value_Params, i, SC_candidate, true, AddPara);

            if isFeasible
                SC = SC_candidate;
            end
        end
    end

    % 同步状态
    for j = 1:N
        Value_data(j).SC = SC;
    end
end
end

function SC = repair_SC_smart(SC, agents, tasks, Value_Params, Value_data, AddPara, ...
    task_type_demands, resource_confidence)
% 智能修复 SC（确保满足所有约束，包括零需求检查）

N = Value_Params.N;
M = Value_Params.M;
K = Value_Params.K;
eps_val = 1e-9;

% ⭐ 约束1: 移除零需求分配
for m = 1:M
    for k = 1:K
        % 计算该任务对资源k的期望需求
        total_expected_demand = 0;
        for i = 1:N
            if SC{m}(i, k) > eps_val
                belief = Value_data(i).initbelief(m, :);
                expected_demand = WorldSim.calculate_demand_quantile(belief, task_type_demands, resource_confidence);
                total_expected_demand = max(total_expected_demand, expected_demand(k));
            end
        end

        % 如果需求为0，清除所有分配
        if total_expected_demand < eps_val
            SC{m}(:, k) = 0;
        end
    end
end

% 约束2: 每个智能体的资源总分配不能超过其拥有量
for i = 1:N
    for k = 1:K
        total_allocated = 0;
        for m = 1:M
            total_allocated = total_allocated + SC{m}(i, k);
        end

        % 如果超额，按比例缩减
        if total_allocated > agents(i).resources(k) + eps_val
            scale = agents(i).resources(k) / total_allocated;
            for m = 1:M
                SC{m}(i, k) = SC{m}(i, k) * scale;
            end
        end
    end
end

% 约束3: 非负约束和稀疏化
threshold = 0.01;
for m = 1:M
    SC{m}(SC{m} < threshold) = 0;
end
end

function SC_new = update_particle_discrete(SC_current, SC_pbest, SC_gbest, w, c1, c2, ...
    agents, tasks, Value_Params, Value_data, AddPara, task_type_demands, resource_confidence)
% 离散PSO更新策略

N = Value_Params.N;
M = Value_Params.M;
K = Value_Params.K;

SC_new = SC_current;

% 对每个任务、每个智能体、每种资源进行概率性更新
for m = 1:M
    for i = 1:N
        for k = 1:K
            % 计算更新概率
            p_inertia = w;                    % 保持当前状态的概率
            p_cognitive = c1 * rand;          % 向个体最优学习的概率
            p_social = c2 * rand;             % 向全局最优学习的概率

            % 归一化概率
            total_p = p_inertia + p_cognitive + p_social;
            p_inertia = p_inertia / total_p;
            p_cognitive = p_cognitive / total_p;
            p_social = p_social / total_p;

            % 根据概率选择更新策略
            r = rand;
            if r < p_inertia
                % 保持当前值
                SC_new{m}(i, k) = SC_current{m}(i, k);
            elseif r < p_inertia + p_cognitive
                % 学习个体最优
                SC_new{m}(i, k) = SC_pbest{m}(i, k);
            else
                % 学习全局最优
                SC_new{m}(i, k) = SC_gbest{m}(i, k);
            end
        end
    end
end

% 修复约束
SC_new = repair_SC_smart(SC_new, agents, tasks, Value_Params, Value_data, AddPara, ...
    task_type_demands, resource_confidence);

% ⭐ 可行性验证：确保修复后的解满足所有约束（特别是能量约束）
Value_data_temp = Value_data;
for i = 1:N
    Value_data_temp(i).SC = SC_new;
end

% 检查所有智能体的能量可行性
all_feasible = true;
for i = 1:N
    [isFeasible, ~, ~] = validate_feasibility(Value_data_temp, agents, tasks, ...
        Value_Params, i, SC_new, true, AddPara);
    if ~isFeasible
        all_feasible = false;
        break;
    end
end

% 如果不可行，回退到当前解
if ~all_feasible
    SC_new = SC_current;
end
end
