clear; clc;
feature('DefaultCharacterSet', 'UTF-8');

%% =========================================================================
%  Experiment D: ablation on belief update and demand estimation mode
%
%  Save layout (aligned with Batch_VaryM / Batch_Belief):
%    results/batch/ablation/<run_name>/
%      run_config.mat
%      progress_status.mat
%      by_condition/<condition>/N{N}/N{N}_M{M}_cond_{condition}_seed{seed}.mat
%      aggregated/
%
%  Each incremental MAT stores:
%    result_entry  - one N x seed x condition entry
%    partial_meta  - save metadata for that entry
%
%  MATLAB no longer writes a top-level aggregate ablation_results MAT. Python
%  plotting rebuilds an aggregate cache on demand from the incremental files.
%% =========================================================================

%% ===== Path bootstrap =====
script_dir = fileparts(mfilename('fullpath'));
root_dir   = fileparts(script_dir);

%% ===== Shared parameters =====
run(fullfile(script_dir, 'Exp_Params.m'));

%% ===== Experiment config =====
cfg = Exp_Config.Ablation;
SEEDS = cfg.SEEDS;
N_VALUES = cfg.N_VALUES(:).';
M = cfg.M;
K = cfg.K;
AddPara_base = cfg.AddPara;
resource_confidence_ablation = cfg.resource_confidence;
init_belief_mode = cfg.init_belief_mode;
init_belief_vector = cfg.init_belief_vector(:).';
all_condition_defs = cfg.ALL_CONDITION_DEFS;
enabled_condition_names = cfg.ENABLED_CONDITIONS;
condition_defs = resolve_enabled_conditions(all_condition_defs, enabled_condition_names);
CONDITIONS = {condition_defs.name};
num_rounds = Exp_Config.Common.num_rounds;
task_values_snapshot = Exp_Config.ScenarioCfg.task_values(:).';
task_type_demand_max_snapshot = Exp_Config.ScenarioCfg.task_type_demand_max(:).';

if numel(init_belief_vector) ~= num_task_types
    error('Batch_Ablation:initBeliefVectorSize', ...
        'cfg.init_belief_vector must have %d elements, got %d.', ...
        num_task_types, numel(init_belief_vector));
end
if any(init_belief_vector < 0)
    error('Batch_Ablation:initBeliefVectorNonnegative', ...
        'cfg.init_belief_vector must be non-negative.');
end
if sum(init_belief_vector) <= 0
    error('Batch_Ablation:initBeliefVectorPositive', ...
        'cfg.init_belief_vector must sum to a positive value.');
end
init_belief_vector = init_belief_vector / sum(init_belief_vector);

%% ===== Code paths =====
addpath(fullfile(root_dir, 'Main_fun'));
addpath(fullfile(root_dir, 'comalg', 'alg7_OCF_SAtabu'));

%% ===== Output layout =====
results_root_dir = fullfile(root_dir, 'results', 'batch', 'ablation');
run_timestamp = datestr(now, 'yyyymmdd_HHMMSS');
run_name = sprintf('%s_N%d-%d_M%d_K%d_C%d_S%d', ...
    run_timestamp, N_VALUES(1), N_VALUES(end), M, K, numel(CONDITIONS), numel(SEEDS));
run_dir          = fullfile(results_root_dir, run_name);
by_condition_dir = fullfile(run_dir, 'by_condition');
aggregate_dir    = fullfile(run_dir, 'aggregated');

if ~exist(results_root_dir, 'dir'), mkdir(results_root_dir); end
if ~exist(run_dir, 'dir'), mkdir(run_dir); end
if ~exist(by_condition_dir, 'dir'), mkdir(by_condition_dir); end
if ~exist(aggregate_dir, 'dir'), mkdir(aggregate_dir); end

