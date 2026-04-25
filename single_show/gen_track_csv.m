function gen_track_csv(viz_data, dt, out_dir)
% GEN_TRACK_CSV  从 viz_data 生成 track_round_*.csv，供实物机器人对接。
%
% 自动选取 4 个代表轮次（第1轮、1/3轮、2/3轮、最后轮），
% 每轮输出一个 CSV，格式：
%   frame, robot_id, sim_x, sim_y, real_x, real_y
%
% 机器人按算法分配结果走直线（start → task1 → task2 → ... → start），
% 不做任何碰撞修正，实物机器人自行避障。

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

for r = round_ids
    timing_r = viz_data.all_rounds_timing{r};

    % 预收集 robot_id
    rid_list = zeros(1, N);
    for i = 1:N
        if isfield(agents(i), 'robot_id') && ~isempty(agents(i).robot_id)
            rid_list(i) = double(agents(i).robot_id);
        else
            rid_list(i) = double(agents(i).id);
        end
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

    % 跨帧 APF 状态：上帧输出位置（初始 = 各机器人起点）
    prev_adj_pos = zeros(N, 2);
    for i = 1:N
        prev_adj_pos(i,:) = [agents(i).x, agents(i).y];
    end

    % 相位切换检测：记录上帧 nat_pos 及各机器人是否处于静止（等待）状态
    prev_nat_pos       = prev_adj_pos;
    prev_is_stationary = true(N, 1);

    % 出发修正状态（以 APF 实际位置为飞行起点，消除任务切换突变）
    fly_actual_start = nan(N, 2);   % P_A：等待阶段结束时的 APF 位置
    fly_nat_start    = nan(N, 2);   % T_A：对应的任务中心
    fly_dest         = nan(N, 2);   % T_B：目标任务中心
    fly_correcting   = false(N, 1);

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

        % Step 1: 计算自然位置
        pos_nat = zeros(N, 2);
        for i = 1:N
            [px, py] = agent_pos_at(t_cur, ...
                [agents(i).x, agents(i).y], agents(i).vel, ...
                timing_r(i).task_sequence, ...
                timing_r(i).completion_times(:), tasks);
            pos_nat(i, :) = [px, py];
        end

        % 相位切换检测 + nat_pos 出发修正
        pos_nat_raw   = pos_nat;   % 保存原始 nat_pos，用于下帧相位比较
        is_stationary = true(N, 1);
        for i = 1:N
            is_stationary(i) = norm(pos_nat(i,:) - prev_nat_pos(i,:)) < 1e-6;

            if ~is_stationary(i) && prev_is_stationary(i)
                % 等待→飞行：记录 APF 实际位置 P_A 和目标 T_B
                fly_actual_start(i,:) = prev_adj_pos(i,:);   % P_A
                fly_nat_start(i,:)    = prev_nat_pos(i,:);   % T_A
                fly_correcting(i)     = true;
                % 查找目标任务中心 T_B
                ct_i  = timing_r(i).completion_times(:);
                seq_i = timing_r(i).task_sequence;
                j_done = sum(ct_i <= t_cur + 1e-6);
                if j_done < numel(seq_i)
                    fly_dest(i,:) = [tasks(seq_i(j_done+1)).x, tasks(seq_i(j_done+1)).y];
                else
                    fly_dest(i,:) = [agents(i).x, agents(i).y];  % 归航
                end

            elseif is_stationary(i) && fly_correcting(i)
                fly_correcting(i) = false;   % 飞行→等待：已到达，清除修正
            end
        end

        % 将 nat_pos 调整为从 P_A 出发、以 T_B 为终点（progress 插值）
        % 机器人从 APF 实际位置平滑飞向下一任务，消除任务切换时的突变
        for i = 1:N
            if fly_correcting(i) && ~is_stationary(i)
                T_A = fly_nat_start(i,:);
                P_A = fly_actual_start(i,:);
                T_B = fly_dest(i,:);
                total_dist = norm(T_B - T_A);
                if total_dist > 1e-6
                    progress = min(1, max(0, norm(pos_nat(i,:) - T_A) / total_dist));
                else
                    progress = 1;
                end
                pos_nat(i,:) = P_A + progress * (T_B - P_A);
            end
        end

        % Step 2: APF 全场调整（从上帧位置出发，吸引+排斥，保证连续性）
        pos_adj = apf_adjust(pos_nat, prev_adj_pos, 40.0);

        % Step 3: 写出
        for i = 1:N
            all_frames(end+1, :) = [frame_t, rid_list(i), pos_adj(i,1), pos_adj(i,2)];
        end
        prev_adj_pos       = pos_adj;
        prev_nat_pos       = pos_nat_raw;   % 用原始 nat_pos 做下帧相位检测
        prev_is_stationary = is_stationary;
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

    % 同步 tasks.csv 到 demo/ 目录
    demo_dir_t = fullfile(out_dir, 'demo');
    if ~exist(demo_dir_t, 'dir'), mkdir(demo_dir_t); end
    copyfile(tasks_path, fullfile(demo_dir_t, 'tasks.csv'));
    fprintf('[gen_track_csv] tasks.csv → %s\n', fullfile(demo_dir_t, 'tasks.csv'));
