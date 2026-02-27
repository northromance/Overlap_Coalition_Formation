clear; clc; close all;

fprintf('\n');
fprintf('========================================================================\n');
fprintf('                    Multi-Algorithm Comparison\n');
fprintf('                    多算法对比实验平台初始化\n');
fprintf('========================================================================\n\n');

%% Add paths
% 添加项目子目录路径，确保 MATLAB 能找到对应算法函数
% 获取项目根目录（Compare_Algorithms.m 在 Main_fun 子目录中）
script_dir = fileparts(mfilename('fullpath'));  % 获取脚本所在目录（Main_fun）
project_root = fileparts(script_dir);            % 获取项目根目录
addpath(fullfile(project_root, "Overlap_Coalition_Formation\Main_fun"));              % core scenario/init functions（核心初始化与场景函数）
addpath(fullfile(project_root, "Overlap_Coalition_Formation\SA"));                    % SA algorithm（模拟退火算法）
addpath(fullfile(project_root, "Overlap_Coalition_Formation\comalg", "Com_Baseline"));   % Greedy baseline（贪心基线算法）
addpath(fullfile(project_root, "Overlap_Coalition_Formation\comalg", "Com_Huo2025"));    % Huo2025 algorithm（Huo2025 算法）
addpath(fullfile(project_root, "Overlap_Coalition_Formation\comalg", "Com_Qi2023"));     % Qi2023 algorithm（Qi2023 算法）
addpath(fullfile(project_root, "Overlap_Coalition_Formation\comalg", "Com_Shi2024"));    % Shi2024 OCF algorithm（Shi2024 重叠联盟形成算法）
addpath(fullfile(project_root, "Overlap_Coalition_Formation\comalg", "Com_Fang2025"));    % Fang2025 algorithm（Fang2025 算法）
addpath(fullfile(project_root, "Overlap_Coalition_Formation\comalg", "SA_TabuEnhance"));        % PSO algorithm（粒子群优化算法）

%% ========================================================================
%  Scenario configuration (adjust for debugging as needed)
%  场景参数配置（调试时可在此处修改）
%% ========================================================================

SEED = 2456;                    % 随机种子（确保实验可复现）
N = 6;                          % number of agents（智能体数量）
M = 10;                         % number of tasks（任务数量）
K = 6;                          % number of resource types（资源类型数）
task_values = [800, 1000, 1500];  % three task types（三种不同类型任务的价值）
num_task_types = length(task_values);
algorithms_to_run_ids = [10]; 

% 算法开关：选择要运行的算法 ID
% 1=SA_Value, 2=Greedy, 3=Huo2025, 4=Qi2023, 5=Shi2024, 6=PSO
% 7-12=SA改进算法（TabuEnhanced, AdaptiveAlpha
% 9=Fang2025

% 比较非重叠联盟算法 + 信念更新机制
% 比较重叠联盟算法Qi2023 + 信念更新机制 
% 

%% Display/save options（显示与保存选项）
save_results = true;    % 是否保存结果到 MAT 文件

% World bounds（环境边界）
WORLD_XMIN = 0; WORLD_XMAX = 100;
WORLD_YMIN = 0; WORLD_YMAX = 100;
WORLD_ZMIN = 0; WORLD_ZMAX = 0;

% Agent parameters（智能体参数）
agent_velocity = 2;             % 移动速度
agent_detprob_min = 0.95;        % 探测概率下限
agent_detprob_max = 1.0;        % 探测概率上限
agent_Emax_min = 300;           % 最大能量下限
agent_Emax_range = 50;          % 最大能量随机范围
agent_fuel = 1;                 % 运动油耗（单位距离消耗）
agent_wait_fuel = 0.5;          % 等待油耗（停留/等待时消耗，通常小于运动）
agent_beta = 1;                 % 执行动作油耗系数（执行任务时的动作消耗）
min_resource_value = 0;         % 智能体拥有的资源能力最小值
max_resource_value = 4;         % 智能体拥有的资源能力最大值

% Task resource demand ranges (per task type)
% 任务资源需求范围（不同任务类型需求强度不同）
task_type1_demand_max = 4;  % low（低需求）
task_type2_demand_max = 6;  % medium（中需求）
task_type3_demand_max = 8;  % high（高需求）

