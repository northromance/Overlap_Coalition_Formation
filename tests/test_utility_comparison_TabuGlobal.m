% test_utility_comparison_TabuGlobal.m
% 测试线性效用 vs 对数效用在 SA_TabuEnhanced_Global 算法中的影响
% 专注分析：为什么对数效用导致任务2和任务5没有被分配资源

clear; clc;
fprintf('========================================\n');
fprintf('效用公式对比测试 - SA_TabuEnhanced_Global\n');
fprintf('========================================\n\n');

% 加载最新的结果文件
script_dir = fileparts(mfilename('fullpath'));
project_root = fileparts(script_dir);
result_file = fullfile(project_root, 'results', 'comparison_N6_M10_TabuGlobal_20260307_194451.mat');
load(result_file);

fprintf('场景信息:\n');
fprintf('  智能体数: %d\n', length(agents));
fprintf('  任务数: %d\n', length(tasks));
fprintf('  轮数: %d\n\n', Value_Params.num_rounds);

%% 1. 分析任务2和任务5的基本信息
fprintf('===== 被忽略任务的基本信息 =====\n\n');

ignored_tasks = [2, 5];
for i = 1:length(ignored_tasks)
    j = ignored_tasks(i);
    fprintf('任务%d:\n', j);
    fprintf('  优先级: %d / 10\n', tasks(j).priority);
    fprintf('  价值: %d\n', tasks(j).value);
    fprintf('  类型: %d\n', tasks(j).type);
    fprintf('  需求: [%s]\n', num2str(tasks(j).resource_demand));
    fprintf('  位置: (%.1f, %.1f)\n', tasks(j).x, tasks(j).y);

    % 计算距离最近的智能体
    min_dist = inf;
    nearest_agent = 0;
    for k = 1:length(agents)
        dist = sqrt((agents(k).x - tasks(j).x)^2 + (agents(k).y - tasks(j).y)^2);
        if dist < min_dist
            min_dist = dist;
            nearest_agent = k;
        end
    end
    fprintf('  最近智能体: 智能体%d, 距离=%.1f\n', nearest_agent, min_dist);
    fprintf('  该智能体资源: [%s]\n\n', num2str(agents(nearest_agent).resources'));
end

%% 2. 模拟效用计算 - 线性 vs 对数
fprintf('===== 效用计算对比（单个智能体参与任务2）=====\n\n');

% 选择任务2和最近的智能体3
task_id = 2;
agent_id = 3;

fprintf('假设智能体%d参与任务%d:\n\n', agent_id, task_id);

% 基本参数
task_value = tasks(task_id).value;
task_demand = tasks(task_id).resource_demand;
agent_resources = agents(agent_id).resources;
task_priority = tasks(task_id).priority;

% 计算距离和飞行成本
dist = sqrt((agents(agent_id).x - tasks(task_id).x)^2 + ...
            (agents(agent_id).y - tasks(task_id).y)^2);
t_fly = dist / agents(agent_id).vel;
fly_cost = t_fly * agents(agent_id).fuel;

fprintf('【成本分析】\n');
fprintf('  距离: %.1f 单位\n', dist);
fprintf('  飞行时间: %.1f\n', t_fly);
fprintf('  飞行成本: %.2f\n', fly_cost);

% 估算执行成本
exec_time = max(tasks(task_id).duration_by_resource);
exec_cost = exec_time * agents(agent_id).beta;
fprintf('  执行时间: %.1f\n', exec_time);
fprintf('  执行成本: %.2f\n', exec_cost);

total_cost = fly_cost + exec_cost;
fprintf('  总成本: %.2f\n\n', total_cost);

% 计算完成度（假设单个智能体）
completion_ratio = 0;
num_required = sum(task_demand > 0);
for k = 1:length(task_demand)
    if task_demand(k) > 0
        contrib = min(agent_resources(k) / task_demand(k), 1.0);
        completion_ratio = completion_ratio + contrib;
    end
end
completion_degree = completion_ratio / num_required;

fprintf('【收益分析】\n');
fprintf('  任务价值: %d\n', task_value);
fprintf('  完成度: %.3f\n', completion_degree);
fprintf('  预期收益: %.2f\n\n', task_value * completion_degree);

% 计算净收益
net_revenue = task_value * completion_degree - total_cost;
fprintf('【净收益】\n');
fprintf('  净收益 = 收益 - 成本 = %.2f\n\n', net_revenue);

%% 3. 对比两种效用公式
fprintf('===== 效用公式对比 =====\n\n');

% 线性效用（旧公式）
utility_linear = net_revenue;
fprintf('【线性效用公式】（注释掉的旧版）\n');
fprintf('  U = Revenue - Cost\n');
fprintf('  U = %.2f\n\n', utility_linear);

% 对数效用（新公式）
rho_m = task_priority;  % 优先级权重
inner_val = rho_m * net_revenue;
tol = 1e-9;
utility_log = log(1 + max(inner_val, -1 + tol));
fprintf('【对数效用公式】（当前使用）\n');
fprintf('  U_m = log(1 + rho_m * (V*D - Cost))\n');
fprintf('  rho_m = %d (优先级)\n', rho_m);
fprintf('  inner_val = %d * %.2f = %.2f\n', rho_m, net_revenue, inner_val);
fprintf('  U_m = log(1 + %.2f) = %.4f\n\n', inner_val, utility_log);

fprintf('【效用压缩比】\n');
compression_ratio = utility_linear / utility_log;
fprintf('  线性效用 / 对数效用 = %.2f / %.4f = %.1f 倍\n\n', ...
    utility_linear, utility_log, compression_ratio);

%% 4. 对比任务2 vs 任务9（相同需求，不同位置）
fprintf('===== 任务2 vs 任务9 对比（相同价值和需求）=====\n\n');

task2_id = 2;
task9_id = 9;

% 任务9被选中，参与的智能体
SC_final = results.alg1.Value_data(1).SC;
participants_9 = find(sum(SC_final{task9_id}, 2) > 0);
fprintf('任务9被选中，参与智能体: %s\n', mat2str(participants_9'));

% 选择距离任务9最近的智能体2
agent9_id = 2;
dist9 = sqrt((agents(agent9_id).x - tasks(task9_id).x)^2 + ...
             (agents(agent9_id).y - tasks(task9_id).y)^2);
t_fly9 = dist9 / agents(agent9_id).vel;
fly_cost9 = t_fly9 * agents(agent9_id).fuel;
exec_cost9 = max(tasks(task9_id).duration_by_resource) * agents(agent9_id).beta;
total_cost9 = fly_cost9 + exec_cost9;

fprintf('\n任务9（优先级%d，被选中）:\n', tasks(task9_id).priority);
fprintf('  智能体%d参与\n', agent9_id);
fprintf('  距离: %.1f vs 任务2的%.1f\n', dist9, dist);
fprintf('  飞行成本: %.2f vs 任务2的%.2f\n', fly_cost9, fly_cost);
fprintf('  总成本: %.2f vs 任务2的%.2f\n', total_cost9, total_cost);
fprintf('  成本差异: %.2f（任务2多花%.1f%%）\n', total_cost - total_cost9, ...
    (total_cost/total_cost9-1)*100);

% 计算净收益（假设相同完成度）
net_revenue9 = task_value * completion_degree - total_cost9;
fprintf('\n  净收益对比:\n');
fprintf('    任务9: %.2f\n', net_revenue9);
fprintf('    任务2: %.2f\n', net_revenue);
fprintf('    差异: %.2f\n', net_revenue9 - net_revenue);

% 对数效用对比
rho9 = tasks(task9_id).priority;
rho2 = tasks(task2_id).priority;
inner_val9 = rho9 * net_revenue9;
inner_val2 = rho2 * net_revenue;
utility_log9 = log(1 + max(inner_val9, -1 + tol));
utility_log2 = log(1 + max(inner_val2, -1 + tol));

fprintf('\n  对数效用对比:\n');
fprintf('    任务9: rho=%d, inner=%.2f, U=%.4f\n', rho9, inner_val9, utility_log9);
fprintf('    任务2: rho=%d, inner=%.2f, U=%.4f\n', rho2, inner_val2, utility_log2);
fprintf('    效用差异: %.4f（任务9高%.1f%%）\n', ...
    utility_log9 - utility_log2, (utility_log9/utility_log2-1)*100);

%% 5. 分析算法决策机制
fprintf('\n\n===== 算法决策机制分析 =====\n\n');

fprintf('SA_TabuEnhanced_Global的核心机制:\n\n');

fprintf('1. 初始构造阶段（Soft Greedy）:\n');
fprintf('   - 温度: T_init_construction = %.2f （低温→贪婪）\n', Value_Params.T_init_construction);
fprintf('   - 基于资源缺口gap计算任务选择概率\n');
fprintf('   - 优先选择"高效"任务（低成本+高效用）\n');
fprintf('   → 任务9因为距离近、成本低，概率高\n');
fprintf('   → 任务2因为距离远、成本高，概率低\n\n');

fprintf('2. 主优化循环（Metropolis准则）:\n');
fprintf('   - 计算: delta_E = GSU_candidate - GSU_current\n');
fprintf('   - GSU = Σ(所有智能体的对数效用)\n');
fprintf('   - 接受条件: delta_E > 0 或 exp(delta_E/T) > rand()\n\n');

fprintf('3. 对数效用的影响:\n');
fprintf('   - 高价值任务的吸引力被压缩\n');
fprintf('   - 低优先级任务的效用被过度惩罚\n');
fprintf('   - 成本差异被放大（对数函数在0附近斜率大）\n\n');

fprintf('4. 为什么任务2被忽略:\n');
fprintf('   ① 初始构造阶段，因为成本高被跳过\n');
fprintf('   ② 优化循环中，加入任务2的delta_E很小\n');
fprintf('      - 对数压缩：净收益%.2f → 效用%.4f\n', net_revenue, utility_log2);
fprintf('      - 优先级低：rho=%d，进一步压制效用\n', rho2);
fprintf('   ③ 温度衰减后，探索性不足，无法跳出局部最优\n\n');

%% 6. 量化分析：GSU差值
fprintf('===== GSU差值模拟 =====\n\n');

fprintf('假设系统当前状态已有任务9，考虑是否加入任务2:\n\n');

% 当前GSU（只有任务9）
current_GSU_approx = length(agents) * utility_log9;  % 近似，假设其他任务效用为0
fprintf('当前GSU（近似）: %.2f × %d = %.2f\n', utility_log9, length(agents), current_GSU_approx);

% 候选GSU（加入任务2）
% 假设智能体3从任务9转移到任务2
candidate_GSU_approx = (length(agents) - 1) * utility_log9 + utility_log2;
fprintf('候选GSU（近似）: %.2f × %d + %.2f = %.2f\n', ...
    utility_log9, length(agents)-1, utility_log2, candidate_GSU_approx);

delta_GSU = candidate_GSU_approx - current_GSU_approx;
fprintf('\ndelta_GSU = %.2f - %.2f = %.4f\n', candidate_GSU_approx, current_GSU_approx, delta_GSU);

if delta_GSU > 0
    fprintf('结论: delta_GSU > 0，应该接受\n');
else
    fprintf('结论: delta_GSU < 0，拒绝接受\n');
    fprintf('      → 这就是任务2被忽略的原因！\n');
end

fprintf('\n问题根源:\n');
fprintf('  对数效用将任务2的效用从 %.2f 压缩到 %.4f\n', utility_linear, utility_log2);
fprintf('  而任务9的效用从 %.2f 压缩到 %.4f\n', task_value*completion_degree-total_cost9, utility_log9);
fprintf('  相对效用差距从 %.1f%% 扩大到 %.1f%%\n', ...
    (net_revenue9/net_revenue-1)*100, (utility_log9/utility_log2-1)*100);

%% 7. 结论与建议
fprintf('\n\n========================================\n');
fprintf('结论与建议\n');
fprintf('========================================\n\n');

fprintf('【核心问题】\n');
fprintf('  对数效用公式的3个副作用:\n');
fprintf('  1. 值域压缩：高价值任务吸引力降低\n');
fprintf('  2. 优先级权重放大：低优先级任务被过度惩罚\n');
fprintf('  3. 成本差异敏感：小的成本差异导致大的效用差异\n\n');

fprintf('【为什么旧公式能分配资源】\n');
fprintf('  线性效用: U = %.2f（任务2）\n', utility_linear);
fprintf('  - 正效用，有吸引力\n');
fprintf('  - 成本差异影响小（线性尺度）\n');
fprintf('  - 优先级不影响效用值（只影响任务排序）\n\n');

fprintf('【为什么新公式不分配资源】\n');
fprintf('  对数效用: U = %.4f（任务2）\n', utility_log2);
fprintf('  - 效用被压缩%.0f倍\n', compression_ratio);
fprintf('  - 优先级%d导致效用进一步降低\n', rho2);
fprintf('  - 相比任务9的效用%.4f，竞争力不足\n\n', utility_log9);

fprintf('【建议】\n');
fprintf('  如果希望提高任务覆盖率，可以尝试:\n');
fprintf('  1. 回退到线性效用公式（最直接）\n');
fprintf('  2. 调整参数:\n');
fprintf('     - 降低 agent_fuel（减少飞行成本惩罚）\n');
fprintf('     - 提高 T_init_construction（增加初始探索）\n');
fprintf('     - 归一化 rho_m（减少优先级权重差距）\n');
fprintf('  3. 改进算法:\n');
fprintf('     - 添加任务覆盖率约束\n');
fprintf('     - 多阶段资源分配\n\n');

fprintf('测试完成！\n');