end
end


%% ===== 内部函数：全 APF 调整（吸引力 + 排斥力，跨帧连续）=====
function pos = apf_adjust(nat_pos, prev_pos, d_safe)
% 以上帧输出位置为起点，同时施加：
%   吸引力：拉向当前自然轨迹位置（使机器人跟踪规划路径）
%   排斥力：保证两两间距 >= d_safe（线性弹簧）
% 两力协同确保轨迹连续且无碰撞。
N   = size(nat_pos, 1);
pos = prev_pos;
tol = 1e-9;

k_att    = 1.0;
k_rep    = 3.0;
alpha    = 0.4;
max_step = 5.0;
max_iter = 300;

for iter = 1:max_iter
    forces = zeros(N, 2);

    % 吸引力：拉向自然位置
    for i = 1:N
        forces(i,:) = forces(i,:) + k_att * (nat_pos(i,:) - pos(i,:));
    end

    % 排斥力：线性弹簧，仅对违约对生效
    for i = 1:N
        for j = i+1:N
            diff = pos(i,:) - pos(j,:);
            d    = norm(diff);
            if d < d_safe - tol
                if d > tol
                    dir = diff / d;
                else
                    angle = 2*pi*(i-1)/N;
                    dir   = [cos(angle), sin(angle)];
                end
                f_mag = k_rep * (d_safe - d);
                forces(i,:) = forces(i,:) + f_mag * dir;
                forces(j,:) = forces(j,:) - f_mag * dir;
            end
        end
    end

    % 步长限制 + 更新
    max_f = 0;
    for i = 1:N
        step      = alpha * forces(i,:);
        step_norm = norm(step);
        max_f     = max(max_f, step_norm);
        if step_norm > max_step
            step = step * (max_step / step_norm);
        end
        pos(i,:) = pos(i,:) + step;
    end
    if max_f < 0.01, break; end
end
end


%% ===== 内部函数：计算单个智能体在时刻 t 的位置（直线插值）=====
function [px, py] = agent_pos_at(t, p0, vel, seq, ct, tasks)
tol = 1e-9;
if isempty(seq)
    px = p0(1); py = p0(2);
    return;
end

p_prev = p0;
t_prev = 0;

for j = 1:numel(seq)
    p_curr = [tasks(seq(j)).x, tasks(seq(j)).y];
    dist   = norm(p_curr - p_prev);
    fly_t  = dist / max(vel, tol);
    t_arrive = t_prev + fly_t;
    t_done   = ct(j);

    if t < t_done - tol
        if t < t_arrive - tol
            if dist < tol
                ratio = 1;
            else
                ratio = max(0, min(1, (t - t_prev) / fly_t));
            end
            pos = p_prev + ratio * (p_curr - p_prev);
            px = pos(1); py = pos(2);
        else
            px = p_curr(1); py = p_curr(2);
        end
        return;
    end

    p_prev = p_curr;
    t_prev = t_done;
end

% 所有任务完成，返回起点
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
    px = pos(1); py = pos(2);
else
    px = p0(1); py = p0(2);
end
end
