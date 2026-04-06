"""
plot_varyN.py
=============
从 Batch_VaryN.m 生成的 .mat 文件绘制论文图：
  图1a  变N效用       (mean ± std 折线图，4算法)
  图1b  变N完成度     (mean ± std 折线图，4算法)
  图1c  变N总完成价值 (mean ± std 折线图，4算法)
  图1d  效用+完成率   (双Y轴柱状折线组合图，N=selected_n_values)
  图1e  总价值+完成率 (双Y轴柱状折线组合图，N=selected_n_values)
  图2c  效用收敛曲线  (对最大N，按种子平均)
  图3a  内循环轨迹    (OCF_SAtabu，current/best utility)

依赖:
  pip install mat73 numpy matplotlib scipy

用法:
  python plot_varyN_top_config.py                     # 自动搜索最新 .mat
  python plot_varyN_top_config.py path/to/varyN.mat   # 指定文件

说明:
  统一绘图配置已收敛到 plot_unified_config.py：
  - 图尺寸、线宽、字体、图例字号、输出 dpi
  - 各算法颜色、线型、marker
  - 各图标题、坐标轴名称、坐标范围、刻度
  - varyN 组合图和 varyM 柱状图的局部样式
"""

import os
import sys
import glob
import copy
import json
import re
import numpy as np
import matplotlib.pyplot as plt
from datetime import datetime
from plot_unified_config import (
    get_family_plot_config,
    get_family_figure_config,
    build_prefixed_stem,
    get_alg_display_name,
    get_alg_display_names,
    get_alg_plot_style as resolve_alg_plot_style,
    get_bar_plot_style as resolve_bar_plot_style,
    compute_error_values as compute_shared_error_values,
)
from plot_style_helper import (
    PlotStyleHelper,
    build_results_figures_dir,
    cm_size_to_inch,
    infer_source_name,
)

try:
    import mat73
except ImportError:
    sys.exit("缺少依赖，请先执行: pip install mat73")


# ══════════════════════════════════════════════════════════════════════════════
# 统一绘图配置入口见 plot_unified_config.py
# ══════════════════════════════════════════════════════════════════════════════

# =========================
# 这里只保留路径和 family 选择；样式主配置统一放在 plot_unified_config.py。
# =========================

# 路径配置
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))  # 当前脚本所在目录
ROOT_DIR = os.path.dirname(SCRIPT_DIR)  # 项目根目录
FIGURES_DIR = build_results_figures_dir(ROOT_DIR, 'varyN')  # 图片输出目录
SEARCH_DIRS = [
    os.path.join(ROOT_DIR, 'results', 'batch', 'varyN'),  # 优先搜索 varyN 实验结果目录
    os.path.join(ROOT_DIR, 'results', 'batch'),  # 兜底搜索通用 batch 目录
]
FAMILY = 'varyN'
PLOT_CONFIG = get_family_plot_config(FAMILY)
ALG_STYLE = PLOT_CONFIG['ALG_STYLE']
DEFAULT_STYLE = PLOT_CONFIG['DEFAULT_STYLE']
PLOT_GLOBAL = PLOT_CONFIG['PLOT_GLOBAL']
BAR_CHART_STYLE = PLOT_CONFIG['BAR_CHART_STYLE']
INNER_LOOP_STYLE = PLOT_CONFIG['INNER_LOOP_STYLE']
COMBO_CHART_STYLE = PLOT_CONFIG['COMBO_CHART_STYLE']
FIGURE_CONFIG = PLOT_CONFIG['FIGURE_CONFIG']
OUTPUT_PREFIX = PLOT_CONFIG['OUTPUT_PREFIX']

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
    """Resolve one final figure config from unified config."""
    return get_family_figure_config(FAMILY, fig_key, **kwargs)


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
    return STYLE_HELPER.build_output_stem(build_prefixed_stem(FAMILY, stem))


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
    if PLOT_GLOBAL.get('use_fixed_export_margins', False):
        fig_width_cm = fig.get_figwidth() * 2.54
        fig_height_cm = fig.get_figheight() * 2.54

        left_margin_cm = float(PLOT_GLOBAL.get('export_margin_left_cm', 1.58))
        right_margin_cm = float(PLOT_GLOBAL.get('export_margin_right_cm', 1.23))
        bottom_margin_cm = float(PLOT_GLOBAL.get('export_margin_bottom_cm', 1.17))
        top_margin_cm = float(PLOT_GLOBAL.get('export_margin_top_cm', 0.26))

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


