clear; clc;
feature('DefaultCharacterSet', 'UTF-8');

%% =========================================================================
%  实验 B：变 M 规模（Batch_VaryM）
%
%  画图用途：
%    图1c — 最终联盟效用 vs M（各算法对比）
%    图1d — 最终平均任务完成度 vs M
%    收敛曲线图 — convergence_utility/cost/completion vs 轮次
%
%  保存数据（results/batch/varyM/{run_timestamp}_N{N}_M{min}-{max}_K{K}_S{nSeeds}/）：
%    run_config.mat            — 本次实验配置快照 + Exp_Params 关键参数快照
%    progress_status.mat       — 已完成的 M / seed / algorithm 进度表
%    by_alg/{AlgName}/M{xxx}/N{N}_M{M}_seed{yyyy}.mat
%                              — 每跑完一个算法立即保存一份结果，便于中断
%    aggregated/
%                              — 保留给 Python 绘图阶段写延迟聚合缓存，不在本脚本中生成总表
%
%  聚合总表中的数据结构：
%    scale_M_results{mi, si}  — 二维 cell [M数量 × seed数量]
%      .M / .seed / .success / .error
%      .algs.(算法名).final_utility        最终联盟效用（图1c 的值）
%      .algs.(算法名).final_cost           最终全局成本（图1d 的值）
%      .algs.(算法名).final_completion     最终平均任务完成度
%      .algs.(算法名).convergence_utility  [num_rounds×1] 每轮效用收敛曲线
%      .algs.(算法名).convergence_cost     [num_rounds×1] 每轮成本曲线
%      .algs.(算法名).convergence_completion [num_rounds×1] 每轮完成度曲线
%      .algs.(算法名).computation_time     算法运行耗时（秒）
%    scale_config — 本次实验参数快照
%
%  注：单次可视化请运行 Single_Viz.m
%% =========================================================================

%% ===== 路径初始化（须在 Exp_Params 之前）=====
script_dir = fileparts(mfilename('fullpath'));
root_dir   = fileparts(script_dir);

%% ===== 加载共享参数 =====
run(fullfile(script_dir, 'Exp_Params.m'));

%% ===== 实验专属配置 =====
cfg = Exp_Config.VaryM;
SEEDS = cfg.SEEDS;
M_VALUES = cfg.M_VALUES;
N = cfg.N;
K = cfg.K;
algorithms_to_run_ids = cfg.algorithms_to_run_ids;
num_rounds = Exp_Config.Common.num_rounds;

%% ===== 附加控制参数 =====
AddPara = cfg.AddPara;

%% ===== 路径加入 =====
addpath(fullfile(root_dir, 'Main_fun'));
addpath(fullfile(root_dir, 'comalg', 'alg1_SA'));
addpath(fullfile(root_dir, 'comalg', 'alg2_Huo2025'));
addpath(fullfile(root_dir, 'comalg', 'alg3_Qi2023'));
addpath(fullfile(root_dir, 'comalg', 'alg4_Shi2024'));
addpath(fullfile(root_dir, 'comalg', 'alg7_OCF_SAtabu'));

%% ===== 输出目录 =====
results_root_dir = fullfile(root_dir, 'results', 'batch', 'varyM');
if ~exist(results_root_dir, 'dir'), mkdir(results_root_dir); end

%% ===== 算法注册表 =====
all_algorithms = get_all_algorithms();

enabled_algorithms = {};
for i = 1:length(all_algorithms)
    if ismember(all_algorithms{i}.id, algorithms_to_run_ids)
        enabled_algorithms{end+1} = all_algorithms{i}; %#ok<SAGROW>
    end
end
num_algs  = length(enabled_algorithms);
alg_names = cellfun(@(a) a.name, enabled_algorithms, 'UniformOutput', false);

%% ===== 进度计数 =====
total_runs     = length(M_VALUES) * length(SEEDS);
total_alg_runs = total_runs * num_algs;
done_scenarios = 0;
done_alg_runs  = 0;
total_tic      = tic;

%% ===== 运行目录与配置快照 =====
run_timestamp = datestr(now, 'yyyymmdd_HHMMSS');
run_name = sprintf('%s_N%d_M%d-%d_K%d_S%d', ...
    run_timestamp, N, M_VALUES(1), M_VALUES(end), K, length(SEEDS));
