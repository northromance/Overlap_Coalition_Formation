clear; clc;
feature('DefaultCharacterSet', 'UTF-8');

%% ===== 实验 E：单次可视化（图5）=====
% N=10, M=10, K=6, seed=1001
% 只运行 OCF_SAtabu (算法 7)
% 保存：final_SC, agents, tasks, WorldSim timing, task_completion_degrees

%% ===== 配置 =====
SEED = 1001;
N    = 10;
M    = 10;
K    = 6;

AddPara.verbose              = 1;
AddPara.enable_belief_update = true;
AddPara.control              = 1;

num_rounds      = 100;
MaxIter         = 100;
obs_times       = 50;
task_values     = [800, 1000, 1500];
num_task_types  = length(task_values);

resource_confidence = 0.7;

Huo_L_tabu       = 10;
Huo_K_stable_max = 10;

Qi_L_tabu       = 10;
Qi_K_stable_max = 10;
Qi_Gamma_init   = 1;
Qi_Gamma_max    = 50;
Qi_p_leave      = 0.3;

Shi_L_tabu       = 10;
Shi_K_stable_max = 10;
Shi_Gamma_init   = 1;
Shi_Gamma_max    = 50;
Shi_p_leave      = 0.3;

OCF_T0_round            = 100;
OCF_alpha               = 0.9;
OCF_Tmin                = 0.01;
OCF_T_decay             = 0.8;
OCF_T_min_round         = 2;
OCF_T_init_construction = 2;
OCF_K_stable_max        = 10;
OCF_tabu_tenure         = 20;
OCF_p_leave             = 0.3;

Common_Params = struct();
Common_Params.max_inner_iter      = MaxIter;
Common_Params.resource_confidence = resource_confidence;

Algorithm_Params = struct();
Algorithm_Params.Huo = struct('L_tabu', Huo_L_tabu, 'K_stable_max', Huo_K_stable_max);
Algorithm_Params.Qi = struct('L_tabu', Qi_L_tabu, 'K_stable_max', Qi_K_stable_max, ...
    'Gamma_init', Qi_Gamma_init, 'Gamma_max', Qi_Gamma_max, 'p_leave', Qi_p_leave);
Algorithm_Params.Shi = struct('L_tabu', Shi_L_tabu, 'K_stable_max', Shi_K_stable_max, ...
    'Gamma_init', Shi_Gamma_init, 'Gamma_max', Shi_Gamma_max, 'p_leave', Shi_p_leave);
Algorithm_Params.OCF = struct('T0_round', OCF_T0_round, 'alpha', OCF_alpha, ...
    'Tmin', OCF_Tmin, 'T_decay', OCF_T_decay, 'T_min_round', OCF_T_min_round, ...
    'T_init_construction', OCF_T_init_construction, 'K_stable_max', OCF_K_stable_max, ...
    'tabu_tenure', OCF_tabu_tenure, 'p_leave', OCF_p_leave);

WORLD_XMIN = 0; WORLD_XMAX = 100;
WORLD_YMIN = 0; WORLD_YMAX = 100;
WORLD_ZMIN = 0; WORLD_ZMAX = 0;
agent_velocity       = 2;
agent_detprob_min    = 0.95;
agent_detprob_max    = 1.0;
agent_Emax_min       = 300;
agent_Emax_range     = 50;
agent_fuel           = 1;
agent_wait_fuel      = 0.5;
agent_beta           = 1;
min_resource_value   = 0;
max_resource_value   = 4;
task_type1_demand_max = 4;
task_type2_demand_max = 6;
task_type3_demand_max = 8;
resource_exec_time   = [50 65 50 60 35 45];

%% ===== 路径初始化 =====
script_dir = fileparts(mfilename('fullpath'));
addpath(fullfile(script_dir, 'Main_fun'));
addpath(fullfile(script_dir, 'comalg', 'alg7_OCF_SAtabu'));

