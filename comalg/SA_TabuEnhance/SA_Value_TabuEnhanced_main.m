function [Value_data, history_data] = SA_Value_TabuEnhanced_main(agents, tasks, AddPara, Value_Params)

% SA_VALUE_TABUENHANCED_MAIN 基于模拟退火和禁忌搜索的重叠联盟形成算法主函数
% 这个是结合了模拟退火（SA）和禁忌搜索（Tabu Search）的增强版本，旨在提升联盟形成过程中的全局搜索能力和跳出局部最优的能力。
% 按照Osman框架写的
%% ==================== 0. 随机数种子设置 ====================
if isfield(Value_Params, 'seed')
    rng(Value_Params.seed); % 固定种子以复现实验结果
end

%% ==================== 1. 初始化阶段 ====================
eps_val = 1e-6;          % 浮点数比较容差
history_data = struct(); % 初始化历史记录容器
tabu_tenure = 20;   % 禁忌期限（根据智能体数量自适应）

% --- 初始化智能体核心数据结构 (Value_data) ---
% 包含 SC (联盟结构矩阵), resources (资源状态), position (位置) 等
Value_data = WorldSim.init_value_data(agents, tasks, Value_Params);

% --- 初始化观测、信念与邻居信息 ---
% summatrix 用于记录观测次数，initbelief 初始化为先验分布
[Value_data, summatrix] = WorldSim.init_observe_belief_neighbor(Value_data, Value_Params.N, Value_Params.M, Value_Params);

%% ==================== 2. 主循环：多轮博弈迭代 ====================