run_dir        = fullfile(results_root_dir, run_name);
by_alg_dir     = fullfile(run_dir, 'by_alg');
aggregate_dir  = fullfile(run_dir, 'aggregated');
if ~exist(run_dir, 'dir'), mkdir(run_dir); end
if ~exist(by_alg_dir, 'dir'), mkdir(by_alg_dir); end
if ~exist(aggregate_dir, 'dir'), mkdir(aggregate_dir); end

scale_config = struct();
scale_config.M_values          = M_VALUES;
scale_config.N                 = N;
scale_config.K                 = K;
scale_config.seeds             = SEEDS;
scale_config.alg_ids           = algorithms_to_run_ids;
scale_config.alg_names         = alg_names;
scale_config.num_rounds        = num_rounds;
scale_config.max_inner_iter    = MaxIter;
scale_config.timestamp         = run_timestamp;
scale_config.run_name          = run_name;
scale_config.run_dir           = run_dir;
scale_config.save_layout       = 'by_alg/<algorithm>/Mxxx/N{N}_M{M}_seedyyyy.mat';
scale_config.aggregate_dir     = aggregate_dir;
scale_config.aggregate_cache_file = fullfile(aggregate_dir, 'varym_aggregate_cache.pkl');
scale_config.results_root_dir  = results_root_dir;
scale_config.save_mode         = 'incremental_by_alg_with_deferred_python_aggregation';
scale_config.deferred_aggregation = true;

param_snapshot = struct();
param_snapshot.common_config = Exp_Config.Common;
param_snapshot.scenario_cfg = Exp_Config.ScenarioCfg;
param_snapshot.varym_cfg = cfg;
param_snapshot.common_params = Common_Params;
param_snapshot.algorithm_params = Algorithm_Params;
param_snapshot.runtime_constants = struct( ...
    'num_rounds', num_rounds, ...
    'max_inner_iter', MaxIter, ...
    'obs_times', obs_times, ...
    'num_task_types', num_task_types, ...
    'task_values', task_values);
param_snapshot.exp_params_source = fullfile(script_dir, 'Exp_Params.m');

run_config_file = fullfile(run_dir, 'run_config.mat');
save(run_config_file, 'scale_config', 'param_snapshot');

progress_status = init_progress_status(M_VALUES, SEEDS, alg_names, run_timestamp, run_dir, total_runs, total_alg_runs);
progress_status_path = fullfile(run_dir, 'progress_status.mat');
save_progress_status(progress_status_path, progress_status);

fprintf('\n');
fprintf('========================================================================\n');
fprintf('  Batch_VaryM  |  M×S = %d×%d = %d 次实验\n', ...
    length(M_VALUES), length(SEEDS), total_runs);
fprintf('  总算法运行数 = %d × %d = %d\n', total_runs, num_algs, total_alg_runs);
fprintf('  M_VALUES = [%s]\n', num2str(M_VALUES));
fprintf('  SEEDS    = %d : %d\n', SEEDS(1), SEEDS(end));
fprintf('  算法     = [%s]\n', strjoin(alg_names, ', '));
fprintf('  轮数     = %d   内层迭代 = %d\n', num_rounds, MaxIter);
fprintf('  运行目录 = %s\n', run_dir);
fprintf('========================================================================\n\n');

%% ===== 结果容器 =====
scale_M_results = cell(length(M_VALUES), length(SEEDS));

