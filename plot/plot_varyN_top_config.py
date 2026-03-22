"""
plot_varyN.py
=============
从 Batch_VaryN.m 生成的 .mat 文件绘制论文图：
  图1a  变N效用       (mean ± std 折线图，4算法)
  图1b  变N完成度     (mean ± std 折线图，4算法)
  图2c  效用收敛曲线  (对最大N，按种子平均)
  图3a  内循环轨迹    (OCF_SAtabu，current/best utility)

依赖:
  pip install mat73 numpy matplotlib scipy

用法:
  python plot_varyN_top_config.py                     # 自动搜索最新 .mat
  python plot_varyN_top_config.py path/to/varyN.mat   # 指定文件

说明:
  你可以直接在本文件最上方的“顶部可调参数区”中修改：
  - 图尺寸、线宽、字体、图例字号、输出 dpi
  - 每个图的标题、坐标轴名称、坐标范围、刻度
  - 是否显示网格、图例、标题
  - 图3a 内循环两条线的颜色、线型、阴影透明度
"""

import os
import sys
import glob
import copy
import numpy as np
import matplotlib.pyplot as plt
import matplotlib.ticker as mticker

try:
    import mat73
except ImportError:
    sys.exit("缺少依赖，请先执行: pip install mat73")


# ══════════════════════════════════════════════════════════════════════════════
# 顶部可调参数区（建议以后优先在这里改）
# ══════════════════════════════════════════════════════════════════════════════

# ── 路径配置 ──────────────────────────────────────────────────────────────────
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
ROOT_DIR = os.path.dirname(SCRIPT_DIR)
FIGURES_DIR = os.path.join(ROOT_DIR, 'figures', 'paper')
SEARCH_DIRS = [
    os.path.join(ROOT_DIR, 'results', 'batch', 'varyN'),
    os.path.join(ROOT_DIR, 'results', 'batch'),
]

# ── 算法显示样式（四个算法的颜色 / 点型 / 线型 / 图例名）────────────────────────
ALG_STYLE = {
    'Huo2025':    dict(color='#4878CF', marker='o', ls='-',  label='Huo2025'),
    'Qi2023':     dict(color='#6ACC65', marker='s', ls='--', label='Qi2023'),
    'Shi2024':    dict(color='#D65F5F', marker='^', ls='-.', label='Shi2024'),
    'OCF_SAtabu': dict(color='#B47CC7', marker='D', ls='-',  label='Ours (OCF-SA)'),
}
DEFAULT_STYLE = dict(color='#888888', marker='x', ls=':', label='Unknown')

# ── 全局绘图参数 ──────────────────────────────────────────────────────────────
PLOT_GLOBAL = {
    # 图尺寸
    'figsize': (5.5, 4.2),

    # 线条 / 点 / 误差棒
    'linewidth': 1.8,
    'markersize': 7,
    'capsize': 1,

    # 字体与版式
    'xlabel_fontsize': 11,
    'ylabel_fontsize': 11,
    'title_fontsize': 12,
    'title_pad': 8,
    'tick_fontsize': 10,
    'legend_fontsize': 9,

    # 网格 / 图例 / 边框
    'show_grid': True,
    'grid_linestyle': '--',
    'grid_linewidth': 0.6,
    'grid_alpha': 0.4,
    'show_legend': True,
    'legend_framealpha': 0.85,
    'legend_edgecolor': '#cccccc',
    'hide_top_spine': True,
    'hide_right_spine': True,

    # 保存参数
    'save_dpi': 150,
    'save_bbox_inches': 'tight',

    # 画布
    'tight_layout': True,
}

# ── 图3a 专用样式（原来写死在函数里，现在提到顶部）────────────────────────────
INNER_LOOP_STYLE = {
    'current_label': 'Current Utility',
    'current_color': '#4878CF',
    'current_ls': '-',
    'current_band_alpha': 0.15,

    'best_label': 'Best Utility',
    'best_color': '#D65F5F',
    'best_ls': '--',
    'best_band_alpha': 0.15,

    # 只是标题里显示的 round 标签，不影响数据提取
    'round_label': 50,
}

