%% Exp_Params.m
% 实验共享参数文件 —— 被以下脚本通过 run() 引用：
%   Batch_VaryN.m / Batch_VaryM.m / Batch_Belief.m / Batch_Ablation.m / Single_Viz.m
%
% 修改此处即可统一调整所有实验的超参数，无需逐个文件修改。
% 实验专属参数（SEEDS、N_VALUES、algorithms_to_run_ids 等）仍在各脚本中单独设置。

%% ===== 通用超参数 =====
num_rounds = 80;   % 外循环轮数（正式运行值；测试时在各脚本中覆盖此变量）
MaxIter    = 80;   % 每轮最大内层迭代次数
obs_times  = 50;    % 效用/观测统计参数（传入 OCFUtils.init_value_params）
xp_Config = struct();
Exp_Config.Common = struct();
Exp_Config.Common.num_rounds = num_rounds;
Exp_Config.Common.SEEDS = 2486:1:2496; % 随机种子列表（21 个种子，正式运行值；测试时在各脚本中覆盖此变量）

%% ===== 任务价值与类型 =====
task_values    = [500, 1000, 2000];   % 三类任务的基础奖励价值
num_task_types = length(task_values); % 任务类型总数（= 3）

%% ===== 公共算法参数 =====
resource_confidence = 0.7;   % 资源需求分位置信度（所有基于 belief 的效用/缺口计算共用）

%% ===== Huo2025 专属参数 =====
Huo_L_tabu       = 10;   % Huo2025 禁忌表长度
Huo_K_stable_max = 10;   % Huo2025 稳定性阈值

%% ===== Qi2023 专属参数 =====
Qi_L_tabu       = 10;   % Qi2023 禁忌表长度
Qi_K_stable_max = 10;   % Qi2023 稳定性阈值
Qi_Gamma_init   = 1;    % Qi2023 初始 Boltzmann 系数
Qi_Gamma_max    = 40;   % Qi2023 最大 Boltzmann 系数
Qi_p_leave      = 0.4;  % Qi2023 离开概率

%% ===== Shi2024 专属参数 =====
Shi_L_tabu       = 10;   % Shi2024 禁忌表长度
Shi_K_stable_max = 10;   % Shi2024 稳定性阈值
Shi_Gamma_init   = 5;    % Shi2024 初始 Boltzmann 系数
Shi_Gamma_max    = 40;   % Shi2024 最大 Boltzmann 系数
Shi_p_leave      = 0.4;  % Shi2024 离开概率

%% ===== OCF_SAtabu 专属参数 =====
OCF_T0_round            = 130;   % OCF_SAtabu 每轮开始时的初始温度
OCF_alpha               = 0.95;   % OCF_SAtabu 轮内退火冷却率
OCF_Tmin                = 0.01;  % OCF_SAtabu 轮内最低温度
OCF_T_decay             = 0.95;   % OCF_SAtabu 轮间温度衰减系数
OCF_T_min_round         = 15;     % OCF_SAtabu 每轮初始温度下界
OCF_T_init_construction = 2;     % OCF_SAtabu 初始构造温度
OCF_K_stable_max        = 10;    % OCF_SAtabu 稳定性阈值
OCF_tabu_tenure         = 5;    % OCF_SAtabu 禁忌期限
OCF_p_leave             = 0.3;   % OCF_SAtabu 离开概率

%% ===== 统一注入结构 =====
Common_Params = struct();
Common_Params.max_inner_iter      = MaxIter;
Common_Params.resource_confidence = resource_confidence;

Algorithm_Params = struct();
Algorithm_Params.Huo = struct( ...
    'L_tabu', Huo_L_tabu, ...
    'K_stable_max', Huo_K_stable_max);
Algorithm_Params.Qi = struct( ...
    'L_tabu', Qi_L_tabu, ...
    'K_stable_max', Qi_K_stable_max, ...
    'Gamma_init', Qi_Gamma_init, ...
    'Gamma_max', Qi_Gamma_max, ...
    'p_leave', Qi_p_leave);
Algorithm_Params.Shi = struct( ...
    'L_tabu', Shi_L_tabu, ...
    'K_stable_max', Shi_K_stable_max, ...
    'Gamma_init', Shi_Gamma_init, ...
    'Gamma_max', Shi_Gamma_max, ...
    'p_leave', Shi_p_leave);