ablation_config = struct();
ablation_config.N_values = N_VALUES;
ablation_config.M = M;
ablation_config.K = K;
ablation_config.seeds = SEEDS;
ablation_config.conditions = CONDITIONS;
ablation_config.enabled_conditions = CONDITIONS;
ablation_config.condition_defs = condition_defs;
ablation_config.num_task_types = num_task_types;
ablation_config.num_rounds = num_rounds;
ablation_config.resource_confidence = resource_confidence_ablation;
ablation_config.init_belief_mode = init_belief_mode;
ablation_config.init_belief_vector = init_belief_vector;
ablation_config.timestamp = run_timestamp;
ablation_config.run_name = run_name;
ablation_config.run_dir = run_dir;
ablation_config.save_layout = 'by_condition/<condition>/N{N}/N{N}_M{M}_cond_{condition}_seed{seed}.mat';
ablation_config.aggregate_dir = aggregate_dir;
ablation_config.aggregate_cache_file = fullfile(aggregate_dir, 'ablation_aggregate_cache.pkl');
ablation_config.results_root_dir = results_root_dir;
ablation_config.save_mode = 'incremental_by_condition_with_deferred_python_aggregation';
ablation_config.deferred_aggregation = true;

param_snapshot = struct();
param_snapshot.common_config = Exp_Config.Common;
param_snapshot.scenario_cfg = Exp_Config.ScenarioCfg;
param_snapshot.ablation_cfg = cfg;
param_snapshot.common_params = Common_Params;
param_snapshot.algorithm_params = Algorithm_Params;
param_snapshot.runtime_constants = struct( ...
    'num_rounds', num_rounds, ...
    'max_inner_iter', MaxIter, ...
    'obs_times', obs_times, ...
    'num_task_types', num_task_types, ...
    'task_values', task_values_snapshot, ...
    'task_type_demand_max', task_type_demand_max_snapshot);
param_snapshot.exp_params_source = fullfile(script_dir, 'Exp_Params.m');

run_config_file = fullfile(run_dir, 'run_config.mat');
save(run_config_file, 'ablation_config', 'param_snapshot');

%% ===== Progress =====
num_n = numel(N_VALUES);
num_s = numel(SEEDS);
num_cond = numel(CONDITIONS);
total_runs = num_n * num_s * num_cond;
done = 0;
total_tic = tic;

progress_status = init_progress_status(N_VALUES, SEEDS, CONDITIONS, run_timestamp, run_dir, total_runs);
progress_status_path = fullfile(run_dir, 'progress_status.mat');
save_progress_status(progress_status_path, progress_status);

fprintf('\n');
fprintf('========================================================================\n');
fprintf('  Batch_Ablation | N x S x C = %d x %d x %d = %d runs\n', ...
    num_n, num_s, num_cond, total_runs);
fprintf('  N_VALUES             = [%s]\n', num2str(N_VALUES));
fprintf('  SEEDS                = %d : %d\n', SEEDS(1), SEEDS(end));
fprintf('  resource_confidence  = %.2f\n', resource_confidence_ablation);
fprintf('  init_belief_mode     = %s\n', init_belief_mode);
fprintf('  init_belief_vector   = [%s]\n', num2str(init_belief_vector, '%.2f '));
for ci = 1:num_cond
    cond_def = condition_defs(ci);
    fprintf('  condition[%d]         = %s | belief_update=%s | demand=%s | rounding=%s\n', ...
        ci, cond_def.name, mat2str(cond_def.enable_belief_update), ...
        cond_def.demand_estimation_mode, cond_def.demand_rounding_mode);
end
fprintf('  rounds / inner_iter  = %d / %d\n', num_rounds, MaxIter);
fprintf('  Run directory        = %s\n', run_dir);
fprintf('========================================================================\n\n');

%% ===== Result container for integrity summary =====
ablation_results = cell(num_n, num_s, num_cond);

