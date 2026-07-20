"""
plot_ablation.py
================
从 Batch_Ablation.m 的结果中绘制消融实验图，包括：
  1. 端点散点图：最终联盟效用、最终任务完成率
  2. 收敛曲线图：联盟效用随外层轮次变化的均值与波动

用法:
  python plot_ablation.py
  python plot_ablation.py <ablation_run_name>
  python plot_ablation.py <path/to/ablation_run_dir>
  python plot_ablation.py <legacy_ablation.mat>
"""

import os
import re
import sys
import json

import matplotlib.lines as mlines
import matplotlib.pyplot as plt
import matplotlib.ticker as mticker
import numpy as np
try:
    import h5py
except ImportError:
    h5py = None

try:
    from plot_style_helper import (
        PlotStyleHelper,
        build_results_figures_dir,
        cm_size_to_inch,
        infer_source_name,
        sanitize_path_component,
    )
except ImportError:
    from .plot_style_helper import (
        PlotStyleHelper,
        build_results_figures_dir,
        cm_size_to_inch,
        infer_source_name,
        sanitize_path_component,
    )
try:
    from plot_unified_config import (
        build_prefixed_stem,
        get_family_figure_config,
        get_family_plot_config,
    )
except ImportError:
    from .plot_unified_config import (
        build_prefixed_stem,
        get_family_figure_config,
        get_family_plot_config,
    )
try:
    from ablation_result_aggregator import AblationResultAggregator
except ImportError:
    from .ablation_result_aggregator import AblationResultAggregator


SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
ROOT_DIR = os.path.dirname(SCRIPT_DIR)
FAMILY = "ablation"
FIGURES_DIR = build_results_figures_dir(ROOT_DIR, FAMILY)
SEARCH_DIRS = [
    os.path.join(ROOT_DIR, "results", "batch", "ablation"),
    os.path.join(ROOT_DIR, "results", "batch"),
]

# =========================
# 顶部可调绘图参数
# 这里集中放置输入筛选、散点图布局、收敛阴影带和保存设置。
# =========================

# 输入来源选择器。
# - None / "": 自动选择最新的 ablation 运行目录；若不存在则回退到旧版 MAT。
# - run name: 例如 "20260330_190655_N6-6_M10_K6_C3_S3"。
# - relative / abs path: 直接指向运行目录、缓存文件或旧版 MAT 文件。
PREFERRED_INPUT = None

# 条件筛选。
# - None: 显示当前输入中的全部条件。
# - 列表: 仅按给定顺序展示这些条件。
VISIBLE_CONDITIONS = None

# 散点图可见的随机种子。
# - None: 显示全部 seed。
# - 列表: 仅显示给定 seed。
SCATTER_VISIBLE_SEEDS = None

# 散点图横轴标签模式。
# - "mc_id": 使用连续 Monte Carlo 编号。
# - "seed": 直接显示原始随机种子。
SCATTER_XLABEL_MODE = "mc_id"
SCATTER_MC_ID_START = 0  # Monte Carlo 编号起点，仅在 mc_id 模式下生效。
SCATTER_MC_TICK_STEP = 5  # 横轴刻度步长；1 表示每个样本都显示。
SCATTER_ALIGN_CONDITIONS = True  # True 表示同一样本的不同条件对齐在同一竖线上。
SCATTER_SHOW_CONNECTION_LINES = False  # True 表示连接同一样本在不同条件下的散点。

# 收敛阴影带设置。
# - CONV_SHOW_BAND: 是否绘制波动区域。
# - CONV_BAND_MODE: "std" 使用均值±标准差，"percentile" 使用分位数区间。
CONV_SHOW_BAND = True
CONV_BAND_MODE = "percentile"
CONV_BAND_SCALE = 1.0  # std 模式下显示 mean ± scale * std。
CONV_BAND_PERCENTILES = (30, 70)  # percentile 模式下显示的分位数区间。

# 条件显示样式：颜色 / marker / 线宽 / 图例名称。

PLOT_CONFIG = get_family_plot_config(FAMILY)
PLOT_GLOBAL = PLOT_CONFIG['PLOT_GLOBAL']
CONDITION_STYLE_MAP = PLOT_CONFIG['CONDITION_STYLE_MAP']
FALLBACK_COLORS = PLOT_CONFIG['FALLBACK_COLORS']
FALLBACK_MARKERS = PLOT_CONFIG['FALLBACK_MARKERS']
CONN_LINE = PLOT_CONFIG['CONN_LINE']
ROW_YLABELS = PLOT_CONFIG['ROW_YLABELS']
ROW_TITLES = PLOT_CONFIG['ROW_TITLES']
BAND_ALPHA = PLOT_GLOBAL['band_alpha']
os.makedirs(FIGURES_DIR, exist_ok=True)
STYLE_HELPER = PlotStyleHelper(PLOT_GLOBAL, FIGURES_DIR)
JSON_BELIEF_CONDITION = "belief_on_quantile"
JSON_BASELINE_CONDITION = "belief_off"

def configure_output_dir(source_name):
    global FIGURES_DIR
    FIGURES_DIR = build_results_figures_dir(ROOT_DIR, FAMILY, source_name)
    os.makedirs(FIGURES_DIR, exist_ok=True)
    STYLE_HELPER.set_figures_dir(FIGURES_DIR)
    return FIGURES_DIR


def build_output_stem(stem):
    return STYLE_HELPER.build_output_stem(build_prefixed_stem(FAMILY, stem))


def _build_subplot_title(cfg, n_value):
    template = cfg.get("subplot_title_template", "N = {n_value}")
    return str(template).format(n_value=n_value)


def _apply_subplots_adjust(fig, cfg):
    adjust_kwargs = {}
    for key in ("left", "right", "bottom", "top"):
        cfg_key = f"subplots_adjust_{key}"
        if cfg.get(cfg_key) is not None:
            adjust_kwargs[key] = cfg[cfg_key]

    if cfg.get("subplot_wspace") is not None:
        adjust_kwargs["wspace"] = cfg["subplot_wspace"]
    if cfg.get("subplot_hspace") is not None:
        adjust_kwargs["hspace"] = cfg["subplot_hspace"]

    if adjust_kwargs:
        fig.subplots_adjust(**adjust_kwargs)


def _draw_shared_ylabel(fig, axes, text, cfg, x_key):
    if not text:
        return

    visible_axes = [ax for ax in np.asarray(axes).ravel() if ax.get_visible()]
    if not visible_axes:
        return

    y0 = min(ax.get_position().y0 for ax in visible_axes)
    y1 = max(ax.get_position().y1 for ax in visible_axes)
    ylabel_style = STYLE_HELPER.get_text_style(
        "ylabel_fontsize",
        "label_fontweight",
        cfg=cfg,
    )
    fig.text(
        float(cfg.get(x_key, 0.02)),
        0.5 * (y0 + y1),
        text,
        rotation="vertical",
        va="center",
        ha="center",
        **ylabel_style,
    )


