%% SS_Exp_Params.m
% single_show 实验专用参数 —— 仅供 SS_Single_Viz.m 使用

%% ===== 通用超参数 =====
num_rounds = 60;
MaxIter    = 80;
obs_times  = 100;    % 每轮每任务观测次数：小→信念收敛慢→多轮才收敛→效用曲线逐步上升
Exp_Config.Common = struct();
Exp_Config.Common.num_rounds = num_rounds;

%% ===== 任务价值与类型 =====
task_values    = [500, 1000, 2000];
num_task_types = length(task_values);

%% ===== 公共算法参数 =====
resource_confidence = 0.75;  % 低置信度→初始分配保守→完成率低→后续随信念收敛逐步提升

%% ===== OCF_SAtabu 专属参数 =====
OCF_T0_round            = 100;
OCF_alpha               = 0.95;
OCF_Tmin                = 0.01;
OCF_T_decay             = 0.95;
OCF_T_min_round         = 10;
OCF_T_init_construction = 5;    % 高温→初始构造更随机→第1轮联盟结构较差→后续SA优化改进明显
OCF_K_stable_max        = 10;
OCF_tabu_tenure         = 20;
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

%% ===== 世界范围（从 initial_info.csv 读取场地角点）=====
WORLD_ZMIN = 0; WORLD_ZMAX = 0;
if exist('script_dir', 'var')
    init_info_path = fullfile(script_dir, 'initial_info.csv');
else
    init_info_path = 'initial_info.csv';
end
fid_w = fopen(init_info_path, 'r');
if fid_w ~= -1
    fgetl(fid_w);  % 跳过元数据行
    fgetl(fid_w);  % 跳过表头
    init_raw = textscan(fid_w, '%d %f %f %f %f %f', 'Delimiter', ',');
    fclose(fid_w);
    WORLD_XMIN = min(init_raw{2});  WORLD_XMAX = max(init_raw{2});
    WORLD_YMIN = min(init_raw{3});  WORLD_YMAX = max(init_raw{3});
    fprintf('[SS_Exp_Params] 场地标定(initial_info): WORLD=[%.1f,%.1f]×[%.1f,%.1f] cm  (%.0f×%.0f)\n', ...
        WORLD_XMIN, WORLD_XMAX, WORLD_YMIN, WORLD_YMAX, ...
        WORLD_XMAX-WORLD_XMIN, WORLD_YMAX-WORLD_YMIN);
else
    WORLD_XMIN = 96;  WORLD_XMAX = 340;
    WORLD_YMIN = 29;  WORLD_YMAX = 225;
    fprintf('[SS_Exp_Params] 未找到 initial_info.csv，使用默认范围 290×240 cm\n');
end

%% ===== 智能体基础属性 =====
agent_velocity    = 10;
agent_detprob_min = 0.75;
agent_detprob_max = 0.95;
agent_Emax_min    = 500;
agent_Emax_range  = 100;
agent_fuel        = 3;
agent_wait_fuel   = 1;
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
Exp_Config.SingleViz.SEED = 2450;   % 原 SEEDS(10)，SEEDS = 2486:2536
Exp_Config.SingleViz.N = 5;
Exp_Config.SingleViz.M = 5;
Exp_Config.SingleViz.K = 6;
Exp_Config.SingleViz.dt_sample  = 0.1;  % 轨迹采样间隔（时间单位）；越小帧越密
Exp_Config.ScenarioCfg.task_spread_mode = 'grid_jitter';  % 任务均匀分布（实物演示）
Exp_Config.ScenarioCfg.min_task_agent_dist = 40;          % 任务离机器人初始位置最小距离（cm）
Exp_Config.SingleViz.AddPara = struct( ...
    'verbose', 1, ...
    'enable_belief_update', true, ...
    'control', 1);