%% =========================================================================
%  Main loop
%% =========================================================================
for ni = 1:num_n
    N = N_VALUES(ni);

    for si = 1:num_s
        seed = SEEDS(si);

        scene_ok = false;
        scene_error = '';
        shared_init_belief = [];
        tasks = [];
        agents = [];
        Value_Params_base = [];

        try
            scenario_cfg = Exp_Config.ScenarioCfg;
            scenario_cfg.N = N;
            scenario_cfg.M = M;
            scenario_cfg.K = K;
            [~, tasks, agents, task_type_demands] = build_scenario(seed, scenario_cfg);

            Value_Params_base = OCFUtils.init_value_params(N, M, K, num_task_types, task_type_demands, ...
                OCF_alpha, OCF_Tmin, OCF_K_stable_max, obs_times, num_rounds);
            Value_Params_base = OCFUtils.apply_experiment_params( ...
                Value_Params_base, Common_Params, Algorithm_Params, seed);
            Value_Params_base.resource_confidence = resource_confidence_ablation;

            shared_init_belief = build_ablation_init_belief( ...
                init_belief_mode, init_belief_vector, N, num_task_types);

            scene_ok = true;
        catch ME_scene
            scene_error = ME_scene.message;
            fprintf('  ! scenario build failed N=%d seed=%d: %s\n', N, seed, scene_error);
        end

        for ci = 1:num_cond
            cond_def = condition_defs(ci);
            cond_name = cond_def.name;

            done = done + 1;
            elapsed = toc(total_tic);
            eta_str = '';
            if done > 1
                avg_per_run = elapsed / (done - 1);
                eta_sec = avg_per_run * (total_runs - done + 1);
                eta_str = sprintf('  ETA %.0fs', eta_sec);
            end
            fprintf('[%3d/%3d] N=%2d seed=%d cond=%s ...%s\n', ...
                done, total_runs, N, seed, cond_name, eta_str);

            entry = struct();
            entry.N = N;
            entry.seed = seed;
            entry.condition = cond_name;
            entry.belief_on = logical(cond_def.enable_belief_update);
            entry.enable_belief_update = logical(cond_def.enable_belief_update);
            entry.demand_estimation_mode = cond_def.demand_estimation_mode;
            entry.demand_rounding_mode = cond_def.demand_rounding_mode;
            entry.resource_confidence = resource_confidence_ablation;
            entry.init_belief_mode = init_belief_mode;
            entry.init_belief_vector = init_belief_vector;
            entry.success = false;
            entry.error = '';

            if ~scene_ok
                entry.error = scene_error;
            else
                try
                    AddPara_run = AddPara_base;
                    AddPara_run.init_belief = shared_init_belief;
                    AddPara_run.enable_belief_update = cond_def.enable_belief_update;
                    AddPara_run.demand_estimation_mode = cond_def.demand_estimation_mode;
                    AddPara_run.demand_rounding_mode = cond_def.demand_rounding_mode;

                    if isfield(AddPara_run, 'init_belief_tensor')
                        AddPara_run = rmfield(AddPara_run, 'init_belief_tensor');
                    end

                    rng(seed);
                    tic;
                    [final_Value_data, history_data] = OCF_SAtabu_global_main( ...
                        agents, tasks, AddPara_run, Value_Params_base);
                    entry.computation_time = toc;

                    num_r = length(history_data.rounds);
                    convergence_utility = nan(num_rounds, 1);
                    for r = 1:num_r
                        convergence_utility(r) = history_data.rounds(r).coalition_utility;
                    end

                    entry.convergence_utility = convergence_utility;
                    entry.final_utility = convergence_utility(num_r);
                    entry.init_belief_matrix = shared_init_belief;

                    final_degrees = history_data.rounds(num_r).task_completion_degrees;
                    entry.final_task_completion = mean(final_degrees);
                    entry.success = true;

                    td = Value_Params_base.task_type_demands;
                    conf = Value_Params_base.resource_confidence;
                    belief_agent1 = final_Value_data(1).initbelief;

                    fprintf('\n  ---- [%s] N=%d seed=%d final belief & demand summary ----\n', ...
                        cond_name, N, seed);
                    fprintf('  %-5s | %-18s | %-14s | %-9s | %-5s | estimated vs true demand\n', ...
                        'task', 'belief[t1 t2 t3]', 'est_type(prob)', 'true_type', 'match');
                    fprintf('  %s\n', repmat('-', 1, 86));

                    n_match = 0;
                    for m_task = 1:M
                        b = belief_agent1(m_task, :);
                        [max_p, est_t] = max(b);
                        true_t = tasks(m_task).type;
                        hit = (est_t == true_t);
                        n_match = n_match + hit;
                        est_d = WorldSim.estimate_demand_from_belief( ...
                            b, td, cond_def.demand_estimation_mode, conf, cond_def.demand_rounding_mode);
                        true_d = tasks(m_task).resource_demand;
                        hit_str = 'x';
                        if hit, hit_str = 'ok'; end
                        fprintf('  T%-3d  | [%s] | %2d(%.0f%%)      | %5d     | %-5s | [%s] vs [%s]\n', ...
                            m_task, num2str(b, '%5.2f'), est_t, max_p * 100, true_t, hit_str, ...
                            num2str(est_d, '%3.0f'), num2str(true_d, '%3.0f'));
                    end
                    fprintf('  belief type hit rate: %d/%d = %.0f%%\n', n_match, M, 100 * n_match / M);
                    fprintf('  --------------------------------------------------------------\n\n');

                catch ME_run
                    entry.error = ME_run.message;
                    fprintf('  ! N=%d seed=%d cond=%s failed: %s\n', N, seed, cond_name, ME_run.message);
                end
            end

            ablation_results{ni, si, ci} = entry;

            result_relpath = save_incremental_entry_result( ...
                by_condition_dir, run_timestamp, N, M, K, cond_name, seed, entry);
            progress_status.done_runs = done;
            progress_status.entry_done(ni, si, ci) = true;
            progress_status.entry_success(ni, si, ci) = entry.success;
            progress_status.entry_error{ni, si, ci} = entry.error;
            progress_status.result_files{ni, si, ci} = result_relpath;
            save_progress_status(progress_status_path, progress_status);
        end
    end
