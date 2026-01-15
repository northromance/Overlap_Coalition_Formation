clear; clc; close all;

%% ========================================================================
%  多算法对比框�? - 联盟形成算法性能评估
%  
%  功能说明�?
%  1. 使用统一的场景（相同的SEED）初始化智能体、任务、资�?
%  2. 在同一场景下运行多个不同的联盟形成算法
%  3. 对比各算法的性能指标（总效用、计算时间、联盟数量等�?
%  4. 生成对比图表和统计报�?
%  5. 保存所有结果用于后续分�?
%
%  使用说明�?
%  - �? algorithms_to_run 中添加或注释要对比的算法
%  - 算法主函数应放在对应�? Com_XXX 文件夹中
%  - 每个算法应返回统一格式�? Value_data �? history_data
% ========================================================================

fprintf('\n');
fprintf('========================================================================\n');
fprintf('                    多算法对比框架启动\n');
fprintf('========================================================================\n\n');

%% 添加路径
% 核心函数路径
addpath("Main_fun\")              % 场景初始化、结果对比等核心函数
addpath("SA\")                    % SA算法
addpath("plots\")                 % 可视化函�?
% 添加对比算法路径
addpath("Com_Baseline\")          % 贪心基线算法
addpath("Com_Huo2025\")           % Huo2025算法
addpath("Com_Qi2023\")            % Qi2023算法
addpath("Com_Qin2025\")           % Qin2025算法

%% ========================================================================
%  场景配置参数（可直接修改用于调试�?
%% ========================================================================
% 基本参数
SEED = 2437;                    % 随机数种子（保证所有算法使用相同场景）
N = 6;                          % 智能体数�?
M = 10;                         % 任务数量
K = 6;                          % 资源类型数量

% 算法选择
algorithms_to_run_ids = [1,2,3,4,5];  % 1=SA_Value, 2=贪心, 3=Huo2025, 4=Qi2023, 5=PSO(Qin2025)

% 显示和保存设�?
save_results = true;            % 是否保存结果
show_plots = true;              % 是否显示图表
verbose = true;                 % 是否详细输出

% 世界空间参数
WORLD_XMIN = 0;
WORLD_XMAX = 100;
WORLD_YMIN = 0;
WORLD_YMAX = 100;
WORLD_ZMIN = 0;
WORLD_ZMAX = 0;
task_values = [800, 1000, 1500];  % 任务价值候选集（对�?3种任务类型）

% 智能体参�?
agent_velocity = 2;
agent_detprob_min = 0.9;
agent_detprob_max = 1.0;
agent_Emax_min = 300;
agent_Emax_range = 50;
agent_fuel = 1;
agent_beta = 1;
min_resource_value = 2;         % 智能体资源最小�?
max_resource_value = 4;         % 智能体资源最大�?

% 任务资源需求参数（每种任务类型的资源需求范围）
task_type1_demand_max = 4;      % 类型1任务：低需�?
task_type2_demand_max = 6;      % 类型2任务：中等需�?
task_type3_demand_max = 8;      % 类型3任务：高需�?

% 资源执行时间
resource_exec_time = [50 65 50 60 35 45];

% 模拟退火参�?
SA_Temperature = 100.0;
SA_alpha = 0.95;
SA_Tmin = 0.01;
SA_max_stable_iterations = 5;

% 观测和博弈参数（主要用于SA_Value算法�?
obs_times = 50;                 % 每轮每个任务的观测次数（SA算法专用�?
num_rounds = 50;                % 博弈轮数（SA算法专用；Huo算法会使用此参数，默�?50�?
resource_confidence = 0.7;      % 资源需求分位数置信度（SA算法专用�?


% Qi2023算法效用函数参数
Qi_beta_m = 1.0;                % Sigmoid函数陡峭度参�?
Qi_C_req = 0.5;                 % 需求阈�?
Qi_omega = 0.1;                 % Sigmoid函数偏移参数
Qi_omega_1 = 1.0;               % 资源完成度权�?
Qi_omega_2 = 0.01;              % 距离成本权重
Qi_omega_3 = 0.001;             % 能量损耗权�?

%% ========================================================================
%  场景初始化（使用上述参数�?
%% ========================================================================
fprintf('正在初始化测试场�?...\n');
fprintf('  - 随机种子: %d\n', SEED);
fprintf('  - 智能体数�?: %d\n', N);
fprintf('  - 任务数量: %d\n', M);
fprintf('  - 资源类型数量: %d\n', K);
fprintf('  - 博弈轮数: %d\n\n', num_rounds);

tic;
rand('seed', SEED);

% 初始化WORLD结构
WORLD.XMIN = WORLD_XMIN;
WORLD.XMAX = WORLD_XMAX;
WORLD.YMIN = WORLD_YMIN;
WORLD.YMAX = WORLD_YMAX;
WORLD.ZMIN = WORLD_ZMIN;
WORLD.ZMAX = WORLD_ZMAX;
WORLD.value = task_values;

% 初始化任务类型资源需�?
num_task_types = length(task_values);
task_type_demands = zeros(num_task_types, K);
task_type_demands(1, :) = randi([0, task_type1_demand_max], 1, K);
task_type_demands(2, :) = randi([0, task_type2_demand_max], 1, K);
task_type_demands(3, :) = randi([0, task_type3_demand_max], 1, K);

% 初始化任务执行时�?
task_type_duration_by_resource = zeros(num_task_types, K);
for t = 1:num_task_types
    needed = task_type_demands(t, :) > 0;
    task_type_duration_by_resource(t, needed) = resource_exec_time(needed);
end

% 初始化任�?
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
    tasks(j).duration = max(tasks(j).duration_by_resource);
    tasks(j).WORLD = WORLD;
end

% 初始化智能体
for i = 1:N
    agents(i).id = i;
    agents(i).vel = agent_velocity;
    agents(i).x = round(rand(1) * (WORLD.XMAX - WORLD.XMIN) + WORLD.XMIN);
    agents(i).y = round(rand(1) * (WORLD.YMAX - WORLD.YMIN) + WORLD.YMIN);
    agents(i).detprob = agent_detprob_min + (agent_detprob_max - agent_detprob_min) * rand();
    agents(i).resources = randi([min_resource_value, max_resource_value], K, 1);
    agents(i).Emax = agent_Emax_min + agent_Emax_range * rand();
    agents(i).fuel = agent_fuel;
    agents(i).beta = agent_beta;
end

% 初始化算法参�?
Value_Params = init_value_params(N, M, K, num_task_types, task_type_demands, ...
                                  SA_Temperature, SA_alpha, SA_Tmin, SA_max_stable_iterations, ...
                                  obs_times, num_rounds, resource_confidence);

% 添加Qi2023算法参数
Value_Params.Qi_beta_m = Qi_beta_m;
Value_Params.Qi_C_req = Qi_C_req;
Value_Params.Qi_omega = Qi_omega;
Value_Params.Qi_omega_1 = Qi_omega_1;
Value_Params.Qi_omega_2 = Qi_omega_2;
Value_Params.Qi_omega_3 = Qi_omega_3;

% 场景信息
scenario_info.SEED = SEED;
scenario_info.N = N;
scenario_info.M = M;
scenario_info.K = K;
scenario_info.num_task_types = num_task_types;
scenario_info.task_type_demands = task_type_demands;
scenario_info.resource_exec_time = resource_exec_time;
scenario_info.timestamp = datetime('now');

init_time = toc;
fprintf('场景初始化完�? (耗时: %.2f�?)\n\n', init_time);

%% 定义所有可用的算法
% 每个算法需要指定：
%   - name: 算法名称（用于显示）
%   - func: 算法主函数句�?
%   - folder: 算法文件所在文件夹
%   - color: 图表颜色
all_algorithms = {
    % 算法1: SA_Value (本文)
    struct('id', 1, ...
           'name', 'SA_Value (本文)', ...
           'func', @SA_Value_main, ...
           'folder', 'SA', ...
           'color', [0.2, 0.6, 0.8]);
    
    % 算法2: 贪心基线算法
    struct('id', 2, ...
           'name', '贪心基线', ...
           'func', @Greedy_Baseline_main, ...
           'folder', 'Com_Baseline', ...
           'color', [0.5, 0.5, 0.5]);
    
    % 算法3: Huo2025 算法
    struct('id', 3, ...
           'name', 'Huo2025算法', ...
           'func', @Huo2025_main, ...
           'folder', 'Com_Huo2025', ...
           'color', [0.8, 0.2, 0.2]);
    
    % 算法4: Qi2023 算法
    struct('id', 4, ...
           'name', 'Qi2023算法', ...
           'func', @Qi2023_main, ...
           'folder', 'Com_Qi2023', ...
           'color', [0.2, 0.8, 0.2]);
    
    % 算法5: Qin2025 PSO 算法
    struct('id', 5, ...
           'name', 'Qin2025 PSO算法', ...
           'func', @Qin2025_main, ...
           'folder', 'Com_Qin2025', ...
           'color', [0.8, 0.8, 0.2]);
};

% 显示可用算法列表
fprintf('可用算法列表:\n');
for i = 1:length(all_algorithms)
    alg = all_algorithms{i};
    if ismember(alg.id, algorithms_to_run_ids)
        fprintf('  [%d] %s ? (已选择)\n', alg.id, alg.name);
    else
        fprintf('  [%d] %s\n', alg.id, alg.name);
    end
end
fprintf('\n当前选择运行: [%s]\n\n', num2str(algorithms_to_run_ids));

%% 准备AddPara参数（根据原Main.m�?
AddPara.control = 1;

%% 运行所有选中的算�?
fprintf('========================================================================\n');
fprintf('                    开始运行算法对比\n');
fprintf('========================================================================\n\n');

results = struct();
enabled_algorithms = {};
enabled_count = 0;

for i = 1:length(all_algorithms)
    alg = all_algorithms{i};
    
    % 检查算法是否在选择列表�?
    if ~ismember(alg.id, algorithms_to_run_ids)
        continue;  % 跳过未选择的算�?
    end
    
    enabled_count = enabled_count + 1;
    enabled_algorithms{enabled_count} = alg;
    
    fprintf('----------------------------------------\n');
    fprintf('正在运行: [%d] %s\n', alg.id, alg.name);
    fprintf('----------------------------------------\n');
    
    try
        % 重置随机数种子（确保每个算法看到相同的随机序列）
        rand('seed', SEED);
        
        % 运行算法
        tic;
        [Value_data, history_data] = alg.func(agents, tasks, AddPara, Value_Params);
        comp_time = toc;
        
        % 保存结果
        results.(sprintf('alg%d', enabled_count)).name = alg.name;
        results.(sprintf('alg%d', enabled_count)).Value_data = Value_data;
        results.(sprintf('alg%d', enabled_count)).history_data = history_data;
        results.(sprintf('alg%d', enabled_count)).computation_time = comp_time;
        results.(sprintf('alg%d', enabled_count)).color = alg.color;
        
        fprintf('? %s 完成 (耗时: %.2f�?)\n\n', alg.name, comp_time);
        
    catch ME
        fprintf('? %s 运行失败:\n', alg.name);
        fprintf('  错误: %s\n', ME.message);
        fprintf('  位置: %s (�?%d�?)\n\n', ME.stack(1).name, ME.stack(1).line);
        
        % 保存错误信息
        results.(sprintf('alg%d', enabled_count)).name = alg.name;
        results.(sprintf('alg%d', enabled_count)).error = ME;
        results.(sprintf('alg%d', enabled_count)).computation_time = NaN;
    end
end

fprintf('========================================================================\n');
fprintf('                    所有算法运行完成\n');
fprintf('========================================================================\n\n');

%% 对比分析结果
if enabled_count > 0
    fprintf('正在进行结果对比分析...\n');
    comparison_stats = compare_results(results, agents, tasks, Value_Params);
    
    %% 显示对比统计�?
    fprintf('\n========================================================================\n');
    fprintf('                    算法性能对比统计\n');
    fprintf('========================================================================\n\n');
    
    % 创建对比表格 - 基础指标
    fprintf('%-20s | %10s | %10s | %10s | %10s\n', ...
            '算法名称', '总效�?', '联盟数量', '归一化完成率', '计算时间(�?)');
    fprintf('%s\n', repmat('-', 1, 80));
    
    for i = 1:enabled_count
        stats = comparison_stats.(sprintf('alg%d', i));
        if isfield(stats, 'total_utility')
            fprintf('%-20s | %10.2f | %10d | %10.2f%% | %10.2f\n', ...
                    stats.name, stats.total_utility, stats.num_coalitions, ...
                    stats.normalized_completion_rate, stats.computation_time);
        else
            fprintf('%-20s | %10s | %10s | %10s | %10.2f\n', ...
                    stats.name, '错误', '错误', '错误', stats.computation_time);
        end
    end
    fprintf('%s\n\n', repmat('-', 1, 80));
    
    % 创建详细任务完成度表�?
    fprintf('\n任务完成度详细统�?:\n');
    fprintf('%-20s | %10s | %10s | %10s | %10s\n', ...
            '算法名称', '等效完成�?', '完全完成', '部分完成', '平均完成�?');
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
    
    %% 绘制对比图表
    if show_plots && enabled_count > 1
        fprintf('正在绘制对比图表...\n');
        plot_algorithm_comparison(results, comparison_stats, enabled_count);
    end
    
    %% 保存结果
    if save_results
        % 确保results文件夹存�?
        if ~exist('results', 'dir')
            mkdir('results');
        end
        
        timestamp = datestr(now, 'yyyymmdd_HHMMSS');
        filename = sprintf('results/comparison_results_seed%d_%s.mat', SEED, timestamp);
        
        fprintf('正在保存对比结果�?: %s\n', filename);
        save(filename, 'results', 'comparison_stats', 'agents', 'tasks', ...
             'Value_Params', 'WORLD', 'scenario_info', 'enabled_algorithms');
        fprintf('? 结果已保存\n\n');
    end
else
    fprintf('警告: 没有启用任何算法进行对比\n\n');
end

fprintf('========================================================================\n');
fprintf('                    对比框架运行完成\n');
fprintf('========================================================================\n\n');