def configure_output_dir(mat_path):
    global FIGURES_DIR
    source_name = infer_source_name(mat_path, fallback='varyN')
    FIGURES_DIR = build_results_figures_dir(ROOT_DIR, 'varyN', source_name)
    os.makedirs(FIGURES_DIR, exist_ok=True)
    STYLE_HELPER.set_figures_dir(FIGURES_DIR)
    return FIGURES_DIR


def get_selected_n_indices(all_n_values, selected_n_values=None):
    """校验目标 N 子集是否存在，并按指定顺序返回索引。"""
    target_values = list(selected_n_values or COMBO_CHART_STYLE['selected_n_values'])
    index_map = {int(n): idx for idx, n in enumerate(all_n_values)}
    missing_values = [n for n in target_values if int(n) not in index_map]
    if missing_values:
        raise ValueError(
            '组合图所需的 N 值缺失: '
            f'{missing_values}；当前数据仅包含 {list(all_n_values)}'
        )
    return [index_map[int(n)] for n in target_values]


def apply_secondary_axis_style(ax, ylabel, ylim=None, yticks=None):
    """统一设置双Y轴右侧坐标轴样式。"""
    ax.set_ylabel(
        ylabel,
        **get_text_style('ylabel_fontsize', 'label_fontweight'),
    )

    if ylim is not None:
        ax.set_ylim(*ylim)
    if yticks is not None:
        ax.set_yticks(yticks)

    tick_fontsize = PLOT_GLOBAL.get('tick_fontsize')
    if tick_fontsize is not None:
        ax.tick_params(axis='y', labelsize=tick_fontsize)

    font_family = PLOT_GLOBAL.get('font_family')
    font_style = PLOT_GLOBAL.get('font_style')
    tick_fontweight = PLOT_GLOBAL.get('tick_fontweight')
    for tick in ax.get_yticklabels():
        if font_family:
            tick.set_fontfamily(font_family)
        if font_style:
            tick.set_fontstyle(font_style)
        if tick_fontweight:
            tick.set_fontweight(tick_fontweight)

    if PLOT_GLOBAL.get('hide_top_spine', False):
        ax.spines['top'].set_visible(False)
    ax.spines['right'].set_visible(True)


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
    """将绘图数据导出为 JSON。"""
    with open(output_path, 'w', encoding='utf-8') as fp:
        json.dump(json_safe_data(payload), fp, ensure_ascii=False, indent=2)
    print(f"  [OK] {output_path}")


def get_alg_plot_style(aname):
    """读取算法折线样式，并支持 mfc/mec/lw/ms/mew。"""
    return resolve_alg_plot_style(aname, ALG_STYLE, DEFAULT_STYLE, PLOT_GLOBAL)


def build_completion_lookup(metrics, N_values, alg_names, selected_n_values):
    """按算法和 N 构建完成率均值查找表，用于组合图精简 JSON 兜底。"""
    selected_indices = get_selected_n_indices(N_values, selected_n_values)
    lookup = {}
    for aname in alg_names:
        completion_values = metrics[aname]['completion'][selected_indices, :]
        completion_mu = np.nanmean(completion_values, axis=1)
        lookup[get_alg_display_name(aname)] = {
            int(n_val): value
            for n_val, value in zip(selected_n_values, completion_mu)
        }
    return lookup


def build_combo_point_map(points, value_key, figure_name, aname, series_kind):
    """将组合图单条序列的点转换为按 N 索引的查找表。"""
    point_map = {}
    for point in points:
        if 'x_value' not in point:
            raise ValueError(
                f"{figure_name} 的 {aname} {series_kind} 序列缺少 x_value"
            )
        n_val = int(point['x_value'])
        if n_val in point_map:
            raise ValueError(
                f"{figure_name} 的 {aname} {series_kind} 序列存在重复 N={n_val}"
            )
        if value_key not in point:
            raise ValueError(
                f"{figure_name} 的 {aname} {series_kind} 序列缺少 {value_key}"
            )
        point_map[n_val] = point[value_key]
    return point_map


