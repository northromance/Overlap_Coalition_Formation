function [is_valid, error_log] = check_coalition_consistency(Value_data, agents, tasks, Value_Params, algorithm_type)
% CHECK_COALITION_CONSISTENCY 统一的联盟一致性检查函数
%
% 功能：
%   根据算法类型（重叠联盟OCF或非重叠联盟Non-OCF）执行相应的一致性检查
%   整合了数据一致性、资源约束、结构对应关系和可行性验证
%
% 输入：
%   Value_data     - 1xN 结构体数组，包含所有智能体的数据
%   agents         - 智能体数组
%   tasks          - 任务数组
%   Value_Params   - 全局参数结构体 (M, N, K等)
%   algorithm_type - 算法类型字符串：
%                    'OCF'     - 重叠联盟（资源可复用）
%                    'Non-OCF' - 非重叠联盟（资源不可复用）
%
% 输出：
%   is_valid   - 布尔值，true表示所有检查通过
%   error_log  - 错误信息元胞数组
%
% 检查内容：
%   1. 全局一致性检查：所有智能体的SC和coalitionstru是否达成共识
%   2. 资源约束检查：单任务资源投入是否超过智能体上限
%   3. 结构对应检查：coalitionstru与SC的双向映射关系
%   4. 自洽性检查：个体资源矩阵与全局SC的一致性
%   5. 可行性检查：验证能量约束是否满足
%
% 使用示例：
%   % 对于重叠联盟算法（如Shi2024, Qi2023）
%   [is_valid, errors] = check_coalition_consistency(Value_data, agents, tasks, Value_Params, 'OCF');
%
%   % 对于非重叠联盟算法
%   [is_valid, errors] = check_coalition_consistency(Value_data, agents, tasks, Value_Params, 'Non-OCF');

    %% 初始化
    is_valid = true;
    error_log = {};
    tol = 1e-6;  % 浮点数比较容差

    N = Value_Params.N;  % 智能体数量
    M = Value_Params.M;  % 任务数量
    K = Value_Params.K;  % 资源类型数量

    % 验证算法类型参数
    if ~ismember(algorithm_type, {'OCF', 'Non-OCF'})
        error('算法类型必须是 ''OCF'' 或 ''Non-OCF''');
    end

    fprintf('\n==============================================\n');
    fprintf('联盟一致性检查 [算法类型: %s]\n', algorithm_type);
    fprintf('智能体数: %d | 任务数: %d | 资源类型: %d\n', N, M, K);
    fprintf('==============================================\n');

    %% 检查1：全局一致性检查 (Global Consensus Check)
    % 验证所有智能体的SC和coalitionstru是否完全一致
    fprintf('\n[检查1] 全局一致性检查...\n');
    [consensus_valid, consensus_errors] = check_global_consensus(Value_data, Value_Params, tol);
    if ~consensus_valid
        is_valid = false;
        error_log = [error_log, consensus_errors];
    end

    %% 检查2：资源约束检查 (Resource Constraints Check)
    % 验证资源分配是否满足约束条件
    fprintf('\n[检查2] 资源约束检查...\n');
    if strcmp(algorithm_type, 'OCF')
        % 重叠联盟：检查单任务资源投入是否超过智能体上限（资源可复用）
        [resource_valid, resource_errors] = check_resource_constraints_OCF(Value_data, agents, Value_Params, tol);
    else
        % 非重叠联盟：检查所有任务的资源总和是否超过智能体上限（资源不可复用）
        [resource_valid, resource_errors] = check_resource_constraints_NonOCF(Value_data, agents, Value_Params, tol);
    end
    if ~resource_valid
        is_valid = false;
        error_log = [error_log, resource_errors];
    end

    %% 检查3：结构对应检查 (Structure Mapping Check)
    % 验证coalitionstru与SC的双向映射关系
    fprintf('\n[检查3] 结构对应检查...\n');
    [mapping_valid, mapping_errors] = check_structure_mapping(Value_data, Value_Params, tol);
    if ~mapping_valid
        is_valid = false;
        error_log = [error_log, mapping_errors];
    end

    %% 检查4：自洽性检查 (Self-Consistency Check)
    % 验证个体资源矩阵与全局SC的一致性
    fprintf('\n[检查4] 自洽性检查...\n');
    [self_valid, self_errors] = check_self_consistency(Value_data, Value_Params, tol);
    if ~self_valid
        is_valid = false;
        error_log = [error_log, self_errors];
    end

    %% 检查5：可行性检查 (Feasibility Check)
    % 验证能量约束是否满足
    fprintf('\n[检查5] 可行性检查（能量约束）...\n');
    [feasibility_valid, feasibility_errors] = check_energy_feasibility(Value_data, agents, tasks, Value_Params, tol);
    if ~feasibility_valid
        is_valid = false;
        error_log = [error_log, feasibility_errors];
    end

    %% 总结报告
    fprintf('\n==============================================\n');
    if is_valid
        fprintf('✅ 所有检查通过！联盟结构合法且一致。\n');
    else
        fprintf('❌ 检查失败！发现 %d 处错误：\n', length(error_log));
        for i = 1:min(10, length(error_log))  % 最多显示前10个错误
            fprintf('  %d. %s\n', i, error_log{i});
        end
        if length(error_log) > 10
            fprintf('  ... 还有 %d 个错误未显示\n', length(error_log) - 10);
        end
    end
    fprintf('==============================================\n\n');
