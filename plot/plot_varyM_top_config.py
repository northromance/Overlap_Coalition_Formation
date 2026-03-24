"""
plot_varyM_top_config.py
========================
从 Batch_VaryM.m 生成的 .mat 文件绘制论文图：
  图1c  变M效用       (mean ± std 折线图，4算法)
  图1d  变M完成度     (mean ± std 折线图，4算法)
  图1e  变M完成总价值 (mean ± std 折线图，4算法)
  图2d  效用收敛曲线  (对最大M，按种子平均)

依赖:
  pip install mat73 numpy matplotlib scipy

用法:
  python plot_varyM_top_config.py                     # 自动搜索最新 .mat
  python plot_varyM_top_config.py path/to/varyM.mat   # 指定文件

说明:
  你可以直接在本文件最上方的"顶部可调参数区"中修改：
  - 图尺寸、线宽、字体、图例字号、输出 dpi
  - 每个图的标题、坐标轴名称、坐标范围、刻度
  - 是否显示网格、图例、标题
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
SCRIPT_DIR  = os.path.dirname(os.path.abspath(__file__))
ROOT_DIR    = os.path.dirname(SCRIPT_DIR)
FIGURES_DIR = os.path.join(ROOT_DIR, 'figures', 'paper')
SEARCH_DIRS = [
    os.path.join(ROOT_DIR, 'results', 'batch', 'varyM'),
    os.path.join(ROOT_DIR, 'results', 'batch'),
]

# ── 算法显示样式（颜色 / 点型 / 线型 / 图例名）────────────────────────────────
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
    'capsize': 4,
    'show_fig2d_band': True,   # 控制 fig2d 是否显示半透明误差带
    'fig2d_band_alpha': 0.18,
    'show_errorbar': True, # 控制 fig1c / fig1d / fig1e 是否画误差棒

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

# ── 每个图单独控制（坐标轴 / 刻度 / 标题 / 范围）──────────────────────────────
# 说明：
#   xlim / ylim = None 表示自动
#   xticks / yticks = None 表示自动
#   use_fixed_M_xticks = True 表示 x 轴刻度强制使用 M_values
#   bottom_zero = True 常用于完成度图让 y 轴从 0 开始
FIGURE_CONFIG = {
    'fig1c': {
        'show_title': True,
        'title': 'Fig. 1c — Utility vs. M',
        'xlabel': 'Number of Tasks (M)',
        'ylabel': 'Final Coalition Utility',
        'xlim': None,
        'ylim': None,
        'xticks': None,
        'yticks': None,
        'use_fixed_M_xticks': True,
        'bottom_zero': False,
    },
    'fig1d': {
        'show_title': True,
        'title': 'Fig. 1d — Completion vs. M',
        'xlabel': 'Number of Tasks (M)',
        'ylabel': 'Avg. Task Completion Degree',
        'xlim': None,
        'ylim': None,
        'xticks': None,
        'yticks': None,
        'use_fixed_M_xticks': True,
        'bottom_zero': True,
    },
    'fig1e': {
        'show_title': True,
        'title': 'Fig. 1e — Total Completed Value vs. M',
        'xlabel': 'Number of Tasks (M)',
        'ylabel': 'Total Completed Value',
        'xlim': None,
        'ylim': None,
        'xticks': None,
        'yticks': None,
        'use_fixed_M_xticks': True,
        'bottom_zero': True,
    },
    'fig2d': {
        'show_title': True,
        'title_template': 'Fig. 2d — Convergence (M={m_target})',
        'xlabel': 'Round',
        'ylabel': 'Coalition Utility',
        'xlim': None,
        'ylim': None,
        'xticks': None,
        'yticks': None,
        'use_fixed_M_xticks': False,
        'bottom_zero': False,
    },
}

os.makedirs(FIGURES_DIR, exist_ok=True)


# ══════════════════════════════════════════════════════════════════════════════
# 工具函数
# ══════════════════════════════════════════════════════════════════════════════

def find_mat_file(argv):
    """优先命令行参数，否则在 SEARCH_DIRS 中找最新的 varyM .mat 文件。"""
    if len(argv) > 1:
        p = argv[1]
        if os.path.isfile(p):
            return p
        print(f"警告: 指定的文件不存在 '{p}'，尝试自动搜索。")

    candidates = []
    for d in SEARCH_DIRS:
        candidates.extend(glob.glob(os.path.join(d, '*.mat')))

    # 优先匹配 varyM 目录下的文件，或文件名含 varyM，或形如 N{int}_M{int}-{int}_...
    varyM = [
        f for f in candidates
        if 'varyM' in os.path.basename(f)
        or os.path.join('varyM', '') in f.replace('\\', '/')
        or (os.path.basename(f).startswith('N') and '_M' in os.path.basename(f)
            and '-' in os.path.basename(f).split('_M', 1)[-1].split('_')[0])
    ]
    pool = varyM if varyM else candidates
    if not pool:
        sys.exit(
            "找不到 .mat 文件，请先运行 Batch_VaryM.m，或手动指定路径作为命令行参数。"
        )

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
    统一返回 (mi, si, entry_dict) 迭代器。
    """
    if isinstance(results, np.ndarray):
        rows, cols = results.shape
        for mi in range(rows):
            for si in range(cols):
                yield mi, si, results[mi, si]
    elif isinstance(results, list):
        for mi, row in enumerate(results):
            if isinstance(row, list):
                for si, entry in enumerate(row):
                    yield mi, si, entry
            else:
                yield mi, 0, row
    else:
        yield 0, 0, results