# ── 每个图单独控制（坐标轴 / 刻度 / 标题 / 范围）──────────────────────────────
# 说明：
#   xlim / ylim = None 表示自动
#   xticks / yticks = None 表示自动
#   use_fixed_N_xticks = True 表示 x 轴刻度强制使用 N_values
#   bottom_zero = True 常用于完成度图让 y 轴从 0 开始
FIGURE_CONFIG = {
    'fig1a': {
        'show_title': True,
        'title': 'Fig. 1a — Utility vs. N',
        'xlabel': 'Number of Agents (N)',
        'ylabel': 'Final Coalition Utility',
        'xlim': None,
        'ylim': None,
        'xticks': None,
        'yticks': None,
        'use_fixed_N_xticks': True,
        'bottom_zero': False,
    },
    'fig1b': {
        'show_title': True,
        'title': 'Fig. 1b — Completion vs. N',
        'xlabel': 'Number of Agents (N)',
        'ylabel': 'Avg. Task Completion Degree',
        'xlim': None,
        'ylim': None,
        'xticks': None,
        'yticks': None,
        'use_fixed_N_xticks': True,
        'bottom_zero': True,
    },
    'fig2c': {
        'show_title': True,
        'title_template': 'Fig. 2c — Convergence (N={n_target})',
        'xlabel': 'Round',
        'ylabel': 'Coalition Utility',
        'xlim': None,
        'ylim': None,
        'xticks': None,
        'yticks': None,
        'use_fixed_N_xticks': False,
        'bottom_zero': False,
    },
    'fig3a': {
        'show_title': True,
        'title_template': 'Fig. 3a — Inner Loop (Round {round_label}, N={n_target})',
        'xlabel': 'Inner Iteration',
        'ylabel': 'Utility',
        'xlim': None,
        'ylim': None,
        'xticks': None,
        'yticks': None,
        'use_fixed_N_xticks': False,
        'bottom_zero': False,
    },
}

os.makedirs(FIGURES_DIR, exist_ok=True)


# ══════════════════════════════════════════════════════════════════════════════
# 工具函数
# ══════════════════════════════════════════════════════════════════════════════

def find_mat_file(argv):
    """优先命令行参数，否则在 SEARCH_DIRS 中找最新的 .mat 文件。"""
    if len(argv) > 1:
        p = argv[1]
        if os.path.isfile(p):
            return p
        print(f"警告: 指定的文件不存在 '{p}'，尝试自动搜索。")

    candidates = []
    for d in SEARCH_DIRS:
        candidates.extend(glob.glob(os.path.join(d, '*.mat')))

    varyN = [
        f for f in candidates
        if 'varyN' in os.path.basename(f) or os.path.basename(f).startswith('N')
    ]
    pool = varyN if varyN else candidates
    if not pool:
        sys.exit("找不到 .mat 文件，请先运行 Batch_VaryN.m，或手动指定路径作为命令行参数。")

    chosen = max(pool, key=os.path.getmtime)
    print(f"自动选择: {chosen}")
    return chosen


def to_scalar(val):
    """将 mat73 返回的各种标量形式统一成 Python float。"""
    if val is None:
        return np.nan
    arr = np.asarray(val, dtype=float).ravel()
    return float(arr[0]) if len(arr) > 0 else np.nan


def to_1d(val, length=None):
    """将字段转为 1D float array，不足 length 时 NaN 后缀。"""
    if val is None:
        return np.full(length or 0, np.nan)
    arr = np.asarray(val, dtype=float).ravel()
    if length is not None and len(arr) < length:
        arr = np.concatenate([arr, np.full(length - len(arr), np.nan)])
    return arr