Algorithm_Params.OCF = struct( ...
    'T0_round', OCF_T0_round, ...
    'alpha', OCF_alpha, ...
    'Tmin', OCF_Tmin, ...
    'T_decay', OCF_T_decay, ...
    'T_min_round', OCF_T_min_round, ...
    'T_init_construction', OCF_T_init_construction, ...
    'K_stable_max', OCF_K_stable_max, ...
    'tabu_tenure', OCF_tabu_tenure, ...
    'p_leave', OCF_p_leave);

%% ===== 世界范围（二维平面，Z 固定为 0）=====
WORLD_XMIN = 0;   WORLD_XMAX = 100;
WORLD_YMIN = 0;   WORLD_YMAX = 100;
WORLD_ZMIN = 0;   WORLD_ZMAX = 0;

%% ===== 智能体基础属性 =====
agent_velocity    = 2;      % 速度（统一）
agent_detprob_min = 0.75;   % 探测/感知概率下限
agent_detprob_max = 1;    % 探测/感知概率上限
agent_Emax_min    = 300;    % 最大能量下限
agent_Emax_range  = 50;     % 最大能量随机浮动范围
agent_fuel        = 1;      % 飞行燃料消耗系数 varpi（= agents.fuel）
agent_wait_fuel   = 0.5;    % 等待燃料消耗系数 gamma（= agents.wait_fuel）
agent_beta        = 1;      % 执行成本系数 beta（= agents.beta）

%% ===== 智能体资源能力范围 =====
min_resource_value = 0;   % 每维资源能力最小值
max_resource_value = 4;   % 每维资源能力最大值

%% ===== 任务资源需求模板参数 =====
task_type1_demand_max = 2;   % 类型1任务各维资源需求上限（低价值任务）
task_type2_demand_max = 5;   % 类型2任务各维资源需求上限（中等任务）
task_type3_demand_max = 8;   % 类型3任务各维资源需求上限（高价值任务）
task_type_demand_max  = [task_type1_demand_max, task_type2_demand_max, task_type3_demand_max];

%% ===== 各资源类型的执行时间（K=6 维）=====
% resource_exec_time(k) = 第 k 类资源执行所需时间
resource_exec_time = [50, 65, 50, 60, 35, 45];

%% ===== 统一场景配置（被 build_scenario 使用，N/M/K 由调用方按需覆盖）=====
Exp_Config.ScenarioCfg.num_task_types        = num_task_types;
Exp_Config.ScenarioCfg.task_values           = task_values;
Exp_Config.ScenarioCfg.task_type_demand_max  = task_type_demand_max;
Exp_Config.ScenarioCfg.task_type1_demand_max = task_type1_demand_max;
Exp_Config.ScenarioCfg.task_type2_demand_max = task_type2_demand_max;
Exp_Config.ScenarioCfg.task_type3_demand_max = task_type3_demand_max;
Exp_Config.ScenarioCfg.resource_exec_time    = resource_exec_time;
Exp_Config.ScenarioCfg.WORLD_XMIN = WORLD_XMIN;
Exp_Config.ScenarioCfg.WORLD_XMAX = WORLD_XMAX;
Exp_Config.ScenarioCfg.WORLD_YMIN = WORLD_YMIN;
Exp_Config.ScenarioCfg.WORLD_YMAX = WORLD_YMAX;
Exp_Config.ScenarioCfg.WORLD_ZMIN = WORLD_ZMIN;
Exp_Config.ScenarioCfg.WORLD_ZMAX = WORLD_ZMAX;
Exp_Config.ScenarioCfg.agent_velocity     = agent_velocity;
Exp_Config.ScenarioCfg.agent_detprob_min  = agent_detprob_min;
Exp_Config.ScenarioCfg.agent_detprob_max  = agent_detprob_max;
Exp_Config.ScenarioCfg.agent_Emax_min     = agent_Emax_min;
Exp_Config.ScenarioCfg.agent_Emax_range   = agent_Emax_range;
Exp_Config.ScenarioCfg.agent_fuel         = agent_fuel;
Exp_Config.ScenarioCfg.agent_wait_fuel    = agent_wait_fuel;
Exp_Config.ScenarioCfg.agent_beta         = agent_beta;
Exp_Config.ScenarioCfg.min_resource_value = min_resource_value;
Exp_Config.ScenarioCfg.max_resource_value = max_resource_value;