def build_combo_only_figure_data(
    figure_name,
    figure_data,
    alg_names,
    selected_n_values,
    left_metric,
    left_value_key,
    completion_lookup,
):
    """从组合图完整导出数据中提取精简版 JSON 结构。"""
    if not isinstance(figure_data, dict) or figure_data.get('status') != 'generated':
        raise ValueError(f'{figure_name} 未成功生成，无法导出精简 JSON')

    show_completion_line = bool(figure_data.get('show_completion_line', True))
    bar_series_by_alg = {}
    line_series_by_alg = {}
    display_alg_names = set(get_alg_display_names(alg_names))

    for series in figure_data.get('series', []):
        aname = series.get('algorithm')
        if aname not in display_alg_names:
            continue
        kind = series.get('series_kind')
        if kind == 'bar':
            if aname in bar_series_by_alg:
                raise ValueError(f'{figure_name} 中算法 {aname} 存在重复 bar 序列')
            bar_series_by_alg[aname] = series
        elif kind == 'line':
            if aname in line_series_by_alg:
                raise ValueError(f'{figure_name} 中算法 {aname} 存在重复 line 序列')
            line_series_by_alg[aname] = series

    algorithms = {}
    for aname in alg_names:
        export_name = get_alg_display_name(aname)
        if export_name not in bar_series_by_alg:
            raise ValueError(f'{figure_name} 缺少算法 {export_name} 的 bar 数据')

        bar_points = build_combo_point_map(
            bar_series_by_alg[export_name].get('points', []),
            value_key='mean',
            figure_name=figure_name,
            aname=export_name,
            series_kind='bar',
        )

        if show_completion_line:
            if export_name not in line_series_by_alg:
                raise ValueError(f'{figure_name} 缺少算法 {export_name} 的 completion line 数据')
            completion_points = build_combo_point_map(
                line_series_by_alg[export_name].get('points', []),
                value_key='value',
                figure_name=figure_name,
                aname=export_name,
                series_kind='line',
            )
        else:
            completion_points = completion_lookup.get(export_name, {})

        rows = []
        for n_val in selected_n_values:
            n_int = int(n_val)
            if n_int not in bar_points:
                raise ValueError(f'{figure_name} 的算法 {export_name} 缺少 N={n_int} 的柱状值')
            if n_int not in completion_points:
                raise ValueError(f'{figure_name} 的算法 {export_name} 缺少 N={n_int} 的完成率')
            rows.append({
                'N': n_int,
                left_value_key: bar_points[n_int],
                'completion_rate': completion_points[n_int],
            })
        algorithms[export_name] = rows

    return {
        'left_metric': left_metric,
        'right_metric': 'Completion Rate',
        'algorithms': algorithms,
    }


def build_combo_only_payload(plot_data, N_values, alg_names, metrics):
    """构建仅包含 fig1d / fig1e 的精简 JSON。"""
    selected_n_values = list(plot_data.get('selected_n_values', COMBO_CHART_STYLE['selected_n_values']))
    completion_lookup = build_completion_lookup(
        metrics,
        N_values,
        alg_names,
        selected_n_values,
    )
    figures = plot_data.get('figures', {})
    return {
        'source_mat_path': plot_data.get('source_mat_path'),
        'output_dir': plot_data.get('output_dir'),
        'selected_n_values': selected_n_values,
        'alg_names': get_alg_display_names(alg_names),
        'figures': {
            'fig1d_utility_completion_combo': build_combo_only_figure_data(
                'fig1d',
                figures.get('fig1d'),
                alg_names,
                selected_n_values,
                left_metric='Final Coalition Utility',
                left_value_key='utility_value',
                completion_lookup=completion_lookup,
            ),
            'fig1e_completed_value_completion_combo': build_combo_only_figure_data(
                'fig1e',
                figures.get('fig1e'),
                alg_names,
                selected_n_values,
                left_metric='Total Completed Value',
                left_value_key='completed_value',
                completion_lookup=completion_lookup,
            ),
        },
    }


def get_combo_line_style(aname):
    """读取组合图中某个算法的折线样式。"""
    base = get_alg_plot_style(aname)
    custom = COMBO_CHART_STYLE.get('line_style_by_alg', {}).get(aname, {})
    line_color = custom.get('color', base['color'])
    base_markerfacecolor = base['markerfacecolor']
    markerfacecolor = custom['mfc'] if 'mfc' in custom else (
        base_markerfacecolor
        if str(base_markerfacecolor).lower() == 'none'
        else (line_color if 'color' in custom else base_markerfacecolor)
    )
    markeredgecolor = custom['mec'] if 'mec' in custom else (
        line_color if 'color' in custom else base['markeredgecolor']
    )
    return {
        'color': line_color,
        'marker': custom.get('marker', base['marker']),
        'ls': custom.get('ls', base['ls']),
        'linewidth': custom.get('linewidth', base['linewidth']),
        'markersize': custom.get('markersize', base['markersize']),
        'markerfacecolor': markerfacecolor,
        'markeredgecolor': markeredgecolor,
        'markeredgewidth': custom.get('markeredgewidth', base['markeredgewidth']),
    }


