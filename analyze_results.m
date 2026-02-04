% 分析SA算法与Qi算法效用差异的脚本
clear; clc;

% 加载最近的比较结果
result_files = dir('results/comparison_N6_M10_SA+Qi+SA*.mat');
if isempty(result_files)
    error('未找到比较结果文件');
end

% 按时间排序，选择最新的
[~, idx] = max([result_files.datenum]);
latest_file = fullfile(result_files(idx).folder, result_files(idx).name);

fprintf('====================================\n');
fprintf('正在分析: %s\n', result_files(idx).name);
fprintf('====================================\n\n');

% 加载数据
data = load(latest_file);

% 提取算法名称
alg_names = {data.enabled_algorithms{:}};
fprintf('包含的算法:\n');
for i = 1:length(alg_names)
    fprintf('  alg%d: %s\n', i, alg_names{i}.name);
end
fprintf('\n');

% 找到SA和Qi算法的索引
sa_idx = 0;
qi_idx = 0;
for i = 1:length(alg_names)
    if contains(alg_names{i}.name, 'SA_Value') && ~contains(alg_names{i}.name, 'Adaptive')
        sa_idx = i;
    elseif contains(alg_names{i}.name, 'Qi2023')
        qi_idx = i;
    end
end

if sa_idx == 0 || qi_idx == 0
    error('未找到SA或Qi算法的结果');
end

% 提取结果
sa_field = sprintf('alg%d', sa_idx);
qi_field = sprintf('alg%d', qi_idx);

sa_result = data.results.(sa_field);
qi_result = data.results.(qi_field);
sa_stats = data.comparison_stats.(sa_field);
qi_stats = data.comparison_stats.(qi_field);

fprintf('【算法对比总览】\n');
fprintf('========================================\n');
fprintf('算法名称: %s vs %s\n', alg_names{sa_idx}.name, alg_names{qi_idx}.name);
fprintf('----------------------------------------\n');
fprintf('指标                 | SA算法      | Qi算法      | 差异        | 差异%%\n');
fprintf('---------------------|-------------|-------------|-------------|---------\n');
fprintf('总效用               | %10.2f  | %10.2f  | %+10.2f  | %+6.1f%%\n', ...
    sa_stats.total_utility, qi_stats.total_utility, ...
    sa_stats.total_utility - qi_stats.total_utility, ...
    100 * (sa_stats.total_utility / qi_stats.total_utility - 1));
fprintf('总成本               | %10.2f  | %10.2f  | %+10.2f  | %+6.1f%%\n', ...
    sa_stats.total_cost, qi_stats.total_cost, ...
    sa_stats.total_cost - qi_stats.total_cost, ...
    100 * (sa_stats.total_cost / qi_stats.total_cost - 1));
fprintf('完成分数             | %10.2f  | %10.2f  | %+10.2f  | %+6.1f%%\n', ...
    sa_stats.total_completion_score, qi_stats.total_completion_score, ...
    sa_stats.total_completion_score - qi_stats.total_completion_score, ...
    100 * (sa_stats.total_completion_score / qi_stats.total_completion_score - 1));
fprintf('平均任务完成度       | %10.1f%% | %10.1f%% | %+10.1f%% |\n', ...
    100 * sa_stats.avg_task_completion, 100 * qi_stats.avg_task_completion, ...
    100 * (sa_stats.avg_task_completion - qi_stats.avg_task_completion));
fprintf('联盟数量             | %10.0f  | %10.0f  | %+10.0f  |\n', ...
    sa_stats.num_coalitions, qi_stats.num_coalitions, ...
    sa_stats.num_coalitions - qi_stats.num_coalitions);
fprintf('计算时间(s)          | %10.2f  | %10.2f  | %+10.2f  |\n', ...
    sa_stats.computation_time, qi_stats.computation_time, ...
    sa_stats.computation_time - qi_stats.computation_time);
fprintf('========================================\n\n');

% 关键发现
fprintf('【关键发现】\n');
fprintf('========================================\n');
utility_diff = sa_stats.total_utility - qi_stats.total_utility;
utility_diff_pct = 100 * (sa_stats.total_utility / qi_stats.total_utility - 1);

if utility_diff < 0
    fprintf('>>> SA算法效用比Qi算法低 %.2f (%.1f%%)\n\n', abs(utility_diff), abs(utility_diff_pct));
end

