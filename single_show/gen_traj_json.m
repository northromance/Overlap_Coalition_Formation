function gen_traj_json(viz_data, dt, out_path)
% GEN_TRAJ_JSON  从 viz_data 生成轨迹 JSON，供动画演示及实物对接。
%
% 当 viz_data 含 all_rounds_timing 字段时输出多轮次格式（rounds 数组）；
% 否则退化为单轮格式（向后兼容）。
%
% 输入:
%   viz_data  — SS_Single_Viz 输出的结构体
%   dt        — 时间步长，默认 1.0
%   out_path  — 输出路径，默认 'trajectory.json'

if nargin < 2 || isempty(dt),       dt = 1.0; end
if nargin < 3 || isempty(out_path), out_path = 'trajectory.json'; end

agents = viz_data.agents;
tasks  = viz_data.tasks;
N      = viz_data.N;
M      = viz_data.M;
K      = viz_data.K;

%% 任务坐标（静止，所有轮次共用）
task_list = cell(M, 1);
for j = 1:M
    task_list{j} = struct( ...
        'id',    tasks(j).id, ...
        'x',     tasks(j).x, ...
        'y',     tasks(j).y, ...
        'type',  tasks(j).type, ...
        'value', tasks(j).value);
end

%% 世界范围
w = viz_data.world_bounds;
world_struct = struct('xmin', w.xmin, 'xmax', w.xmax, 'ymin', w.ymin, 'ymax', w.ymax);

%% 多轮次 or 单轮次
if isfield(viz_data, 'all_rounds_timing') && ~isempty(viz_data.all_rounds_timing)
    %% ===== 多轮次模式 =====
    num_r = numel(viz_data.all_rounds_timing);

    % 每轮 coalition_utility（若有）
    has_cu = isfield(viz_data, 'convergence_utility') && ...
             numel(viz_data.convergence_utility) == num_r;

    round_list = cell(num_r, 1);
    for r = 1:num_r
        timing_r = viz_data.all_rounds_timing{r};

        T_max_r = 0;
        for i = 1:N
            if ~isempty(timing_r(i).mission_end_time)
                T_max_r = max(T_max_r, timing_r(i).mission_end_time);
            end
        end
        time_axis_r = 0 : dt : T_max_r;
        n_frames_r  = numel(time_axis_r);

        cu = NaN;
        if has_cu, cu = viz_data.convergence_utility(r); end

        agent_list_r = build_agent_list(agents, tasks, timing_r, N, time_axis_r, n_frames_r);

        round_list{r} = struct( ...
            'round_id',         r, ...
            'T_max',            T_max_r, ...
            'n_frames',         n_frames_r, ...
            'coalition_utility', cu, ...
            'agents',           {agent_list_r});
    end

    out = struct( ...
        'meta', struct( ...
            'N', N, 'M', M, 'K', K, ...
            'seed', viz_data.seed, ...
            'num_rounds', num_r, ...
            'dt', dt, ...
            'world', world_struct), ...
        'tasks',  {task_list}, ...
        'rounds', {round_list});

    fprintf('  模式: 多轮次，共 %d 轮\n', num_r);

else
    %% ===== 单轮次兼容模式 =====
    timing = viz_data.timing;

    T_max = 0;
    for i = 1:N
        if ~isempty(timing(i).mission_end_time)
            T_max = max(T_max, timing(i).mission_end_time);
        end
    end
    time_axis = 0 : dt : T_max;
    n_frames  = numel(time_axis);

    agent_list = build_agent_list(agents, tasks, timing, N, time_axis, n_frames);

    out = struct( ...
        'meta', struct( ...
            'N', N, 'M', M, 'K', K, ...
            'seed', viz_data.seed, ...
            'dt', dt, 'T_max', T_max, ...
            'world', world_struct), ...
        'tasks',  {task_list}, ...
        'agents', {agent_list});

    fprintf('  模式: 单轮次，T_max=%.1f，帧数=%d\n', T_max, n_frames);
end