for counter = 1:Value_Params.num_rounds
    
    %% 2.2 SA 初始化 (本轮博弈前的准备)
    k_iter = 1;                         % 内循环迭代计数器
    previous_SC = Value_data(1).SC;     % 用于检测状态是否变化的基准
    k_stable = 0;                       % 稳定计数器 (连续多少次状态未变)
    doneflag = 0;                       % 内循环结束标志
    
    % --- 温度调度策略 ---
    % 采用指数衰减策略，随着轮数 (counter) 增加，初始温度 T 逐轮降低
    % 意味着后期的博弈探索性降低，更倾向于利用 (Exploitation)
    % Value_Params.Temperature = max(Value_Params.SA_T_base_round, Value_Params.SA_T0_round * Value_Params.SA_beta_round^(counter-1));
    
    if AddPara.verbose
        fprintf('  [SA] Round %d: 初始温度 = %.2f\n', counter, Value_Params.Temperature);
    end
    
    % 初始化本轮“主观最优”记录变量
    best_SC = Value_data(1).SC;
    best_coalitionstru = Value_data(1).coalitionstru;
    % ⭐⭐⭐ [关键修复开始] ⭐⭐⭐
    % 在每一轮开始时，必须基于“当前的信念”重新计算继承下来的 SC 的效用。
    % 否则 Round 2 的新效用会和 Round 1 的旧效用（基于旧信念）进行错误比较。
    best_utility = 0;
    for j = 1:Value_Params.N
        best_utility = best_utility + UtilityEvaluator.calc_agent_total_utility(best_SC, agents, tasks, Value_Params, Value_data(j), AddPara);
    end

    %% ==================== 2.25 初始化禁忌列表 ====================
    % 禁忌列表用于存储最近访问过的联盟结构，防止算法陷入循环
    tabu_list = {};                          % 禁忌列表（存储SC的哈希值）

    if AddPara.verbose
        fprintf('  [Tabu] 禁忌期限 = %d\\n', tabu_tenure);
    end

    %% ==================== 2.3 第一轮特有：生成初始解 (Soft Greedy) ====================
    % 在第1轮，为了避免从完全随机开始，使用启发式规则快速构建一个可行的初始解
    if counter == 1
        if AddPara.verbose
            fprintf('  [SA] 第1轮：基于低温概率与规则生成的初始联盟结构 (Soft Greedy)...\n');
        end
        
        SC_global = Value_data(1).SC;
        task_type_demands = Value_Params.task_type_demands;
        resource_confidence = Value_Params.SA_resource_confidence; % 初始置信度
        T_init_construction = Value_Params.SA_T_init_construction; % 构造阶段使用极低温度，接近贪婪选择
        
        for i = 1:Value_Params.N
            Value_data(i).SC = SC_global;
            
            % 计算当前资源缺口 (Gap)
            [~, resource_gap] = calc_gaps(Value_data(i), Value_Params, AddPara);
            
            % 基于缺口计算选择概率 (Probabilities)
            probs = SA_Select_probs(Value_data(i), agents, tasks, Value_Params, resource_gap, T_init_construction);
            
            for k = 1:Value_Params.K
                resource_amt = agents(i).resources(k);
                if resource_amt <= 0, continue; end % 无资源则跳过
                
                % 轮盘赌采样目标任务
                prob_vec = probs(k, :);
                cum_prob = cumsum(prob_vec);
                if cum_prob(end) > 1e-9
                    r = rand * cum_prob(end);
                    selected_task = find(cum_prob >= r, 1, 'first');
                else
                    selected_task = randi(Value_Params.M);
                end
                if isempty(selected_task), selected_task = randi(Value_Params.M); end
                
                % --- 查重检测 ---
                % 如果该资源已经在该任务中，则跳过 (防止重复叠加)
                if SC_global{selected_task}(i, k) > 0, continue; end
                
                % --- 需求估算 ---
                curr_alloc = sum(SC_global{selected_task}(:, k));
                belief = Value_data(i).initbelief(selected_task, :);
                expected_demand = WorldSim.calculate_demand_quantile(belief, task_type_demands, resource_confidence);
                
                % 仅当预期还有缺口时才尝试加入
                can_add = max(0, expected_demand(k) - curr_alloc);
                
                if can_add > 0
                    % 构造候选 SC
                    SC_candidate = SC_global;
                    SC_candidate{selected_task}(i, k) = resource_amt;
                    
                    % 临时同步数据以进行可行性检测
                    Value_data_temp = Value_data;
                    for j=1:Value_Params.N, Value_data_temp(j).SC = SC_candidate; end
                    
                    % 可行性检测 (能量、路径、载重)
                    [isFeasible, ~, ~] = validate_feasibility(Value_data_temp, agents, tasks, ...
                        Value_Params, i, SC_candidate, true, AddPara);
                        
                    if isFeasible
                        SC_global = SC_candidate; % 接受变更
                    end
                end
            end
            % 每一位智能体操作完，暂存状态
            for j = 1:Value_Params.N, Value_data(j).SC = SC_global; end
        end
        
        % --- 初始化结束后的全网同步 ---
        for i = 1:Value_Params.N
            Value_data(i).SC = SC_global;
            Value_data(i).resources_matrix = OCFUtils.get_agent_resource_matrix(SC_global, i, Value_Params);
            Value_data(i).coalitionstru = OCFUtils.build_coalitionstru_from_SC(SC_global, Value_Params, agents);
        end
        
        best_SC = SC_global;
        best_coalitionstru = Value_data(1).coalitionstru;

        for ii = 1:Value_Params.N
            u_i = UtilityEvaluator.calc_agent_total_utility(SC_global, agents, tasks, Value_Params, Value_data(ii), AddPara);
            best_utility = best_utility + u_i;
        end
        
        if AddPara.verbose
            fprintf('  [SA] 第1轮：初始主观效用 = %.2f\n', best_utility);
        end
    end
    
    %% ==================== 3. SA 内循环 (核心博弈过程) ====================
    % 初始化内循环历史记录
    inner_loop_history = ResultProcessor.init_inner_loop_history();

    while(doneflag == 0)

        % --- 3.1 顺序博弈 (Sequential Game) ---
        % 智能体按照 1 到 N 的顺序依次决策
        for ii = 1:Value_Params.N
            % 核心函数：Overlapping Coalition Formation
            % 内部包含 Join/Leave/Switch 操作及 Metropolis 准则判断
            [Value_data_ii] = Overlap_Coalition_Formation(agents, tasks, Value_data(ii), Value_Params, AddPara);

            % 更新当前智能体状态
            Value_data(ii) = Value_data_ii;

            % [关键] 信息传递：将最新的 SC 传递给下一个智能体
            % 模拟共享黑板 (Shared Blackboard) 机制
            if ii < Value_Params.N
                Value_data(ii + 1).coalitionstru = Value_data_ii.coalitionstru;
                Value_data(ii + 1).SC = Value_data_ii.SC;
            end
        end

        % --- 3.3 降温 (Cooling) ---
        Value_Params.Temperature = Value_Params.alpha * Value_Params.Temperature;

        % 获取本轮迭代结束后的最终状态
        final_SC = Value_data(Value_Params.N).SC;
        final_coalitionstru = Value_data(Value_Params.N).coalitionstru;

        % --- 3.35 禁忌检测 (Tabu Check) ---
        % 计算当前解的哈希值
        current_hash = get_SC_hash(final_SC, Value_Params);

        % 检查是否在禁忌列表中
        is_tabu = is_in_tabu_list(current_hash, tabu_list);

        if is_tabu
            % 计算当前解的效用（用于特赦准则判断）
            current_utility_check = 0;
            for j = 1:Value_Params.N
                current_utility_check = current_utility_check + UtilityEvaluator.calc_agent_total_utility(final_SC, agents, tasks, Value_Params, Value_data(j), AddPara);
            end

            % 特赦准则：如果禁忌解优于历史最优，仍然接受
            if current_utility_check > best_utility
                if AddPara.verbose
                    fprintf('    [Tabu-Aspiration] 特赦接受禁忌解 (效用=%.2f > 最优=%.2f)\\n', current_utility_check, best_utility);
                end
                % 接受该解，继续执行
            else
                % 拒绝禁忌解，回滚到上一个状态
                if AddPara.verbose
                    fprintf('    [Tabu-Reject] 拒绝禁忌解 (效用=%.2f)\\n', current_utility_check);
                end
                final_SC = previous_SC;
                final_coalitionstru = Value_data(1).coalitionstru;

                % 回滚所有智能体状态
                for ii = 1:Value_Params.N
                    Value_data(ii).SC = previous_SC;
                    Value_data(ii).coalitionstru = final_coalitionstru;
                end
            end
        else
            % 不在禁忌列表中，将当前解加入禁忌列表
            tabu_list = update_tabu_list(tabu_list, current_hash, tabu_tenure);
        end

        % --- 3.4 收敛检测 (Convergence Check) ---
        if isequal(previous_SC, final_SC)
            k_stable = k_stable + 1; % 状态未变，稳定计数器+1
        else
            k_stable = 0;            % 状态改变，重置计数器
        end

        % 判断是否退出内循环
        if k_stable >= Value_Params.K_len_SA        % 连续多次未变
            doneflag = 1;
        elseif Value_Params.Temperature < Value_Params.Tmin % 温度过低
            doneflag = 1;
        elseif k_iter >= Value_Params.K_max_inner_SA % 达到最大迭代次数
            doneflag = 1;
        end

        previous_SC = final_SC;
        k_iter = k_iter + 1;

        % --- 3.5 全网状态同步 ---
        % 确保下一轮迭代开始前，所有智能体对 SC 达成共识
        for ii = 1:Value_Params.N
            Value_data(ii).coalitionstru = final_coalitionstru;
            Value_data(ii).SC = final_SC;
            Value_data(ii).resources_matrix = OCFUtils.get_agent_resource_matrix(Value_data(ii).SC, ii, Value_Params);
        end

        % --- 3.7 更新本轮最优解 (基于主观效用) ---
        % 注意：SA 过程中可能会接受差解，因此需要记录过程中出现过的"主观最好"状态
        current_utility = 0;
        for j = 1:Value_Params.N
            % 计算全系统的主观效用总和
            current_utility = current_utility + UtilityEvaluator.calc_agent_total_utility(final_SC, agents, tasks, Value_Params, Value_data(j), AddPara);
        end

        if current_utility > best_utility
            best_utility = current_utility;
            best_SC = final_SC;
            best_coalitionstru = final_coalitionstru;
        end

        % --- 3.8 记录内循环历史数据 ---
        inner_loop_history = ResultProcessor.record_inner_loop_iteration(...
            inner_loop_history, k_iter - 1, Value_Params.Temperature, ...
            current_utility, best_utility, final_SC, Value_Params);
    end
    
    %% 3.8 恢复本轮最优解
    % 如果内循环结束时的解不如过程中遇到的最优解，强制回滚到最优解
    if ~isequal(final_SC, best_SC)
        if AddPara.verbose
            fprintf('  [SA] Round %d: 恢复本轮最优解\n', counter);
        end
        final_SC = best_SC;
        final_coalitionstru = best_coalitionstru;
    end
    
    % 将最优解应用到所有智能体
    for ii = 1:Value_Params.N
        Value_data(ii).coalitionstru = best_coalitionstru;
        Value_data(ii).SC = best_SC;
        Value_data(ii).resources_matrix = OCFUtils.get_agent_resource_matrix(Value_data(ii).SC, ii, Value_Params);
    end
    
    % 重新计算并缓存任务时间表 (Task Schedule) 和路径成本
    Value_data = update_task_schedule(Value_data, agents, tasks, Value_Params);
    
    %% ==================== 4. 观测与信念更新 ====================
    
    % --- 4.1 收集观测数据 ---
    % 智能体基于 final_SC 执行任务，观测任务的真实反馈
    [Value_data, summatrix] = AgentOps.collect_observations(Value_data, agents, tasks, Value_Params, summatrix, final_SC);
    
    % --- 4.2 贝叶斯信念更新 ---
    % 利用 Dirichlet 分布更新对任务需求的认知 (Belief)
    Value_data = AgentOps.update_belief_from_observations(Value_data, Value_Params);
    
    %% ==================== 5. 结果评估 (客观/上帝视角) ====================
    
    % 使用真实参数评估当前联盟结构的性能
    [coalition_utility, total_global_cost, total_completed_value, task_completion_degrees] = ...
        UtilityEvaluator.evaluate_coalition_metrics(final_SC, agents, tasks, Value_Params, eps_val);

    

    
    %% 4.8 信念广播
    % 模拟智能体之间的通信，交换信念参数
    for i = 1:Value_Params.N
        for j = 1:Value_Params.N
            Value_data(i).other{j}.initbelief = Value_data(j).initbelief;
        end
    end
    
    % --- 记录本轮历史数据 ---
    history_data = ResultProcessor.record_history_data(history_data, counter, Value_data, Value_Params, ...
        final_SC, final_coalitionstru, ...
        coalition_utility, total_global_cost, ...
        total_completed_value, task_completion_degrees, ...
        summatrix);

    % --- 记录内循环历史数据 ---
    history_data.inner_loop{counter} = inner_loop_history;