def get_combo_bar_style(aname):
    """读取组合图中某个算法的柱状图样式。"""
    return resolve_bar_plot_style(aname, ALG_STYLE, DEFAULT_STYLE)


def compute_combo_error_values(values_2d, errorbar_mode='std'):
    """按指定模式计算组合图柱状图误差棒。"""
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


def build_scalar_points(x_values, means, stds):
    """构建 mean/std 标量图的数据点列表。"""
    points = []
    for x_val, mu, std in zip(x_values, means, stds):
        points.append({
            'x_label': str(int(x_val)),
            'x_value': int(x_val),
            'mean': mu,
            'std': std,
        })
    return points


def build_scalar_figure_data(fig_key, cfg, alg_names, metric_key, metrics, N_values):
    """构建 fig1a / fig1b / fig1c 的导出数据。"""
    series = []
    for aname in alg_names:
        st = get_alg_plot_style(aname)
        export_name = get_alg_display_name(aname)
        means = np.nanmean(metrics[aname][metric_key], axis=1)
        stds = np.nanstd(metrics[aname][metric_key], axis=1)
        series.append({
            'name': st['label'],
            'algorithm': export_name,
            'series_kind': 'line',
            'style': {
                'color': st['color'],
                'marker': st['marker'],
                'ls': st['ls'],
                'linewidth': st['linewidth'],
                'markersize': st['markersize'],
                'markerfacecolor': st['markerfacecolor'],
                'markeredgecolor': st['markeredgecolor'],
                'markeredgewidth': st['markeredgewidth'],
            },
            'points': build_scalar_points(N_values, means, stds),
        })

    return {
        'status': 'generated',
        'figure_type': 'line_chart',
        'x_axis': cfg.get('xlabel'),
        'left_y_axis': cfg.get('ylabel'),
        'series': series,
    }


def build_convergence_figure_data(cfg, alg_names, mean_curves, num_rounds):
    """构建 fig2c 的导出数据。"""
    rounds = np.arange(1, num_rounds + 1)
    series = []
    for aname in alg_names:
        curve = fill_curve_tail(mean_curves.get(aname))
        if curve is None or np.all(np.isnan(curve)):
            continue
        st = get_alg_plot_style(aname)
        export_name = get_alg_display_name(aname)
        points = []
        for round_idx, value in zip(rounds, curve):
            points.append({
                'round': int(round_idx),
                'value': value,
            })
        series.append({
            'name': st['label'],
            'algorithm': export_name,
            'series_kind': 'line',
            'style': {
                'color': st['color'],
                'marker': st['marker'],
                'ls': st['ls'],
                'linewidth': st['linewidth'],
                'markersize': st['markersize'],
                'markerfacecolor': st['markerfacecolor'],
                'markeredgecolor': st['markeredgecolor'],
                'markeredgewidth': st['markeredgewidth'],
            },
            'points': points,
        })

    return {
        'status': 'generated',
        'figure_type': 'convergence_line_chart',
        'x_axis': cfg.get('xlabel'),
        'left_y_axis': cfg.get('ylabel'),
        'series': series,
    }


