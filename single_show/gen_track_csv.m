function gen_track_csv(viz_data, dt, out_dir)
% GEN_TRACK_CSV  从 viz_data 生成 track_round_*.csv，供实物机器人对接。
%
% 自动选取 4 个代表轮次（第1轮、1/3轮、2/3轮、最后轮），
% 每轮输出一个 CSV，格式：
%   frame, robot_id, sim_x, sim_y, real_x, real_y
%
% 路径规划：以调度表目标点为吸引力目标，直接用 APF 逐帧导航，
% 同时保持机器人间距 >= d_safe（无需预先计算直线轨迹）。

if nargin < 2 || isempty(dt),      dt = 1.0; end
if nargin < 3 || isempty(out_dir), out_dir = 'results'; end

agents = viz_data.agents;
tasks  = viz_data.tasks;
N      = viz_data.N;

if ~isfield(viz_data, 'all_rounds_timing') || isempty(viz_data.all_rounds_timing)
    fprintf('[gen_track_csv] viz_data 不含 all_rounds_timing，跳过 CSV 导出。\n');
    return;
end

num_r = numel(viz_data.all_rounds_timing);

% 选 4 个代表轮次（含首尾）
round_ids = unique([1, max(1,floor(num_r/3)), max(1,floor(2*num_r/3)), num_r]);

if ~exist(out_dir, 'dir'), mkdir(out_dir); end

d_safe = 45.0;  % 机器人间最小安全距离（cm）

for r = round_ids
    timing_r = viz_data.all_rounds_timing{r};

    % 预收集 robot_id 和速度
    rid_list = zeros(1, N);
    vel_vec  = zeros(N, 1);
    for i = 1:N
        if isfield(agents(i), 'robot_id') && ~isempty(agents(i).robot_id)
            rid_list(i) = double(agents(i).robot_id);
        else
            rid_list(i) = double(agents(i).id);
        end
        vel_vec(i) = agents(i).vel;
    end

    % 计算本轮最大仿真时刻
    T_max_r = 0;
    for i = 1:N
        ct_i = timing_r(i).completion_times(:);
        if isempty(ct_i), continue; end
        seq_i  = timing_r(i).task_sequence;
        p_last = [tasks(seq_i(end)).x, tasks(seq_i(end)).y];
        p0_i   = [agents(i).x, agents(i).y];
        vel_i  = agents(i).vel;
        t_ret  = ct_i(end) + norm(p0_i - p_last) / max(vel_i, 1e-9);
        T_max_r = max(T_max_r, t_ret);
    end
    t_arr = 0 : dt : T_max_r;

    % 机器人初始位置
    pos_cur = zeros(N, 2);
    for i = 1:N
        pos_cur(i,:) = [agents(i).x, agents(i).y];
    end

    out_path = fullfile(out_dir, sprintf('track_round_%d.csv', r));
    fid = fopen(out_path, 'w', 'n', 'UTF-8');
    if fid == -1
        error('gen_track_csv:fileOpen', '无法写入文件: %s', out_path);
    end
    fprintf(fid, 'frame,robot_id,sim_x,sim_y,real_x,real_y\n');

    all_frames = zeros(0, 4);  % [raw_frame, rid, x, y]

    for ti = 1:numel(t_arr)
        t_cur   = t_arr(ti);
        frame_t = round(t_cur * 10);

        % 确定各机器人当前目标点（调度表：第一个尚未完成的任务中心）
        targets = zeros(N, 2);
        for i = 1:N
            [tx, ty] = get_target(t_cur, [agents(i).x, agents(i).y], ...
                timing_r(i).task_sequence, timing_r(i).completion_times(:), tasks);
            targets(i,:) = [tx, ty];
        end

        % 标记归航中的机器人（所有任务已完成，目标为初始点）
        is_home = false(N, 1);
        for i = 1:N
            ct_i = timing_r(i).completion_times(:);
            is_home(i) = isempty(ct_i) || (t_cur >= ct_i(end));
        end

        % APF 逐帧导航：向目标移动，同时保持安全距离
        pos_cur = apf_navigate(pos_cur, targets, d_safe, vel_vec, dt, is_home);

        for i = 1:N
            all_frames(end+1, :) = [frame_t, rid_list(i), pos_cur(i,1), pos_cur(i,2)]; %#ok<AGROW>
        end
    end

    % 重编帧号为 0, 10, 20, ...
    all_frames = sortrows(all_frames, [1, 2]);
    unique_ft  = unique(all_frames(:, 1));
    for uf = 1:numel(unique_ft)
        all_frames(all_frames(:,1) == unique_ft(uf), 1) = (uf-1)*10;
    end

    for k = 1:size(all_frames, 1)
        fprintf(fid, '%d,%d,%.7f,%.7f,%.7f,%.7f\n', ...
            all_frames(k,1), all_frames(k,2), 0.0, 0.0, all_frames(k,3), all_frames(k,4));
    end
    fclose(fid);
    n_frames = numel(unique_ft);
    fprintf('[gen_track_csv] 轮次 %d → %s  (%d 帧×%d 机器人=%d 行, dt=%.2f)\n', ...
        r, out_path, n_frames, N, size(all_frames,1), dt);

    % === 生成演示用稀疏采样文件（每 subsample 帧取 1 帧）===
    subsample = 20;
    demo_dir  = fullfile(out_dir, 'demo');
    if ~exist(demo_dir, 'dir'), mkdir(demo_dir); end
    demo_path = fullfile(demo_dir, sprintf('track_round_%d.csv', r));

    unique_ft_all = unique(all_frames(:, 1));
    demo_ft       = unique_ft_all(1 : subsample : end);
    mask          = ismember(all_frames(:, 1), demo_ft);
    demo_frames   = all_frames(mask, :);

    demo_unique = unique(demo_frames(:, 1));
    for du = 1:numel(demo_unique)
        demo_frames(demo_frames(:,1) == demo_unique(du), 1) = (du-1)*10;
    end

    fid_d = fopen(demo_path, 'w', 'n', 'UTF-8');
    fprintf(fid_d, 'frame,robot_id,sim_x,sim_y,real_x,real_y\n');
    for k = 1:size(demo_frames, 1)
        fprintf(fid_d, '%d,%d,%.7f,%.7f,%.7f,%.7f\n', ...
            demo_frames(k,1), demo_frames(k,2), 0.0, 0.0, demo_frames(k,3), demo_frames(k,4));
    end
    fclose(fid_d);
    fprintf('[gen_track_csv] 演示文件 → %s  (%d 帧×%d 机器人=%d 行, 间隔=%d)\n', ...
        demo_path, numel(demo_unique), N, size(demo_frames,1), subsample);