def iter_results(results):
    """
    mat73 加载的 cell array 可能是 list-of-list 或 numpy object array。
    统一返回 (ni, si, entry_dict) 迭代器。
    """
    if isinstance(results, np.ndarray):
        rows, cols = results.shape
        for ni in range(rows):
            for si in range(cols):
                yield ni, si, results[ni, si]
    elif isinstance(results, list):
        for ni, row in enumerate(results):
            if isinstance(row, list):
                for si, entry in enumerate(row):
                    yield ni, si, entry
            else:
                yield ni, 0, row
    else:
        yield 0, 0, results


def get_shape(results):
    """返回 (nN, nS)。"""
    if isinstance(results, np.ndarray):
        return results.shape
    if isinstance(results, list):
        nN = len(results)
        nS = len(results[0]) if results and isinstance(results[0], list) else 1
        return nN, nS
    return 1, 1


def parse_alg_names(config):
    """从 config 中提取算法名列表。"""
    raw = config.get('alg_names', [])
    if isinstance(raw, str):
        return [raw]
    if isinstance(raw, np.ndarray):
        return list(raw.ravel())
    return list(raw)


def parse_N_values(config):
    return list(np.asarray(config['N_values'], dtype=int).ravel())


def merge_figure_config(fig_key, **kwargs):
    """复制并补充每个图的配置，避免运行中修改全局字典。"""
    cfg = copy.deepcopy(FIGURE_CONFIG[fig_key])
    cfg.update(kwargs)
    return cfg


def apply_common_style(ax, cfg, title=None):
    """统一处理坐标轴标签、标题、网格、图例和边框。"""
    ax.set_xlabel(cfg['xlabel'], fontsize=PLOT_GLOBAL['xlabel_fontsize'])
    ax.set_ylabel(cfg['ylabel'], fontsize=PLOT_GLOBAL['ylabel_fontsize'])

    if cfg.get('show_title', True) and title:
        ax.set_title(
            title,
            fontsize=PLOT_GLOBAL['title_fontsize'],
            pad=PLOT_GLOBAL['title_pad'],
        )

    if PLOT_GLOBAL['show_grid']:
        ax.grid(
            True,
            linestyle=PLOT_GLOBAL['grid_linestyle'],
            linewidth=PLOT_GLOBAL['grid_linewidth'],
            alpha=PLOT_GLOBAL['grid_alpha'],
        )

    ax.tick_params(labelsize=PLOT_GLOBAL['tick_fontsize'])

    if PLOT_GLOBAL['show_legend']:
        ax.legend(
            fontsize=PLOT_GLOBAL['legend_fontsize'],
            framealpha=PLOT_GLOBAL['legend_framealpha'],
            edgecolor=PLOT_GLOBAL['legend_edgecolor'],
        )

    if PLOT_GLOBAL['hide_top_spine']:
        ax.spines['top'].set_visible(False)
    if PLOT_GLOBAL['hide_right_spine']:
        ax.spines['right'].set_visible(False)


def apply_axis_controls(ax, cfg, n_values=None):
    """统一处理 xlim / ylim / xticks / yticks / 底部从 0 开始等。"""
    if cfg.get('use_fixed_N_xticks', False) and n_values is not None:
        ax.xaxis.set_major_locator(mticker.FixedLocator(n_values))

    if cfg.get('xticks') is not None:
        ax.set_xticks(cfg['xticks'])
    if cfg.get('yticks') is not None:
        ax.set_yticks(cfg['yticks'])

    if cfg.get('xlim') is not None:
        ax.set_xlim(*cfg['xlim'])
    if cfg.get('ylim') is not None:
        ax.set_ylim(*cfg['ylim'])

    if cfg.get('bottom_zero', False):
        ymin, ymax = ax.get_ylim()
        ax.set_ylim(bottom=0, top=ymax)


def finalize_and_save(fig, save_path):
    if PLOT_GLOBAL['tight_layout']:
        fig.tight_layout()
    fig.savefig(
        save_path,
        dpi=PLOT_GLOBAL['save_dpi'],
        bbox_inches=PLOT_GLOBAL['save_bbox_inches'],
    )
    print(f"  ✓ {save_path}")


