"""
plot_single_viz.py
==================
从 Single_Viz.m 生成的 .mat 文件绘制论文图：
  图5a  资源分配矩阵热图  (M 个任务的 SC{m} = N×K 热图网格)
  图5b  智能体任务执行甘特图  (N 个智能体的时序执行条形图，按任务类型着色)

依赖:
  pip install mat73 numpy matplotlib scipy

用法:
  python plot_single_viz.py                        # 自动搜索最新 .mat
  python plot_single_viz.py path/to/visualize.mat  # 指定文件

说明:
  你可以直接在本文件最上方的"顶部可调参数区"中修改：
  - 热图色彩映射、是否显示统一 colorbar、是否在格内标数值
  - 甘特条高度、任务 ID 标签显示阈值
  - 任务类型颜色方案
  - 每个图的标题、坐标轴标签、输出 dpi
"""

import os
import sys
import glob
import json
import colorsys
import numpy as np
import matplotlib.pyplot as plt
import matplotlib.patches as mpatches
from matplotlib.lines import Line2D
from matplotlib.colors import Normalize, TwoSlopeNorm, to_hex, to_rgb
from matplotlib.cm import ScalarMappable
from plot_unified_config import (
    build_prefixed_stem,
    get_alg_display_name,
    get_family_figure_config,
    get_family_plot_config,
)
from plot_style_helper import PlotStyleHelper, build_results_figures_dir, cm_size_to_inch, infer_source_name

try:
    import mat73
except ImportError:
    sys.exit("缺少依赖，请先执行: pip install mat73")


# ══════════════════════════════════════════════════════════════════════════════
# 顶部可调参数区（建议以后优先在这里改）
# ══════════════════════════════════════════════════════════════════════════════

# ── 路径配置 ──────────────────────────────────────────────────────────────────
# =========================
# 顶部可调绘图参数
# 建议优先在这里改颜色方案、子图尺寸、图例和保存设置。
# =========================

# 路径配置
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
ROOT_DIR = os.path.dirname(SCRIPT_DIR)
FIGURES_DIR = build_results_figures_dir(ROOT_DIR, 'single_viz')
SEARCH_DIRS = [
    os.path.join(ROOT_DIR, 'results', 'batch', 'visualize'),
    os.path.join(ROOT_DIR, 'results', 'batch'),
]

# 任务类型颜色（用于甘特图和子图标题）

FAMILY = 'single_viz'
PLOT_CONFIG = get_family_plot_config(FAMILY)
PLOT_GLOBAL = PLOT_CONFIG['PLOT_GLOBAL']
TEXT_STYLE = PLOT_CONFIG['TEXT_STYLE']
HEATMAP_STYLE = PLOT_CONFIG['HEATMAP_STYLE']
TASK_STYLE = PLOT_CONFIG['TASK_STYLE']
RESOURCE_STYLE = PLOT_CONFIG['RESOURCE_STYLE']
TASK_TYPE_COLOR = TASK_STYLE['colors']
TASK_TYPE_LABEL = TASK_STYLE['labels']
DEFAULT_TASK_COLOR = TASK_STYLE['default_color']
TASK_TITLE_FALLBACK_COLOR = TASK_STYLE['title_fallback_color']
RESOURCE_COLORS = RESOURCE_STYLE['colors']
FIG5A_CONFIG = get_family_figure_config(FAMILY, 'fig5a')
FIG5B_CONFIG = get_family_figure_config(FAMILY, 'fig5b')
FIG5C_CONFIG = get_family_figure_config(FAMILY, 'fig5c')
FIG5D_CONFIG = get_family_figure_config(FAMILY, 'fig5d')
FIG5E_CONFIG = get_family_figure_config(FAMILY, 'fig5e')
FIG5F_CONFIG = get_family_figure_config(FAMILY, 'fig5f')
FIG5G_CONFIG = get_family_figure_config(FAMILY, 'fig5g')
FIG5H_CONFIG = get_family_figure_config(FAMILY, 'fig5h')
FIG5I_CONFIG = get_family_figure_config(FAMILY, 'fig5i')
FIG5J_CONFIG = get_family_figure_config(FAMILY, 'fig5j')
FIG5K_CONFIG = get_family_figure_config(FAMILY, 'fig5k')
FIG5L_CONFIG = get_family_figure_config(FAMILY, 'fig5l')
FIG5M_CONFIG = get_family_figure_config(FAMILY, 'fig5m')
FIG5N_CONFIG = get_family_figure_config(FAMILY, 'fig5n')
os.makedirs(FIGURES_DIR, exist_ok=True)
PLOT_STYLE_ADAPTER = dict(PLOT_GLOBAL)
PLOT_STYLE_ADAPTER['show_grid'] = False
PLOT_STYLE_ADAPTER['show_legend'] = False
STYLE_HELPER = PlotStyleHelper(PLOT_STYLE_ADAPTER, FIGURES_DIR)

def find_mat_file(argv):
    """优先命令行参数，否则在 SEARCH_DIRS 中找最新的 visualize .mat 文件。"""
    if len(argv) > 1:
        p = argv[1]
        if os.path.isfile(p):
            return p
        print(f"警告: 指定的文件不存在 '{p}'，尝试自动搜索。")

    candidates = []
    for d in SEARCH_DIRS:
        candidates.extend(glob.glob(os.path.join(d, '*.mat')))

    viz = [
        f for f in candidates
        if 'visualize' in os.path.basename(f)
        or os.path.join('visualize', '') in f.replace('\\', '/')
    ]
    pool = viz if viz else candidates
    if not pool:
        sys.exit(
            "找不到 .mat 文件，请先运行 Single_Viz.m，或手动指定路径作为命令行参数。"
        )
    chosen = max(pool, key=os.path.getmtime)
    print(f"自动选择: {chosen}")
    return chosen


def to_scalar(val, default=np.nan):
    """将 mat73 返回的各种标量形式统一成 Python float。"""
    if val is None:
        return default
    arr = np.asarray(val, dtype=float).ravel()
    return float(arr[0]) if len(arr) > 0 else default


def to_int(val, default=0):
    v = to_scalar(val, default=float(default))
    return int(round(v)) if not np.isnan(v) else default


def to_1d(val):
    """字段转为 1D float array；输入 None 或空时返回空 array。"""
    if val is None:
        return np.array([])
    arr = np.asarray(val, dtype=float).ravel()
    return arr


def to_2d(val):
    """字段转为 2D float array；1D 输入按列向量处理。"""
    if val is None:
        return np.zeros((1, 1))
    arr = np.asarray(val, dtype=float)
    if arr.ndim == 3 and arr.shape[0] == 1:
        arr = arr[0]
    if arr.ndim == 1:
        arr = arr.reshape(-1, 1)
    return arr


def get_agent_field(struct_dict, field, idx):
    """
    从 mat73 加载的 struct array（dict 形式）中取第 idx 个智能体的 field。

    mat73 加载规则：
      - struct array 大小 1×N（N>1）：field → list of N items
      - struct array 大小 1×1（N=1）：field → 值本身（不包在 list 中）
    """
    if isinstance(struct_dict, list):
        if idx >= len(struct_dict):
            return None
        item = struct_dict[idx]
        if isinstance(item, dict):
            return item.get(field)
        return None

    val = struct_dict.get(field) if struct_dict else None
    if val is None:
        return None
    if isinstance(val, list):
        return val[idx] if idx < len(val) else None
    if isinstance(val, np.ndarray):
        if val.dtype == object:          # object array：每项是一个数组
            return val.flat[idx] if idx < val.size else None
        if idx == 0:                     # N=1 时字段直接是数值/数组
            return val
        return None
    return val   # 标量：直接返回（N=1 情形）


def apply_common_style(ax, xlabel=None, ylabel=None, title=None, cfg=None, legend_kwargs=None):
    STYLE_HELPER.apply_common_style(
        ax,
        cfg=cfg,
        xlabel=xlabel,
        ylabel=ylabel,
        title=title,
        legend_kwargs=legend_kwargs,
    )
    apply_spine_style(ax, cfg=cfg)


def resolve_fontsize(size_key, cfg=None, default=None):
    return STYLE_HELPER.resolve_fontsize(size_key, default=default, cfg=cfg)


def style_legend(legend, cfg=None):
    return STYLE_HELPER.style_legend(legend, cfg=cfg)


def create_single_axis_figure(cfg=None):
    return STYLE_HELPER.create_single_axis_figure(cfg=cfg)


def finalize_and_save(fig, save_path, cfg=None, tight_layout_rect=None):
    merged_cfg = dict(PLOT_GLOBAL)
    if cfg:
        merged_cfg.update(cfg)

    if merged_cfg.get('use_fixed_export_margins', False):
        fig_width_cm = fig.get_figwidth() * 2.54
        fig_height_cm = fig.get_figheight() * 2.54

        left_margin_cm = float(merged_cfg.get('export_margin_left_cm', 1.58))
        right_margin_cm = float(merged_cfg.get('export_margin_right_cm', 1.23))
        bottom_margin_cm = float(merged_cfg.get('export_margin_bottom_cm', 1.17))
        top_margin_cm = float(merged_cfg.get('export_margin_top_cm', 0.26))

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

        fig.subplots_adjust(
            left=left_margin_cm / fig_width_cm,
            right=1.0 - right_margin_cm / fig_width_cm,
            bottom=bottom_margin_cm / fig_height_cm,
            top=1.0 - top_margin_cm / fig_height_cm,
        )
    STYLE_HELPER.finalize_and_save(fig, save_path, tight_layout_rect=tight_layout_rect, cfg=cfg)


def build_output_stem(stem):
    return STYLE_HELPER.build_output_stem(build_prefixed_stem(FAMILY, stem))


def configure_output_dir(mat_path):
    global FIGURES_DIR
    source_name = infer_source_name(mat_path, fallback='visualize')
    FIGURES_DIR = build_results_figures_dir(ROOT_DIR, 'single_viz', source_name)
    os.makedirs(FIGURES_DIR, exist_ok=True)
    STYLE_HELPER.set_figures_dir(FIGURES_DIR)
    return FIGURES_DIR


def apply_plot_rcparams():
    STYLE_HELPER.apply_rcparams()


def apply_spine_style(ax, cfg=None):
    merged_cfg = dict(PLOT_GLOBAL)
    if cfg:
        merged_cfg.update(cfg)

    spine_color = merged_cfg['spine_color']
    spine_linewidth = float(merged_cfg['spine_linewidth'])
    for spine in ax.spines.values():
        spine.set_visible(True)
        spine.set_color(spine_color)
        spine.set_linewidth(spine_linewidth)


def json_safe_data(obj):
    """Recursively convert numpy/NaN values into JSON-safe Python objects."""
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
        value = float(obj)
        return None if (np.isnan(value) or np.isinf(value)) else value
    if isinstance(obj, float):
        return None if (np.isnan(obj) or np.isinf(obj)) else obj
    return obj


def write_plot_data_json(output_path, payload):
    """Write plot-related data to a JSON file."""
    with open(output_path, 'w', encoding='utf-8') as fp:
        json.dump(json_safe_data(payload), fp, ensure_ascii=False, indent=2)
    print(f"  [OK] {output_path}")


def build_curve_endpoint_summary(curve, label):
    """Build first/last actual-iteration summary for a 1D convergence curve."""
    if curve is None:
        return None

    arr = np.asarray(curve, dtype=float).ravel()
    if arr.size == 0:
        return None

    first_value = float(arr[0])
    last_value = float(arr[-1])
    if not (np.isfinite(first_value) and np.isfinite(last_value)):
        return None

    return {
        'label': str(label),
        'first_iteration_index': 1,
        'last_iteration_index': int(arr.size),
        'first_iteration_value': first_value,
        'last_iteration_value': last_value,
    }


def build_convergence_metrics_combined_summary_payload(
    mat_path,
    output_dir,
    convergence_utility,
    convergence_cost,
    convergence_completed_value,
):
    """Build JSON payload for single_viz combined convergence figure endpoints."""
    utility_summary = build_curve_endpoint_summary(
        convergence_utility,
        FIG5M_CONFIG.get('utility_curve_label', 'Coalition Utility'),
    )
    cost_summary = build_curve_endpoint_summary(
        convergence_cost,
        FIG5M_CONFIG.get('cost_curve_label', 'Total Global Cost'),
    )
    completed_value_summary = build_curve_endpoint_summary(
        convergence_completed_value,
        FIG5M_CONFIG.get('completed_value_curve_label', 'Total Completed Value'),
    )

    if utility_summary is None or cost_summary is None or completed_value_summary is None:
        return None

    return {
        'metadata': {
            'source_mat_path': os.path.abspath(mat_path),
            'run_name': infer_source_name(mat_path, fallback='visualize'),
            'output_dir': os.path.abspath(output_dir),
            'round_basis': 'first_actual_iteration_to_last_actual_iteration',
            'note': 'exclude prepended plotting origin at round 0',
        },
        'convergence_utility': utility_summary,
        'convergence_cost': cost_summary,
        'convergence_completed_value': completed_value_summary,
    }