def _draw_shared_row_ylabels(fig, axes, row_labels, cfg):
    ylabel_style = STYLE_HELPER.get_text_style(
        "ylabel_fontsize",
        "label_fontweight",
        cfg=cfg,
    )
    x_pos = float(cfg.get("shared_row_ylabel_x", 0.02))

    axes_arr = np.asarray(axes)
    for row_idx, row_text in enumerate(row_labels):
        row_axes = [ax for ax in axes_arr[row_idx].ravel() if ax.get_visible()]
        if not row_axes or not row_text:
            continue

        y0 = min(ax.get_position().y0 for ax in row_axes)
        y1 = max(ax.get_position().y1 for ax in row_axes)
        fig.text(
            x_pos,
            0.5 * (y0 + y1),
            row_text,
            rotation="vertical",
            va="center",
            ha="center",
            **ylabel_style,
        )


def _apply_scientific_utility_ticks(ax, cfg):
    if not cfg.get("use_scientific_utility_ticks", False):
        return

    power = int(cfg.get("utility_tick_power", 3))
    formatter = mticker.ScalarFormatter(useMathText=True)
    formatter.set_scientific(True)
    formatter.set_powerlimits((power, power))
    formatter.set_useOffset(False)
    ax.yaxis.set_major_formatter(formatter)
    ax.ticklabel_format(axis="y", style="sci", scilimits=(power, power), useMathText=True)

    offset_text = ax.yaxis.get_offset_text()
    tick_fontsize = cfg.get("tick_fontsize")
    if tick_fontsize is not None:
        offset_text.set_fontsize(tick_fontsize)
    font_family = cfg.get("font_family")
    if font_family:
        offset_text.set_fontfamily(font_family)
    font_style = cfg.get("font_style")
    if font_style:
        offset_text.set_fontstyle(font_style)
    tick_fontweight = cfg.get("tick_fontweight")
    if tick_fontweight:
        offset_text.set_fontweight(tick_fontweight)


def _add_configured_legend(fig, active_axes, handles, labels, cfg):
    if not cfg.get("show_legend", False) or not handles or not labels:
        return None

    legend_container = str(cfg.get("legend_container", "figure")).strip().lower()
    if legend_container not in {"axes", "figure"}:
        print(f"  ! invalid legend_container={cfg.get('legend_container')!r}; fallback to 'figure'")
        legend_container = "figure"

    if legend_container == "axes" and active_axes:
        target_ax = active_axes[-1]
        legend_subplot_index = cfg.get("legend_subplot_index", "last_active")
        if legend_subplot_index != "last_active":
            try:
                legend_index = int(legend_subplot_index)
            except (TypeError, ValueError):
                legend_index = None

            if legend_index is None or legend_index < 1 or legend_index > len(active_axes):
                print(
                    f"  ! invalid legend_subplot_index={legend_subplot_index!r}; "
                    "fallback to last active subplot"
                )
            else:
                target_ax = active_axes[legend_index - 1]

        legend_kwargs = {
            "handles": handles,
            "labels": labels,
            "loc": cfg.get("legend_loc", "best"),
            "framealpha": cfg.get("legend_framealpha"),
            "edgecolor": cfg.get("legend_edgecolor"),
        }
        if cfg.get("legend_fontsize") is not None:
            legend_kwargs["fontsize"] = cfg["legend_fontsize"]
        if cfg.get("legend_bbox_to_anchor") is not None:
            legend_kwargs["bbox_to_anchor"] = cfg["legend_bbox_to_anchor"]
        if cfg.get("legend_ncol") is not None:
            legend_kwargs["ncol"] = cfg["legend_ncol"]
        if cfg.get("legend_borderaxespad") is not None:
            legend_kwargs["borderaxespad"] = cfg["legend_borderaxespad"]
        if cfg.get("legend_handlelength") is not None:
            legend_kwargs["handlelength"] = cfg["legend_handlelength"]
        if cfg.get("legend_labelspacing") is not None:
            legend_kwargs["labelspacing"] = cfg["legend_labelspacing"]

        legend = target_ax.legend(**legend_kwargs)
        STYLE_HELPER.style_legend(legend, cfg=cfg)
        return legend

    return STYLE_HELPER.add_figure_legend(
        fig,
        handles,
        labels,
        cfg=cfg,
        loc=cfg.get("legend_loc", "best"),
        bbox_to_anchor=cfg.get("legend_bbox_to_anchor"),
        ncol=cfg.get("legend_ncol"),
    )


def resolve_input_selector(input_selector):
    if input_selector is None:
        return None
    selector = str(input_selector).strip()
    return selector or None


def _read_scalar(dataset, h5file=None):
    if dataset is None:
        return np.nan

    value = dataset[()]
    if isinstance(value, np.ndarray) and value.dtype.kind == "O":
        if h5file is None or value.size == 0:
            return np.nan
        try:
            value = h5file[value.flat[0]][()]
        except Exception:
            return np.nan

    try:
        return float(np.asarray(value, dtype=float).ravel()[0])
    except Exception:
        return np.nan


def _read_1d(dataset, h5file=None):
    if dataset is None:
        return np.array([])

    value = dataset[()]
    if isinstance(value, np.ndarray) and value.dtype.kind == "O":
        if h5file is None or value.size == 0:
            return np.array([])
        try:
            value = h5file[value.flat[0]][()]
        except Exception:
            return np.array([])

    try:
        return np.asarray(value, dtype=float).ravel()
    except Exception:
        return np.array([])


def _decode_char_array(value):
    arr = np.asarray(value)
    if arr.size == 0:
        return None

    if arr.dtype.kind in ("U", "S"):
        chars = []
        for item in arr.flatten(order="F"):
            if isinstance(item, bytes):
                chars.append(item.decode("utf-8", errors="ignore"))
            else:
                chars.append(str(item))
        text = "".join(chars).strip()
        return text or None

    if np.issubdtype(arr.dtype, np.integer):
        chars = [chr(int(ch)) for ch in arr.flatten(order="F") if int(ch) != 0]
        text = "".join(chars).strip()
        return text or None

    if arr.ndim == 0:
        text = str(arr.item()).strip()
        return text or None

    return None


def _read_string(dataset, h5file):
    if dataset is None:
        return None

    value = dataset[()]
    if isinstance(value, bytes):
        text = value.decode("utf-8", errors="ignore").strip()
        return text or None
    if isinstance(value, str):
        text = value.strip()
        return text or None

    if isinstance(value, np.ndarray) and value.dtype.kind == "O":
        if value.size == 0:
            return None
        try:
            return _read_string(h5file[value.flat[0]], h5file)
        except Exception:
            return None

    return _decode_char_array(value)