end

%% 导出任务点（供 play_traj.py 绘图）
tasks_path = fullfile(out_dir, 'tasks.csv');
fid_t = fopen(tasks_path, 'w', 'n', 'UTF-8');
if fid_t ~= -1
    fprintf(fid_t, 'task_id,x,y,type,value\n');
    for j = 1:numel(tasks)
        fprintf(fid_t, '%d,%.4f,%.4f,%d,%d\n', ...
            j, tasks(j).x, tasks(j).y, tasks(j).type, tasks(j).value);
    end
    fclose(fid_t);
    fprintf('[gen_track_csv] 任务点 → %s  (%d 个任务)\n', tasks_path, numel(tasks));

    demo_dir_t = fullfile(out_dir, 'demo');
    if ~exist(demo_dir_t, 'dir'), mkdir(demo_dir_t); end
    copyfile(tasks_path, fullfile(demo_dir_t, 'tasks.csv'));
    fprintf('[gen_track_csv] tasks.csv → %s\n', fullfile(demo_dir_t, 'tasks.csv'));
end
end


%% ===== APF 逐帧导航：向目标移动 + 安全距离排斥 =====
function pos = apf_navigate(pos, targets, d_safe, vel_vec, dt, is_home)
% 各机器人向其目标点移动一步（步长 = vel*dt），
% 通过排斥力保持两两间距 >= d_safe。
% 任务目标设置 d_task_safe 排斥半径：多机器人共享任务时分散在任务中心周围。
% 归航目标（is_home=true）不施加排斥，允许机器人精确回到初始点。
% 所有位移同步计算，避免顺序依赖。
N           = size(pos, 1);
tol         = 1e-9;
k_rep       = 3.0;
d_task_safe = 10.0;  % 任务点排斥半径（cm）

delta = zeros(N, 2);

for i = 1:N
    max_step = vel_vec(i) * dt;

    to_target = targets(i,:) - pos(i,:);
    d_target  = norm(to_target);
    if d_target > tol
        if is_home(i)
            % 归航：直接吸引，无排斥，机器人可回到精确初始点
            dir = to_target / d_target;
        else
            % 任务目标：d_task_safe 软边界，平衡点在 ~10cm 处
            att_scale = (d_target - d_task_safe) / d_target;
            dir = att_scale * (to_target / d_target);
        end
    else
        dir = [0, 0];
    end

    % 机器人间排斥力：线性弹簧，d < d_safe 时生效
    for j = 1:N
        if j == i, continue; end
        diff = pos(i,:) - pos(j,:);
        d    = norm(diff);
        if d < d_safe - tol
            if d > tol
                rep_dir = diff / d;
            else
                angle   = 2*pi*(i-1)/N;
                rep_dir = [cos(angle), sin(angle)];
            end
            dir = dir + k_rep * (d_safe - d) / d_safe * rep_dir;
        end
    end

    % 归一化合力方向，以 max_step 定速前进
    d_dir = norm(dir);
    if d_dir > tol
        delta(i,:) = max_step * dir / d_dir;
    end
end

pos = pos + delta;
end


%% ===== 根据调度表确定机器人在时刻 t 的目标点 =====
function [tx, ty] = get_target(t, p0, seq, ct, tasks)
% 返回机器人在时刻 t 应飞向/停留的任务中心坐标。
%   t < ct(j): 目标为任务 seq(j)（飞向或执行中）
%   t >= ct(end): 所有任务完成，目标为起点（归航）
if isempty(seq)
    tx = p0(1); ty = p0(2);
    return;
end

for j = 1:numel(seq)
    if t < ct(j)
        tx = tasks(seq(j)).x;
        ty = tasks(seq(j)).y;
        return;
    end
end

tx = p0(1);
ty = p0(2);
end