% Resource execution time
% 每种资源的执行时间
resource_exec_time = [50 65 50 60 35 45];

%% ========================================================================
%% 算法迭代控制参数 - 各算法独立配置
%% ========================================================================

% 通用参数
obs_times = 50;              % 观测次数（贝叶斯更新等）
num_rounds = 300;              % 迭代轮数（快速测试: 5轮）

% ========================================================================
% 算法 1: SA_Value（模拟退火基础算法）
% ========================================================================
SA_Temperature = 200.0;               % 初始温度
SA_alpha = 0.95;                      % 降温系数
SA_Tmin = 0.01;                       % 终止温度
SA_K_len = 20;                        % 稳定性阈值（连续无改进迭代次数）
SA_K_max_inner = 100;                  % 每轮最大迭代次数（快速测试20，完整测试建议200）
SA_T0_round = 200;                    % 回合温度调度：初始温度 T_0
SA_beta_round = 0.85;                 % 回合温度调度：衰减系数 beta
SA_T_base_round = 10;                 % 回合温度调度：温度下界 T_base
SA_resource_confidence = 0.9;         % 初始构造阶段需求分位置信度
SA_T_init_construction = 0.5;         % 初始构造阶段温度（低温近贪婪）

% TabuEnhanced专属参数：
% 算法 7: SA_TabuEnhanced（全局效用版本）
SA_Tabu_K_max_outer = 50;
SA_Tabu_K_max_inner = 1;
SA_Tabu_tenure = 20;
SA_p_leave = 0.1;  % 新增：离开概率

% 算法 10: SA_TabuEnhanced_Altruistic（利他偏好版本）
% 使用与算法7相同的参数，但决策机制基于 Preference_gain
tabu_tenure = 20;        % 禁忌期限

% ========================================================================
% 算法 4: Qi2023（基于禁忌搜索的重叠联盟形成算法）
% ========================================================================
% 效用函数参数
Qi_beta_m = 1.0;                      % 边际效用权重
Qi_C_req = 0.5;                       % 资源需求成本系数
Qi_omega = 0.1;                       % 惩罚/松弛项
Qi_omega_1 = 1.0;                     % 权重参数 1
Qi_omega_2 = 0.01;                    % 权重参数 2
Qi_omega_3 = 0.001;                   % 权重参数 3
% 迭代控制参数
Qi_L_tabu = 10;                       % 禁忌表长度
Qi_K_len = 30;                        % 稳定性阈值（连续无改进迭代次数）
Qi_K_max_inner = 20;                  % 每轮最大迭代次数（统一为20，原200）
Qi_Gamma_init = 1;                    % 初始 Boltzmann 系数
Qi_Gamma_max = 100;                   % 最大 Boltzmann 系数

% ========================================================================
% 算法 5: Shi2024（动态重叠联盟形成算法）
% ========================================================================
Shi_K_max_inner = 50;                 % 每轮最大迭代次数
Shi_K_len = 10;                       % 稳定性阈值

% ========================================================================
% 算法 10: 
% ========================================================================
tabu_tenure = 20 ; % 禁忌期限


%% AddPara (算法接口参数)
% 为接口统一保留：部分算法需要该结构体
AddPara.control = 1;
AddPara.resource_confidence = 0.95;  % 资源分位/置信度（风险规避）
AddPara.enable_belief_update = true; % 信念更新开关：true=启用，false=仅使用初始信念
AddPara.verbose = true;             % 打印调试开关：true=详细输出，false=精简输出

%% ========================================================================
%  Scenario initialization
%  场景初始化：生成智能体、任务以及共享参数
%% ========================================================================


fprintf('Initializing scenario...\n');
fprintf('  - seed: %d\n', SEED);
fprintf('  - agents: %d\n', N);
fprintf('  - tasks: %d\n', M);
fprintf('  - resources: %d\n', K);
fprintf('  - rounds: %d\n\n', num_rounds);

tic;

% pro =rand(1, 10);  % 已删：在前面调用 rand() 可能导致不可复现
rng('default');      % 重置随机数发生器到默认状态
rng(SEED);           % 设置固定随机种子