%% ===== 机器人初始位置来源开关 =====
% true  = 实物实验：从 aruco_data*.csv 读取真实位置，N/位置/robot_id 全以 CSV 为准
% false = 仿真调试：忽略 CSV，用上方配置的 N 随机生成位置
use_csv_robot_positions = true;

%% ===== 从 CSV 读取智能体初始位置（aruco 测量结果）=====
% CSV 格式：第1行元数据、第2行表头、第3行起为各机器人数据
% 列：robot_id, x_cm, y_cm, angle_deg, x_pixel, y_pixel
if use_csv_robot_positions
    if exist('script_dir', 'var')
        csv_candidates = dir(fullfile(script_dir, 'aruco_data*.csv'));
    else
        csv_candidates = dir('aruco_data*.csv');
    end

    if ~isempty(csv_candidates)
        [~, newest_idx] = max([csv_candidates.datenum]);
        agent_csv_path = fullfile(csv_candidates(newest_idx).folder, ...
                                  csv_candidates(newest_idx).name);
        fprintf('[SS_Exp_Params] 使用 CSV 文件: %s\n', csv_candidates(newest_idx).name);

        fid = fopen(agent_csv_path, 'r');
        fgetl(fid);  % 跳过第1行元数据（image_w, image_h, scale）
        fgetl(fid);  % 跳过第2行表头
        data_raw = textscan(fid, '%d %f %f %f %f %f', 'Delimiter', ',');
        fclose(fid);

        agent_robot_ids = int32(data_raw{1});  % 列向量
        x_cm_raw        = data_raw{2};
        y_cm_raw        = data_raw{3};

        % 按 robot_id 升序排列，保证顺序确定性
        [agent_robot_ids, sort_idx] = sort(agent_robot_ids);
        agent_init_positions = [x_cm_raw(sort_idx), y_cm_raw(sort_idx)];  % [N_csv × 2]，cm

        N_from_csv = length(agent_robot_ids);
        fprintf('[SS_Exp_Params] 读取到 %d 个机器人，robot_ids = %s\n', ...
                N_from_csv, mat2str(agent_robot_ids(:)'));
    else
        agent_robot_ids      = [];
        agent_init_positions = [];
        N_from_csv           = Exp_Config.SingleViz.N;
        fprintf('[SS_Exp_Params] 未找到 aruco_data*.csv，使用随机初始位置\n');
    end
else
    agent_robot_ids      = [];
    agent_init_positions = [];
    N_from_csv           = Exp_Config.SingleViz.N;
    fprintf('[SS_Exp_Params] use_csv_robot_positions=false，N=%d 随机生成初始位置\n', N_from_csv);
end

%% ===== 用机器人坐标外包矩形覆盖世界范围 =====
if use_csv_robot_positions && ~isempty(agent_init_positions)
    WORLD_XMIN = min(agent_init_positions(:,1));
    WORLD_XMAX = max(agent_init_positions(:,1));
    WORLD_YMIN = min(agent_init_positions(:,2));
    WORLD_YMAX = max(agent_init_positions(:,2));
    fprintf('[SS_Exp_Params] 世界范围来自机器人坐标: WORLD=[%.1f,%.1f]×[%.1f,%.1f] cm\n', ...
        WORLD_XMIN, WORLD_XMAX, WORLD_YMIN, WORLD_YMAX);
    Exp_Config.ScenarioCfg.WORLD_XMIN = WORLD_XMIN;
    Exp_Config.ScenarioCfg.WORLD_XMAX = WORLD_XMAX;
    Exp_Config.ScenarioCfg.WORLD_YMIN = WORLD_YMIN;
    Exp_Config.ScenarioCfg.WORLD_YMAX = WORLD_YMAX;
end

Exp_Config.SingleViz.agent_robot_ids      = agent_robot_ids;
Exp_Config.SingleViz.agent_init_positions = agent_init_positions;
% 仅在 CSV 有数据时才覆盖 N
if ~isempty(agent_robot_ids)
    Exp_Config.SingleViz.N = N_from_csv;
end
