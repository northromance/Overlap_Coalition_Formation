clear; clc;
feature('DefaultCharacterSet', 'UTF-8');

%% =========================================================================
%  实验 C：信念演化（Batch_Belief）
%
%  画图用途：
%    图2a — 信念误差（belief error）随轮次的收敛曲线（不同初始信念条件对比）
%    图2b — 信念分布演化热图（某一任务/智能体的信念概率分布随轮次变化）
%
%  保存数据（results/batch/belief/N{N}_M{M}_K{K}_S{nSeeds}_{ts}.mat）：
%    belief_results{ci, si}  — 二维 cell [条件数 × seed数量]
%      .condition             初始信念条件名称（'uniform'/'heterogeneous'）
%      .seed                  随机种子
%      .success / .error
%      .true_task_types       [M×1] 各任务的真实类型（1..T），用于计算信念误差
%      .init_belief_mode      round-0 先验模式（shared_agent_prior / task_specific_prior）
%      .init_belief_matrix    [N×T] 兼容摘要；heterogeneous 下为对任务维均值后的摘要
%      .init_belief_tensor    [N×M×T] round-0 权威先验张量
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

% 初始信念分布模板
% uniform: 所有智能体均匀先验 [1/T, ..., 1/T]（条件共用）
% heterogeneous: 每个 agent-task 直接随机采样一个任务类型概率分布
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

%% ===== 附加控制参数 =====
AddPara = cfg.AddPara;

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
            scenario_cfg = Exp_Config.ScenarioCfg;
            scenario_cfg.N = N;
            scenario_cfg.M = M;
            scenario_cfg.K = K;
            scenario_cfg.num_task_types = num_task_types;
            scenario_cfg.task_values = task_values;
            scenario_cfg.task_type_demand_max = task_type_demand_max;
            [WORLD, tasks_local, agents_local, task_type_demands] = build_scenario(seed, scenario_cfg); %#ok<ASGLU>

            Value_Params = OCFUtils.init_value_params(N, M, K, num_task_types, task_type_demands, ...
                OCF_alpha, OCF_Tmin, OCF_K_stable_max, obs_times, num_rounds);
            Value_Params = OCFUtils.apply_experiment_params(Value_Params, Common_Params, Algorithm_Params, seed);

            % 提取真实任务类型（用于 Python 端计算信念误差）
            true_task_types = zeros(M, 1);
            true_task_values = zeros(M, 1);
            for j = 1:M
                true_task_types(j)  = tasks_local(j).type;
                true_task_values(j) = tasks_local(j).value;
            end

            %% -- 按条件构造初始信念矩阵并注入 AddPara --
            % init_belief_matrix: N×T，兼容摘要
            % init_belief_tensor: N×M×T，round-0 权威先验
            AddPara_run = AddPara;
            init_b = [];
            init_b_tensor = [];
            init_b_mode = '';
            switch cond_name
                case 'uniform'
                    % 所有智能体相同：均匀分布 [1/T, ..., 1/T]
                    init_b = repmat(belief_uniform, N, 1);  % N×T
                    init_b_tensor = repmat(reshape(init_b, [N, 1, num_task_types]), 1, M, 1);
                    AddPara_run.init_belief = init_b;
                    AddPara_run.init_belief_tensor = init_b_tensor;
                    init_b_mode = 'shared_agent_prior';

                case 'heterogeneous'
                    % 每个 agent-task 直接随机采样一个任务类型概率分布，不再显式依赖真实类型
                    rng(seed + 9999);   % 独立子种子，不干扰场景生成
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

            %% -- 运行 OCF_SAtabu --
            rng(seed);
            [~, history_data] = OCF_SAtabu_global_main(agents_local, tasks_local, AddPara_run, Value_Params);

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
            entry.true_task_values    = true_task_values;   % [M×1] 各任务真实价值
            entry.init_belief_mode    = init_b_mode;
            entry.init_belief_matrix  = init_b;             % [N×T] 本条件的初始信念矩阵
            entry.init_belief_tensor  = init_b_tensor;      % [N×M×T] round-0 权威先验
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
belief_config.num_task_types     = num_task_types;
belief_config.task_type_values   = task_values;
belief_config.task_type_demand_max = task_type_demand_max;
belief_config.num_rounds         = num_rounds;
belief_config.belief_uniform     = belief_uniform;
belief_config.belief_random_dirichlet_alpha = belief_random_dirichlet_alpha;
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
