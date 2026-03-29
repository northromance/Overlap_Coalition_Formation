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
import re
import numpy as np
import matplotlib.pyplot as plt
from datetime import datetime
from plot_style_helper import PlotStyleHelper

try:
    import mat73
except ImportError:
    sys.exit("缺少依赖，请先执行: pip install mat73")


# ══════════════════════════════════════════════════════════════════════════════
# 顶部可调参数区（建议以后优先在这里改）
# ══════════════════════════════════════════════════════════════════════════════

# ── 路径配置 ──────────────────────────────────────────────────────────────────
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))  # 当前脚本所在目录
ROOT_DIR = os.path.dirname(SCRIPT_DIR)  # 项目根目录
FIGURES_DIR = os.path.join(ROOT_DIR, 'figures', 'paper')  # 图片输出目录
SEARCH_DIRS = [
    os.path.join(ROOT_DIR, 'results', 'batch', 'varyN'),  # 优先搜索 varyN 实验结果目录
    os.path.join(ROOT_DIR, 'results', 'batch'),  # 若上面没找到，则回退到通用 batch 目录
]

# ── 算法显示样式（四个算法的颜色 / 点型 / 线型 / 图例名）────────────────────────
ALG_STYLE = {
    'Huo2025':    dict(color='#4878CF', marker='o', ls='-',  label='Huo2025'),  # Huo2025 的颜色/点型/线型/图例名
    'Qi2023':     dict(color='#6ACC65', marker='s', ls='--', label='Qi2023'),  # Qi2023 的颜色/点型/线型/图例名
    'Shi2024':    dict(color='#D65F5F', marker='^', ls='-.', label='Shi2024'),  # Shi2024 的颜色/点型/线型/图例名
    'OCF_SAtabu': dict(color='#B47CC7', marker='D', ls='-',  label='Ours (OCF-SA)'),  # OCF_SAtabu 的颜色/点型/线型/图例名
}
DEFAULT_STYLE = dict(color='#888888', marker='x', ls=':', label='Unknown')  # 未知算法时的兜底样式

# ── 全局绘图参数 ──────────────────────────────────────────────────────────────
PLOT_GLOBAL = {
    'figsize': (5.5, 4.2),  # 图像尺寸 (宽, 高)，单位英寸

    'linewidth': 1.8,  # 折线线宽
    'markersize': 4,  # 数据点大小；改这里即可统一放大/缩小点
    'markeredgewidth': 0.8,  # 数据点边框宽度
    'capsize': 1,  # 误差棒帽子的宽度
    'show_errorbar_varyN': False,  # fig1a/1b/1c 是否显示均值±std 误差棒
    'show_markers_fig2c': False,  # fig2c 是否在收敛曲线上显示数据点
    'show_markers_fig3a': False,  # fig3a 是否在 inner-loop 曲线上显示数据点
    'markevery_fig2c': None,  # fig2c 每隔多少个点显示一个 marker；None 表示全部
    'markevery_fig3a': None,  # fig3a 每隔多少个点显示一个 marker；None 表示全部

    'font_family': ['Times New Roman', 'SimSun', 'DejaVu Sans'],  # 全局字体族；可改成 ['Arial']、['SimHei'] 等
    'font_style': 'normal',  # 字体样式：normal / italic / oblique
    'font_weight': 'normal',  # 全局默认字重：normal / bold
    'xlabel_fontsize': 11,  # x 轴标题字号
    'ylabel_fontsize': 11,  # y 轴标题字号
    'label_fontweight': 'normal',  # 坐标轴标题字重
    'show_titles': False,  # 全局标题总开关；False 时所有图都不显示标题
    'title_fontsize': 12,  # 图标题字号
    'title_fontweight': 'bold',  # 图标题字重
    'title_pad': 8,  # 图标题与绘图区的间距
    'tick_fontsize': 10,  # 刻度字号
    'tick_fontweight': 'normal',  # 刻度字重
    'legend_fontsize': 9,  # 图例字号
    'legend_fontweight': 'normal',  # 图例字重
    'legend_loc': 'best',  # 图例位置，例如 'best' / 'upper right' / 'lower left'
    'legend_bbox_to_anchor': None,  # 图例锚点，例如 (1.02, 1.0)；None 表示不用锚点
    'legend_ncol': 1,  # 图例列数
    'legend_borderaxespad': 0.3,  # 图例与坐标轴边缘的间距
    'legend_handlelength': 2.0,  # 图例中示意线段的长度
    'legend_labelspacing': 0.4,  # 图例条目之间的垂直间距

    'show_grid': True,  # 是否显示网格
    'grid_linestyle': '--',  # 网格线型
    'grid_linewidth': 0.6,  # 网格线宽
    'grid_alpha': 0.4,  # 网格透明度
    'show_legend': True,  # 是否显示图例
    'legend_framealpha': 0.85,  # 图例边框透明度
    'legend_edgecolor': '#cccccc',  # 图例边框颜色
    'hide_top_spine': True,  # 是否隐藏上边框
    'hide_right_spine': True,  # 是否隐藏右边框

    'save_format': 'eps',  # 保存格式，例如 'eps' / 'png' / 'pdf' / 'svg'
    'save_dpi': 150,  # 保存图片的 dpi
    'save_bbox_inches': 'tight',  # 保存时是否紧凑裁边
    'timestamp_first_in_name': True,  # 文件名是否把时间戳放前面，便于按名称排序

    'tight_layout': True,  # 保存前是否自动紧凑排版
}