def build_task_type_value_maps(task_info):
    """Build task_id -> type/value lookups from extracted task_info."""
    task_type_map = {}
    task_value_map = {}
    for m in range(task_info['M']):
        tid = int(round(task_info['id'][m]))
        if tid <= 0:
            continue
        task_type_map[tid] = int(round(task_info['type'][m]))
        task_value_map[tid] = to_scalar(task_info['value'][m], default=np.nan)
    return task_type_map, task_value_map


def build_task_id_hue_map(task_ids, hue_offset):
    """Assign a stable hue to each task id without using a short discrete palette."""
    sorted_ids = sorted({int(tid) for tid in task_ids if int(tid) > 0})
    hue_map = {}
    golden_ratio = 0.618033988749895
    for idx, tid in enumerate(sorted_ids):
        hue_map[tid] = (hue_offset + idx * golden_ratio) % 1.0
    return hue_map


def normalize_task_id_color_map(raw_map):
    """Normalize configurable task-id color mappings to int -> str."""
    if not isinstance(raw_map, dict):
        return {}

    normalized = {}
    for raw_key, raw_color in raw_map.items():
        if raw_color is None:
            continue
        try:
            task_id = int(round(float(raw_key)))
        except (TypeError, ValueError):
            continue
        if task_id <= 0:
            continue
        normalized[task_id] = str(raw_color)
    return normalized


def build_value_level_map(task_value_map):
    """Map raw task values to ordered value levels."""
    valid_values = sorted({
        float(v) for v in task_value_map.values()
        if v is not None and np.isfinite(v) and float(v) > 0
    })
    return {val: idx for idx, val in enumerate(valid_values)}, valid_values


def get_value_lightness(level_idx, num_levels, cfg):
    """Convert a value level into an HLS lightness value."""
    light_max = float(cfg['value_lightness_max'])
    light_min = float(cfg['value_lightness_min'])
    if num_levels <= 1 or level_idx is None:
        return 0.5 * (light_max + light_min)

    pos = float(level_idx) / float(num_levels - 1)
    if cfg['value_shade_order'] == 'high_lighter':
        return light_min + pos * (light_max - light_min)
    return light_max - pos * (light_max - light_min)


def make_hls_color(hue, lightness, saturation):
    rgb = colorsys.hls_to_rgb(hue % 1.0, np.clip(lightness, 0.0, 1.0), np.clip(saturation, 0.0, 1.0))
    return to_hex(rgb)


def shift_color_lightness(color, delta):
    """Lighten or darken a color by shifting HLS lightness."""
    r, g, b = to_rgb(color)
    hue, lightness, saturation = colorsys.rgb_to_hls(r, g, b)
    new_lightness = np.clip(lightness + delta, 0.0, 1.0)
    return to_hex(colorsys.hls_to_rgb(hue, new_lightness, saturation))


def get_contrast_text_color(color):
    """Choose white or dark text based on perceived luminance."""
    r, g, b = to_rgb(color)
    luminance = 0.2126 * r + 0.7152 * g + 0.0722 * b
    if luminance < TEXT_STYLE['contrast_luminance_threshold']:
        return TEXT_STYLE['contrast_light_color']
    return TEXT_STYLE['contrast_dark_color']


def get_value_label(level_idx, num_levels, value):
    if num_levels == 1:
        prefix = 'Value'
    elif num_levels == 2:
        prefix = ['Low value', 'High value'][level_idx]
    elif num_levels == 3:
        prefix = ['Low value', 'Med value', 'High value'][level_idx]
    else:
        prefix = f'Value level {level_idx + 1}'

    if value is None or not np.isfinite(value):
        return prefix
    if abs(value - round(value)) < 1e-9:
        return f'{prefix} ({int(round(value))})'
    return f'{prefix} ({value:.2f})'


def resolve_curve_markevery(rounds, cfg):
    """Resolve marker positions from actual round values or legacy markevery."""
    if not cfg:
        return None

    rounds_arr = np.asarray(rounds, dtype=float).ravel()
    if rounds_arr.size == 0:
        return None

    marker_rounds = cfg.get('curve_marker_rounds')
    if marker_rounds is not None:
        targets = np.asarray(marker_rounds, dtype=float).ravel()
        if targets.size == 0:
            return []

        indices = [
            idx for idx, round_value in enumerate(rounds_arr)
            if np.isfinite(round_value)
            and np.any(np.isclose(round_value, targets, rtol=0.0, atol=1e-9))
        ]
        return indices

    step = cfg.get('curve_markevery_step')
    if step is not None:
        try:
            step_value = float(step)
        except (TypeError, ValueError):
            step_value = np.nan

        if np.isfinite(step_value) and step_value > 0:
            indices = []
            for idx, round_value in enumerate(rounds_arr):
                if not np.isfinite(round_value):
                    continue
                remainder = np.mod(round_value, step_value)
                if (
                    np.isclose(remainder, 0.0, rtol=0.0, atol=1e-9)
                    or np.isclose(remainder, step_value, rtol=0.0, atol=1e-9)
                ):
                    indices.append(idx)
            return indices

    return cfg.get('curve_markevery')


def maybe_prepend_origin_zero(rounds, curve, cfg):
    """Optionally prepend an origin point (0, 0) and shift existing rounds right."""
    rounds_arr = np.asarray(rounds, dtype=float).ravel()
    curve_arr = np.asarray(curve, dtype=float).ravel()
    if not cfg or not cfg.get('prepend_origin_zero', False):
        return rounds_arr, curve_arr

    if rounds_arr.size == 0 or curve_arr.size == 0:
        return rounds_arr, curve_arr

    shifted_rounds = rounds_arr.copy()
    if np.isfinite(shifted_rounds[0]) and np.isclose(shifted_rounds[0], 0.0, rtol=0.0, atol=1e-9):
        shifted_rounds = shifted_rounds + 1.0

    rounds_with_origin = np.concatenate(([0.0], shifted_rounds))
    curve_with_origin = np.concatenate(([0.0], curve_arr))
    return rounds_with_origin, curve_with_origin


def build_fig5b_task_style_maps(task_info, cfg):
    """Prepare fill, edge, and text colors for the Fig.5b gantt chart."""
    task_type_map, task_value_map = build_task_type_value_maps(task_info)
    task_ids = list(task_type_map.keys()) or list(task_value_map.keys())
    hue_map = build_task_id_hue_map(task_ids, cfg['task_hue_offset'])
    value_level_map, value_levels = build_value_level_map(task_value_map)
    task_id_colors = normalize_task_id_color_map(cfg.get('task_id_colors'))
    default_color = cfg.get('task_default_color', DEFAULT_TASK_COLOR)
    edge_darken_delta = float(cfg.get('task_edge_darken_delta', -0.14))
    label_color = cfg.get('task_label_color', TEXT_STYLE['contrast_dark_color'])

    fill_color_map = {}
    edge_color_map = {}
    text_color_map = {}
    for tid in sorted(set(task_ids)):
        if cfg['color_mode'] == 'uniform_task':
            color = cfg.get('uniform_task_color', DEFAULT_TASK_COLOR)
        elif cfg['color_mode'] == 'task_type':
            color = TASK_TYPE_COLOR.get(task_type_map.get(tid, 0), DEFAULT_TASK_COLOR)
        elif cfg['color_mode'] == 'task_id_light':
            color = task_id_colors.get(tid)
            if color is None:
                hue = hue_map.get(tid)
                if hue is None:
                    color = default_color
                else:
                    color = make_hls_color(
                        hue,
                        float(cfg.get('task_color_lightness', 0.82)),
                        float(cfg.get('task_color_saturation', 0.32)),
                    )
        else:
            hue = hue_map.get(tid)
            value = task_value_map.get(tid)
            if hue is None:
                color = DEFAULT_TASK_COLOR
            else:
                level_idx = value_level_map.get(float(value)) if value is not None and np.isfinite(value) else None
                lightness = get_value_lightness(level_idx, len(value_levels), cfg)
                color = make_hls_color(hue, lightness, cfg['task_color_saturation'])

        fill_color_map[tid] = color
        edge_color_map[tid] = shift_color_lightness(color, edge_darken_delta)
        text_color_map[tid] = label_color

    return {
        'task_type_map': task_type_map,
        'task_value_map': task_value_map,
        'fill_color_map': fill_color_map,
        'edge_color_map': edge_color_map,
        'text_color_map': text_color_map,
        'value_levels': value_levels,
    }


def build_fig5b_legend_handles(cfg, style_maps, used_types):
    """Create legend handles for either legacy type colors or value shades."""
    if cfg['color_mode'] == 'uniform_task':
        color = cfg.get('uniform_task_color', DEFAULT_TASK_COLOR)
        return [
            mpatches.Patch(
                facecolor=color,
                edgecolor=shift_color_lightness(color, -0.14),
                label=cfg['legend_label'],
            )
        ]

    if cfg['color_mode'] == 'task_id_light':
        color = next(
            iter(style_maps['fill_color_map'].values()),
            cfg.get('task_default_color', DEFAULT_TASK_COLOR),
        )
        return [
            mpatches.Patch(
                facecolor=color,
                edgecolor=shift_color_lightness(color, float(cfg.get('task_edge_darken_delta', -0.14))),
                label=cfg['legend_label'],
            )
        ]

    if cfg['color_mode'] == 'task_type':
        return [
            mpatches.Patch(
                color=TASK_TYPE_COLOR.get(t, DEFAULT_TASK_COLOR),
                label=TASK_TYPE_LABEL.get(t, f'Type {t}')
            )
            for t in sorted(used_types)
        ]

    if not cfg.get('show_value_legend', True):
        return []

    value_levels = style_maps['value_levels']
    if not value_levels:
        return []

    handles = []
    for idx, value in enumerate(value_levels):
        lightness = get_value_lightness(idx, len(value_levels), cfg)
        sample_color = make_hls_color(
            cfg['value_legend_hue'],
            lightness,
            cfg['task_color_saturation'],
        )
        handles.append(
            mpatches.Patch(
                facecolor=sample_color,
                edgecolor=shift_color_lightness(sample_color, -0.14),
                label=get_value_label(idx, len(value_levels), value),
            )
        )
    return handles


# ══════════════════════════════════════════════════════════════════════════════
# 数据提取
# ══════════════════════════════════════════════════════════════════════════════

def extract_sc_matrices(viz_data):
    """
    提取 final_SC：MATLAB cell{M×1} → mat73 list of M arrays, each [N×K]。
    返回: List[np.ndarray]
    """
    sc_raw = viz_data.get('final_SC')
    if sc_raw is None:
        return []

    items = list(sc_raw) if isinstance(sc_raw, np.ndarray) else (
        sc_raw if isinstance(sc_raw, list) else [sc_raw]
    )
    result = []
    for item in items:
        if item is None:
            result.append(np.zeros((1, 1)))
        else:
            while isinstance(item, list) and len(item) == 1:
                item = item[0]
            result.append(to_2d(item))
    return result


def extract_task_info(viz_data, M_hint=0):
    """
    提取任务信息：id / type / value 以及各任务完成度。
    MATLAB struct array → mat73 dict-of-arrays。
    返回 dict: 'id','type','value','degree' 均为 list[float], 'M' 为 int
    """
    tasks   = viz_data.get('tasks') or {}
    degrees = to_1d(viz_data.get('task_completion_degrees'))

    def field_list(name):
        if isinstance(tasks, list):
            vals = []
            for item in tasks:
                if isinstance(item, dict):
                    vals.append(to_scalar(item.get(name)))
            return vals

        val = tasks.get(name) if tasks else None
        if val is None:
            return []
        return np.asarray(val, dtype=float).ravel().tolist()

    ids    = field_list('id')
    types  = field_list('type')
    values = field_list('value')
    priorities = field_list('priority')

    M = max(len(ids), len(degrees), M_hint)
    # 补齐长度
    def pad(lst, length, fill=0.0):
        return lst + [fill] * (length - len(lst))

    ids    = pad(ids,    M, fill=0.0)
    types  = pad(types,  M, fill=0.0)
    values = pad(values, M, fill=0.0)
    priorities = pad(priorities, M, fill=0.0)
    if len(degrees) < M:
        degrees = np.concatenate([degrees, np.full(M - len(degrees), np.nan)])

    return {
        'id': ids,
        'type': types,
        'value': values,
        'priority': priorities,
        'degree': degrees,
        'M': M,
    }


