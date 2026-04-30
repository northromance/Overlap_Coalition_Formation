"""
play_traj.py  —  从 track_round_*.csv 播放仿真/实物轨迹动画（含甘特图）

用法:
    python play_traj.py                    # 播放 results/ 下的所有轮次（sim 坐标）
    python play_traj.py --real             # 使用真实摄像头坐标 (real_x/real_y)
    python play_traj.py --results DIR      # 指定 CSV 目录
    python play_traj.py --save demo.gif --fps 12
    python play_traj.py --save demo.mp4 --fps 20
    python play_traj.py --pause 15         # 轮次间暂停帧数（默认 10）

键盘:
    空格        暂停 / 继续
    → / ↑       加速（快进）；暂停时 → 逐帧前进
    ← / ↓       减速；暂停时 ← 逐帧后退
    ] / PageDown  切换到下一轮次（自动暂停）
    [ / PageUp    切换到上一轮次（自动暂停）
    Q / Esc     关闭
"""

import csv
import glob
import json
import re
import argparse
import pathlib
import matplotlib
import matplotlib.pyplot as plt
import matplotlib.animation as animation
import matplotlib.patches as mpatches

# ── 中文字体配置 ──────────────────────────────────────────────
matplotlib.rcParams['font.sans-serif'] = [
    'Microsoft YaHei', 'SimHei', 'SimSun',
    'WenQuanYi Micro Hei', 'Noto Sans CJK SC', 'DejaVu Sans',
]
matplotlib.rcParams['axes.unicode_minus'] = False


# ────────────────────────────────────────────────────────────
#  数据加载
# ────────────────────────────────────────────────────────────

def load_tasks(results_dir):
    """读取 tasks.csv → [{id, x, y, type, value}, ...]"""
    path = pathlib.Path(results_dir) / 'tasks.csv'
    if not path.exists():
        return []
    tasks = []
    with open(path, 'r', encoding='utf-8') as f:
        for row in csv.DictReader(f):
            tasks.append({
                'id':    int(row['task_id']),
                'x':     float(row['x']),
                'y':     float(row['y']),
                'type':  int(row['type']),
                'value': int(row['value']),
            })
    return tasks


def load_schedule(results_dir):
    """读取 trajectory.json → {round_id: round_data}，不存在返回 None。"""
    path = pathlib.Path(results_dir) / 'trajectory.json'
    if not path.exists():
        return None
    with open(path, 'r', encoding='utf-8') as f:
        data = json.load(f)
    return {rnd['round_id']: rnd for rnd in data.get('rounds', [])}


def load_rounds(results_dir, use_real=False):
    """
    读取所有 track_round_*.csv，按文件写入顺序读取各帧坐标（APF 真实路径）。
    frame 列存在已知写入 bug（第 2 帧写成 10000 而非 10），不能按 frame 排序，
    文件写入顺序即正确时序。
    trajectory.json 仅用于甘特图调度数据，不用于轨迹坐标。
    """
    pattern = str(pathlib.Path(results_dir) / 'track_round_*.csv')
    files = sorted(
        glob.glob(pattern),
        key=lambda p: int(re.search(r'track_round_(\d+)', p).group(1))
    )
    if not files:
        raise FileNotFoundError(f'No track_round_*.csv found in {results_dir}')

    rounds = []
    for fpath in files:
        round_id = int(re.search(r'track_round_(\d+)', fpath).group(1))
        robots = {}
        with open(fpath, 'r', encoding='utf-8') as f:
            for row in csv.DictReader(f):
                rid = int(row['robot_id'])
                x   = float(row['sim_x'] if use_real else row['real_x'])
                y   = float(row['sim_y'] if use_real else row['real_y'])
                robots.setdefault(rid, []).append((x, y))

        nf = min(len(v) for v in robots.values()) if robots else 0
        print(f'  Round {round_id}: {len(robots)} robots, {nf} frames  ({fpath})')
        rounds.append({'round_id': round_id, 'robots': robots})

    return rounds


