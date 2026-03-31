clear; clc;
feature('DefaultCharacterSet', 'UTF-8');

%% =========================================================================
%  Experiment C: belief evolution under different initial conditions
%
%  New save layout (aligned with Batch_VaryM):
%    results/batch/belief/<run_name>/
%      run_config.mat
%      progress_status.mat
%      by_condition/<condition>/N{N}_M{M}_cond_{condition}_seed{seed}.mat
%      aggregated/
%
%  Each incremental MAT stores:
%    result_entry  - one condition x seed entry
%    partial_meta  - save metadata for that entry
%
%  The top-level aggregate MAT is no longer written by MATLAB. Python plots
%  rebuild an aggregate cache on demand from the incremental files.
%% =========================================================================

%% ===== Path bootstrap =====
script_dir = fileparts(mfilename('fullpath'));
root_dir   = fileparts(script_dir);

%% ===== Shared parameters =====
run(fullfile(script_dir, 'Exp_Params.m'));

%% ===== Experiment-specific config =====
cfg = Exp_Config.Belief;
SEEDS = cfg.SEEDS;
N = cfg.N;
M = cfg.M;
K = cfg.K;
CONDITIONS = cfg.CONDITIONS;
num_rounds = Exp_Config.Common.num_rounds;
task_values = cfg.task_values(:).';
num_task_types = numel(task_values);
task_type_demand_max = cfg.task_type_demand_max(:).';

belief_uniform = cfg.belief_uniform;
belief_random_dirichlet_alpha = cfg.belief_random_dirichlet_alpha(:).';

if numel(task_type_demand_max) ~= num_task_types
    error('Batch_Belief:taskTypeDemandMaxSize', ...
        'cfg.task_type_demand_max must have %d elements, got %d.', ...
        num_task_types, numel(task_type_demand_max));
end
if numel(belief_uniform) ~= num_task_types
    error('Batch_Belief:uniformBeliefSize', ...
        'cfg.belief_uniform must have %d elements, got %d.', ...
        num_task_types, numel(belief_uniform));
end
if numel(belief_random_dirichlet_alpha) ~= num_task_types
    error('Batch_Belief:randomAlphaSize', ...
        'cfg.belief_random_dirichlet_alpha must have %d elements, got %d.', ...
        num_task_types, numel(belief_random_dirichlet_alpha));
end
if any(belief_random_dirichlet_alpha <= 0)
    error('Batch_Belief:randomAlphaPositive', ...
        'cfg.belief_random_dirichlet_alpha must be strictly positive.');
end

%% ===== Extra control parameters =====
AddPara = cfg.AddPara;

%% ===== Add code paths =====
addpath(fullfile(root_dir, 'Main_fun'));
addpath(fullfile(root_dir, 'comalg', 'alg7_OCF_SAtabu'));

%% ===== Output layout =====
results_root_dir = fullfile(root_dir, 'results', 'batch', 'belief');
run_timestamp = datestr(now, 'yyyymmdd_HHMMSS');
run_name = sprintf('%s_N%d_M%d_K%d_C%d_S%d', ...
    run_timestamp, N, M, K, length(CONDITIONS), length(SEEDS));
run_dir          = fullfile(results_root_dir, run_name);
by_condition_dir = fullfile(run_dir, 'by_condition');
aggregate_dir    = fullfile(run_dir, 'aggregated');

if ~exist(results_root_dir, 'dir'), mkdir(results_root_dir); end
if ~exist(run_dir, 'dir'), mkdir(run_dir); end
if ~exist(by_condition_dir, 'dir'), mkdir(by_condition_dir); end
if ~exist(aggregate_dir, 'dir'), mkdir(aggregate_dir); end

belief_config = struct();
belief_config.conditions = CONDITIONS;
belief_config.N = N;
belief_config.M = M;
belief_config.K = K;
belief_config.seeds = SEEDS;
belief_config.num_task_types = num_task_types;
belief_config.task_type_values = task_values;
belief_config.task_type_demand_max = task_type_demand_max;
belief_config.num_rounds = num_rounds;
belief_config.belief_uniform = belief_uniform;
belief_config.belief_random_dirichlet_alpha = belief_random_dirichlet_alpha;
belief_config.timestamp = run_timestamp;
belief_config.run_name = run_name;
belief_config.run_dir = run_dir;
belief_config.save_layout = 'by_condition/<condition>/N{N}_M{M}_cond_{condition}_seed{seed}.mat';
belief_config.aggregate_dir = aggregate_dir;
belief_config.aggregate_cache_file = fullfile(aggregate_dir, 'belief_aggregate_cache.pkl');
belief_config.results_root_dir = results_root_dir;
belief_config.save_mode = 'incremental_by_condition_with_deferred_python_aggregation';
belief_config.deferred_aggregation = true;

