clear; clc;
feature('DefaultCharacterSet', 'UTF-8');

%% =========================================================================
%  实验 A：变 N 规模（Batch_VaryN）
%
%  画图用途：
%    图1a — 最终联盟效用 vs N（各算法对比）
%    图1b — 最终平均任务完成度 vs N
%    图2c — 最终全局成本 vs N（可选）
%    收敛曲线图 — convergence_utility/cost/completion vs 轮次
%
%  保存数据（results/batch/varyN/N{min}-{max}_M{M}_K{K}_S{nSeeds}_{ts}.mat）：
%    scale_N_results{ni, si}  — 二维 cell [N数量 × seed数量]
%      .N / .seed / .success / .error
%      .algs.(算法名).final_utility        最终联盟效用（图1a 的值）
%      .algs.(算法名).final_cost           最终全局成本（图1b 的值）
%      .algs.(算法名).final_completion     最终平均任务完成度
%      .algs.(算法名).convergence_utility  [num_rounds×1] 每轮效用收敛曲线
%      .algs.(算法名).convergence_cost     [num_rounds×1] 每轮成本曲线
%      .algs.(算法名).convergence_completion [num_rounds×1] 每轮完成度曲线
%      .algs.(算法名).computation_time     算法运行耗时（秒）
%    scale_config — 本次实验参数快照
%
%  注：单次可视化（联盟结构图、时序甘特图等）请运行 Single_Viz.m
%% =========================================================================

%% ===== 路径初始化（须在 Exp_Params 之前）=====
script_dir = fileparts(mfilename('fullpath'));
root_dir   = fileparts(script_dir);

%% ===== 加载共享参数 =====
run(fullfile(script_dir, 'Exp_Params.m'));

%% ===== 实验专属配置 =====
% 测试时用小规模，正式运行时注释掉 "测试用" 行，启用 "正式" 行
SEEDS             = 1001:1:1006;              % 测试用；正式改成 1001:1:1020
N_VALUES          = [4, 6, 8, 10];           % 测试用；正式改成 [4,6,8,10,12,16,20]
M                 = 10;                       % 固定任务数
K                 = 6;                        % 固定资源种类数
algorithms_to_run_ids = [2, 3, 4, 7];

% 覆盖 Exp_Params 中的 num_rounds（测试模式）；正式运行删除此行
num_rounds = 3;

%% ===== 附加控制参数 =====
AddPara.verbose              = 1;
AddPara.enable_belief_update = true;

%% ===== 路径加入 =====
addpath(fullfile(root_dir, 'Main_fun'));
addpath(fullfile(root_dir, 'comalg', 'alg1_SA'));
addpath(fullfile(root_dir, 'comalg', 'alg2_Huo2025'));
addpath(fullfile(root_dir, 'comalg', 'alg3_Qi2023'));
addpath(fullfile(root_dir, 'comalg', 'alg4_Shi2024'));
addpath(fullfile(root_dir, 'comalg', 'alg7_OCF_SAtabu'));

%% ===== 输出目录 =====
results_dir = fullfile(root_dir, 'results', 'batch', 'varyN');
if ~exist(results_dir, 'dir'), mkdir(results_dir); end

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
total_runs     = length(N_VALUES) * length(SEEDS);
total_alg_runs = total_runs * num_algs;
done           = 0;
total_tic      = tic;

fprintf('\n');
fprintf('========================================================================\n');
fprintf('  Batch_VaryN  |  场景数 N×S = %d×%d = %d\n', ...
    length(N_VALUES), length(SEEDS), total_runs);
fprintf('  总算法运行数 = %d × %d = %d\n', total_runs, num_algs, total_alg_runs);
fprintf('  N_VALUES = [%s]\n', num2str(N_VALUES));
fprintf('  SEEDS    = %d : %d\n', SEEDS(1), SEEDS(end));
fprintf('  算法     = [%s]\n', strjoin(alg_names, ', '));
fprintf('  轮数     = %d   内层迭代 = %d\n', num_rounds, MaxIter);
fprintf('========================================================================\n\n');

%% ===== 结果容器 =====
scale_N_results = cell(length(N_VALUES), length(SEEDS));

