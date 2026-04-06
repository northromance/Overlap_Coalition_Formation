"""
plot_varyM_top_config.py
========================
从 Batch_VaryM.m 生成的 .mat / 聚合缓存绘制论文图：
  图1c  变M效用       (mean ± std 折线图，4算法)
  图1d  变M完成度     (mean ± std 折线图，4算法)
  图1e  变M完成总价值 (mean ± std 折线图，4算法)
  图1f  变M效用柱状图 (mean ± std 分组柱状图，4算法)
  图1g  变M总价值柱状图 (mean ± std 分组柱状图，4算法)
  图2d  效用收敛曲线  (对最大M，按种子平均)

并额外导出一个精简 JSON：
  varyM_plot_data_compact.json

依赖:
  pip install mat73 numpy matplotlib scipy

用法:
  python plot_varyM_top_config.py                         # 自动搜索最新运行目录
  python plot_varyM_top_config.py path/to/run_dir        # 指定新的 VaryM 运行目录
  python plot_varyM_top_config.py path/to/cache.pkl      # 指定聚合缓存
  python plot_varyM_top_config.py path/to/legacy.mat     # 指定旧版聚合 MAT

说明:
  你可以直接在本文件最上方的“顶部可调参数区”中修改：
  - 图尺寸、线宽、字体、图例字号、输出 dpi
  - 每个图的标题、坐标轴名称、坐标范围、刻度
  - 是否显示网格、图例、标题
  - 固定导出边距和误差棒开关
"""

import os
import sys
import glob
import json
import numpy as np
import matplotlib.pyplot as plt
from plot_unified_config import (
    get_family_plot_config,
    get_family_figure_config,
    build_prefixed_stem,
    get_alg_display_name,
    get_alg_display_names,
    get_alg_plot_style as resolve_alg_plot_style,
    get_bar_layout as resolve_bar_layout,
    get_bar_plot_style as resolve_bar_plot_style,
    compute_error_values as compute_shared_error_values,
)
from plot_style_helper import (
    PlotStyleHelper,
    build_results_figures_dir,
    cm_size_to_inch,
    infer_source_name,
)
from varym_result_aggregator import VaryMResultAggregator


# ══════════════════════════════════════════════════════════════════════════════
# 顶部可调参数区（建议以后优先在这里改）
# ══════════════════════════════════════════════════════════════════════════════

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

# 算法显示样式主配置
# 这里是本文件最核心的“调色板”：
# - fig1c / fig1d / fig1e 的折线样式直接读这里
# - fig2d 的收敛曲线样式也直接读这里
#
# 字段说明：
# - color: 主颜色。
# - marker: 点的形状，如 'o' 圆点、's' 方块、'^' 三角、'D' 菱形。
# - ls: 线型，如 '-' 实线、'--' 虚线、'-.' 点划线。
# - lw: 该算法自己的线宽；若设置了，会优先于 PLOT_GLOBAL['linewidth']。
# - ms: 该算法自己的 marker 大小；若设置了，会优先于 PLOT_GLOBAL['markersize']。
# - mfc: marker face color，点内部填充色；写成 'none' 就是空心。
# - mec: marker edge color，点边框颜色。
# - mew: marker edge width，点边框线宽。
# - label: 图例显示名称。

FAMILY = 'varyM'
PLOT_CONFIG = get_family_plot_config(FAMILY)
ALG_STYLE = PLOT_CONFIG['ALG_STYLE']
DEFAULT_STYLE = PLOT_CONFIG['DEFAULT_STYLE']
PLOT_GLOBAL = PLOT_CONFIG['PLOT_GLOBAL']
BAR_CHART_STYLE = PLOT_CONFIG['BAR_CHART_STYLE']
FIGURE_CONFIG = PLOT_CONFIG['FIGURE_CONFIG']
OUTPUT_PREFIX = PLOT_CONFIG['OUTPUT_PREFIX']

os.makedirs(FIGURES_DIR, exist_ok=True)
STYLE_HELPER = PlotStyleHelper(PLOT_GLOBAL, FIGURES_DIR)