%% 写入文件
json_str = jsonencode(out, 'PrettyPrint', true);
fid = fopen(out_path, 'w', 'n', 'UTF-8');
if fid == -1
    error('gen_traj_json:fileOpen', '无法写入文件: %s', out_path);
end
fwrite(fid, json_str, 'char');
fclose(fid);
fprintf('轨迹 JSON 已保存至: %s\n', out_path);
end


%% ===== 辅助：为一组 timing 生成 agent_list =====
function agent_list = build_agent_list(agents, tasks, timing, N, time_axis, n_frames)
agent_list = cell(N, 1);
for i = 1:N
    p0  = [agents(i).x, agents(i).y];
    vel = agents(i).vel;
    seq = timing(i).task_sequence;
    st  = timing(i).start_times(:);
    ct  = timing(i).completion_times(:);

    frames = repmat(struct('t', 0, 'x', 0, 'y', 0, 'state', 'idle'), n_frames, 1);
    for fi = 1:n_frames
        t = time_axis(fi);
        [px, py, state] = agent_pos_at(t, p0, vel, seq, st, ct, tasks);
        frames(fi).t     = t;
        frames(fi).x     = px;
        frames(fi).y     = py;
        frames(fi).state = state;
    end

    % 个人到达时刻
    p_tmp = p0;  t_tmp = 0;
    arrival_times = zeros(size(st));
    for jj = 1:numel(seq)
        p_tgt = [tasks(seq(jj)).x, tasks(seq(jj)).y];
        fly_t_tmp = norm(p_tgt - p_tmp) / max(vel, 1e-9);
        arrival_times(jj) = t_tmp + fly_t_tmp;
        p_tmp = p_tgt;
        t_tmp = ct(jj);
    end

    agent_list{i} = struct( ...
        'id',               agents(i).id, ...
        'start_x',          p0(1), ...
        'start_y',          p0(2), ...
        'task_sequence',    seq(:)', ...
        'arrival_times',    arrival_times(:)', ...
        'start_times',      st(:)', ...
        'completion_times', ct(:)', ...
        'mission_end_time', timing(i).mission_end_time, ...
        'frames',           frames);
end
end


%% ===== 内部函数：计算单个智能体在时刻 t 的位置与状态 =====
function [px, py, state] = agent_pos_at(t, p0, vel, seq, st, ct, tasks)
if isempty(seq)
    px = p0(1); py = p0(2); state = 'idle';
    return;
end

n_tasks = numel(seq);
tol     = 1e-9;
p_prev  = p0;
t_prev  = 0;

for j = 1:n_tasks
    task_id  = seq(j);
    p_curr   = [tasks(task_id).x, tasks(task_id).y];
    dist     = norm(p_curr - p_prev);
    fly_t    = dist / max(vel, tol);
    t_arrive = t_prev + fly_t;
    t_start  = st(j);
    t_done   = ct(j);

    if t < t_arrive - tol
        if dist < tol
            ratio = 1;
        else
            ratio = max(0, min(1, (t - t_prev) / fly_t));
        end
        pos = p_prev + ratio * (p_curr - p_prev);
        px = pos(1); py = pos(2); state = 'flying';
        return;
    end
    if t < t_start - tol
        px = p_curr(1); py = p_curr(2); state = 'waiting';
        return;
    end
    if t < t_done - tol
        px = p_curr(1); py = p_curr(2); state = 'executing';
        return;
    end

    p_prev = p_curr;
    t_prev = t_done;
end

dist_ret  = norm(p0 - p_prev);
fly_t_ret = dist_ret / max(vel, tol);
t_end     = t_prev + fly_t_ret;

if t < t_end - tol
    if dist_ret < tol
        ratio = 1;
    else
        ratio = max(0, min(1, (t - t_prev) / fly_t_ret));
    end
    pos = p_prev + ratio * (p0 - p_prev);
    px = pos(1); py = pos(2); state = 'returning';
else
    px = p0(1); py = p0(2); state = 'done';
end
end