def _read_string_list(dataset, h5file):
    if dataset is None:
        return []

    value = dataset[()]
    if isinstance(value, np.ndarray) and value.dtype.kind == "O":
        items = []
        for ref in value.flatten(order="F"):
            try:
                text = _read_string(h5file[ref], h5file)
            except Exception:
                text = None
            if text:
                items.append(text)
        return items

    text = _read_string(dataset, h5file)
    return [text] if text else []


def _json_safe(value):
    if isinstance(value, dict):
        return {str(key): _json_safe(val) for key, val in value.items()}
    if isinstance(value, list):
        return [_json_safe(item) for item in value]
    if isinstance(value, tuple):
        return [_json_safe(item) for item in value]
    if isinstance(value, np.ndarray):
        return [_json_safe(item) for item in value.tolist()]
    if isinstance(value, np.bool_):
        return bool(value)
    if isinstance(value, np.integer):
        return int(value)
    if isinstance(value, np.floating):
        scalar = float(value)
        return None if (np.isnan(scalar) or np.isinf(scalar)) else scalar
    if isinstance(value, float):
        return None if (np.isnan(value) or np.isinf(value)) else value
    return value


def _write_json(path, payload):
    output_dir = os.path.dirname(path)
    if output_dir:
        os.makedirs(output_dir, exist_ok=True)
    with open(path, "w", encoding="utf-8") as fp:
        json.dump(_json_safe(payload), fp, ensure_ascii=False, indent=2)
    print(f"  [OK] {path}")


def _normalize_value(value):
    if isinstance(value, dict):
        return {key: _normalize_value(val) for key, val in value.items()}
    if isinstance(value, list):
        return [_normalize_value(val) for val in value]
    if isinstance(value, tuple):
        return tuple(_normalize_value(val) for val in value)
    if isinstance(value, np.ndarray):
        if value.dtype.names:
            if value.size == 1:
                return _normalize_value(value.reshape(-1, order="F")[0])
            flat = np.empty(value.size, dtype=object)
            for idx, item in enumerate(value.reshape(-1, order="F")):
                flat[idx] = _normalize_value(item)
            return flat.reshape(value.shape, order="F")
        if value.dtype == object:
            if value.ndim == 0:
                return _normalize_value(value.item())
            flat = np.empty(value.size, dtype=object)
            for idx, item in enumerate(value.reshape(-1, order="F")):
                flat[idx] = _normalize_value(item)
            return flat.reshape(value.shape, order="F")
        if value.ndim == 0:
            return _normalize_value(value.item())
        return value
    if isinstance(value, np.generic):
        return value.item()
    return value


def _coerce_results_array(raw_results):
    results = _normalize_value(raw_results)
    arr = np.asarray(results, dtype=object)
    if arr.ndim != 3:
        raise RuntimeError(
            f"Unsupported ablation_results shape: {arr.shape}. Expected a 3-D [N, seed, condition] container."
        )
    return arr


def _to_string(value):
    if value is None:
        return ""
    if isinstance(value, bytes):
        return value.decode("utf-8", errors="ignore")
    if isinstance(value, np.ndarray):
        if value.size == 0:
            return ""
        if value.size == 1:
            return _to_string(value.item())
        return "".join(_to_string(item) for item in value.ravel().tolist())
    text = str(value)
    return "" if text == "None" else text


def _to_bool(value):
    if isinstance(value, np.ndarray):
        if value.size == 0:
            return False
        return _to_bool(value.item())
    if isinstance(value, (list, tuple)):
        if not value:
            return False
        return _to_bool(value[0])
    if value is None:
        return False
    return bool(value)


def _to_scalar(value):
    if value is None:
        return np.nan
    try:
        arr = np.asarray(value, dtype=float).ravel()
        return float(arr[0]) if arr.size else np.nan
    except Exception:
        return np.nan


def _to_curve(value):
    if value is None:
        return np.array([])
    try:
        return np.asarray(value, dtype=float).ravel()
    except Exception:
        return np.array([])


def _to_optional_int(value):
    scalar = _to_scalar(value)
    if np.isnan(scalar):
        return None
    return int(scalar)


def _to_int_list(value):
    if value is None:
        return []
    arr = np.asarray(value).ravel()
    return [int(v) for v in arr.tolist()]


def _to_string_list(value):
    if value is None:
        return []
    if isinstance(value, str):
        return [value]
    if isinstance(value, np.ndarray):
        return [_to_string(v) for v in value.ravel().tolist()]
    return [_to_string(v) for v in list(value)]


def _first_entry_with_field(entries_2d, field_name):
    for item in entries_2d.reshape(-1, order="F"):
        if isinstance(item, dict) and field_name in item and item[field_name] not in (None, ""):
            return item[field_name]
    return None


def _infer_n_values(results_arr, configured_n_values):
    if configured_n_values and len(configured_n_values) == results_arr.shape[0]:
        return configured_n_values

    inferred = []
    for ni in range(results_arr.shape[0]):
        field_value = _first_entry_with_field(results_arr[ni, :, :], "N")
        if field_value is None:
            inferred.append(ni + 1)
        else:
            inferred.append(int(_to_scalar(field_value)))
    return inferred


def _infer_seeds(results_arr, configured_seeds):
    if configured_seeds and len(configured_seeds) == results_arr.shape[1]:
        return configured_seeds

    inferred = []
    for si in range(results_arr.shape[1]):
        field_value = _first_entry_with_field(results_arr[:, si, :], "seed")
        if field_value is None:
            inferred.append(si + 1)
        else:
            inferred.append(int(_to_scalar(field_value)))
    return inferred


def _resolve_condition_name(entry, cond_idx, configured_conditions):
    if isinstance(entry, dict):
        cond_name = _to_string(entry.get("condition"))
        if cond_name:
            return cond_name

        belief_on = entry.get("belief_on", entry.get("enable_belief_update"))
        demand_mode = _to_string(entry.get("demand_estimation_mode")).lower()
        if belief_on is not None:
            belief_on = _to_bool(belief_on)
            if belief_on and demand_mode == "expected":
                return "belief_on_expected"
            if belief_on:
                return "belief_on"
            return "belief_off"

    if cond_idx < len(configured_conditions) and configured_conditions[cond_idx]:
        return configured_conditions[cond_idx]
    return f"condition_{cond_idx + 1}"