# ══════════════════════════════════════════════════════════════════════════════
# 工具函数
# ══════════════════════════════════════════════════════════════════════════════

def to_scalar(val):
    """将聚合器返回的各种标量形式统一成 Python float。"""
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
    cell array 可能是 list-of-list 或 numpy object array。
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
    """从 config 中提取 M 取值列表。"""
    return list(np.asarray(config['M_values'], dtype=int).ravel())


def merge_figure_config(fig_key, **kwargs):
    """Resolve one final figure config from unified config."""
    return get_family_figure_config(FAMILY, fig_key, **kwargs)


def get_text_style(size_key, weight_key):
    """返回一组可复用的字体配置。"""
    return STYLE_HELPER.get_text_style(size_key, weight_key)


def apply_plot_rcparams():
    """设置 matplotlib 的全局字体默认值。"""
    STYLE_HELPER.apply_rcparams()


def legacy_build_output_path_unused(ts, stem):
    """按配置生成输出文件路径。"""
    _ = ts
    return STYLE_HELPER.build_output_stem(build_prefixed_stem(FAMILY, stem))


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
    """按固定 cm 边距统一导出，保证所有图外框尺寸一致。"""
    if PLOT_GLOBAL.get('use_fixed_export_margins', False):
        fig_width_cm = fig.get_figwidth() * 2.54
        fig_height_cm = fig.get_figheight() * 2.54

        left_margin_cm = float(PLOT_GLOBAL.get('export_margin_left_cm', 1.62))
        right_margin_cm = float(PLOT_GLOBAL.get('export_margin_right_cm', 0.98))
        bottom_margin_cm = float(PLOT_GLOBAL.get('export_margin_bottom_cm', 1.02))
        top_margin_cm = float(PLOT_GLOBAL.get('export_margin_top_cm', 0.30))

        if left_margin_cm + right_margin_cm >= fig_width_cm:
            raise ValueError(
                f"固定导出边距非法: 左右边距之和 {left_margin_cm + right_margin_cm:.3f} cm "
                f"必须小于图宽 {fig_width_cm:.3f} cm"
            )
        if bottom_margin_cm + top_margin_cm >= fig_height_cm:
            raise ValueError(
                f"固定导出边距非法: 上下边距之和 {bottom_margin_cm + top_margin_cm:.3f} cm "
                f"必须小于图高 {fig_height_cm:.3f} cm"
            )

        left = left_margin_cm / fig_width_cm
        right = 1.0 - right_margin_cm / fig_width_cm
        bottom = bottom_margin_cm / fig_height_cm
        top = 1.0 - top_margin_cm / fig_height_cm

        fig.subplots_adjust(
            left=left,
            right=right,
            bottom=bottom,
            top=top,
        )

    STYLE_HELPER.finalize_and_save(fig, save_path)


def configure_output_dir(source_name):
    """切换输出目录到当前输入结果对应的 varyM 子目录。"""
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


def json_safe_data(obj):
    """递归将 numpy / NaN 转成可安全写入 JSON 的 Python 对象。"""
    if isinstance(obj, dict):
        return {str(k): json_safe_data(v) for k, v in obj.items()}
    if isinstance(obj, (list, tuple)):
        return [json_safe_data(v) for v in obj]
    if isinstance(obj, np.ndarray):
        return [json_safe_data(v) for v in obj.tolist()]
    if isinstance(obj, np.bool_):
        return bool(obj)
    if isinstance(obj, np.integer):
        return int(obj)
    if isinstance(obj, np.floating):
        val = float(obj)
        return None if (np.isnan(val) or np.isinf(val)) else val
    if isinstance(obj, float):
        return None if (np.isnan(obj) or np.isinf(obj)) else obj
    return obj


def write_plot_data_json(output_path, payload):
    """将精简绘图数据导出为 JSON。"""
    with open(output_path, 'w', encoding='utf-8') as fp:
        json.dump(json_safe_data(payload), fp, ensure_ascii=False, indent=2)
    print(f"  [OK] {output_path}")