def build_inner_loop_figure_data(cfg, mean_curr, std_curr, mean_best, std_best):
    """构建 fig3a 的导出数据。"""
    if mean_curr is None and mean_best is None:
        return {
            'status': 'skipped',
            'figure_type': 'inner_loop_line_chart',
            'x_axis': cfg.get('xlabel'),
            'left_y_axis': cfg.get('ylabel'),
            'reason': 'inner_loop data unavailable',
            'series': [],
        }

    series = []
    if mean_curr is not None:
        points = []
        for iter_idx, (mu, std) in enumerate(zip(mean_curr, std_curr if std_curr is not None else np.full_like(mean_curr, np.nan)), start=1):
            points.append({
                'iteration': int(iter_idx),
                'mean': mu,
                'std': std,
            })
        series.append({
            'name': INNER_LOOP_STYLE['current_label'],
            'algorithm': get_alg_display_name('OCF_SAtabu'),
            'series_kind': 'line',
            'style': {
                'color': INNER_LOOP_STYLE['current_color'],
                'ls': INNER_LOOP_STYLE['current_ls'],
                'linewidth': PLOT_GLOBAL['linewidth'],
            },
            'points': points,
        })

    if mean_best is not None:
        points = []
        for iter_idx, (mu, std) in enumerate(zip(mean_best, std_best if std_best is not None else np.full_like(mean_best, np.nan)), start=1):
            points.append({
                'iteration': int(iter_idx),
                'mean': mu,
                'std': std,
            })
        series.append({
            'name': INNER_LOOP_STYLE['best_label'],
            'algorithm': get_alg_display_name('OCF_SAtabu'),
            'series_kind': 'line',
            'style': {
                'color': INNER_LOOP_STYLE['best_color'],
                'ls': INNER_LOOP_STYLE['best_ls'],
                'linewidth': PLOT_GLOBAL['linewidth'],
            },
            'points': points,
        })

    return {
        'status': 'generated',
        'figure_type': 'inner_loop_line_chart',
        'x_axis': cfg.get('xlabel'),
        'left_y_axis': cfg.get('ylabel'),
        'series': series,
    }


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
    fig, ax = plt.subplots(figsize=cm_size_to_inch(PLOT_GLOBAL['figsize_cm']))

    for aname in alg_names:
        st = get_alg_plot_style(aname)
        mu = np.nanmean(metrics[aname]['utility'], axis=1)
        std = np.nanstd(metrics[aname]['utility'], axis=1)

        if PLOT_GLOBAL.get('show_errorbar_varyN', True):
            ax.errorbar(
                N_values, mu, yerr=std,
                color=st['color'], marker=st['marker'], ls=st['ls'],
                lw=st['linewidth'], ms=st['markersize'],
                mfc=st['markerfacecolor'], mec=st['markeredgecolor'],
                mew=st['markeredgewidth'],
                capsize=PLOT_GLOBAL['capsize'],
                label=st['label'], zorder=3,
            )
        else:
            ax.plot(
                N_values, mu,
                color=st['color'], marker=st['marker'], ls=st['ls'],
                lw=st['linewidth'], ms=st['markersize'],
                mfc=st['markerfacecolor'], mec=st['markeredgecolor'],
                mew=st['markeredgewidth'],
                label=st['label'], zorder=3,
            )

    apply_axis_controls(ax, cfg, n_values=N_values)
    apply_common_style(ax, cfg, title=cfg.get('title'))
    finalize_and_save(fig, save_path)
    return build_scalar_figure_data('fig1a', cfg, alg_names, 'utility', metrics, N_values)

def plot_fig1b(N_values, alg_names, metrics, save_path):
    """图1b：变N完成度（mean ± std 折线图）"""
    cfg = merge_figure_config('fig1b')
    fig, ax = plt.subplots(figsize=cm_size_to_inch(PLOT_GLOBAL['figsize_cm']))

    for aname in alg_names:
        st = get_alg_plot_style(aname)
        mu = np.nanmean(metrics[aname]['completion'], axis=1)
        std = np.nanstd(metrics[aname]['completion'], axis=1)

        if PLOT_GLOBAL.get('show_errorbar_varyN', True):
            ax.errorbar(
                N_values, mu, yerr=std,
                color=st['color'], marker=st['marker'], ls=st['ls'],
                lw=st['linewidth'], ms=st['markersize'],
                mfc=st['markerfacecolor'], mec=st['markeredgecolor'],
                mew=st['markeredgewidth'],
                capsize=PLOT_GLOBAL['capsize'],
                label=st['label'], zorder=3,
            )
        else:
            ax.plot(
                N_values, mu,
                color=st['color'], marker=st['marker'], ls=st['ls'],
                lw=st['linewidth'], ms=st['markersize'],
                mfc=st['markerfacecolor'], mec=st['markeredgecolor'],
                mew=st['markeredgewidth'],
                label=st['label'], zorder=3,
            )

    apply_axis_controls(ax, cfg, n_values=N_values)
    apply_common_style(ax, cfg, title=cfg.get('title'))
    finalize_and_save(fig, save_path)
    return build_scalar_figure_data('fig1b', cfg, alg_names, 'completion', metrics, N_values)

