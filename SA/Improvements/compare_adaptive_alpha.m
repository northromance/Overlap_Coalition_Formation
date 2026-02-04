% compare_adaptive_alpha.m - 对比原始 SA 和自适应温度 SA
%
% 用途：快速对比两种算法的温度调整策略和性能差异

clear; clc; close all;

fprintf('========================================\n');
fprintf('  SA vs SA_AdaptiveAlpha 对比测试\n');
fprintf('========================================\n\n');

%% 1. 设置项目路径
% 获取项目根目录（从 SA/Improvements/ 向上两级）
current_dir = fileparts(mfilename('fullpath'));
project_root = fileparts(fileparts(current_dir));

% 添加必要的路径
addpath(fullfile(project_root, "Main_fun"));
addpath(fullfile(project_root, "SA"));
addpath(fullfile(project_root, "SA", "Improvements"));
addpath(fullfile(project_root, "utils"));
addpath(fullfile(project_root, "comalg"));

% 验证路径
if ~exist('SA_Value_main.m', 'file')
    error('找不到 SA_Value_main.m，请检查路径设置');
end

%% 2. 创建测试场景
fprintf('[1/3] 创建测试场景...\n');

N = 8;  % 8 个智能体
M = 5;  % 5 个任务
K = 3;  % 3 种资源类型

% 定义任务类型需求矩阵 (task_type x K)
% 3 种任务类型，每种类型对 3 种资源的需求不同
task_type_demands = [
    10, 15, 20;  % 类型1：低需求
    20, 25, 30;  % 类型2：中需求
    30, 35, 40;  % 类型3：高需求
];

Value_Params = struct();
Value_Params.N = N;
Value_Params.M = M;
Value_Params.K = K;
Value_Params.task_type = 3;
Value_Params.task_type_demands = task_type_demands;  % 添加任务类型需求
Value_Params.num_rounds = 5;  % 运行 5 轮观察温度变化
Value_Params.K_len_SA = 3;
Value_Params.K_max_inner_SA = 30;
Value_Params.Temperature = 100;  % 初始温度（原始算法使用）
Value_Params.alpha = 0.95;
Value_Params.Tmin = 1;
Value_Params.seed = 42;
Value_Params.obs_times = 10;  % 观测次数

AddPara = struct();
AddPara.verbose = true;
AddPara.plot_enabled = false;
AddPara.resource_confidence = 0.95;  % 资源置信度参数

% 生成随机场景
rng(42);
agents = struct('id', {}, 'resources', {}, 'x', {}, 'y', {});
for i = 1:N
    agents(i).id = i;
    agents(i).resources = randi([8, 20], 1, K);
    pos = rand(1, 2) * 100;
    agents(i).x = pos(1);
    agents(i).y = pos(2);
end

tasks = struct('id', {}, 'x', {}, 'y', {}, 'true_demand', {}, 'resource_demand', {}, 'value', {}, 'priority', {}, 'duration', {}, 'duration_by_resource', {});
for j = 1:M
    tasks(j).id = j;
    pos = rand(1, 2) * 100;
    tasks(j).x = pos(1);
    tasks(j).y = pos(2);
    tasks(j).type = randi([1, Value_Params.task_type]);
    tasks(j).true_demand = task_type_demands(tasks(j).type, :);  % 使用类型对应的需求
    tasks(j).resource_demand = tasks(j).true_demand;  % 资源需求
    tasks(j).value = randi([80, 200]);
    tasks(j).priority = randi([1, 3]);
    tasks(j).duration_by_resource = ones(1, K) * 10;  % 每种资源的执行时间
    tasks(j).duration = 10;  % 任务持续时间
end

fprintf('  ✓ 场景创建完成：%d 智能体，%d 任务，%d 资源类型\n\n', N, M, K);

%% 3. 运行原始 SA 算法
fprintf('[2/3] 运行原始 SA_Value 算法...\n');
fprintf('========================================\n');
tic;
[Value_data_SA, history_SA] = SA_Value_main(agents, tasks, AddPara, Value_Params);
time_SA = toc;
fprintf('========================================\n');
fprintf('  ✓ 原始 SA 完成 | 时间: %.2f 秒\n\n', time_SA);

%% 4. 运行自适应温度 SA 算法
fprintf('[3/3] 运行 SA_AdaptiveAlpha 算法...\n');
fprintf('========================================\n');
tic;
[Value_data_Adaptive, history_Adaptive] = SA_Value_AdaptiveAlpha_main(agents, tasks, AddPara, Value_Params);
time_Adaptive = toc;
fprintf('========================================\n');
fprintf('  ✓ 自适应 SA 完成 | 时间: %.2f 秒\n\n', time_Adaptive);