% Build WORLD struct（构造 WORLD 结构体）
WORLD.XMIN = WORLD_XMIN; WORLD.XMAX = WORLD_XMAX;
WORLD.YMIN = WORLD_YMIN; WORLD.YMAX = WORLD_YMAX;
WORLD.ZMIN = WORLD_ZMIN; WORLD.ZMAX = WORLD_ZMAX;
WORLD.value = task_values;

% Task type demands（不同任务类型的资源需求模板）
task_type_demands = zeros(num_task_types, K);
task_type_demands(1, :) = randi([0, task_type1_demand_max], 1, K); % 低需求
task_type_demands(2, :) = randi([0, task_type2_demand_max], 1, K); % 中需求
task_type_demands(3, :) = randi([0, task_type3_demand_max], 1, K); % 高需求

% Task durations by resource（不同任务类型在各资源上的执行时间）
task_type_duration_by_resource = zeros(num_task_types, K);
for t = 1:num_task_types
    needed = task_type_demands(t, :) > 0; % 找出该类型任务需要哪些资源
    task_type_duration_by_resource(t, needed) = resource_exec_time(needed);
end

% Tasks Generation（生成 M 个任务）
task_priorities = randperm(M);
for j = 1:M
    tasks(j).id = j;
    tasks(j).priority = task_priorities(j);
    tasks(j).x = round(rand(1) * (WORLD.XMAX - WORLD.XMIN) + WORLD.XMIN);
    tasks(j).y = round(rand(1) * (WORLD.YMAX - WORLD.YMIN) + WORLD.YMIN);
    tasks(j).type = randi(num_task_types, 1, 1); % 任务类型
    tasks(j).value = WORLD.value(tasks(j).type);
    tasks(j).resource_demand = task_type_demands(tasks(j).type, :);
    tasks(j).duration_by_resource = task_type_duration_by_resource(tasks(j).type, :);
    
    % 任务持续时间：取所需资源执行时间的最大值（以最耗时资源为准）
    tasks(j).duration = max(tasks(j).duration_by_resource);
    tasks(j).WORLD = WORLD;
end

% Agents Generation（生成 N 个智能体）
for i = 1:N
    agents(i).id = i;
    agents(i).vel = agent_velocity;
    agents(i).x = round(rand(1) * (WORLD.XMAX - WORLD.XMIN) + WORLD_XMIN);
    agents(i).y = round(rand(1) * (WORLD.YMAX - WORLD_YMIN) + WORLD_YMIN);
    agents(i).detprob = agent_detprob_min + (agent_detprob_max - agent_detprob_min) * rand();
    agents(i).resources = randi([min_resource_value, max_resource_value], K, 1); % 资源能力
    agents(i).Emax = agent_Emax_min + agent_Emax_range * rand();
    agents(i).fuel = agent_fuel;
    agents(i).wait_fuel = agent_wait_fuel;
    agents(i).beta = agent_beta;
end

% Algorithm shared params（各算法通用参数）
Value_Params = OCFUtils.init_value_params(N, M, K, num_task_types, task_type_demands, ...
    SA_Temperature, SA_alpha, SA_Tmin, SA_K_len, ...
    obs_times, num_rounds);

%% ========================================================================
%% 算法专属参数注入 Value_Params
%% ========================================================================

% ------------------ SA系列算法参数 ------------------
Value_Params.SA_K_len = SA_K_len;                       % SA 稳定性阈值
Value_Params.SA_K_max_inner = SA_K_max_inner;           % SA 每轮最大迭代次数
Value_Params.SA_T0_round = SA_T0_round;                 % SA 回合温度调度：初始温度
Value_Params.SA_beta_round = SA_beta_round;             % SA 回合温度调度：衰减系数
Value_Params.SA_T_base_round = SA_T_base_round;         % SA 回合温度调度：温度下界
Value_Params.SA_resource_confidence = SA_resource_confidence; % SA 初始构造置信度
Value_Params.SA_T_init_construction = SA_T_init_construction; % SA 初始构造温度

% SA_TabuEnhanced 专属参数
Value_Params.SA_Tabu_K_max_outer = SA_Tabu_K_max_outer;
Value_Params.SA_Tabu_K_max_inner = SA_Tabu_K_max_inner;
Value_Params.SA_Tabu_tenure = SA_Tabu_tenure;
Value_Params.SA_p_leave = SA_p_leave;  % 新增这一行

