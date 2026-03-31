"""
plot_ablation.py
================
Plot ablation results produced by Batch_Ablation.m.

Outputs:
1. Endpoint scatter figure:
   - final coalition utility
   - final task completion rate
2. Convergence figure:
   - mean +/- std coalition utility over rounds

Usage:
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
    from plot_style_helper import PlotStyleHelper
except ImportError:
    from .plot_style_helper import PlotStyleHelper
try:
    from ablation_result_aggregator import AblationResultAggregator
except ImportError:
    from .ablation_result_aggregator import AblationResultAggregator


SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
ROOT_DIR = os.path.dirname(SCRIPT_DIR)
FIGURES_DIR = os.path.join(ROOT_DIR, "figures", "paper")
SEARCH_DIRS = [
    os.path.join(ROOT_DIR, "results", "batch", "ablation"),
    os.path.join(ROOT_DIR, "results", "batch"),
]

# Optional manual input selector.
# None / ""      -> auto-pick the latest ablation run_dir; fallback to latest legacy MAT.
# run name       -> exact run directory name under SEARCH_DIRS.
# relative / abs -> run_dir, cache file, or legacy MAT path.




# Example:
#   PREFERRED_INPUT = "20260330_190655_N6-6_M10_K6_C3_S3"
#   PREFERRED_INPUT = r"results/batch/ablation/20260330_190655_N6-6_M10_K6_C3_S3"
# PREFERRED_INPUT = "20260330_190655_N6-6_M10_K6_C3_S3"
PREFERRED_INPUT = None


# None means "show all conditions found in the input".
# Example:
VISIBLE_CONDITIONS = ['belief_off', 'belief_on_quantile']
# VISIBLE_CONDITIONS = None

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

CONN_LINE = {"color": "#B3B3B3", "linewidth": 0.8, "alpha": 0.7, "zorder": 2}
BAND_ALPHA = 0.16

ROW_YLABELS = ["Coalition Utility", "Task Completion Rate"]
ROW_TITLES = ["Endpoint Utility", "Endpoint Completion"]

PLOT_GLOBAL = {
    "subplot_w": 3.5,
    "subplot_h": 3.1,
    "convergence_subplot_w": 3.6,
    "convergence_subplot_h": 2.9,
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
    "save_bbox_inches": "tight",
}

STYLE_HELPER = PlotStyleHelper(PLOT_GLOBAL, FIGURES_DIR)


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


def _build_condition_offsets(num_visible):
    if num_visible <= 1:
        return np.array([0.0])
    return np.linspace(-0.22, 0.22, num_visible)


def _sanitize_token(text):
    return re.sub(r"[^A-Za-z0-9_\\-]+", "-", text).strip("-") or "all"


def _visibility_suffix(visible_conditions, all_conditions):
    if visible_conditions == all_conditions:
        return "all"
    return "-".join(_sanitize_token(name) for name in visible_conditions)


def plot_ablation_scatter(n_values, seeds, condition_names, utility, completion, save_path):
    visible_conditions = _resolve_visible_conditions(condition_names)
    condition_styles = _build_condition_styles(condition_names)
    condition_indices = [condition_names.index(name) for name in visible_conditions]
    offsets = _build_condition_offsets(len(condition_indices))

    num_n = len(n_values)
    num_s = len(seeds)
    x_ticks = np.arange(1, num_s + 1)
    x_labels = [str(seed) for seed in seeds]

    fig_w = PLOT_GLOBAL["subplot_w"] * num_n
    fig_h = PLOT_GLOBAL["subplot_h"] * 2
    fig, axes = plt.subplots(2, num_n, figsize=(fig_w, fig_h), squeeze=False)

    for row, (data, ylabel) in enumerate(zip([utility, completion], ROW_YLABELS)):
        for col, n_value in enumerate(n_values):
            ax = axes[row][col]

            for si, base_x in enumerate(x_ticks):
                xs = []
                ys = []
                for offset, cond_idx in zip(offsets, condition_indices):
                    y = data[col, si, cond_idx]
                    if np.isnan(y):
                        continue
                    xs.append(base_x + offset)
                    ys.append(y)
                if len(xs) >= 2:
                    ax.plot(xs, ys, **CONN_LINE)

            for offset, cond_idx in zip(offsets, condition_indices):
                cond_name = condition_names[cond_idx]
                style = condition_styles[cond_name]
                y = data[col, :, cond_idx]
                valid = ~np.isnan(y)
                ax.plot(
                    x_ticks[valid] + offset,
                    y[valid],
                    linestyle="none",
                    marker=style["marker"],
                    color=style["color"],
                    markersize=style["markersize"],
                    markeredgewidth=style.get("markeredgewidth", 1.2),
                    zorder=4,
                )

            margin = 0.3 + (np.max(np.abs(offsets)) if offsets.size else 0.0)
            ax.set_xticks(x_ticks)
            ax.set_xticklabels(x_labels)
            ax.set_xlim(0.5 - margin, num_s + 0.5 + margin)
            STYLE_HELPER.apply_common_style(
                ax,
                xlabel="Seed",
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

    fig_w = PLOT_GLOBAL["convergence_subplot_w"] * num_n
    fig_h = PLOT_GLOBAL["convergence_subplot_h"]
    fig, axes = plt.subplots(1, num_n, figsize=(fig_w, fig_h), squeeze=False)

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
            ax.fill_between(
                rounds[valid],
                (mean - std)[valid],
                (mean + std)[valid],
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

    fig.suptitle("Ablation convergence by N (mean +/- std)", fontsize=12, fontweight="bold", y=1.08)
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
    for cond_idx, cond_name in enumerate(condition_names):
        utility_valid = int(np.sum(~np.isnan(utility[:, :, cond_idx])))
        completion_valid = int(np.sum(~np.isnan(completion[:, :, cond_idx])))
        print(f"  valid[{cond_name}] utility={utility_valid} completion={completion_valid}")
    print(f"  convergence rounds = {convergence.shape[-1]}")

    timestamp_token = _extract_timestamp_token(run_meta)
    visibility_token = _visibility_suffix(visible_conditions, _unique_preserve_order(condition_names))
    scatter_path = STYLE_HELPER.build_output_path(timestamp_token, f"ablation_scatter_{visibility_token}")
    convergence_path = STYLE_HELPER.build_output_path(timestamp_token, f"ablation_convergence_{visibility_token}")

    print(f"\nPlotting endpoint scatter -> {scatter_path}")
    plot_ablation_scatter(n_values, seeds, condition_names, utility, completion, scatter_path)

    if convergence.shape[-1] > 0 and not np.all(np.isnan(convergence)):
        print(f"Plotting convergence figure -> {convergence_path}")
        plot_ablation_convergence(n_values, condition_names, convergence, convergence_path)
    else:
        print("Skipping convergence figure: no convergence_utility data found.")

    print("\nDone.")
    plt.show()


if __name__ == "__main__":
    main()