def _load_ablation_h5py_legacy(mat_path):
    if h5py is None:
        raise RuntimeError(
            "Legacy ablation MAT loading requires h5py in this environment."
        )

    with h5py.File(mat_path, "r") as h5file:
        config = h5file["ablation_config"]
        n_values_arr = _read_1d(config.get("N_values"), h5file)
        seeds_arr = _read_1d(config.get("seeds"), h5file)
        fixed_m = _read_scalar(config.get("M"), h5file)
        num_rounds_cfg = int(_read_scalar(config.get("num_rounds"), h5file))
        configured_conditions = _read_string_list(config.get("conditions"), h5file)

        n_values = [int(v) for v in n_values_arr]
        seeds = [int(v) for v in seeds_arr]
        num_n = len(n_values)
        num_s = len(seeds)

        refs_dataset = h5file["ablation_results"]
        num_c = int(refs_dataset.shape[0])

        utility = np.full((num_n, num_s, num_c), np.nan)
        completion = np.full((num_n, num_s, num_c), np.nan)
        condition_names = [None] * num_c

        convergence_map = {}
        max_rounds = max(num_rounds_cfg, 0)

        for hdf5_idx in np.ndindex(refs_dataset.shape):
            ni, si, ci = tuple(reversed(hdf5_idx))
            if ni >= num_n or si >= num_s or ci >= num_c:
                continue

            ref = refs_dataset[hdf5_idx]
            try:
                entry = h5file[ref]
            except Exception:
                continue
            if not isinstance(entry, h5py.Group):
                continue

            cond_name = _read_string(entry.get("condition"), h5file)
            if not cond_name and ci < len(configured_conditions):
                cond_name = configured_conditions[ci]
            if not cond_name:
                belief_on = _read_scalar(entry.get("belief_on"), h5file)
                demand_mode = _read_string(entry.get("demand_estimation_mode"), h5file) or ""
                if not np.isnan(belief_on):
                    if belief_on >= 0.5 and demand_mode.lower() == "expected":
                        cond_name = "belief_on_expected"
                    elif belief_on >= 0.5:
                        cond_name = "belief_on"
                    else:
                        cond_name = "belief_off"
            if not cond_name:
                cond_name = f"condition_{ci + 1}"

            if condition_names[ci] is None:
                condition_names[ci] = cond_name

            success = _read_scalar(entry.get("success"), h5file)
            if success != 1.0:
                continue

            utility[ni, si, ci] = _read_scalar(entry.get("final_utility"), h5file)
            completion[ni, si, ci] = _read_scalar(entry.get("final_task_completion"), h5file)

            curve = _read_1d(entry.get("convergence_utility"), h5file)
            if curve.size:
                convergence_map[(ni, si, ci)] = curve
                max_rounds = max(max_rounds, int(curve.size))

        for ci in range(num_c):
            if condition_names[ci] is None:
                if ci < len(configured_conditions) and configured_conditions[ci]:
                    condition_names[ci] = configured_conditions[ci]
                else:
                    condition_names[ci] = f"condition_{ci + 1}"

        convergence = np.full((num_n, num_s, num_c, max_rounds), np.nan)
        for (ni, si, ci), curve in convergence_map.items():
            upto = min(max_rounds, curve.size)
            convergence[ni, si, ci, :upto] = curve[:upto]

    run_meta = {
        "source_type": "legacy_mat",
        "source_path": mat_path,
        "run_dir": os.path.dirname(mat_path),
        "run_name": os.path.splitext(os.path.basename(mat_path))[0],
        "used_cache": False,
        "cache_path": None,
        "param_snapshot": None,
        "fixed_m": None if np.isnan(fixed_m) else int(fixed_m),
        "num_rounds": int(num_rounds_cfg),
    }
    return n_values, seeds, condition_names, utility, completion, convergence, run_meta


def load_ablation_data(input_path=None):
    aggregator = AblationResultAggregator(SEARCH_DIRS)
    resolved = aggregator.resolve_input(input_path=input_path)
    if resolved["source_type"] == "legacy_mat":
        return _load_ablation_h5py_legacy(resolved["path"])

    raw_results, ablation_config, run_meta = aggregator.load_results(input_path=resolved["path"])

    ablation_config = _normalize_value(ablation_config)
    results_arr = _coerce_results_array(raw_results)

    configured_conditions = _to_string_list(ablation_config.get("conditions", []))
    configured_n_values = _to_int_list(ablation_config.get("N_values", []))
    configured_seeds = _to_int_list(ablation_config.get("seeds", []))
    configured_rounds = int(_to_scalar(ablation_config.get("num_rounds", 0)))

    n_values = _infer_n_values(results_arr, configured_n_values)
    seeds = _infer_seeds(results_arr, configured_seeds)
    num_n, num_s, num_c = results_arr.shape

    utility = np.full((num_n, num_s, num_c), np.nan)
    completion = np.full((num_n, num_s, num_c), np.nan)
    condition_names = [None] * num_c

    convergence_map = {}
    max_rounds = max(configured_rounds, 0)

    for ni in range(num_n):
        for si in range(num_s):
            for ci in range(num_c):
                entry = results_arr[ni, si, ci]
                if not isinstance(entry, dict):
                    continue

                cond_name = _resolve_condition_name(entry, ci, configured_conditions)
                if condition_names[ci] is None:
                    condition_names[ci] = cond_name

                if not _to_bool(entry.get("success")):
                    continue

                utility[ni, si, ci] = _to_scalar(entry.get("final_utility"))
                completion[ni, si, ci] = _to_scalar(entry.get("final_task_completion"))

                curve = _to_curve(entry.get("convergence_utility"))
                if curve.size:
                    convergence_map[(ni, si, ci)] = curve
                    max_rounds = max(max_rounds, int(curve.size))

    for ci in range(num_c):
        if condition_names[ci] is None:
            if ci < len(configured_conditions) and configured_conditions[ci]:
                condition_names[ci] = configured_conditions[ci]
            else:
                condition_names[ci] = f"condition_{ci + 1}"

    convergence = np.full((num_n, num_s, num_c, max_rounds), np.nan)
    for (ni, si, ci), curve in convergence_map.items():
        upto = min(max_rounds, curve.size)
        convergence[ni, si, ci, :upto] = curve[:upto]

    run_meta = dict(run_meta or {})
    run_meta["fixed_m"] = _to_optional_int(ablation_config.get("M"))
    run_meta["num_rounds"] = int(max_rounds)

    return n_values, seeds, condition_names, utility, completion, convergence, run_meta


def _extract_timestamp_token(run_meta):
    run_name = _to_string(run_meta.get("run_name"))
    if run_name:
        parts = run_name.split("_")
        if len(parts) >= 2 and re.fullmatch(r"\d{8}", parts[0]) and re.fullmatch(r"\d{6}", parts[1]):
            return f"{parts[0]}_{parts[1]}"

    source_path = _to_string(run_meta.get("source_path"))
    basename = os.path.splitext(os.path.basename(source_path))[0]
    parts = basename.split("_")
    if len(parts) >= 2:
        if re.fullmatch(r"\d{8}", parts[0]) and re.fullmatch(r"\d{6}", parts[1]):
            return f"{parts[0]}_{parts[1]}"
        return "_".join(parts[-2:])
    return basename or "ablation"


