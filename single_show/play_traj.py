"""
play_traj.py  —  从 track_round_*.csv 播放仿真/实物轨迹动画

用法:
    python play_traj.py                    # 播放 results/ 下的所有轮次（sim 坐标）
    python play_traj.py --real             # 使用真实摄像头坐标 (real_x/real_y)
    python play_traj.py --results DIR      # 指定 CSV 目录
    python play_traj.py --save demo.gif --fps 12
    python play_traj.py --save demo.mp4 --fps 20
    python play_traj.py --pause 15         # 轮次间暂停帧数（默认 10）
"""

import csv
import glob
import re
import argparse
import pathlib
import matplotlib
import matplotlib.pyplot as plt
import matplotlib.animation as animation
import matplotlib.patches as mpatches


def load_tasks(results_dir):
    """读取 tasks.csv，返回 [{id, x, y, type, value}, ...]，不存在则返回空列表。"""
    path = pathlib.Path(results_dir) / 'tasks.csv'
    if not path.exists():
        return []
    tasks = []
    with open(path, 'r', encoding='utf-8') as f:
        reader = csv.DictReader(f)
        for row in reader:
            tasks.append({
                'id':    int(row['task_id']),
                'x':     float(row['x']),
                'y':     float(row['y']),
                'type':  int(row['type']),
                'value': int(row['value']),
            })
    return tasks


def load_rounds(results_dir, use_real=False):
    """读取所有 track_round_*.csv，按轮次编号排序，返回轮次列表。"""
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
        robots = {}  # robot_id -> [(x, y), ...]
        with open(fpath, 'r', encoding='utf-8') as f:
            reader = csv.DictReader(f)
            for row in reader:
                rid = int(row['robot_id'])
                if use_real:
                    x = float(row['sim_x'])
                    y = float(row['sim_y'])
                else:
                    x = float(row['real_x'])
                    y = float(row['real_y'])
                robots.setdefault(rid, []).append((x, y))
        rounds.append({'round_id': round_id, 'robots': robots})
        n_frames = min(len(v) for v in robots.values()) if robots else 0
        print(f'  Round {round_id}: {len(robots)} robots, {n_frames} frames  ({fpath})')

    return rounds


def agent_color_palette(robot_ids):
    cmap = matplotlib.colormaps.get_cmap('tab10').resampled(max(len(robot_ids), 1))
    return {rid: cmap(i) for i, rid in enumerate(sorted(robot_ids))}


