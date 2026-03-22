clear; clc;
feature('DefaultCharacterSet', 'UTF-8');

%% ===== 实验 D：消融实验（图4）=====
% 固定 M=10, K=6，遍历不同 N 值
% 只运行 OCF_SAtabu (算法 7)
% 两种条件：belief_on (enable_belief_update=true) / belief_off (=false)

%% ===== 实验配置 =====
SEEDS      = 1001:1:1020;
N_VALUES   = [4, 6, 8, 10, 12, 16, 20];
M          = 10;
K          = 6;
CONDITIONS = {'belief_on', 'belief_off'};

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
addpath(fullfile(root_dir, 'comalg', 'alg7_OCF_SAtabu'));

%% ===== 输出目录 =====
results_dir = fullfile(root_dir, 'results', 'batch', 'ablation');
if ~exist(results_dir, 'dir')
    mkdir(results_dir);
end

%% ===== 进度计数 =====
num_cond   = length(CONDITIONS);
total_runs = length(N_VALUES) * length(SEEDS) * num_cond;
done       = 0;
total_tic  = tic;

fprintf('\n');
fprintf('========================================================================\n');
fprintf('  Batch_Ablation  |  N×S×C = %d×%d×%d = %d 次实验\n', ...
    length(N_VALUES), length(SEEDS), num_cond, total_runs);
fprintf('  N_VALUES = [%s]\n', num2str(N_VALUES));
fprintf('  SEEDS    = %d : %d\n', SEEDS(1), SEEDS(end));
fprintf('  条件     = [%s]\n', strjoin(CONDITIONS, ', '));
fprintf('  轮数     = %d   内层迭代 = %d\n', num_rounds, MaxIter);
fprintf('========================================================================\n\n');

%% ===== 主循环 =====
ablation_results = cell(length(N_VALUES), length(SEEDS), num_cond);

for ni = 1:length(N_VALUES)
    N = N_VALUES(ni);

    for si = 1:length(SEEDS)
        seed = SEEDS(si);

        %% -- 构建场景（同一(N,seed)两种条件共享）--
        scene_ok = false;
        try
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

            Value_Params_base = OCFUtils.init_value_params(N, M, K, num_task_types, task_type_demands, ...
                SA_alpha, SA_Tmin, K_stable_max, obs_times, num_rounds);
            Value_Params_base.K_stable_max        = K_stable_max;
            Value_Params_base.max_inner_iter      = MaxIter;
            Value_Params_base.T0_round            = T0_round;
            Value_Params_base.T_decay             = T_decay;
            Value_Params_base.T_min_round         = T_min_round;
            Value_Params_base.resource_confidence = resource_confidence;
            Value_Params_base.T_init_construction = T_init_construction;
            Value_Params_base.tabu_tenure         = tabu_tenure;
            Value_Params_base.p_leave             = p_leave;
            Value_Params_base.Qi_L_tabu           = 10;
            Value_Params_base.Qi_K_stable_max     = 10;
            Value_Params_base.Qi_Gamma_init       = 1;
            Value_Params_base.Qi_Gamma_max        = 50;
            Value_Params_base.Shi_K_stable_max    = 10;
            Value_Params_base.C                   = 2000;
            Value_Params_base.seed                = seed;

            scene_ok = true;
        catch ME_scene
            fprintf('  ! 场景构建失败 N=%d seed=%d: %s\n', N, seed, ME_scene.message);
        end

        %% -- 两种条件分别运行 --
        for ci = 1:num_cond
            done = done + 1;
            elapsed = toc(total_tic);
            eta_str = '';
            if done > 1
                avg_per_run = elapsed / (done - 1);
                eta_sec     = avg_per_run * (total_runs - done + 1);
                eta_str     = sprintf('  ETA %.0fs', eta_sec);
            end
            cond_name = CONDITIONS{ci};
            fprintf('[%3d/%3d] N=%2d seed=%d cond=%s ...%s\n', ...
                done, total_runs, N, seed, cond_name, eta_str);

            entry.N         = N;
            entry.seed      = seed;
            entry.belief_on = (ci == 1);
            entry.success   = false;
            entry.error     = '';

            if ~scene_ok
                entry.error = '场景构建失败';
                ablation_results{ni, si, ci} = entry;
                continue;
            end

            try
                AddPara_run.verbose              = 0;
                AddPara_run.enable_belief_update = (ci == 1);  % 消融开关
                AddPara_run.control              = 1;

                rng(seed);
                tic;
                [~, history_data] = OCF_SAtabu_global_main(agents, tasks, AddPara_run, Value_Params_base);
                entry.computation_time = toc;

                num_r = length(history_data.rounds);
                convergence_utility = nan(num_rounds, 1);
                for r = 1:num_r
                    convergence_utility(r) = history_data.rounds(r).coalition_utility;
                end

                entry.convergence_utility = convergence_utility;
                entry.final_utility       = convergence_utility(num_r);
                entry.success             = true;

            catch ME_run
                entry.error = ME_run.message;
                fprintf('  ! N=%d seed=%d cond=%s failed: %s\n', N, seed, cond_name, ME_run.message);
            end

            ablation_results{ni, si, ci} = entry;
        end % conditions
    end % seeds
end % N_VALUES

total_elapsed = toc(total_tic);
fprintf('\n全部完成，总耗时 %.1f s (%.1f min)\n', total_elapsed, total_elapsed / 60);

%% ===== 保存 .mat =====
% 命名格式：N{min}-{max}_M{M}_K{K}_S{nSeeds}_{timestamp}.mat
ablation_config.N_values    = N_VALUES;
ablation_config.M           = M;
ablation_config.K           = K;
ablation_config.seeds       = SEEDS;
ablation_config.conditions  = CONDITIONS;
ablation_config.num_rounds  = num_rounds;
ablation_config.timestamp   = datestr(now, 'yyyymmdd_HHMMSS');

timestamp = ablation_config.timestamp;
filename  = fullfile(results_dir, sprintf('N%d-%d_M%d_K%d_S%d_%s.mat', ...
    N_VALUES(1), N_VALUES(end), M, K, length(SEEDS), timestamp));

fprintf('保存至: %s\n', filename);
save(filename, 'ablation_results', 'ablation_config', '-v7.3');
fprintf('保存完成。\n\n');

%% ===== 快速完整性检查 =====
fprintf('--- 完整性检查 ---\n');
success_count = 0;
fail_count    = 0;
for ni2 = 1:length(N_VALUES)
    for si2 = 1:length(SEEDS)
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
fprintf('成功: %d / %d  失败: %d\n', success_count, total_runs, fail_count);

fprintf('\n--- 消融对比：各 N 规模最终效用均值 ---\n');
header = sprintf('%-6s', 'N');
for ci2 = 1:num_cond
    header = [header, sprintf(' | %-15s', CONDITIONS{ci2})]; %#ok<AGROW>
end
fprintf('%s\n', header);
fprintf('%s\n', repmat('-', 1, 6 + num_cond * 18));

for ni2 = 1:length(N_VALUES)
    row = sprintf('%-6d', N_VALUES(ni2));
    for ci2 = 1:num_cond
        vals = zeros(1, length(SEEDS));
        for si2 = 1:length(SEEDS)
            e = ablation_results{ni2, si2, ci2};
            if ~isempty(e) && e.success
                vals(si2) = e.final_utility;
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
