clear; clc;
feature('DefaultCharacterSet', 'UTF-8');

%% =========================================================================
%  实验 C：信念演化（Batch_Belief）
%
%  画图用途：
%    图2a — 信念误差（belief error）随轮次的收敛曲线（3种初始信念条件对比）
%    图2b — 信念分布演化热图（某一任务/智能体的信念概率分布随轮次变化）
%
%  保存数据（results/batch/belief/N{N}_M{M}_K{K}_S{nSeeds}_{ts}.mat）：
%    belief_results{ci, si}  — 二维 cell [条件数 × seed数量]
%      .condition             初始信念条件名称（'uniform'/'optimistic'/'pessimistic'）
%      .seed                  随机种子
%      .success / .error
%      .true_task_types       [M×1] 各任务的真实类型（1/2/3），用于计算信念误差
%      .belief_history        [num_rounds × N × M × task_type] 每轮每智能体对每任务的信念分布
%      .convergence_utility   [num_rounds×1] 每轮联盟效用收敛曲线
%    belief_config — 本次实验参数快照
%
%  注：本实验仅运行算法 7（OCF_SAtabu），测试信念更新机制的效果
%% =========================================================================

%% ===== 路径初始化（须在 Exp_Params 之前）=====
script_dir = fileparts(mfilename('fullpath'));
root_dir   = fileparts(script_dir);

%% ===== 加载共享参数 =====
run(fullfile(script_dir, 'Exp_Params.m'));

%% ===== 实验专属配置 =====
SEEDS      = 1001:1:1010;
N          = 10;
M          = 10;
K          = 6;
CONDITIONS = {'uniform', 'optimistic', 'pessimistic'};

% 三种初始信念分布模板（对应 3 种任务类型：value=800/1000/1500）
belief_uniform     = ones(1, num_task_types) / num_task_types;  % [1/3, 1/3, 1/3]
belief_optimistic  = [0.1, 0.1, 0.8];  % 偏向高价值类型（type3, value=1500）
belief_pessimistic = [0.8, 0.1, 0.1];  % 偏向低价值类型（type1, value=800）

%% ===== 附加控制参数 =====
AddPara.verbose              = 0;
AddPara.enable_belief_update = true;
AddPara.control              = 1;

%% ===== 路径加入 =====
addpath(fullfile(root_dir, 'Main_fun'));
addpath(fullfile(root_dir, 'comalg', 'alg7_OCF_SAtabu'));

%% ===== 输出目录 =====
results_dir = fullfile(root_dir, 'results', 'batch', 'belief');
if ~exist(results_dir, 'dir'), mkdir(results_dir); end

%% ===== 进度计数 =====
num_cond   = length(CONDITIONS);
total_runs = num_cond * length(SEEDS);
done       = 0;
total_tic  = tic;

fprintf('\n');
fprintf('========================================================================\n');
fprintf('  Batch_Belief  |  C×S = %d×%d = %d 次实验\n', num_cond, length(SEEDS), total_runs);
fprintf('  条件 = [%s]\n', strjoin(CONDITIONS, ', '));
fprintf('  SEEDS = %d : %d\n', SEEDS(1), SEEDS(end));
fprintf('  N=%d  M=%d  K=%d  轮数=%d\n', N, M, K, num_rounds);
fprintf('========================================================================\n\n');

%% ===== 结果容器 =====
belief_results = cell(num_cond, length(SEEDS));