%% =========================================================================
%  主循环：先遍历 M，再遍历 seed
%% =========================================================================
for mi = 1:length(M_VALUES)
    M = M_VALUES(mi);

    for si = 1:length(SEEDS)
        seed = SEEDS(si);
        done_scenarios = done_scenarios + 1;
        elapsed = toc(total_tic);
        eta_str = '';
        if done_scenarios > 1
            avg_per_run = elapsed / (done_scenarios - 1);
            eta_sec     = avg_per_run * (total_runs - done_scenarios + 1);
            eta_str     = sprintf('  ETA %.0fs', eta_sec);
        end
        fprintf('[%3d/%3d] M=%2d seed=%d ...%s\n', done_scenarios, total_runs, M, seed, eta_str);

        entry = struct();
        entry.M       = M;
        entry.seed    = seed;
        entry.success = false;
        entry.error   = '';
        entry.algs    = struct();

        try
            %% -- 构建随机场景 --
            scenario_cfg = Exp_Config.ScenarioCfg;
            scenario_cfg.N = N;
            scenario_cfg.M = M;
            scenario_cfg.K = K;
            [WORLD, tasks, agents, task_type_demands] = build_scenario(seed, scenario_cfg); %#ok<ASGLU>

            Value_Params = OCFUtils.init_value_params(N, M, K, num_task_types, task_type_demands, ...
                OCF_alpha, OCF_Tmin, OCF_K_stable_max, obs_times, num_rounds);
            Value_Params = OCFUtils.apply_experiment_params(Value_Params, Common_Params, Algorithm_Params, seed);

            %% -- 运行所有启用算法 --
            for ai = 1:num_algs
                alg   = enabled_algorithms{ai};
                aname = alg.name;

                alg_entry = init_alg_entry(num_rounds);

                try
                    rng(seed);
                    tic;
                    [~, history_data] = alg.func(agents, tasks, AddPara, Value_Params);
                    alg_entry.computation_time = toc;

                    num_r = length(history_data.rounds);
                    for r = 1:num_r
                        alg_entry.convergence_utility(r)    = history_data.rounds(r).coalition_utility;
                        alg_entry.convergence_cost(r)       = history_data.rounds(r).total_global_cost;
                        alg_entry.convergence_completed_value(r) = history_data.rounds(r).total_completed_value;
                        td = history_data.rounds(r).task_completion_degrees;
                        alg_entry.convergence_completion(r) = mean(td);
                    end
                    alg_entry.final_utility    = alg_entry.convergence_utility(num_r);
                    alg_entry.final_cost       = alg_entry.convergence_cost(num_r);
                    alg_entry.final_completed_value = alg_entry.convergence_completed_value(num_r);
                    alg_entry.final_completion = alg_entry.convergence_completion(num_r);
                    alg_entry.success          = true;

                catch ME_alg
                    alg_entry.error = ME_alg.message;
                    fprintf('  ! %s failed: %s\n', aname, ME_alg.message);
                end

                entry.algs.(aname) = alg_entry;
                done_alg_runs = done_alg_runs + 1;

                result_relpath = save_incremental_alg_result(by_alg_dir, run_timestamp, N, M, K, seed, alg, alg_entry);
                progress_status.alg_done(mi, si, ai) = true;
                progress_status.alg_success(mi, si, ai) = alg_entry.success;
                progress_status.alg_error{mi, si, ai} = alg_entry.error;
                progress_status.result_files{mi, si, ai} = result_relpath;
                progress_status.done_alg_runs = done_alg_runs;
                save_progress_status(progress_status_path, progress_status);
            end

            entry.success = true;
            progress_status.scenario_done(mi, si) = true;
            progress_status.scenario_success(mi, si) = true;
            progress_status.scenario_error{mi, si} = '';

        catch ME_outer
            entry.error = ME_outer.message;
            fprintf('  ! scenario M=%d seed=%d failed: %s\n', M, seed, ME_outer.message);
            progress_status.scenario_done(mi, si) = true;
            progress_status.scenario_success(mi, si) = false;
            progress_status.scenario_error{mi, si} = ME_outer.message;
        end

        scale_M_results{mi, si} = entry;
        save_progress_status(progress_status_path, progress_status);
    end % seeds
end % M_VALUES

total_elapsed = toc(total_tic);
fprintf('\n全部完成，总耗时 %.1f s (%.1f min)\n', total_elapsed, total_elapsed / 60);

%% ===== 标记完成（不在 MATLAB 侧做批末聚合） =====
progress_status.is_complete = true;
progress_status.finished_at = datestr(now, 'yyyymmdd_HHMMSS');
progress_status.total_elapsed_sec = total_elapsed;
save_progress_status(progress_status_path, progress_status);
save(run_config_file, 'scale_config', 'param_snapshot');

fprintf('已完成增量保存。\n');
fprintf('聚合总表将在 Python 绘图阶段按需生成缓存到: %s\n\n', aggregate_dir);

%% ===== 完整性检查 =====
fprintf('--- 完整性检查 ---\n');
success_count = 0;
fail_count    = 0;
for mi2 = 1:length(M_VALUES)
    for si2 = 1:length(SEEDS)
        e = scale_M_results{mi2, si2};
        if e.success
            success_count = success_count + 1;
        else
            fail_count = fail_count + 1;
            fprintf('  FAIL: M=%d seed=%d  %s\n', e.M, e.seed, e.error);
        end
    end
end
fprintf('成功: %d / %d  失败: %d\n', success_count, total_runs, fail_count);