%% ===== 输出目录 =====
results_dir = fullfile(script_dir, 'results', 'batch');
if ~exist(results_dir, 'dir')
    mkdir(results_dir);
end

%% ===== 构建场景 =====
fprintf('========================================================================\n');
fprintf('  Single_Viz  |  N=%d M=%d K=%d seed=%d\n', N, M, K, SEED);
fprintf('========================================================================\n\n');

rng('default');
rng(SEED);

WORLD.XMIN = WORLD_XMIN; WORLD.XMAX = WORLD_XMAX;
WORLD.YMIN = WORLD_YMIN; WORLD.YMAX = WORLD_YMAX;
WORLD.ZMIN = WORLD_ZMIN; WORLD.ZMAX = WORLD_ZMAX;
WORLD.value = task_values;

task_type_demands = zeros(num_task_types, K);
task_type_demands(1, :) = randi([0, task_type1_demand_max], 1, K);
task_type_demands(2, :) = randi([0, task_type2_demand_max], 1, K);
task_type_demands(3, :) = randi([0, task_type3_demand_max], 1, K);

task_type_duration_by_resource = zeros(num_task_types, K);
for t = 1:num_task_types
    needed = task_type_demands(t, :) > 0;
    task_type_duration_by_resource(t, needed) = resource_exec_time(needed);
end

task_priorities = randperm(M);
tasks = struct();
for j = 1:M
    tasks(j).id       = j;
    tasks(j).priority = task_priorities(j);
    tasks(j).x        = round(rand() * (WORLD.XMAX - WORLD.XMIN) + WORLD.XMIN);
    tasks(j).y        = round(rand() * (WORLD.YMAX - WORLD.YMIN) + WORLD.YMIN);
    tasks(j).type     = randi(num_task_types, 1, 1);
    tasks(j).value    = WORLD.value(tasks(j).type);
    tasks(j).resource_demand      = task_type_demands(tasks(j).type, :);
    tasks(j).duration_by_resource = task_type_duration_by_resource(tasks(j).type, :);
    tasks(j).duration = max(tasks(j).duration_by_resource);
    tasks(j).WORLD    = WORLD;
end

agents = struct();
for i = 1:N
    agents(i).id        = i;
    agents(i).vel       = agent_velocity;
    agents(i).x         = round(rand() * (WORLD.XMAX - WORLD.XMIN) + WORLD_XMIN);
    agents(i).y         = round(rand() * (WORLD.YMAX - WORLD.YMIN) + WORLD_YMIN);
    agents(i).detprob   = agent_detprob_min + (agent_detprob_max - agent_detprob_min) * rand();
    agents(i).resources = randi([min_resource_value, max_resource_value], K, 1);
    agents(i).Emax      = agent_Emax_min + agent_Emax_range * rand();
    agents(i).fuel      = agent_fuel;
    agents(i).wait_fuel = agent_wait_fuel;
    agents(i).beta      = agent_beta;
end

Value_Params = OCFUtils.init_value_params(N, M, K, num_task_types, task_type_demands, ...
    OCF_alpha, OCF_Tmin, OCF_K_stable_max, obs_times, num_rounds);
Value_Params = OCFUtils.apply_experiment_params(Value_Params, Common_Params, Algorithm_Params, SEED);

%% ===== 运行算法 =====
fprintf('运行 OCF_SAtabu...\n');
rng(SEED);
tic;
[Value_data, history_data] = OCF_SAtabu_global_main(agents, tasks, AddPara, Value_Params);
comp_time = toc;
fprintf('完成，耗时 %.2f s\n\n', comp_time);

%% ===== 提取最终 SC =====
num_r    = length(history_data.rounds);
final_SC = history_data.rounds(num_r).SC;

%% ===== 计算全局时间同步结果（WorldSim，调用一次）=====
fprintf('计算时间同步...\n');
all_agents_results = WorldSim.calc_all_agents_with_global_sync(final_SC, agents, tasks, Value_Params);
fprintf('完成。\n\n');

