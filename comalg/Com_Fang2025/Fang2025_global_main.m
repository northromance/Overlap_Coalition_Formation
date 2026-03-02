function [Value_data, history_data] = Fang2025_global_main(agents, tasks, AddPara, Value_Params)
% FANG2025_GLOBAL_MAIN Fang2025框架 + 全局社会效用(GSU)判断准则
%
% === [与 Fang2025_main 的核心区别] ===
%   原版：调用 Overlap_Coalition_Formation → join_operation/leave_operation
%         接受准则基于 Preference_gain（局部效用差，BMBT公式）
%
%   本版：将 Join/Leave 操作内联于函数体内（消除外部依赖）
%         接受准则改为 global_utility_diff（全局社会效用GSU差值）
%         GSU = 所有 N 个智能体在候选解下的效用总和
%
% === [GSU Metropolis 准则] ===
%   delta_E = GSU(SC_candidate) - GSU(SC_current)
%   - delta_E > 0：无条件接受
%   - delta_E ≤ 0：以 exp(delta_E / T) 概率接受，允许跳出局部最优

%% ==================== 0. 随机数种子设置 ====================
if isfield(Value_Params, 'seed')
    rng(Value_Params.seed);
end

%% ==================== 1. 初始化阶段 ====================
eps_val   = 1e-6;
tol       = 1e-9;
history_data = struct();

Value_data = WorldSim.init_value_data(agents, tasks, Value_Params);
[Value_data, summatrix] = WorldSim.init_observe_belief_neighbor( ...
    Value_data, Value_Params.N, Value_Params.M, Value_Params);