def _mean_and_std(curves_2d):
    valid = np.any(~np.isnan(curves_2d), axis=0)
    counts = np.sum(~np.isnan(curves_2d), axis=0)
    safe_counts = np.maximum(counts, 1)

    filled = np.where(np.isnan(curves_2d), 0.0, curves_2d)
    mean = np.sum(filled, axis=0) / safe_counts

    centered = np.where(np.isnan(curves_2d), 0.0, curves_2d - mean)
    std = np.sqrt(np.sum(centered ** 2, axis=0) / safe_counts)

    mean[~valid] = np.nan
    std[~valid] = np.nan
    return mean, std, valid


def _resolve_required_condition_indices(condition_names):
    missing = [
        cond_name
        for cond_name in (JSON_BELIEF_CONDITION, JSON_BASELINE_CONDITION)
        if cond_name not in condition_names
    ]
    if missing:
        raise SystemExit(
            "Missing required ablation conditions for JSON export: "
            f"{missing}. Available conditions: {condition_names}"
        )

    return (
        condition_names.index(JSON_BELIEF_CONDITION),
        condition_names.index(JSON_BASELINE_CONDITION),
    )


def _build_formula_metadata():
    return {
        "delta_utility_pct": (
            "((U_belief - U_no_belief) / U_no_belief) * 100, "
            "where U_belief=belief_on_quantile utility mean and "
            "U_no_belief=belief_off utility mean"
        ),
        "delta_completion_abs": (
            "CR_belief - CR_no_belief, "
            "where CR_belief=belief_on_quantile completion mean and "
            "CR_no_belief=belief_off completion mean"
        ),
    }


def _build_json_metadata(run_meta, condition_names):
    return {
        "source_path": os.path.abspath(_to_string(run_meta.get("source_path"))),
        "source_type": _to_string(run_meta.get("source_type")),
        "run_name": _to_string(run_meta.get("run_name")),
        "output_dir": os.path.abspath(FIGURES_DIR),
        "fixed_M": run_meta.get("fixed_m"),
        "num_rounds": run_meta.get("num_rounds"),
        "all_conditions": list(condition_names),
        "exported_conditions": [JSON_BELIEF_CONDITION, JSON_BASELINE_CONDITION],
        "comparison": {
            "belief_condition": JSON_BELIEF_CONDITION,
            "baseline_condition": JSON_BASELINE_CONDITION,
        },
        "formulas": _build_formula_metadata(),
    }


def _compute_delta_utility_pct(belief_utility, baseline_utility):
    if not np.isfinite(belief_utility) or not np.isfinite(baseline_utility):
        return np.nan
    if np.isclose(baseline_utility, 0.0):
        return np.nan
    return ((belief_utility - baseline_utility) / baseline_utility) * 100.0


def _compute_paired_seed_mask(utility_row, completion_row, belief_idx, baseline_idx):
    return (
        np.isfinite(utility_row[:, belief_idx])
        & np.isfinite(utility_row[:, baseline_idx])
        & np.isfinite(completion_row[:, belief_idx])
        & np.isfinite(completion_row[:, baseline_idx])
    )


def _compute_mean_std(values):
    if values.size == 0:
        return np.nan, np.nan
    return float(np.mean(values)), float(np.std(values))


def build_ablation_summary_payload(n_values, seeds, condition_names, utility, completion, run_meta):
    belief_idx, baseline_idx = _resolve_required_condition_indices(condition_names)
    summary_by_n = []

    for ni, n_value in enumerate(n_values):
        paired_mask = _compute_paired_seed_mask(utility[ni], completion[ni], belief_idx, baseline_idx)
        belief_utility = utility[ni, paired_mask, belief_idx]
        baseline_utility = utility[ni, paired_mask, baseline_idx]
        belief_completion = completion[ni, paired_mask, belief_idx]
        baseline_completion = completion[ni, paired_mask, baseline_idx]

        belief_utility_mean, belief_utility_std = _compute_mean_std(belief_utility)
        baseline_utility_mean, baseline_utility_std = _compute_mean_std(baseline_utility)
        belief_completion_mean, belief_completion_std = _compute_mean_std(belief_completion)
        baseline_completion_mean, baseline_completion_std = _compute_mean_std(baseline_completion)

        summary_by_n.append(
            {
                "N": int(n_value),
                "paired_seed_count": int(np.sum(paired_mask)),
                JSON_BELIEF_CONDITION: {
                    "utility_mean": belief_utility_mean,
                    "utility_std": belief_utility_std,
                    "completion_mean": belief_completion_mean,
                    "completion_std": belief_completion_std,
                },
                JSON_BASELINE_CONDITION: {
                    "utility_mean": baseline_utility_mean,
                    "utility_std": baseline_utility_std,
                    "completion_mean": baseline_completion_mean,
                    "completion_std": baseline_completion_std,
                },
                "comparison": {
                    "delta_utility_abs": belief_utility_mean - baseline_utility_mean,
                    "delta_utility_pct": _compute_delta_utility_pct(
                        belief_utility_mean,
                        baseline_utility_mean,
                    ),
                    "delta_completion_abs": belief_completion_mean - baseline_completion_mean,
                },
            }
        )

    return {
        "metadata": _build_json_metadata(run_meta, condition_names),
        "summary_by_N": summary_by_n,
    }


def build_ablation_scatter_payload(
    n_values,
    seeds,
    condition_names,
    utility,
    completion,
    run_meta,
    scatter_seed_indices=None,
):
    belief_idx, baseline_idx = _resolve_required_condition_indices(condition_names)
    if scatter_seed_indices is None:
        scatter_seed_indices = np.arange(len(seeds), dtype=int)
    else:
        scatter_seed_indices = np.asarray(scatter_seed_indices, dtype=int)
    scatter_groups = []

    for ni, n_value in enumerate(n_values):
        paired_mask = _compute_paired_seed_mask(utility[ni], completion[ni], belief_idx, baseline_idx)
        points = []
        for si in scatter_seed_indices:
            is_valid = bool(paired_mask[si])
            if not is_valid:
                continue

            belief_utility = float(utility[ni, si, belief_idx])
            baseline_utility = float(utility[ni, si, baseline_idx])
            belief_completion = float(completion[ni, si, belief_idx])
            baseline_completion = float(completion[ni, si, baseline_idx])

            points.append(
                {
                    "seed": int(seeds[si]),
                    JSON_BELIEF_CONDITION: {
                        "utility": belief_utility,
                        "completion": belief_completion,
                    },
                    JSON_BASELINE_CONDITION: {
                        "utility": baseline_utility,
                        "completion": baseline_completion,
                    },
                    "comparison": {
                        "delta_utility_abs": belief_utility - baseline_utility,
                        "delta_utility_pct": _compute_delta_utility_pct(
                            belief_utility,
                            baseline_utility,
                        ),
                        "delta_completion_abs": belief_completion - baseline_completion,
                    },
                }
            )

        scatter_groups.append(
            {
                "N": int(n_value),
                "paired_seed_count": int(np.sum(paired_mask)),
                "points": points,
            }
        )

    return {
        "metadata": _build_json_metadata(run_meta, condition_names),
        "scatter_points_by_N": scatter_groups,
    }