%% ===== 计算任务完成度 =====
eps_val = 1e-6;
[coalition_utility, total_global_cost, total_completed_value, task_completion_degrees] = ...
    UtilityEvaluator.evaluate_coalition_metrics(final_SC, agents, tasks, Value_Params, eps_val);

%% ===== 打印摘要 =====
fprintf('--- 最终结果摘要 ---\n');
fprintf('  联盟效用 = %.2f\n', coalition_utility);
fprintf('  总成本   = %.2f\n', total_global_cost);
fprintf('  完成价值 = %.2f\n', total_completed_value);
fprintf('  平均完成度 = %.3f\n', mean(task_completion_degrees));
fprintf('\n  各任务完成度:\n');
for j = 1:M
    fprintf('    任务 %2d (type=%d, val=%4d): %.3f\n', ...
        j, tasks(j).type, tasks(j).value, task_completion_degrees(j));
end
fprintf('\n  各智能体时间分量:\n');
fprintf('  %-6s | %-10s | %-10s | %-10s | %-20s\n', ...
    'Agent', 't_fly', 't_wait', 't_exec', 'task_seq');
for i = 1:N
    r = all_agents_results(i);
    seq_str = mat2str(r.task_sequence);
    fprintf('  %-6d | %-10.2f | %-10.2f | %-10.2f | %-20s\n', ...
        i, r.t_fly_total, r.t_wait_total, r.t_exec_total, seq_str);
end
fprintf('\n');

%% ===== 组装 viz_data =====
viz_data.N    = N;
viz_data.M    = M;
viz_data.K    = K;
viz_data.seed = SEED;

% 智能体结构体数组（去除冗余字段，保留绘图所需）
viz_data.agents = agents;  % struct array [1×N]，含 id/x/y/vel/resources/fuel/wait_fuel/beta

% 任务结构体数组
viz_data.tasks  = tasks;   % struct array [1×M]，含 id/x/y/type/value/resource_demand

% 最终分配矩阵（图5a：资源热力图 / 分配矩阵）
viz_data.final_SC = final_SC;  % cell{M×1}，SC{m} = [N×K]

% 时间同步结果（图5b：Gantt图 / 路线图）
% all_agents_results(i) 含 t_fly_total/t_wait_total/t_exec_total/task_sequence/start_times/execution_times
viz_data.timing = all_agents_results;  % struct array [1×N]

% 任务完成度
viz_data.task_completion_degrees = task_completion_degrees;  % [M×1]

% 逐轮收敛曲线（辅助参考）
convergence_utility = nan(num_r, 1);
for r = 1:num_r
    convergence_utility(r) = history_data.rounds(r).coalition_utility;
end
viz_data.convergence_utility = convergence_utility;  % [num_r×1]

% 全局指标
viz_data.coalition_utility       = coalition_utility;
viz_data.total_global_cost       = total_global_cost;
viz_data.total_completed_value   = total_completed_value;
viz_data.computation_time        = comp_time;

%% ===== 保存 .mat =====
timestamp = datestr(now, 'yyyymmdd_HHMMSS');
filename  = fullfile(results_dir, sprintf('visualize_%s.mat', timestamp));

fprintf('保存至: %s\n', filename);
save(filename, 'viz_data', '-v7.3');
fprintf('保存完成。\n\n');

%% ===== 快速验证 =====
fprintf('--- 验证检查 ---\n');
fprintf('  final_SC 是否非空: %d 个任务有联盟\n', ...
    sum(cellfun(@(sc) any(sc(:) > 1e-9), final_SC)));
fprintf('  timing(1).task_sequence = %s\n', mat2str(all_agents_results(1).task_sequence));
if ~isempty(all_agents_results(1).task_sequence)
    fprintf('  timing 结果: OK\n');
else
    fprintf('  WARNING: agent 1 的 task_sequence 为空\n');
end
fprintf('\n');
