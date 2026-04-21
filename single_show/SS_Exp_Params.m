%% SS_Exp_Params.m
% single_show 实验专用参数 —— 仅供 SS_Single_Viz.m 使用

%% ===== 通用超参数 =====
num_rounds = 30;
MaxIter    = 200;
obs_times  = 1000;
Exp_Config.Common = struct();
Exp_Config.Common.num_rounds = num_rounds;

%% ===== 任务价值与类型 =====
task_values    = [500, 1000, 2000];
num_task_types = length(task_values);

%% ===== 公共算法参数 =====
resource_confidence = 0.8;

%% ===== OCF_SAtabu 专属参数 =====
OCF_T0_round            = 100;
OCF_alpha               = 0.95;
OCF_Tmin                = 0.01;
OCF_T_decay             = 0.9;
OCF_T_min_round         = 5;
OCF_T_init_construction = 2;
OCF_K_stable_max        = 10;
OCF_tabu_tenure         = 5;
OCF_p_leave             = 0.3;

%% ===== 统一注入结构 =====
Common_Params = struct();
Common_Params.max_inner_iter      = MaxIter;
Common_Params.resource_confidence = resource_confidence;

Algorithm_Params = struct();
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

%% ===== 世界范围（290cm × 240cm 实验地面）=====
WORLD_XMIN = 0;   WORLD_XMAX = 290;
WORLD_YMIN = 0;   WORLD_YMAX = 240;
WORLD_ZMIN = 0;   WORLD_ZMAX = 0;

%% ===== 智能体基础属性 =====
agent_velocity    = 10;
agent_detprob_min = 0.75;
agent_detprob_max = 0.95;
agent_Emax_min    = 300;
agent_Emax_range  = 100;
agent_fuel        = 1;
agent_wait_fuel   = 0.5;
agent_beta        = 1;

%% ===== 智能体资源能力范围 =====
min_resource_value = 0;
max_resource_value = 4;

%% ===== 任务资源需求模板参数 =====
task_type1_demand_max = 2;
task_type2_demand_max = 5;
task_type3_demand_max = 8;
task_type_demand_max  = [task_type1_demand_max, task_type2_demand_max, task_type3_demand_max];

%% ===== 各资源类型的执行时间（K=6 维）=====
resource_exec_time = [20, 25, 20, 25, 15, 18];

%% ===== 统一场景配置 =====
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

%% ===== SingleViz 实验配置 =====
Exp_Config.SingleViz.SEED = 2495;   % 原 SEEDS(10)，SEEDS = 2486:2536
Exp_Config.SingleViz.N = 5;
Exp_Config.SingleViz.M = 6;
Exp_Config.SingleViz.K = 6;
Exp_Config.SingleViz.AddPara = struct( ...
    'verbose', 1, ...
    'enable_belief_update', true, ...
    'control', 1);