def extract_task_demand_matrix(viz_data, M_hint=0, K_hint=0):
    tasks = viz_data.get('tasks') or {}
    demand_rows = []

    if isinstance(tasks, list):
        for item in tasks:
            if isinstance(item, dict):
                demand_rows.append(to_1d(item.get('resource_demand')))
    else:
        raw = tasks.get('resource_demand') if tasks else None
        if isinstance(raw, list):
            demand_rows = [to_1d(x) for x in raw]
        elif isinstance(raw, np.ndarray) and raw.dtype == object:
            demand_rows = [to_1d(x) for x in raw.flat]
        elif raw is not None:
            arr = np.asarray(raw, dtype=float)
            if arr.ndim == 1:
                demand_rows = [arr]
            elif arr.ndim >= 2:
                demand_rows = [np.asarray(arr[i], dtype=float).ravel() for i in range(arr.shape[0])]

    M = max(M_hint, len(demand_rows))
    K = max(K_hint, max((len(row) for row in demand_rows), default=0))
    demand = np.zeros((M, K))

    for m, row in enumerate(demand_rows[:M]):
        if row.size == 0:
            continue
        demand[m, :min(K, len(row))] = row[:K]

    return demand


def extract_timing(viz_data, N):
    """
    提取每个智能体的时序数据。
    MATLAB struct array(1×N) → mat73 dict-of-lists（或 dict-of-values for N=1）。
    返回: List[dict]，长度 N，每个包含 task_seq, starts, execs, t_fly, t_wait, t_exec
    """
    timing_raw = viz_data.get('timing') or {}
    result = []
    for i in range(N):
        task_seq  = to_1d(get_agent_field(timing_raw, 'task_sequence',    i)).astype(int).tolist()
        starts    = to_1d(get_agent_field(timing_raw, 'start_times',      i)).tolist()
        execs     = to_1d(get_agent_field(timing_raw, 'execution_times',  i)).tolist()
        completions = to_1d(get_agent_field(timing_raw, 'completion_times', i)).tolist()
        t_fly     = to_scalar(get_agent_field(timing_raw, 't_fly_total',  i), default=0.0)
        t_wait    = to_scalar(get_agent_field(timing_raw, 't_wait_total', i), default=0.0)
        t_exec    = to_scalar(get_agent_field(timing_raw, 't_exec_total', i), default=0.0)

        L = min(len(task_seq), len(starts), len(execs))
        ends = []
        for idx in range(L):
            if idx < len(completions):
                completion_time = float(completions[idx])
                if np.isfinite(completion_time):
                    ends.append(completion_time)
                    continue

            start_time = float(starts[idx])
            exec_time = float(execs[idx])
            if np.isfinite(start_time) and np.isfinite(exec_time):
                ends.append(start_time + exec_time)
            else:
                ends.append(np.nan)

        result.append({
            'task_seq': task_seq[:L],
            'starts':   starts[:L],
            'execs':    execs[:L],
            'ends':     ends,
            't_fly':    t_fly,
            't_wait':   t_wait,
            't_exec':   t_exec,
        })
    return result


def build_task_metadata_lookup(task_info):
    lookup = {}
    task_ids = np.asarray((task_info or {}).get('id', []), dtype=float).ravel()
    task_types = np.asarray((task_info or {}).get('type', []), dtype=float).ravel()
    task_values = np.asarray((task_info or {}).get('value', []), dtype=float).ravel()
    task_priorities = np.asarray((task_info or {}).get('priority', []), dtype=float).ravel()
    task_degrees = np.asarray((task_info or {}).get('degree', []), dtype=float).ravel()
    task_count = max(
        int((task_info or {}).get('M', 0)),
        task_ids.size,
        task_types.size,
        task_values.size,
        task_priorities.size,
        task_degrees.size,
    )

    for idx in range(task_count):
        task_id_val = task_ids[idx] if idx < task_ids.size else np.nan
        if np.isfinite(task_id_val) and int(round(task_id_val)) > 0:
            task_id = int(round(task_id_val))
        else:
            task_id = idx + 1

        task_type = task_types[idx] if idx < task_types.size else np.nan
        task_value = task_values[idx] if idx < task_values.size else np.nan
        task_priority = task_priorities[idx] if idx < task_priorities.size else np.nan
        completion_degree = task_degrees[idx] if idx < task_degrees.size else np.nan

        lookup[task_id] = {
            'task_id': task_id,
            'task_label': f'T{task_id}',
            'task_type': to_int(task_type, default=0),
            'task_value': to_scalar(task_value, default=np.nan),
            'task_priority': to_scalar(task_priority, default=np.nan),
            'completion_degree': to_scalar(completion_degree, default=np.nan),
        }

    return lookup


def sanitize_matrix_row(row_values, width):
    row = np.zeros(int(width), dtype=float)
    src = to_1d(row_values)
    if src.size > 0:
        row[:min(int(width), src.size)] = src[:int(width)]
    row[~np.isfinite(row)] = 0.0
    return row


def compact_numeric_value(value):
    numeric = to_scalar(value, default=np.nan)
    if not np.isfinite(numeric):
        return None
    if abs(numeric - round(numeric)) < 1e-9:
        return int(round(numeric))
    return float(numeric)


def vector_to_compact_list(values):
    return [compact_numeric_value(v) for v in np.asarray(values, dtype=float).ravel()]


def vector_to_bracketed_text(values):
    parts = []
    for value in np.asarray(values, dtype=float).ravel():
        if not np.isfinite(value):
            parts.append('null')
        elif abs(value - round(value)) < 1e-9:
            parts.append(str(int(round(value))))
        else:
            parts.append(f'{value:.3f}'.rstrip('0').rstrip('.'))
    return '[' + ','.join(parts) + ']'


def format_time_text(value):
    numeric = to_scalar(value, default=np.nan)
    if not np.isfinite(numeric):
        return '--'
    return f'{numeric:.1f}'


def format_percent_text(value):
    numeric = to_scalar(value, default=np.nan)
    if not np.isfinite(numeric):
        return '--'
    return f'{numeric * 100:.1f}%'


def build_fig5_agent_task_schedule_table_payload(
    mat_path,
    sc_list,
    demand_mat,
    task_info,
    timing_list,
    agent_layout,
    N,
    M,
    K,
    output_dir,
):
    task_meta_lookup = build_task_metadata_lookup(task_info)
    task_ids_arr = np.asarray((task_info or {}).get('id', []), dtype=float).ravel()
    task_count = max(int(M), len(sc_list), demand_mat.shape[0], int((task_info or {}).get('M', 0)))
    task_index_map = {}

    for idx in range(task_count):
        task_id_val = task_ids_arr[idx] if idx < task_ids_arr.size else np.nan
        task_id = int(round(task_id_val)) if np.isfinite(task_id_val) and int(round(task_id_val)) > 0 else idx + 1
        task_index_map[task_id] = idx
        task_meta_lookup.setdefault(task_id, {
            'task_id': task_id,
            'task_label': f'T{task_id}',
            'task_type': 0,
            'task_value': np.nan,
            'task_priority': np.nan,
            'completion_degree': np.nan,
        })

    ordered_task_ids = sorted(
        task_index_map.keys(),
        key=lambda task_id: (
            -to_scalar(task_meta_lookup[task_id].get('task_priority'), default=-np.inf),
            int(task_id),
        ),
    )

    resource_labels = [f'R{resource_id}' for resource_id in range(1, int(K) + 1)]
    columns = []
    demand_summary = []
    allocated_summary = []
    completion_summary = []
    sc_by_task = {}

    for task_id in ordered_task_ids:
        task_idx = task_index_map[task_id]
        task_meta = task_meta_lookup[task_id]
        task_value = compact_numeric_value(task_meta.get('task_value'))
        task_priority = compact_numeric_value(task_meta.get('task_priority'))
        sc = to_2d(sc_list[task_idx]) if task_idx < len(sc_list) else np.zeros((0, 0))
        alloc_matrix = np.zeros((int(N), int(K)), dtype=float)
        if sc.size > 0:
            rows = min(int(N), sc.shape[0])
            cols = min(int(K), sc.shape[1])
            alloc_matrix[:rows, :cols] = sc[:rows, :cols]
        sc_by_task[task_id] = alloc_matrix

        demand_vector = sanitize_matrix_row(demand_mat[task_idx] if task_idx < demand_mat.shape[0] else None, K)
        allocated_vector = alloc_matrix.sum(axis=0)
        completion_value = to_scalar(task_meta.get('completion_degree'), default=np.nan)

        columns.append({
            'task_id': int(task_id),
            'task_label': task_meta['task_label'],
            'task_priority': task_priority,
            'task_value': task_value,
            'header_text': f"{task_meta['task_label']} (P{task_priority}, V{task_value})",
        })
        demand_summary.append({
            'task_id': int(task_id),
            'task_label': task_meta['task_label'],
            'vector': vector_to_compact_list(demand_vector),
            'text': vector_to_bracketed_text(demand_vector),
        })
        allocated_summary.append({
            'task_id': int(task_id),
            'task_label': task_meta['task_label'],
            'vector': vector_to_compact_list(allocated_vector),
            'text': vector_to_bracketed_text(allocated_vector),
        })
        completion_summary.append({
            'task_id': int(task_id),
            'task_label': task_meta['task_label'],
            'value': completion_value,
            'text': format_percent_text(completion_value),
        })

    agent_count = max(int(N), len(timing_list), int((agent_layout or {}).get('count', 0)))
    agent_resources = np.asarray((agent_layout or {}).get('resources', np.zeros((0, 0))), dtype=float)
    agents_payload = []

    for agent_idx in range(agent_count):
        if agent_layout is not None and agent_idx < int(agent_layout.get('count', 0)):
            agent_id_val = agent_layout['id'][agent_idx]
            agent_id = int(round(agent_id_val)) if np.isfinite(agent_id_val) else agent_idx + 1
        else:
            agent_id = agent_idx + 1

        capacity_vector = sanitize_matrix_row(
            agent_resources[agent_idx] if agent_idx < agent_resources.shape[0] else None,
            K,
        )

        timing = timing_list[agent_idx] if agent_idx < len(timing_list) else {
            'task_seq': [],
            'starts': [],
            'execs': [],
            'ends': [],
        }
        task_schedule = {}
        task_count_local = min(
            len(timing.get('task_seq', [])),
            len(timing.get('starts', [])),
            len(timing.get('execs', [])),
            len(timing.get('ends', [])),
        )
        for task_pos in range(task_count_local):
            task_id = int(round(timing['task_seq'][task_pos]))
            if task_id <= 0 or task_id in task_schedule:
                continue
            task_schedule[task_id] = {
                'start_time': timing['starts'][task_pos],
                'end_time': timing['ends'][task_pos],
                'execution_time': timing['execs'][task_pos],
            }

        cells = []
        for task_id in ordered_task_ids:
            alloc_matrix = sc_by_task.get(task_id, np.zeros((int(N), int(K)), dtype=float))
            alloc_vector_raw = sanitize_matrix_row(
                alloc_matrix[agent_idx] if agent_idx < alloc_matrix.shape[0] else None,
                K,
            )
            schedule_item = task_schedule.get(task_id)
            has_allocation = bool(np.any(np.abs(alloc_vector_raw) > 1e-9))
            executed = schedule_item is not None or has_allocation

            start_time = to_scalar(schedule_item.get('start_time'), default=np.nan) if schedule_item else np.nan
            end_time = to_scalar(schedule_item.get('end_time'), default=np.nan) if schedule_item else np.nan
            execution_time = to_scalar(schedule_item.get('execution_time'), default=np.nan) if schedule_item else np.nan

            cells.append({
                'task_id': int(task_id),
                'executed': bool(executed),
                'allocation_vector_raw': vector_to_compact_list(alloc_vector_raw),
                'allocation_vector': vector_to_compact_list(alloc_vector_raw) if executed else None,
                'allocation_text': vector_to_bracketed_text(alloc_vector_raw) if executed else '--',
                'start_time': start_time if np.isfinite(start_time) else None,
                'end_time': end_time if np.isfinite(end_time) else None,
                'execution_time': execution_time if np.isfinite(execution_time) else None,
                'start_text': format_time_text(start_time),
                'end_text': format_time_text(end_time),
            })

        agents_payload.append({
            'agent_id': int(agent_id),
            'agent_label': f'A{agent_id}',
            'capacity_vector': vector_to_compact_list(capacity_vector),
            'capacity_text_plain': ','.join(str(v) for v in vector_to_compact_list(capacity_vector)),
            'capacity_text_bracketed': vector_to_bracketed_text(capacity_vector),
            'cells': cells,
        })

    return {
        'source_mat_path': os.path.abspath(mat_path),
        'output_dir': os.path.abspath(output_dir),
        'dimensions': {
            'N': int(N),
            'M': int(M),
            'K': int(K),
        },
        'table': {
            'name': 'agent_task_schedule_with_carry_demand',
            'task_order_rule': 'priority_desc_then_task_id_asc',
            'resource_labels': resource_labels,
            'columns': columns,
            'agents': agents_payload,
            'summary_rows': {
                'demand': demand_summary,
                'allocated': allocated_summary,
                'completion': completion_summary,
            },
        },
    }