# ────────────────────────────────────────────────────────────
#  颜色辅助
# ────────────────────────────────────────────────────────────

def agent_color_palette(robot_ids):
    cmap = matplotlib.colormaps.get_cmap('tab10').resampled(max(len(robot_ids), 1))
    return {rid: cmap(i) for i, rid in enumerate(sorted(robot_ids))}


def task_color_palette(task_ids):
    cmap = matplotlib.colormaps.get_cmap('Set2').resampled(max(len(task_ids), 1))
    return {tid: cmap(i) for i, tid in enumerate(sorted(task_ids))}


# ────────────────────────────────────────────────────────────
#  主画布
# ────────────────────────────────────────────────────────────

def build_figure(rounds, tasks=None, pause_frames=10, schedule=None):
    all_rids = sorted({rid for rnd in rounds for rid in rnd['robots']})
    colors    = agent_color_palette(all_rids)
    num_rounds = len(rounds)

    # 全局帧序列 (round_idx, local_fi, is_pause)
    global_frames = []
    for r, rnd in enumerate(rounds):
        nf = min(len(v) for v in rnd['robots'].values()) if rnd['robots'] else 0
        for fi in range(nf):
            global_frames.append((r, fi, False))
        if r < num_rounds - 1:
            for _ in range(pause_frames):
                global_frames.append((r, nf - 1, True))
    total_frames = len(global_frames)

    # 每个轮次第一帧在全局帧序列中的下标
    round_start_gfi = {}
    for _gfi, (_r, _fi, _is_pause) in enumerate(global_frames):
        if not _is_pause and _fi == 0 and _r not in round_start_gfi:
            round_start_gfi[_r] = _gfi

    # 地图范围
    all_x, all_y = [], []
    for rnd in rounds:
        for pts in rnd['robots'].values():
            all_x.extend(p[0] for p in pts)
            all_y.extend(p[1] for p in pts)
    margin = 15
    x_lo, x_hi = min(all_x) - margin, max(all_x) + margin
    y_lo, y_hi = min(all_y) - margin, max(all_y) + margin

    # 任务颜色（甘特图执行段）
    all_tids = sorted({t['id'] for t in (tasks or [])})
    if not all_tids and schedule:
        for rnd_sch in schedule.values():
            for ag in rnd_sch.get('agents', []):
                all_tids.extend(ag.get('task_sequence', []))
        all_tids = sorted(set(all_tids))
    task_colors = task_color_palette(all_tids) if all_tids else {}

    # ── 画布：左轨迹 + 右甘特图 ──────────────────────────────
    fig = plt.figure(figsize=(16, 7))
    ax       = fig.add_subplot(1, 2, 1)
    ax_gantt = fig.add_subplot(1, 2, 2)
    fig.patch.set_facecolor('white')

    # 轨迹 axes
    ax.set_title('Agent Trajectories', fontsize=11)
    ax.set_xlabel('X (cm)')
    ax.set_ylabel('Y (cm)')
    ax.grid(True, alpha=0.4)
    ax.set_facecolor('white')
    ax.set_xlim(x_lo, x_hi)
    ax.set_ylim(y_lo, y_hi)
    ax.set_aspect('equal', adjustable='datalim')

    sup = fig.suptitle('', fontsize=12, fontweight='bold')
    ax.text(0.5, -0.10,
            '空格=暂停/继续   →/↑=加速   ←/↓=减速（暂停时逐帧）   [/]=切换轮次   Q=关闭',
            transform=ax.transAxes, ha='center', fontsize=8, color='gray')

    # 任务点
    if tasks:
        ax.scatter([t['x'] for t in tasks], [t['y'] for t in tasks],
                   s=80, c='steelblue', marker='*', zorder=5,
                   edgecolors='navy', linewidths=0.7, label='Task')
        for t in tasks:
            ax.text(t['x'] + 3, t['y'] + 3,
                    f"T{t['id']}(v={t['value']})", fontsize=7, zorder=6, color='navy')

    # 起点标记（第 1 轮第 0 帧）
    rnd0 = rounds[0]
    for rid in all_rids:
        if rid in rnd0['robots'] and rnd0['robots'][rid]:
            sx, sy = rnd0['robots'][rid][0]
            ax.plot(sx, sy, 's', markersize=8,
                    markeredgecolor='red', markerfacecolor='none',
                    linewidth=1.5, zorder=6)

    # 动态 marker + trail
    h_markers, h_trails = {}, {}
    trail_x = {rid: [] for rid in all_rids}
    trail_y = {rid: [] for rid in all_rids}

    for rid in all_rids:
        col = colors[rid]
        sx, sy = (rnd0['robots'][rid][0]
                  if rid in rnd0['robots'] and rnd0['robots'][rid] else (0.0, 0.0))
        trail, = ax.plot([sx], [sy], '-', color=(*col[:3], 0.5), linewidth=1.5, zorder=4)
        marker, = ax.plot(sx, sy, 'o', markersize=10,
                          markerfacecolor=col, markeredgecolor='black',
                          linewidth=2, zorder=7, label=f'Robot {rid}')
        h_markers[rid] = marker
        h_trails[rid]  = trail
        trail_x[rid]   = [sx]
        trail_y[rid]   = [sy]

    ax.legend(loc='upper right', fontsize=9)

    # ── 甘特图状态 ────────────────────────────────────────────
    FLY_COLOR  = '#c8c8c8'
    WAIT_COLOR = '#f4a460'

    gantt_cursor = [None]   # axvline artist
    gantt_T_max  = [1.0]

    def draw_gantt(r):
        ax_gantt.cla()
        rid_id = rounds[r]['round_id']
        ax_gantt.set_facecolor('#f7f7f7')
        ax_gantt.grid(axis='x', alpha=0.3, linestyle='--')
        ax_gantt.set_xlabel('Time (s)', fontsize=9)
        ax_gantt.set_title(f'Round {rid_id}  —  Schedule', fontsize=10)

        if schedule is None or rid_id not in schedule:
            ax_gantt.text(0.5, 0.5,
                          'No schedule data\n(trajectory.json not found)',
                          transform=ax_gantt.transAxes,
                          ha='center', va='center', fontsize=9, color='gray')
            gantt_cursor[0] = None
            gantt_T_max[0]  = 1.0
            return

        rnd_sch        = schedule[rid_id]
        T_max          = rnd_sch['T_max']
        gantt_T_max[0] = T_max

        agents_sch = rnd_sch.get('agents', [])
        if not agents_sch:
            gantt_cursor[0] = None
            return

        def _as_list(v):
            """MATLAB 单元素数组在 JSON 里会变成标量，统一转成列表。"""
            if isinstance(v, list):
                return v
            return [] if v is None else [v]

        shown_tasks = set()
        for i, ag in enumerate(agents_sch):
            prev_end    = 0.0
            tasks_seq   = _as_list(ag.get('task_sequence', []))
            arr_times   = _as_list(ag.get('arrival_times', []))
            start_times = _as_list(ag.get('start_times', []))
            comp_times  = _as_list(ag.get('completion_times', []))

            for j, tid in enumerate(tasks_seq):
                arr = arr_times[j]
                st  = start_times[j]
                ct  = comp_times[j]

                fly_dur  = arr - prev_end
                wait_dur = st  - arr
                exec_dur = ct  - st

                if fly_dur  > 0.01:
                    ax_gantt.barh(i, fly_dur,  left=prev_end, height=0.55,
                                  color=FLY_COLOR,  edgecolor='none')
                if wait_dur > 0.01:
                    ax_gantt.barh(i, wait_dur, left=arr,      height=0.55,
                                  color=WAIT_COLOR, edgecolor='none')
                if exec_dur > 0.01:
                    tcol = task_colors.get(tid, '#7ec8a0')
                    ax_gantt.barh(i, exec_dur, left=st,       height=0.55,
                                  color=tcol, edgecolor='none', alpha=0.9)
                    ax_gantt.text(st + exec_dur / 2, i, f'T{tid}',
                                  ha='center', va='center',
                                  fontsize=7, fontweight='bold', color='black')
                    shown_tasks.add(tid)

                prev_end = ct

        ax_gantt.set_yticks(range(len(agents_sch)))
        ax_gantt.set_yticklabels([f'A{ag["id"]}' for ag in agents_sch], fontsize=9)
        ax_gantt.set_xlim(0, T_max * 1.05)
        ax_gantt.set_ylim(-0.65, len(agents_sch) - 0.35)

        # 图例
        legend_patches = [
            mpatches.Patch(color=FLY_COLOR,  label='Flying'),
            mpatches.Patch(color=WAIT_COLOR, label='Waiting'),
        ]
        for tid in sorted(shown_tasks):
            legend_patches.append(
                mpatches.Patch(color=task_colors.get(tid, '#7ec8a0'),
                               label=f'T{tid}', alpha=0.9))
        ax_gantt.legend(handles=legend_patches, loc='upper right',
                        fontsize=7, ncol=2, framealpha=0.8)

        # 时间光标（初始在 t=0）
        cline = ax_gantt.axvline(x=0, color='crimson',
                                 linewidth=1.8, zorder=10, alpha=0.85)
        gantt_cursor[0] = cline

    # ── 轮次切换 ──────────────────────────────────────────────
    current_round = [0]
    last_gfi      = [0]

    def switch_round(new_r):
        if new_r == current_round[0]:
            return
        rnd_new = rounds[new_r]
        for rid in all_rids:
            trail_x[rid].clear()
            trail_y[rid].clear()
            sx, sy = (rnd_new['robots'][rid][0]
                      if rid in rnd_new['robots'] and rnd_new['robots'][rid]
                      else (0.0, 0.0))
            trail_x[rid].append(sx)
            trail_y[rid].append(sy)
        current_round[0] = new_r
        draw_gantt(new_r)

    # ── 帧更新 ────────────────────────────────────────────────
    def update(gfi):
        last_gfi[0] = gfi
        r, fi, _is_pause = global_frames[gfi]
        switch_round(r)

        rnd = rounds[r]
        n_frames_r = min(len(v) for v in rnd['robots'].values()) if rnd['robots'] else 0
        sup.set_text(f'Round {rnd["round_id"]}  |  Frame {fi + 1} / {n_frames_r}')

        artists = [sup]
        for rid in all_rids:
            if rid not in rnd['robots'] or not rnd['robots'][rid]:
                continue
            pts        = rnd['robots'][rid]
            fi_clamped = min(fi, len(pts) - 1)
            x, y       = pts[fi_clamped]
            if fi_clamped > 0:
                px, py = pts[fi_clamped - 1]
                if x != px or y != py:
                    trail_x[rid].append(x)
                    trail_y[rid].append(y)
            h_trails[rid].set_data(trail_x[rid], trail_y[rid])
            h_markers[rid].set_data([x], [y])
            artists += [h_markers[rid], h_trails[rid]]

        # 移动甘特图时间光标（用 CSV 实际帧数做分母，与轨迹播放速率对齐）
        if gantt_cursor[0] is not None:
            t_cur = fi * gantt_T_max[0] / max(n_frames_r - 1, 1)
            gantt_cursor[0].set_xdata([t_cur, t_cur])
            artists.append(gantt_cursor[0])

        return artists

    # 初始化第一轮甘特图
    draw_gantt(0)

    ani = animation.FuncAnimation(
        fig, update,
        frames=total_frames,
        interval=80,
        blit=False,
        repeat=True,
    )

    # ── 键盘控制 ──────────────────────────────────────────────
    paused   = [False]
    interval = [80]

    def _refresh_hint():
        fps_cur = round(1000 / interval[0])
        base    = sup.get_text().split('  【')[0].split('  [')[0]
        hint    = '  【已暂停】' if paused[0] else f'  [{fps_cur} fps]'
        sup.set_text(base + hint)
        fig.canvas.draw_idle()

    def on_key(event):
        key = event.key
        if key == ' ':
            if paused[0]:
                ani.resume()
            else:
                ani.pause()
            paused[0] = not paused[0]
            _refresh_hint()

        elif key in ('right', 'up', '+', '='):
            if paused[0] and key == 'right':          # 暂停时右键逐帧前进
                nfi = min(last_gfi[0] + 1, total_frames - 1)
                update(nfi)
                _refresh_hint()
                fig.canvas.draw_idle()
            else:                                      # 加速（快进）
                interval[0] = max(20, interval[0] - 20)
                ani.event_source.interval = interval[0]
                _refresh_hint()

        elif key in ('left', 'down', '-'):
            if paused[0] and key == 'left':            # 暂停时左键逐帧后退
                nfi = max(last_gfi[0] - 1, 0)
                update(nfi)
                _refresh_hint()
                fig.canvas.draw_idle()
            else:                                      # 减速
                interval[0] = min(500, interval[0] + 20)
                ani.event_source.interval = interval[0]
                _refresh_hint()

        elif key in (']', 'pagedown'):           # 下一轮次
            target_r = min(current_round[0] + 1, num_rounds - 1)
            nfi = round_start_gfi.get(target_r, last_gfi[0])
            if not paused[0]:
                ani.pause()
                paused[0] = True
            last_gfi[0] = nfi
            update(nfi)
            _refresh_hint()
            fig.canvas.draw_idle()

        elif key in ('[', 'pageup'):             # 上一轮次
            target_r = max(current_round[0] - 1, 0)
            nfi = round_start_gfi.get(target_r, last_gfi[0])
            if not paused[0]:
                ani.pause()
                paused[0] = True
            last_gfi[0] = nfi
            update(nfi)
            _refresh_hint()
            fig.canvas.draw_idle()

        elif key in ('q', 'Q', 'escape'):
            plt.close(fig)

    fig.canvas.mpl_connect('key_press_event', on_key)

    plt.tight_layout(rect=[0, 0, 1, 0.93])
    return fig, ani


