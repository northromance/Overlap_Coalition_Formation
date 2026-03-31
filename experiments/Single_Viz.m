clear; clc;
feature('DefaultCharacterSet', 'UTF-8');

%% =========================================================================
%  实验 E：单次可视化（Single_Viz）
%
%  画图用途：
%    图5a — 最终联盟结构资源分配矩阵（每个任务的 SC{m} 热图）
%    图5b — 智能体时序甘特图（t_fly / t_wait / t_exec 三段）
%    图5c — 收敛曲线（coalition_utility vs 轮次）
%
%  保存数据（results/batch/visualize/N{N}_M{M}_K{K}_seed{seed}_{ts}.mat）：
%    viz_data
%      .N / .M / .K / .seed
%      .agents                  struct array [1×N]，含位置、资源、能量等字段
%      .tasks                   struct array [1×M]，含坐标、类型、需求等字段
%      .final_SC                cell{M×1}，SC{m}=[N×K]，最终联盟分配矩阵 → 图5a
%      .timing                  struct array [1×N]，含 t_fly/t_wait/t_exec 时间 → 图5b
%      .task_completion_degrees [M×1]，各任务完成度
%      .convergence_utility     [num_rounds×1]，每轮联盟效用 → 图5c
%      .coalition_utility       标量，最终联盟效用
%      .total_global_cost       标量，最终全局成本
%      .total_completed_value   标量，最终完成价值
%      .computation_time        算法运行耗时（秒）
%
%  注：本脚本只跑单个场景（固定 seed），适合单次深度可视化分析
%% =========================================================================

%% ===== 路径初始化（须在 Exp_Params 之前）=====
script_dir = fileparts(mfilename('fullpath'));
root_dir   = fileparts(script_dir);

%% ===== 加载共享参数 =====
run(fullfile(script_dir, 'Exp_Params.m'));

%% ===== 实验专属配置 =====
cfg = Exp_Config.SingleViz;
SEED = cfg.SEED;
N = cfg.N;
M = cfg.M;
K = cfg.K;
num_rounds = Exp_Config.Common.num_rounds;

%% ===== 附加控制参数 =====
AddPara = cfg.AddPara;

%% ===== 路径加入 =====
addpath(fullfile(root_dir, 'Main_fun'));
addpath(fullfile(root_dir, 'comalg', 'alg7_OCF_SAtabu'));

%% ===== 输出目录 =====
results_dir = fullfile(root_dir, 'results', 'batch', 'visualize');
if ~exist(results_dir, 'dir'), mkdir(results_dir); end

%% ===== 构建场景 =====
fprintf('========================================================================\n');
fprintf('  Single_Viz  |  N=%d M=%d K=%d seed=%d\n', N, M, K, SEED);
fprintf('========================================================================\n\n');

scenario_cfg = Exp_Config.ScenarioCfg;
scenario_cfg.N = N;
scenario_cfg.M = M;
scenario_cfg.K = K;
[WORLD, tasks, agents, task_type_demands] = build_scenario(SEED, scenario_cfg); %#ok<ASGLU>

Value_Params = OCFUtils.init_value_params(N, M, K, num_task_types, task_type_demands, ...
    OCF_alpha, OCF_Tmin, OCF_K_stable_max, obs_times, num_rounds);
Value_Params = OCFUtils.apply_experiment_params(Value_Params, Common_Params, Algorithm_Params, SEED);

singleviz_run = struct();
singleviz_run.N = N;
singleviz_run.M = M;
singleviz_run.K = K;
singleviz_run.seed = SEED;
singleviz_run.scenario_cfg = scenario_cfg;
singleviz_run.AddPara = AddPara;
singleviz_run.Value_Params = Value_Params;
singleviz_run.task_type_demands = task_type_demands;
singleviz_run.num_rounds = num_rounds;
singleviz_run.max_inner_iter = MaxIter;
singleviz_run.obs_times = obs_times;
singleviz_run.num_task_types = num_task_types;
singleviz_run.algorithm_name = 'OCF_SAtabu';

