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
  python plot_varyM_top_config.py                         # 自动搜索最新运行目录
  python plot_varyM_top_config.py path/to/run_dir        # 指定新的 VaryM 运行目录
  python plot_varyM_top_config.py path/to/cache.pkl      # 指定聚合缓存
  python plot_varyM_top_config.py path/to/legacy.mat     # 指定旧版聚合 MAT

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
from plot_style_helper import PlotStyleHelper, build_results_figures_dir, cm_size_to_inch, infer_source_name
from varym_result_aggregator import VaryMResultAggregator


# ══════════════════════════════════════════════════════════════════════════════
# 顶部可调参数区（建议以后优先在这里改）
# ══════════════════════════════════════════════════════════════════════════════

# =========================
# 顶部可调绘图参数
# 建议优先在这里改尺寸、字体、图例和保存选项。
# =========================

# 路径配置
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))  # 当前脚本所在目录
ROOT_DIR = os.path.dirname(SCRIPT_DIR)  # 项目根目录
FIGURES_DIR = build_results_figures_dir(ROOT_DIR, 'varyM')  # 图片输出目录
SEARCH_DIRS = [
    os.path.join(ROOT_DIR, 'results', 'batch', 'varyM'),  # 优先搜索 varyM 实验结果目录
    os.path.join(ROOT_DIR, 'results', 'batch'),  # 兜底搜索通用 batch 目录
]

# 手动输入选择器
# - None: 自动选择 SEARCH_DIRS 下最新的运行目录或缓存
# - 名称: 按运行目录名匹配，例如 '20260329_190314_N8_M8-20_K6_S11'
# - 路径: 直接指定运行目录、缓存文件或旧版 MAT 文件
PREFERRED_INPUT = '20260329_190314_N8_M8-20_K6_S11'

# 算法显示样式：颜色 / marker / 线型 / 图例名
ALG_STYLE = {
    'Huo2025': dict(color='#4878CF', marker='o', ls='-', label='Huo2025'),
    'Qi2023': dict(color='#6ACC65', marker='s', ls='--', label='Qi2023'),
    'Shi2024': dict(color='#D65F5F', marker='^', ls='-.', label='Shi2024'),
    'OCF_SAtabu': dict(color='#B47CC7', marker='D', ls='-', label='Ours (OCF-SA)'),
}
DEFAULT_STYLE = dict(color='#888888', marker='x', ls=':', label='Unknown')  # 未知算法的兜底样式

# 全局绘图参数
PLOT_GLOBAL = {
    'figsize_cm': (13.97, 10.67),  # 单张图尺寸（宽, 高），单位 cm
    'linewidth': 1.8,  # 主曲线线宽
    'markersize': 4,  # marker 大小
    'markeredgewidth': 0.8,  # marker 边框线宽
    'capsize': 1,  # 误差棒帽宽
    'show_errorbar_varyM': False,  # fig1c/fig1d/fig1e 是否显示 mean±std 误差棒
    'show_markers_fig2d': False,  # fig2d 是否显示 marker
    'markevery_fig2d': None,  # fig2d 的 marker 抽样步长；None 表示全部点
    'show_fig2d_band': True,  # fig2d 是否显示阴影带
    'fig2d_band_alpha': 0.18,  # fig2d 阴影带透明度
    'font_family': ['Times New Roman', 'SimSun', 'DejaVu Sans'],  # 全局字体候选顺序
    'font_style': 'normal',  # 字体样式：normal / italic / oblique
    'font_weight': 'normal',  # 全局默认字重：normal / bold
    'xlabel_fontsize': 11,  # x 轴标题字号
    'ylabel_fontsize': 11,  # y 轴标题字号
    'label_fontweight': 'normal',  # 坐标轴标题字重
    'show_titles': False,  # 全局标题总开关；False 时所有子图都不显示标题
    'title_fontsize': 12,  # 标题字号
    'title_fontweight': 'bold',  # 标题字重
    'title_pad': 8,  # 标题与坐标轴之间的间距
    'tick_fontsize': 10,  # 刻度字号
    'tick_fontweight': 'normal',  # 刻度字重
    'legend_fontsize': 9,  # 图例字号
    'legend_fontweight': 'normal',  # 图例字重
    'legend_loc': 'best',  # 图例位置
    'legend_bbox_to_anchor': None,  # 图例锚点；None 表示不额外指定
    'legend_ncol': 1,  # 图例列数
    'legend_borderaxespad': 0.3,  # 图例与坐标轴边界的间距
    'legend_handlelength': 2.0,  # 图例示意线长度
    'legend_labelspacing': 0.4,  # 图例条目垂直间距
    'show_grid': True,  # 是否显示网格
    'grid_linestyle': '--',  # 网格线型
    'grid_linewidth': 0.6,  # 网格线宽
    'grid_alpha': 0.4,  # 网格透明度
    'show_legend': True,  # 全局图例总开关
    'legend_framealpha': 0.85,  # 图例边框透明度
    'legend_edgecolor': '#cccccc',  # 图例边框颜色
    'hide_top_spine': True,  # 是否隐藏上边框
    'hide_right_spine': True,  # 是否隐藏右边框
    'save_format': 'eps',  # 主保存格式
    'save_formats': ['png', 'eps'],  # 实际输出格式列表
    'save_dpi': 150,  # 位图输出 dpi
    'save_bbox_inches': 'tight',  # 保存时裁掉多余白边
    'timestamp_first_in_name': True,  # True 表示时间戳放在文件名前面
    'tight_layout': True,  # 保存前是否执行 tight_layout
}