%% ===== 打印各算法最终效用均值（按 M）=====
fprintf('\n--- 各算法最终效用均值（按 M 规模）---\n');
header = sprintf('%-6s', 'M');
for ai = 1:num_algs
    header = [header, sprintf(' | %-15s', alg_names{ai})]; %#ok<AGROW>
end
fprintf('%s\n', header);
fprintf('%s\n', repmat('-', 1, 6 + num_algs * 18));

for mi2 = 1:length(M_VALUES)
    row = sprintf('%-6d', M_VALUES(mi2));
    for ai = 1:num_algs
        aname = alg_names{ai};
        vals  = zeros(1, length(SEEDS));
        for si2 = 1:length(SEEDS)
            e = scale_M_results{mi2, si2};
            if e.success && isfield(e.algs, aname) && e.algs.(aname).success
                vals(si2) = e.algs.(aname).final_utility;
            else
                vals(si2) = NaN;
            end
        end
        mu = mean(vals(~isnan(vals)));
        if isnan(mu)
            row = [row, sprintf(' | %-15s', 'N/A')]; %#ok<AGROW>
        else
            row = [row, sprintf(' | %-15.2f', mu)]; %#ok<AGROW>
        end
    end
    fprintf('%s\n', row);
end
fprintf('\n');


function alg_entry = init_alg_entry(num_rounds)
alg_entry = struct();
alg_entry.computation_time            = NaN;
alg_entry.convergence_utility         = nan(num_rounds, 1);
alg_entry.convergence_cost            = nan(num_rounds, 1);
alg_entry.convergence_completed_value = nan(num_rounds, 1);
alg_entry.convergence_completion      = nan(num_rounds, 1);
alg_entry.final_utility               = NaN;
alg_entry.final_cost                  = NaN;
alg_entry.final_completed_value       = NaN;
alg_entry.final_completion            = NaN;
alg_entry.success                     = false;
alg_entry.error                       = '';
end


function progress_status = init_progress_status(M_VALUES, SEEDS, alg_names, run_timestamp, run_dir, total_runs, total_alg_runs)
nM = length(M_VALUES);
nS = length(SEEDS);
nA = length(alg_names);

progress_status = struct();
progress_status.timestamp        = run_timestamp;
progress_status.run_dir          = run_dir;
progress_status.M_values         = M_VALUES;
progress_status.seeds            = SEEDS;
progress_status.alg_names        = alg_names;
progress_status.total_runs       = total_runs;
progress_status.total_alg_runs   = total_alg_runs;
progress_status.done_alg_runs    = 0;
progress_status.scenario_done    = false(nM, nS);
progress_status.scenario_success = false(nM, nS);
progress_status.scenario_error   = cell(nM, nS);
progress_status.alg_done         = false(nM, nS, nA);
progress_status.alg_success      = false(nM, nS, nA);
progress_status.alg_error        = cell(nM, nS, nA);
progress_status.result_files     = cell(nM, nS, nA);
progress_status.last_update      = run_timestamp;
progress_status.is_complete      = false;
progress_status.finished_at      = '';
progress_status.total_elapsed_sec = NaN;
progress_status.save_mode        = 'incremental_by_alg_with_deferred_python_aggregation';
end


function save_progress_status(progress_status_path, progress_status)
progress_status.last_update = datestr(now, 'yyyymmdd_HHMMSS');
save(progress_status_path, 'progress_status');
end


function result_relpath = save_incremental_alg_result(by_alg_dir, run_timestamp, N, M, K, seed, alg, alg_entry)
alg_dir = fullfile(by_alg_dir, alg.name, sprintf('M%03d', M));
if ~exist(alg_dir, 'dir')
    mkdir(alg_dir);
end

result_name = sprintf('N%d_M%03d_seed%d.mat', N, M, seed);
result_path = fullfile(alg_dir, result_name);
result_relpath = fullfile('by_alg', alg.name, sprintf('M%03d', M), result_name);

partial_meta = struct();
partial_meta.timestamp      = run_timestamp;
partial_meta.algorithm_id   = alg.id;
partial_meta.algorithm_name = alg.name;
partial_meta.N              = N;
partial_meta.M              = M;
partial_meta.K              = K;
partial_meta.seed           = seed;
partial_meta.saved_at       = datestr(now, 'yyyymmdd_HHMMSS');

result_entry = alg_entry;
save(result_path, 'result_entry', 'partial_meta');
end