def legacy_get_alg_plot_style_unused(aname):
    """读取算法折线样式，并支持 mfc/mec/lw/ms/mew。"""
    base = ALG_STYLE.get(aname, DEFAULT_STYLE)
    color = base.get('color', DEFAULT_STYLE['color'])
    return {
        'color': color,
        'marker': base.get('marker', DEFAULT_STYLE['marker']),
        'ls': base.get('ls', DEFAULT_STYLE['ls']),
        'linewidth': base.get('lw', PLOT_GLOBAL['linewidth']),
        'markersize': base.get('ms', PLOT_GLOBAL['markersize']),
        'markerfacecolor': base.get('mfc', color),
        'markeredgecolor': base.get('mec', color),
        'markeredgewidth': base.get('mew', PLOT_GLOBAL['markeredgewidth']),
        'label': base.get('label', aname),
    }


def get_plot_marker_kwargs(style, show_markers, markevery=None):
    """根据算法样式和开关生成 marker 参数。"""
    if not show_markers:
        return {}

    kwargs = {
        'marker': style['marker'],
        'markersize': style['markersize'],
        'markerfacecolor': style['markerfacecolor'],
        'markeredgecolor': style['markeredgecolor'],
        'markeredgewidth': style['markeredgewidth'],
    }
    if markevery is not None:
        kwargs['markevery'] = markevery
    return kwargs


def legacy_get_bar_layout_unused(num_algs):
    """计算分组柱状图中每个算法相对组中心的偏移量。"""
    bar_width = float(BAR_CHART_STYLE.get('bar_width', 0.34))
    use_bar_spacing = bool(BAR_CHART_STYLE.get('use_bar_spacing', True))
    offset_step = float(BAR_CHART_STYLE.get('bar_offset_step', bar_width))
    if not use_bar_spacing:
        offset_step = bar_width
    offsets = (np.arange(num_algs) - (num_algs - 1) / 2.0) * offset_step
    return bar_width, offsets


def legacy_get_bar_plot_style_unused(aname):
    """读取新增柱状图中某个算法的柱子样式，直接继承 ALG_STYLE。"""
    base = ALG_STYLE.get(aname, DEFAULT_STYLE)
    return {
        'color': base.get('color', DEFAULT_STYLE['color']),
        'label': base.get('label', aname),
    }


def legacy_compute_bar_error_values_unused(values_2d, errorbar_mode='std'):
    """按指定模式计算柱状图误差棒。"""
    mode = str(errorbar_mode or 'std').lower()
    std = np.nanstd(values_2d, axis=1)

    if mode == 'std':
        return std, mode, std

    valid_counts = np.sum(~np.isnan(values_2d), axis=1).astype(float)
    sem = np.divide(
        std,
        np.sqrt(valid_counts),
        out=np.full_like(std, np.nan, dtype=float),
        where=valid_counts > 0,
    )

    if mode == 'sem':
        return sem, mode, std
    if mode == 'ci95':
        return 1.96 * sem, mode, std

    raise ValueError(
        f"不支持的柱状图误差棒模式: {errorbar_mode}；可选值为 'std' / 'sem' / 'ci95'"
    )


def build_output_path(ts, stem):
    """Use the shared unified output prefix policy."""
    _ = ts
    return STYLE_HELPER.build_output_stem(build_prefixed_stem(FAMILY, stem))


def get_alg_plot_style(aname):
    """Resolve algorithm line style from the shared unified config."""
    return resolve_alg_plot_style(aname, ALG_STYLE, DEFAULT_STYLE, PLOT_GLOBAL)


def get_bar_layout(num_algs):
    """Resolve grouped-bar layout from the shared unified config."""
    return resolve_bar_layout(BAR_CHART_STYLE, num_algs)


def get_bar_plot_style(aname):
    """Resolve grouped-bar color/label from the shared unified config."""
    return resolve_bar_plot_style(aname, ALG_STYLE, DEFAULT_STYLE)


