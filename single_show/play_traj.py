"""
play_traj.py  —  多轮次轨迹动画（MATLAB PlotClass 风格）
左图=地图轨迹, 右图=甘特时间线；每轮次顺序播放，轮间自动重置

用法:
    python play_traj.py                          # 交互播放（默认 results/trajectory.json）
    python play_traj.py path/to/traj.json
    python play_traj.py --save demo.gif --fps 12
    python play_traj.py --save demo.mp4 --fps 20
    python play_traj.py --pause 15               # 轮次间暂停帧数（默认 10）
"""

import json
import argparse
import pathlib
import matplotlib
import matplotlib.pyplot as plt
import matplotlib.patches as mpatches
import matplotlib.animation as animation

COLOR_FUTURE = (0.90, 0.90, 0.90)
COLOR_WAIT   = (1.00, 1.00, 0.00)
COLOR_ACTIVE = (0.00, 1.00, 0.00)
BAR_HEIGHT   = 0.6
MIN_BAR_W    = 0.5   # 等待段最小宽度（秒），小于此不渲染


def load_json(path):
    with open(path, 'r', encoding='utf-8') as f:
        return json.load(f)


def agent_color_palette(N):
    cmap = matplotlib.colormaps.get_cmap('tab10').resampled(max(N, 1))
    return [cmap(i) for i in range(N)]


def to_list(v):
    if v is None:
        return []
    return v if isinstance(v, list) else [v]