# ══════════════════════════════════════════════════════════════════════════════
# 数据提取
# ══════════════════════════════════════════════════════════════════════════════

def extract_final_metrics(results, config):
    """
    返回:
      N_values  : list[int]
      alg_names : list[str]
      metrics   : {alg: {'utility': (nN, nS), 'completion': (nN, nS),
                          'cost': (nN, nS), 'time': (nN, nS)}}
    """
    N_values = parse_N_values(config)
    alg_names = parse_alg_names(config)
    nN, nS = get_shape(results)

    metrics = {
        a: {k: np.full((nN, nS), np.nan) for k in ('utility', 'completion', 'cost', 'time')}
        for a in alg_names
    }

    for ni, si, entry in iter_results(results):
        if not entry or not entry.get('success', False):
            continue
        algs_data = entry.get('algs', {}) or {}
        for aname in alg_names:
            ae = algs_data.get(aname)
            if not ae or not ae.get('success', False):
                continue
            metrics[aname]['utility'][ni, si] = to_scalar(ae.get('final_utility'))
            metrics[aname]['completion'][ni, si] = to_scalar(ae.get('final_completion'))
            metrics[aname]['cost'][ni, si] = to_scalar(ae.get('final_cost'))
            metrics[aname]['time'][ni, si] = to_scalar(ae.get('computation_time'))

    return N_values, alg_names, metrics


def extract_convergence(results, config, n_target=None):
    """
    提取收敛曲线（图2c）。
    n_target: 取哪个 N 值（None → 取最大 N）。
    返回: mean_curves {alg: [R,]}, num_rounds, n_target
    """
    N_values = parse_N_values(config)
    alg_names = parse_alg_names(config)
    num_rounds = int(to_scalar(config.get('num_rounds', 100)))
    if n_target is None:
        n_target = max(N_values)
    ni_target = N_values.index(n_target)

    curves = {a: [] for a in alg_names}

    for ni, si, entry in iter_results(results):
        if ni != ni_target:
            continue
        if not entry or not entry.get('success', False):
            continue
        algs_data = entry.get('algs', {}) or {}
        for aname in alg_names:
            ae = algs_data.get(aname)
            if not ae or not ae.get('success', False):
                continue
            arr = to_1d(ae.get('convergence_utility'), length=num_rounds)
            curves[aname].append(arr)

    mean_curves = {}
    for aname in alg_names:
        if curves[aname]:
            mat = np.vstack(curves[aname])
            mean_curves[aname] = np.nanmean(mat, axis=0)
        else:
            mean_curves[aname] = np.full(num_rounds, np.nan)

    return mean_curves, num_rounds, n_target


def extract_inner_loop(results, config, n_target=None):
    """
    提取 OCF_SAtabu 的内循环轨迹（图3a），对各种子求均值。
    返回: mean_curr, std_curr, mean_best, std_best, n_target
    """
    N_values = parse_N_values(config)
    if n_target is None:
        n_target = max(N_values)
    ni_target = N_values.index(n_target)

    all_curr, all_best = [], []

    for ni, si, entry in iter_results(results):
        if ni != ni_target:
            continue
        if not entry or not entry.get('success', False):
            continue
        ae = (entry.get('algs', {}) or {}).get('OCF_SAtabu')
        if not ae or not ae.get('success', False):
            continue
        il = ae.get('inner_loop_r50') or {}
        if not il:
            continue
        curr = to_1d(il.get('current_utility'))
        best = to_1d(il.get('best_utility'))
        if len(curr) > 0 and not np.all(np.isnan(curr)):
            all_curr.append(curr)
        if len(best) > 0 and not np.all(np.isnan(best)):
            all_best.append(best)

    def mean_ragged(lst):
        if not lst:
            return None, None
        max_len = max(len(a) for a in lst)
        mat = np.full((len(lst), max_len), np.nan)
        for i, a in enumerate(lst):
            mat[i, :len(a)] = a
        return np.nanmean(mat, axis=0), np.nanstd(mat, axis=0)

    mean_curr, std_curr = mean_ragged(all_curr)
    mean_best, std_best = mean_ragged(all_best)
    return mean_curr, std_curr, mean_best, std_best, n_target