% ------------------ Qi2023算法参数 ------------------
% 效用函数参数
Value_Params.Qi_beta_m = Qi_beta_m;       % 边际效用权重
Value_Params.Qi_C_req = Qi_C_req;         % 资源需求成本系数
Value_Params.Qi_omega = Qi_omega;         % 惩罚/松弛项
Value_Params.Qi_omega_1 = Qi_omega_1;     % 权重参数 1
Value_Params.Qi_omega_2 = Qi_omega_2;     % 权重参数 2
Value_Params.Qi_omega_3 = Qi_omega_3;     % 权重参数 3

% 迭代控制参数
Value_Params.Qi_L_tabu = Qi_L_tabu;           % 禁忌表长度
Value_Params.Qi_K_len = Qi_K_len;             % 稳定性阈值
Value_Params.Qi_K_max_inner = Qi_K_max_inner; % 每轮最大迭代次数
Value_Params.Qi_Gamma_init = Qi_Gamma_init;   % 初始 Boltzmann 系数
Value_Params.Qi_Gamma_max = Qi_Gamma_max;     % 最大 Boltzmann 系数

% ------------------ Shi2024算法参数 ------------------
Value_Params.Shi_K_max_inner = Shi_K_max_inner; % 每轮最大迭代次数
Value_Params.Shi_K_len = Shi_K_len;             % 稳定性阈值


% ------------------ 算法10参数 ------------------
Value_Params.tabu_tenure = tabu_tenure;        % 禁忌期限



% ------------------ 通用参数 ------------------
Value_Params.seed = SEED;  % Random seed for reproducibility（用于复现实验）

