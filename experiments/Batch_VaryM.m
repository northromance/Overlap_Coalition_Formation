clear; clc;
feature('DefaultCharacterSet', 'UTF-8');

%% ===== 实验 B：变 M 规模（图1c/1d）=====
% 固定 N=10, K=6，遍历不同 M 值

%% ===== 批量实验配置 =====
SEEDS             = 1001:1:1020;                  % 20 个随机种子
M_VALUES          = [5, 8, 10, 12, 15, 18, 20];   % 7 种任务规模
N                 = 10;                            % 智能体数（固定）
K                 = 6;                             % 资源种类（固定）
algorithms_to_run_ids = [2, 3, 4, 7];

AddPara.verbose              = 0;
AddPara.enable_belief_update = true;
AddPara.control              = 1;

% ---------- 通用超参 ----------
num_rounds      = 100;
MaxIter         = 100;
obs_times       = 50;
task_values     = [800, 1000, 1500];
num_task_types  = length(task_values);

T0_round            = 100;
SA_alpha            = 0.9;
SA_Tmin             = 0.01;
T_decay             = 0.8;
T_min_round         = 2;
T_init_construction = 2;
resource_confidence = 0.7;
K_stable_max        = 10;
tabu_tenure         = 20;
p_leave             = 0.3;
Qi_L_tabu           = 10;
Qi_K_stable_max     = 10;
Qi_Gamma_init       = 1;
Qi_Gamma_max        = 50;
Shi_K_stable_max    = 10;

% 场景参数
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
root_dir   = fileparts(script_dir);
addpath(fullfile(root_dir, 'Main_fun'));
addpath(fullfile(root_dir, 'comalg', 'alg1_SA'));
addpath(fullfile(root_dir, 'comalg', 'alg2_Huo2025'));
addpath(fullfile(root_dir, 'comalg', 'alg3_Qi2023'));
addpath(fullfile(root_dir, 'comalg', 'alg4_Shi2024'));
addpath(fullfile(root_dir, 'comalg', 'alg7_OCF_SAtabu'));

%% ===== 输出目录 =====
results_dir = fullfile(root_dir, 'results', 'batch', 'varyM');
if ~exist(results_dir, 'dir')
    mkdir(results_dir);
end

%% ===== 算法注册表 =====
all_algorithms = {
    struct('id', 2, 'name', 'Huo2025',    'func', @Huo2025_main);
    struct('id', 3, 'name', 'Qi2023',     'func', @Qi2023_main);
    struct('id', 4, 'name', 'Shi2024',    'func', @Shi2024_main);
    struct('id', 7, 'name', 'OCF_SAtabu', 'func', @OCF_SAtabu_global_main);
};

enabled_algorithms = {};
for i = 1:length(all_algorithms)
    if ismember(all_algorithms{i}.id, algorithms_to_run_ids)
        enabled_algorithms{end+1} = all_algorithms{i}; %#ok<SAGROW>
    end
end
num_algs  = length(enabled_algorithms);
alg_names = cellfun(@(a) a.name, enabled_algorithms, 'UniformOutput', false);

%% ===== 进度计数 =====
total_runs = length(M_VALUES) * length(SEEDS);
done       = 0;
total_tic  = tic;

fprintf('\n');
fprintf('========================================================================\n');
fprintf('  Batch_VaryM  |  M×S = %d×%d = %d 次实验\n', ...
    length(M_VALUES), length(SEEDS), total_runs);
fprintf('  M_VALUES = [%s]\n', num2str(M_VALUES));
fprintf('  SEEDS    = %d : %d\n', SEEDS(1), SEEDS(end));
fprintf('  算法     = [%s]\n', strjoin(alg_names, ', '));
fprintf('  轮数     = %d   内层迭代 = %d\n', num_rounds, MaxIter);
fprintf('========================================================================\n\n');

%% ===== 主循环 =====
scale_M_results = cell(length(M_VALUES), length(SEEDS));