def _unique_preserve_order(items):
    seen = set()
    result = []
    for item in items:
        if item in seen:
            continue
        seen.add(item)
        result.append(item)
    return result


def _build_condition_styles(condition_names):
    styles = {}
    fallback_idx = 0
    for cond_name in condition_names:
        if cond_name in CONDITION_STYLE_MAP:
            style = dict(CONDITION_STYLE_MAP[cond_name])
            if style.get("legend_label") is None:
                style["legend_label"] = style.get("label", cond_name)
            styles[cond_name] = style
            continue

        styles[cond_name] = {
            "color": FALLBACK_COLORS[fallback_idx % len(FALLBACK_COLORS)],
            "marker": FALLBACK_MARKERS[fallback_idx % len(FALLBACK_MARKERS)],
            "markersize": 7.5,
            "markeredgewidth": 1.2,
            "linewidth": 2.0,
            "label": cond_name,
            "legend_label": cond_name,
        }
        fallback_idx += 1
    return styles


def _resolve_visible_conditions(condition_names):
    names = _unique_preserve_order(condition_names)
    if VISIBLE_CONDITIONS is None:
        return names

    visible = [name for name in VISIBLE_CONDITIONS if name in names]
    if not visible:
        raise SystemExit(
            f"VISIBLE_CONDITIONS={VISIBLE_CONDITIONS} does not match any condition in this input: {names}"
        )
    return visible


def _normalize_seed_value(seed_value):
    if isinstance(seed_value, (int, np.integer)):
        return int(seed_value)

    text = str(seed_value).strip()
    if not text:
        return text

    try:
        numeric = float(text)
    except ValueError:
        return text

    if numeric.is_integer():
        return int(numeric)
    return text


def _resolve_scatter_seed_indices(seeds):
    if SCATTER_VISIBLE_SEEDS is None:
        return np.arange(len(seeds), dtype=int)

    normalized_seeds = [_normalize_seed_value(seed) for seed in seeds]
    seed_to_index = {seed_value: idx for idx, seed_value in enumerate(normalized_seeds)}

    requested = _unique_preserve_order([_normalize_seed_value(seed) for seed in SCATTER_VISIBLE_SEEDS])
    resolved = []
    missing = []
    for seed_value in requested:
        if seed_value in seed_to_index:
            resolved.append(seed_to_index[seed_value])
        else:
            missing.append(seed_value)

    if missing:
        print(f"Warning: scatter seeds not found in current input and will be skipped: {missing}")
    if not resolved:
        raise SystemExit(
            "SCATTER_VISIBLE_SEEDS does not match any seed in this input. "
            f"Available seeds: {list(seeds)}"
        )
    return np.asarray(resolved, dtype=int)


def _resolve_scatter_seed_selection(seeds):
    seed_indices = _resolve_scatter_seed_indices(seeds)
    display_seeds = [seeds[idx] for idx in seed_indices]
    return seed_indices, display_seeds


def _build_condition_offsets(num_visible):
    if num_visible <= 1:
        return np.array([0.0])
    if SCATTER_ALIGN_CONDITIONS:
        return np.zeros(num_visible)
    return np.linspace(-0.22, 0.22, num_visible)


def _sanitize_token(text):
    token = sanitize_path_component(text, default="all")
    token = token.replace("-", "_").replace(".", "_")
    token = re.sub(r"_+", "_", token).strip("_")
    return token or "all"


def _visibility_suffix(visible_conditions, all_conditions):
    if visible_conditions == all_conditions:
        return "all_conditions"
    joined = "_".join(_sanitize_token(name) for name in visible_conditions)
    return f"conditions_{joined}" if joined else "conditions"


def _scatter_seed_suffix(display_seeds, all_seeds):
    if len(display_seeds) == len(all_seeds) and list(display_seeds) == list(all_seeds):
        return "all_seeds"
    joined = "_".join(_sanitize_token(str(seed)) for seed in display_seeds)
    return f"selected_seeds_{joined}" if joined else "selected_seeds"


def _build_scatter_axis(display_seeds):
    x_positions = np.arange(1, len(display_seeds) + 1, dtype=float)
    mode = str(SCATTER_XLABEL_MODE).strip().lower()
    tick_step = max(1, int(SCATTER_MC_TICK_STEP))

    if mode == "mc_id":
        base_labels = [f"{SCATTER_MC_ID_START + idx}" for idx in range(len(display_seeds))]
        xlabel = "Monte Carlo ID"
    elif mode == "seed":
        base_labels = [str(seed) for seed in display_seeds]
        xlabel = "Random Seed"
    else:
        raise SystemExit(f"Unsupported SCATTER_XLABEL_MODE={SCATTER_XLABEL_MODE!r}. Use 'mc_id' or 'seed'.")

    tick_indices = np.arange(0, len(display_seeds), tick_step, dtype=int)
    tick_positions = x_positions[tick_indices]
    tick_labels = [base_labels[idx] for idx in tick_indices]
    return x_positions, tick_positions, tick_labels, xlabel


def _resolve_convergence_band(curves, mean, std, valid):
    mode = str(CONV_BAND_MODE).strip().lower()

    if mode == "std":
        scale = float(CONV_BAND_SCALE)
        lower = mean - scale * std
        upper = mean + scale * std
    elif mode == "percentile":
        low, high = CONV_BAND_PERCENTILES
        if not (0 <= low < high <= 100):
            raise SystemExit(
                f"Invalid CONV_BAND_PERCENTILES={CONV_BAND_PERCENTILES}. Expected 0 <= low < high <= 100."
            )

        lower = np.full_like(mean, np.nan, dtype=float)
        upper = np.full_like(mean, np.nan, dtype=float)
        valid_cols = np.where(valid)[0]
        if valid_cols.size:
            percentiles = np.nanpercentile(curves[:, valid_cols], [low, high], axis=0)
            lower[valid_cols] = percentiles[0]
            upper[valid_cols] = percentiles[1]
    else:
        raise SystemExit(f"Unsupported CONV_BAND_MODE={CONV_BAND_MODE!r}. Use 'std' or 'percentile'.")

    lower[~valid] = np.nan
    upper[~valid] = np.nan
    return lower, upper


def _describe_convergence_band():
    mode = str(CONV_BAND_MODE).strip().lower()
    if not CONV_SHOW_BAND:
        return "mean only"
    if mode == "std":
        scale = float(CONV_BAND_SCALE)
        if np.isclose(scale, 1.0):
            return "mean +/- std"
        return f"mean +/- {scale:g} std"

    low, high = CONV_BAND_PERCENTILES
    return f"mean with {low:g}-{high:g} percentile band"