end

total_elapsed = toc(total_tic);
fprintf('\nAll runs completed. Total elapsed %.1f s (%.1f min)\n', total_elapsed, total_elapsed / 60);

%% ===== Mark completion =====
progress_status.is_complete = true;
progress_status.finished_at = datestr(now, 'yyyymmdd_HHMMSS');
progress_status.total_elapsed_sec = total_elapsed;
save_progress_status(progress_status_path, progress_status);
save(run_config_file, 'ablation_config', 'param_snapshot');

fprintf('Incremental results were saved successfully.\n');
fprintf('Aggregate cache will be built on demand by Python at %s\n\n', aggregate_dir);

%% ===== Integrity check =====
fprintf('--- Integrity check ---\n');
success_count = 0;
fail_count = 0;
for ni2 = 1:num_n
    for si2 = 1:num_s
        for ci2 = 1:num_cond
            e = ablation_results{ni2, si2, ci2};
            if isempty(e)
                fail_count = fail_count + 1;
                continue;
            end
            if e.success
                success_count = success_count + 1;
            else
                fail_count = fail_count + 1;
                fprintf('  FAIL: N=%d seed=%d cond=%s  %s\n', ...
                    e.N, e.seed, CONDITIONS{ci2}, e.error);
            end
        end
    end
end
fprintf('Success: %d / %d  Failure: %d\n', success_count, total_runs, fail_count);

%% ===== Mean table =====
fprintf('\n--- Ablation mean final utility by N ---\n');
header = sprintf('%-6s', 'N');
for ci2 = 1:num_cond
    header = [header, sprintf(' | %-22s', CONDITIONS{ci2})]; %#ok<AGROW>
end
fprintf('%s\n', header);
fprintf('%s\n', repmat('-', 1, 6 + num_cond * 25));

for ni2 = 1:num_n
    row = sprintf('%-6d', N_VALUES(ni2));
    for ci2 = 1:num_cond
        vals = nan(1, num_s);
        for si2 = 1:num_s
            e = ablation_results{ni2, si2, ci2};
            if ~isempty(e) && e.success
                vals(si2) = e.final_utility;
            end
        end
        mu = mean(vals(~isnan(vals)));
        if isnan(mu)
            row = [row, sprintf(' | %-22s', 'N/A')]; %#ok<AGROW>
        else
            row = [row, sprintf(' | %-22.2f', mu)]; %#ok<AGROW>
        end
    end
    fprintf('%s\n', row);