def compute_bar_error_values(values_2d, errorbar_mode='std'):
    """Resolve grouped-bar error values from the shared unified config."""
    return compute_shared_error_values(values_2d, errorbar_mode)


def fill_curve_tail(curve):
    """用最后一个有效值填充尾部 NaN，保持与实际绘图一致。"""
    if curve is None:
        return None
    arr = np.asarray(curve, dtype=float).copy()
    mask = ~np.isnan(arr)
    if not np.any(mask):
        return arr
    last_valid = np.where(mask)[0][-1]
    arr[last_valid + 1:] = arr[last_valid]
    return arr


def fill_std_tail(std_curve, reference_curve):
    """用最后一个有效 std 向右补平，保持与实际绘图一致。"""
    if std_curve is None:
        return None
    ref = np.asarray(reference_curve, dtype=float)
    std_arr = np.asarray(std_curve, dtype=float).copy()
    mask = ~np.isnan(ref)
    if not np.any(mask):
        return std_arr
    last_valid = np.where(mask)[0][-1]
    std_arr[last_valid + 1:] = std_arr[last_valid]
    return std_arr


def build_scalar_points(x_values, means, stds, errorbars=None):
    """构建标量图的精简数据点列表。"""
    rows = []
    iterable = zip(
        x_values,
        means,
        stds,
        errorbars if errorbars is not None else np.full(len(x_values), np.nan),
    )
    for x_val, mu, std, err in iterable:
        point = {
            'M': int(x_val),
            'value': mu,
            'std': std,
        }
        if errorbars is not None:
            point['errorbar'] = err
        rows.append(point)
    return rows


def build_scalar_figure_data(cfg, alg_names, metric_key, metrics, M_values, errorbar_mode=None):
    """构建标量图的精简 JSON 数据。"""
    algorithms = {}
    for aname in alg_names:
        means = np.nanmean(metrics[aname][metric_key], axis=1)
        stds = np.nanstd(metrics[aname][metric_key], axis=1)
        errorbars = None
        if errorbar_mode is not None:
            errorbars, _, stds = compute_bar_error_values(
                metrics[aname][metric_key],
                errorbar_mode=errorbar_mode,
            )
        algorithms[get_alg_display_name(aname)] = build_scalar_points(
            M_values,
            means,
            stds,
            errorbars=errorbars,
        )
    payload = {
        'x_axis': cfg.get('xlabel'),
        'y_axis': cfg.get('ylabel'),
        'algorithms': algorithms,
    }
    if errorbar_mode is not None:
        payload['errorbar_mode'] = errorbar_mode
    return payload


def build_convergence_figure_data(cfg, alg_names, mean_curves, std_curves, num_rounds, m_target):
    """构建 fig2d 的精简 JSON 数据。"""
    rounds = np.arange(1, num_rounds + 1)
    algorithms = {}
    for aname in alg_names:
        export_name = get_alg_display_name(aname)
        curve = fill_curve_tail(mean_curves.get(aname))
        if curve is None:
            algorithms[export_name] = []
            continue
        std_curve = fill_std_tail(std_curves.get(aname), curve)
        rows = []
        for round_idx, value, std_val in zip(
            rounds,
            curve,
            std_curve if std_curve is not None else np.full(num_rounds, np.nan),
        ):
            rows.append({
                'round': int(round_idx),
                'value': value,
                'std': std_val,
            })
        algorithms[export_name] = rows
    return {
        'x_axis': cfg.get('xlabel'),
        'y_axis': cfg.get('ylabel'),
        'm_target': int(m_target),
        'algorithms': algorithms,
    }