# ── 图3a 专用样式（原来写死在函数里，现在提到顶部）────────────────────────────
INNER_LOOP_STYLE = {
    'current_label': 'Current Utility',  # fig3a 中当前效用曲线的图例文字
    'current_color': '#4878CF',  # fig3a 中当前效用曲线颜色
    'current_ls': '-',  # fig3a 中当前效用曲线线型
    'current_marker': 'o',  # fig3a 中当前效用曲线点型；仅在 show_markers_fig3a=True 时生效
    'current_band_alpha': 0.15,  # fig3a 中当前效用阴影带透明度

    'best_label': 'Best Utility',  # fig3a 中最优效用曲线的图例文字
    'best_color': '#D65F5F',  # fig3a 中最优效用曲线颜色
    'best_ls': '--',  # fig3a 中最优效用曲线线型
    'best_marker': 's',  # fig3a 中最优效用曲线点型；仅在 show_markers_fig3a=True 时生效
    'best_band_alpha': 0.15,  # fig3a 中最优效用阴影带透明度

    'round_label': 50,  # 仅用于标题显示的 round 标签，不影响实际数据提取
}

# ── 每个图单独控制（坐标轴 / 刻度 / 标题 / 范围）──────────────────────────────
# 说明：
#   xlim / ylim = None 表示自动
#   xticks / yticks = None 表示自动
#   use_fixed_N_xticks = True 表示 x 轴刻度强制使用 N_values
#   bottom_zero = True 常用于完成度图让 y 轴从 0 开始
FIGURE_CONFIG = {
    'fig1a': {
        'show_title': True,  # 是否显示标题；仅在全局 show_titles=True 时生效
        'title': 'Fig. 1a — Utility vs. N',  # 固定标题内容
        'xlabel': 'Number of Agents (N)',  # x 轴名称
        'ylabel': 'Final Coalition Utility',  # y 轴名称
        'xlim': None,  # x 轴范围，例如 (10, 100)
        'ylim': None,  # y 轴范围，例如 (0, 150)
        'xticks': None,  # 手动指定 x 轴刻度，例如 [10, 20, 30]
        'yticks': None,  # 手动指定 y 轴刻度，例如 [0, 50, 100]
        'use_fixed_N_xticks': True,  # 是否强制用 N_values 作为 x 轴刻度
        'bottom_zero': False,  # 是否强制让 y 轴从 0 开始
    },
    'fig1b': {
        'show_title': True,  # 是否显示标题；仅在全局 show_titles=True 时生效
        'title': 'Fig. 1b — Completion vs. N',  # 固定标题内容
        'xlabel': 'Number of Agents (N)',  # x 轴名称
        'ylabel': 'Avg. Task Completion Degree',  # y 轴名称
        'xlim': None,  # x 轴范围
        'ylim': None,  # y 轴范围
        'xticks': None,  # 手动指定 x 轴刻度
        'yticks': None,  # 手动指定 y 轴刻度
        'use_fixed_N_xticks': True,  # 是否强制用 N_values 作为 x 轴刻度
        'bottom_zero': True,  # 是否强制让 y 轴从 0 开始
    },
    'fig1c': {
        'show_title': True,  # 是否显示标题；仅在全局 show_titles=True 时生效
        'title': 'Fig. 1c - Total Completed Value vs. N',  # 固定标题内容
        'xlabel': 'Number of Agents (N)',  # x 轴名称
        'ylabel': 'Total Completed Value',  # y 轴名称
        'xlim': None,  # x 轴范围
        'ylim': None,  # y 轴范围
        'xticks': None,  # 手动指定 x 轴刻度
        'yticks': None,  # 手动指定 y 轴刻度
        'use_fixed_N_xticks': True,  # 是否强制用 N_values 作为 x 轴刻度
        'bottom_zero': True,  # 是否强制让 y 轴从 0 开始
    },
    'fig2c': {
        'show_title': True,  # 是否显示标题；仅在全局 show_titles=True 时生效
        'title_template': 'Fig. 2c — Convergence (N={n_target})',  # 动态标题模板
        'xlabel': 'Round',  # x 轴名称
        'ylabel': 'Coalition Utility',  # y 轴名称
        'xlim': None,  # x 轴范围
        'ylim': None,  # y 轴范围
        'xticks': None,  # 手动指定 x 轴刻度
        'yticks': None,  # 手动指定 y 轴刻度
        'use_fixed_N_xticks': False,  # 是否强制用 N_values 作为 x 轴刻度
        'bottom_zero': False,  # 是否强制让 y 轴从 0 开始
    },
    'fig3a': {
        'show_title': True,  # 是否显示标题；仅在全局 show_titles=True 时生效
        'title_template': 'Fig. 3a — Inner Loop (Round {round_label}, N={n_target})',  # 动态标题模板
        'xlabel': 'Inner Iteration',  # x 轴名称
        'ylabel': 'Utility',  # y 轴名称
        'xlim': None,  # x 轴范围
        'ylim': None,  # y 轴范围
        'xticks': None,  # 手动指定 x 轴刻度
        'yticks': None,  # 手动指定 y 轴刻度
        'use_fixed_N_xticks': False,  # 是否强制用 N_values 作为 x 轴刻度
        'bottom_zero': False,  # 是否强制让 y 轴从 0 开始
    },
}