# ────────────────────────────────────────────────────────────
#  入口
# ────────────────────────────────────────────────────────────

def main():
    parser = argparse.ArgumentParser(description='track_round_*.csv 轨迹动画播放器（含甘特图）')
    parser.add_argument('--results', metavar='DIR',
                        default=str(pathlib.Path(__file__).parent / 'results'),
                        help='包含 track_round_*.csv 的目录（默认 results/）')
    parser.add_argument('--real', action='store_true',
                        help='使用 sim_x/sim_y 而非 real_x/real_y')
    parser.add_argument('--save', metavar='FILE',
                        help='保存为 gif 或 mp4')
    parser.add_argument('--fps',   type=int, default=12)
    parser.add_argument('--pause', type=int, default=10,
                        help='轮次间暂停帧数（默认 10）')
    args = parser.parse_args()

    print(f'结果目录: {args.results}')
    print(f'坐标模式: {"real (sim_x/sim_y)" if args.real else "sim (real_x/real_y)"}')

    # schedule 先加载，load_rounds 会用它来决定坐标来源
    schedule = load_schedule(args.results)
    if schedule:
        print(f'调度数据: {len(schedule)} 个轮次  (来自 trajectory.json)')
    else:
        print('未找到 trajectory.json，回退到 CSV 坐标，甘特图显示占位提示')

    rounds = load_rounds(args.results, use_real=args.real)
    print(f'共加载 {len(rounds)} 个轮次\n')

    tasks = load_tasks(args.results)
    print(f'任务点: {len(tasks)} 个' if tasks else '未找到 tasks.csv，不绘制任务点')

    fig, ani = build_figure(rounds, tasks=tasks, pause_frames=args.pause,
                            schedule=schedule)

    if args.save:
        print(f'保存至: {args.save}  fps={args.fps}')
        writer = (animation.PillowWriter(fps=args.fps) if args.save.endswith('.gif')
                  else animation.FFMpegWriter(fps=args.fps, bitrate=1800))
        ani.save(args.save, writer=writer)
        print('完成。')
    else:
        plt.show()


if __name__ == '__main__':
    main()