%% 5. 对比结果
fprintf('========================================\n');
fprintf('  结果对比\n');
fprintf('========================================\n\n');

% 提取最终效用
if isfield(history_SA, 'total_completed_value') && ~isempty(history_SA.total_completed_value)
    final_utility_SA = history_SA.total_completed_value(end);
else
    final_utility_SA = NaN;
end

if isfield(history_Adaptive, 'total_completed_value') && ~isempty(history_Adaptive.total_completed_value)
    final_utility_Adaptive = history_Adaptive.total_completed_value(end);
else
    final_utility_Adaptive = NaN;
end

fprintf('%-25s | %-15s | %-15s\n', '指标', 'SA_Value', 'SA_AdaptiveAlpha');
fprintf('-------------------------------------------------------------------------\n');
fprintf('%-25s | %-15.2f | %-15.2f\n', '最终效用', final_utility_SA, final_utility_Adaptive);
fprintf('%-25s | %-15.2f | %-15.2f\n', '运行时间 (秒)', time_SA, time_Adaptive);

if ~isnan(final_utility_SA) && ~isnan(final_utility_Adaptive)
    improvement = ((final_utility_Adaptive - final_utility_SA) / final_utility_SA) * 100;
    fprintf('%-25s | %-15s | %-15.2f%%\n', '效用提升', 'N/A', improvement);
end

fprintf('========================================\n\n');

%% 6. 温度策略对比
fprintf('========================================\n');
fprintf('  温度策略对比\n');
fprintf('========================================\n\n');

fprintf('原始 SA_Value:\n');
fprintf('  - 使用固定的轮间温度递减策略\n');
fprintf('  - T(round) = max(T_base, T_0 * beta^(round-1))\n');
fprintf('  - 不考虑信念变化情况\n\n');

fprintf('SA_AdaptiveAlpha:\n');
fprintf('  - 根据信念变化自适应调整温度\n');
fprintf('  - 信念变化大 → 温度高（探索）\n');
fprintf('  - 信念变化小 → 温度低（开发）\n\n');

if isfield(history_Adaptive, 'belief_diff') && isfield(history_Adaptive, 'initial_temperature')
    fprintf('各轮温度调整详情：\n');
    fprintf('%-8s | %-15s | %-15s\n', '轮次', '信念变化', '初始温度');
    fprintf('------------------------------------------------------------------------\n');
    for r = 1:Value_Params.num_rounds
        if r == 1
            fprintf('%-8d | %-15s | %-15.2f\n', r, 'N/A (首轮)', history_Adaptive.initial_temperature(r));
        else
            fprintf('%-8d | %-15.4f | %-15.2f\n', r, history_Adaptive.belief_diff(r), history_Adaptive.initial_temperature(r));
        end
    end
end

fprintf('========================================\n\n');

%% 7. 结论
fprintf('========================================\n');
fprintf('  结论\n');
fprintf('========================================\n\n');

if ~isnan(final_utility_Adaptive) && ~isnan(final_utility_SA)
    if final_utility_Adaptive > final_utility_SA
        fprintf('✓ SA_AdaptiveAlpha 表现更好！\n');
        fprintf('  - 通过自适应温度策略，算法能够根据学习状态动态调整探索强度\n');
        fprintf('  - 在信念变化大时保持高温探索，在信念稳定时降低温度精细开发\n');
    elseif final_utility_Adaptive < final_utility_SA
        fprintf('⚠ 原始 SA_Value 表现更好\n');
        fprintf('  - 可能需要调整自适应策略的参数（threshold, T_0, T_base）\n');
        fprintf('  - 或者当前场景下固定递减策略更合适\n');
    else
        fprintf('= 两种算法效用相同\n');
        fprintf('  - 在当前场景下两种策略效果相当\n');
    end
else
    fprintf('⚠ 无法比较（某个算法未返回有效结果）\n');
end

fprintf('\n建议：\n');
fprintf('  1. 在更大规模场景下测试（N=20, M=10）\n');
fprintf('  2. 调整自适应参数（threshold, T_0, T_base）\n');
fprintf('  3. 使用 Compare_Algorithms.m 进行完整对比\n');
fprintf('========================================\n');

fprintf('\n测试完成！\n');