%% ==================== 2. 主循环：多轮博弈迭代 ====================
for counter = 1:Value_Params.num_rounds

    %% 2.2 SA 初始化
    k_iter       = 1;
    previous_SC  = Value_data(1).SC;
    k_stable     = 0;
    doneflag     = 0;

    Value_Params.Temperature = max(Value_Params.T_min_round, ...
        Value_Params.T0_round * Value_Params.T_decay^(counter - 1));

    if AddPara.verbose
        fprintf('  [Fang-GSU] Round %d: 初始温度 = %.2f\n', counter, Value_Params.Temperature);
    end

    %% ==================== 2.3 第一轮：Soft Greedy 初始解 ====================
    if counter == 1
        if AddPara.verbose
            fprintf('  [Fang-GSU] 第1轮：基于低温概率生成初始联盟结构 (Soft Greedy)...\n');
        end

        SC_global            = Value_data(1).SC;
        task_type_demands    = Value_Params.task_type_demands;
        resource_confidence  = Value_Params.resource_confidence;
        T_init_construction  = Value_Params.T_init_construction;

        for i = 1:Value_Params.N
            Value_data(i).SC = SC_global;
            [~, resource_gap] = calc_gaps(Value_data(i), Value_Params, AddPara);
            probs = SA_Select_probs(Value_data(i), agents, tasks, Value_Params, resource_gap, T_init_construction);

            for k = 1:Value_Params.K
                resource_amt = agents(i).resources(k);
                if resource_amt <= 0, continue; end

                % 轮盘赌选择任务
                prob_vec = probs(k, :);
                cum_prob = cumsum(prob_vec);
                if cum_prob(end) > 1e-9
                    r_val        = rand * cum_prob(end);
                    selected_task = find(cum_prob >= r_val, 1, 'first');
                else
                    selected_task = randi(Value_Params.M);
                end
                if isempty(selected_task), selected_task = randi(Value_Params.M); end

                if SC_global{selected_task}(i, k) > 0, continue; end

                curr_alloc   = sum(SC_global{selected_task}(:, k));
                belief       = Value_data(i).initbelief(selected_task, :);
                exp_demand   = WorldSim.calculate_demand_quantile(belief, task_type_demands, resource_confidence);
                can_add      = max(0, exp_demand(k) - curr_alloc);

                if can_add > 0
                    SC_candidate = SC_global;
                    SC_candidate{selected_task}(i, k) = resource_amt;

                    Value_data_temp = Value_data;
                    for j = 1:Value_Params.N
                        Value_data_temp(j).SC = SC_candidate;
                    end
                    [isFeasible, ~, ~] = validate_feasibility(Value_data_temp, agents, tasks, ...
                        Value_Params, i, SC_candidate, true, AddPara);
                    if isFeasible
                        SC_global = SC_candidate;
                    end
                end
            end
            for j = 1:Value_Params.N, Value_data(j).SC = SC_global; end
        end

        % 同步初始解给所有智能体
        for i = 1:Value_Params.N
            Value_data(i).SC             = SC_global;
            Value_data(i).resources_matrix = OCFUtils.get_agent_resource_matrix(SC_global, i, Value_Params);
            Value_data(i).coalitionstru  = OCFUtils.build_coalitionstru_from_SC(SC_global, Value_Params, agents);
        end

        best_utility       = 0;
        for ii = 1:Value_Params.N
            best_utility = best_utility + UtilityEvaluator.calc_agent_total_utility( ...
                SC_global, agents, tasks, Value_Params, Value_data(ii), AddPara);
        end
        if AddPara.verbose
            fprintf('  [Fang-GSU] 第1轮：初始全局效用 = %.2f\n', best_utility);
        end
    end

    %% ==================== 3. SA 内循环（GSU版顺序博弈） ====================
    inner_loop_history = ResultProcessor.init_inner_loop_history();

    % 精英快照初始化
    elite_utility_init = 0;
    for j = 1:Value_Params.N
        elite_utility_init = elite_utility_init + UtilityEvaluator.calc_agent_total_utility( ...
            Value_data(j).SC, agents, tasks, Value_Params, Value_data(j), AddPara);
    end
    elite_global_utility = elite_utility_init;
    elite_SC             = Value_data(1).SC;
    elite_coalitionstru  = Value_data(1).coalitionstru;

    while doneflag == 0

        %% 3.1 顺序博弈：智能体 1..N 依次决策
        for ii = 1:Value_Params.N

            % --- 计算资源缺口与选择概率 ---
            [~, resource_gap] = calc_gaps(Value_data(ii), Value_Params, AddPara);
            probs_ii = SA_Select_probs(Value_data(ii), agents, tasks, Value_Params, ...
                resource_gap, Value_Params.Temperature);
            Value_data(ii).selectProb = probs_ii;

            % --- 备份当前状态 ---
            SC_backup = Value_data(ii).SC;

            % ============================================================
            %  [Join 操作] 内联实现（替代 join_operation.m）
            %  接受准则：global_utility_diff（GSU差值）替代 Preference_gain
            % ============================================================
            agentID = Value_data(ii).agentID;

            for r = 1:Value_Params.K
                % 1. 轮盘赌采样目标任务
                target = OCFUtils.sample_task_from_probs(probs_ii(r, :), Value_Params.M);
                if isempty(target), continue; end

                % 已在该任务中投入该资源，跳过
                if Value_data(ii).SC{target}(agentID, r) > tol, continue; end

                % 容量检查
                belief      = Value_data(ii).initbelief(target, :);
                exp_demand  = WorldSim.calculate_demand_quantile( ...
                    belief, Value_Params.task_type_demands, AddPara.resource_confidence);
                curr_alloc  = sum(Value_data(ii).SC{target}(:, r));
                can_add     = max(0, exp_demand(r) - curr_alloc);
                if can_add <= 0, continue; end

                % 2. 生成候选状态
                [SC_P, SC_Q, ~, R_agent_Q] = StateTran.join_changes( ...
                    Value_data(ii), agents, Value_Params, target, agentID, r);

                % 3. 可行性检测
                [feasible, ~, cost_data] = validate_feasibility( ...
                    Value_data(ii), agents, tasks, Value_Params, agentID, SC_Q, true, AddPara);
                if ~feasible, continue; end

                % 4. GSU差値（全局效用Metropolis准则）
                delta_E = global_utility_diff(tasks, agents, SC_P, SC_Q, agentID, Value_Params, Value_data(ii));

                % 5. 接受判断
                accept_join = false;
                if delta_E > 1e-4
                    accept_join = true;
                elseif delta_E < 0
                    T = max(Value_Params.Temperature, tol);
                    if rand < exp(delta_E / T)
                        accept_join = true;
                        if AddPara.verbose
                            fprintf('      [Join-GSU] Agent %d -> Task %d Res %d 概率接受 (dE=%.4f)\n', ...
                                agentID, target, r, delta_E);
                        end
                    end
                end

                % 6. 执行更新
                if accept_join
                    Value_data(ii).SC               = SC_Q;
                    Value_data(ii).resources_matrix = R_agent_Q;
                    if ~isempty(cost_data)
                        Value_data(ii).task_schedule = cost_data;
                    end
                    % 更新 coalitionstru
                    Value_data(ii).coalitionstru = update_coalitionstru( ...
                        Value_data(ii).coalitionstru, R_agent_Q, agentID, agents, Value_Params, tol);

                    if AddPara.verbose
                        fprintf('      [Join-GSU] Agent %d -> Task %d Res %d 接受 (dE=%.4f)\n', ...
                            agentID, target, r, delta_E);
                    end
                    break; % 每轮每个智能体只执行一次加入
                end
            end  % end for r (Join)

            % ============================================================
            %  [Leave 操作] 内联实现（替代 leave_operation.m）
            %  无论 Join 是否成功均执行：先完整尝试加入，再尝试离开能否提升 GSU
            % ============================================================
            original_rm = Value_data(ii).resources_matrix;

            for r = 1:Value_Params.K
                alloc_col       = Value_data(ii).resources_matrix(:, r);
                candidate_tasks = find(alloc_col > tol);
                if isempty(candidate_tasks), continue; end

                did_leave = false;
                for tidx = 1:numel(candidate_tasks)
                    src_task = candidate_tasks(tidx);

                    % 生成撤出后的状态
                    [SC_P, SC_Q, R_agent_P, R_agent_Q] = StateTran.leave_changes( ...
                        Value_data(ii), agents, Value_Params, src_task, agentID, r);

                    % 临时更新资源矩阵以供效用计算
                    Value_data(ii).resources_matrix = R_agent_Q;

                    % GSU差值
                    delta_E = global_utility_diff(tasks, agents, SC_P, SC_Q, agentID, Value_Params, Value_data(ii));

                    % 接受判断
                    accept_leave = false;
                    if delta_E > 1e-4
                        accept_leave = true;
                    elseif delta_E < 0
                        T = max(Value_Params.Temperature, tol);
                        if rand < exp(delta_E / T)
                            accept_leave = true;
                            if AddPara.verbose
                                fprintf('      [Leave-GSU] Agent %d <- Task %d Res %d 概率接受 (dE=%.4f)\n', ...
                                    agentID, src_task, r, delta_E);
                            end
                        end
                    end

                    if accept_leave
                        Value_data(ii).SC               = SC_Q;
                        Value_data(ii).resources_matrix = R_agent_Q;
                        Value_data(ii).coalitionstru    = update_coalitionstru( ...
                            Value_data(ii).coalitionstru, R_agent_Q, agentID, agents, Value_Params, tol);
                        if AddPara.verbose
                            fprintf('      [Leave-GSU] Agent %d <- Task %d Res %d 接受 (dE=%.4f)\n', ...
                                agentID, src_task, r, delta_E);
                        end
                        did_leave = true;
                        break;
                    else
                        Value_data(ii).resources_matrix = R_agent_P; % 回滚资源矩阵
                    end
                end  % end for tidx
                if did_leave, break; end
            end  % end for r (Leave)

            % 如果 Join+Leave 均无变化，回滚 resources_matrix 至快照
            SC_now_changed = false;
            for m = 1:Value_Params.M
                if ~isequal(SC_backup{m}, Value_data(ii).SC{m})
                    SC_now_changed = true; break;
                end
            end
            if ~SC_now_changed
                Value_data(ii).resources_matrix = original_rm;
            end

            % --- 信息传递：将更新后的 SC 传递给下一个智能体 ---
            if ii < Value_Params.N
                Value_data(ii + 1).coalitionstru = Value_data(ii).coalitionstru;
                Value_data(ii + 1).SC            = Value_data(ii).SC;
            end
        end  % end for ii (顺序博弈)

        %% 3.3 降温
        Value_Params.Temperature = Value_Params.alpha * Value_Params.Temperature;

        final_SC            = Value_data(Value_Params.N).SC;
        final_coalitionstru = Value_data(Value_Params.N).coalitionstru;

        %% 3.4 收敛检测
        if isequal(previous_SC, final_SC)
            k_stable = k_stable + 1;
        else
            k_stable = 0;
        end

        if k_stable >= Value_Params.K_stable_max
            doneflag = 1;
        elseif Value_Params.Temperature < Value_Params.Tmin
            doneflag = 1;
        elseif k_iter >= Value_Params.max_inner_iter
            doneflag = 1;
        end

        previous_SC = final_SC;
        k_iter      = k_iter + 1;

        %% 3.5 全局状态同步
        for ii = 1:Value_Params.N
            Value_data(ii).coalitionstru  = final_coalitionstru;
            Value_data(ii).SC             = final_SC;
            Value_data(ii).resources_matrix = OCFUtils.get_agent_resource_matrix(final_SC, ii, Value_Params);
        end

        % 计算当前全局效用
        current_utility = 0;
        for j = 1:Value_Params.N
            current_utility = current_utility + UtilityEvaluator.calc_agent_total_utility( ...
                final_SC, agents, tasks, Value_Params, Value_data(j), AddPara);
        end

        % 精英快照更新
        if current_utility > elite_global_utility
            elite_global_utility = current_utility;
            elite_SC             = final_SC;
            elite_coalitionstru  = final_coalitionstru;
            if AddPara.verbose
                fprintf('    [Elite] 发现本轮历史最高全局效用: %.2f (Iter: %d)\n', elite_global_utility, k_iter - 1);
            end
        end

        % 记录内循环历史
        inner_loop_history = ResultProcessor.record_inner_loop_iteration( ...
            inner_loop_history, k_iter - 1, Value_Params.Temperature, ...
            current_utility, elite_global_utility, final_SC, Value_Params);
    end  % end while

    %% 强制采纳精英方案
    if AddPara.verbose
        fprintf('  [Fang-GSU Done] Round %d 内循环结束，采纳精英方案 (Utility: %.2f)\n', counter, elite_global_utility);
    end
    final_SC            = elite_SC;
    final_coalitionstru = elite_coalitionstru;
    for ii = 1:Value_Params.N
        Value_data(ii).coalitionstru  = final_coalitionstru;
        Value_data(ii).SC             = final_SC;
        Value_data(ii).resources_matrix = OCFUtils.get_agent_resource_matrix(final_SC, ii, Value_Params);
    end

    Value_data = update_task_schedule(Value_data, agents, tasks, Value_Params);

    %% ==================== 4. 观测与信念更新 ====================
    [Value_data, summatrix] = AgentOps.collect_observations( ...
        Value_data, agents, tasks, Value_Params, summatrix, final_SC);
    Value_data = AgentOps.update_belief_from_observations(Value_data, Value_Params);

    %% ==================== 5. 结果评估 ====================
    [coalition_utility, total_global_cost, total_completed_value, task_completion_degrees] = ...
        UtilityEvaluator.evaluate_coalition_metrics(final_SC, agents, tasks, Value_Params, eps_val);

    %% 信念广播
    for i = 1:Value_Params.N
        for j = 1:Value_Params.N
            Value_data(i).other{j}.initbelief = Value_data(j).initbelief;
        end
    end

    %% 记录历史数据
    history_data = ResultProcessor.record_history_data(history_data, counter, Value_data, Value_Params, ...
        final_SC, final_coalitionstru, ...
        coalition_utility, total_global_cost, ...
        total_completed_value, task_completion_degrees, ...
        summatrix);
    history_data.k_iter_per_round{counter} = k_iter;
    history_data.inner_loop{counter}       = inner_loop_history;