# ------------------------------------------------------------------ #
#  主函数
# ------------------------------------------------------------------ #
def build_figure(data, pause_frames=10):
    meta  = data['meta']
    tasks = data['tasks']
    N     = meta['N']
    dt    = meta['dt']
    world = meta['world']

    # 判断单/多轮次
    multi = 'rounds' in data
    if multi:
        rounds = data['rounds']
        num_rounds = len(rounds)
    else:
        rounds = [{'round_id': 1, 'T_max': meta['T_max'],
                   'coalition_utility': None,
                   'agents': data['agents']}]
        num_rounds = 1

    agent_colors = agent_color_palette(N)
    task_lookup  = {tk['id']: tk for tk in tasks}

    # ------ 全局帧序列: (round_idx, local_fi, is_pause) ------
    global_frames = []
    for r, rnd in enumerate(rounds):
        n_frames_r = len(rnd['agents'][0]['frames'])
        for fi in range(n_frames_r):
            global_frames.append((r, fi, False))
        # 轮次间暂停（最后一轮不加）
        if r < num_rounds - 1:
            for _ in range(pause_frames):
                global_frames.append((r, n_frames_r - 1, True))  # 冻结最后一帧

    total_frames = len(global_frames)

    # ------ 最大 T_max（用于甘特 x 轴） ------
    T_max_global = max(rnd['T_max'] for rnd in rounds)

    # ================================================================== #
    #  画布
    # ================================================================== #
    fig, (ax_map, ax_gantt) = plt.subplots(1, 2, figsize=(13, 6))
    fig.patch.set_facecolor('white')
    sup = fig.suptitle('', fontsize=13, fontweight='bold')

    # ================================================================== #
    #  左图：地图视图（静态部分）
    # ================================================================== #
    ax_map.set_title('Agent Trajectories (Map View)', fontsize=11)
    ax_map.set_xlabel('X (cm)')
    ax_map.set_ylabel('Y (cm)')
    ax_map.grid(True)
    ax_map.set_facecolor('white')

    task_xs = [tk['x'] for tk in tasks]
    task_ys = [tk['y'] for tk in tasks]
    ax_map.scatter(task_xs, task_ys, s=50, c='blue', zorder=5,
                   edgecolors='black', linewidths=0.7)
    for tk in tasks:
        ax_map.text(tk['x'] + 2, tk['y'] + 2, f"T{tk['id']}", fontsize=8, zorder=6)

    # 起点标记（所有轮次共用）
    start_positions = [(rnd['agents'][i]['start_x'], rnd['agents'][i]['start_y'])
                       for i in range(N)]
    for sx, sy in start_positions:
        ax_map.plot(sx, sy, 's', markersize=8, markeredgecolor='red',
                    markerfacecolor='none', linewidth=1.5, zorder=6)

    all_x = task_xs + [p[0] for p in start_positions]
    all_y = task_ys + [p[1] for p in start_positions]
    margin = 15
    ax_map.set_xlim(min(all_x) - margin, max(all_x) + margin)
    ax_map.set_ylim(min(all_y) - margin, max(all_y) + margin)
    ax_map.set_aspect('equal', adjustable='datalim')

    # ------ 规划路线虚线（每轮次一组，初始不可见）------
    route_lines = []   # route_lines[r][i] = Line2D
    for r, rnd in enumerate(rounds):
        row = []
        for i, ag in enumerate(rnd['agents']):
            col = agent_colors[i]
            seq = to_list(ag.get('task_sequence', []))
            if seq:
                rx = [ag['start_x']] + [task_lookup[t]['x'] for t in seq] + [ag['start_x']]
                ry = [ag['start_y']] + [task_lookup[t]['y'] for t in seq] + [ag['start_y']]
            else:
                rx = [ag['start_x']]
                ry = [ag['start_y']]
            line, = ax_map.plot(rx, ry, '--',
                                color=(*col[:3], 0.25), linewidth=1.0, zorder=2,
                                visible=(r == 0))
            row.append(line)
        route_lines.append(row)

    # ------ 动态 marker + trail ------
    h_markers = []
    h_trails  = []
    trail_x   = [[rounds[0]['agents'][i]['start_x']] for i in range(N)]
    trail_y   = [[rounds[0]['agents'][i]['start_y']] for i in range(N)]

    for i in range(N):
        col = agent_colors[i]
        sx, sy = start_positions[i]
        trail, = ax_map.plot([sx], [sy], '-',
                             color=(*col[:3], 0.5), linewidth=1.5, zorder=4)
        marker, = ax_map.plot(sx, sy, 'o',
                              markersize=10, markerfacecolor=col,
                              markeredgecolor='black', linewidth=2, zorder=7)
        h_markers.append(marker)
        h_trails.append(trail)

    # ================================================================== #
    #  右图：甘特视图（每轮次预构建，初始不可见）
    # ================================================================== #
    ax_gantt.set_title('Execution Timeline (Gantt View)', fontsize=11)
    ax_gantt.set_xlabel('Time (s)')
    ax_gantt.set_ylabel('Agent ID')
    ax_gantt.grid(True)
    ax_gantt.set_xlim(0, T_max_global * 1.05)
    ax_gantt.set_ylim(0, N + 1)
    ax_gantt.set_yticks(range(1, N + 1))
    ax_gantt.invert_yaxis()

    # wait_patches[r][i][j], exec_patches[r][i][j]
    all_wait = []
    all_exec = []

    for r, rnd in enumerate(rounds):
        rnd_wait, rnd_exec = [], []
        for i, ag in enumerate(rnd['agents']):
            seq = to_list(ag.get('task_sequence',   []))
            at  = to_list(ag.get('arrival_times',   []))
            st  = to_list(ag.get('start_times',     []))
            ct  = to_list(ag.get('completion_times',[]))

            row_w, row_e = [], []
            y_lo = (i + 1) - BAR_HEIGHT / 2
            y_hi = (i + 1) + BAR_HEIGHT / 2
            ys   = [y_lo, y_lo, y_hi, y_hi]

            for j in range(len(seq)):
                tid      = seq[j]
                t_arrive = at[j] if j < len(at) else st[j]
                t_start  = st[j]
                t_done   = ct[j]

                w_width = t_start - t_arrive
                if w_width > MIN_BAR_W:
                    xs_w = [t_arrive, t_start, t_start, t_arrive]
                    pw = mpatches.Polygon(list(zip(xs_w, ys)), closed=True,
                                         facecolor=COLOR_FUTURE,
                                         edgecolor='black', linewidth=0.5,
                                         zorder=3, visible=(r == 0))
                    ax_gantt.add_patch(pw)
                else:
                    pw = None
                row_w.append(pw)

                xs_e = [t_start, t_done, t_done, t_start]
                pe = mpatches.Polygon(list(zip(xs_e, ys)), closed=True,
                                      facecolor=COLOR_FUTURE,
                                      edgecolor='black', linewidth=0.5,
                                      zorder=3, visible=(r == 0))
                ax_gantt.add_patch(pe)
                if r == 0:   # 标签只画一次（轮次切换时重新设文本无意义，轮次内相对位置相同）
                    ax_gantt.text((t_start + t_done) / 2, i + 1,
                                  f'T{tid}', ha='center', va='center',
                                  fontsize=8, color='black', zorder=5,
                                  visible=True)
                row_e.append(pe)
            rnd_wait.append(row_w)
            rnd_exec.append(row_e)
        all_wait.append(rnd_wait)
        all_exec.append(rnd_exec)

    h_cursor, = ax_gantt.plot([0, 0], [0, N + 1], 'r-', linewidth=2, zorder=6)

    # ================================================================== #
    #  帧缓存
    # ================================================================== #
    frame_cache = []   # frame_cache[r][i][fi] = (x, y, state)
    for r, rnd in enumerate(rounds):
        round_cache = []
        for ag in rnd['agents']:
            round_cache.append([(fr['x'], fr['y'], fr['state'])
                                 for fr in ag['frames']])
        frame_cache.append(round_cache)

    # ================================================================== #
    #  状态
    # ================================================================== #
    prev_state   = ['idle'] * N
    current_round = [0]

    def switch_round(new_r):
        old_r = current_round[0]
        if new_r == old_r:
            return
        # 隐藏旧轮次
        for i in range(N):
            route_lines[old_r][i].set_visible(False)
            for pw in all_wait[old_r][i]:
                if pw is not None: pw.set_visible(False)
            for pe in all_exec[old_r][i]:
                pe.set_visible(False)
        # 显示新轮次
        for i in range(N):
            route_lines[new_r][i].set_visible(True)
            for pw in all_wait[new_r][i]:
                if pw is not None: pw.set_visible(True)
            for pe in all_exec[new_r][i]:
                pe.set_visible(True)
        # 重置 trail
        rnd_new = rounds[new_r]
        for i in range(N):
            trail_x[i].clear()
            trail_y[i].clear()
            trail_x[i].append(rnd_new['agents'][i]['start_x'])
            trail_y[i].append(rnd_new['agents'][i]['start_y'])
            prev_state[i] = 'idle'
        current_round[0] = new_r

    # ================================================================== #
    #  更新函数
    # ================================================================== #
    def update(gfi):
        r, fi, is_pause = global_frames[gfi]
        switch_round(r)

        rnd = rounds[r]
        t = fi * dt
        T_max_r = rnd['T_max']
        cu = rnd.get('coalition_utility', None)

        if multi:
            cu_str = f' | Utility={cu:.1f}' if cu is not None and cu == cu else ''
            sup.set_text(
                f'Round {r+1}/{num_rounds}{cu_str} | '
                f'Time {min(t, T_max_r):.1f} / {T_max_r:.1f} s'
            )
        else:
            sup.set_text(f'Simulation Time: {min(t, T_max_r):.1f} / {T_max_r:.1f} s')

        h_cursor.set_xdata([t, t])

        for i in range(N):
            col = agent_colors[i]
            x, y, state = frame_cache[r][i][fi]

            # marker
            if state == 'waiting':
                fc = COLOR_WAIT
            elif state == 'executing':
                fc = COLOR_ACTIVE
            else:
                fc = col
            h_markers[i].set_data([x], [y])
            h_markers[i].set_markerfacecolor(fc)

            # trail
            if state in ('flying', 'returning'):
                trail_x[i].append(x)
                trail_y[i].append(y)
            elif prev_state[i] in ('flying', 'returning'):
                trail_x[i].append(x)
                trail_y[i].append(y)
            h_trails[i].set_data(trail_x[i], trail_y[i])
            prev_state[i] = state

            # 甘特着色
            ag = rnd['agents'][i]
            at_list = to_list(ag.get('arrival_times',   []))
            st_list = to_list(ag.get('start_times',     []))
            ct_list = to_list(ag.get('completion_times',[]))

            for j, pe in enumerate(all_exec[r][i]):
                t_arrive = at_list[j] if j < len(at_list) else st_list[j]
                t_start  = st_list[j]
                t_done   = ct_list[j]

                pw = all_wait[r][i][j]
                if pw is not None:
                    pw.set_facecolor(COLOR_FUTURE if t < t_arrive else COLOR_WAIT)

                if t < t_start:
                    pe.set_facecolor(COLOR_FUTURE)
                elif t < t_done:
                    pe.set_facecolor(COLOR_ACTIVE)
                else:
                    pe.set_facecolor(col)

        return h_markers + h_trails + [h_cursor, sup]

    ani = animation.FuncAnimation(
        fig, update,
        frames=total_frames,
        interval=80,
        blit=False,
        repeat=True
    )

    plt.tight_layout(rect=[0, 0, 1, 0.94])
    return fig, ani


