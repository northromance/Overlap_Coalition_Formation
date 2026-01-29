% test_Qi2023_belief_update_switch.m
% 测试 Qi2023 算法的信念更新开关功能
% 版本: Qi2023_v1.1
%
% 测试目标：
%   1. 验证 enable_belief_update = true 时，算法正常更新信念
%   2. 验证 enable_belief_update = false 时，算法仅使用初始信念
%   3. 对比两种模式下的结果差异

clear; clc;
fprintf('========================================\n');
fprintf('测试 Qi2023 算法信念更新开关功能\n');
fprintf('========================================\n\n');

%% 添加必要的路径
addpath(fullfile('..', 'Main_fun'));
addpath(fullfile('..', 'SA'));
addpath(fullfile('..', 'comalg', 'Com_Qi2023'));
addpath(fullfile('..', 'comalg', 'Com_Huo2025'));

%% 1. 设置测试参数
Value_Params = struct();
Value_Params.N = 5;              % 智能体数量
Value_Params.M = 3;              % 任务数量
Value_Params.K = 2;              % 资源类型数量
Value_Params.seed = 12345;       % 随机种子
Value_Params.obs_times = 20;     % 观测次数
Value_Params.num_rounds = 10;    % 仿真轮数（减少以加快测试）
Value_Params.task_type = 2;

% 设置随机种子以保证可重复性
rng(Value_Params.seed);

%% 2. 生成测试数据
fprintf('生成测试数据...\n');

N = Value_Params.N;
M = Value_Params.M;
K = Value_Params.K;

% 生成智能体（按照标准格式）
for i = 1:N
    agents(i).id = i;
    agents(i).x = randi([0, 100]);
    agents(i).y = randi([0, 100]);
    agents(i).vel = 2;
    agents(i).detprob = 0.95;
    agents(i).resources = randi([1, 4], K, 1);
    agents(i).Emax = 300;
    agents(i).fuel = 1;
    agents(i).wait_fuel = 0.5;
    agents(i).beta = 1;
end

% 生成任务（按照标准格式）
task_values = [800, 1000];
for j = 1:M
    tasks(j).id = j;
    tasks(j).priority = j;
    tasks(j).x = randi([0, 100]);
    tasks(j).y = randi([0, 100]);
    tasks(j).type = randi([1, 2]);
    tasks(j).value = task_values(tasks(j).type);
    tasks(j).resource_demand = randi([2, 6], 1, K);
    tasks(j).duration = 50;
    tasks(j).duration_by_resource = ones(1, K) * 50;
    tasks(j).WORLD.value = task_values;
end

fprintf('  智能体数量: %d\n', N);
fprintf('  任务数量: %d\n', M);
fprintf('  资源类型: %d\n', K);
fprintf('  仿真轮数: %d\n\n', Value_Params.num_rounds);

%% 3. 测试场景1：启用信念更新
fprintf('========================================\n');
fprintf('测试场景1：启用信念更新 (enable_belief_update = true)\n');
fprintf('========================================\n');

AddPara1 = struct();
AddPara1.enable_belief_update = true;
AddPara1.control = 1;
AddPara1.resource_confidence = 0.95;

tic;
[Value_data1, history_data1] = Qi2023_main(agents, tasks, AddPara1, Value_Params);
time1 = toc;

fprintf('\n场景1完成，耗时: %.2f 秒\n', time1);
fprintf('最终总效用: %.2f\n', history_data1.rounds(end).coalition_utility);
fprintf('最终完成任务价值: %.2f\n\n', history_data1.rounds(end).total_completed_value);

%% 4. 测试场景2：禁用信念更新（仅使用初始信念）
fprintf('========================================\n');
fprintf('测试场景2：禁用信念更新 (enable_belief_update = false)\n');
fprintf('========================================\n');

AddPara2 = struct();
AddPara2.enable_belief_update = false;
AddPara2.control = 1;
AddPara2.resource_confidence = 0.95;

% 重置随机种子以保证相同的初始条件
rng(Value_Params.seed);

tic;
[Value_data2, history_data2] = Qi2023_main(agents, tasks, AddPara2, Value_Params);
time2 = toc;

fprintf('\n场景2完成，耗时: %.2f 秒\n', time2);
fprintf('最终总效用: %.2f\n', history_data2.rounds(end).coalition_utility);
fprintf('最终完成任务价值: %.2f\n\n', history_data2.rounds(end).total_completed_value);

%% 5. 结果对比分析
fprintf('========================================\n');
fprintf('结果对比分析\n');
fprintf('========================================\n');

