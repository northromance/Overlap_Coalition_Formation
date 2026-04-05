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
  python plot/plot_varyN.py                     # 自动搜索最新 .mat
  python plot/plot_varyN.py path/to/varyN.mat   # 指定文件
"""

import os
import sys
import glob
import numpy as np
import matplotlib.pyplot as plt
import matplotlib.ticker as mticker
from plot_style_helper import PlotStyleHelper, build_results_figures_dir, cm_size_to_inch, infer_source_name

try:
    import mat73
except ImportError:
    sys.exit("缺少依赖，请先执行: pip install mat73")


# =========================
# 顶部可调绘图参数
# 这里集中放置尺寸、线宽、字号和保存设置。
# =========================

# 路径配置
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
ROOT_DIR = os.path.dirname(SCRIPT_DIR)
FIGURES_DIR = build_results_figures_dir(ROOT_DIR, 'varyN')
SEARCH_DIRS = [
    os.path.join(ROOT_DIR, 'results', 'batch', 'varyN'),
    os.path.join(ROOT_DIR, 'results', 'batch'),
]

os.makedirs(FIGURES_DIR, exist_ok=True)

# 算法显示样式：颜色 / marker / 线型 / 图例名
ALG_STYLE = {
    'Huo2025': dict(color='#4878CF', marker='o', ls='-', label='Huo2025'),
    'Qi2023': dict(color='#6ACC65', marker='s', ls='--', label='Qi2023'),
    'Shi2024': dict(color='#D65F5F', marker='^', ls='-.', label='Shi2024'),
    'OCF_SAtabu': dict(color='#B47CC7', marker='D', ls='-', label='Ours (OCF-SA)'),
}
DEFAULT_STYLE = dict(color='#888888', marker='x', ls=':', label='Unknown')

# 单图尺寸与线条参数
FIGSIZE_CM = (13.97, 10.67)  # 主图尺寸（宽, 高），单位 cm
LW = 1.8  # 主曲线线宽
MS = 7  # marker 大小
CAPS = 4  # 误差棒帽宽

# 交给 PlotStyleHelper 的通用样式适配器
PLOT_GLOBAL_ADAPTER = {
    'xlabel_fontsize': 11,  # x 轴标题字号
    'ylabel_fontsize': 11,  # y 轴标题字号
    'title_fontsize': 12,  # 标题字号
    'title_pad': 8,  # 标题与坐标轴之间的间距
    'tick_fontsize': 10,  # 刻度字号
    'legend_fontsize': 9,  # 图例字号
    'show_grid': True,  # 是否显示网格
    'grid_linestyle': '--',  # 网格线型
    'grid_linewidth': 0.6,  # 网格线宽
    'grid_alpha': 0.4,  # 网格透明度
    'show_legend': True,  # 是否显示图例
    'legend_framealpha': 0.85,  # 图例边框透明度
    'legend_edgecolor': '#cccccc',  # 图例边框颜色
    'hide_top_spine': True,  # 是否隐藏上边框
    'hide_right_spine': True,  # 是否隐藏右边框
    'save_formats': ['png', 'eps'],  # 实际输出格式列表
    'save_dpi': 150,  # 位图输出 dpi
    'save_bbox_inches': 'tight',  # 保存时裁掉多余白边
    'tight_layout': True,  # 保存前是否执行 tight_layout
}
STYLE_HELPER = PlotStyleHelper(PLOT_GLOBAL_ADAPTER, FIGURES_DIR)

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
    # 只取文件名含 varyN 或 N 的
    varyN = [f for f in candidates if 'varyN' in os.path.basename(f) or
             os.path.basename(f).startswith('N')]
    pool = varyN if varyN else candidates
    if not pool:
        sys.exit(f"找不到 .mat 文件，请先运行 Batch_VaryN.m，或手动指定路径作为命令行参数。")
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
                # 只有一列
                yield ni, 0, row
    else:
        yield 0, 0, results


def get_shape(results):
    """返回 (nN, nS)。"""
    if isinstance(results, np.ndarray):
        return results.shape
    elif isinstance(results, list):
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
    N_values  = parse_N_values(config)
    alg_names = parse_alg_names(config)
    nN, nS    = get_shape(results)

    metrics = {
        a: {k: np.full((nN, nS), np.nan)
            for k in ('utility', 'completion', 'cost', 'time')}
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
            metrics[aname]['utility']   [ni, si] = to_scalar(ae.get('final_utility'))
            metrics[aname]['completion'][ni, si] = to_scalar(ae.get('final_completion'))
            metrics[aname]['cost']      [ni, si] = to_scalar(ae.get('final_cost'))
            metrics[aname]['time']      [ni, si] = to_scalar(ae.get('computation_time'))

    return N_values, alg_names, metrics


def extract_convergence(results, config, n_target=None):
    """
    提取收敛曲线（图2c）。
    n_target: 取哪个 N 值（None → 取最大 N）。
    返回: mean_curves {alg: [R,]}, num_rounds, n_target
    """
    N_values   = parse_N_values(config)
    alg_names  = parse_alg_names(config)
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
            mat = np.vstack(curves[aname])          # (nS, R)
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

def _style_ax(ax, xlabel, ylabel, title=None):
    STYLE_HELPER.apply_common_style(ax, xlabel=xlabel, ylabel=ylabel, title=title)


def finalize_and_save(fig, save_path):
    STYLE_HELPER.finalize_and_save(fig, save_path)


def build_output_stem(stem):
    return STYLE_HELPER.build_output_stem(stem)


def configure_output_dir(mat_path):
    global FIGURES_DIR
    source_name = infer_source_name(mat_path, fallback='varyN')
    FIGURES_DIR = build_results_figures_dir(ROOT_DIR, 'varyN', source_name)
    os.makedirs(FIGURES_DIR, exist_ok=True)
    STYLE_HELPER.set_figures_dir(FIGURES_DIR)
    return FIGURES_DIR


def plot_fig1a(N_values, alg_names, metrics, save_path):
    """图1a：变N效用（mean ± std 折线图）"""
    fig, ax = plt.subplots(figsize=cm_size_to_inch(FIGSIZE_CM))

    for aname in alg_names:
        st  = ALG_STYLE.get(aname, DEFAULT_STYLE)
        mu  = np.nanmean(metrics[aname]['utility'], axis=1)
        std = np.nanstd (metrics[aname]['utility'], axis=1)
        ax.errorbar(N_values, mu, yerr=std,
                    color=st['color'], marker=st['marker'], ls=st['ls'],
                    lw=LW, ms=MS, capsize=CAPS,
                    label=st['label'], zorder=3)

    ax.xaxis.set_major_locator(mticker.FixedLocator(N_values))
    _style_ax(ax, 'Number of Agents (N)', 'Final Coalition Utility',
              'Fig. 1a — Utility vs. N')
    finalize_and_save(fig, save_path)


def plot_fig1b(N_values, alg_names, metrics, save_path):
    """图1b：变N完成度（mean ± std 折线图）"""
    fig, ax = plt.subplots(figsize=cm_size_to_inch(FIGSIZE_CM))

    for aname in alg_names:
        st  = ALG_STYLE.get(aname, DEFAULT_STYLE)
        mu  = np.nanmean(metrics[aname]['completion'], axis=1)
        std = np.nanstd (metrics[aname]['completion'], axis=1)
        ax.errorbar(N_values, mu, yerr=std,
                    color=st['color'], marker=st['marker'], ls=st['ls'],
                    lw=LW, ms=MS, capsize=CAPS,
                    label=st['label'], zorder=3)

    ax.xaxis.set_major_locator(mticker.FixedLocator(N_values))
    ax.set_ylim(bottom=0)
    _style_ax(ax, 'Number of Agents (N)', 'Avg. Task Completion Degree',
              'Fig. 1b — Completion vs. N')
    finalize_and_save(fig, save_path)


def plot_fig2c(mean_curves, num_rounds, n_target, alg_names, save_path):
    """图2c：效用收敛曲线（对指定N均值化）"""
    fig, ax = plt.subplots(figsize=cm_size_to_inch(FIGSIZE_CM))
    rounds = np.arange(1, num_rounds + 1)

    for aname in alg_names:
        curve = mean_curves.get(aname)
        if curve is None or np.all(np.isnan(curve)):
            continue
        st = ALG_STYLE.get(aname, DEFAULT_STYLE)
        # 用前向填充处理 NaN（算法提前收敛的情形）
        mask = ~np.isnan(curve)
        if not np.any(mask):
            continue
        filled = curve.copy()
        idx = np.where(mask)[0]
        filled[idx[-1]+1:] = filled[idx[-1]]   # ffill 尾部 NaN
        ax.plot(rounds, filled,
                color=st['color'], ls=st['ls'],
                lw=LW, label=st['label'])

    _style_ax(ax, 'Round', 'Coalition Utility',
              f'Fig. 2c — Convergence (N={n_target})')
    finalize_and_save(fig, save_path)


def plot_fig3a(mean_curr, std_curr, mean_best, std_best, n_target, save_path):
    """图3a：OCF_SAtabu 内循环 current / best utility 轨迹"""
    if mean_curr is None and mean_best is None:
        print("  ! 内循环数据为空（OCF_SAtabu 未记录 inner_loop），跳过图3a")
        return

    fig, ax = plt.subplots(figsize=cm_size_to_inch(FIGSIZE_CM))
    ref = mean_curr if mean_curr is not None else mean_best
    iters = np.arange(1, len(ref) + 1)

    if mean_curr is not None:
        ax.plot(iters, mean_curr,
                color='#4878CF', ls='-', lw=LW, label='Current Utility')
        if std_curr is not None:
            ax.fill_between(iters,
                            mean_curr - std_curr,
                            mean_curr + std_curr,
                            alpha=0.15, color='#4878CF')

    if mean_best is not None:
        ax.plot(iters, mean_best,
                color='#D65F5F', ls='--', lw=LW, label='Best Utility')
        if std_best is not None:
            ax.fill_between(iters,
                            mean_best - std_best,
                            mean_best + std_best,
                            alpha=0.15, color='#D65F5F')

    r_label = 50   # INNER_LOOP_ROUND 默认值
    _style_ax(ax, 'Inner Iteration', 'Utility',
              f'Fig. 3a — Inner Loop (Round {r_label}, N={n_target})')
    finalize_and_save(fig, save_path)


# ══════════════════════════════════════════════════════════════════════════════
# 主程序
# ══════════════════════════════════════════════════════════════════════════════

def main():
    mat_path = find_mat_file(sys.argv)
    configure_output_dir(mat_path)

    print(f"\n加载数据...")
    raw = mat73.loadmat(mat_path)
    results = raw['scale_N_results']
    config  = raw['scale_config']

    N_values  = parse_N_values(config)
    alg_names = parse_alg_names(config)
    nN, nS    = get_shape(results)
    n_conv    = max(N_values)   # 收敛图和内循环图取最大 N

    print(f"  N_values  = {N_values}")
    print(f"  alg_names = {alg_names}")
    print(f"  形状      = {nN}×{nS} (N×seed)")

    # 从文件名提取时间戳（用于输出文件命名）
    basename = os.path.splitext(os.path.basename(mat_path))[0]
    # 取末尾形如 20260322_211050 的部分
    parts = basename.split('_')
    ts = '_'.join(parts[-2:]) if len(parts) >= 2 else 'ts'

    print(f"\n提取指标...")
    N_values, alg_names, metrics = extract_final_metrics(results, config)

    print(f"\n绘图 → {FIGURES_DIR}")

    # 图1a
    plot_fig1a(N_values, alg_names, metrics,
               build_output_stem('fig1a_utility'))

    # 图1b
    plot_fig1b(N_values, alg_names, metrics,
               build_output_stem('fig1b_completion'))

    # 图2c：收敛曲线（取最大 N）
    mean_curves, num_rounds, n_target = extract_convergence(
        results, config, n_target=n_conv)
    plot_fig2c(mean_curves, num_rounds, n_target, alg_names,
               build_output_stem('fig2c_convergence'))

    # 图3a：OCF_SAtabu 内循环（取最大 N）
    mc, sc, mb, sb, nt = extract_inner_loop(results, config, n_target=n_conv)
    plot_fig3a(mc, sc, mb, sb, nt,
               build_output_stem('fig3a_innerloop'))

    print(f"\n完成。图窗已弹出，关闭后程序退出。")
    plt.show()


if __name__ == '__main__':
    main()


