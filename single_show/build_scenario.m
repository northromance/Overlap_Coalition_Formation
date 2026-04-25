function [WORLD, tasks, agents, task_type_demands] = build_scenario(seed, cfg)
% build_scenario  统一场景生成函数（随机序列与各实验脚本原有内联代码完全对齐）
%
% 用法：
%   [WORLD, tasks, agents, task_type_demands] = build_scenario(seed, cfg)
%
% 输入：
%   seed — 随机种子（整数）
%   cfg  — 场景参数结构体，必须包含以下字段：
%            N, M, K                           维度
%            num_task_types                    任务类型数
%            task_values                       [1×num_task_types] 各类型任务价值
%            task_type_demand_max              [1×num_task_types] 各类型任务资源需求上限
%            （兼容旧字段 task_type1_demand_max / task_type2_demand_max / task_type3_demand_max）
%            resource_exec_time                [1×K] 各资源类型的执行时间
%            WORLD_XMIN, WORLD_XMAX            环境 X 轴范围
%            WORLD_YMIN, WORLD_YMAX            环境 Y 轴范围
%            WORLD_ZMIN, WORLD_ZMAX            环境 Z 轴范围（通常为 0）
%            agent_velocity                    智能体速度
%            agent_detprob_min, agent_detprob_max  探测概率范围
%            agent_Emax_min, agent_Emax_range  最大能量范围
%            agent_fuel                        飞行燃料系数 varpi
%            agent_wait_fuel                   等待燃料系数 gamma
%            agent_beta                        执行成本系数 beta
%            min_resource_value, max_resource_value  智能体资源能力范围
%
% 输出：
%   WORLD              — 环境结构体（含边界与任务价值列表）
%   tasks              — [1×M] 任务结构体数组
%   agents             — [1×N] 智能体结构体数组
%   task_type_demands  — [num_task_types×K] 各类型任务资源需求模板（供 Value_Params 注入）
%
% 注意：函数在入口处重置随机种子，保证与各脚本原有内联代码产生完全相同的随机序列。

rng('default');
rng(seed);

N              = cfg.N;
M              = cfg.M;
K              = cfg.K;
num_task_types = cfg.num_task_types;
task_values     = cfg.task_values(:).';

if numel(task_values) ~= num_task_types
    error('build_scenario:taskValuesSize', ...
        'cfg.task_values must have %d elements, got %d.', ...
        num_task_types, numel(task_values));
end

if isfield(cfg, 'task_type_demand_max') && ~isempty(cfg.task_type_demand_max)
    demand_max_by_type = cfg.task_type_demand_max(:).';
else
    demand_max_by_type = zeros(1, num_task_types);
    for t = 1:num_task_types
        field_name = sprintf('task_type%d_demand_max', t);
        if ~isfield(cfg, field_name)
            error('build_scenario:missingDemandField', ...
                'Missing cfg.%s for task type %d.', field_name, t);
        end
        demand_max_by_type(t) = cfg.(field_name);
    end
end

if isscalar(demand_max_by_type) && num_task_types > 1
    demand_max_by_type = repmat(demand_max_by_type, 1, num_task_types);
end

if numel(demand_max_by_type) ~= num_task_types
    error('build_scenario:demandMaxSize', ...
        'cfg.task_type_demand_max must have %d elements, got %d.', ...
        num_task_types, numel(demand_max_by_type));
end

%% Build WORLD struct
WORLD.XMIN  = cfg.WORLD_XMIN;  WORLD.XMAX = cfg.WORLD_XMAX;
WORLD.YMIN  = cfg.WORLD_YMIN;  WORLD.YMAX = cfg.WORLD_YMAX;
WORLD.ZMIN  = cfg.WORLD_ZMIN;  WORLD.ZMAX = cfg.WORLD_ZMAX;
WORLD.value = task_values;

%% Task type demands（不同任务类型的资源需求模板）
task_type_demands = zeros(num_task_types, K);
for t = 1:num_task_types
    task_type_demands(t, :) = randi([0, demand_max_by_type(t)], 1, K);
end

%% Task durations by resource（各任务类型在各资源上的执行时间）
task_type_duration_by_resource = zeros(num_task_types, K);
for t = 1:num_task_types
    needed = task_type_demands(t, :) > 0;
    task_type_duration_by_resource(t, needed) = cfg.resource_exec_time(needed);
end

%% Tasks generation（生成 M 个任务）
task_priorities = randperm(M);
tasks = struct();

% 位置模式：'manual' 手动坐标，'grid_jitter' 均匀铺满地图，'random' 纯随机（默认）
spread_mode = 'random';
if isfield(cfg, 'task_spread_mode') && ~isempty(cfg.task_spread_mode)
    spread_mode = cfg.task_spread_mode;
end

manual_pos = [];
if isfield(cfg, 'manual_task_positions') && ~isempty(cfg.manual_task_positions)
    manual_pos = cfg.manual_task_positions;   % M×2，单位 cm
end