param_snapshot = struct();
param_snapshot.common_config = Exp_Config.Common;
param_snapshot.scenario_cfg = Exp_Config.ScenarioCfg;
param_snapshot.belief_cfg = cfg;
param_snapshot.common_params = Common_Params;
param_snapshot.algorithm_params = Algorithm_Params;
param_snapshot.runtime_constants = struct( ...
    'num_rounds', num_rounds, ...
    'max_inner_iter', MaxIter, ...
    'obs_times', obs_times, ...
    'num_task_types', num_task_types, ...
    'task_values', task_values, ...
    'task_type_demand_max', task_type_demand_max);
param_snapshot.exp_params_source = fullfile(script_dir, 'Exp_Params.m');

run_config_file = fullfile(run_dir, 'run_config.mat');
save(run_config_file, 'belief_config', 'param_snapshot');

%% ===== Progress bookkeeping =====
num_cond = length(CONDITIONS);
num_seeds = length(SEEDS);
total_runs = num_cond * num_seeds;
done = 0;
total_tic = tic;

progress_status = init_progress_status(CONDITIONS, SEEDS, run_timestamp, run_dir, total_runs);
progress_status_path = fullfile(run_dir, 'progress_status.mat');
save_progress_status(progress_status_path, progress_status);

fprintf('\n');
fprintf('========================================================================\n');
fprintf('  Batch_Belief  |  CxS = %d x %d = %d runs\n', num_cond, num_seeds, total_runs);
fprintf('  Conditions    = [%s]\n', strjoin(CONDITIONS, ', '));
fprintf('  Seeds         = %d : %d\n', SEEDS(1), SEEDS(end));
fprintf('  N=%d  M=%d  K=%d  rounds=%d\n', N, M, K, num_rounds);
fprintf('  Run directory = %s\n', run_dir);
fprintf('========================================================================\n\n');

%% ===== In-memory container for final integrity check =====
belief_results = cell(num_cond, num_seeds);

%% =========================================================================
%  Main loop: condition first, then seed
%% =========================================================================
for ci = 1:num_cond
    cond_name = CONDITIONS{ci};

    for si = 1:num_seeds
        seed = SEEDS(si);
        done = done + 1;
        elapsed = toc(total_tic);
        eta_str = '';
        if done > 1
            avg_per_run = elapsed / (done - 1);
            eta_sec = avg_per_run * (total_runs - done + 1);
            eta_str = sprintf('  ETA %.0fs', eta_sec);
        end
        fprintf('[%2d/%2d] cond=%s seed=%d ...%s\n', done, total_runs, cond_name, seed, eta_str);

        entry = struct();
        entry.condition = cond_name;
        entry.seed = seed;
        entry.success = false;
        entry.error = '';

        try
            %% -- Build random scenario --
            scenario_cfg = Exp_Config.ScenarioCfg;
            scenario_cfg.N = N;
            scenario_cfg.M = M;
            scenario_cfg.K = K;
            scenario_cfg.num_task_types = num_task_types;
            scenario_cfg.task_values = task_values;
            scenario_cfg.task_type_demand_max = task_type_demand_max;
            [~, tasks_local, agents_local, task_type_demands] = build_scenario(seed, scenario_cfg);

            Value_Params = OCFUtils.init_value_params(N, M, K, num_task_types, task_type_demands, ...
                OCF_alpha, OCF_Tmin, OCF_K_stable_max, obs_times, num_rounds);
            Value_Params = OCFUtils.apply_experiment_params(Value_Params, Common_Params, Algorithm_Params, seed);

            true_task_types = zeros(M, 1);
            true_task_values = zeros(M, 1);
            for j = 1:M
                true_task_types(j) = tasks_local(j).type;
                true_task_values(j) = tasks_local(j).value;
            end

            %% -- Build initial belief prior for the current condition --
            AddPara_run = AddPara;
            init_b = [];
            init_b_tensor = [];
            init_b_mode = '';
            switch cond_name
                case 'uniform'
                    init_b = repmat(belief_uniform, N, 1);
                    init_b_tensor = repmat(reshape(init_b, [N, 1, num_task_types]), 1, M, 1);
                    AddPara_run.init_belief = init_b;
                    AddPara_run.init_belief_tensor = init_b_tensor;
                    init_b_mode = 'shared_agent_prior';

                case 'heterogeneous'
                    rng(seed + 9999);
                    init_b_tensor = zeros(N, M, num_task_types);

                    for i_agent = 1:N
                        for m_task = 1:M
                            belief_vec = OCFUtils.drchrnd(belief_random_dirichlet_alpha, 1);
                            init_b_tensor(i_agent, m_task, :) = belief_vec / sum(belief_vec);
                        end
                    end

                    init_b = reshape(mean(init_b_tensor, 2), [N, num_task_types]);
                    AddPara_run.init_belief_tensor = init_b_tensor;
                    init_b_mode = 'task_specific_prior';

                otherwise
                    init_b = repmat(belief_uniform, N, 1);
                    init_b_tensor = repmat(reshape(init_b, [N, 1, num_task_types]), 1, M, 1);
                    AddPara_run.init_belief = init_b;
                    AddPara_run.init_belief_tensor = init_b_tensor;
                    init_b_mode = 'shared_agent_prior';
            end

            %% -- Run OCF_SAtabu --
            rng(seed);
            [~, history_data] = OCF_SAtabu_global_main(agents_local, tasks_local, AddPara_run, Value_Params);

            %% -- Extract belief history [num_rounds x N x M x type] --
            num_r = length(history_data.rounds);
            belief_history = nan(num_r, N, M, num_task_types);
            for r = 1:num_r
                if isfield(history_data.rounds(r), 'beliefs') && ~isempty(history_data.rounds(r).beliefs)
                    belief_history(r, :, :, :) = history_data.rounds(r).beliefs;
                end
            end

            convergence_utility = nan(num_r, 1);
            for r = 1:num_r
                convergence_utility(r) = history_data.rounds(r).coalition_utility;
            end

            entry.true_task_types = true_task_types;
            entry.true_task_values = true_task_values;
            entry.init_belief_mode = init_b_mode;
            entry.init_belief_matrix = init_b;
            entry.init_belief_tensor = init_b_tensor;
            entry.belief_history = belief_history;
            entry.convergence_utility = convergence_utility;
            entry.success = true;

        catch ME_outer
            entry.error = ME_outer.message;
            fprintf('  ! cond=%s seed=%d failed: %s\n', cond_name, seed, ME_outer.message);
        end

        belief_results{ci, si} = entry;

        result_relpath = save_incremental_belief_result( ...
            by_condition_dir, run_timestamp, N, M, K, cond_name, seed, entry);

        progress_status.done_runs = done;
        progress_status.entry_done(ci, si) = true;
        progress_status.entry_success(ci, si) = entry.success;
        progress_status.entry_error{ci, si} = entry.error;
        progress_status.result_files{ci, si} = result_relpath;
        save_progress_status(progress_status_path, progress_status);
    end