% 任务完成度对比
fprintf('【任务完成度详细对比】\n');
fprintf('----------------------------------------\n');
fprintf('任务 | SA完成度 | Qi完成度 | 差异\n');
fprintf('-----|----------|----------|----------\n');

M = length(sa_stats.task_completion_degrees);
for m = 1:M
    sa_comp = sa_stats.task_completion_degrees(m);
    qi_comp = qi_stats.task_completion_degrees(m);
    diff = sa_comp - qi_comp;

    marker = '';
    if abs(diff) >= 0.2
        if diff < 0
            marker = ' <<<';  % SA明显落后
        else
            marker = ' >>>';  % SA明显领先
        end
    end

    fprintf('%4d | %7.1f%% | %7.1f%% | %+8.1f%%%s\n', ...
        m, 100*sa_comp, 100*qi_comp, 100*diff, marker);
end
fprintf('----------------------------------------\n\n');

% 分析问题根源
fprintf('【问题根源分析】\n');
fprintf('========================================\n');

problem_count = 0;

% 1. 完成度问题
if sa_stats.avg_task_completion < qi_stats.avg_task_completion
    problem_count = problem_count + 1;
    fprintf('\n问题 %d: 任务完成度偏低\n', problem_count);
    fprintf('----------------------------------------\n');
    fprintf('  SA平均完成度: %.1f%%\n', 100 * sa_stats.avg_task_completion);
    fprintf('  Qi平均完成度: %.1f%%\n', 100 * qi_stats.avg_task_completion);
    fprintf('  差异: %.1f个百分点\n', 100 * (qi_stats.avg_task_completion - sa_stats.avg_task_completion));

    % 找出完成度差异大的任务
    comp_diff = sa_stats.task_completion_degrees - qi_stats.task_completion_degrees;
    [~, worst_idx] = sort(comp_diff);
    worst_tasks = worst_idx(1:min(3, M));

    fprintf('\n  最差的3个任务:\n');
    for i = 1:length(worst_tasks)
        m = worst_tasks(i);
        fprintf('    任务%d: SA=%.1f%%, Qi=%.1f%% (差%.1f%%)\n', ...
            m, 100*sa_stats.task_completion_degrees(m), ...
            100*qi_stats.task_completion_degrees(m), ...
            100*comp_diff(m));
    end

    fprintf('\n  可能原因:\n');
    fprintf('    a) 资源分配策略不当 - SA可能将资源分散到太多任务\n');
    fprintf('    b) 优先级处理不合理 - 未能优先完成高价值任务\n');
    fprintf('    c) 初始化问题 - Soft Greedy策略可能不如Qi的初始化\n');
    fprintf('    d) 概率计算差异 - SA的Boltzmann分布可能不够优化\n');
end

% 2. 联盟数量问题
if sa_stats.num_coalitions < qi_stats.num_coalitions
    problem_count = problem_count + 1;
    fprintf('\n问题 %d: 联盟数量偏少\n', problem_count);
    fprintf('----------------------------------------\n');
    fprintf('  SA联盟数: %d\n', sa_stats.num_coalitions);
    fprintf('  Qi联盟数: %d\n', qi_stats.num_coalitions);
    fprintf('  差异: %d个联盟\n', qi_stats.num_coalitions - sa_stats.num_coalitions);

    fprintf('\n  可能原因:\n');
    fprintf('    a) join_operation拒绝率过高\n');
    fprintf('    b) 可行性检测过于严格（特别是队友检查）\n');
    fprintf('    c) 温度下降过快，探索性不足\n');
    fprintf('    d) 能量/资源约束导致无法参与更多任务\n');
end

% 3. 成本问题
cost_diff_pct = 100 * (sa_stats.total_cost / qi_stats.total_cost - 1);
if abs(cost_diff_pct) < 5
    % 成本相近但效用差，说明问题不在成本
    problem_count = problem_count + 1;
    fprintf('\n问题 %d: 成本相近但效用偏低\n', problem_count);
    fprintf('----------------------------------------\n');
    fprintf('  SA成本: %.2f\n', sa_stats.total_cost);
    fprintf('  Qi成本: %.2f (差异: %.1f%%)\n', qi_stats.total_cost, cost_diff_pct);
    fprintf('\n  这说明问题主要在收益端，而非成本端:\n');
    fprintf('    a) 任务完成度不足（资源分配不够）\n');
    fprintf('    b) 高价值任务未被充分完成\n');
    fprintf('    c) 资源利用效率低\n');
end

fprintf('\n========================================\n\n');