def build_compact_payload(source_input, output_dir, M_values, alg_names, metrics, mean_curves, std_curves, num_rounds, m_target):
    """构建 varyM 的精简 JSON。"""
    return {
        'source_input': source_input,
        'output_dir': output_dir,
        'M_values': list(M_values),
        'alg_names': get_alg_display_names(alg_names),
        'figures': {
            'fig1c_utility': build_scalar_figure_data(
                FIGURE_CONFIG['fig1c'],
                alg_names,
                'utility',
                metrics,
                M_values,
            ),
            'fig1d_completion': build_scalar_figure_data(
                FIGURE_CONFIG['fig1d'],
                alg_names,
                'completion',
                metrics,
                M_values,
            ),
            'fig1e_completed_value': build_scalar_figure_data(
                FIGURE_CONFIG['fig1e'],
                alg_names,
                'completed_value',
                metrics,
                M_values,
            ),
            'fig1f_utility_bar': build_scalar_figure_data(
                FIGURE_CONFIG['fig1f'],
                alg_names,
                'utility',
                metrics,
                M_values,
                errorbar_mode=FIGURE_CONFIG['fig1f'].get('errorbar_mode'),
            ),
            'fig1g_completed_value_bar': build_scalar_figure_data(
                FIGURE_CONFIG['fig1g'],
                alg_names,
                'completed_value',
                metrics,
                M_values,
                errorbar_mode=FIGURE_CONFIG['fig1g'].get('errorbar_mode'),
            ),
            'fig2d_convergence': build_convergence_figure_data(
                FIGURE_CONFIG['fig2d'],
                alg_names,
                mean_curves,
                std_curves,
                num_rounds,
                m_target,
            ),
        },
    }


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
    M_values = parse_M_values(config)
    alg_names = parse_alg_names(config)
    nM, nS = get_shape(results)

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

            utility = to_scalar(ae.get('final_utility'))
            completion = to_scalar(ae.get('final_completion'))
            cost = to_scalar(ae.get('final_cost'))
            completed_value = to_scalar(ae.get('final_completed_value'))

            if np.isnan(completed_value) and not np.isnan(utility) and not np.isnan(cost):
                completed_value = utility + cost

            metrics[aname]['utility'][mi, si] = utility
            metrics[aname]['completion'][mi, si] = completion
            metrics[aname]['completed_value'][mi, si] = completed_value
            metrics[aname]['cost'][mi, si] = cost
            metrics[aname]['time'][mi, si] = to_scalar(ae.get('computation_time'))

    return M_values, alg_names, metrics


def extract_convergence(results, config, m_target=None):
    """
    提取效用收敛曲线（图2d）。
    m_target: 取哪个 M 值（None → 取最大 M）。
    返回: mean_curves, std_curves, num_rounds, m_target
    """
    M_values = parse_M_values(config)
    alg_names = parse_alg_names(config)
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
    std_curves = {}
    for aname in alg_names:
        if curves[aname]:
            mat = np.vstack(curves[aname])
            mean_curves[aname] = np.nanmean(mat, axis=0)
            std_curves[aname] = np.nanstd(mat, axis=0)
        else:
            mean_curves[aname] = np.full(num_rounds, np.nan)
            std_curves[aname] = np.full(num_rounds, np.nan)

    return mean_curves, std_curves, num_rounds, m_target


# ══════════════════════════════════════════════════════════════════════════════
# 绘图函数
# ══════════════════════════════════════════════════════════════════════════════

def _plot_scalar_vs_M(fig_key, metric_key, M_values, alg_names, metrics, save_path):
    """通用：画某个标量指标 vs M 的折线图（均值 ± std）。"""
    cfg = merge_figure_config(fig_key)
    fig, ax = plt.subplots(figsize=cm_size_to_inch(PLOT_GLOBAL['figsize_cm']))

    for aname in alg_names:
        st = get_alg_plot_style(aname)
        mu = np.nanmean(metrics[aname][metric_key], axis=1)
        std = np.nanstd(metrics[aname][metric_key], axis=1)

        if PLOT_GLOBAL.get('show_errorbar_varyM', False):
            ax.errorbar(
                M_values,
                mu,
                yerr=std,
                color=st['color'],
                marker=st['marker'],
                ls=st['ls'],
                lw=st['linewidth'],
                ms=st['markersize'],
                markerfacecolor=st['markerfacecolor'],
                markeredgecolor=st['markeredgecolor'],
                markeredgewidth=st['markeredgewidth'],
                capsize=PLOT_GLOBAL['capsize'],
                label=st['label'],
                zorder=3,
            )
        else:
            ax.plot(
                M_values,
                mu,
                color=st['color'],
                marker=st['marker'],
                ls=st['ls'],
                lw=st['linewidth'],
                ms=st['markersize'],
                markerfacecolor=st['markerfacecolor'],
                markeredgecolor=st['markeredgecolor'],
                markeredgewidth=st['markeredgewidth'],
                label=st['label'],
                zorder=3,
            )

    apply_axis_controls(ax, cfg, m_values=M_values)
    apply_common_style(ax, cfg, title=cfg.get('title'))
    finalize_and_save(fig, save_path)