%% =========================================================================
%  主循环：先遍历 N，再遍历 seed
%% =========================================================================
for ni = 1:length(N_VALUES)
    N = N_VALUES(ni);

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
        fprintf('[%3d/%3d] N=%2d seed=%d ...%s\n', done, total_runs, N, seed, eta_str);

        entry = struct();
        entry.N       = N;
        entry.seed    = seed;
        entry.success = false;
        entry.error   = '';
        entry.algs    = struct();

        try
            %% -- 构建随机场景 --
            rng('default'); rng(seed);

            WORLD = struct();
            WORLD.XMIN  = WORLD_XMIN;  WORLD.XMAX = WORLD_XMAX;
            WORLD.YMIN  = WORLD_YMIN;  WORLD.YMAX = WORLD_YMAX;
            WORLD.ZMIN  = WORLD_ZMIN;  WORLD.ZMAX = WORLD_ZMAX;
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
                tasks(j).x = round(rand() * (WORLD.XMAX - WORLD.XMIN) + WORLD.XMIN);
                tasks(j).y = round(rand() * (WORLD.YMAX - WORLD.YMIN) + WORLD.YMIN);
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
                agents(i).x = round(rand() * (WORLD.XMAX - WORLD.XMIN) + WORLD_XMIN);
                agents(i).y = round(rand() * (WORLD.YMAX - WORLD.YMIN) + WORLD_YMIN);
                agents(i).detprob   = agent_detprob_min + (agent_detprob_max - agent_detprob_min) * rand();
                agents(i).resources = randi([min_resource_value, max_resource_value], K, 1);
                agents(i).Emax      = agent_Emax_min + agent_Emax_range * rand();
                agents(i).fuel      = agent_fuel;
                agents(i).wait_fuel = agent_wait_fuel;
                agents(i).beta      = agent_beta;
            end

            Value_Params = OCFUtils.init_value_params( ...
                N, M, K, num_task_types, task_type_demands, ...
                OCF_alpha, OCF_Tmin, OCF_K_stable_max, obs_times, num_rounds);
            Value_Params = OCFUtils.apply_experiment_params(Value_Params, Common_Params, Algorithm_Params, seed);

            %% -- 运行所有启用算法 --
            for ai = 1:num_algs
                alg   = enabled_algorithms{ai};
                aname = alg.name;

                alg_entry = struct();
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
            fprintf('  ! scenario N=%d seed=%d failed: %s\n', N, seed, ME_outer.message);
        end

        scale_N_results{ni, si} = entry;
    end % seeds
end % N_VALUES

total_elapsed = toc(total_tic);
fprintf('\n全部完成，总耗时 %.1f s (%.1f min)\n', total_elapsed, total_elapsed / 60);

%% ===== 保存 .mat =====
scale_config = struct();
scale_config.N_values       = N_VALUES;
scale_config.M              = M;
scale_config.K              = K;
scale_config.seeds          = SEEDS;
scale_config.alg_ids        = algorithms_to_run_ids;
scale_config.alg_names      = alg_names;
scale_config.num_rounds     = num_rounds;
scale_config.max_inner_iter = MaxIter;
scale_config.timestamp      = datestr(now, 'yyyymmdd_HHMMSS');

timestamp = scale_config.timestamp;
filename  = fullfile(results_dir, sprintf('N%d-%d_M%d_K%d_S%d_%s.mat', ...
    N_VALUES(1), N_VALUES(end), M, K, length(SEEDS), timestamp));

fprintf('保存至: %s\n', filename);
save(filename, 'scale_N_results', 'scale_config', '-v7.3');
fprintf('保存完成。\n\n');

%% ===== 完整性检查 =====
fprintf('--- 完整性检查 ---\n');
success_count = 0;
fail_count    = 0;
for ni2 = 1:length(N_VALUES)
    for si2 = 1:length(SEEDS)
        e = scale_N_results{ni2, si2};
        if e.success
            success_count = success_count + 1;
        else
            fail_count = fail_count + 1;
            fprintf('  FAIL: N=%d seed=%d  %s\n', e.N, e.seed, e.error);
        end
    end
end
fprintf('成功: %d / %d  失败: %d\n', success_count, total_runs, fail_count);

%% ===== 打印各算法最终效用均值（按 N）=====
fprintf('\n--- 各算法最终效用均值（按 N 规模）---\n');
header = sprintf('%-6s', 'N');
for ai = 1:num_algs
    header = [header, sprintf(' | %-15s', alg_names{ai})]; %#ok<AGROW>
end
fprintf('%s\n', header);
fprintf('%s\n', repmat('-', 1, 6 + num_algs * 18));

for ni2 = 1:length(N_VALUES)
    row = sprintf('%-6d', N_VALUES(ni2));
    for ai = 1:num_algs
        aname = alg_names{ai};
        vals  = zeros(1, length(SEEDS));
        for si2 = 1:length(SEEDS)
            e = scale_N_results{ni2, si2};
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
