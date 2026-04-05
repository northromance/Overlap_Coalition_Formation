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

import matplotlib.lines as mlines
import matplotlib.pyplot as plt
import numpy as np
try:
    import h5py
except ImportError:
    h5py = None

try:
    from plot_style_helper import PlotStyleHelper, build_results_figures_dir, cm_size_to_inch, infer_source_name
except ImportError:
    from .plot_style_helper import PlotStyleHelper, build_results_figures_dir, cm_size_to_inch, infer_source_name
try:
    from ablation_result_aggregator import AblationResultAggregator
except ImportError:
    from .ablation_result_aggregator import AblationResultAggregator


SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
ROOT_DIR = os.path.dirname(SCRIPT_DIR)
FIGURES_DIR = build_results_figures_dir(ROOT_DIR, "ablation")
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
CONDITION_STYLE_MAP = {
    "belief_off": {
        "color": "#C0392B",
        "marker": "o",
        "markersize": 5,
        "markeredgewidth": 1.8,
        "linewidth": 2.0,
        "label": "belief_off",
    },
    "belief_on": {
        "color": "#2E6DB4",
        "marker": "o",
        "markersize": 5,
        "markeredgewidth": 1.2,
        "linewidth": 2.0,
        "label": "belief_on",
    },
    "belief_on_quantile": {
        "color": "#2E6DB4",
        "marker": "o",
        "markersize": 5,
        "markeredgewidth": 1.2,
        "linewidth": 2.0,
        "label": "belief_on_quantile",
    },
    "belief_on_expected": {
        "color": "#1F8A5B",
        "marker": "^",
        "markersize": 8.0,
        "markeredgewidth": 1.2,
        "linewidth": 2.0,
        "label": "belief_on_expected",
    },
}
FALLBACK_COLORS = ["#7A5195", "#EF5675", "#FFA600", "#4C78A8", "#72B7B2"]
FALLBACK_MARKERS = ["s", "D", "P", "v", ">"]

CONN_LINE = {"color": "#B3B3B3", "linewidth": 0.8, "alpha": 0.7, "zorder": 2}  # 连接线样式。
BAND_ALPHA = 0.16  # 收敛阴影带透明度。
ROW_YLABELS = ["Coalition Utility", "Task Completion Rate"]
ROW_TITLES = ["Endpoint Utility", "Endpoint Completion"]

# 全局绘图参数。
# - 所有物理尺寸统一使用 cm，真正传给 Matplotlib 时再换算为英寸。
# - subplot_w_cm / subplot_h_cm: 端点散点图单个子图尺寸，单位 cm。
# - convergence_subplot_w_cm / convergence_subplot_h_cm: 收敛图单个子图尺寸，单位 cm。
# - 其余字段控制字号、网格、图例和保存行为。
PLOT_GLOBAL = {
    "subplot_w_cm": 8.89,
    "subplot_h_cm": 7.87,
    "convergence_subplot_w_cm": 9.14,
    "convergence_subplot_h_cm": 7.37,
    "xlabel_fontsize": 10,
    "ylabel_fontsize": 10,
    "title_fontsize": 11,
    "title_fontweight": "bold",
    "label_fontweight": "normal",
    "tick_fontsize": 9,
    "tick_fontweight": "normal",
    "legend_fontsize": 9,
    "show_titles": True,
    "show_grid": True,
    "grid_alpha": 0.35,
    "grid_linestyle": "--",
    "hide_top_spine": True,
    "hide_right_spine": True,
    "show_legend": False,
    "tight_layout": True,
    "save_dpi": 150,
    "save_format": "png",
    "save_formats": ["png", "eps"],
    "save_bbox_inches": "tight",
}

os.makedirs(FIGURES_DIR, exist_ok=True)
STYLE_HELPER = PlotStyleHelper(PLOT_GLOBAL, FIGURES_DIR)