def plot_fig1c(N_values, alg_names, metrics, save_path):
    """Plot total completed value vs N."""
    cfg = merge_figure_config('fig1c')
    fig, ax = plt.subplots(figsize=cm_size_to_inch(PLOT_GLOBAL['figsize_cm']))

    for aname in alg_names:
        st = get_alg_plot_style(aname)
        mu = np.nanmean(metrics[aname]['completed_value'], axis=1)
        std = np.nanstd(metrics[aname]['completed_value'], axis=1)

        if PLOT_GLOBAL.get('show_errorbar_varyN', True):
            ax.errorbar(
                N_values, mu, yerr=std,
                color=st['color'], marker=st['marker'], ls=st['ls'],
                lw=st['linewidth'], ms=st['markersize'],
                mfc=st['markerfacecolor'], mec=st['markeredgecolor'],
                mew=st['markeredgewidth'],
                capsize=PLOT_GLOBAL['capsize'],
                label=st['label'], zorder=3,
            )
        else:
            ax.plot(
                N_values, mu,
                color=st['color'], marker=st['marker'], ls=st['ls'],
                lw=st['linewidth'], ms=st['markersize'],
                mfc=st['markerfacecolor'], mec=st['markeredgecolor'],
                mew=st['markeredgewidth'],
                label=st['label'], zorder=3,
            )

    apply_axis_controls(ax, cfg, n_values=N_values)
    apply_common_style(ax, cfg, title=cfg.get('title'))
    finalize_and_save(fig, save_path)
    return build_scalar_figure_data('fig1c', cfg, alg_names, 'completed_value', metrics, N_values)