end

%% ========== 子函数：检查1 - 全局一致性 ==========
function [is_valid, error_log] = check_global_consensus(Value_data, Value_Params, tol)
    % 检查所有智能体的SC和coalitionstru是否与Agent 1一致
    is_valid = true;
    error_log = {};

    base_SC = Value_data(1).SC;
    base_stru = Value_data(1).coalitionstru;

    for i = 2:Value_Params.N
        % 检查联盟结构
        if ~isequal(base_stru, Value_data(i).coalitionstru)
            msg = sprintf('Agent %d 的 coalitionstru 与 Agent 1 不一致', i);
            error_log{end+1} = msg;
            fprintf('  ❌ %s\n', msg);
            is_valid = false;
        end

        % 检查SC（逐任务检查）
        for j = 1:Value_Params.M
            if ~isempty(base_SC{j}) && ~isempty(Value_data(i).SC{j})
                diff_sc = norm(base_SC{j} - Value_data(i).SC{j});
                if diff_sc > tol
                    msg = sprintf('Agent %d 在 Task %d 的 SC 与 Agent 1 不一致 (差异: %.4f)', i, j, diff_sc);
                    error_log{end+1} = msg;
                    fprintf('  ❌ %s\n', msg);
                    is_valid = false;
                end
            end
        end
    end

    if is_valid
        fprintf('  ✅ 所有智能体达成全局共识\n');
    end
end

%% ========== 子函数：检查2A - 资源约束（OCF模式）==========
function [is_valid, error_log] = check_resource_constraints_OCF(Value_data, agents, Value_Params, tol)
    % 重叠联盟模式：检查单任务资源投入是否超过智能体上限
    is_valid = true;
    error_log = {};

    base_SC = Value_data(1).SC;
    N = Value_Params.N;
    M = Value_Params.M;
    K = Value_Params.K;

    for i = 1:N
        % 获取智能体i的资源上限
        if isfield(agents(i), 'resources')
            max_cap = agents(i).resources(:)';
            if length(max_cap) < K
                max_cap = [max_cap, zeros(1, K - length(max_cap))];
            else
                max_cap = max_cap(1:K);
            end
        else
            max_cap = zeros(1, K);
        end

        % 检查每个任务的资源投入
        for j = 1:M
            if ~isempty(base_SC{j}) && i <= size(base_SC{j}, 1)
                current_invested = base_SC{j}(i, 1:K);
                diff_vec = current_invested - max_cap;

                if any(diff_vec > tol)
                    msg = sprintf('Agent %d 在 Task %d 资源越界: 投入 %s > 上限 %s', ...
                        i, j, mat2str(current_invested, 2), mat2str(max_cap, 2));
                    error_log{end+1} = msg;
                    fprintf('  ❌ %s\n', msg);
                    is_valid = false;
                end
            end
        end
    end

    if is_valid
        fprintf('  ✅ 所有资源分配满足OCF约束（单任务不越界）\n');
    end