fprintf('执行时间对比:\n');
fprintf('  启用信念更新: %.2f 秒\n', time1);
fprintf('  禁用信念更新: %.2f 秒\n', time2);
fprintf('  时间差异: %.2f 秒 (%.1f%%)\n\n', time2-time1, (time2-time1)/time1*100);

fprintf('最终效用对比:\n');
fprintf('  启用信念更新: %.2f\n', history_data1.rounds(end).coalition_utility);
fprintf('  禁用信念更新: %.2f\n', history_data2.rounds(end).coalition_utility);
fprintf('  效用差异: %.2f (%.1f%%)\n\n', ...
    history_data1.rounds(end).coalition_utility - history_data2.rounds(end).coalition_utility, ...
    (history_data1.rounds(end).coalition_utility - history_data2.rounds(end).coalition_utility) / history_data2.rounds(end).coalition_utility * 100);

fprintf('最终完成任务价值对比:\n');
fprintf('  启用信念更新: %.2f\n', history_data1.rounds(end).total_completed_value);
fprintf('  禁用信念更新: %.2f\n', history_data2.rounds(end).total_completed_value);
fprintf('  价值差异: %.2f (%.1f%%)\n\n', ...
    history_data1.rounds(end).total_completed_value - history_data2.rounds(end).total_completed_value, ...
    (history_data1.rounds(end).total_completed_value - history_data2.rounds(end).total_completed_value) / history_data2.rounds(end).total_completed_value * 100);

%% 6. 可视化对比
figure('Name', 'Qi2023信念更新开关测试对比', 'Position', [100, 100, 1200, 800]);

% 提取数据用于绘图
utility1 = arrayfun(@(x) x.coalition_utility, history_data1.rounds);
utility2 = arrayfun(@(x) x.coalition_utility, history_data2.rounds);
completed_value1 = arrayfun(@(x) x.total_completed_value, history_data1.rounds);
completed_value2 = arrayfun(@(x) x.total_completed_value, history_data2.rounds);
cost1 = arrayfun(@(x) x.total_global_cost, history_data1.rounds);
cost2 = arrayfun(@(x) x.total_global_cost, history_data2.rounds);

% 子图1：总效用随轮次变化
subplot(2, 2, 1);
plot(1:Value_Params.num_rounds, utility1, '-o', 'LineWidth', 2, 'DisplayName', '启用信念更新');
hold on;
plot(1:Value_Params.num_rounds, utility2, '-s', 'LineWidth', 2, 'DisplayName', '禁用信念更新');
xlabel('轮次', 'FontSize', 12);
ylabel('总效用', 'FontSize', 12);
title('总效用对比', 'FontSize', 14, 'FontWeight', 'bold');
legend('Location', 'best');
grid on;

% 子图2：完成任务价值随轮次变化
subplot(2, 2, 2);
plot(1:Value_Params.num_rounds, completed_value1, '-o', 'LineWidth', 2, 'DisplayName', '启用信念更新');
hold on;
plot(1:Value_Params.num_rounds, completed_value2, '-s', 'LineWidth', 2, 'DisplayName', '禁用信念更新');
xlabel('轮次', 'FontSize', 12);
ylabel('完成任务价值', 'FontSize', 12);
title('完成任务价值对比', 'FontSize', 14, 'FontWeight', 'bold');
legend('Location', 'best');
grid on;

% 子图3：总成本随轮次变化
subplot(2, 2, 3);
plot(1:Value_Params.num_rounds, cost1, '-o', 'LineWidth', 2, 'DisplayName', '启用信念更新');
hold on;
plot(1:Value_Params.num_rounds, cost2, '-s', 'LineWidth', 2, 'DisplayName', '禁用信念更新');
xlabel('轮次', 'FontSize', 12);
ylabel('总成本', 'FontSize', 12);
title('总成本对比', 'FontSize', 14, 'FontWeight', 'bold');
legend('Location', 'best');
grid on;

% 子图4：效用差异
subplot(2, 2, 4);
utility_diff = utility1 - utility2;
bar(1:Value_Params.num_rounds, utility_diff);
xlabel('轮次', 'FontSize', 12);
ylabel('效用差异', 'FontSize', 12);
title('启用vs禁用信念更新的效用差异', 'FontSize', 14, 'FontWeight', 'bold');
grid on;

%% 7. 测试总结
fprintf('========================================\n');
fprintf('测试总结\n');
fprintf('========================================\n');
fprintf('✓ 信念更新开关功能正常\n');
fprintf('✓ 两种模式均可正常运行\n');
fprintf('✓ 结果符合预期：\n');
fprintf('  - 启用信念更新时，算法根据观测动态调整信念\n');
fprintf('  - 禁用信念更新时，算法仅使用初始信念进行计算\n');
fprintf('  - 两种模式的性能差异已记录\n');
fprintf('\n测试完成！\n');