exp_params_snapshot = build_exp_params_snapshot(struct( ...
    'exp_params_source', fullfile(script_dir, 'Exp_Params.m'), ...
    'experiment_script', fullfile(script_dir, 'Single_Viz.m'), ...
    'experiment_name', 'Single_Viz', ...
    'common_config', Exp_Config.Common, ...
    'scenario_cfg_base', Exp_Config.ScenarioCfg, ...
    'experiment_cfg', cfg, ...
    'common_params', Common_Params, ...
    'algorithm_params', Algorithm_Params, ...
    'effective_run', singleviz_run));

%% ===== 运行算法 =====
fprintf('运行 OCF_SAtabu...\n');
rng(SEED);
tic;
[~, history_data] = OCF_SAtabu_global_main(agents, tasks, AddPara, Value_Params);
comp_time = toc;
fprintf('完成，耗时 %.2f s\n\n', comp_time);

%% ===== 提取最终 SC =====
num_r    = length(history_data.rounds);
final_SC = history_data.rounds(num_r).SC;

%% ===== 计算全局时间同步（只调用一次）=====
fprintf('计算时间同步...\n');
all_agents_results = WorldSim.calc_all_agents_with_global_sync(agents, tasks, Value_Params, final_SC);
fprintf('完成。\n\n');

%% ===== 计算任务完成度与全局指标 =====
eps_val = 1e-6;
[coalition_utility, total_global_cost, total_completed_value, task_completion_degrees] = ...
    UtilityEvaluator.evaluate_coalition_metrics(final_SC, agents, tasks, Value_Params, eps_val);

%% ===== 打印摘要 =====
fprintf('--- 最终结果摘要 ---\n');
fprintf('  联盟效用   = %.2f\n', coalition_utility);
fprintf('  总成本     = %.2f\n', total_global_cost);
fprintf('  完成价值   = %.2f\n', total_completed_value);
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
    fprintf('  %-6d | %-10.2f | %-10.2f | %-10.2f | %-20s\n', ...
        i, r.t_fly_total, r.t_wait_total, r.t_exec_total, mat2str(r.task_sequence));
end
fprintf('\n');

%% ===== 组装 viz_data =====
viz_data.N    = N;
viz_data.M    = M;
viz_data.K    = K;
viz_data.seed = SEED;

viz_data.agents = agents;   % struct array [1×N]
viz_data.tasks  = tasks;    % struct array [1×M]

viz_data.final_SC                = final_SC;               % cell{M×1}，SC{m}=[N×K] → 图5a
viz_data.timing                  = all_agents_results;     % struct array [1×N]      → 图5b
viz_data.task_completion_degrees = task_completion_degrees; % [M×1]

convergence_utility = nan(num_r, 1);
for r = 1:num_r
    convergence_utility(r) = history_data.rounds(r).coalition_utility;
end
viz_data.convergence_utility   = convergence_utility;      % → 图5c
viz_data.coalition_utility     = coalition_utility;
viz_data.total_global_cost     = total_global_cost;
viz_data.total_completed_value = total_completed_value;
viz_data.computation_time      = comp_time;
viz_data.exp_params_snapshot   = exp_params_snapshot;

%% ===== 保存 .mat =====
timestamp = datestr(now, 'yyyymmdd_HHMMSS');
filename  = fullfile(results_dir, sprintf('N%d_M%d_K%d_seed%d_%s.mat', ...
    N, M, K, SEED, timestamp));

fprintf('保存至: %s\n', filename);
save(filename, 'viz_data', '-v7.3');
fprintf('保存完成。\n\n');

%% ===== 验证检查 =====
fprintf('--- 验证检查 ---\n');
num_active = sum(cellfun(@(sc) any(sc(:) > 1e-9), final_SC));
fprintf('  final_SC：%d / %d 个任务有联盟分配\n', num_active, M);
fprintf('  timing(1).task_sequence = %s\n', mat2str(all_agents_results(1).task_sequence));
if ~isempty(all_agents_results(1).task_sequence)
    fprintf('  timing 结果: OK\n');
else
    fprintf('  WARNING: agent 1 的 task_sequence 为空\n');
end
fprintf('\n');