# ══════════════════════════════════════════════════════════════════════════════
# 绘图函数
# ══════════════════════════════════════════════════════════════════════════════

def plot_fig1a(N_values, alg_names, metrics, save_path):
    """图1a：变N效用（mean ± std 折线图）"""
    cfg = merge_figure_config('fig1a')
    fig, ax = plt.subplots(figsize=PLOT_GLOBAL['figsize'])

    for aname in alg_names:
        st = ALG_STYLE.get(aname, DEFAULT_STYLE)
        mu = np.nanmean(metrics[aname]['utility'], axis=1)
        std = np.nanstd(metrics[aname]['utility'], axis=1)
        ax.errorbar(
            N_values, mu, yerr=std,
            color=st['color'], marker=st['marker'], ls=st['ls'],
            lw=PLOT_GLOBAL['linewidth'], ms=PLOT_GLOBAL['markersize'],
            capsize=PLOT_GLOBAL['capsize'],
            label=st['label'], zorder=3,
        )

    apply_axis_controls(ax, cfg, n_values=N_values)
    apply_common_style(ax, cfg, title=cfg.get('title'))
    finalize_and_save(fig, save_path)


def plot_fig1b(N_values, alg_names, metrics, save_path):
    """图1b：变N完成度（mean ± std 折线图）"""
    cfg = merge_figure_config('fig1b')
    fig, ax = plt.subplots(figsize=PLOT_GLOBAL['figsize'])

    for aname in alg_names:
        st = ALG_STYLE.get(aname, DEFAULT_STYLE)
        mu = np.nanmean(metrics[aname]['completion'], axis=1)
        std = np.nanstd(metrics[aname]['completion'], axis=1)
        ax.errorbar(
            N_values, mu, yerr=std,
            color=st['color'], marker=st['marker'], ls=st['ls'],
            lw=PLOT_GLOBAL['linewidth'], ms=PLOT_GLOBAL['markersize'],
            capsize=PLOT_GLOBAL['capsize'],
            label=st['label'], zorder=3,
        )

    apply_axis_controls(ax, cfg, n_values=N_values)
    apply_common_style(ax, cfg, title=cfg.get('title'))
    finalize_and_save(fig, save_path)


def plot_fig2c(mean_curves, num_rounds, n_target, alg_names, save_path):
    """图2c：效用收敛曲线（对指定N均值化）"""
    cfg = merge_figure_config(
        'fig2c',
        title=FIGURE_CONFIG['fig2c']['title_template'].format(n_target=n_target),
    )
    fig, ax = plt.subplots(figsize=PLOT_GLOBAL['figsize'])
    rounds = np.arange(1, num_rounds + 1)

    for aname in alg_names:
        curve = mean_curves.get(aname)
        if curve is None or np.all(np.isnan(curve)):
            continue
        st = ALG_STYLE.get(aname, DEFAULT_STYLE)
        mask = ~np.isnan(curve)
        if not np.any(mask):
            continue
        filled = curve.copy()
        idx = np.where(mask)[0]
        filled[idx[-1] + 1:] = filled[idx[-1]]
        ax.plot(
            rounds, filled,
            color=st['color'], ls=st['ls'],
            lw=PLOT_GLOBAL['linewidth'], label=st['label'],
        )

    apply_axis_controls(ax, cfg)
    apply_common_style(ax, cfg, title=cfg.get('title'))
    finalize_and_save(fig, save_path)