def plot_ablation_scatter(
    n_values,
    seeds,
    condition_names,
    utility,
    completion,
    save_path,
    scatter_seed_indices=None,
    scatter_display_seeds=None,
):
    cfg = get_family_figure_config(FAMILY, "endpoint_scatter")
    subplot_cfg_base = dict(cfg)
    subplot_cfg_base["show_legend"] = False
    visible_conditions = _resolve_visible_conditions(condition_names)
    condition_styles = _build_condition_styles(condition_names)
    condition_indices = [condition_names.index(name) for name in visible_conditions]
    offsets = _build_condition_offsets(len(condition_indices))
    if scatter_seed_indices is None or scatter_display_seeds is None:
        seed_indices, display_seeds = _resolve_scatter_seed_selection(seeds)
    else:
        seed_indices = np.asarray(scatter_seed_indices, dtype=int)
        display_seeds = list(scatter_display_seeds)

    num_n = len(n_values)
    num_s = len(display_seeds)
    x_positions, tick_positions, tick_labels, xlabel = _build_scatter_axis(display_seeds)

    configured_row_labels = list(cfg.get("shared_row_ylabels", ROW_YLABELS))
    row_specs = []
    if cfg.get("show_utility_row", False):
        utility_label = configured_row_labels[0] if configured_row_labels else ROW_YLABELS[0]
        row_specs.append((utility, utility_label))

    completion_label = (
        configured_row_labels[1]
        if len(configured_row_labels) > 1
        else configured_row_labels[0] if configured_row_labels else ROW_YLABELS[-1]
    )
    row_specs.append((completion, completion_label))

    num_rows = len(row_specs)
    fig_w = cfg["subplot_w_cm"] * num_n
    fig_h = cfg["subplot_h_cm"] * num_rows
    fig, axes = plt.subplots(num_rows, num_n, figsize=cm_size_to_inch((fig_w, fig_h)), squeeze=False)
    active_axes = []

    for row, (data, row_ylabel) in enumerate(row_specs):
        for col, n_value in enumerate(n_values):
            ax = axes[row][col]
            active_axes.append(ax)

            if SCATTER_SHOW_CONNECTION_LINES:
                for scatter_idx, base_x in enumerate(x_positions):
                    xs = []
                    ys = []
                    seed_idx = seed_indices[scatter_idx]
                    for offset, cond_idx in zip(offsets, condition_indices):
                        y = data[col, seed_idx, cond_idx]
                        if np.isnan(y):
                            continue
                        xs.append(base_x + offset)
                        ys.append(y)
                    if len(xs) >= 2:
                        ax.plot(xs, ys, **CONN_LINE)

            for offset, cond_idx in zip(offsets, condition_indices):
                cond_name = condition_names[cond_idx]
                style = condition_styles[cond_name]
                y = data[col, seed_indices, cond_idx]
                valid = ~np.isnan(y)
                ax.plot(
                    x_positions[valid] + offset,
                    y[valid],
                    linestyle="none",
                    marker=style["marker"],
                    color=style["color"],
                    markersize=style["markersize"],
                    markeredgewidth=style.get("markeredgewidth", 1.2),
                    zorder=4,
                )

            margin = 0.3 + (np.max(np.abs(offsets)) if offsets.size else 0.0)
            ax.set_xticks(tick_positions)
            ax.set_xticklabels(tick_labels)
            ax.set_xlim(0.5 - margin, num_s + 0.5 + margin)
            subplot_cfg = dict(subplot_cfg_base)
            subplot_cfg["title"] = _build_subplot_title(cfg, n_value)
            subplot_cfg["ylabel"] = None if cfg.get("use_shared_row_ylabels", False) else row_ylabel
            STYLE_HELPER.apply_common_style(
                ax,
                cfg=subplot_cfg,
                xlabel=xlabel,
                ylabel=None,
                title=None,
            )
            STYLE_HELPER.apply_axis_controls(ax, cfg=subplot_cfg)
            if row_ylabel == "Coalition Utility":
                _apply_scientific_utility_ticks(ax, cfg)

    legend_handles = []
    for cond_name in visible_conditions:
        style = condition_styles[cond_name]
        legend_handles.append(
            mlines.Line2D(
                [],
                [],
                linestyle="none",
                marker=style["marker"],
                color=style["color"],
                markersize=style["markersize"],
                markeredgewidth=style.get("markeredgewidth", 1.2),
                label=style.get("legend_label", style["label"]),
            )
        )
    _apply_subplots_adjust(fig, cfg)
    if cfg.get("use_shared_row_ylabels", False):
        _draw_shared_row_ylabels(fig, axes, [label for _, label in row_specs], cfg)
    _add_configured_legend(
        fig,
        active_axes,
        legend_handles,
        [handle.get_label() for handle in legend_handles],
        cfg,
    )

    if cfg.get("show_titles", True) and cfg.get("show_suptitle", cfg.get("show_title", True)):
        fig.suptitle(
            cfg["title"],
            fontsize=cfg["title_fontsize"],
            fontweight=cfg["title_fontweight"],
            y=cfg.get("suptitle_y", 0.98),
        )
    STYLE_HELPER.finalize_and_save(fig, save_path, tight_layout_rect=[0, 0, 1, 0.95], cfg=cfg)
    return fig


