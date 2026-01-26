clear; clc; close all;

fprintf('\n');
fprintf('========================================================================\n');
fprintf('                    Multi-Algorithm Comparison\n');
fprintf('                    多算法对比测试平台主程序\n');
fprintf('========================================================================\n\n');

%% Add paths
% 添加项目所需的子目录路径，确保 MATLAB 能找到所有算法函数
addpath("Main_fun\");              % core scenario/init functions (核心初始化与场景函数)
addpath("SA\");                    % SA algorithm (模拟退火算法)
addpath("plots\");                 % visualization helpers (绘图辅助工具)
addpath("comalg/Com_Baseline/");   % Greedy baseline (贪心基线算法)
addpath("comalg/Com_Huo2025/");    % Huo2025 algorithm (本文提出的算法)
addpath("comalg/Com_Qi2023/");     % Qi2023 algorithm (对比文献算法)
addpath("comalg/Com_PSO/");        % PSO algorithm (粒子群优化算法)

%% ========================================================================
%  Scenario configuration (adjust for debugging as needed)
%  场景参数配置（需要调试时可在此调整）
%% ========================================================================
SEED = 2456;                    % 随机种子 (所有算法共享，确保实验可复现性)
N = 5;                          % number of agents (智能体数量)
M = 10;                         % number of tasks (任务数量)
K = 6;                          % number of resource types (资源类型数量)
task_values = [800, 1000, 1500];  % three task types (三种不同类型的任务价值)
num_task_types = length(task_values);

% 核心开关：选择要运行的算法 ID
% 1=SA_Value, 2=Greedy, 3=Huo2025, 4=Qi2023, 5=PSO
algorithms_to_run_ids = [1,3];  

%%
% Display/save options (显示与保存选项)
save_results = true;    % 是否保存结果到本地 MAT 文件
show_plots = true;      % 是否绘制对比图
verbose = true;         % 是否打印额外日志

% World bounds (世界边界)
WORLD_XMIN = 0; WORLD_XMAX = 100;
WORLD_YMIN = 0; WORLD_YMAX = 100;
WORLD_ZMIN = 0; WORLD_ZMAX = 0;

% Agent parameters (智能体物理参数)
agent_velocity = 2;             % 移动速度
agent_detprob_min = 0.9;        % 探测概率下限
agent_detprob_max = 1.0;        % 探测概率上限
agent_Emax_min = 300;          % 最大能量下限
agent_Emax_range = 50;          % 最大能量随机范围
agent_fuel = 1;                 % 飞行油耗率 (单位距离消耗)
agent_wait_fuel = 0.5;          % 等待油耗率 (悬停/等待时的消耗，独立于飞行)
agent_beta = 1;                 % 执行任务油耗率 (执行任务时的额外消耗)
min_resource_value = 2;         % 智能体拥有资源的最小值
max_resource_value = 4;         % 智能体拥有资源的最大值

% Task resource demand ranges (per task type)
% 任务资源需求上限 (不同类型的任务需求不同)
task_type1_demand_max = 4;  % low (低需求任务)
task_type2_demand_max = 6;  % medium (中等需求)
task_type3_demand_max = 8;  % high (高需求)

% Resource execution time
% 每种资源类型处理所需的时间
resource_exec_time = [50 65 50 60 35 45];

% SA params (用于 SA_Value 算法，其他算法可忽略)
SA_Temperature = 100.0;     % 初始温度
SA_alpha = 0.95;            % 降温系数
SA_Tmin = 0.01;             % 终止温度
max_stable_iterations = 5;  % 最大稳定迭代次数 (用于判定收敛)

% Observation/game params (博弈与观测参数)
obs_times = 50;             % 观测次数 (贝叶斯更新用)
num_rounds = 50;            % 博弈总轮数
resource_confidence = 0.7;  % 资源分位数置信度

% Qi2023 utility params (对比算法 Qi2023 的特定参数)
Qi_beta_m = 1.0;   % 任务完成率权重
Qi_C_req = 0.5;    % 资源需求系数
Qi_omega = 0.1;    % 惩罚/调整参数
Qi_omega_1 = 1.0;  % 权重因子 1
Qi_omega_2 = 0.01; % 权重因子 2
Qi_omega_3 = 0.001;% 权重因子 3

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
% pro =rand(1, 10);  % 已删除：在种子设置前调用rand()会导致不可复现
rng('default');      % 重置随机数生成器到默认状态
rng(SEED);           % 设置固定的随机种子

% 构建 WORLD 结构体
WORLD.XMIN = WORLD_XMIN; WORLD.XMAX = WORLD_XMAX;
WORLD.YMIN = WORLD_YMIN; WORLD.YMAX = WORLD_YMAX;
WORLD.ZMIN = WORLD_ZMIN; WORLD.ZMAX = WORLD_ZMAX;
WORLD.value = task_values;

% Task type demands (生成三种任务类型的资源需求模板)
task_type_demands = zeros(num_task_types, K);
task_type_demands(1, :) = randi([0, task_type1_demand_max], 1, K); % 低需求
task_type_demands(2, :) = randi([0, task_type2_demand_max], 1, K); % 中需求
task_type_demands(3, :) = randi([0, task_type3_demand_max], 1, K); % 高需求

% Task durations by resource (计算各任务的时间消耗)
task_type_duration_by_resource = zeros(num_task_types, K);
for t = 1:num_task_types
    needed = task_type_demands(t, :) > 0; % 找出该任务需要哪些资源
    task_type_duration_by_resource(t, needed) = resource_exec_time(needed);
end

% Tasks Generation (生成具体的 M 个任务)
task_priorities = randperm(M);
for j = 1:M
    tasks(j).id = j;
    tasks(j).priority = task_priorities(j);
    tasks(j).x = round(rand(1) * (WORLD.XMAX - WORLD.XMIN) + WORLD.XMIN);
    tasks(j).y = round(rand(1) * (WORLD.YMAX - WORLD.YMIN) + WORLD.YMIN);
    tasks(j).type = randi(num_task_types, 1, 1); % 随机分配类型
    tasks(j).value = WORLD.value(tasks(j).type);
    tasks(j).resource_demand = task_type_demands(tasks(j).type, :);
    tasks(j).duration_by_resource = task_type_duration_by_resource(tasks(j).type, :);
    
    % 并行资源模型：如果任务需要多种资源，总时长取决于耗时最长的那个资源
    tasks(j).duration = max(tasks(j).duration_by_resource); 
    tasks(j).WORLD = WORLD;
end

% Agents Generation (生成 N 个智能体)
for i = 1:N
    agents(i).id = i;
    agents(i).vel = agent_velocity;
    agents(i).x = round(rand(1) * (WORLD.XMAX - WORLD.XMIN) + WORLD.XMIN);
    agents(i).y = round(rand(1) * (WORLD.YMAX - WORLD.YMIN) + WORLD.YMIN);
    agents(i).detprob = agent_detprob_min + (agent_detprob_max - agent_detprob_min) * rand();
    agents(i).resources = randi([min_resource_value, max_resource_value], K, 1); % 随机资源能力
    agents(i).Emax = agent_Emax_min + agent_Emax_range * rand();
    agents(i).fuel = agent_fuel;
    agents(i).wait_fuel = agent_wait_fuel;
    agents(i).beta = agent_beta;
end

% Algorithm shared params (打包所有算法通用的参数)
Value_Params = OCFUtils.init_value_params(N, M, K, num_task_types, task_type_demands, ...
    SA_Temperature, SA_alpha, SA_Tmin, max_stable_iterations, ...
    obs_times, num_rounds, resource_confidence); 

% Random seed for reproducibility (重要：将种子也传入参数中)
Value_Params.seed = SEED;

% Qi2023 extras (附加 Qi2023 专用参数)
Value_Params.Qi_beta_m = Qi_beta_m;
Value_Params.Qi_C_req = Qi_C_req;
Value_Params.Qi_omega = Qi_omega;
Value_Params.Qi_omega_1 = Qi_omega_1;
Value_Params.Qi_omega_2 = Qi_omega_2;
Value_Params.Qi_omega_3 = Qi_omega_3;

% Scenario info (saved with results) (保存场景元数据，用于后续分析)
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
% 定义算法注册表：包含ID、名称、对应的函数句柄、文件夹路径和绘图颜色
all_algorithms = {
    struct('id', 1, 'name', 'SA_Value',        'func', @SA_Value_main,       'folder', 'SA',                   'color', [0.2, 0.6, 0.8]); % 模拟退火
    struct('id', 2, 'name', 'Greedy baseline', 'func', @Greedy_Baseline_main,'folder', 'comalg/Com_Baseline',  'color', [0.5, 0.5, 0.5]); % 贪心基线
    struct('id', 3, 'name', 'Huo2025',         'func', @Huo2025_main,        'folder', 'comalg/Com_Huo2025',   'color', [0.8, 0.2, 0.2]); % Huo2025
    struct('id', 4, 'name', 'Qi2023',          'func', @Qi2023_main,         'folder', 'comalg/Com_Qi2023',    'color', [0.2, 0.8, 0.2]); % Qi2023
    struct('id', 5, 'name', 'PSO',             'func', @PSO_main,            'folder', 'comalg/Com_PSO',       'color', [0.8, 0.8, 0.2]); % 粒子群
    }; 

fprintf('Available algorithms (可用算法):\n');
for i = 1:length(all_algorithms)
    alg = all_algorithms{i};
    if ismember(alg.id, algorithms_to_run_ids)
        fprintf('  [%d] %s (selected / 已选)\n', alg.id, alg.name);
    else
        fprintf('  [%d] %s\n', alg.id, alg.name);
    end
end
fprintf('\nRunning IDs: [%s]\n\n', num2str(algorithms_to_run_ids));

%% AddPara (kept for interface parity)
% 保留接口，部分旧算法可能需要这个结构体
AddPara.control = 1;

%% Run selected algorithms
% 逐个运行已选算法，记录结果与运行时间
fprintf('========================================================================\n');
fprintf('                    Running comparisons (开始运行对比)\n');
fprintf('========================================================================\n\n');

results = struct();
enabled_algorithms = {};
enabled_count = 0;

for i = 1:length(all_algorithms)
    alg = all_algorithms{i};
    % 如果当前算法不在“运行列表”中，则跳过
    if ~ismember(alg.id, algorithms_to_run_ids)
        continue;
    end
    enabled_count = enabled_count + 1;
    enabled_algorithms{enabled_count} = alg;

    fprintf('----------------------------------------\n');
    fprintf('Running: [%d] %s\n', alg.id, alg.name);
    fprintf('----------------------------------------\n');
    try
        rng(SEED);  % 关键：再次重置随机种子，确保每个算法面临的内部随机性起点一致（公平竞争）
        tic;
        % 调用算法主函数：输入统一为 (agents, tasks, AddPara, Value_Params)
        [Value_data, history_data] = alg.func(agents, tasks, AddPara, Value_Params);
        comp_time = toc;

        % 保存运行结果
        results.(sprintf('alg%d', enabled_count)).name = alg.name;
        results.(sprintf('alg%d', enabled_count)).Value_data = Value_data;
        results.(sprintf('alg%d', enabled_count)).history_data = history_data;
        results.(sprintf('alg%d', enabled_count)).computation_time = comp_time;
        results.(sprintf('alg%d', enabled_count)).color = alg.color;

        fprintf('OK %s done (%.2f s)\n\n', alg.name, comp_time);
    catch ME
        % 错误处理：如果某算法崩溃，记录错误但不中断整个脚本
        fprintf('X %s failed (失败):\n', alg.name);
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
fprintf('                    All runs finished (所有运行结束)\n');
fprintf('========================================================================\n\n');

%% Compare results
% 对比各算法的统计指标，输出表格、绘图/存档
if enabled_count > 0
    fprintf('Analyzing results...\n');
    % [修改] 传入 Value_Params，因为 compare_results 内部需要用到 M (任务数) 等参数
    comparison_stats = compare_results(results, Value_Params); 

    fprintf('\n========================================================================\n');
    fprintf('                    Performance summary (性能总结)\n');
    fprintf('========================================================================\n\n');

    % [表格1] 总体性能：效用、成本、联盟数、时间
    fprintf('%-20s | %10s | %10s | %10s | %10s\n', ...
        'Algorithm', 'Utility', 'Cost', '#Coal', 'Time(s)');
    fprintf('%s\n', repmat('-', 1, 80));

    for i = 1:enabled_count
        stats = comparison_stats.(sprintf('alg%d', i));
        if isfield(stats, 'total_utility')
            fprintf('%-20s | %10.2f | %10.2f | %10d | %10.2f\n', ...
                stats.name, ...
                stats.total_utility, ...
                stats.total_cost, ...      % 总成本
                stats.num_coalitions, ...  % 成功组建的联盟数 (执行的任务数)
                stats.computation_time);
        else
            fprintf('%-20s | %10s | %10s | %10s | %10.2f\n', ...
                stats.name, 'error', 'error', 'error', stats.computation_time);
        end
    end
    fprintf('%s\n\n', repmat('-', 1, 80));

    % [表格2] 任务完成细节
    fprintf('\nTask Completion Details (任务完成详情):\n'); 
    fprintf('%-20s | %15s | %15s\n', ...
        'Algorithm', 'Total Value', 'Avg Rate (%)');
    fprintf('%s\n', repmat('-', 1, 65));

    for i = 1:enabled_count
        stats = comparison_stats.(sprintf('alg%d', i));
        if isfield(stats, 'total_completion_score')
            fprintf('%-20s | %15.2f | %15.2f%%\n', ...
                stats.name, ...
                stats.total_completion_score, ...   % 任务完成总价值
                stats.avg_task_completion * 100);   % 平均完成率 (0-1 -> %)
        else
            fprintf('%-20s | %15s | %15s\n', ...
                stats.name, '-', '-');
        end
    end
    fprintf('%s\n\n', repmat('-', 1, 65));

    % 绘图
    if show_plots && enabled_count > 1
        fprintf('Plotting comparison charts...\n');
        plot_algorithm_comparison(results, comparison_stats, enabled_count);
    end

    % 保存数据
    if save_results
        if ~exist('results', 'dir'); mkdir('results'); end
        timestamp = datestr(now, 'yyyymmdd_HHMMSS');
        filename = sprintf('results/comparison_results_seed%d_%s.mat', SEED, timestamp);
        fprintf('Saving results to: %s\n', filename);
        
        % 保存所有关键变量，方便后续复盘
        save(filename, 'results', 'comparison_stats', 'agents', 'tasks', ...
            'Value_Params', 'WORLD', 'scenario_info', 'enabled_algorithms');
        fprintf('results saved\n\n');
    end
else
    fprintf('Warning: no algorithms enabled (警告：未选中任何算法)\n\n'); 
end

fprintf('========================================================================\n');
fprintf('                    Comparison done (对比结束)\n');
fprintf('========================================================================\n\n');

%% ========================================================================
%  Custom Visualization: SA_Value Resource Allocation
%  新增可视化：SA算法资源分配详情 & 打印智能体能力
%  调用 plots/ResourcePlotter 类
%% ========================================================================

% 检查是否运行了 SA_Value (ID = 1) 且结果存在
if isfield(results, 'alg1') && strcmp(results.alg1.name, 'SA_Value')
    fprintf('\nVisualizing SA_Value resource details...\n');
    
    % 1. [新增] 首先打印智能体的资源能力上限，方便对照
    PlotClass.print_agent_capabilities(agents);
    
    % 2. 获取 SA 算法的最终输出数据并绘图
    sa_value_data = results.alg1.Value_data;
    PlotClass.plot_SA_allocation(sa_value_data, tasks, Value_Params);
    
    fprintf('Resource allocation plot generated.\n');
else
    fprintf('\nSkipping SA_Value visualization (Algorithm not run or not result 1).\n');
end


% 选择要进行动画展示的算法结果 (例如这里选择 SA_Value，即 alg1)
target_alg_idx = 1; % 修改这里可以选择其他算法，如 2, 3 等
target_alg_field = sprintf('alg%d', target_alg_idx);

if isfield(results, target_alg_field) && isfield(results.(target_alg_field), 'Value_data')
    alg_name = results.(target_alg_field).name;
    fprintf('\nGenerating dynamic animation for algorithm: %s ...\n', alg_name);
    fprintf('Please wait for the animation window to appear.\n');
    
    % 获取目标算法的输出数据
    anim_data = results.(target_alg_field).Value_data;
    
    % 调用 PlotClass 中的静态动画函数
    % 注意：确保 plots 文件夹在路径中
    PlotClass.plot_execution_animation(anim_data, agents, tasks, Value_Params);
    
else
    fprintf('\nSkipping animation: Algorithm result %d not found.\n', target_alg_idx);
end