# 各子图单独控制
# - show_title: 当前图是否允许标题，仍受 PLOT_GLOBAL['show_titles'] 总开关控制
# - xlim / ylim = None: 自动范围
# - xticks / yticks = None: 自动刻度
# - use_fixed_M_xticks = True: 强制使用 M_values 作为 x 轴刻度
# - bottom_zero = True: y 轴下界至少为 0
FIGURE_CONFIG = {
    'fig1c': {
        'show_title': True,
        'title': 'Fig. 1c - Utility vs. M',
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
        'title': 'Fig. 1d - Completion vs. M',
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
        'title': 'Fig. 1e - Total Completed Value vs. M',
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
        'title_template': 'Fig. 2d - Convergence (M={m_target})',
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
STYLE_HELPER = PlotStyleHelper(PLOT_GLOBAL, FIGURES_DIR)

# ══════════════════════════════════════════════════════════════════════════════
# 工具函数
# ══════════════════════════════════════════════════════════════════════════════


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


def get_timestamp_tag(config, run_meta):
    timestamp = config.get('timestamp')
    if timestamp is not None:
        arr = np.asarray(timestamp).ravel()
        if arr.size > 0:
            return str(arr[0])

    run_name = str(run_meta.get('run_name', ''))
    parts = run_name.split('_')
    if len(parts) >= 2 and parts[0].isdigit() and parts[1].isdigit():
        return f'{parts[0]}_{parts[1]}'

    source_path = str(run_meta.get('source_path', ''))
    basename = os.path.splitext(os.path.basename(source_path))[0]
    parts = basename.split('_')
    if len(parts) >= 2 and parts[-2].isdigit() and parts[-1].isdigit():
        return '_'.join(parts[-2:])
    return 'ts'


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
    _ = ts
    return STYLE_HELPER.build_output_stem(stem)


def apply_common_style(ax, cfg, title=None):
    """统一处理坐标轴标签、标题、网格、图例和边框。"""
    STYLE_HELPER.apply_common_style(ax, cfg=cfg, title=title)


def apply_axis_controls(ax, cfg, m_values=None):
    """统一处理 xlim / ylim / xticks / yticks / 底部从 0 开始等。"""
    STYLE_HELPER.apply_axis_controls(
        ax,
        cfg=cfg,
        fixed_values=m_values,
        fixed_locator_key='use_fixed_M_xticks',
    )


def finalize_and_save(fig, save_path):
    STYLE_HELPER.finalize_and_save(fig, save_path)


def configure_output_dir(source_name):
    global FIGURES_DIR
    FIGURES_DIR = build_results_figures_dir(ROOT_DIR, 'varyM', source_name)
    os.makedirs(FIGURES_DIR, exist_ok=True)
    STYLE_HELPER.set_figures_dir(FIGURES_DIR)
    return FIGURES_DIR


def resolve_input_selector(input_selector, search_dirs=None):
    """
    Resolve a preferred input selector into an existing path when possible.

    Supported forms:
      - None / ''                     -> use latest available input
      - run folder name               -> search under SEARCH_DIRS
      - absolute or relative file/dir -> use directly if it exists
    """
    if input_selector is None:
        return None

    selector = str(input_selector).strip()
    if not selector:
        return None

    candidate_paths = [
        os.path.abspath(selector),
        os.path.abspath(os.path.join(ROOT_DIR, selector)),
    ]
    for candidate in candidate_paths:
        if os.path.exists(candidate):
            return candidate

    matches = []
    for search_dir in (search_dirs or []):
        if not os.path.isdir(search_dir):
            continue

        direct_match = os.path.join(search_dir, selector)
        if os.path.exists(direct_match):
            matches.append(os.path.abspath(direct_match))

        pattern = os.path.join(search_dir, '**', selector)
        for matched_path in glob.glob(pattern, recursive=True):
            if os.path.basename(os.path.normpath(matched_path)) == selector:
                matches.append(os.path.abspath(matched_path))

    matches = sorted(set(matches))
    if len(matches) == 1:
        return matches[0]
    if len(matches) > 1:
        match_text = '\n  - '.join(matches)
        raise FileNotFoundError(
            f"Multiple VaryM inputs match '{selector}'. Please use a full path:\n  - {match_text}"
        )

    raise FileNotFoundError(
        f"Cannot find VaryM input '{selector}'. "
        f"Set PREFERRED_INPUT to a run name under SEARCH_DIRS or to a full path."
    )


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
    fig, ax = plt.subplots(figsize=cm_size_to_inch(PLOT_GLOBAL['figsize_cm']))

    for aname in alg_names:
        st  = ALG_STYLE.get(aname, DEFAULT_STYLE)
        mu  = np.nanmean(metrics[aname][metric_key], axis=1)
        std = np.nanstd(metrics[aname][metric_key], axis=1)

        if PLOT_GLOBAL.get('show_errorbar_varyM', False):
            ax.errorbar(
                M_values, mu, yerr=std,
                color=st['color'], marker=st['marker'], ls=st['ls'],
                lw=PLOT_GLOBAL['linewidth'], ms=PLOT_GLOBAL['markersize'],
                mew=PLOT_GLOBAL['markeredgewidth'],
                capsize=PLOT_GLOBAL['capsize'],
                label=st['label'], zorder=3,
            )
        else:
            ax.plot(
                M_values, mu,
                color=st['color'], marker=st['marker'], ls=st['ls'],
                lw=PLOT_GLOBAL['linewidth'], ms=PLOT_GLOBAL['markersize'],
                mew=PLOT_GLOBAL['markeredgewidth'],
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
    fig, ax = plt.subplots(figsize=cm_size_to_inch(PLOT_GLOBAL['figsize_cm']))
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

        marker_kwargs = get_marker_kwargs(
            PLOT_GLOBAL['show_markers_fig2d'],
            st['marker'],
            PLOT_GLOBAL['markevery_fig2d'],
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

# ══════════════════════════════════════════════════════════════════════════════
# 主程序
# ══════════════════════════════════════════════════════════════════════════════

def main(input_path=None):
    apply_plot_rcparams()
    if input_path is None and len(sys.argv) > 1:
        input_path = sys.argv[1]
    if input_path is None:
        input_path = PREFERRED_INPUT
    input_path = resolve_input_selector(input_path, SEARCH_DIRS)
    aggregator = VaryMResultAggregator(search_dirs=SEARCH_DIRS)

    print("\n加载数据...")
    results, config, run_meta = aggregator.load_results(input_path=input_path)
    output_source = run_meta.get('run_name') or infer_source_name(run_meta.get('source_path'), fallback='varyM')
    configure_output_dir(output_source)

    print(f"  数据来源  = {run_meta.get('source_path', '')}")
    if run_meta.get('source_type') == 'run_dir':
        cache_state = '命中缓存' if run_meta.get('used_cache') else '重建缓存'
        print(f"  聚合方式  = 延迟聚合（{cache_state}）")
        print(f"  缓存文件  = {run_meta.get('cache_path', '')}")
    else:
        print(f"  聚合方式  = 直接读取 {run_meta.get('source_type')}")

    M_values  = parse_M_values(config)
    alg_names = parse_alg_names(config)
    nM, nS    = get_shape(results)
    fixed_N   = int(to_scalar(config.get('N', 0)))
    m_conv    = max(M_values)

    print(f"  固定 N    = {fixed_N}")
    print(f"  M_values  = {M_values}")
    print(f"  alg_names = {alg_names}")
    print(f"  形状      = {nM}×{nS} (M×seed)")

    print("\n提取指标...")
    M_values, alg_names, metrics = extract_final_metrics(results, config)

    print(f"\n绘图 → {FIGURES_DIR}")

    plot_fig1c(
        M_values, alg_names, metrics,
        build_output_path(None, 'fig1c_utility'),
    )

    plot_fig1d(
        M_values, alg_names, metrics,
        build_output_path(None, 'fig1d_completion'),
    )

    plot_fig1e(
        M_values, alg_names, metrics,
        build_output_path(None, 'fig1e_completed_value'),
    )

    mean_curves, std_curves, num_rounds, m_target = extract_convergence(
        results, config, m_target=m_conv,
    )
    plot_fig2d(
        mean_curves, std_curves, num_rounds, m_target, alg_names,
        build_output_path(None, 'fig2d_convergence'),
    )
    print("\n完成。图窗已弹出，关闭后程序退出。")
    plt.show()


if __name__ == '__main__':
    main()