def build_total_allocation_matrix(sc_list, K_hint=0):
    M = len(sc_list)
    K = max(K_hint, max((sc.shape[1] for sc in sc_list if sc.ndim >= 2), default=0))
    alloc = np.zeros((M, K))

    for m, sc in enumerate(sc_list):
        sc2 = to_2d(sc)
        if sc2.size == 0:
            continue
        row = sc2.sum(axis=0).ravel()
        alloc[m, :min(K, len(row))] = row[:K]

    return alloc


def build_fulfillment_ratio_matrix(alloc_mat, demand_mat):
    M = min(alloc_mat.shape[0], demand_mat.shape[0])
    K = min(alloc_mat.shape[1], demand_mat.shape[1])
    ratio = np.full((M, K), np.nan)

    for m in range(M):
        for k in range(K):
            demand = demand_mat[m, k]
            alloc = alloc_mat[m, k]
            if demand > 1e-9:
                ratio[m, k] = alloc / demand

    return ratio


def get_nested_field(data, *keys, default=None):
    current = data
    for key in keys:
        if not isinstance(current, dict):
            return default
        current = current.get(key)
        if current is None:
            return default
    return current


def format_numeric_vector(values, max_items=12, precision=2):
    arr = to_1d(values)
    if arr.size == 0:
        return '[]'

    parts = []
    for value in arr[:max_items]:
        if not np.isfinite(value):
            parts.append('nan')
        elif abs(value - round(value)) < 1e-9:
            parts.append(str(int(round(value))))
        else:
            parts.append(f'{value:.{precision}f}')

    if arr.size > max_items:
        parts.append('...')
    return '[' + ' '.join(parts) + ']'


def format_scalar_value(value, precision=3):
    if isinstance(value, (bool, np.bool_)):
        return 'True' if value else 'False'

    arr = np.asarray(value).ravel() if value is not None else np.array([])
    if arr.size == 1:
        try:
            numeric = float(arr[0])
        except (TypeError, ValueError):
            return str(arr[0])
        if not np.isfinite(numeric):
            return 'N/A'
        if abs(numeric - round(numeric)) < 1e-9:
            return str(int(round(numeric)))
        return f'{numeric:.{precision}f}'

    if isinstance(value, str):
        return value
    return format_numeric_vector(value, precision=precision)


def print_exp_params_snapshot(snapshot):
    if not isinstance(snapshot, dict) or not snapshot:
        return

    source = get_nested_field(snapshot, 'source', default={}) or {}
    effective = get_nested_field(snapshot, 'effective_run', default={}) or {}
    scenario_cfg = get_nested_field(snapshot, 'effective_run', 'scenario_cfg', default={}) or {}
    add_para = get_nested_field(snapshot, 'effective_run', 'AddPara', default={}) or {}
    value_params = get_nested_field(snapshot, 'effective_run', 'Value_Params', default={}) or {}

    exp_name = source.get('experiment_name') or 'Unknown'
    script_name = os.path.basename(str(source.get('experiment_script', ''))) if source.get('experiment_script') else ''
    algorithm_name = effective.get('algorithm_name')

    print("\n参数快照:")
    if script_name:
        print(f"  experiment           = {exp_name}  ({script_name})")
    else:
        print(f"  experiment           = {exp_name}")
    if algorithm_name:
        print(f"  algorithm            = {algorithm_name}")

    run_parts = []
    for key in ('N', 'M', 'K', 'seed'):
        if key in effective:
            run_parts.append(f"{key}={format_scalar_value(effective.get(key), precision=0)}")
    if run_parts:
        print(f"  effective_run        = {'  '.join(run_parts)}")

    runtime_parts = []
    for key in ('num_rounds', 'max_inner_iter', 'obs_times', 'num_task_types'):
        if key in effective:
            runtime_parts.append(f"{key}={format_scalar_value(effective.get(key), precision=0)}")
    if 'resource_confidence' in value_params:
        runtime_parts.append(
            f"resource_confidence={format_scalar_value(value_params.get('resource_confidence'))}"
        )
    if runtime_parts:
        print(f"  runtime              = {', '.join(runtime_parts)}")

    addpara_parts = []
    for key in ('enable_belief_update', 'control', 'demand_estimation_mode', 'demand_rounding_mode'):
        if key in add_para:
            addpara_parts.append(f"{key}={format_scalar_value(add_para.get(key))}")
    if addpara_parts:
        print(f"  AddPara              = {', '.join(addpara_parts)}")

    if isinstance(scenario_cfg, dict):
        if 'task_values' in scenario_cfg:
            print(f"  task_values          = {format_numeric_vector(scenario_cfg.get('task_values'), precision=0)}")
        if 'task_type_demand_max' in scenario_cfg:
            print(f"  task_type_demand_max = {format_numeric_vector(scenario_cfg.get('task_type_demand_max'), precision=0)}")

    ocf_keys = (
        'OCF_T0_round', 'OCF_alpha', 'OCF_Tmin', 'OCF_T_decay',
        'OCF_T_min_round', 'OCF_T_init_construction',
        'OCF_K_stable_max', 'OCF_tabu_tenure', 'OCF_p_leave'
    )
    ocf_parts = []
    for key in ocf_keys:
        if key in value_params:
            ocf_parts.append(f"{key}={format_scalar_value(value_params.get(key))}")
    if ocf_parts:
        print(f"  OCF params           = {', '.join(ocf_parts)}")


def struct_field_list(struct_data, field):
    if isinstance(struct_data, list):
        return [item.get(field) if isinstance(item, dict) else None for item in struct_data]

    if isinstance(struct_data, dict):
        raw = struct_data.get(field)
        if raw is None:
            return []
        if isinstance(raw, list):
            return raw
        if isinstance(raw, np.ndarray) and raw.dtype == object:
            return list(raw.flat)
        return [raw]

    return []


def get_struct_length(struct_data):
    if isinstance(struct_data, list):
        return len(struct_data)
    if isinstance(struct_data, dict):
        max_len = 0
        for value in struct_data.values():
            if isinstance(value, list):
                max_len = max(max_len, len(value))
            elif isinstance(value, np.ndarray) and value.dtype == object:
                max_len = max(max_len, value.size)
            elif value is not None:
                max_len = max(max_len, 1)
        return max_len
    return 0


def extract_agent_layout(viz_data, N_hint=0):
    agents = viz_data.get('agents') or {}
    count = max(N_hint, get_struct_length(agents))
    ids = np.arange(1, count + 1, dtype=int)
    xs = np.full(count, np.nan, dtype=float)
    ys = np.full(count, np.nan, dtype=float)
    resource_rows = []

    for idx in range(count):
        ids[idx] = to_int(get_agent_field(agents, 'id', idx), default=idx + 1)
        xs[idx] = to_scalar(get_agent_field(agents, 'x', idx))
        ys[idx] = to_scalar(get_agent_field(agents, 'y', idx))
        resource_rows.append(to_1d(get_agent_field(agents, 'resources', idx)))

    resource_dim = max((row.size for row in resource_rows), default=0)
    resources = np.zeros((count, resource_dim), dtype=float)
    for idx, row in enumerate(resource_rows):
        if row.size > 0:
            resources[idx, :min(resource_dim, row.size)] = row[:resource_dim]

    return {'id': ids, 'x': xs, 'y': ys, 'resources': resources, 'count': count}


def extract_task_layout(viz_data, M_hint=0):
    tasks = viz_data.get('tasks') or {}
    count = max(M_hint, get_struct_length(tasks))
    ids = np.arange(1, count + 1, dtype=int)
    xs = np.full(count, np.nan, dtype=float)
    ys = np.full(count, np.nan, dtype=float)
    types = np.full(count, np.nan, dtype=float)
    values = np.full(count, np.nan, dtype=float)

    id_vals = struct_field_list(tasks, 'id')
    x_vals = struct_field_list(tasks, 'x')
    y_vals = struct_field_list(tasks, 'y')
    type_vals = struct_field_list(tasks, 'type')
    value_vals = struct_field_list(tasks, 'value')

    for idx in range(count):
        if idx < len(id_vals):
            ids[idx] = to_int(id_vals[idx], default=idx + 1)
        if idx < len(x_vals):
            xs[idx] = to_scalar(x_vals[idx])
        if idx < len(y_vals):
            ys[idx] = to_scalar(y_vals[idx])
        if idx < len(type_vals):
            types[idx] = to_scalar(type_vals[idx])
        if idx < len(value_vals):
            values[idx] = to_scalar(value_vals[idx])

    return {'id': ids, 'x': xs, 'y': ys, 'type': types, 'value': values, 'count': count}


def extract_world_bounds(viz_data, agent_layout=None, task_layout=None, cfg=None):
    bounds = viz_data.get('world_bounds')
    if isinstance(bounds, dict):
        xmin = to_scalar(bounds.get('xmin'))
        xmax = to_scalar(bounds.get('xmax'))
        ymin = to_scalar(bounds.get('ymin'))
        ymax = to_scalar(bounds.get('ymax'))
        if np.all(np.isfinite([xmin, xmax, ymin, ymax])):
            return xmin, xmax, ymin, ymax

    world = viz_data.get('world')
    if isinstance(world, dict):
        xmin = to_scalar(world.get('XMIN'))
        xmax = to_scalar(world.get('XMAX'))
        ymin = to_scalar(world.get('YMIN'))
        ymax = to_scalar(world.get('YMAX'))
        if np.all(np.isfinite([xmin, xmax, ymin, ymax])):
            return xmin, xmax, ymin, ymax

    xs = []
    ys = []
    if agent_layout is not None:
        xs.extend(agent_layout['x'][np.isfinite(agent_layout['x'])].tolist())
        ys.extend(agent_layout['y'][np.isfinite(agent_layout['y'])].tolist())
    if task_layout is not None:
        xs.extend(task_layout['x'][np.isfinite(task_layout['x'])].tolist())
        ys.extend(task_layout['y'][np.isfinite(task_layout['y'])].tolist())

    if not xs or not ys:
        return None

    xmin = min(xs)
    xmax = max(xs)
    ymin = min(ys)
    ymax = max(ys)
    margin_x = max(1.0, (xmax - xmin) * float((cfg or {}).get('x_margin_ratio', 0.05)))
    margin_y = max(1.0, (ymax - ymin) * float((cfg or {}).get('y_margin_ratio', 0.05)))
    if xmin == xmax:
        xmin -= 1.0
        xmax += 1.0
    if ymin == ymax:
        ymin -= 1.0
        ymax += 1.0
    return xmin - margin_x, xmax + margin_x, ymin - margin_y, ymax + margin_y


def extract_algorithm_display_name(viz_data):
    algorithm_name = viz_data.get('algorithm_name')
    if algorithm_name is None:
        algorithm_name = get_nested_field(viz_data.get('exp_params_snapshot'), 'effective_run', 'algorithm_name')
    if algorithm_name is None:
        algorithm_name = 'OCF_SAtabu'
    return get_alg_display_name(algorithm_name)