def plot_fig3a(mean_curr, std_curr, mean_best, std_best, n_target, save_path):
    """图3a：OCF_SAtabu 内循环 current / best utility 轨迹"""
    if mean_curr is None and mean_best is None:
        print("  ! 内循环数据为空（OCF_SAtabu 未记录 inner_loop），跳过图3a")
        return

    cfg = merge_figure_config(
        'fig3a',
        title=FIGURE_CONFIG['fig3a']['title_template'].format(
            round_label=INNER_LOOP_STYLE['round_label'],
            n_target=n_target,
        ),
    )
    fig, ax = plt.subplots(figsize=PLOT_GLOBAL['figsize'])
    ref = mean_curr if mean_curr is not None else mean_best
    iters = np.arange(1, len(ref) + 1)

    if mean_curr is not None:
        ax.plot(
            iters, mean_curr,
            color=INNER_LOOP_STYLE['current_color'],
            ls=INNER_LOOP_STYLE['current_ls'],
            lw=PLOT_GLOBAL['linewidth'],
            label=INNER_LOOP_STYLE['current_label'],
        )
        if std_curr is not None:
            ax.fill_between(
                iters,
                mean_curr - std_curr,
                mean_curr + std_curr,
                alpha=INNER_LOOP_STYLE['current_band_alpha'],
                color=INNER_LOOP_STYLE['current_color'],
            )

    if mean_best is not None:
        ax.plot(
            iters, mean_best,
            color=INNER_LOOP_STYLE['best_color'],
            ls=INNER_LOOP_STYLE['best_ls'],
            lw=PLOT_GLOBAL['linewidth'],
            label=INNER_LOOP_STYLE['best_label'],
        )
        if std_best is not None:
            ax.fill_between(
                iters,
                mean_best - std_best,
                mean_best + std_best,
                alpha=INNER_LOOP_STYLE['best_band_alpha'],
                color=INNER_LOOP_STYLE['best_color'],
            )

    apply_axis_controls(ax, cfg)
    apply_common_style(ax, cfg, title=cfg.get('title'))
    finalize_and_save(fig, save_path)


# ══════════════════════════════════════════════════════════════════════════════
# 主程序
# ══════════════════════════════════════════════════════════════════════════════

def main():
    mat_path = find_mat_file(sys.argv)

    print("\n加载数据...")
    raw = mat73.loadmat(mat_path)
    results = raw['scale_N_results']
    config = raw['scale_config']

    N_values = parse_N_values(config)
    alg_names = parse_alg_names(config)
    nN, nS = get_shape(results)
    n_conv = max(N_values)

    print(f"  N_values  = {N_values}")
    print(f"  alg_names = {alg_names}")
    print(f"  形状      = {nN}×{nS} (N×seed)")

    basename = os.path.splitext(os.path.basename(mat_path))[0]
    parts = basename.split('_')
    ts = '_'.join(parts[-2:]) if len(parts) >= 2 else 'ts'

    print("\n提取指标...")
    N_values, alg_names, metrics = extract_final_metrics(results, config)

    print(f"\n绘图 → {FIGURES_DIR}")

    plot_fig1a(
        N_values, alg_names, metrics,
        os.path.join(FIGURES_DIR, f'fig1a_utility_varyN_{ts}.png'),
    )

    plot_fig1b(
        N_values, alg_names, metrics,
        os.path.join(FIGURES_DIR, f'fig1b_completion_varyN_{ts}.png'),
    )

    mean_curves, num_rounds, n_target = extract_convergence(
        results, config, n_target=n_conv,
    )
    plot_fig2c(
        mean_curves, num_rounds, n_target, alg_names,
        os.path.join(FIGURES_DIR, f'fig2c_convergence_N{n_target}_{ts}.png'),
    )

    mc, sc, mb, sb, nt = extract_inner_loop(results, config, n_target=n_conv)
    plot_fig3a(
        mc, sc, mb, sb, nt,
        os.path.join(FIGURES_DIR, f'fig3a_innerloop_N{nt}_{ts}.png'),
    )

    print("\n完成。图窗已弹出，关闭后程序退出。")
    plt.show()


if __name__ == '__main__':
    main()