%% =========================================================================
%  主循环：先遍历条件，再遍历 seed
%% =========================================================================
for ci = 1:num_cond
    cond_name = CONDITIONS{ci};

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
        fprintf('[%2d/%2d] cond=%s seed=%d ...%s\n', done, total_runs, cond_name, seed, eta_str);

        entry = struct();
        entry.condition = cond_name;
        entry.seed      = seed;
        entry.success   = false;
        entry.error     = '';

        try
            %% -- 构建随机场景 --
            rng('default'); rng(seed);

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
            tasks_local = struct();
            for j = 1:M
                tasks_local(j).id       = j;
                tasks_local(j).priority = task_priorities(j);
                tasks_local(j).x = round(rand() * (WORLD.XMAX - WORLD.XMIN) + WORLD.XMIN);
                tasks_local(j).y = round(rand() * (WORLD.YMAX - WORLD.YMIN) + WORLD.YMIN);
                tasks_local(j).type     = randi(num_task_types, 1, 1);
                tasks_local(j).value    = WORLD.value(tasks_local(j).type);
                tasks_local(j).resource_demand      = task_type_demands(tasks_local(j).type, :);
                tasks_local(j).duration_by_resource = task_type_duration_by_resource(tasks_local(j).type, :);
                tasks_local(j).duration = max(tasks_local(j).duration_by_resource);
                tasks_local(j).WORLD    = WORLD;
            end

            agents_local = struct();
            for i = 1:N
                agents_local(i).id        = i;
                agents_local(i).vel       = agent_velocity;
                agents_local(i).x = round(rand() * (WORLD.XMAX - WORLD.XMIN) + WORLD_XMIN);
                agents_local(i).y = round(rand() * (WORLD.YMAX - WORLD.YMIN) + WORLD_YMIN);
                agents_local(i).detprob   = agent_detprob_min + (agent_detprob_max - agent_detprob_min) * rand();
                agents_local(i).resources = randi([min_resource_value, max_resource_value], K, 1);
                agents_local(i).Emax      = agent_Emax_min + agent_Emax_range * rand();
                agents_local(i).fuel      = agent_fuel;
                agents_local(i).wait_fuel = agent_wait_fuel;
                agents_local(i).beta      = agent_beta;
            end

            Value_Params = OCFUtils.init_value_params(N, M, K, num_task_types, task_type_demands, ...
                OCF_alpha, OCF_Tmin, OCF_K_stable_max, obs_times, num_rounds);
            Value_Params = OCFUtils.apply_experiment_params(Value_Params, Common_Params, Algorithm_Params, seed);

            % 提取真实任务类型（用于 Python 端计算信念误差）
            true_task_types = zeros(M, 1);
            for j = 1:M
                true_task_types(j) = tasks_local(j).type;
            end

            %% -- 运行 OCF_SAtabu --
            rng(seed);
            [~, history_data] = OCF_SAtabu_global_main(agents_local, tasks_local, AddPara, Value_Params);

            %% -- 提取 belief_history [num_rounds × N × M × task_type] --
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

            entry.true_task_types     = true_task_types;
            entry.belief_history      = belief_history;
            entry.convergence_utility = convergence_utility;
            entry.success             = true;

        catch ME_outer
            entry.error = ME_outer.message;
            fprintf('  ! cond=%s seed=%d failed: %s\n', cond_name, seed, ME_outer.message);
        end

        belief_results{ci, si} = entry;
    end % seeds
end % conditions

total_elapsed = toc(total_tic);
fprintf('\n全部完成，总耗时 %.1f s (%.1f min)\n', total_elapsed, total_elapsed / 60);

%% ===== 保存 .mat =====
belief_config = struct();
belief_config.conditions         = CONDITIONS;
belief_config.N                  = N;
belief_config.M                  = M;
belief_config.K                  = K;
belief_config.seeds              = SEEDS;
belief_config.task_type_values   = task_values;
belief_config.num_rounds         = num_rounds;
belief_config.belief_uniform     = belief_uniform;
belief_config.belief_optimistic  = belief_optimistic;
belief_config.belief_pessimistic = belief_pessimistic;
belief_config.timestamp          = datestr(now, 'yyyymmdd_HHMMSS');

timestamp = belief_config.timestamp;
filename  = fullfile(results_dir, sprintf('N%d_M%d_K%d_S%d_%s.mat', ...
    N, M, K, length(SEEDS), timestamp));

fprintf('保存至: %s\n', filename);
save(filename, 'belief_results', 'belief_config', '-v7.3');
fprintf('保存完成。\n\n');

%% ===== 完整性检查 =====
fprintf('--- 完整性检查 ---\n');
success_count = 0;
fail_count    = 0;
for ci2 = 1:num_cond
    for si2 = 1:length(SEEDS)
        e = belief_results{ci2, si2};
        if e.success
            success_count = success_count + 1;
            if ci2 == 1 && si2 == 1
                fprintf('  [信息] belief_history 尺寸: [%s]\n', num2str(size(e.belief_history)));
            end
        else
            fail_count = fail_count + 1;
            fprintf('  FAIL: cond=%s seed=%d  %s\n', e.condition, e.seed, e.error);
        end
    end
end
fprintf('成功: %d / %d  失败: %d\n', success_count, total_runs, fail_count);
fprintf('\n');