def extract_task_type_values(viz_data, task_info):
    raw = viz_data.get('task_type_values')
    values = to_1d(raw)
    if values.size > 0:
        return values[np.isfinite(values)]

    snap_values = to_1d(get_nested_field(viz_data.get('exp_params_snapshot'), 'effective_run', 'scenario_cfg', 'task_values'))
    if snap_values.size > 0:
        return snap_values[np.isfinite(snap_values)]

    task_types = np.asarray(task_info.get('type', []), dtype=float).ravel()
    task_values = np.asarray(task_info.get('value', []), dtype=float).ravel()
    valid = np.isfinite(task_types) & np.isfinite(task_values) & (task_types >= 1)
    if not np.any(valid):
        return np.array([])

    max_type = int(np.nanmax(task_types[valid]))
    inferred = np.full(max_type, np.nan, dtype=float)
    for task_type, task_value in zip(task_types[valid].astype(int), task_values[valid]):
        if np.isnan(inferred[task_type - 1]):
            inferred[task_type - 1] = task_value
    return inferred


def normalize_init_belief_tensor(init_b_raw, n_agents, n_tasks, n_types):
    default = np.full((n_agents, n_tasks, n_types), 1.0 / max(n_types, 1), dtype=float)
    if init_b_raw is None:
        return default

    try:
        init_b = np.asarray(init_b_raw, dtype=float)
    except Exception:
        return default

    if init_b.ndim == 4 and init_b.shape[0] == 1:
        init_b = init_b[0]

    tensor = None
    if init_b.shape == (n_agents, n_tasks, n_types):
        tensor = init_b
    elif init_b.shape == (n_tasks, n_agents, n_types):
        tensor = np.transpose(init_b, (1, 0, 2))
    elif init_b.shape == (n_agents, n_types, n_tasks):
        tensor = np.transpose(init_b, (0, 2, 1))
    elif init_b.shape == (n_tasks, n_types, n_agents):
        tensor = np.transpose(init_b, (2, 0, 1))
    elif init_b.shape == (n_types, n_agents, n_tasks):
        tensor = np.transpose(init_b, (1, 2, 0))
    elif init_b.shape == (n_types, n_tasks, n_agents):
        tensor = np.transpose(init_b, (2, 1, 0))
    elif init_b.ndim == 2:
        if init_b.shape == (n_agents, n_types):
            tensor = np.repeat(init_b[:, np.newaxis, :], n_tasks, axis=1)
        elif init_b.shape == (n_types, n_agents):
            tensor = np.repeat(init_b.T[:, np.newaxis, :], n_tasks, axis=1)

    if tensor is None:
        return default

    fixed = default.copy()
    agent_count = min(n_agents, tensor.shape[0])
    task_count = min(n_tasks, tensor.shape[1])
    type_count = min(n_types, tensor.shape[2])
    fixed[:agent_count, :task_count, :type_count] = tensor[:agent_count, :task_count, :type_count]
    return fixed


def normalize_belief_history(history_raw, n_agents, n_tasks):
    if history_raw is None:
        return None

    try:
        history = np.asarray(history_raw, dtype=float)
    except Exception:
        return None

    if history.ndim == 5 and history.shape[0] == 1:
        history = history[0]
    if history.ndim != 4:
        return None

    for perm in (
        (0, 1, 2, 3),
        (0, 2, 1, 3),
        (0, 1, 3, 2),
        (0, 2, 3, 1),
        (0, 3, 1, 2),
        (0, 3, 2, 1),
    ):
        candidate = history if perm == (0, 1, 2, 3) else np.transpose(history, perm)
        if candidate.shape[1] == n_agents and candidate.shape[2] == n_tasks:
            return candidate

    return None


def build_belief_value_payload(viz_data, task_info, N, M):
    history_raw = viz_data.get('belief_history')
    if history_raw is None:
        print('  ! skip fig5h/fig5i: belief_history not found in viz_data')
        return None

    task_type_values = extract_task_type_values(viz_data, task_info)
    if task_type_values.size == 0:
        print('  ! skip fig5h/fig5i: task_type_values not found in viz_data')
        return None

    n_agents = max(1, int(N))
    n_tasks = max(1, int(M))
    history = normalize_belief_history(history_raw, n_agents, n_tasks)
    if history is None:
        print('  ! skip fig5h/fig5i: belief_history shape is invalid')
        return None

    init_tensor = normalize_init_belief_tensor(
        viz_data.get('init_belief_tensor'),
        n_agents,
        n_tasks,
        history.shape[3],
    )

    common_types = min(init_tensor.shape[2], history.shape[3], task_type_values.size)
    if common_types <= 0:
        print('  ! skip fig5h/fig5i: no valid belief/value dimensions')
        return None

    init_tensor = init_tensor[:, :, :common_types]
    history = history[:, :, :, :common_types]
    task_type_values = task_type_values[:common_types]

    beliefs = np.concatenate([init_tensor[np.newaxis, :, :, :], history], axis=0)
    expected_values = np.tensordot(beliefs, task_type_values, axes=([3], [0]))

    true_task_values = np.asarray(task_info.get('value', []), dtype=float).ravel()
    if true_task_values.size < n_tasks:
        true_task_values = np.pad(true_task_values, (0, n_tasks - true_task_values.size), constant_values=np.nan)
    else:
        true_task_values = true_task_values[:n_tasks]

    mean_expected_values = np.nanmean(expected_values, axis=1)
    value_error = np.nanmean(
        np.abs(expected_values - true_task_values[np.newaxis, np.newaxis, :]),
        axis=(1, 2),
    )

    return {
        'rounds': np.arange(beliefs.shape[0], dtype=int),
        'mean_expected_values': mean_expected_values,
        'true_task_values': true_task_values,
        'value_error': value_error,
    }


def extract_curve_1d(viz_data, field_name):
    curve = to_1d(viz_data.get(field_name))
    if curve.size == 0:
        return None
    if not np.any(np.isfinite(curve)):
        return None
    return curve


def build_task_position_map(task_layout):
    task_map = {}
    for idx in range(task_layout['count']):
        x_val = task_layout['x'][idx]
        y_val = task_layout['y'][idx]
        if not np.all(np.isfinite([x_val, y_val])):
            continue

        task_id = task_layout['id'][idx]
        if np.isfinite(task_id):
            task_key = int(round(task_id))
        else:
            task_key = idx + 1
        task_map[task_key] = (float(x_val), float(y_val))
    return task_map


def apply_spatial_axis_limits(ax, cfg, world_bounds):
    configured_xlim = cfg.get('xlim')
    configured_ylim = cfg.get('ylim')

    if configured_xlim is not None:
        ax.set_xlim(*configured_xlim)
    elif world_bounds is not None:
        xmin, xmax, _, _ = world_bounds
        ax.set_xlim(xmin, xmax)

    if configured_ylim is not None:
        ax.set_ylim(*configured_ylim)
    elif world_bounds is not None:
        _, _, ymin, ymax = world_bounds
        ax.set_ylim(ymin, ymax)


def build_spatial_legend_handles(cfg):
    return [
        Line2D(
            [0], [0],
            marker=cfg['agent_marker'],
            color='none',
            markerfacecolor=cfg['agent_palette'][0],
            markeredgecolor=cfg['agent_edgecolor'],
            markersize=np.sqrt(cfg['agent_markersize']),
            label=cfg['agent_legend_label'],
        ),
        Line2D(
            [0], [0],
            marker=cfg['task_marker'],
            color='none',
            markerfacecolor=cfg['task_color'],
            markeredgecolor=cfg['task_edgecolor'],
            markersize=np.sqrt(cfg['task_markersize']),
            label=cfg['task_legend_label'],
        ),
    ]


def draw_spatial_layout(ax, agent_layout, task_layout, cfg):
    agent_palette = cfg['agent_palette']
    task_color = cfg['task_color']
    agent_mask = np.isfinite(agent_layout['x']) & np.isfinite(agent_layout['y'])
    task_mask = np.isfinite(task_layout['x']) & np.isfinite(task_layout['y'])

    for idx in np.where(agent_mask)[0]:
        agent_color = agent_palette[idx % len(agent_palette)]
        ax.scatter(
            agent_layout['x'][idx],
            agent_layout['y'][idx],
            s=cfg['agent_markersize'],
            marker=cfg['agent_marker'],
            color=agent_color,
            edgecolors=cfg['agent_edgecolor'],
            linewidths=cfg['agent_scatter_linewidth'],
            zorder=3,
        )

    for idx in np.where(task_mask)[0]:
        ax.scatter(
            task_layout['x'][idx],
            task_layout['y'][idx],
            s=cfg['task_markersize'],
            marker=cfg['task_marker'],
            color=task_color,
            edgecolors=cfg['task_edgecolor'],
            linewidths=cfg['task_scatter_linewidth'],
            zorder=3,
        )

    if cfg.get('annotate_agents', False):
        for idx in np.where(agent_mask)[0]:
            ax.text(
                agent_layout['x'][idx] + cfg['annotation_dx'],
                agent_layout['y'][idx] + cfg['annotation_dy'],
                f"A{agent_layout['id'][idx]}",
                fontsize=cfg['annotation_fontsize'],
                color=agent_palette[idx % len(agent_palette)],
                zorder=4,
            )

    if cfg.get('annotate_tasks', False):
        for idx in np.where(task_mask)[0]:
            ax.text(
                task_layout['x'][idx] + cfg['annotation_dx'],
                task_layout['y'][idx] + cfg['annotation_dy'],
                f"T{task_layout['id'][idx]}",
                fontsize=cfg['annotation_fontsize'],
                color=cfg['task_edgecolor'],
                zorder=4,
            )


def draw_scheduled_path(ax, points, color, cfg):
    if len(points) < 2:
        return

    point_arr = np.asarray(points, dtype=float)
    path_style = str(cfg.get('path_style', 'arrow')).strip().lower()
    linestyle = str(cfg.get('path_linestyle', '-')).strip() or '-'
    linewidth = float(cfg.get('path_linewidth', 1.5))
    alpha = float(cfg.get('path_alpha', 0.85))

    if path_style == 'polyline':
        ax.plot(
            point_arr[:, 0],
            point_arr[:, 1],
            color=color,
            linestyle=linestyle,
            linewidth=linewidth,
            alpha=alpha,
            zorder=2,
        )
        return

    mutation_scale = float(cfg.get('arrow_scale', 12.0))
    arrowstyle = str(cfg.get('path_arrowstyle', '-|>')).strip() or '-|>'
    for start, end in zip(point_arr[:-1], point_arr[1:]):
        if not np.all(np.isfinite(start)) or not np.all(np.isfinite(end)):
            continue
        if np.hypot(*(end - start)) <= 1e-9:
            continue
        ax.add_patch(
            mpatches.FancyArrowPatch(
                tuple(start),
                tuple(end),
                arrowstyle=arrowstyle,
                mutation_scale=mutation_scale,
                linestyle=linestyle,
                linewidth=linewidth,
                color=color,
                alpha=alpha,
                shrinkA=0.0,
                shrinkB=0.0,
                zorder=2,
            )
        )


def plot_fig5g_initial_layout(agent_layout, task_layout, world_bounds, save_path):
    cfg = FIG5G_CONFIG
    if agent_layout['count'] == 0 or task_layout['count'] == 0:
        print('  ! skip fig5g: agent/task layout data is empty')
        return

    fig, ax = create_single_axis_figure(cfg)
    draw_spatial_layout(ax, agent_layout, task_layout, cfg)
    apply_spatial_axis_limits(ax, cfg, world_bounds)

    if cfg.get('aspect_equal', False):
        ax.set_aspect('equal', adjustable='box')

    legend_handles = build_spatial_legend_handles(cfg)

    apply_common_style(
        ax,
        cfg=cfg,
        legend_kwargs={'handles': legend_handles, 'labels': [h.get_label() for h in legend_handles]},
    )
    finalize_and_save(fig, save_path, cfg=cfg)


def plot_fig5n_scheduled_paths(agent_layout, task_layout, timing_list, world_bounds, save_path):
    cfg = FIG5N_CONFIG
    if agent_layout['count'] == 0 or task_layout['count'] == 0:
        print('  ! skip fig5n: agent/task layout data is empty')
        return

    fig, ax = create_single_axis_figure(cfg)
    task_position_map = build_task_position_map(task_layout)
    agent_palette = cfg['agent_palette']
    num_agents = min(agent_layout['count'], len(timing_list))

    for idx in range(num_agents):
        start_x = agent_layout['x'][idx]
        start_y = agent_layout['y'][idx]
        if not np.all(np.isfinite([start_x, start_y])):
            continue

        points = [(float(start_x), float(start_y))]
        for task_id in timing_list[idx].get('task_seq', []):
            task_pos = task_position_map.get(int(round(task_id)))
            if task_pos is None:
                continue
            points.append(task_pos)

        draw_scheduled_path(ax, points, agent_palette[idx % len(agent_palette)], cfg)

    draw_spatial_layout(ax, agent_layout, task_layout, cfg)
    apply_spatial_axis_limits(ax, cfg, world_bounds)

    if cfg.get('aspect_equal', False):
        ax.set_aspect('equal', adjustable='box')

    plot_cfg = dict(cfg)
    legend_kwargs = None
    if cfg.get('show_path_legend', True):
        legend_handles = build_spatial_legend_handles(cfg)
        legend_kwargs = {'handles': legend_handles, 'labels': [h.get_label() for h in legend_handles]}
    else:
        plot_cfg['show_legend'] = False

    apply_common_style(ax, cfg=plot_cfg, legend_kwargs=legend_kwargs)
    finalize_and_save(fig, save_path, cfg=cfg)