end

total_elapsed = toc(total_tic);
fprintf('\nAll runs completed. Total elapsed %.1f s (%.1f min)\n', total_elapsed, total_elapsed / 60);

%% ===== Mark completion =====
progress_status.is_complete = true;
progress_status.finished_at = datestr(now, 'yyyymmdd_HHMMSS');
progress_status.total_elapsed_sec = total_elapsed;
save_progress_status(progress_status_path, progress_status);
save(run_config_file, 'belief_config', 'param_snapshot');

fprintf('Incremental save completed.\n');
fprintf('Aggregate cache will be built on demand by Python at %s\n\n', aggregate_dir);

%% ===== Integrity check =====
fprintf('--- Integrity check ---\n');
success_count = 0;
fail_count = 0;
for ci2 = 1:num_cond
    for si2 = 1:num_seeds
        e = belief_results{ci2, si2};
        if e.success
            success_count = success_count + 1;
            if ci2 == 1 && si2 == 1
                fprintf('  [info] belief_history size: [%s]\n', num2str(size(e.belief_history)));
            end
        else
            fail_count = fail_count + 1;
            fprintf('  FAIL: cond=%s seed=%d  %s\n', e.condition, e.seed, e.error);
        end
    end
end
fprintf('Success: %d / %d  Failure: %d\n', success_count, total_runs, fail_count);
fprintf('\n');


function progress_status = init_progress_status(CONDITIONS, SEEDS, run_timestamp, run_dir, total_runs)
nC = length(CONDITIONS);
nS = length(SEEDS);

progress_status = struct();
progress_status.timestamp = run_timestamp;
progress_status.run_dir = run_dir;
progress_status.conditions = CONDITIONS;
progress_status.seeds = SEEDS;
progress_status.total_runs = total_runs;
progress_status.done_runs = 0;
progress_status.entry_done = false(nC, nS);
progress_status.entry_success = false(nC, nS);
progress_status.entry_error = cell(nC, nS);
progress_status.result_files = cell(nC, nS);
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


function result_relpath = save_incremental_belief_result(by_condition_dir, run_timestamp, N, M, K, cond_name, seed, entry)
cond_key = sanitize_condition_name(cond_name);
cond_dir = fullfile(by_condition_dir, cond_key);
if ~exist(cond_dir, 'dir')
    mkdir(cond_dir);
end

result_name = sprintf('N%d_M%d_cond_%s_seed%d.mat', N, M, cond_key, seed);
result_path = fullfile(cond_dir, result_name);
result_relpath = fullfile('by_condition', cond_key, result_name);

partial_meta = struct();
partial_meta.timestamp = run_timestamp;
partial_meta.condition = cond_name;
partial_meta.condition_sanitized = cond_key;
partial_meta.N = N;
partial_meta.M = M;
partial_meta.K = K;
partial_meta.seed = seed;
partial_meta.saved_at = datestr(now, 'yyyymmdd_HHMMSS');

result_entry = entry;
save(result_path, 'result_entry', 'partial_meta');
end


function cond_key = sanitize_condition_name(cond_name)
cond_key = regexprep(char(string(cond_name)), '[^A-Za-z0-9_-]+', '_');
cond_key = regexprep(cond_key, '^_+|_+$', '');
if isempty(cond_key)
    cond_key = 'condition';
end
end