end
fprintf('\n');


function progress_status = init_progress_status(N_VALUES, SEEDS, CONDITIONS, run_timestamp, run_dir, total_runs)
nN = numel(N_VALUES);
nS = numel(SEEDS);
nC = numel(CONDITIONS);

progress_status = struct();
progress_status.timestamp = run_timestamp;
progress_status.run_dir = run_dir;
progress_status.N_values = N_VALUES;
progress_status.seeds = SEEDS;
progress_status.conditions = CONDITIONS;
progress_status.total_runs = total_runs;
progress_status.done_runs = 0;
progress_status.entry_done = false(nN, nS, nC);
progress_status.entry_success = false(nN, nS, nC);
progress_status.entry_error = cell(nN, nS, nC);
progress_status.result_files = cell(nN, nS, nC);
progress_status.last_update = run_timestamp;
progress_status.is_complete = false;
progress_status.finished_at = '';
progress_status.total_elapsed_sec = NaN;
progress_status.save_mode = 'incremental_by_condition_with_deferred_python_aggregation';
end


function save_progress_status(progress_status_path, progress_status)
progress_status.last_update = datestr(now, 'yyyymmdd_HHMMSS');
save(progress_status_path, 'progress_status');
end


function relpath = save_incremental_entry_result(by_condition_dir, run_timestamp, N, M, K, condition_name, seed, result_entry)
cond_key = sanitize_token(condition_name);
entry_dir = fullfile(by_condition_dir, cond_key, sprintf('N%d', N));
if ~exist(entry_dir, 'dir'), mkdir(entry_dir); end

filename = sprintf('N%d_M%d_cond_%s_seed%d.mat', N, M, cond_key, seed);
result_path = fullfile(entry_dir, filename);

partial_meta = struct();
partial_meta.timestamp = run_timestamp;
partial_meta.condition = condition_name;
partial_meta.seed = seed;
partial_meta.N = N;
partial_meta.M = M;
partial_meta.K = K;
partial_meta.saved_at = datestr(now, 'yyyymmdd_HHMMSS');

save(result_path, 'result_entry', 'partial_meta');
relpath = strrep(result_path, [fileparts(by_condition_dir), filesep], '');
end


function token = sanitize_token(text)
token = regexprep(char(string(text)), '[^A-Za-z0-9_-]+', '_');
token = regexprep(token, '^_+|_+$', '');
if isempty(token)
    token = 'condition';
end
end


function init_belief = build_ablation_init_belief(init_belief_mode, init_belief_vector, N, num_task_types)
switch init_belief_mode
    case 'shared_wrong_prior'
        belief_row = reshape(init_belief_vector, 1, num_task_types);
    case 'uniform'
        belief_row = ones(1, num_task_types) / num_task_types;
    otherwise
        error('Batch_Ablation:UnsupportedInitBeliefMode', ...
            'Unsupported cfg.init_belief_mode: %s', init_belief_mode);
end

init_belief = repmat(belief_row, N, 1);
end


function condition_defs = resolve_enabled_conditions(all_condition_defs, enabled_condition_names)
if isempty(all_condition_defs)
    error('Batch_Ablation:MissingConditionDefs', ...
        'cfg.ALL_CONDITION_DEFS must not be empty.');
end

if isempty(enabled_condition_names)
    condition_defs = all_condition_defs;
    return;
end

condition_defs = struct('name', {}, 'enable_belief_update', {}, ...
    'demand_estimation_mode', {}, 'demand_rounding_mode', {});

for idx = 1:numel(enabled_condition_names)
    target_name = enabled_condition_names{idx};
    matched = false;
    for j = 1:numel(all_condition_defs)
        if strcmp(all_condition_defs(j).name, target_name)
            condition_defs(end + 1) = all_condition_defs(j); %#ok<AGROW>
            matched = true;
            break;
        end
    end
    if ~matched
        error('Batch_Ablation:UnknownCondition', ...
            'Unknown enabled condition: %s', target_name);
    end
end
end