end

%% ==================== 6. 最终一致性检查 ====================
if AddPara.verbose
    fprintf('\n[Fang2025_Global] 执行最终一致性检查...\n');
end
[is_valid, error_log] = check_coalition_consistency( ...
    Value_data, agents, tasks, Value_Params, 'OCF', AddPara.verbose);
if ~is_valid
    warning('[Fang2025_Global] 一致性检查发现 %d 处问题', length(error_log));
    history_data.consistency_errors = error_log;
else
    if AddPara.verbose
        fprintf('  [Fang2025_Global] 所有一致性检查通过！\n');
    end
end
end

%% ==================== 内部辅助函数 ====================

% -----------------------------------------------------------------------
% update_coalitionstru: 根据新的资源矩阵更新联盟归属结构
% -----------------------------------------------------------------------
function coalition = update_coalitionstru(coalition, R_agent_Q, agentID, agents, Value_Params, tol)
agentIdx           = agentID;
assigned_tasks     = find(any(R_agent_Q > tol, 2));
coalition(1:Value_Params.M, agentIdx) = 0;
for mIdx = assigned_tasks'
    coalition(mIdx, agentIdx) = agents(agentIdx).id;
end
if isempty(assigned_tasks)
    coalition(Value_Params.M + 1, agentIdx) = agents(agentIdx).id;