end

%% ========== 子函数：检查2B - 资源约束（Non-OCF模式）==========
function [is_valid, error_log] = check_resource_constraints_NonOCF(Value_data, agents, Value_Params, tol)
    % 非重叠联盟模式：检查所有任务的资源总和是否超过智能体上限
    is_valid = true;
    error_log = {};

    base_SC = Value_data(1).SC;
    N = Value_Params.N;
    M = Value_Params.M;
    K = Value_Params.K;

    for i = 1:N
        % 获取智能体i的资源上限
        if isfield(agents(i), 'resources')
            max_cap = agents(i).resources(:)';
            if length(max_cap) < K
                max_cap = [max_cap, zeros(1, K - length(max_cap))];
            else
                max_cap = max_cap(1:K);
            end
        else
            max_cap = zeros(1, K);
        end

        % 累加所有任务的资源投入
        total_invested = zeros(1, K);
        for j = 1:M
            if ~isempty(base_SC{j}) && i <= size(base_SC{j}, 1)
                total_invested = total_invested + base_SC{j}(i, 1:K);
            end
        end

        % 检查总投入是否超过上限
        diff_vec = total_invested - max_cap;
        if any(diff_vec > tol)
            msg = sprintf('Agent %d 总资源越界: 总投入 %s > 上限 %s', ...
                i, mat2str(total_invested, 2), mat2str(max_cap, 2));
            error_log{end+1} = msg;
            fprintf('  ❌ %s\n', msg);
            is_valid = false;
        end
    end

    if is_valid
        fprintf('  ✅ 所有资源分配满足Non-OCF约束（总和不越界）\n');
    end
end

%% ========== 子函数：检查3 - 结构对应关系 ==========
function [is_valid, error_log] = check_structure_mapping(Value_data, Value_Params, tol)
    % 检查coalitionstru与SC的双向映射关系
    is_valid = true;
    error_log = {};

    base_SC = Value_data(1).SC;
    base_stru = Value_data(1).coalitionstru;
    M = Value_Params.M;

    for j = 1:M
        if isempty(base_SC{j})
            continue;
        end

        % 从SC中找出所有资源非零的智能体
        active_agents_in_SC = find(any(base_SC{j} > tol, 2));

        % 从coalitionstru中找出所有成员
        members_in_stru = base_stru(j, :);
        members_in_stru = members_in_stru(members_in_stru > 0);

        % 检查SC中有资源的智能体是否都在coalitionstru中
        for idx = 1:length(active_agents_in_SC)
            aid = active_agents_in_SC(idx);
            if ~ismember(aid, members_in_stru)
                msg = sprintf('Task %d: Agent %d 在 SC 中有资源投入，但不在 coalitionstru 中', j, aid);
                error_log{end+1} = msg;
                fprintf('  ❌ %s\n', msg);
                is_valid = false;
            end
        end

        % 检查coalitionstru中的成员是否都在SC中有资源
        for idx = 1:length(members_in_stru)
            aid = members_in_stru(idx);
            if aid <= size(base_SC{j}, 1)
                resource_sum = sum(abs(base_SC{j}(aid, :)));
                if resource_sum < tol
                    msg = sprintf('Task %d: Agent %d 在 coalitionstru 中，但在 SC 中无资源投入', j, aid);
                    error_log{end+1} = msg;
                    fprintf('  ⚠️  %s\n', msg);
                    % 这可能是警告而非错误，取决于业务逻辑
                end
            end
        end
    end

    if is_valid
        fprintf('  ✅ coalitionstru 与 SC 的映射关系正确\n');
    end
