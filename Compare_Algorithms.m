clear; clc; close all;

%% ========================================================================
%  Multi-algorithm comparison framework for coalition formation
%  多算法对比主脚本：在同一场景下运行多种联盟形成算法并比较结果
%  - Initialize a common scenario (same SEED) for all algorithms
%    为所有算法初始化相同的随机场景（共享 SEED）
%  - Run multiple algorithms under the same scenario
%    在相同场景下运行多种算法
%  - Compare metrics: total utility, runtime, coalition counts, etc.
%    比较总效用、运行时间、联盟数量等指标
%  - Generate comparison tables/plots and save results
%    生成对比表格/图表并保存结果
%  - Adjust algorithms_to_run_ids to include/exclude algorithms
%    通过 algorithms_to_run_ids 选择要运行的算法
%% ========================================================================

fprintf('\n');
fprintf('========================================================================\n');
fprintf('                    Multi-Algorithm Comparison\n');
fprintf('========================================================================\n\n');

%% Add paths
% 添加项目所需的子目录路径
addpath("Main_fun\");             % core scenario/init functions 核心初始化/场景函数
addpath("SA\");                    % SA algorithm 模拟退火算法
addpath("plots\");                 % visualization helpers 绘图辅助
addpath("comalg/Com_Baseline/");          % Greedy baseline 贪心基线
addpath("comalg/Com_Huo2025/");           % Huo2025 algorithm
addpath("comalg/Com_Qi2023/");            % Qi2023 algorithm
addpath("comalg/Com_PSO/");           % PSO algorithm 粒子群算法

%% ========================================================================
%  Scenario configuration (adjust for debugging as needed)
%  场景参数配置（需要调试时可在此调整）
%% ========================================================================
SEED = 2437;                    % random seed (shared across algorithms)
N = 6;                          % number of agents
M = 10;                         % number of tasks
K = 6;                          % number of resource types
task_values = [800, 1000, 1500];  % three task types
num_task_types = length(task_values);

% Algorithm selection
algorithms_to_run_ids = [3];  % 选择要运行的算法 1=SA_Value, 2=Greedy, 3=Huo2025, 4=Qi2023, 5=PSO

% Display/save options
save_results = true;  % 是否保存结果到 MAT 文件
show_plots = true;    % 是否绘制对比图
verbose = true;       % 是否打印额外日志

% World bounds and task values
WORLD_XMIN = 0; WORLD_XMAX = 100;
WORLD_YMIN = 0; WORLD_YMAX = 100;
WORLD_ZMIN = 0; WORLD_ZMAX = 0;

% Agent parameters
agent_velocity = 2; % vel速度
agent_detprob_min = 0.9;
agent_detprob_max = 1.0;
agent_Emax_min = 300;
agent_Emax_range = 50;
agent_fuel = 1;               % 飞行油耗
agent_wait_fuel = 0.5;        % 等待阶段的油耗率（独立于飞行油耗）
agent_beta = 1;              % 执行任务油耗
min_resource_value = 2;      % 智能体资源值最大最小设置
max_resource_value = 4;

% Task resource demand ranges (per task type)
task_type1_demand_max = 4;  % low
task_type2_demand_max = 6;  % medium
task_type3_demand_max = 8;  % high

% Resource execution time
resource_exec_time = [50 65 50 60 35 45];

% SA params (used by SA_Value; others may ignore)
SA_Temperature = 100.0;
SA_alpha = 0.95;
SA_Tmin = 0.01;
SA_max_stable_iterations = 5;

% Observation/game params
obs_times = 50;      % 观测次数
num_rounds = 50;     % 博弈轮数
resource_confidence = 0.7;  % 分位数置信度

% Qi2023 utility params
Qi_beta_m = 1.0;   % 任务完成率权重
Qi_C_req = 0.5;    % 资源需求系数
Qi_omega = 0.1;    % 惩罚/调整参数
Qi_omega_1 = 1.0;  % 权重1
Qi_omega_2 = 0.01; % 权重2
Qi_omega_3 = 0.001;% 权重3

%% ========================================================================
%  Scenario initialization
%  场景初始化：生成任务、智能体与共享参数
%% ========================================================================
fprintf('Initializing scenario...\n');
fprintf('  - seed: %d\n', SEED);
fprintf('  - agents: %d\n', N);
fprintf('  - tasks: %d\n', M);
fprintf('  - resources: %d\n', K);
fprintf('  - rounds: %d\n\n', num_rounds);

tic;
rand('seed', SEED);

% WORLD struct
WORLD.XMIN = WORLD_XMIN; WORLD.XMAX = WORLD_XMAX;
WORLD.YMIN = WORLD_YMIN; WORLD.YMAX = WORLD_YMAX;
WORLD.ZMIN = WORLD_ZMIN; WORLD.ZMAX = WORLD_ZMAX;
WORLD.value = task_values;

% Task type demands
% 三种类型的需求
task_type_demands = zeros(num_task_types, K);
task_type_demands(1, :) = randi([0, task_type1_demand_max], 1, K); % 低需求
task_type_demands(2, :) = randi([0, task_type2_demand_max], 1, K); % 中等需求
task_type_demands(3, :) = randi([0, task_type3_demand_max], 1, K); % 高需求

% Task durations by resource
% 根据需求 每个需求所需要的时间
task_type_duration_by_resource = zeros(num_task_types, K);
for t = 1:num_task_types
    needed = task_type_demands(t, :) > 0;
    task_type_duration_by_resource(t, needed) = resource_exec_time(needed);
end

% Tasks
task_priorities = randperm(M);
for j = 1:M
    tasks(j).id = j;
    tasks(j).priority = task_priorities(j);
    tasks(j).x = round(rand(1) * (WORLD.XMAX - WORLD.XMIN) + WORLD.XMIN);
    tasks(j).y = round(rand(1) * (WORLD.YMAX - WORLD.YMIN) + WORLD.YMIN);
    tasks(j).type = randi(num_task_types, 1, 1);
    tasks(j).value = WORLD.value(tasks(j).type);
    tasks(j).resource_demand = task_type_demands(tasks(j).type, :);
    tasks(j).duration_by_resource = task_type_duration_by_resource(tasks(j).type, :);
    tasks(j).duration = max(tasks(j).duration_by_resource); % 并行资源模型：总时长取最大值
    tasks(j).WORLD = WORLD;
end

% Agents
for i = 1:N
    agents(i).id = i;
    agents(i).vel = agent_velocity;
    agents(i).x = round(rand(1) * (WORLD.XMAX - WORLD.XMIN) + WORLD.XMIN);
    agents(i).y = round(rand(1) * (WORLD.YMAX - WORLD.YMIN) + WORLD.YMIN);
    agents(i).detprob = agent_detprob_min + (agent_detprob_max - agent_detprob_min) * rand();
    agents(i).resources = randi([min_resource_value, max_resource_value], K, 1);
    agents(i).Emax = agent_Emax_min + agent_Emax_range * rand();
    agents(i).fuel = agent_fuel;
    agents(i).wait_fuel = agent_wait_fuel;
    agents(i).beta = agent_beta;
end

% Algorithm shared params
Value_Params = init_value_params(N, M, K, num_task_types, task_type_demands, ...
    SA_Temperature, SA_alpha, SA_Tmin, SA_max_stable_iterations, ...
    obs_times, num_rounds, resource_confidence); % 通用参数结构（不同算法可复用）

% Qi2023 extras
Value_Params.Qi_beta_m = Qi_beta_m;
Value_Params.Qi_C_req = Qi_C_req;
Value_Params.Qi_omega = Qi_omega;
Value_Params.Qi_omega_1 = Qi_omega_1;
Value_Params.Qi_omega_2 = Qi_omega_2;
Value_Params.Qi_omega_3 = Qi_omega_3;

% Scenario info (saved with results)
scenario_info.SEED = SEED;
scenario_info.N = N;
scenario_info.M = M;
scenario_info.K = K;
scenario_info.num_task_types = num_task_types;
scenario_info.task_type_demands = task_type_demands;
scenario_info.resource_exec_time = resource_exec_time;
scenario_info.timestamp = datetime('now');

init_time = toc;
fprintf('Scenario initialized (%.2f s)\n\n', init_time);

%% Define algorithms
all_algorithms = {
    struct('id', 1, 'name', 'SA_Value',        'func', @SA_Value_main,       'folder', 'SA',           'color', [0.2, 0.6, 0.8]); % 模拟退火
    struct('id', 2, 'name', 'Greedy baseline', 'func', @Greedy_Baseline_main,'folder', 'comalg/Com_Baseline', 'color', [0.5, 0.5, 0.5]); % 贪心基线
    struct('id', 3, 'name', 'Huo2025',         'func', @Huo2025_main,        'folder', 'comalg/Com_Huo2025',  'color', [0.8, 0.2, 0.2]); % Huo2025
    struct('id', 4, 'name', 'Qi2023',          'func', @Qi2023_main,         'folder', 'comalg/Com_Qi2023',   'color', [0.2, 0.8, 0.2]); % Qi2023
    struct('id', 5, 'name', 'PSO',     'func', @PSO_main,        'folder', 'comalg/Com_PSO',  'color', [0.8, 0.8, 0.2]); % 粒子群
    }; % 可根据需要增删算法

fprintf('Available algorithms:\n');
for i = 1:length(all_algorithms)
    alg = all_algorithms{i};
    if ismember(alg.id, algorithms_to_run_ids)
        fprintf('  [%d] %s (selected)\n', alg.id, alg.name);
    else
        fprintf('  [%d] %s\n', alg.id, alg.name);
    end
end
fprintf('\nRunning: [%s]\n\n', num2str(algorithms_to_run_ids));

%% AddPara (kept for interface parity)
AddPara.control = 1;

%% Run selected algorithms
% 逐个运行已选算法，记录结果与运行时间
fprintf('========================================================================\n');
fprintf('                    Running comparisons\n');
fprintf('========================================================================\n\n');

results = struct();
enabled_algorithms = {};
enabled_count = 0;

for i = 1:length(all_algorithms)
    alg = all_algorithms{i};
    if ~ismember(alg.id, algorithms_to_run_ids)
        continue;
    end
    enabled_count = enabled_count + 1;
    enabled_algorithms{enabled_count} = alg;

    fprintf('----------------------------------------\n');
    fprintf('Running: [%d] %s\n', alg.id, alg.name);
    fprintf('----------------------------------------\n');
    try
        rand('seed', SEED);
        tic;
        [Value_data, history_data] = alg.func(agents, tasks, AddPara, Value_Params);
        comp_time = toc;

        results.(sprintf('alg%d', enabled_count)).name = alg.name;
        results.(sprintf('alg%d', enabled_count)).Value_data = Value_data;
        results.(sprintf('alg%d', enabled_count)).history_data = history_data;
        results.(sprintf('alg%d', enabled_count)).computation_time = comp_time;
        results.(sprintf('alg%d', enabled_count)).color = alg.color;

        fprintf('OK %s done (%.2f s)\n\n', alg.name, comp_time);
    catch ME
        fprintf('X %s failed:\n', alg.name);
        fprintf('  error: %s\n', ME.message);
        if ~isempty(ME.stack)
            fprintf('  location: %s (line %d)\n\n', ME.stack(1).name, ME.stack(1).line);
        end
        results.(sprintf('alg%d', enabled_count)).name = alg.name;
        results.(sprintf('alg%d', enabled_count)).error = ME;
        results.(sprintf('alg%d', enabled_count)).computation_time = NaN;
    end
end

fprintf('========================================================================\n');
fprintf('                    All runs finished\n');
fprintf('========================================================================\n\n');

%% Compare results
% 对比各算法的统计指标，输出表格/绘图/存档
if enabled_count > 0
    fprintf('Analyzing results...\n');
    comparison_stats = compare_results(results, agents, tasks, Value_Params); % 统计与对比各算法指标

    fprintf('\n========================================================================\n');
    fprintf('                    Performance summary\n');
    fprintf('========================================================================\n\n');

    fprintf('%-20s | %10s | %10s | %10s | %10s\n', ...
        'Algorithm', 'Utility', '#Coal', 'NormComp', 'Time(s)');
    fprintf('%s\n', repmat('-', 1, 80));
    for i = 1:enabled_count
        stats = comparison_stats.(sprintf('alg%d', i));
        if isfield(stats, 'total_utility')
            fprintf('%-20s | %10.2f | %10d | %10.2f%% | %10.2f\n', ...
                stats.name, stats.total_utility, stats.num_coalitions, ...
                stats.normalized_completion_rate, stats.computation_time);
        else
            fprintf('%-20s | %10s | %10s | %10s | %10.2f\n', ...
                stats.name, 'error', 'error', 'error', stats.computation_time);
        end
    end
    fprintf('%s\n\n', repmat('-', 1, 80));

    fprintf('\nTask completion details:\n'); % 任务完成情况明细
    fprintf('%-20s | %10s | %10s | %10s | %10s\n', ...
        'Algorithm', 'EqvDone', 'Full', 'Partial', 'AvgComp');
    fprintf('%s\n', repmat('-', 1, 80));
    for i = 1:enabled_count
        stats = comparison_stats.(sprintf('alg%d', i));
        if isfield(stats, 'total_completion_score')
            fprintf('%-20s | %10.2f | %10d | %10d | %10.2f%%\n', ...
                stats.name, stats.total_completion_score, ...
                stats.fully_completed_tasks, stats.partially_completed_tasks, ...
                stats.avg_task_completion * 100);
        else
            fprintf('%-20s | %10s | %10s | %10s | %10s\n', ...
                stats.name, '-', '-', '-', '-');
        end
    end
    fprintf('%s\n\n', repmat('-', 1, 80));

    if show_plots && enabled_count > 1
        fprintf('Plotting comparison charts...\n');
        plot_algorithm_comparison(results, comparison_stats, enabled_count);
    end

    if save_results
        % 保存结果到本地 MAT 文件
        if ~exist('results', 'dir'); mkdir('results'); end
        timestamp = datestr(now, 'yyyymmdd_HHMMSS');
        filename = sprintf('results/comparison_results_seed%d_%s.mat', SEED, timestamp);
        fprintf('Saving results to: %s\n', filename);
        save(filename, 'results', 'comparison_stats', 'agents', 'tasks', ...
            'Value_Params', 'WORLD', 'scenario_info', 'enabled_algorithms');
        fprintf('results saved\n\n');
    end
else
    fprintf('Warning: no algorithms enabled\n\n'); % 未选择算法的提示
end

fprintf('========================================================================\n');
fprintf('                    Comparison done\n');
fprintf('========================================================================\n\n');