def plot_fig5h_expected_task_value(payload, task_layout, save_path):
    cfg = FIG5H_CONFIG
    subplot_cfg = dict(cfg)
    subplot_cfg['show_legend'] = False
    if cfg.get('use_shared_ylabel', False):
        subplot_cfg['ylabel'] = None
    mean_expected = payload['mean_expected_values']
    true_values = payload['true_task_values']
    rounds = payload['rounds']
    num_tasks = mean_expected.shape[1]
    if num_tasks == 0:
        print('  ! skip fig5h: expected-value payload is empty')
        return

    ncols = min(cfg['ncols'], num_tasks)
    nrows = int(np.ceil(num_tasks / ncols))
    fig_w = ncols * cfg['subplot_w_cm']
    fig_h = nrows * cfg['subplot_h_cm']
    fig, axes = plt.subplots(nrows, ncols, figsize=cm_size_to_inch((fig_w, fig_h)))
    axes = np.array(axes).reshape(nrows, ncols)

    legend_handles = None
    legend_labels = None
    active_axes = []
    for task_idx in range(num_tasks):
        row, col = divmod(task_idx, ncols)
        ax = axes[row, col]
        active_axes.append(ax)
        curve_markevery = resolve_curve_markevery(rounds, cfg)
        line_est, = ax.plot(
            rounds,
            mean_expected[:, task_idx],
            color=cfg['curve_color'],
            linestyle=cfg['curve_linestyle'],
            linewidth=cfg['linewidth'],
            marker=cfg['curve_marker'],
            markersize=PLOT_GLOBAL['markersize'],
            markerfacecolor=cfg['curve_markerfacecolor'],
            markeredgewidth=cfg['curve_markeredgewidth'],
            markevery=curve_markevery,
            label=cfg['estimate_label'],
        )
        line_true = ax.axhline(
            true_values[task_idx],
            color=cfg['true_line_color'],
            linestyle=cfg['true_line_style'],
            linewidth=cfg['true_line_width'],
            label=cfg['true_line_label'],
        )
        STYLE_HELPER.apply_axis_controls(ax, cfg=subplot_cfg)

        task_type = int(round(task_layout['type'][task_idx])) if task_idx < task_layout['count'] and np.isfinite(task_layout['type'][task_idx]) else 0
        true_value = true_values[task_idx]
        title = f"T{task_idx + 1}  type={task_type}  v={true_value:.0f}" if np.isfinite(true_value) else f"T{task_idx + 1}"
        ax.set_title(
            title,
            fontsize=cfg['subplot_title_fontsize'],
            pad=cfg['subplot_title_pad'],
            color=cfg['subplot_title_color'],
        )
        apply_common_style(ax, cfg=subplot_cfg, title=None)

        if legend_handles is None:
            legend_handles = [line_est, line_true]
            legend_labels = [cfg['estimate_label'], cfg['true_line_label']]

    for task_idx in range(num_tasks, nrows * ncols):
        row, col = divmod(task_idx, ncols)
        axes[row, col].set_visible(False)

    if cfg.get('show_title', True):
        fig.suptitle(cfg['suptitle'], fontsize=PLOT_GLOBAL['title_fontsize'], y=cfg['suptitle_y'])
    if cfg.get('show_legend', False) and legend_handles is not None:
        legend_container = str(cfg.get('legend_container', 'axes')).strip().lower()
        if legend_container not in {'axes', 'figure'}:
            print(f"  ! fig5h: invalid legend_container={cfg.get('legend_container')!r}; fallback to 'axes'")
            legend_container = 'axes'

        if legend_container == 'axes':
            target_ax = active_axes[-1]
            legend_subplot_index = cfg.get('legend_subplot_index', 'last_active')
            if legend_subplot_index != 'last_active':
                try:
                    legend_index = int(legend_subplot_index)
                except (TypeError, ValueError):
                    legend_index = None

                if legend_index is None or legend_index < 1 or legend_index > len(active_axes):
                    print(
                        f"  ! fig5h: invalid legend_subplot_index={legend_subplot_index!r}; "
                        "fallback to last active subplot"
                    )
                else:
                    target_ax = active_axes[legend_index - 1]

            legend_kwargs = {
                'handles': legend_handles,
                'labels': legend_labels,
                'loc': cfg['legend_loc'],
                'fontsize': resolve_fontsize('legend_fontsize', cfg=cfg),
                'framealpha': cfg['legend_framealpha'],
                'edgecolor': cfg['legend_edgecolor'],
            }
            if cfg.get('legend_bbox_to_anchor') is not None:
                legend_kwargs['bbox_to_anchor'] = cfg['legend_bbox_to_anchor']
            if cfg.get('legend_ncol') is not None:
                legend_kwargs['ncol'] = cfg['legend_ncol']
            if cfg.get('legend_borderaxespad') is not None:
                legend_kwargs['borderaxespad'] = cfg['legend_borderaxespad']
            if cfg.get('legend_handlelength') is not None:
                legend_kwargs['handlelength'] = cfg['legend_handlelength']
            if cfg.get('legend_labelspacing') is not None:
                legend_kwargs['labelspacing'] = cfg['legend_labelspacing']

            legend = target_ax.legend(**legend_kwargs)
            style_legend(legend, cfg=cfg)
        else:
            STYLE_HELPER.add_figure_legend(
                fig,
                legend_handles,
                legend_labels,
                cfg=cfg,
                loc=cfg['legend_loc'],
                bbox_to_anchor=cfg['legend_bbox_to_anchor'],
            )
    if cfg.get('use_shared_ylabel', False):
        shared_ylabel_text = cfg.get('shared_ylabel_text', cfg.get('ylabel'))
        if shared_ylabel_text:
            ylabel_style = STYLE_HELPER.get_text_style(
                'ylabel_fontsize',
                'label_fontweight',
                cfg=cfg,
            )
            fig.text(
                float(cfg.get('shared_ylabel_x', 0.02)),
                0.5,
                shared_ylabel_text,
                rotation='vertical',
                va='center',
                ha='center',
                **ylabel_style,
            )

    adjust_kwargs = {
        'top': cfg['subplots_adjust_top'],
        'hspace': cfg['subplot_hspace'],
        'wspace': cfg['subplot_wspace'],
    }
    for key in ('left', 'right', 'bottom'):
        cfg_key = f'subplots_adjust_{key}'
        if cfg.get(cfg_key) is not None:
            adjust_kwargs[key] = cfg[cfg_key]
    fig.subplots_adjust(**adjust_kwargs)
    finalize_and_save(fig, save_path, cfg=cfg)


def plot_single_curve(curve, save_path, cfg, label, rounds):
    curve = np.asarray(curve, dtype=float).ravel()
    rounds = np.asarray(rounds, dtype=float).ravel()
    if curve.size == 0 or rounds.size == 0:
        print(f"  ! skip {os.path.basename(save_path)}: curve data is empty")
        return

    rounds, curve = maybe_prepend_origin_zero(rounds, curve, cfg)

    curve_label = cfg.get('curve_label', label) if label is None else label
    curve_markevery = resolve_curve_markevery(rounds, cfg)
    fig, ax = create_single_axis_figure(cfg)
    ax.plot(
        rounds,
        curve,
        color=cfg['curve_color'],
        linestyle=cfg['curve_linestyle'],
        linewidth=cfg['linewidth'],
        marker=cfg['curve_marker'],
        markersize=PLOT_GLOBAL['markersize'],
        markerfacecolor=cfg['curve_markerfacecolor'],
        markeredgewidth=cfg['curve_markeredgewidth'],
        markevery=curve_markevery,
        label=curve_label,
    )
    STYLE_HELPER.apply_axis_controls(ax, cfg=cfg)
    apply_common_style(ax, cfg=cfg)
    finalize_and_save(fig, save_path, cfg=cfg)


def plot_fig5m_combined_convergence(curve_specs, save_path):
    cfg = FIG5M_CONFIG
    valid_specs = []
    for spec in curve_specs:
        curve = spec.get('curve')
        if curve is None:
            print(f"  ! skip fig5m series: {spec['label']} not found")
            continue

        arr = np.asarray(curve, dtype=float).ravel()
        if arr.size == 0:
            print(f"  ! skip fig5m series: {spec['label']} is empty")
            continue

        valid_specs.append({
            'label': spec['label'],
            'curve': arr,
            'style_cfg': spec['style_cfg'],
        })

    if len(valid_specs) < 2:
        print('  ! skip fig5m: fewer than two convergence curves are available')
        return

    fig, ax = create_single_axis_figure(cfg)
    for spec in valid_specs:
        style_cfg = spec['style_cfg']
        rounds = np.arange(spec['curve'].size, dtype=int)
        rounds, curve = maybe_prepend_origin_zero(rounds, spec['curve'], style_cfg)
        curve_markevery = resolve_curve_markevery(rounds, style_cfg)
        ax.plot(
            rounds,
            curve,
            color=style_cfg['curve_color'],
            linestyle=style_cfg['curve_linestyle'],
            linewidth=style_cfg['linewidth'],
            marker=style_cfg['curve_marker'],
            markersize=PLOT_GLOBAL['markersize'],
            markerfacecolor=style_cfg['curve_markerfacecolor'],
            markeredgewidth=style_cfg['curve_markeredgewidth'],
            markevery=curve_markevery,
            label=spec['label'],
        )

    STYLE_HELPER.apply_axis_controls(ax, cfg=cfg)
    apply_common_style(ax, cfg=cfg)
    finalize_and_save(fig, save_path, cfg=cfg)