% Scenario info（保存场景元数据，用于复现实验）
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
% 定义算法：ID、名称、主函数句柄、文件夹、绘图颜色
all_algorithms = {
    % 原始算法
    struct('id', 1, 'name', 'SA_Value',        'func', @SA_Value_main,        'folder', 'SA',                  'color', [0.2, 0.6, 0.8]); % 模拟退火
   %  struct('id', 2, 'name', 'Greedy baseline', 'func', @Greedy_Baseline_main, 'folder', 'comalg/Com_Baseline', 'color', [0.5, 0.5, 0.5]); % 贪心基线
    struct('id', 3, 'name', 'Huo2025',         'func', @Huo2025_main,         'folder', 'comalg/Com_Huo2025',  'color', [0.8, 0.2, 0.2]); % Huo2025
    struct('id', 4, 'name', 'Qi2023',          'func', @Qi2023_main,          'folder', 'comalg/Com_Qi2023',   'color', [0.2, 0.8, 0.2]); % Qi2023
    struct('id', 5, 'name', 'Shi2024',         'func', @Shi2024_main,         'folder', 'comalg/Com_Shi2024',  'color', [0.8, 0.4, 0.2]); % Shi2024 OCF
    % struct('id', 6, 'name', 'PSO',             'func', @PSO_main,             'folder', 'comalg/Com_PSO',      'color', [0.8, 0.8, 0.2]); % 粒子
    % SA 改进算法（ID 7-12）
   % struct('id', 7,  'name', 'SA_TabuEnhanced',    'func', @SA_Value_TabuEnhanced_main,    'folder', 'comalg/SA_TabuEnhance', 'color', [0.3, 0.7, 0.9]); % 禁忌搜索增强
   % struct('id', 8,  'name', 'SA_AdaptiveAlpha',   'func', @SA_Value_AdaptiveAlpha_main,   'folder', 'comalg/SA_Value_Adapt', 'color', [0.4, 0.5, 0.9]); % 自适应
    % 新算法
    struct('id', 9,  'name', 'Fang2025',           'func', @Fang2025_main,                 'folder', 'comalg/Com_Fang2025',  'color', [0.9, 0.3, 0.6]); % Fang2025
    struct('id', 10, 'name', 'SA_TabuEnhanced_Altruistic', 'func', @SA_Value_TabuEnhanced_Altruistic_main, 'folder', 'comalg/SA_TabuEnhance', 'color', [0.6, 0.3, 0.9]);
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

%% Run selected algorithms
% 运行选定算法并记录结果与耗时
fprintf('========================================================================\n');
fprintf('                    Running comparisons (开始运行对比)\n');
fprintf('========================================================================\n\n');

results = struct();
enabled_algorithms = {};
enabled_count = 0;

for i = 1:length(all_algorithms)
    alg = all_algorithms{i};
    % 若当前算法不在运行列表中，则跳过
    if ~ismember(alg.id, algorithms_to_run_ids)
        continue;
    end
    enabled_count = enabled_count + 1;
    enabled_algorithms{enabled_count} = alg;
    
    fprintf('----------------------------------------\n');
    fprintf('Running: [%d] %s\n', alg.id, alg.name);
    fprintf('----------------------------------------\n');
    
    try
        rng(SEED);  % 关键：重置随机种子，保证每个算法内部随机一致，公平对比
        
        % 设置当前算法的verbose级别
        
        tic;
        % 统一算法接口：(agents, tasks, AddPara, Value_Params)
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
        % 某算法失败：记录错误但不中断脚本
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
% 对比各算法指标：效用、成本、联盟数量、时间；并可绘图/保存
if enabled_count > 0
    fprintf('Analyzing results...\n');
    % compare_results 内部需要用到 M 等参数，因此传入 Value_Params
    comparison_stats = ResultProcessor.compare_results(results, Value_Params);
    
    fprintf('\n========================================================================\n');
    fprintf('                    Performance summary (性能汇总)\n');
    fprintf('========================================================================\n\n');
    
    % 汇总：效用、成本、联盟数量、运行时间
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
                stats.num_coalitions, ...  % 成功组建联盟次数（执行的任务数）
                stats.computation_time);
        else
            fprintf('%-20s | %10s | %10s | %10s | %10.2f\n', ...
                stats.name, 'error', 'error', 'error', stats.computation_time);
        end
    end
    fprintf('%s\n\n', repmat('-', 1, 80));
    
    % 任务完成细节
    fprintf('\nTask Completion Details (任务完成情况):\n');
    fprintf('%-20s | %15s | %15s\n', ...
        'Algorithm', 'Total Value', 'Avg Rate (%)');
    fprintf('%s\n', repmat('-', 1, 65));
    
    for i = 1:enabled_count
        stats = comparison_stats.(sprintf('alg%d', i));
        if isfield(stats, 'total_completion_score')
            fprintf('%-20s | %15.2f | %15.2f%%\n', ...
                stats.name, ...
                stats.total_completion_score, ...   % 完成任务的总价值
                stats.avg_task_completion * 100);   % 平均完成率（0-1 -> %）
        else
            fprintf('%-20s | %15s | %15s\n', ...
                stats.name, '-', '-');
        end
    end
    fprintf('%s\n\n', repmat('-', 1, 65));
    
    % 保存结果
    if save_results
        if ~exist('results', 'dir'); mkdir('results'); end
        timestamp = datestr(now, 'yyyymmdd_HHMMSS');
        
        % 生成算法名称缩写（用于文件名）
        abbr_patterns = {'SA', 'Qi', 'Huo', 'Shi', 'PSO', 'Greedy'};
        abbr_values = {'SA', 'Qi', 'Huo', 'Shi', 'PSO', 'Grd'};
        alg_abbr = cell(1, enabled_count);
        for i = 1:enabled_count
            alg_name = enabled_algorithms{i}.name;
            idx = find(cellfun(@(p) contains(alg_name, p), abbr_patterns), 1, 'first');
            if isempty(idx)
                alg_abbr{i} = regexprep(alg_name, '\s+', '');
            else
                alg_abbr{i} = abbr_values{idx};
            end
        end
        alg_names_short = strjoin(alg_abbr, '+');
        % 新文件名格式：comparison_N6_M10_SA+Qi_20260203_164611.mat
        filename = sprintf('results/comparison_N%d_M%d_%s_%s.mat', ...
            N, M, alg_names_short, timestamp);
        fprintf('Saving results to: %s\n', filename);
        
        % 保存关键变量，便于复现实验与后续分析
        save(filename, 'results', 'comparison_stats', 'agents', 'tasks', ...
            'Value_Params', 'WORLD', 'scenario_info', 'enabled_algorithms');
        fprintf('results saved\n\n');
    end
    
    
end