else
    coalition(Value_Params.M + 1, agentIdx) = 0;
end
end

% -----------------------------------------------------------------------
% global_utility_diff: 计算候选解与当前解的全局社会效用(GSU)差值
%   delta_E = GSU(SC_candidate) - GSU(SC_current)
%   正值表示候选解更优，负值表示候选解更差
% -----------------------------------------------------------------------
function delta_E = global_utility_diff(tasks, agents, SC_current, SC_candidate, agent_idx, Value_Params, Value_data_i) %#ok<INUSL>
AddPara_silent.verbose = false;

GSU_candidate = 0;
for j = 1:Value_Params.N
    if j == agent_idx
        agent_belief = Value_data_i.initbelief;
    elseif length(Value_data_i.other) >= j && ~isempty(Value_data_i.other{j})
        agent_belief = Value_data_i.other{j}.initbelief;
    else
        agent_belief = Value_data_i.initbelief;
    end
    temp_data.agentIndex = j;
    temp_data.initbelief = agent_belief;
    temp_data.SC         = SC_candidate;
    GSU_candidate = GSU_candidate + UtilityEvaluator.calc_agent_total_utility( ...
        SC_candidate, agents, tasks, Value_Params, temp_data, AddPara_silent);
end

GSU_current = 0;
for j = 1:Value_Params.N
    if j == agent_idx
        agent_belief = Value_data_i.initbelief;
    elseif length(Value_data_i.other) >= j && ~isempty(Value_data_i.other{j})
        agent_belief = Value_data_i.other{j}.initbelief;
    else
        agent_belief = Value_data_i.initbelief;
    end
    temp_data.agentIndex = j;
    temp_data.initbelief = agent_belief;
    temp_data.SC         = SC_current;
    GSU_current = GSU_current + UtilityEvaluator.calc_agent_total_utility( ...
        SC_current, agents, tasks, Value_Params, temp_data, AddPara_silent);
end

delta_E = GSU_candidate - GSU_current;
end