os.makedirs(FIGURES_DIR, exist_ok=True)
STYLE_HELPER = PlotStyleHelper(PLOT_GLOBAL, FIGURES_DIR)


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


def get_text_style(size_key, weight_key):
    """返回一组可复用的字体配置。"""
    return STYLE_HELPER.get_text_style(size_key, weight_key)


def apply_plot_rcparams():
    """设置 matplotlib 的全局字体默认值。"""
    STYLE_HELPER.apply_rcparams()


def get_marker_kwargs(show_markers, marker, markevery=None):
    """根据配置生成 marker 参数。"""
    return STYLE_HELPER.get_marker_kwargs(show_markers, marker, markevery)


def build_output_path(ts, stem):
    """按配置生成输出文件路径。"""
    return STYLE_HELPER.build_output_path(ts, stem)


def extract_timestamp_tag(mat_path):
    """从结果文件名中提取时间戳；提取失败时回退到当前时间。"""
    basename = os.path.splitext(os.path.basename(mat_path))[0]
    match = re.search(r'(\d{8})_(\d{6})$', basename)
    if match:
        return f'{match.group(1)}_{match.group(2)}'
    return datetime.now().strftime('%Y%m%d_%H%M%S')


def apply_common_style(ax, cfg, title=None):
    """统一处理坐标轴标签、标题、网格、图例和边框。"""
    STYLE_HELPER.apply_common_style(ax, cfg=cfg, title=title)