def plot_dual_axis_combo(fig_key, left_metric_key, N_values, alg_names, metrics, save_path):
    """双Y轴柱状折线组合图：左轴柱状图，右轴完成率折线图。"""
    cfg = merge_figure_config(fig_key)
    selected_indices = get_selected_n_indices(
        N_values,
        COMBO_CHART_STYLE['selected_n_values'],
    )
    selected_n_values = [N_values[idx] for idx in selected_indices]
    x_centers = np.arange(len(selected_n_values), dtype=float)
    show_completion_line = bool(cfg.get('show_completion_line', True))
    show_errorbar = bool(cfg.get('show_errorbar', True))
    errorbar_mode = str(cfg.get('errorbar_mode', 'std')).lower()

    fig, ax = plt.subplots(figsize=cm_size_to_inch(PLOT_GLOBAL['figsize_cm']))
    ax2 = ax.twinx() if show_completion_line else None
    if ax2 is not None:
        ax2.patch.set_alpha(0.0)

    num_algs = len(alg_names)
    bar_width = COMBO_CHART_STYLE['bar_width']
    use_bar_spacing = bool(COMBO_CHART_STYLE.get('use_bar_spacing', True))
    bar_offset_step = (
        COMBO_CHART_STYLE.get('bar_offset_step', bar_width)
        if use_bar_spacing else bar_width
    )
    show_bar_edge = bool(COMBO_CHART_STYLE.get('show_bar_edge', True))
    bar_edgecolor = COMBO_CHART_STYLE['bar_edgecolor'] if show_bar_edge else 'none'
    bar_edgewidth = COMBO_CHART_STYLE['bar_edgewidth'] if show_bar_edge else 0.0
    offsets = (
        np.arange(num_algs, dtype=float) - (num_algs - 1) / 2.0
    ) * bar_offset_step
    series = []

    for alg_idx, aname in enumerate(alg_names):
        export_name = get_alg_display_name(aname)
        bar_style = get_combo_bar_style(aname)
        line_style = get_combo_line_style(aname)
        x_positions = x_centers + offsets[alg_idx]

        left_values = metrics[aname][left_metric_key][selected_indices, :]
        left_mu = np.nanmean(left_values, axis=1)
        left_error, errorbar_mode, left_std = compute_combo_error_values(
            left_values,
            errorbar_mode=errorbar_mode,
        )

        ax.bar(
            x_positions,
            left_mu,
            width=bar_width,
            color=bar_style['color'],
            alpha=COMBO_CHART_STYLE['bar_alpha'],
            edgecolor=bar_edgecolor,
            linewidth=bar_edgewidth,
            yerr=left_error if show_errorbar else None,
            error_kw={
                'ecolor': COMBO_CHART_STYLE['errorbar_color'],
                'elinewidth': COMBO_CHART_STYLE['errorbar_linewidth'],
                'capsize': PLOT_GLOBAL['capsize'],
                'capthick': COMBO_CHART_STYLE['errorbar_capthick'],
            },
            label=bar_style['label'],
            zorder=2,
        )
        bar_points = []
        for x_idx, n_val, mu, std, err in zip(
            range(len(selected_n_values)),
            selected_n_values,
            left_mu,
            left_std,
            left_error,
        ):
            bar_points.append({
                'x_label': str(int(n_val)),
                'x_index': int(x_idx),
                'x_value': int(n_val),
                'mean': mu,
                'std': std,
                'errorbar': err if show_errorbar else None,
            })
        series.append({
            'name': bar_style['label'],
            'algorithm': export_name,
            'series_kind': 'bar',
            'style': {
                'color': bar_style['color'],
                'alpha': COMBO_CHART_STYLE['bar_alpha'],
                'bar_width': bar_width,
                'use_bar_spacing': use_bar_spacing,
                'bar_offset_step': bar_offset_step,
                'show_bar_edge': show_bar_edge,
                'edgecolor': bar_edgecolor,
                'edgewidth': bar_edgewidth,
                'errorbar_color': COMBO_CHART_STYLE['errorbar_color'],
                'errorbar_linewidth': COMBO_CHART_STYLE['errorbar_linewidth'],
                'errorbar_capthick': COMBO_CHART_STYLE['errorbar_capthick'],
                'capsize': PLOT_GLOBAL['capsize'],
                'errorbar_mode': errorbar_mode,
            },
            'points': bar_points,
        })

        if show_completion_line and ax2 is not None:
            completion_values = metrics[aname]['completion'][selected_indices, :]
            completion_mu = np.nanmean(completion_values, axis=1)
            ax2.plot(
                x_centers,
                completion_mu,
                color=line_style['color'],
                marker=line_style['marker'],
                ls=line_style['ls'],
                lw=line_style['linewidth'],
                ms=line_style['markersize'],
                mfc=line_style['markerfacecolor'],
                mec=line_style['markeredgecolor'],
                mew=line_style['markeredgewidth'],
                label='_nolegend_',
                zorder=4,
            )
            line_points = []
            for x_idx, n_val, value in zip(range(len(selected_n_values)), selected_n_values, completion_mu):
                line_points.append({
                    'x_label': str(int(n_val)),
                    'x_index': int(x_idx),
                    'x_value': int(n_val),
                    'value': value,
                })
            series.append({
                'name': bar_style['label'],
                'algorithm': export_name,
                'series_kind': 'line',
                'style': line_style,
                'points': line_points,
            })

    ax.set_xticks(x_centers)
    ax.set_xticklabels([str(int(n)) for n in selected_n_values])

    if cfg.get('xlim') is None and len(x_centers) > 0:
        x_pad = ((num_algs - 1) / 2.0) * bar_offset_step + bar_width / 2.0 + 0.12
        ax.set_xlim(x_centers[0] - x_pad, x_centers[-1] + x_pad)

    apply_axis_controls(ax, cfg)
    STYLE_HELPER.apply_common_style(
        ax,
        cfg=cfg,
        title=cfg.get('title'),
    )
    if show_completion_line and ax2 is not None:
        apply_secondary_axis_style(
            ax2,
            cfg.get('right_ylabel', 'Completion Rate'),
            ylim=COMBO_CHART_STYLE['completion_ylim'],
            yticks=COMBO_CHART_STYLE['completion_yticks'],
        )
    finalize_and_save(fig, save_path)
    return {
        'status': 'generated',
        'figure_type': 'dual_axis_bar_line_combo',
        'x_axis': cfg.get('xlabel'),
        'left_y_axis': cfg.get('ylabel'),
        'right_y_axis': cfg.get('right_ylabel', 'Completion Rate') if show_completion_line else None,
        'show_completion_line': show_completion_line,
        'show_errorbar': show_errorbar,
        'errorbar_mode': errorbar_mode,
        'series': series,
    }


def plot_fig2c(mean_curves, num_rounds, n_target, alg_names, save_path):
    """图2c：效用收敛曲线（对指定N均值化）"""
    cfg = merge_figure_config(
        'fig2c',
        title=FIGURE_CONFIG['fig2c']['title_template'].format(n_target=n_target),
    )
    fig, ax = plt.subplots(figsize=cm_size_to_inch(PLOT_GLOBAL['figsize_cm']))
    rounds = np.arange(1, num_rounds + 1)

    for aname in alg_names:
        curve = mean_curves.get(aname)
        if curve is None or np.all(np.isnan(curve)):
            continue
        st = get_alg_plot_style(aname)
        filled = fill_curve_tail(curve)
        mask = ~np.isnan(filled)
        if not np.any(mask):
            continue
        marker_kwargs = {}
        if PLOT_GLOBAL['show_markers_fig2c']:
            marker_kwargs = {
                'marker': st['marker'],
                'ms': st['markersize'],
                'mfc': st['markerfacecolor'],
                'mec': st['markeredgecolor'],
                'mew': st['markeredgewidth'],
            }
            if PLOT_GLOBAL['markevery_fig2c'] is not None:
                marker_kwargs['markevery'] = PLOT_GLOBAL['markevery_fig2c']
        ax.plot(
            rounds, filled,
            color=st['color'], ls=st['ls'],
            lw=st['linewidth'], label=st['label'],
            **marker_kwargs,
        )

    apply_axis_controls(ax, cfg)
    apply_common_style(ax, cfg, title=cfg.get('title'))
    finalize_and_save(fig, save_path)
    return build_convergence_figure_data(cfg, alg_names, mean_curves, num_rounds)