def plot_task_resource_heatmap(matrix, save_path, cfg, colorbar_label,
                               center_value=None, vmin=None, vmax=None):
    if matrix.size == 0:
        print(f"  ! {os.path.basename(save_path)} 数据为空，跳过")
        return

    heatmap_cfg = dict(HEATMAP_STYLE)
    heatmap_cfg.update(cfg)
    colorbar_label = heatmap_cfg.get('colorbar_label', colorbar_label)
    center_value = heatmap_cfg.get('center_value', center_value)
    vmin = heatmap_cfg.get('vmin', vmin)
    vmax = heatmap_cfg.get('vmax', vmax)
    M, K = matrix.shape
    show_colorbar = bool(heatmap_cfg.get('show_colorbar', True))
    use_wide_colorbar_layout = (
        heatmap_cfg.get('figure_key') == 'fig5d'
        and show_colorbar
    )

    if use_wide_colorbar_layout:
        fig_wide = heatmap_cfg.get('figsize_in_with_colorbar', heatmap_cfg.get('figsize_in'))
        fig = plt.figure(
            figsize=fig_wide,
            constrained_layout=bool(heatmap_cfg.get('constrained_layout', False)),
        )
        gs = fig.add_gridspec(
            1,
            2,
            width_ratios=[
                1.0,
                float(heatmap_cfg.get('colorbar_axes_width_ratio', 0.12)),
            ],
            wspace=float(heatmap_cfg.get('colorbar_axes_pad_ratio', 0.05)),
        )
        ax = fig.add_subplot(gs[0, 0])
        if hasattr(ax, 'set_box_aspect'):
            ax.set_box_aspect(float(heatmap_cfg.get('axes_box_aspect', 1.0)))
        cax = fig.add_subplot(gs[0, 1])
    else:
        fig, ax = create_single_axis_figure(heatmap_cfg)
        cax = None

    finite_vals = matrix[np.isfinite(matrix)]
    cmap = plt.get_cmap(heatmap_cfg['cmap']).copy()
    cmap.set_bad(heatmap_cfg['bad_color'])

    if center_value is not None:
        if finite_vals.size == 0:
            lo = vmin if vmin is not None else center_value - 1.0
            hi = vmax if vmax is not None else center_value + 1.0
        else:
            lo = vmin if vmin is not None else float(np.min(finite_vals))
            hi = vmax if vmax is not None else float(np.max(finite_vals))
        span = max(1.0, abs(center_value) * 0.1)
        if lo >= center_value:
            lo = center_value - span
        if hi <= center_value:
            hi = center_value + span
        norm = TwoSlopeNorm(vmin=lo, vcenter=center_value, vmax=hi)
    else:
        lo = vmin if vmin is not None else 0.0
        hi = vmax if vmax is not None else (float(np.max(finite_vals)) if finite_vals.size > 0 else 0.0)
        if not np.isfinite(hi) or hi <= lo:
            hi = lo + 1.0
        norm = Normalize(vmin=lo, vmax=hi)

    im = ax.imshow(np.ma.masked_invalid(matrix), cmap=cmap, aspect='auto', norm=norm)

    if heatmap_cfg.get('annot', False):
        for m in range(M):
            for k in range(K):
                val = matrix[m, k]
                if not np.isfinite(val):
                    nan_text = heatmap_cfg.get('nan_text', '')
                    if nan_text:
                        ax.text(k, m, nan_text,
                                ha='center', va='center',
                                fontsize=heatmap_cfg['annot_fontsize'],
                                color=heatmap_cfg['nan_text_color'])
                    continue
                rgba = im.cmap(im.norm(val))
                luminance = 0.299 * rgba[0] + 0.587 * rgba[1] + 0.114 * rgba[2]
                text_color = (
                    heatmap_cfg['annot_dark_text_color']
                    if luminance > heatmap_cfg['annot_luminance_threshold']
                    else heatmap_cfg['annot_light_text_color']
                )
                ax.text(k, m, heatmap_cfg['value_fmt'].format(val),
                        ha='center', va='center',
                        fontsize=heatmap_cfg['annot_fontsize'],
                        color=text_color)

    ax.set_xticks(range(K))
    ax.set_xticklabels([f'R{k+1}' for k in range(K)], fontsize=PLOT_GLOBAL['tick_fontsize'])
    ax.set_yticks(range(M))
    ax.set_yticklabels([f'T{m+1}' for m in range(M)], fontsize=PLOT_GLOBAL['tick_fontsize'])
    apply_common_style(ax, heatmap_cfg['xlabel'], heatmap_cfg['ylabel'],
                       title=heatmap_cfg['title'] if heatmap_cfg.get('show_title', True) else None)

    if show_colorbar:
        if use_wide_colorbar_layout:
            cbar = fig.colorbar(im, cax=cax)
        else:
            cbar = fig.colorbar(
                im,
                ax=ax,
                fraction=heatmap_cfg['colorbar_fraction'],
                pad=heatmap_cfg['colorbar_pad'],
            )
        STYLE_HELPER.apply_colorbar_style(cbar, cfg=heatmap_cfg, label=colorbar_label)
    finalize_and_save(fig, save_path)


def plot_fig5e_stacked_compare(alloc_mat, demand_mat, task_info, save_path):
    ratio_mat = build_fulfillment_ratio_matrix(alloc_mat, demand_mat)
    return plot_fig5e_ratio_heatmap(ratio_mat, save_path)

    cfg = FIG5E_CONFIG
    if alloc_mat.size == 0 or demand_mat.size == 0:
        print("  ! fig5e 数据为空，跳过")
        return

    M = min(alloc_mat.shape[0], demand_mat.shape[0], task_info.get('M', alloc_mat.shape[0]))
    K = min(alloc_mat.shape[1], demand_mat.shape[1])
    if M == 0 or K == 0:
        print("  ! fig5e 数据维度无效，跳过")
        return

    x = np.arange(M, dtype=float)
    width = cfg['bar_width']
    fig, ax = create_single_axis_figure(cfg)

    bottom_demand = np.zeros(M)
    bottom_alloc = np.zeros(M)
    resource_handles = []

    for k in range(K):
        color = RESOURCE_COLORS[k % len(RESOURCE_COLORS)]
        label = f'R{k+1}'
        bars_d = ax.bar(
            x - width / 2,
            demand_mat[:M, k],
            width,
            bottom=bottom_demand,
            color=color,
            edgecolor=cfg['bar_edgecolor'],
            linewidth=cfg['bar_linewidth'],
            hatch=cfg['hatch_demand'],
            label=label,
        )
        ax.bar(
            x + width / 2,
            alloc_mat[:M, k],
            width,
            bottom=bottom_alloc,
            color=color,
            edgecolor=cfg['bar_edgecolor'],
            linewidth=cfg['bar_linewidth'],
            hatch=cfg['hatch_alloc'],
        )
        bottom_demand += demand_mat[:M, k]
        bottom_alloc += alloc_mat[:M, k]
        resource_handles.append(bars_d[0])

    if cfg.get('show_completion_text', False):
        degrees = task_info.get('degree', np.full(M, np.nan))
        y_top = np.maximum(bottom_demand, bottom_alloc)
        offset = max(np.nanmax(y_top) * cfg['completion_text_offset_ratio'], cfg['completion_text_min_offset'])
        for i in range(M):
            deg = degrees[i] if i < len(degrees) else np.nan
            if np.isnan(deg):
                continue
            ax.text(
                x[i],
                y_top[i] + offset,
                f'{deg * 100:.0f}%',
                ha='center',
                va='bottom',
                fontsize=PLOT_GLOBAL['tick_fontsize'] - 1,
                color=cfg['completion_text_color'],
            )

    ax.set_xticks(x)
    ax.set_xticklabels([f'T{i+1}' for i in range(M)], fontsize=PLOT_GLOBAL['tick_fontsize'])

    if PLOT_GLOBAL['show_grid']:
        ax.yaxis.grid(
            True,
            linestyle=PLOT_GLOBAL['grid_linestyle'],
            linewidth=PLOT_GLOBAL['grid_linewidth'],
            alpha=PLOT_GLOBAL['grid_alpha'],
        )
    ax.set_axisbelow(True)

    apply_common_style(ax, cfg['xlabel'], cfg['ylabel'],
                       title=cfg['title'] if cfg.get('show_title', True) else None)

    role_handles = [
        mpatches.Patch(
            facecolor=cfg['role_demand_facecolor'],
            edgecolor=cfg['role_demand_edgecolor'],
            hatch=cfg['hatch_demand'],
            label=cfg['role_demand_label'],
        ),
        mpatches.Patch(
            facecolor=cfg['role_alloc_facecolor'],
            edgecolor=cfg['role_alloc_edgecolor'],
            hatch=cfg['hatch_alloc'],
            label=cfg['role_alloc_label'],
        ),
    ]

    legend1 = ax.legend(
        handles=role_handles,
        fontsize=resolve_fontsize('legend_fontsize', cfg=cfg),
        framealpha=PLOT_GLOBAL['legend_framealpha'],
        edgecolor=PLOT_GLOBAL['legend_edgecolor'],
        loc=cfg['role_legend_loc'],
        title=cfg['role_legend_title'],
    )
    style_legend(legend1, cfg=cfg)
    ax.add_artist(legend1)
    legend2 = ax.legend(
        handles=resource_handles,
        fontsize=resolve_fontsize('legend_fontsize', cfg=cfg),
        framealpha=PLOT_GLOBAL['legend_framealpha'],
        edgecolor=PLOT_GLOBAL['legend_edgecolor'],
        loc=cfg['resource_legend_loc'],
        title=cfg['resource_legend_title'],
        ncols=min(K, cfg['resource_legend_ncols_max']),
    )
    style_legend(legend2, cfg=cfg)

    finalize_and_save(fig, save_path)


# ══════════════════════════════════════════════════════════════════════════════
# 绘图函数
# ══════════════════════════════════════════════════════════════════════════════

def plot_fig5e_ratio_heatmap(ratio_mat, save_path):
    plot_task_resource_heatmap(
        ratio_mat,
        save_path,
        FIG5E_CONFIG,
        colorbar_label=None,
    )


def choose_fig5a_grid(M, max_ncols):
    if M <= 1:
        return 1, 1

    start_ncols = 1 if M == 1 else 2
    max_ncols = max(start_ncols, min(int(max_ncols), int(M)))
    best_ncols = start_ncols
    best_empty_slots = None

    for ncols in range(start_ncols, max_ncols + 1):
        nrows = int(np.ceil(M / ncols))
        empty_slots = nrows * ncols - M
        if (
            best_empty_slots is None
            or empty_slots < best_empty_slots
            or (empty_slots == best_empty_slots and ncols > best_ncols)
        ):
            best_empty_slots = empty_slots
            best_ncols = ncols

    return int(np.ceil(M / best_ncols)), best_ncols


def plot_fig5a(sc_list, task_info, N, K, save_path):
    """
    图5a：M 个任务资源分配矩阵热图网格。
    每个子图 = 一个任务的 SC{m}，[N×K] 热图，共享 colorbar 颜色上限。
    """
    cfg = dict(HEATMAP_STYLE)
    cfg.update(FIG5A_CONFIG)
    M   = len(sc_list)
    if M == 0:
        print("  ! final_SC 为空，跳过图5a")
        return

    nrows, ncols = choose_fig5a_grid(M, cfg['max_ncols'])

    fig_w = ncols * cfg['subplot_w_cm'] + (cfg['colorbar_extra_w_cm'] if cfg['show_colorbar'] else cfg['plain_extra_w_cm'])
    fig_h = nrows * cfg['subplot_h_cm']
    fig, axes = plt.subplots(nrows, ncols, figsize=cm_size_to_inch((fig_w, fig_h)))
    axes = np.array(axes).reshape(nrows, ncols)

    # 决定共享 vmax
    if cfg['shared_vmax']:
        vmax_vals = [sc.max() for sc in sc_list if sc.size > 0 and sc.max() > 0]
        vmax = max(vmax_vals) if vmax_vals else 1.0
    else:
        vmax = None

    ims = []
    visible_axes = []
    for m in range(M):
        row, col = divmod(m, ncols)
        ax = axes[row, col]
        visible_axes.append(ax)
        sc = sc_list[m]
        if sc.ndim == 1:
            sc = sc.reshape(-1, 1)
        cur_N, cur_K = sc.shape

        im_kwargs = dict(cmap=cfg['cmap'], aspect='auto', vmin=0,
                         vmax=vmax if vmax is not None else sc.max() or 1.0)
        im = ax.imshow(sc, **im_kwargs)
        ims.append(im)

        # 格内数值标注（可选）
        if cfg['cell_annot']:
            for ni in range(cur_N):
                for ki in range(cur_K):
                    v = sc[ni, ki]
                    if v > 0:
                        ax.text(ki, ni, f'{v:.0f}',
                                ha='center', va='center',
                                fontsize=cfg['cell_fontsize'],
                                color=(
                                    cfg['annot_light_text_color']
                                    if v > (vmax or 1) * cfg['annot_luminance_threshold']
                                    else cfg['annot_dark_text_color']
                                ))

        # 子图标题（颜色与任务类型对应）
        task_type = int(round(task_info['type'][m])) if m < len(task_info['type']) else 0
        task_val  = task_info['value'][m]              if m < len(task_info['value']) else 0
        deg       = task_info['degree'][m]              if m < len(task_info['degree']) else np.nan
        deg_str   = f'{deg*100:.0f}%' if not np.isnan(deg) else '?'
        ax.set_title(
            f'T{m+1}  type={task_type}  v={task_val:.0f}  d={deg_str}',
            fontsize=cfg['subplot_title_fontsize'],
            color=cfg['subplot_title_color'],
            pad=cfg['subplot_title_pad'],
            fontfamily=PLOT_GLOBAL['font_family'][0],
        )

        # 轴刻度
        ax.set_xticks(range(cur_K))
        ax.set_xticklabels([f'R{k+1}' for k in range(cur_K)],
                           fontsize=PLOT_GLOBAL['tick_fontsize'])
        ax.set_yticks(range(cur_N))
        ax.set_yticklabels([f'A{n+1}' for n in range(cur_N)],
                           fontsize=PLOT_GLOBAL['tick_fontsize'])
        if row == nrows - 1:
            ax.set_xlabel(cfg['xlabel'], fontsize=PLOT_GLOBAL['xlabel_fontsize'])
        if col == 0:
            ax.set_ylabel(cfg['ylabel'], fontsize=PLOT_GLOBAL['ylabel_fontsize'])
        apply_spine_style(ax)

    # 隐藏多余子图
    for m in range(M, nrows * ncols):
        row, col = divmod(m, ncols)
        axes[row, col].set_visible(False)

    # 统一 colorbar
    if cfg['show_colorbar'] and ims:
        fig.subplots_adjust(
            hspace=cfg['subplot_hspace'],
            wspace=cfg['subplot_wspace'],
        )
        norm = Normalize(vmin=0, vmax=vmax if vmax else 1)
        sm   = ScalarMappable(cmap=cfg['cmap'], norm=norm)
        sm.set_array([])
        cb = fig.colorbar(
            sm,
            ax=visible_axes,
            fraction=cfg['colorbar_fraction'],
            pad=cfg['colorbar_pad'],
        )
        STYLE_HELPER.apply_colorbar_style(cb, cfg=cfg, label=cfg['colorbar_label'])
    else:
        fig.subplots_adjust(hspace=cfg['subplot_hspace'], wspace=cfg['subplot_wspace'])

    if cfg['show_title']:
        fig.suptitle(cfg['suptitle'],
                     fontsize=PLOT_GLOBAL['title_fontsize'], y=cfg['suptitle_y'],
                     fontfamily=PLOT_GLOBAL['font_family'][0])

    finalize_and_save(fig, save_path)