def main():
    parser = argparse.ArgumentParser(description='多轮次轨迹动画播放器')
    parser.add_argument('json', nargs='?',
                        default=str(pathlib.Path(__file__).parent /
                                    'results' / 'trajectory.json'))
    parser.add_argument('--save', metavar='FILE')
    parser.add_argument('--fps',   type=int, default=12)
    parser.add_argument('--pause', type=int, default=10,
                        help='轮次间暂停帧数（默认 10）')
    args = parser.parse_args()

    print(f'读取: {args.json}')
    data = load_json(args.json)
    meta = data['meta']

    if 'rounds' in data:
        print(f"  多轮次模式: {len(data['rounds'])} 轮  "
              f"N={meta['N']} M={meta['M']} dt={meta['dt']}")
    else:
        print(f"  单轮次模式: N={meta['N']} M={meta['M']} "
              f"T_max={meta.get('T_max', '?')} dt={meta['dt']}")

    fig, ani = build_figure(data, pause_frames=args.pause)

    if args.save:
        print(f'保存至: {args.save}  fps={args.fps}')
        if args.save.endswith('.gif'):
            writer = animation.PillowWriter(fps=args.fps)
        else:
            writer = animation.FFMpegWriter(fps=args.fps, bitrate=1800)
        ani.save(args.save, writer=writer)
        print('完成。')
    else:
        plt.show()


if __name__ == '__main__':
    main()