def configure_output_dir(source_name):
    global FIGURES_DIR
    FIGURES_DIR = build_results_figures_dir(ROOT_DIR, "ablation", source_name)
    os.makedirs(FIGURES_DIR, exist_ok=True)
    STYLE_HELPER.set_figures_dir(FIGURES_DIR)
    return FIGURES_DIR


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
            styles[cond_name] = dict(CONDITION_STYLE_MAP[cond_name])
            continue

        styles[cond_name] = {
            "color": FALLBACK_COLORS[fallback_idx % len(FALLBACK_COLORS)],
            "marker": FALLBACK_MARKERS[fallback_idx % len(FALLBACK_MARKERS)],
            "markersize": 7.5,
            "markeredgewidth": 1.2,
            "linewidth": 2.0,
            "label": cond_name,
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
    return re.sub(r"[^A-Za-z0-9_\\-]+", "-", text).strip("-") or "all"


def _visibility_suffix(visible_conditions, all_conditions):
    if visible_conditions == all_conditions:
        return "all"
    return "-".join(_sanitize_token(name) for name in visible_conditions)


def _scatter_seed_suffix(display_seeds, all_seeds):
    if len(display_seeds) == len(all_seeds) and list(display_seeds) == list(all_seeds):
        return "allseeds"
    return "seedsel-" + "-".join(_sanitize_token(str(seed)) for seed in display_seeds)


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

    fig_w = PLOT_GLOBAL["subplot_w_cm"] * num_n
    fig_h = PLOT_GLOBAL["subplot_h_cm"] * 2
    fig, axes = plt.subplots(2, num_n, figsize=cm_size_to_inch((fig_w, fig_h)), squeeze=False)

    for row, (data, ylabel) in enumerate(zip([utility, completion], ROW_YLABELS)):
        for col, n_value in enumerate(n_values):
            ax = axes[row][col]

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
            STYLE_HELPER.apply_common_style(
                ax,
                xlabel=xlabel,
                ylabel=ylabel,
                title=f"N = {n_value}",
            )

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
                label=style["label"],
            )
        )
    fig.legend(
        handles=legend_handles,
        loc="upper center",
        ncol=max(1, min(3, len(legend_handles))),
        framealpha=0.9,
        edgecolor="#cccccc",
        fontsize=PLOT_GLOBAL["legend_fontsize"],
        bbox_to_anchor=(0.5, 1.02),
    )

    for row, title in enumerate(ROW_TITLES):
        axes[row][0].annotate(
            title,
            xy=(0, 0.5),
            xycoords="axes fraction",
            xytext=(-0.28, 0.5),
            textcoords="axes fraction",
            fontsize=9,
            fontweight="bold",
            rotation=90,
            va="center",
            ha="center",
            annotation_clip=False,
        )

    fig.suptitle("Ablation endpoint comparison", fontsize=12, fontweight="bold", y=1.07)
    STYLE_HELPER.finalize_and_save(fig, save_path, tight_layout_rect=[0, 0, 1, 0.95])
    return fig


def plot_ablation_convergence(n_values, condition_names, convergence, save_path):
    visible_conditions = _resolve_visible_conditions(condition_names)
    condition_styles = _build_condition_styles(condition_names)
    condition_indices = [condition_names.index(name) for name in visible_conditions]

    num_n = len(n_values)
    num_rounds = convergence.shape[-1]
    rounds = np.arange(1, num_rounds + 1)

    fig_w = PLOT_GLOBAL["convergence_subplot_w_cm"] * num_n
    fig_h = PLOT_GLOBAL["convergence_subplot_h_cm"]
    fig, axes = plt.subplots(1, num_n, figsize=cm_size_to_inch((fig_w, fig_h)), squeeze=False)

    for col, n_value in enumerate(n_values):
        ax = axes[0][col]

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
        STYLE_HELPER.apply_common_style(
            ax,
            xlabel="Round",
            ylabel="Coalition Utility",
            title=f"N = {n_value}",
        )

    legend_handles = []
    for cond_name in visible_conditions:
        style = condition_styles[cond_name]
        legend_handles.append(
            mlines.Line2D([], [], color=style["color"], linewidth=style["linewidth"], label=style["label"])
        )
    fig.legend(
        handles=legend_handles,
        loc="upper center",
        ncol=max(1, min(3, len(legend_handles))),
        framealpha=0.9,
        edgecolor="#cccccc",
        fontsize=PLOT_GLOBAL["legend_fontsize"],
        bbox_to_anchor=(0.5, 1.02),
    )

    fig.suptitle(
        f"Ablation convergence by N ({_describe_convergence_band()})",
        fontsize=12,
        fontweight="bold",
        y=1.08,
    )
    STYLE_HELPER.finalize_and_save(fig, save_path, tight_layout_rect=[0, 0, 1, 0.94])
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
    scatter_base = f"ablation_scatter_{visibility_token}"
    if scatter_seed_token != "allseeds":
        scatter_base = f"{scatter_base}_{scatter_seed_token}"
    scatter_path = STYLE_HELPER.build_output_stem(scatter_base)
    convergence_path = STYLE_HELPER.build_output_stem(f"ablation_convergence_{visibility_token}")

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

    print("\nDone.")
    plt.show()


if __name__ == "__main__":
    main()