def get_shape(results):
    """返回 (nM, nS)。"""
    if isinstance(results, np.ndarray):
        return results.shape
    if isinstance(results, list):
        nM = len(results)
        nS = len(results[0]) if results and isinstance(results[0], list) else 1
        return nM, nS
    return 1, 1


def parse_alg_names(config):
    """从 config 中提取算法名列表。"""
    raw = config.get('alg_names', [])
    if isinstance(raw, str):
        return [raw]
    if isinstance(raw, np.ndarray):
        return list(raw.ravel())
    return list(raw)


def parse_M_values(config):
    return list(np.asarray(config['M_values'], dtype=int).ravel())


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


def apply_axis_controls(ax, cfg, m_values=None):
    """统一处理 xlim / ylim / xticks / yticks / 底部从 0 开始等。"""
    if cfg.get('use_fixed_M_xticks', False) and m_values is not None:
        ax.xaxis.set_major_locator(mticker.FixedLocator(m_values))

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
    从 scale_M_results / scale_config 提取最终指标矩阵。

    返回:
      M_values  : list[int]
      alg_names : list[str]
      metrics   : {alg: {'utility': (nM, nS), 'completion': (nM, nS),
                          'completed_value': (nM, nS), 'cost': (nM, nS), 'time': (nM, nS)}}
    """
    M_values  = parse_M_values(config)
    alg_names = parse_alg_names(config)
    nM, nS    = get_shape(results)

    metrics = {
        a: {k: np.full((nM, nS), np.nan)
            for k in ('utility', 'completion', 'completed_value', 'cost', 'time')}
        for a in alg_names
    }

    for mi, si, entry in iter_results(results):
        if not entry or not entry.get('success', False):
            continue
        algs_data = entry.get('algs', {}) or {}
        for aname in alg_names:
            ae = algs_data.get(aname)
            if not ae or not ae.get('success', False):
                continue

            utility         = to_scalar(ae.get('final_utility'))
            completion      = to_scalar(ae.get('final_completion'))
            cost            = to_scalar(ae.get('final_cost'))
            completed_value = to_scalar(ae.get('final_completed_value'))

            # 兼容旧数据：若没有 final_completed_value 则用 utility + cost 近似
            if np.isnan(completed_value) and not np.isnan(utility) and not np.isnan(cost):
                completed_value = utility + cost

            metrics[aname]['utility'][mi, si]         = utility
            metrics[aname]['completion'][mi, si]      = completion
            metrics[aname]['completed_value'][mi, si] = completed_value
            metrics[aname]['cost'][mi, si]            = cost
            metrics[aname]['time'][mi, si]            = to_scalar(ae.get('computation_time'))

    return M_values, alg_names, metrics


def extract_convergence(results, config, m_target=None):
    """
    提取效用收敛曲线（图2d）。
    m_target: 取哪个 M 值（None → 取最大 M）。
    返回: mean_curves, std_curves, num_rounds, m_target
    """
    M_values   = parse_M_values(config)
    alg_names  = parse_alg_names(config)
    num_rounds = int(to_scalar(config.get('num_rounds', 100)))

    if m_target is None:
        m_target = max(M_values)
    mi_target = M_values.index(m_target)

    curves = {a: [] for a in alg_names}

    for mi, si, entry in iter_results(results):
        if mi != mi_target:
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
    std_curves  = {}

    for aname in alg_names:
        if curves[aname]:
            mat = np.vstack(curves[aname])
            mean_curves[aname] = np.nanmean(mat, axis=0)
            std_curves[aname]  = np.nanstd(mat, axis=0)
        else:
            mean_curves[aname] = np.full(num_rounds, np.nan)
            std_curves[aname]  = np.full(num_rounds, np.nan)

    return mean_curves, std_curves, num_rounds, m_target


# ══════════════════════════════════════════════════════════════════════════════
# 绘图函数（复用同一个内部实现，只在 FIGURE_CONFIG 中区分参数）
# ══════════════════════════════════════════════════════════════════════════════

def _plot_scalar_vs_M(fig_key, metric_key, M_values, alg_names, metrics, save_path):
    """通用：画某个标量指标 vs M 的折线图（均值 ± std）。"""
    cfg = merge_figure_config(fig_key)
    fig, ax = plt.subplots(figsize=PLOT_GLOBAL['figsize'])

    for aname in alg_names:
        st  = ALG_STYLE.get(aname, DEFAULT_STYLE)
        mu  = np.nanmean(metrics[aname][metric_key], axis=1)
        std = np.nanstd(metrics[aname][metric_key], axis=1)

        if PLOT_GLOBAL.get('show_errorbar', False):
            ax.errorbar(
                M_values, mu, yerr=std,
                color=st['color'], marker=st['marker'], ls=st['ls'],
                lw=PLOT_GLOBAL['linewidth'], ms=PLOT_GLOBAL['markersize'],
                capsize=PLOT_GLOBAL['capsize'],
                label=st['label'], zorder=3,
            )
        else:
            ax.plot(
                M_values, mu,
                color=st['color'], marker=st['marker'], ls=st['ls'],
                lw=PLOT_GLOBAL['linewidth'], ms=PLOT_GLOBAL['markersize'],
                label=st['label'], zorder=3,
            )

    apply_axis_controls(ax, cfg, m_values=M_values)
    apply_common_style(ax, cfg, title=cfg.get('title'))
    finalize_and_save(fig, save_path)


def plot_fig1c(M_values, alg_names, metrics, save_path):
    """图1c：变M效用（mean ± std 折线图）"""
    _plot_scalar_vs_M('fig1c', 'utility', M_values, alg_names, metrics, save_path)


def plot_fig1d(M_values, alg_names, metrics, save_path):
    """图1d：变M任务完成度（mean ± std 折线图）"""
    _plot_scalar_vs_M('fig1d', 'completion', M_values, alg_names, metrics, save_path)


def plot_fig1e(M_values, alg_names, metrics, save_path):
    """图1e：变M总完成价值（mean ± std 折线图）"""
    _plot_scalar_vs_M('fig1e', 'completed_value', M_values, alg_names, metrics, save_path)


def plot_fig2d(mean_curves, std_curves, num_rounds, m_target, alg_names, save_path):
    """图2d：效用收敛曲线（对最大M，按种子平均 + 半透明误差带）"""
    cfg = merge_figure_config(
        'fig2d',
        title=FIGURE_CONFIG['fig2d']['title_template'].format(m_target=m_target),
    )
    fig, ax = plt.subplots(figsize=PLOT_GLOBAL['figsize'])
    rounds = np.arange(1, num_rounds + 1)

    for aname in alg_names:
        curve = mean_curves.get(aname)
        std   = std_curves.get(aname)

        if curve is None or np.all(np.isnan(curve)):
            continue

        st   = ALG_STYLE.get(aname, DEFAULT_STYLE)
        mask = ~np.isnan(curve)
        if not np.any(mask):
            continue

        # 用最后一个有效值向右补平（避免截断）
        filled = curve.copy()
        idx    = np.where(mask)[0]
        filled[idx[-1] + 1:] = filled[idx[-1]]

        if std is not None:
            std_filled = std.copy()
            std_filled[idx[-1] + 1:] = std_filled[idx[-1]]

            if PLOT_GLOBAL.get('show_fig2d_band', False):
                lower = filled - std_filled
                upper = filled + std_filled
                ax.fill_between(
                    rounds, lower, upper,
                    color=st['color'],
                    alpha=PLOT_GLOBAL.get('fig2d_band_alpha', 0.18),
                    linewidth=0,
                )

        ax.plot(
            rounds, filled,
            color=st['color'], ls=st['ls'],
            lw=PLOT_GLOBAL['linewidth'], label=st['label'],
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
    raw     = mat73.loadmat(mat_path)
    results = raw['scale_M_results']
    config  = raw['scale_config']

    M_values  = parse_M_values(config)
    alg_names = parse_alg_names(config)
    nM, nS    = get_shape(results)
    fixed_N   = int(to_scalar(config.get('N', 0)))
    m_conv    = max(M_values)

    print(f"  固定 N    = {fixed_N}")
    print(f"  M_values  = {M_values}")
    print(f"  alg_names = {alg_names}")
    print(f"  形状      = {nM}×{nS} (M×seed)")

    # 时间戳：取文件名末尾两段，如 20260322_224718
    basename = os.path.splitext(os.path.basename(mat_path))[0]
    parts = basename.split('_')
    ts = '_'.join(parts[-2:]) if len(parts) >= 2 else 'ts'

    print("\n提取指标...")
    M_values, alg_names, metrics = extract_final_metrics(results, config)

    print(f"\n绘图 → {FIGURES_DIR}")

    plot_fig1c(
        M_values, alg_names, metrics,
        os.path.join(FIGURES_DIR, f'fig1c_utility_varyM_{ts}.png'),
    )

    plot_fig1d(
        M_values, alg_names, metrics,
        os.path.join(FIGURES_DIR, f'fig1d_completion_varyM_{ts}.png'),
    )

    plot_fig1e(
        M_values, alg_names, metrics,
        os.path.join(FIGURES_DIR, f'fig1e_completed_value_varyM_{ts}.png'),
    )

    mean_curves, std_curves, num_rounds, m_target = extract_convergence(
        results, config, m_target=m_conv,
    )
    plot_fig2d(
        mean_curves, std_curves, num_rounds, m_target, alg_names,
        os.path.join(FIGURES_DIR, f'fig2d_convergence_M{m_target}_{ts}.png'),
    )
    print("\n完成。图窗已弹出，关闭后程序退出。")
    plt.show()


if __name__ == '__main__':
    main()