def build_figure(rounds, tasks=None, pause_frames=10):
    # 收集所有 robot_id
    all_rids = set()
    for rnd in rounds:
        all_rids.update(rnd['robots'].keys())
    all_rids = sorted(all_rids)
    colors = agent_color_palette(all_rids)
    num_rounds = len(rounds)

    # 全局帧序列: (round_idx, local_fi, is_pause)
    global_frames = []
    for r, rnd in enumerate(rounds):
        n_frames_r = min(len(v) for v in rnd['robots'].values()) if rnd['robots'] else 0
        for fi in range(n_frames_r):
            global_frames.append((r, fi, False))
        if r < num_rounds - 1:
            for _ in range(pause_frames):
                global_frames.append((r, n_frames_r - 1, True))
    total_frames = len(global_frames)

    # 计算地图范围
    all_x, all_y = [], []
    for rnd in rounds:
        for pts in rnd['robots'].values():
            all_x.extend(p[0] for p in pts)
            all_y.extend(p[1] for p in pts)
    margin = 15
    x_lo = min(all_x) - margin
    x_hi = max(all_x) + margin
    y_lo = min(all_y) - margin
    y_hi = max(all_y) + margin

    # ------------------------------------------------------------------ #
    #  画布（单幅地图）
    # ------------------------------------------------------------------ #
    fig, ax = plt.subplots(figsize=(8, 7))
    fig.patch.set_facecolor('white')
    ax.set_title('Agent Trajectories', fontsize=11)
    ax.set_xlabel('X (cm)')
    ax.set_ylabel('Y (cm)')
    ax.grid(True)
    ax.set_facecolor('white')
    ax.set_xlim(x_lo, x_hi)
    ax.set_ylim(y_lo, y_hi)
    ax.set_aspect('equal', adjustable='datalim')

    sup = fig.suptitle('', fontsize=12, fontweight='bold')
    ax.text(0.5, -0.08, '空格=暂停/继续   ←/→=逐帧（暂停时）   +/↑=加速   -/↓=减速   Q=关闭',
            transform=ax.transAxes, ha='center', fontsize=9, color='gray')

    # 任务点
    if tasks:
        task_xs = [t['x'] for t in tasks]
        task_ys = [t['y'] for t in tasks]
        ax.scatter(task_xs, task_ys, s=80, c='steelblue', marker='*',
                   zorder=5, edgecolors='navy', linewidths=0.7, label='Task')
        for t in tasks:
            ax.text(t['x'] + 3, t['y'] + 3,
                    f"T{t['id']}(v={t['value']})", fontsize=7, zorder=6, color='navy')

    # 起点标记（第 1 轮第 0 帧各机器人位置）
    rnd0 = rounds[0]
    for rid in all_rids:
        if rid in rnd0['robots'] and rnd0['robots'][rid]:
            sx, sy = rnd0['robots'][rid][0]
            ax.plot(sx, sy, 's', markersize=8,
                    markeredgecolor='red', markerfacecolor='none',
                    linewidth=1.5, zorder=6)

    # 动态 marker + trail
    h_markers = {}
    h_trails  = {}
    trail_x   = {rid: [] for rid in all_rids}
    trail_y   = {rid: [] for rid in all_rids}

    for rid in all_rids:
        col = colors[rid]
        sx, sy = (rnd0['robots'][rid][0] if rid in rnd0['robots'] and rnd0['robots'][rid]
                  else (0.0, 0.0))
        trail, = ax.plot([sx], [sy], '-',
                         color=(*col[:3], 0.5), linewidth=1.5, zorder=4)
        marker, = ax.plot(sx, sy, 'o',
                          markersize=10, markerfacecolor=col,
                          markeredgecolor='black', linewidth=2, zorder=7,
                          label=f'Robot {rid}')
        h_markers[rid] = marker
        h_trails[rid]  = trail
        trail_x[rid]   = [sx]
        trail_y[rid]   = [sy]

    ax.legend(loc='upper right', fontsize=9)

    current_round = [0]
    last_gfi = [0]

    def switch_round(new_r):
        old_r = current_round[0]
        if new_r == old_r:
            return
        rnd_new = rounds[new_r]
        for rid in all_rids:
            trail_x[rid].clear()
            trail_y[rid].clear()
            if rid in rnd_new['robots'] and rnd_new['robots'][rid]:
                sx, sy = rnd_new['robots'][rid][0]
            else:
                sx, sy = 0.0, 0.0
            trail_x[rid].append(sx)
            trail_y[rid].append(sy)
        current_round[0] = new_r

    def update(gfi):
        last_gfi[0] = gfi
        r, fi, is_pause = global_frames[gfi]
        switch_round(r)

        rnd = rounds[r]
        rid_id = rnd['round_id']
        n_frames_r = min(len(v) for v in rnd['robots'].values()) if rnd['robots'] else 0
        sup.set_text(f'Round {rid_id}  |  Frame {fi + 1} / {n_frames_r}')

        artists = [sup]
        for rid in all_rids:
            if rid not in rnd['robots'] or not rnd['robots'][rid]:
                continue
            pts = rnd['robots'][rid]
            fi_clamped = min(fi, len(pts) - 1)
            x, y = pts[fi_clamped]

            # trail: append when moving (position changed from previous frame)
            if fi_clamped > 0:
                px, py = pts[fi_clamped - 1]
                if x != px or y != py:
                    trail_x[rid].append(x)
                    trail_y[rid].append(y)
            h_trails[rid].set_data(trail_x[rid], trail_y[rid])
            h_markers[rid].set_data([x], [y])
            artists += [h_markers[rid], h_trails[rid]]

        return artists

    ani = animation.FuncAnimation(
        fig, update,
        frames=total_frames,
        interval=80,
        blit=False,
        repeat=True
    )

    # 键盘控制
    paused   = [False]
    interval = [80]   # ms，初始帧间隔

    def _update_title_hint():
        fps_cur = round(1000 / interval[0])
        base = sup.get_text().split('  【')[0]
        hint = '  【已暂停】' if paused[0] else f'  [{fps_cur} fps]'
        sup.set_text(base + hint)
        fig.canvas.draw_idle()

    def on_key(event):
        if event.key == ' ':
            if paused[0]:
                ani.resume()
            else:
                ani.pause()
            paused[0] = not paused[0]
            _update_title_hint()
        elif event.key in ('+', '=', 'up'):      # 加速
            interval[0] = max(20, interval[0] - 20)
            ani.event_source.interval = interval[0]
            _update_title_hint()
        elif event.key in ('-', 'down'):           # 减速
            interval[0] = min(500, interval[0] + 20)
            ani.event_source.interval = interval[0]
            _update_title_hint()
        elif event.key in ('right', '.') and paused[0]:   # 逐帧前进
            nfi = min(last_gfi[0] + 1, total_frames - 1)
            update(nfi)
            _update_title_hint()
            fig.canvas.draw_idle()
        elif event.key in ('left', ',') and paused[0]:    # 逐帧后退
            nfi = max(last_gfi[0] - 1, 0)
            update(nfi)
            _update_title_hint()
            fig.canvas.draw_idle()
        elif event.key in ('q', 'Q', 'escape'):
            plt.close(fig)

    fig.canvas.mpl_connect('key_press_event', on_key)

    plt.tight_layout(rect=[0, 0, 1, 0.92])
    return fig, ani


def main():
    parser = argparse.ArgumentParser(description='track_round_*.csv 轨迹动画播放器')
    parser.add_argument('--results', metavar='DIR',
                        default=str(pathlib.Path(__file__).parent / 'results'),
                        help='包含 track_round_*.csv 的目录（默认 results/）')
    parser.add_argument('--real', action='store_true',
                        help='使用 sim_x/sim_y 而非 real_x/real_y（即摄像头实测坐标替换算法坐标）')
    parser.add_argument('--save', metavar='FILE',
                        help='保存为 gif 或 mp4')
    parser.add_argument('--fps',   type=int, default=12)
    parser.add_argument('--pause', type=int, default=10,
                        help='轮次间暂停帧数（默认 10）')
    args = parser.parse_args()

    coord_mode = 'real (real_x/real_y)' if args.real else 'sim (sim_x/sim_y)'
    print(f'结果目录: {args.results}')
    print(f'坐标模式: {coord_mode}')

    rounds = load_rounds(args.results, use_real=args.real)
    print(f'共加载 {len(rounds)} 个轮次\n')

    tasks = load_tasks(args.results)
    if tasks:
        print(f'任务点: {len(tasks)} 个  (来自 tasks.csv)')
    else:
        print('未找到 tasks.csv，不绘制任务点（请重新运行 SS_Single_Viz.m 生成）')

    fig, ani = build_figure(rounds, tasks=tasks, pause_frames=args.pause)

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