def plot_ablation_convergence(n_values, condition_names, convergence, save_path):
    cfg = get_family_figure_config(
        FAMILY,
        "convergence",
        title=get_family_figure_config(
            FAMILY,
            "convergence",
            band_desc=_describe_convergence_band(),
        )["title_template"].format(band_desc=_describe_convergence_band()),
    )
    subplot_cfg_base = dict(cfg)
    subplot_cfg_base["show_legend"] = False
    if cfg.get("use_shared_ylabel", False):
        subplot_cfg_base["ylabel"] = None
    visible_conditions = _resolve_visible_conditions(condition_names)
    condition_styles = _build_condition_styles(condition_names)
    condition_indices = [condition_names.index(name) for name in visible_conditions]

    num_n = len(n_values)
    num_rounds = convergence.shape[-1]
    rounds = np.arange(1, num_rounds + 1)

    fig_w = cfg["convergence_subplot_w_cm"] * num_n
    fig_h = cfg["convergence_subplot_h_cm"]
    fig, axes = plt.subplots(1, num_n, figsize=cm_size_to_inch((fig_w, fig_h)), squeeze=False)
    active_axes = []

    for col, n_value in enumerate(n_values):
        ax = axes[0][col]
        active_axes.append(ax)

        for cond_idx in condition_indices:
            cond_name = condition_names[cond_idx]
            style = condition_styles[cond_name]
            curves = convergence[col, :, cond_idx, :]
            mean, std, valid = _mean_and_std(curves)

            if not np.any(valid):
                continue

            ax.plot(
                rounds,
                mean,
                color=style["color"],
                linewidth=style["linewidth"],
                label=style["label"],
            )
            if CONV_SHOW_BAND:
                lower, upper = _resolve_convergence_band(curves, mean, std, valid)
                ax.fill_between(
                    rounds[valid],
                    lower[valid],
                    upper[valid],
                    color=style["color"],
                    alpha=BAND_ALPHA,
                    linewidth=0,
                )

        ax.set_xlim(1, max(1, num_rounds))
        subplot_cfg = dict(subplot_cfg_base)
        subplot_cfg["title"] = _build_subplot_title(cfg, n_value)
        STYLE_HELPER.apply_common_style(
            ax,
            cfg=subplot_cfg,
            xlabel=cfg.get("xlabel", "Round"),
            ylabel=None,
            title=None,
        )
        STYLE_HELPER.apply_axis_controls(ax, cfg=subplot_cfg)
        _apply_scientific_utility_ticks(ax, cfg)

    legend_handles = []
    for cond_name in visible_conditions:
        style = condition_styles[cond_name]
        legend_handles.append(
            mlines.Line2D(
                [],
                [],
                color=style["color"],
                linewidth=style["linewidth"],
                label=style.get("legend_label", style["label"]),
            )
        )
    _apply_subplots_adjust(fig, cfg)
    if cfg.get("use_shared_ylabel", False):
        _draw_shared_ylabel(
            fig,
            axes,
            cfg.get("shared_ylabel_text", cfg.get("ylabel")),
            cfg,
            "shared_ylabel_x",
        )
    _add_configured_legend(
        fig,
        active_axes,
        legend_handles,
        [handle.get_label() for handle in legend_handles],
        cfg,
    )

    if cfg.get("show_titles", True) and cfg.get("show_suptitle", cfg.get("show_title", True)):
        fig.suptitle(
            cfg["title"],
            fontsize=cfg["title_fontsize"],
            fontweight=cfg["title_fontweight"],
            y=cfg.get("suptitle_y", 0.98),
        )
    STYLE_HELPER.finalize_and_save(fig, save_path, tight_layout_rect=[0, 0, 1, 0.94], cfg=cfg)
    return fig


def main(input_path=None):
    STYLE_HELPER.apply_rcparams()

    if input_path is None and len(sys.argv) > 1:
        input_path = sys.argv[1]
    if input_path is None:
        input_path = PREFERRED_INPUT
    input_path = resolve_input_selector(input_path)

    print("\nLoading ablation data...")
    n_values, seeds, condition_names, utility, completion, convergence, run_meta = load_ablation_data(input_path)
    output_source = run_meta.get("run_name") or infer_source_name(run_meta.get("source_path"), fallback="ablation")
    configure_output_dir(output_source)
    _resolve_required_condition_indices(condition_names)
    visible_conditions = _resolve_visible_conditions(condition_names)

    print(f"  Input path         = {run_meta.get('source_path', '')}")
    print(f"  Source type        = {run_meta.get('source_type', '')}")
    print(f"  Run name           = {run_meta.get('run_name', '')}")
    if run_meta.get("source_type") == "run_dir":
        cache_state = "cache hit" if run_meta.get("used_cache") else "cache rebuilt"
        print(f"  Aggregation        = {cache_state}")
        print(f"  Cache path         = {run_meta.get('cache_path', '')}")
    elif run_meta.get("source_type") == "cache_file":
        print("  Aggregation        = direct cache load")
    else:
        print(f"  Aggregation        = direct {run_meta.get('source_type', '')} load")

    print(f"  N_values           = {n_values}")
    print(f"  seeds              = {seeds}")
    print(f"  conditions         = {condition_names}")
    print(
        "  JSON comparison    = "
        f"{JSON_BELIEF_CONDITION} vs {JSON_BASELINE_CONDITION}"
    )
    print(f"  visible_conditions = {visible_conditions}")
    scatter_seed_indices, scatter_display_seeds = _resolve_scatter_seed_selection(seeds)
    if SCATTER_VISIBLE_SEEDS is None:
        print("  scatter seeds      = all")
    else:
        print(f"  scatter seeds      = {scatter_display_seeds}")
    print(f"  convergence band   = {_describe_convergence_band()}")
    for cond_idx, cond_name in enumerate(condition_names):
        utility_valid = int(np.sum(~np.isnan(utility[:, :, cond_idx])))
        completion_valid = int(np.sum(~np.isnan(completion[:, :, cond_idx])))
        print(f"  valid[{cond_name}] utility={utility_valid} completion={completion_valid}")
    print(f"  convergence rounds = {convergence.shape[-1]}")

    visibility_token = _visibility_suffix(visible_conditions, _unique_preserve_order(condition_names))
    scatter_seed_token = _scatter_seed_suffix(
        [_normalize_seed_value(seed) for seed in scatter_display_seeds],
        [_normalize_seed_value(seed) for seed in seeds],
    )
    scatter_base = f"endpoint_scatter_{visibility_token}"
    if scatter_seed_token != "all_seeds":
        scatter_base = f"{scatter_base}_{scatter_seed_token}"
    scatter_path = build_output_stem(scatter_base)
    convergence_path = build_output_stem(f"convergence_{visibility_token}")
    scatter_json_path = f"{scatter_path}.json"
    convergence_json_path = f"{convergence_path}.json"

    print(f"\nFigure output dir      = {FIGURES_DIR}")
    print(f"Plotting endpoint scatter -> {scatter_path}")
    plot_ablation_scatter(
        n_values,
        seeds,
        condition_names,
        utility,
        completion,
        scatter_path,
        scatter_seed_indices=scatter_seed_indices,
        scatter_display_seeds=scatter_display_seeds,
    )

    if convergence.shape[-1] > 0 and not np.all(np.isnan(convergence)):
        print(f"Plotting convergence figure -> {convergence_path}")
        plot_ablation_convergence(n_values, condition_names, convergence, convergence_path)
    else:
        print("Skipping convergence figure: no convergence_utility data found.")

    print(f"Writing endpoint scatter JSON -> {scatter_json_path}")
    _write_json(
        scatter_json_path,
        build_ablation_scatter_payload(
            n_values,
            seeds,
            condition_names,
            utility,
            completion,
            run_meta,
            scatter_seed_indices=scatter_seed_indices,
        ),
    )

    print(f"Writing convergence summary JSON -> {convergence_json_path}")
    _write_json(
        convergence_json_path,
        build_ablation_summary_payload(
            n_values,
            seeds,
            condition_names,
            utility,
            completion,
            run_meta,
        ),
    )

    print("\nDone.")
    plt.show()


if __name__ == "__main__":
    main()