def plot_grouped_bar_vs_M(fig_key, metric_key, M_values, alg_names, metrics, save_path):
    """通用：画某个标量指标 vs M 的纯分组柱状图（均值 ± std）。"""
    cfg = merge_figure_config(fig_key)
    fig, ax = plt.subplots(figsize=cm_size_to_inch(PLOT_GLOBAL['figsize_cm']))
    x_centers = np.arange(len(M_values), dtype=float)
    bar_width, offsets = get_bar_layout(len(alg_names))
    show_errorbar = bool(cfg.get('show_errorbar', True))
    errorbar_mode = str(cfg.get('errorbar_mode', 'std')).lower()
    show_bar_edge = bool(BAR_CHART_STYLE.get('show_bar_edge', True))
    bar_edgecolor = BAR_CHART_STYLE.get('bar_edgecolor', '#000000') if show_bar_edge else 'none'
    bar_edgewidth = float(BAR_CHART_STYLE.get('bar_edgewidth', 0.0)) if show_bar_edge else 0.0

    for idx, aname in enumerate(alg_names):
        st = get_bar_plot_style(aname)
        values_2d = metrics[aname][metric_key]
        mu = np.nanmean(values_2d, axis=1)
        left_error, errorbar_mode, _ = compute_bar_error_values(
            values_2d,
            errorbar_mode=errorbar_mode,
        )
        x_positions = x_centers + offsets[idx]

        error_kw = {
            'ecolor': BAR_CHART_STYLE.get('errorbar_color', '#000000'),
            'elinewidth': BAR_CHART_STYLE.get('errorbar_linewidth', 0.5),
            'capsize': PLOT_GLOBAL['capsize'],
            'capthick': BAR_CHART_STYLE.get('errorbar_capthick', 0.5),
        }

        ax.bar(
            x_positions,
            mu,
            width=bar_width,
            yerr=left_error if show_errorbar else None,
            color=st['color'],
            alpha=BAR_CHART_STYLE.get('bar_alpha', 0.82),
            edgecolor=bar_edgecolor,
            linewidth=bar_edgewidth,
            label=st['label'],
            zorder=3,
            error_kw=error_kw,
        )

    apply_axis_controls(ax, cfg, m_values=x_centers)
    ax.set_xticklabels([str(int(m_val)) for m_val in M_values])
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


def plot_fig1f(M_values, alg_names, metrics, save_path):
    """图1f：变M效用纯分组柱状图。"""
    plot_grouped_bar_vs_M('fig1f', 'utility', M_values, alg_names, metrics, save_path)


def plot_fig1g(M_values, alg_names, metrics, save_path):
    """图1g：变M总完成价值纯分组柱状图。"""
    plot_grouped_bar_vs_M('fig1g', 'completed_value', M_values, alg_names, metrics, save_path)