% 深度分析：对比联盟结构
if isfield(sa_result, 'SC_global') && isfield(qi_result, 'SC_global')
    fprintf('【联盟结构深度分析】\n');
    fprintf('========================================\n');

    sa_SC = sa_result.SC_global;
    qi_SC = qi_result.SC_global;

    fprintf('任务 | SA成员 | Qi成员 | SA总资源 | Qi总资源 | SA完成 | Qi完成\n');
    fprintf('-----|--------|--------|----------|----------|--------|--------\n');

    for m = 1:M
        sa_members = sum(any(sa_SC{m} > 1e-9, 2));
        qi_members = sum(any(qi_SC{m} > 1e-9, 2));

        sa_total_res = sum(sa_SC{m}(:));
        qi_total_res = sum(qi_SC{m}(:));

        sa_comp = sa_stats.task_completion_degrees(m);
        qi_comp = qi_stats.task_completion_degrees(m);

        fprintf('%4d | %6d | %6d | %8.2f | %8.2f | %5.1f%% | %5.1f%%\n', ...
            m, sa_members, qi_members, sa_total_res, qi_total_res, ...
            100*sa_comp, 100*qi_comp);
    end

    fprintf('========================================\n\n');

    % 分析资源分配模式
    fprintf('【资源分配模式分析】\n');
    fprintf('----------------------------------------\n');

    % 找出SA分配资源少但Qi分配多的任务
    res_diff = zeros(1, M);
    for m = 1:M
        res_diff(m) = sum(qi_SC{m}(:)) - sum(sa_SC{m}(:));
    end

    [~, sorted_idx] = sort(res_diff, 'descend');
    fprintf('Qi比SA多分配资源的任务 (前5个):\n');
    for i = 1:min(5, M)
        m = sorted_idx(i);
        if res_diff(m) > 0.1
            fprintf('  任务%d: Qi多分配 %.2f 单位资源 (完成度: SA=%.1f%%, Qi=%.1f%%)\n', ...
                m, res_diff(m), 100*sa_stats.task_completion_degrees(m), ...
                100*qi_stats.task_completion_degrees(m));
        end
    end

    fprintf('\nSA比Qi多分配资源的任务:\n');
    [~, sorted_idx] = sort(res_diff, 'ascend');
    found_any = false;
    for i = 1:min(5, M)
        m = sorted_idx(i);
        if res_diff(m) < -0.1
            found_any = true;
            fprintf('  任务%d: SA多分配 %.2f 单位资源 (完成度: SA=%.1f%%, Qi=%.1f%%)\n', ...
                m, abs(res_diff(m)), 100*sa_stats.task_completion_degrees(m), ...
                100*qi_stats.task_completion_degrees(m));
        end
    end
    if ~found_any
        fprintf('  (无)\n');
    end

    fprintf('========================================\n\n');
end

% 总结建议
fprintf('【改进建议】\n');
fprintf('========================================\n');
fprintf('根据以上分析，建议从以下方面改进SA算法:\n\n');

fprintf('1. 调整概率计算公式 (SA_Select_probs.m)\n');
fprintf('   - 当前: score = (priority^2 * demand * supply) / distance\n');
fprintf('   - 对比Qi的偏好重力公式，考虑增加任务价值权重\n');
fprintf('   - 可能需要更强调高价值任务的优先级\n\n');

fprintf('2. 优化温度参数\n');
fprintf('   - 当前alpha=%.2f可能导致温度下降过快\n', data.Value_Params.alpha);
fprintf('   - 建议尝试更大的alpha（如0.7-0.8）以增加探索性\n');
fprintf('   - 或采用自适应温度调整策略\n\n');

fprintf('3. 改进初始化策略\n');
fprintf('   - Soft Greedy的T_init_construction=0.5可能过低\n');
fprintf('   - Qi算法保留跨轮联盟结构（热启动），SA每轮重启可能损失效率\n');
fprintf('   - 考虑在信念更新后保留部分联盟结构\n\n');

fprintf('4. 分析join_operation的拒绝原因\n');
fprintf('   - 如果大量操作因可行性检测被拒绝，考虑放宽约束\n');
fprintf('   - 队友检查可能过于保守，需要平衡\n\n');

fprintf('5. 考虑资源分配集中度\n');
fprintf('   - 分析SA是否过度分散资源到多个任务\n');
fprintf('   - 或者过度集中资源导致联盟数量少\n');
fprintf('   - 需要找到平衡点\n\n');

fprintf('========================================\n');