end

%% ========== 子函数：检查4 - 自洽性 ==========
function [is_valid, error_log] = check_self_consistency(Value_data, Value_Params, tol)
    % 检查每个智能体的resources_matrix与SC的一致性
    is_valid = true;
    error_log = {};

    N = Value_Params.N;
    M = Value_Params.M;
    K = Value_Params.K;

    for i = 1:N
        my_R = Value_data(i).resources_matrix;
        my_SC = Value_data(i).SC;

        for j = 1:M
            % 提取个体矩阵中的资源记录
            res_personal = my_R(j, :);

            % 提取SC中的资源记录
            if isempty(my_SC{j})
                res_global = zeros(1, K);
            else
                if i <= size(my_SC{j}, 1)
                    res_global = my_SC{j}(i, :);
                else
                    res_global = zeros(1, K);
                end
            end

            % 比较（维度对齐）
            len = min(length(res_personal), length(res_global));
            diff_res = norm(res_personal(1:len) - res_global(1:len));

            if diff_res > tol
                msg = sprintf('Agent %d 在 Task %d 的个体矩阵与 SC 不一致: 个体 %s != SC %s', ...
                    i, j, mat2str(res_personal(1:len), 2), mat2str(res_global(1:len), 2));
                error_log{end+1} = msg;
                fprintf('  ❌ %s\n', msg);
                is_valid = false;
            end
        end
    end

    if is_valid
        fprintf('  ✅ 所有智能体的个体矩阵与 SC 保持一致\n');
    end
end

%% ========== 子函数：检查5 - 能量可行性 ==========
function [is_valid, error_log] = check_energy_feasibility(Value_data, agents, tasks, Value_Params, tol)
    % 检查每个智能体的能量约束是否满足
    is_valid = true;
    error_log = {};

    N = Value_Params.N;
    M = Value_Params.M;
    K = Value_Params.K;
    SC = Value_data(1).SC;

    for i = 1:N
        % 提取该智能体的资源分配矩阵
       R_agent = OCFUtils.get_agent_resource_matrix(SC, i, Value_Params);

        % 找出参与的任务
        my_tasks = OCFUtils.get_agent_tasks_fast(SC, i, tol);

        if isempty(my_tasks)
            continue;  % 没有参与任何任务，跳过
        end

        % 按优先级排序任务
        ordered_tasks = OCFUtils.sort_tasks_by_priority(my_tasks, tasks);

        % 计算总能量消耗
        try
            [t_fly, t_wait, t_exec] = WorldSim.calc_with_global_sync(...
                i, ordered_tasks, agents, tasks, Value_Params, SC, tol);

            % 计算总能量
            alpha_fly = agents(i).fuel;
            alpha_wait = agents(i).wait_fuel;
            beta = agents(i).beta;
            total_energy = alpha_fly * t_fly + alpha_wait * t_wait + beta * t_exec;

            % 检查能量是否足够
            if total_energy > agents(i).Emax + tol
                msg = sprintf('Agent %d 能量不足: 需要 %.2f > 拥有 %.2f', ...
                    i, total_energy, agents(i).Emax);
                error_log{end+1} = msg;
                fprintf('  ❌ %s\n', msg);
                is_valid = false;
            end
        catch ME
            msg = sprintf('Agent %d 能量计算失败: %s', i, ME.message);
            error_log{end+1} = msg;
            fprintf('  ❌ %s\n', msg);
            is_valid = false;
        end
    end

    if is_valid
        fprintf('  ✅ 所有智能体的能量约束满足\n');
    end
end