def apply_axis_controls(ax, cfg, n_values=None):
    """统一处理 xlim / ylim / xticks / yticks / 底部从 0 开始等。"""
    STYLE_HELPER.apply_axis_controls(
        ax,
        cfg=cfg,
        fixed_values=n_values,
        fixed_locator_key='use_fixed_N_xticks',
    )


def finalize_and_save(fig, save_path):
    STYLE_HELPER.finalize_and_save(fig, save_path)


# ══════════════════════════════════════════════════════════════════════════════
# 数据提取
# ══════════════════════════════════════════════════════════════════════════════

def extract_final_metrics(results, config):
    """
    返回:
      N_values  : list[int]
      alg_names : list[str]
      metrics   : {alg: {'utility': (nN, nS), 'completion': (nN, nS),
                          'completed_value': (nN, nS), 'cost': (nN, nS), 'time': (nN, nS)}}
    """
    N_values = parse_N_values(config)
    alg_names = parse_alg_names(config)
    nN, nS = get_shape(results)

    metrics = {
        a: {k: np.full((nN, nS), np.nan) for k in ('utility', 'completion', 'completed_value', 'cost', 'time')}
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
            utility = to_scalar(ae.get('final_utility'))
            completion = to_scalar(ae.get('final_completion'))
            cost = to_scalar(ae.get('final_cost'))
            completed_value = to_scalar(ae.get('final_completed_value'))
            if np.isnan(completed_value) and not np.isnan(utility) and not np.isnan(cost):
                completed_value = utility + cost

            metrics[aname]['utility'][ni, si] = utility
            metrics[aname]['completion'][ni, si] = completion
            metrics[aname]['completed_value'][ni, si] = completed_value
            metrics[aname]['cost'][ni, si] = cost
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

        if PLOT_GLOBAL.get('show_errorbar_varyN', True):
            ax.errorbar(
                N_values, mu, yerr=std,
                color=st['color'], marker=st['marker'], ls=st['ls'],
                lw=PLOT_GLOBAL['linewidth'], ms=PLOT_GLOBAL['markersize'],
                mew=PLOT_GLOBAL['markeredgewidth'],
                capsize=PLOT_GLOBAL['capsize'],
                label=st['label'], zorder=3,
            )
        else:
            ax.plot(
                N_values, mu,
                color=st['color'], marker=st['marker'], ls=st['ls'],
                lw=PLOT_GLOBAL['linewidth'], ms=PLOT_GLOBAL['markersize'],
                mew=PLOT_GLOBAL['markeredgewidth'],
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

        if PLOT_GLOBAL.get('show_errorbar_varyN', True):
            ax.errorbar(
                N_values, mu, yerr=std,
                color=st['color'], marker=st['marker'], ls=st['ls'],
                lw=PLOT_GLOBAL['linewidth'], ms=PLOT_GLOBAL['markersize'],
                mew=PLOT_GLOBAL['markeredgewidth'],
                capsize=PLOT_GLOBAL['capsize'],
                label=st['label'], zorder=3,
            )
        else:
            ax.plot(
                N_values, mu,
                color=st['color'], marker=st['marker'], ls=st['ls'],
                lw=PLOT_GLOBAL['linewidth'], ms=PLOT_GLOBAL['markersize'],
                mew=PLOT_GLOBAL['markeredgewidth'],
                label=st['label'], zorder=3,
            )

    apply_axis_controls(ax, cfg, n_values=N_values)
    apply_common_style(ax, cfg, title=cfg.get('title'))
    finalize_and_save(fig, save_path)

def plot_fig1c(N_values, alg_names, metrics, save_path):
    """Plot total completed value vs N."""
    cfg = merge_figure_config('fig1c')
    fig, ax = plt.subplots(figsize=PLOT_GLOBAL['figsize'])

    for aname in alg_names:
        st = ALG_STYLE.get(aname, DEFAULT_STYLE)
        mu = np.nanmean(metrics[aname]['completed_value'], axis=1)
        std = np.nanstd(metrics[aname]['completed_value'], axis=1)

        if PLOT_GLOBAL.get('show_errorbar_varyN', True):
            ax.errorbar(
                N_values, mu, yerr=std,
                color=st['color'], marker=st['marker'], ls=st['ls'],
                lw=PLOT_GLOBAL['linewidth'], ms=PLOT_GLOBAL['markersize'],
                mew=PLOT_GLOBAL['markeredgewidth'],
                capsize=PLOT_GLOBAL['capsize'],
                label=st['label'], zorder=3,
            )
        else:
            ax.plot(
                N_values, mu,
                color=st['color'], marker=st['marker'], ls=st['ls'],
                lw=PLOT_GLOBAL['linewidth'], ms=PLOT_GLOBAL['markersize'],
                mew=PLOT_GLOBAL['markeredgewidth'],
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
        marker_kwargs = get_marker_kwargs(
            PLOT_GLOBAL['show_markers_fig2c'],
            st['marker'],
            PLOT_GLOBAL['markevery_fig2c'],
        )
        ax.plot(
            rounds, filled,
            color=st['color'], ls=st['ls'],
            lw=PLOT_GLOBAL['linewidth'], label=st['label'],
            **marker_kwargs,
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
        marker_kwargs = get_marker_kwargs(
            PLOT_GLOBAL['show_markers_fig3a'],
            INNER_LOOP_STYLE['current_marker'],
            PLOT_GLOBAL['markevery_fig3a'],
        )
        ax.plot(
            iters, mean_curr,
            color=INNER_LOOP_STYLE['current_color'],
            ls=INNER_LOOP_STYLE['current_ls'],
            lw=PLOT_GLOBAL['linewidth'],
            label=INNER_LOOP_STYLE['current_label'],
            **marker_kwargs,
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
        marker_kwargs = get_marker_kwargs(
            PLOT_GLOBAL['show_markers_fig3a'],
            INNER_LOOP_STYLE['best_marker'],
            PLOT_GLOBAL['markevery_fig3a'],
        )
        ax.plot(
            iters, mean_best,
            color=INNER_LOOP_STYLE['best_color'],
            ls=INNER_LOOP_STYLE['best_ls'],
            lw=PLOT_GLOBAL['linewidth'],
            label=INNER_LOOP_STYLE['best_label'],
            **marker_kwargs,
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
    apply_plot_rcparams()
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

    ts = extract_timestamp_tag(mat_path)

    print("\n提取指标...")
    N_values, alg_names, metrics = extract_final_metrics(results, config)

    print(f"\n绘图 → {FIGURES_DIR}")

    plot_fig1a(
        N_values, alg_names, metrics,
        build_output_path(ts, 'fig1a_utility_varyN'),
    )

    plot_fig1b(
        N_values, alg_names, metrics,
        build_output_path(ts, 'fig1b_completion_varyN'),
    )

    plot_fig1c(
        N_values, alg_names, metrics,
        build_output_path(ts, 'fig1c_completed_value_varyN'),
    )

    mean_curves, num_rounds, n_target = extract_convergence(
        results, config, n_target=n_conv,
    )
    plot_fig2c(
        mean_curves, num_rounds, n_target, alg_names,
        build_output_path(ts, f'fig2c_convergence_N{n_target}'),
    )

    mc, sc, mb, sb, nt = extract_inner_loop(results, config, n_target=n_conv)
    plot_fig3a(
        mc, sc, mb, sb, nt,
        build_output_path(ts, f'fig3a_innerloop_N{nt}'),
    )

    print("\n完成。图窗已弹出，关闭后程序退出。")
    plt.show()


if __name__ == '__main__':
    main()