def plot_fig5b(timing_list, task_info, N, save_path):
    """
    图5b：智能体任务执行甘特图。
    每行 = 一个智能体，每条 = 一次任务执行，按任务类型着色。
    条上标注任务 ID（宽度足够时显示）。
    """
    cfg    = FIG5B_CONFIG
    bar_h  = cfg['bar_height']

    # 找最大时间终点
    t_max = 1.0
    for ag in timing_list:
        for s, e in zip(ag['starts'], ag['execs']):
            t_max = max(t_max, float(s) + float(e))

    fig, ax = create_single_axis_figure(cfg)

    # task_id → type 映射
    style_maps = build_fig5b_task_style_maps(task_info, cfg)
    task_type_map = style_maps['task_type_map']
    fill_color_map = style_maps['fill_color_map']
    edge_color_map = style_maps['edge_color_map']
    text_color_map = style_maps['text_color_map']
    default_fill_color = cfg.get('task_default_color', DEFAULT_TASK_COLOR)
    default_edge_color = shift_color_lightness(
        default_fill_color,
        float(cfg.get('task_edge_darken_delta', -0.14)),
    )
    default_text_color = cfg.get('task_label_color', TEXT_STYLE['contrast_dark_color'])

    used_types = set()
    for i, ag in enumerate(timing_list):
        y = N - 1 - i    # 智能体 1 在最顶行
        for task_id, start, dur in zip(ag['task_seq'], ag['starts'], ag['execs']):
            task_id = int(round(task_id))
            t_type  = task_type_map.get(task_id, 0)
            color   = fill_color_map.get(task_id, default_fill_color)
            edge_color = edge_color_map.get(task_id, default_edge_color)
            text_color = text_color_map.get(task_id, default_text_color)
            used_types.add(t_type)

            ax.barh(y, dur, left=start, height=bar_h,
                    color=color, edgecolor=edge_color, linewidth=cfg['bar_linewidth'],
                    align='center', zorder=2)

            if cfg['show_task_id_label'] and dur >= cfg['label_min_width']:
                ax.text(start + dur / 2, y, f'T{task_id}',
                        ha='center', va='center',
                        fontsize=cfg['label_fontsize'],
                        color=text_color, fontweight=cfg['task_label_fontweight'], zorder=3)

    # y 轴：智能体标签（从上到下 A1→AN）
    ax.set_yticks(range(N))
    ax.set_yticklabels([f'A{N - i}' for i in range(N)],
                       fontsize=PLOT_GLOBAL['tick_fontsize'])
    ax.set_ylim(-0.8, N - 0.2)
    ax.set_xlim(0, t_max * (1.0 + cfg['xlim_expand_ratio']))

    # 纵向网格线（方便读时间）
    if PLOT_GLOBAL['show_grid']:
        ax.xaxis.grid(True, linestyle=PLOT_GLOBAL['grid_linestyle'],
                      linewidth=PLOT_GLOBAL['grid_linewidth'],
                      alpha=PLOT_GLOBAL['grid_alpha'], zorder=0)
    ax.set_axisbelow(True)

    # 图例：任务类型
    if cfg.get('show_legend', PLOT_GLOBAL.get('show_legend', False)):
        patches = build_fig5b_legend_handles(cfg, style_maps, used_types)
        if patches:
            legend = ax.legend(handles=patches,
                               fontsize=resolve_fontsize('legend_fontsize', cfg=cfg),
                               framealpha=PLOT_GLOBAL['legend_framealpha'],
                               edgecolor=PLOT_GLOBAL['legend_edgecolor'],
                               loc=cfg['legend_loc'],
                               ncol=cfg['legend_ncol'])
            style_legend(legend, cfg=cfg)

    apply_common_style(ax, cfg['xlabel'], cfg['ylabel'],
                       title=cfg['title'] if cfg['show_title'] else None)

    finalize_and_save(fig, save_path)


# ══════════════════════════════════════════════════════════════════════════════
# 主程序
# ══════════════════════════════════════════════════════════════════════════════

def main():
    apply_plot_rcparams()
    mat_path = find_mat_file(sys.argv)
    configure_output_dir(mat_path)

    print("\n加载数据...")
    raw      = mat73.loadmat(mat_path)
    viz_data = raw.get('viz_data', raw)

    N    = to_int(viz_data.get('N'),    default=0)
    M    = to_int(viz_data.get('M'),    default=0)
    K    = to_int(viz_data.get('K'),    default=0)
    seed = to_int(viz_data.get('seed'), default=0)
    algorithm_display_name = extract_algorithm_display_name(viz_data)

    print(f"  N={N}  M={M}  K={K}  seed={seed}")
    print(f"  algorithm             = {algorithm_display_name}")
    print(f"  coalition_utility     = {to_scalar(viz_data.get('coalition_utility')):.2f}")
    print(f"  total_completed_value = {to_scalar(viz_data.get('total_completed_value')):.2f}")
    print(f"  computation_time      = {to_scalar(viz_data.get('computation_time')):.2f} s")
    print_exp_params_snapshot(viz_data.get('exp_params_snapshot'))

    print("\n提取数据...")
    sc_list     = extract_sc_matrices(viz_data)
    task_info   = extract_task_info(viz_data, M_hint=M)
    demand_mat  = extract_task_demand_matrix(viz_data, M_hint=M, K_hint=K)
    timing_list = extract_timing(viz_data, N)
    agent_layout = extract_agent_layout(viz_data, N_hint=N)
    task_layout = extract_task_layout(viz_data, M_hint=M)
    world_bounds = extract_world_bounds(viz_data, agent_layout=agent_layout, task_layout=task_layout, cfg=FIG5G_CONFIG)
    belief_payload = build_belief_value_payload(viz_data, task_info, N, M)
    convergence_utility = extract_curve_1d(viz_data, 'convergence_utility')
    convergence_cost = extract_curve_1d(viz_data, 'convergence_cost')
    convergence_completed_value = extract_curve_1d(viz_data, 'convergence_completed_value')
    alloc_mat   = build_total_allocation_matrix(sc_list, K_hint=K)
    gap_mat     = alloc_mat - demand_mat
    ratio_mat   = build_fulfillment_ratio_matrix(alloc_mat, demand_mat)

    print(f"  final_SC: {len(sc_list)} 个任务矩阵")
    active_sc = sum(1 for sc in sc_list if sc.max() > 1e-9)
    print(f"           其中 {active_sc} 个有联盟分配")
    active_agents = sum(1 for ag in timing_list if len(ag['task_seq']) > 0)
    print(f"  timing:   {len(timing_list)} 个智能体，其中 {active_agents} 个有任务分配")

    print(f"\n绘图 → {FIGURES_DIR}")
    table_json_path = os.path.join(FIGURES_DIR, 'fig5_agent_task_schedule_table.json')
    write_plot_data_json(
        table_json_path,
        build_fig5_agent_task_schedule_table_payload(
            mat_path,
            sc_list,
            demand_mat,
            task_info,
            timing_list,
            agent_layout,
            N,
            M,
            K,
            FIGURES_DIR,
        ),
    )
    convergence_metrics_json_path = os.path.join(
        FIGURES_DIR,
        f"{build_prefixed_stem(FAMILY, 'convergence_metrics_combined')}.json",
    )
    convergence_metrics_payload = build_convergence_metrics_combined_summary_payload(
        mat_path,
        FIGURES_DIR,
        convergence_utility,
        convergence_cost,
        convergence_completed_value,
    )
    if convergence_metrics_payload is not None:
        write_plot_data_json(convergence_metrics_json_path, convergence_metrics_payload)
    else:
        print('  ! skip single_viz_convergence_metrics_combined.json: missing or invalid convergence endpoint data')
    for legacy_name in ('fig5a_resource_tables.json', 'fig5b_schedule.json'):
        legacy_path = os.path.join(FIGURES_DIR, legacy_name)
        if os.path.isfile(legacy_path):
            os.remove(legacy_path)
            print(f"  [DEL] {legacy_path}")

    plot_fig5a(
        sc_list, task_info, N, K,
        build_output_stem('resource_allocation_matrix'),
    )
    plot_fig5b(
        timing_list, task_info, N,
        build_output_stem('agent_task_gantt'),
    )
    plot_task_resource_heatmap(
        alloc_mat,
        build_output_stem('task_total_allocated_resource'),
        FIG5C_CONFIG,
        colorbar_label=None,
    )
    plot_task_resource_heatmap(
        gap_mat,
        build_output_stem('task_allocation_minus_demand'),
        FIG5D_CONFIG,
        colorbar_label=None,
    )
    plot_fig5e_ratio_heatmap(
        ratio_mat,
        build_output_stem('task_allocation_to_demand_ratio'),
    )
    plot_task_resource_heatmap(
        demand_mat,
        build_output_stem('task_true_resource_demand'),
        FIG5F_CONFIG,
        colorbar_label=None,
    )
    plot_fig5g_initial_layout(
        agent_layout,
        task_layout,
        world_bounds,
        build_output_stem('initial_layout'),
    )
    plot_fig5n_scheduled_paths(
        agent_layout,
        task_layout,
        timing_list,
        world_bounds,
        build_output_stem('scheduled_path_map'),
    )

    if belief_payload is not None:
        plot_fig5h_expected_task_value(
            belief_payload,
            task_layout,
            build_output_stem('belief_expected_task_value'),
        )
        plot_single_curve(
            belief_payload['value_error'],
            build_output_stem('belief_value_error'),
            FIG5I_CONFIG,
            label=None,
            rounds=belief_payload['rounds'],
        )

    if convergence_utility is not None:
        plot_single_curve(
            convergence_utility,
            build_output_stem('convergence_utility'),
            FIG5J_CONFIG,
            label=algorithm_display_name,
            rounds=np.arange(convergence_utility.size, dtype=int),
        )
    else:
        print('  ! skip fig5j: convergence_utility not found in viz_data')

    if convergence_cost is not None:
        plot_single_curve(
            convergence_cost,
            build_output_stem('convergence_cost'),
            FIG5K_CONFIG,
            label=algorithm_display_name,
            rounds=np.arange(convergence_cost.size, dtype=int),
        )
    else:
        print('  ! skip fig5k: convergence_cost not found in viz_data')

    if convergence_completed_value is not None:
        plot_single_curve(
            convergence_completed_value,
            build_output_stem('convergence_completed_value'),
            FIG5L_CONFIG,
            label=algorithm_display_name,
            rounds=np.arange(convergence_completed_value.size, dtype=int),
        )
    else:
        print('  ! skip fig5l: convergence_completed_value not found in viz_data')

    print("\n完成。图窗已弹出，关闭后程序退出。")
    plot_fig5m_combined_convergence(
        [
            {
                'label': FIG5M_CONFIG.get('utility_curve_label', 'Utility'),
                'curve': convergence_utility,
                'style_cfg': FIG5J_CONFIG,
            },
            {
                'label': FIG5M_CONFIG.get('cost_curve_label', 'Cost'),
                'curve': convergence_cost,
                'style_cfg': FIG5K_CONFIG,
            },
            {
                'label': FIG5M_CONFIG.get('completed_value_curve_label', 'Completed value'),
                'curve': convergence_completed_value,
                'style_cfg': FIG5L_CONFIG,
            },
        ],
        build_output_stem('convergence_metrics_combined'),
    )
    plt.show()


if __name__ == '__main__':
    main()
