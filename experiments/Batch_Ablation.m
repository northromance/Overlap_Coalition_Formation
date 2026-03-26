clear; clc;
feature('DefaultCharacterSet', 'UTF-8');

%% =========================================================================
%  实验 D：消融实验（Batch_Ablation）
%
%  画图用途：
%    图4 — 消融对比：belief_on vs belief_off 的最终效用 vs N 折线图
%          （验证信念更新机制对算法性能的贡献）
%
%  保存数据（results/batch/ablation/N{min}-{max}_M{M}_K{K}_S{nSeeds}_{ts}.mat）：
%    ablation_results{ni, si, ci}  — 三维 cell [N数量 × seed数量 × 条件数]
%      .N / .seed / .belief_on / .success / .error
%      .convergence_utility   [num_rounds×1] 每轮联盟效用收敛曲线
%      .final_utility         最终联盟效用（图4 的纵轴值）
%      .computation_time      算法运行耗时（秒）
%    ablation_config — 本次实验参数快照
%
%  注：本实验仅运行算法 7（OCF_SAtabu），两种条件共享同一随机场景
%% =========================================================================

%% ===== 路径初始化（须在 Exp_Params 之前）=====
script_dir = fileparts(mfilename('fullpath'));
root_dir   = fileparts(script_dir);

%% ===== 加载共享参数 =====
run(fullfile(script_dir, 'Exp_Params.m'));

%% ===== 实验专属配置 =====
cfg = Exp_Config.Ablation;
SEEDS = cfg.SEEDS;
N_VALUES = cfg.N_VALUES;
M = cfg.M;
K = cfg.K;
CONDITIONS = cfg.CONDITIONS;
AddPara_base = cfg.AddPara;
num_rounds = Exp_Config.Common.num_rounds;

%% ===== 路径加入 =====
addpath(fullfile(root_dir, 'Main_fun'));
addpath(fullfile(root_dir, 'comalg', 'alg7_OCF_SAtabu'));

%% ===== 输出目录 =====
results_dir = fullfile(root_dir, 'results', 'batch', 'ablation');
if ~exist(results_dir, 'dir'), mkdir(results_dir); end

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

%% ===== 结果容器 =====
ablation_results = cell(length(N_VALUES), length(SEEDS), num_cond);

%% =========================================================================
%  主循环：遍历 N、seed，同一场景对两种条件各跑一次
%% =========================================================================
for ni = 1:length(N_VALUES)
    N = N_VALUES(ni);

    for si = 1:length(SEEDS)
        seed = SEEDS(si);

        %% -- 构建场景（两种条件共享同一随机场景）--
        scene_ok = false;
        try
            scenario_cfg = Exp_Config.ScenarioCfg;
            scenario_cfg.N = N;
            scenario_cfg.M = M;
            scenario_cfg.K = K;
            [WORLD, tasks, agents, task_type_demands] = build_scenario(seed, scenario_cfg); %#ok<ASGLU>

            Value_Params_base = OCFUtils.init_value_params(N, M, K, num_task_types, task_type_demands, ...
                OCF_alpha, OCF_Tmin, OCF_K_stable_max, obs_times, num_rounds);
            Value_Params_base = OCFUtils.apply_experiment_params(Value_Params_base, Common_Params, Algorithm_Params, seed);

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

            entry = struct();
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
                AddPara_run = AddPara_base;
                AddPara_run.enable_belief_update = (ci == 1);  % 消融开关：ci=1开启，ci=2关闭

                rng(seed);
                tic;
                [final_Value_data, history_data] = OCF_SAtabu_global_main(agents, tasks, AddPara_run, Value_Params_base);
                entry.computation_time = toc;

                num_r = length(history_data.rounds);
                convergence_utility = nan(num_rounds, 1);
                for r = 1:num_r
                    convergence_utility(r) = history_data.rounds(r).coalition_utility;
                end
                entry.convergence_utility   = convergence_utility;
                entry.final_utility         = convergence_utility(num_r);
                % 提取最终轮平均任务完成率
                final_degrees = history_data.rounds(num_r).task_completion_degrees;
                entry.final_task_completion = mean(final_degrees);
                entry.success               = true;

                %% ===== 打印最终信念 & 需求估计摘要 =====
                td  = Value_Params_base.task_type_demands;  % num_types × K
                conf = Value_Params_base.resource_confidence;
                belief_agent1 = final_Value_data(1).initbelief;  % M × num_types（所有agent广播后一致）

                fprintf('\n  ┌─ [%s] N=%d seed=%d  最终信念/需求估计 ─────────────────────────\n', ...
                    cond_name, N, seed);
                fprintf('  │ %-5s │ %-18s │ est_type(prob) │ true_type │ match │ 估计需求 vs 真实需求\n', ...
                    '任务', '信念分布[t1 t2 t3]');
                fprintf('  │%s\n', repmat('─', 1, 80));

                n_match = 0;
                for m_p = 1:M
                    b = belief_agent1(m_p, :);
                    [max_p, est_t] = max(b);
                    true_t = tasks(m_p).type;
                    hit = (est_t == true_t);
                    n_match = n_match + hit;
                    est_d  = WorldSim.calculate_demand_quantile(b, td, conf);
                    true_d = tasks(m_p).resource_demand;
                    hit_str = '';
                    if hit, hit_str = '✓'; else, hit_str = '✗'; end
                    fprintf('  │ T%-3d  │ [%s] │   %d(%.0f%%)   │     %d     │  %s    │ [%s] vs [%s]\n', ...
                        m_p, num2str(b, '%5.2f'), est_t, max_p*100, true_t, hit_str, ...
                        num2str(est_d, '%3.0f'), num2str(true_d, '%3.0f'));
                end
                fprintf('  │ 命中率: %d/%d = %.0f%%\n', n_match, M, 100*n_match/M);
                fprintf('  └─────────────────────────────────────────────────────────────────\n\n');

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
ablation_config = struct();
ablation_config.N_values   = N_VALUES;
ablation_config.M          = M;
ablation_config.K          = K;
ablation_config.seeds      = SEEDS;
ablation_config.conditions = CONDITIONS;
ablation_config.num_rounds = num_rounds;
ablation_config.timestamp  = datestr(now, 'yyyymmdd_HHMMSS');

timestamp = ablation_config.timestamp;
filename  = fullfile(results_dir, sprintf('N%d-%d_M%d_K%d_S%d_%s.mat', ...
    N_VALUES(1), N_VALUES(end), M, K, length(SEEDS), timestamp));

fprintf('保存至: %s\n', filename);
save(filename, 'ablation_results', 'ablation_config', '-v7.3');
fprintf('保存完成。\n\n');

%% ===== 完整性检查 =====
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

%% ===== 打印消融对比均值表 =====
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