end

%% ==================== 6. 结束与最终检查 ====================


% --- 最终一致性检查 ---
% 验证 SC、coalitionstru 和 resources_matrix 是否逻辑互洽
if AddPara.verbose
    fprintf('\n[SA_Value] 执行最终一致性检查...\n');
end

[is_valid, error_log] = check_coalition_consistency(Value_data, agents, tasks, Value_Params, 'OCF', AddPara.verbose);

if ~is_valid
    warning('[SA_Value] 一致性检查发现 %d 处问题', length(error_log));
    history_data.consistency_errors = error_log;
else
    if AddPara.verbose
        fprintf('✅ [SA_Value] 所有一致性检查通过！\n');
    end
end

end

%% ==================== 内部辅助函数 (Internal Helper Functions) ====================

function hash_str = get_SC_hash(SC, Value_Params)
    % GET_SC_HASH 计算联盟结构SC的哈希值
    %
    % 输入:
    %   SC          - 联盟结构 (cell array of matrices)
    %   Value_Params - 参数结构体
    %
    % 输出:
    %   hash_str    - SC的哈希字符串
    %
    % 说明:
    %   将SC转换为唯一的字符串标识，用于禁忌列表检测
    %   采用稀疏表示法：只记录非零元素的 (task, agent, resource, amount)

    hash_parts = {};
    eps_val = 1e-9;

    for m = 1:Value_Params.M
        SC_m = SC{m};
        [rows, cols] = find(SC_m > eps_val);

        for idx = 1:length(rows)
            i = rows(idx);
            k = cols(idx);
            amount = SC_m(i, k);

            % 格式: "m-i-k-amount"
            hash_parts{end+1} = sprintf('%d-%d-%d-%.4f', m, i, k, amount);
        end
    end

    % 排序以确保相同SC产生相同哈希
    hash_parts = sort(hash_parts);

    % 拼接成字符串
    if isempty(hash_parts)
        hash_str = 'EMPTY';
    else
        hash_str = strjoin_custom(hash_parts, '|');
    end