def plot_fig2d(mean_curves, std_curves, num_rounds, m_target, alg_names, save_path):
    """图2d：效用收敛曲线（对最大M，按种子平均 + 半透明误差带）。"""
    cfg = merge_figure_config(
        'fig2d',
        title=FIGURE_CONFIG['fig2d']['title_template'].format(m_target=m_target),
    )
    fig, ax = plt.subplots(figsize=cm_size_to_inch(PLOT_GLOBAL['figsize_cm']))
    rounds = np.arange(1, num_rounds + 1)

    for aname in alg_names:
        curve = mean_curves.get(aname)
        std = std_curves.get(aname)

        if curve is None or np.all(np.isnan(curve)):
            continue

        st = get_alg_plot_style(aname)
        mask = ~np.isnan(curve)
        if not np.any(mask):
            continue

        filled = fill_curve_tail(curve)
        std_filled = fill_std_tail(std, curve)

        if std_filled is not None and PLOT_GLOBAL.get('show_fig2d_band', False):
            lower = filled - std_filled
            upper = filled + std_filled
            ax.fill_between(
                rounds,
                lower,
                upper,
                color=st['color'],
                alpha=PLOT_GLOBAL.get('fig2d_band_alpha', 0.18),
                linewidth=0,
            )

        marker_kwargs = get_plot_marker_kwargs(
            st,
            PLOT_GLOBAL['show_markers_fig2d'],
            PLOT_GLOBAL['markevery_fig2d'],
        )
        ax.plot(
            rounds,
            filled,
            color=st['color'],
            ls=st['ls'],
            lw=st['linewidth'],
            label=st['label'],
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
    output_source = run_meta.get('run_name') or infer_source_name(
        run_meta.get('source_path'),
        fallback='varyM',
    )
    configure_output_dir(output_source)

    print(f"  数据来源  = {run_meta.get('source_path', '')}")
    if run_meta.get('source_type') == 'run_dir':
        cache_state = '命中缓存' if run_meta.get('used_cache') else '重建缓存'
        print(f"  聚合方式  = 延迟聚合（{cache_state}）")
        print(f"  缓存文件  = {run_meta.get('cache_path', '')}")
    else:
        print(f"  聚合方式  = 直接读取 {run_meta.get('source_type')}")

    M_values = parse_M_values(config)
    alg_names = parse_alg_names(config)
    nM, nS = get_shape(results)
    fixed_N = int(to_scalar(config.get('N', 0)))
    m_conv = max(M_values)

    print(f"  固定 N    = {fixed_N}")
    print(f"  M_values  = {M_values}")
    print(f"  alg_names = {alg_names}")
    print(f"  形状      = {nM}×{nS} (M×seed)")

    print("\n提取指标...")
    M_values, alg_names, metrics = extract_final_metrics(results, config)

    print(f"\n绘图 → {FIGURES_DIR}")

    plot_fig1c(
        M_values,
        alg_names,
        metrics,
        build_output_path(None, 'fig1c_utility'),
    )

    plot_fig1d(
        M_values,
        alg_names,
        metrics,
        build_output_path(None, 'fig1d_completion'),
    )

    plot_fig1e(
        M_values,
        alg_names,
        metrics,
        build_output_path(None, 'fig1e_completed_value'),
    )

    plot_fig1f(
        M_values,
        alg_names,
        metrics,
        build_output_path(None, 'fig1f_utility_bar'),
    )

    plot_fig1g(
        M_values,
        alg_names,
        metrics,
        build_output_path(None, 'fig1g_completed_value_bar'),
    )

    mean_curves, std_curves, num_rounds, m_target = extract_convergence(
        results,
        config,
        m_target=m_conv,
    )
    plot_fig2d(
        mean_curves,
        std_curves,
        num_rounds,
        m_target,
        alg_names,
        build_output_path(None, 'fig2d_convergence'),
    )

    compact_payload = build_compact_payload(
        source_input=run_meta.get('source_path') or input_path,
        output_dir=FIGURES_DIR,
        M_values=M_values,
        alg_names=alg_names,
        metrics=metrics,
        mean_curves=mean_curves,
        std_curves=std_curves,
        num_rounds=num_rounds,
        m_target=m_target,
    )
    write_plot_data_json(
        os.path.join(FIGURES_DIR, 'varyM_plot_data_compact.json'),
        compact_payload,
    )

    print("\n完成。图窗已弹出，关闭后程序退出。")
    plt.show()


if __name__ == '__main__':
    main()
