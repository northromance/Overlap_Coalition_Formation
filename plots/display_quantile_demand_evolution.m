function display_quantile_demand_evolution(history_data, tasks, Value_Params, agent_id, task_id)
% 显示分位数需求演化分析（针对指定智能体和任务）
% 输入：
%   history_data - 历史数据
%   tasks - 任务数组
%   Value_Params - 参数结构体
%   agent_id - 要分析的智能体ID
%   task_id - 要分析的任务ID

K = Value_Params.K;
num_rounds = Value_Params.num_rounds;
num_task_types = Value_Params.task_type;

fprintf('\n========================================\n');
fprintf('  分位数需求演化分析（按智能体-任务）\n');
fprintf('========================================\n\n');

% 提取该任务的真实需求
actual_demand = tasks(task_id).resource_demand;

% 打印基本信息
fprintf('【任务 T%d 信息】\n', task_id);
fprintf('  真实类型: %d\n', tasks(task_id).type);
fprintf('  真实价值: %d\n', tasks(task_id).value);
fprintf('  真实需求: ');
fprintf('[%d, %d, %d, %d, %d, %d]\n\n', actual_demand);

fprintf('【智能体 A%d 对任务 T%d 的需求演化】\n', agent_id, task_id);
fprintf('置信水平: %.2f\n\n', Value_Params.resource_confidence);

% 提取所有轮次的数据
quantile_demand_evolution = zeros(num_rounds, K);
expected_demand_evolution = zeros(num_rounds, K);
belief_evolution = zeros(num_rounds, num_task_types);

for r = 1:num_rounds
    quantile_demand_evolution(r, :) = history_data.rounds(r).agents(agent_id).quantile_demand(task_id, :);
    belief_evolution(r, :) = history_data.rounds(r).agents(agent_id).belief(task_id, :);
    expected_demand_evolution(r, :) = belief_evolution(r, :) * Value_Params.task_type_demands;
end

% 添加信念显示列
fprintf('轮次 | 信念[类型1] | 信念[类型2] | 信念[类型3] | 最大信念 | ');
for k = 1:K
    fprintf('Res%d-期望 | Res%d-分位 | ', k, k);
end
fprintf('\n');
fprintf('-----|-----------|-----------|-----------|---------|');
for k = 1:K
    fprintf('---------|---------|');
end
fprintf('\n');

% 打印数据（每5轮打印一次，节省空间）
for r = 1:1:num_rounds
    fprintf('%4d | ', r);
    % 打印信念
    fprintf('   %7.4f | ', belief_evolution(r, 1));
    fprintf('   %7.4f | ', belief_evolution(r, 2));
    fprintf('   %7.4f | ', belief_evolution(r, 3));
    fprintf(' %7.4f | ', max(belief_evolution(r, :)));
    % 打印需求
    for k = 1:K
        fprintf('  %6.2f | ', expected_demand_evolution(r, k));
        fprintf('   %4d | ', quantile_demand_evolution(r, k));
    end
    fprintf('\n');
end

% 打印最后一轮
if mod(num_rounds, 5) ~= 0
    r = num_rounds;
    fprintf('%4d | ', r);
    % 打印信念
    fprintf('   %7.4f | ', belief_evolution(r, 1));
    fprintf('   %7.4f | ', belief_evolution(r, 2));
    fprintf('   %7.4f | ', belief_evolution(r, 3));
    fprintf(' %7.4f | ', max(belief_evolution(r, :)));
    % 打印需求
    for k = 1:K
        fprintf('  %6.2f | ', expected_demand_evolution(r, k));
        fprintf('   %4d | ', quantile_demand_evolution(r, k));
    end
    fprintf('\n');
end

% 打印对比摘要
fprintf('\n【最终需求对比摘要】\n');
fprintf('资源类型 | 真实需求 | 期望值法 | 分位数法 | 期望偏差 | 分位偏差\n');
fprintf('---------|---------|---------|---------|---------|--------\n');
for k = 1:K
    true_val = actual_demand(k);
    exp_val = expected_demand_evolution(end, k);
    quant_val = quantile_demand_evolution(end, k);
    exp_diff = exp_val - true_val;
    quant_diff = quant_val - true_val;
    fprintf('  Res%d   |    %2d   |  %6.2f |    %2d   |  %+6.2f |   %+3d\n', ...
            k, true_val, exp_val, quant_val, exp_diff, quant_diff);
end

fprintf('\n========================================\n\n');
end