end

function is_tabu = is_in_tabu_list(hash_str, tabu_list)
    % IS_IN_TABU_LIST 检查哈希值是否在禁忌列表中
    %
    % 输入:
    %   hash_str   - 待检查的哈希字符串
    %   tabu_list  - 禁忌列表 (cell array of strings)
    %
    % 输出:
    %   is_tabu    - 是否在禁忌列表中 (boolean)

    is_tabu = false;

    for i = 1:length(tabu_list)
        if strcmp(tabu_list{i}, hash_str)
            is_tabu = true;
            return;
        end
    end
end

function tabu_list = update_tabu_list(tabu_list, hash_str, tabu_tenure)
    % UPDATE_TABU_LIST 更新禁忌列表（FIFO队列）
    %
    % 输入:
    %   tabu_list   - 当前禁忌列表
    %   hash_str    - 要添加的哈希字符串
    %   tabu_tenure - 禁忌期限（列表最大长度）
    %
    % 输出:
    %   tabu_list   - 更新后的禁忌列表
    %
    % 说明:
    %   采用FIFO策略：当列表满时，移除最早的元素

    % 添加新元素到列表末尾
    tabu_list{end+1} = hash_str;

    % 如果超过禁忌期限，移除最早的元素
    if length(tabu_list) > tabu_tenure
        tabu_list = tabu_list(2:end);
    end
end

function result = strjoin_custom(cell_array, delimiter)
    % STRJOIN_CUSTOM 自定义字符串拼接函数（兼容旧版MATLAB）
    %
    % 输入:
    %   cell_array - 字符串cell数组
    %   delimiter  - 分隔符
    %
    % 输出:
    %   result     - 拼接后的字符串

    if isempty(cell_array)
        result = '';
        return;
    end

    result = cell_array{1};
    for i = 2:length(cell_array)
        result = [result, delimiter, cell_array{i}];
    end
end