def plot_fig3a(mean_curr, std_curr, mean_best, std_best, n_target, save_path):
    """图3a：OCF_SAtabu 内循环 current / best utility 轨迹"""
    cfg = merge_figure_config(
        'fig3a',
        title=FIGURE_CONFIG['fig3a']['title_template'].format(
            round_label=INNER_LOOP_STYLE['round_label'],
            n_target=n_target,
        ),
    )
    if mean_curr is None and mean_best is None:
        print("  ! 内循环数据为空（OCF_SAtabu 未记录 inner_loop），跳过图3a")
        return build_inner_loop_figure_data(cfg, mean_curr, std_curr, mean_best, std_best)

    fig, ax = plt.subplots(figsize=cm_size_to_inch(PLOT_GLOBAL['figsize_cm']))
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
    return build_inner_loop_figure_data(cfg, mean_curr, std_curr, mean_best, std_best)


# ══════════════════════════════════════════════════════════════════════════════
# 主程序
# ══════════════════════════════════════════════════════════════════════════════

def main():
    apply_plot_rcparams()
    mat_path = find_mat_file(sys.argv)
    configure_output_dir(mat_path)

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

    print("\n提取指标...")
    N_values, alg_names, metrics = extract_final_metrics(results, config)
    plot_data = {
        'source_mat_path': os.path.abspath(mat_path),
        'output_dir': os.path.abspath(FIGURES_DIR),
        'selected_n_values': list(COMBO_CHART_STYLE['selected_n_values']),
        'all_n_values': list(N_values),
        'alg_names': get_alg_display_names(alg_names),
        'figures': {},
    }

    print(f"\n绘图 → {FIGURES_DIR}")

    plot_data['figures']['fig1a'] = plot_fig1a(
        N_values, alg_names, metrics,
        build_output_path(None, 'fig1a_utility'),
    )

    plot_data['figures']['fig1b'] = plot_fig1b(
        N_values, alg_names, metrics,
        build_output_path(None, 'fig1b_completion'),
    )

    plot_data['figures']['fig1c'] = plot_fig1c(
        N_values, alg_names, metrics,
        build_output_path(None, 'fig1c_completed_value'),
    )

    plot_data['figures']['fig1d'] = plot_dual_axis_combo(
        'fig1d', 'utility', N_values, alg_names, metrics,
        build_output_path(None, 'fig1d_utility_completion_combo'),
    )

    plot_data['figures']['fig1e'] = plot_dual_axis_combo(
        'fig1e', 'completed_value', N_values, alg_names, metrics,
        build_output_path(None, 'fig1e_completed_value_completion_combo'),
    )

    mean_curves, num_rounds, n_target = extract_convergence(
        results, config, n_target=n_conv,
    )
    plot_data['figures']['fig2c'] = plot_fig2c(
        mean_curves, num_rounds, n_target, alg_names,
        build_output_path(None, 'fig2c_convergence'),
    )

    mc, sc, mb, sb, nt = extract_inner_loop(results, config, n_target=n_conv)
    plot_data['figures']['fig3a'] = plot_fig3a(
        mc, sc, mb, sb, nt,
        build_output_path(None, 'fig3a_inner_loop'),
    )

    write_plot_data_json(
        os.path.join(FIGURES_DIR, 'varyN_plot_data_all.json'),
        plot_data,
    )
    write_plot_data_json(
        os.path.join(FIGURES_DIR, 'varyN_plot_data_combo_only.json'),
        build_combo_only_payload(plot_data, N_values, alg_names, metrics),
    )

    print("\n完成。图窗已弹出，关闭后程序退出。")
    plt.show()


if __name__ == '__main__':
    main()