%% ===== 实验脚本专属配置（集中放在文件末尾）=====

% Batch_VaryN
Exp_Config.VaryN.SEEDS = Exp_Config.Common.SEEDS;
Exp_Config.VaryN.N_VALUES = [4, 6, 8, 10, 12, 14, 16];
Exp_Config.VaryN.M = 10;
Exp_Config.VaryN.K = 6;
Exp_Config.VaryN.inner_loop_round = 50;   % 保存第 N 轮内循环轨迹（用于图3a）
Exp_Config.VaryN.algorithms_to_run_ids = [2, 3, 4, 7];
Exp_Config.VaryN.AddPara = struct( ...
    'verbose', 1, ...
    'enable_belief_update', true, ...
    'control', 1);

% Batch_VaryM
Exp_Config.VaryM.SEEDS = Exp_Config.Common.SEEDS;
Exp_Config.VaryM.M_VALUES = [16];
Exp_Config.VaryM.N = 8;
Exp_Config.VaryM.K = 6;
Exp_Config.VaryM.algorithms_to_run_ids = [2, 3, 4, 7];
Exp_Config.VaryM.AddPara = struct( ...
    'verbose', 1, ...
    'enable_belief_update', true, ...
    'control', 1);

% Batch_Belief
Exp_Config.Belief.SEEDS = Exp_Config.Common.SEEDS;
Exp_Config.Belief.N = 10;
Exp_Config.Belief.M = 10;
Exp_Config.Belief.K = 6;
Exp_Config.Belief.CONDITIONS = {'uniform', 'heterogeneous'};
Exp_Config.Belief.task_values = [500, 800, 1100, 1400, 1700, 2000];  % 6类任务的真实价值档位（从低到高）
Exp_Config.Belief.task_type_demand_max = [2, 3, 4, 5, 6, 8];         % 与6类任务一一对应的资源需求上限，通常数值越大任务越“重”
belief_num_types = numel(Exp_Config.Belief.task_values);             % T=6，用于统一生成 belief 向量/矩阵维度
% uniform: 所有智能体使用相同均匀先验 [1/T, ..., 1/T]
% heterogeneous: 对每个 agent-task 直接随机采样一个任务类型概率分布并注入
Exp_Config.Belief.belief_uniform = ones(1, belief_num_types) / belief_num_types;  % 完全无偏好先验
Exp_Config.Belief.belief_random_dirichlet_alpha = 0.35 * ones(1, belief_num_types);
% belief_random_dirichlet_alpha:
%   heterogeneous 条件下，对每个 agent-task 的初始 belief 直接从 Dirichlet(alpha) 随机采样。
%   alpha < 1  -> 更尖锐、更容易出现“明显偏向某一类型”的随机初始信念
%   alpha = 1  -> 在概率单纯形上近似均匀随机
%   alpha > 1  -> 更平缓、更接近均匀分布
%   当前设为 0.35，是为了让初始 belief 更随机、更极端，而不是刻意靠近真实类型。
Exp_Config.Belief.AddPara = struct( ...
    'verbose', 1, ...
    'enable_belief_update', true, ...
    'control', 1);

% Batch_Ablation
Exp_Config.Ablation.SEEDS = Exp_Config.Common.SEEDS;
Exp_Config.Ablation.N_VALUES = [10];
Exp_Config.Ablation.M = 10;
Exp_Config.Ablation.K = 6;
Exp_Config.Ablation.CONDITIONS = {'belief_on', 'belief_off'};
Exp_Config.Ablation.AddPara = struct( ...
    'verbose', 1, ...
    'enable_belief_update', true, ...
    'control', 1);

% Single_Viz
Exp_Config.SingleViz.SEED = Exp_Config.Common.SEEDS(1);
Exp_Config.SingleViz.N = 10;
Exp_Config.SingleViz.M = 10;
Exp_Config.SingleViz.K = 6;
Exp_Config.SingleViz.AddPara = struct( ...
    'verbose', 1, ...
    'enable_belief_update', true, ...
    'control', 1);