for mi = 1:length(M_VALUES)
    M = M_VALUES(mi);

    for si = 1:length(SEEDS)
        seed = SEEDS(si);
        done = done + 1;
        elapsed = toc(total_tic);
        eta_str = '';
        if done > 1
            avg_per_run = elapsed / (done - 1);
            eta_sec     = avg_per_run * (total_runs - done + 1);
            eta_str     = sprintf('  ETA %.0fs', eta_sec);
        end
        fprintf('[%3d/%3d] M=%2d seed=%d ...%s\n', done, total_runs, M, seed, eta_str);

        entry.M       = M;
        entry.seed    = seed;
        entry.success = false;
        entry.error   = '';
        entry.algs    = struct();

        try
            %% -- 构建场景 --
            rng('default');
            rng(seed);

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
                SA_alpha, SA_Tmin, K_stable_max, obs_times, num_rounds);
            Value_Params.K_stable_max        = K_stable_max;
            Value_Params.max_inner_iter      = MaxIter;
            Value_Params.T0_round            = T0_round;
            Value_Params.T_decay             = T_decay;
            Value_Params.T_min_round         = T_min_round;
            Value_Params.resource_confidence = resource_confidence;
            Value_Params.T_init_construction = T_init_construction;
            Value_Params.tabu_tenure         = tabu_tenure;
            Value_Params.p_leave             = p_leave;
            Value_Params.Qi_L_tabu           = Qi_L_tabu;
            Value_Params.Qi_K_stable_max     = Qi_K_stable_max;
            Value_Params.Qi_Gamma_init       = Qi_Gamma_init;
            Value_Params.Qi_Gamma_max        = Qi_Gamma_max;
            Value_Params.Shi_K_stable_max    = Shi_K_stable_max;
            Value_Params.C                   = 2000;
            Value_Params.seed                = seed;

            %% -- 各算法执行 --
            for ai = 1:num_algs
                alg   = enabled_algorithms{ai};
                aname = alg.name;

                alg_entry.computation_time       = NaN;
                alg_entry.convergence_utility    = nan(num_rounds, 1);
                alg_entry.convergence_cost       = nan(num_rounds, 1);
                alg_entry.convergence_completion = nan(num_rounds, 1);
                alg_entry.final_utility          = NaN;
                alg_entry.final_cost             = NaN;
                alg_entry.final_completion       = NaN;
                alg_entry.success                = false;
                alg_entry.error                  = '';

                try
                    rng(seed);
                    tic;
                    [~, history_data] = alg.func(agents, tasks, AddPara, Value_Params);
                    alg_entry.computation_time = toc;

                    num_r = length(history_data.rounds);
                    for r = 1:num_r
                        alg_entry.convergence_utility(r)    = history_data.rounds(r).coalition_utility;
                        alg_entry.convergence_cost(r)       = history_data.rounds(r).total_global_cost;
                        td = history_data.rounds(r).task_completion_degrees;
                        alg_entry.convergence_completion(r) = mean(td);
                    end

                    alg_entry.final_utility    = alg_entry.convergence_utility(num_r);
                    alg_entry.final_cost       = alg_entry.convergence_cost(num_r);
                    alg_entry.final_completion = alg_entry.convergence_completion(num_r);
                    alg_entry.success          = true;

                catch ME_alg
                    alg_entry.error = ME_alg.message;
                    fprintf('  ! %s failed: %s\n', aname, ME_alg.message);
                end

                entry.algs.(aname) = alg_entry;
            end

            entry.success = true;

        catch ME_outer
            entry.error = ME_outer.message;
            fprintf('  ! scenario M=%d seed=%d failed: %s\n', M, seed, ME_outer.message);
        end

        scale_M_results{mi, si} = entry;
    end % seeds
end % M_VALUES

total_elapsed = toc(total_tic);
fprintf('\n全部完成，总耗时 %.1f s (%.1f min)\n', total_elapsed, total_elapsed / 60);

%% ===== 保存 .mat =====
% 命名格式：N{N}_M{min}-{max}_K{K}_S{nSeeds}_{timestamp}.mat
scale_config.M_values       = M_VALUES;
scale_config.N              = N;
scale_config.K              = K;
scale_config.seeds          = SEEDS;
scale_config.alg_ids        = algorithms_to_run_ids;
scale_config.alg_names      = alg_names;
scale_config.num_rounds     = num_rounds;
scale_config.max_inner_iter = MaxIter;
scale_config.timestamp      = datestr(now, 'yyyymmdd_HHMMSS');

timestamp = scale_config.timestamp;
filename  = fullfile(results_dir, sprintf('N%d_M%d-%d_K%d_S%d_%s.mat', ...
    N, M_VALUES(1), M_VALUES(end), K, length(SEEDS), timestamp));

fprintf('保存至: %s\n', filename);
save(filename, 'scale_M_results', 'scale_config', '-v7.3');
fprintf('保存完成。\n\n');

%% ===== 快速完整性检查 =====
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