if strcmp(spread_mode, 'grid_jitter')
    margin = 0.10;   % 离边界留白比例
    jitter = 0.50;   % 格内抖动幅度（0=格心，1=满格；0.5 保证最小间距约 cell_size/2）
    xlo = WORLD.XMIN + margin * (WORLD.XMAX - WORLD.XMIN);
    xhi = WORLD.XMAX - margin * (WORLD.XMAX - WORLD.XMIN);
    ylo = WORLD.YMIN + margin * (WORLD.YMAX - WORLD.YMIN);
    yhi = WORLD.YMAX - margin * (WORLD.YMAX - WORLD.YMIN);
    aspect = (xhi - xlo) / max(yhi - ylo, 1e-9);
    ncols  = max(1, round(sqrt(M * aspect)));
    nrows  = ceil(M / ncols);
    cell_w = (xhi - xlo) / ncols;
    cell_h = (yhi - ylo) / nrows;
end

for j = 1:M
    tasks(j).id       = j;
    tasks(j).priority = task_priorities(j);
    if strcmp(spread_mode, 'manual') && ~isempty(manual_pos) && j <= size(manual_pos, 1)
        tasks(j).x = manual_pos(j, 1);
        tasks(j).y = manual_pos(j, 2);
    elseif strcmp(spread_mode, 'grid_jitter')
        col = mod(j-1, ncols);
        row = floor((j-1) / ncols);
        cx  = xlo + (col + 0.5) * cell_w;
        cy  = ylo + (row + 0.5) * cell_h;
        tasks(j).x = round(cx + (rand()-0.5) * jitter * cell_w);
        tasks(j).y = round(cy + (rand()-0.5) * jitter * cell_h);
    else
        tasks(j).x = round(rand() * (WORLD.XMAX - WORLD.XMIN) + WORLD.XMIN);
        tasks(j).y = round(rand() * (WORLD.YMAX - WORLD.YMIN) + WORLD.YMIN);
    end
    tasks(j).type     = randi(num_task_types, 1, 1);
    tasks(j).value    = WORLD.value(tasks(j).type);
    tasks(j).resource_demand      = task_type_demands(tasks(j).type, :);
    tasks(j).duration_by_resource = task_type_duration_by_resource(tasks(j).type, :);
    tasks(j).duration = max(tasks(j).duration_by_resource);
    tasks(j).WORLD    = WORLD;
end

%% Agents generation（生成 N 个智能体）
agents = struct();
has_init_pos  = isfield(cfg, 'agent_init_positions') && ~isempty(cfg.agent_init_positions);
has_robot_ids = isfield(cfg, 'agent_robot_ids')      && ~isempty(cfg.agent_robot_ids);
init_pos = [];
if has_init_pos
    init_pos = cfg.agent_init_positions;  % [Np × 2]，x_cm / y_cm（已按 robot_id 升序）
end
for i = 1:N
    agents(i).id        = i;
    agents(i).vel       = cfg.agent_velocity;
    if has_init_pos && i <= size(init_pos, 1)
        agents(i).x = init_pos(i, 1);
        agents(i).y = init_pos(i, 2);
    else
        agents(i).x = round(rand() * (WORLD.XMAX - WORLD.XMIN) + WORLD.XMIN);
        agents(i).y = round(rand() * (WORLD.YMAX - WORLD.YMIN) + WORLD.YMIN);
    end
    if has_robot_ids && i <= length(cfg.agent_robot_ids)
        agents(i).robot_id = cfg.agent_robot_ids(i);
    end
    agents(i).detprob   = cfg.agent_detprob_min + (cfg.agent_detprob_max - cfg.agent_detprob_min) * rand();
    agents(i).resources = randi([cfg.min_resource_value, cfg.max_resource_value], K, 1);
    agents(i).Emax      = cfg.agent_Emax_min + cfg.agent_Emax_range * rand();
    agents(i).fuel      = cfg.agent_fuel;
    agents(i).wait_fuel = cfg.agent_wait_fuel;
    agents(i).beta      = cfg.agent_beta;
end

%% Post-process: 确保任务点距所有机器人初始位置 >= min_task_agent_dist
if isfield(cfg, 'min_task_agent_dist') && cfg.min_task_agent_dist > 0
    min_d = cfg.min_task_agent_dist;
    for j = 1:M
        for iter_adj = 1:30
            any_viol = false;
            for i = 1:N
                dx = tasks(j).x - agents(i).x;
                dy = tasks(j).y - agents(i).y;
                dist = sqrt(dx^2 + dy^2);
                if dist < min_d
                    if dist > 1e-9
                        dir = [dx, dy] / dist;
                    else
                        dir = [cos(j*pi/M), sin(j*pi/M)];
                    end
                    tasks(j).x = round(agents(i).x + min_d * dir(1));
                    tasks(j).y = round(agents(i).y + min_d * dir(2));
                    tasks(j).x = max(WORLD.XMIN, min(WORLD.XMAX, tasks(j).x));
                    tasks(j).y = max(WORLD.YMIN, min(WORLD.YMAX, tasks(j).y));
                    any_viol = true;
                end
            end
            if ~any_viol, break; end
        end
    end
end
