"""
plot_convergence_detail.py
==========================
从 Batch_VaryN.m / Batch_VaryM.m 的结果中绘制“四算法外层 round 收敛细节图”。

功能:
  - 支持 VaryN / VaryM 两类批量结果
  - 支持均值曲线(mean over seeds)和单 seed 真实轨迹
  - 支持四种指标:
      utility / completion / cost / completed_value
  - 一张图中对比 Huo2025 / Qi2023 / Shi2024 / OCF_SAtabu

支持输入:
  - VaryN 聚合 .mat 文件
  - VaryM run directory / run_config.mat / progress_status.mat / cache 文件
  - 不传输入时自动搜索 results/batch 下最新可用结果

用法:
  python plot/plot_convergence_detail.py
  python plot/plot_convergence_detail.py --family varyN --n 16 --seed mean
  python plot/plot_convergence_detail.py --family varyN --n 16 --seed 2486
  python plot/plot_convergence_detail.py --family varyM --m 16 --metric cost
  python plot/plot_convergence_detail.py results/batch/varyM/20260329_190314_N8_M8-20_K6_S11

说明:
  - 如果你只是想快速改默认行为，可以直接修改本文件顶部“可调参数区”
  - 如果你想临时覆盖默认行为，优先使用命令行参数
  - “某一轮内部 iteration 演化”不在本脚本范围内，那个继续用 Plot_InnerLoop_Evolution.m
"""

import argparse
import glob
import os
import sys

import matplotlib.pyplot as plt
import numpy as np

from plot_style_helper import PlotStyleHelper
from varym_result_aggregator import VaryMResultAggregator

try:
    import mat73
except ImportError:
    mat73 = None


SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
ROOT_DIR = os.path.dirname(SCRIPT_DIR)
FIGURES_DIR = os.path.join(ROOT_DIR, "figures", "paper")
SEARCH_DIRS_VARYN = [
    os.path.join(ROOT_DIR, "results", "batch", "varyN"),
    os.path.join(ROOT_DIR, "results", "batch"),
]
SEARCH_DIRS_VARYM = [
    os.path.join(ROOT_DIR, "results", "batch", "varyM"),
    os.path.join(ROOT_DIR, "results", "batch"),
]

# =========================
# 顶部可调参数区
# =========================
# 输入来源:
# - None: 自动搜索最新结果
# - run name: 例如 "20260329_190314_N8_M8-20_K6_S11"
# - 文件名: 例如 "N4-16_M10_K6_S21_20260329_115653.mat"
# - 相对路径 / 绝对路径: 指向具体的 VaryN MAT 或 VaryM run_dir
PREFERRED_INPUT = '20260329_190314_N8_M8-20_K6_S11'

# 结果家族:
# - "auto"  : 自动识别 VaryN / VaryM
# - "varyN" : 强制按 VaryN 读取
# - "varyM" : 强制按 VaryM 读取
DEFAULT_FAMILY = "auto"

# 默认目标规模:
# - DEFAULT_N 仅对 VaryN 生效; None 表示取最大 N
# - DEFAULT_M 仅对 VaryM 生效; None 表示取最大 M
# 可选参数补充:
# - DEFAULT_N 可填 None 或结果文件中的具体 N 值
#   例如按当前 Exp_Params.m, 常见可选值为 4 / 6 / 8 / 10 / 12 / 14 / 16
# - DEFAULT_M 可填 None 或结果文件中的具体 M 值
#   例如按当前结果可写 14 / 16; 更稳妥的做法是以实际结果文件中的 M_values 为准
DEFAULT_N = None
DEFAULT_M = 16

# 默认 seed 模式:
# - "mean" : 对当前 N/M 下所有有效 seed 求均值
# - 整数     : 只画某一个 seed 的真实轨迹
DEFAULT_SEED = "mean"

# 默认指标:
# - "utility"
# - "completion"
# - "cost"
# - "completed_value"
DEFAULT_METRIC = "completion"

# 是否在脚本结束后弹出图窗:
# - True  : 交互环境下显示图窗
# - False : 只保存图片，不弹窗
AUTO_SHOW_FIGURE = True

# 曲线细节显示:
# - 平均曲线时是否显示 std 阴影带
# - 阴影带透明度
# - marker 稀疏显示阈值与步长
CURVE_DETAIL_CONFIG = {
    "show_mean_band": True,
    "band_alpha": 0.16,
    "markevery_divisor": 10,
    "markevery_threshold": 12,
}

# =========================
# 样式与绘图配置
# =========================
# 这里控制算法颜色 / 点型 / 线型 / 图例名字
ALG_STYLE = {
    "Huo2025": dict(color="#4878CF", marker="o", ls="-", label="Huo2025"),
    "Qi2023": dict(color="#6ACC65", marker="s", ls="--", label="Qi2023"),
    "Shi2024": dict(color="#D65F5F", marker="^", ls="-.", label="Shi2024"),
    "OCF_SAtabu": dict(color="#B47CC7", marker="D", ls="-", label="Ours (OCF-SA)"),
}
DEFAULT_STYLE = dict(color="#888888", marker="x", ls=":", label="Unknown")

# 指标定义:
# - curve_field: 数据结构中的字段名
# - ylabel     : y 轴标题
# - title_name : 图标题中的指标名
# - stem       : 自动输出文件名中的标识
METRIC_SPECS = {
    "utility": {
        "curve_field": "convergence_utility",
        "ylabel": "Coalition Utility",
        "title_name": "Coalition Utility",
        "stem": "utility",
    },
    "completion": {
        "curve_field": "convergence_completion",
        "ylabel": "Avg. Task Completion Degree",
        "title_name": "Task Completion Degree",
        "stem": "completion",
    },
    "cost": {
        "curve_field": "convergence_cost",
        "ylabel": "Total Global Cost",
        "title_name": "Total Global Cost",
        "stem": "cost",
    },
    "completed_value": {
        "curve_field": "convergence_completed_value",
        "ylabel": "Total Completed Value",
        "title_name": "Total Completed Value",
        "stem": "completed_value",
    },
}

# 全局绘图样式:
# - 图尺寸 / 线宽 / 字号 / 网格 / 保存格式等
PLOT_GLOBAL = {
    "figsize": (6.2, 4.6),
    "linewidth": 2.0,
    "markersize": 4,
    "markeredgewidth": 0.8,
    "xlabel_fontsize": 11,
    "ylabel_fontsize": 11,
    "title_fontsize": 12,
    "title_pad": 8,
    "tick_fontsize": 10,
    "legend_fontsize": 9,
    "show_titles": True,
    "show_grid": True,
    "grid_linestyle": "--",
    "grid_linewidth": 0.6,
    "grid_alpha": 0.35,
    "show_legend": True,
    "legend_framealpha": 0.85,
    "legend_edgecolor": "#cccccc",
    "hide_top_spine": True,
    "hide_right_spine": True,
    "save_format": "png",
    "save_dpi": 150,
    "save_bbox_inches": "tight",
    "tight_layout": True,
}

os.makedirs(FIGURES_DIR, exist_ok=True)
STYLE_HELPER = PlotStyleHelper(PLOT_GLOBAL, FIGURES_DIR)


def warn(message):
    print(f"[WARN] {message}")


def to_scalar(val, default=np.nan):
    if val is None:
        return default
    arr = np.asarray(val, dtype=float).ravel()
    return float(arr[0]) if arr.size > 0 else default


def to_int(val, default=0):
    scalar = to_scalar(val, default=float(default))
    if np.isnan(scalar):
        return default
    return int(round(scalar))


def to_1d(val, length=None):
    if val is None:
        return np.full(length or 0, np.nan)
    arr = np.asarray(val, dtype=float).ravel()
    if length is not None and arr.size < length:
        arr = np.concatenate([arr, np.full(length - arr.size, np.nan)])
    return arr


def iter_results(results):
    if isinstance(results, np.ndarray):
        rows, cols = results.shape
        for row_idx in range(rows):
            for col_idx in range(cols):
                yield row_idx, col_idx, results[row_idx, col_idx]
        return

    if isinstance(results, list):
        for row_idx, row in enumerate(results):
            if isinstance(row, list):
                for col_idx, entry in enumerate(row):
                    yield row_idx, col_idx, entry
            else:
                yield row_idx, 0, row
        return

    yield 0, 0, results


def parse_str_list(raw):
    if raw is None:
        return []
    if isinstance(raw, str):
        return [raw]
    if isinstance(raw, np.ndarray):
        return [str(x) for x in raw.ravel().tolist()]
    return [str(x) for x in list(raw)]


def parse_int_list(raw):
    if raw is None:
        return []
    return [int(x) for x in np.asarray(raw, dtype=int).ravel().tolist()]


def get_timestamp_token(config, fallback_path):
    token = config.get("timestamp") if isinstance(config, dict) else None
    if token:
        return str(token)

    base = os.path.splitext(os.path.basename(fallback_path))[0]
    parts = base.split("_")
    if len(parts) >= 2:
        tail = "_".join(parts[-2:])
        if tail.replace("_", "").isdigit():
            return tail
    return "ts"


def resolve_input_selector(input_selector, family="auto"):
    """
    Resolve a human-friendly selector into an existing path.

    Supported forms:
      - None / ""                       -> keep auto behavior
      - run folder name                 -> search under results/batch
      - MAT file name / MAT stem        -> search under results/batch
      - absolute or relative file/dir   -> use directly if it exists
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

    search_dirs = []
    if family in ("auto", "varyN"):
        search_dirs.extend(SEARCH_DIRS_VARYN)
    if family in ("auto", "varyM"):
        search_dirs.extend(SEARCH_DIRS_VARYM)
    search_dirs = sorted(set(os.path.abspath(path) for path in search_dirs))

    matches = []
    selector_stem, selector_ext = os.path.splitext(selector)
    for search_dir in search_dirs:
        if not os.path.isdir(search_dir):
            continue

        direct_match = os.path.join(search_dir, selector)
        if os.path.exists(direct_match):
            matches.append(os.path.abspath(direct_match))

        pattern = os.path.join(search_dir, "**", selector)
        for matched_path in glob.glob(pattern, recursive=True):
            base_name = os.path.basename(os.path.normpath(matched_path))
            if base_name == selector:
                matches.append(os.path.abspath(matched_path))

        if not selector_ext:
            pattern = os.path.join(search_dir, "**", f"{selector}.mat")
            for matched_path in glob.glob(pattern, recursive=True):
                if os.path.splitext(os.path.basename(matched_path))[0] == selector_stem:
                    matches.append(os.path.abspath(matched_path))

            pattern = os.path.join(search_dir, "**", "*")
            for matched_path in glob.glob(pattern, recursive=True):
                base_name = os.path.basename(os.path.normpath(matched_path))
                if os.path.splitext(base_name)[0] == selector_stem:
                    matches.append(os.path.abspath(matched_path))

    matches = sorted(set(matches))
    if len(matches) == 1:
        return matches[0]
    if len(matches) > 1:
        match_text = "\n  - ".join(matches)
        raise FileNotFoundError(
            f"Multiple inputs match '{selector}'. Please use a full path:\n  - {match_text}"
        )

    raise FileNotFoundError(
        f"Cannot find input '{selector}'. "
        f"Set PREFERRED_INPUT to a run name under results/batch or to a full path."
    )


def find_latest_varyn_mat():
    candidates = []
    for search_dir in SEARCH_DIRS_VARYN:
        if not os.path.isdir(search_dir):
            continue
        candidates.extend(glob.glob(os.path.join(search_dir, "*.mat")))
    if not candidates:
        return None

    preferred = [
        path for path in candidates
        if "varyN" in os.path.basename(path) or os.path.basename(path).startswith("N")
    ]
    pool = preferred if preferred else candidates
    return max(pool, key=os.path.getmtime)


def resolve_varyn_input(input_path=None):
    if input_path:
        path = os.path.abspath(input_path)
        if os.path.isdir(path):
            mats = glob.glob(os.path.join(path, "*.mat"))
            if not mats:
                raise FileNotFoundError(f"No .mat file found under {path}")
            return max(mats, key=os.path.getmtime)
        if not os.path.isfile(path):
            raise FileNotFoundError(f"Input path does not exist: {path}")
        return path

    latest = find_latest_varyn_mat()
    if latest is None:
        raise FileNotFoundError("No VaryN .mat file found. Run Batch_VaryN.m first.")
    return latest


def load_varyn_dataset(input_path=None):
    if mat73 is None:
        raise RuntimeError("mat73 is required to read VaryN aggregate .mat files.")

    path = resolve_varyn_input(input_path)
    raw = mat73.loadmat(path)
    if "scale_N_results" not in raw or "scale_config" not in raw:
        raise ValueError(f"Not a VaryN aggregate result file: {path}")

    config = raw["scale_config"]
    return {
        "family": "varyN",
        "results": raw["scale_N_results"],
        "config": config,
        "target_name": "N",
        "target_values": parse_int_list(config.get("N_values", [])),
        "fixed_key": "N",
        "seed_values": parse_int_list(config.get("seeds", [])),
        "alg_names": parse_str_list(config.get("alg_names", [])),
        "num_rounds": to_int(config.get("num_rounds"), default=0),
        "source_path": path,
        "timestamp": get_timestamp_token(config, path),
    }


def load_varym_dataset(input_path=None):
    aggregator = VaryMResultAggregator(search_dirs=SEARCH_DIRS_VARYM)
    results, config, run_meta = aggregator.load_results(input_path=input_path)
    source_path = run_meta.get("source_path", input_path or "")
    return {
        "family": "varyM",
        "results": results,
        "config": config,
        "target_name": "M",
        "target_values": parse_int_list(config.get("M_values", [])),
        "fixed_key": "M",
        "seed_values": parse_int_list(config.get("seeds", [])),
        "alg_names": parse_str_list(config.get("alg_names", [])),
        "num_rounds": to_int(config.get("num_rounds"), default=0),
        "source_path": source_path,
        "timestamp": get_timestamp_token(config, source_path),
    }


def auto_pick_latest_family():
    varyn_path = find_latest_varyn_mat()

    varym_path = None
    aggregator = VaryMResultAggregator(search_dirs=SEARCH_DIRS_VARYM)
    try:
        resolved = aggregator.resolve_input(input_path=None)
        varym_path = resolved["path"]
    except Exception:
        varym_path = None

    if varyn_path is None and varym_path is None:
        raise FileNotFoundError("No VaryN/VaryM batch result found.")
    if varyn_path is None:
        return "varyM", varym_path
    if varym_path is None:
        return "varyN", varyn_path

    if os.path.getmtime(varym_path) >= os.path.getmtime(varyn_path):
        return "varyM", varym_path
    return "varyN", varyn_path


def load_dataset(input_path=None, family="auto"):
    input_path = resolve_input_selector(input_path, family=family)

    if family == "varyN":
        return load_varyn_dataset(input_path)
    if family == "varyM":
        return load_varym_dataset(input_path)

    if input_path is None:
        detected_family, detected_path = auto_pick_latest_family()
        return load_dataset(detected_path, family=detected_family)

    path = os.path.abspath(input_path)
    attempts = []
    if os.path.isdir(path):
        attempts = [("varyM", load_varym_dataset)]
    else:
        attempts = [("varyN", load_varyn_dataset), ("varyM", load_varym_dataset)]

    errors = []
    for family_name, loader in attempts:
        try:
            return loader(path)
        except Exception as exc:
            errors.append(f"{family_name}: {exc}")

    error_text = "\n".join(errors)
    raise RuntimeError(f"Failed to auto-detect result family for {path}\n{error_text}")


def resolve_target_value(dataset, n_value=None, m_value=None):
    target_name = dataset["target_name"]
    target_values = dataset["target_values"]
    requested = n_value if target_name == "N" else m_value

    if not target_values:
        raise ValueError(f"No {target_name} values found in result config.")
    if requested is None:
        return max(target_values)
    if requested not in target_values:
        raise ValueError(f"{target_name}={requested} is not available. Choices: {target_values}")
    return requested


def resolve_seed_mode(dataset, seed_text):
    if str(seed_text).lower() == "mean":
        return "mean"

    seed_value = int(seed_text)
    seed_values = dataset["seed_values"]
    if seed_value not in seed_values:
        raise ValueError(f"seed={seed_value} is not available. Choices: {seed_values}")
    return seed_value


def collect_curves(dataset, target_value, seed_mode, metric_key):
    metric_spec = METRIC_SPECS[metric_key]
    curve_field = metric_spec["curve_field"]
    target_index = dataset["target_values"].index(target_value)
    num_rounds = dataset["num_rounds"]
    alg_names = dataset["alg_names"]

    curves = {name: [] for name in alg_names}
    selected_scenario_count = 0
    matched_seed = False

    for row_idx, col_idx, entry in iter_results(dataset["results"]):
        if row_idx != target_index or not isinstance(entry, dict):
            continue

        entry_seed = to_int(entry.get("seed"), default=dataset["seed_values"][col_idx])
        if seed_mode != "mean" and entry_seed != seed_mode:
            continue

        matched_seed = True
        if not entry.get("success", False):
            continue

        selected_scenario_count += 1
        algs_data = entry.get("algs", {}) or {}
        for alg_name in alg_names:
            alg_entry = algs_data.get(alg_name)
            if not isinstance(alg_entry, dict) or not alg_entry.get("success", False):
                continue
            if curve_field not in alg_entry or alg_entry.get(curve_field) is None:
                continue
            curve = to_1d(alg_entry.get(curve_field), length=num_rounds)
            if curve.size == 0 or np.all(np.isnan(curve)):
                continue
            curves[alg_name].append(curve)

    if seed_mode != "mean" and not matched_seed:
        raise ValueError(
            f"seed={seed_mode} not found under {dataset['target_name']}={target_value}."
        )

    if selected_scenario_count == 0:
        raise ValueError(
            f"No successful scenario found for {dataset['target_name']}={target_value}."
        )

    non_empty = sum(1 for alg_name in alg_names if curves[alg_name])
    if non_empty == 0:
        raise ValueError(
            f"No {curve_field} data found for {dataset['target_name']}={target_value}."
        )

    return curves


def fill_tail_with_last(curve):
    filled = np.asarray(curve, dtype=float).copy()
    valid = np.where(~np.isnan(filled))[0]
    if valid.size == 0:
        return filled
    filled[valid[-1] + 1:] = filled[valid[-1]]
    return filled


def summarize_curves(curves, seed_mode):
    summary = {}
    for alg_name, series_list in curves.items():
        if not series_list:
            summary[alg_name] = None
            continue

        mat = np.vstack(series_list)
        mean_curve = np.nanmean(mat, axis=0)
        std_curve = np.nanstd(mat, axis=0) if seed_mode == "mean" else None
        summary[alg_name] = {
            "curve": fill_tail_with_last(mean_curve),
            "std": fill_tail_with_last(std_curve) if std_curve is not None else None,
            "count": mat.shape[0],
        }
    return summary


def build_default_output_path(dataset, target_value, seed_mode, metric_key):
    metric_stem = METRIC_SPECS[metric_key]["stem"]
    seed_token = "mean" if seed_mode == "mean" else f"seed{seed_mode}"
    stem = (
        f"detail_convergence_{metric_stem}_{dataset['family']}_"
        f"{dataset['target_name']}{target_value}_{seed_token}_{dataset['timestamp']}"
    )
    return os.path.join(FIGURES_DIR, f"{stem}.png")


def normalize_output_path(output_path):
    if output_path is None:
        return None

    normalized = os.path.abspath(output_path)
    root, ext = os.path.splitext(normalized)
    if not ext:
        normalized = root + ".png"
    return normalized


def plot_detail_convergence(dataset, target_value, seed_mode, metric_key, output_path=None):
    metric_spec = METRIC_SPECS[metric_key]
    curves = collect_curves(dataset, target_value, seed_mode, metric_key)
    summary = summarize_curves(curves, seed_mode)

    fig, ax = plt.subplots(figsize=PLOT_GLOBAL["figsize"])
    rounds = np.arange(1, dataset["num_rounds"] + 1)

    plotted = 0
    for alg_name in dataset["alg_names"]:
        item = summary.get(alg_name)
        if item is None:
            warn(
                f"Skipping {alg_name}: no {metric_spec['curve_field']} data "
                f"for {dataset['target_name']}={target_value}."
            )
            continue

        curve = item["curve"]
        if np.all(np.isnan(curve)):
            warn(
                f"Skipping {alg_name}: all values are NaN in "
                f"{metric_spec['curve_field']}."
            )
            continue

        style = ALG_STYLE.get(alg_name, DEFAULT_STYLE)
        std_curve = item["std"]
        if (
            CURVE_DETAIL_CONFIG["show_mean_band"]
            and std_curve is not None
            and item["count"] > 1
        ):
            lower = curve - std_curve
            upper = curve + std_curve
            ax.fill_between(
                rounds,
                lower,
                upper,
                color=style["color"],
                alpha=CURVE_DETAIL_CONFIG["band_alpha"],
                linewidth=0,
            )

        markevery = None
        if len(rounds) > CURVE_DETAIL_CONFIG["markevery_threshold"]:
            markevery = max(1, len(rounds) // CURVE_DETAIL_CONFIG["markevery_divisor"])

        ax.plot(
            rounds,
            curve,
            color=style["color"],
            linestyle=style["ls"],
            linewidth=PLOT_GLOBAL["linewidth"],
            marker=style["marker"],
            markersize=PLOT_GLOBAL["markersize"],
            markeredgewidth=PLOT_GLOBAL["markeredgewidth"],
            markevery=markevery,
            label=style["label"],
        )
        plotted += 1

    if plotted == 0:
        raise RuntimeError("No valid algorithm curve was plotted.")

    mode_text = "mean over available seeds" if seed_mode == "mean" else f"seed={seed_mode}"
    title = (
        f"Detail Convergence of {metric_spec['title_name']} "
        f"({dataset['target_name']}={target_value}, {mode_text})"
    )

    ax.set_xlim(1, max(dataset["num_rounds"], 1))
    STYLE_HELPER.apply_common_style(
        ax,
        xlabel="Round",
        ylabel=metric_spec["ylabel"],
        title=title,
    )

    save_path = normalize_output_path(output_path) or build_default_output_path(
        dataset, target_value, seed_mode, metric_key
    )
    STYLE_HELPER.finalize_and_save(fig, save_path)
    return save_path


def parse_args(argv):
    parser = argparse.ArgumentParser(
        description="Plot detailed outer-round convergence curves for batch results."
    )
    parser.add_argument(
        "input_path",
        nargs="?",
        default=PREFERRED_INPUT,
        help="Optional result path or run directory.",
    )
    parser.add_argument(
        "--family",
        choices=["auto", "varyN", "varyM"],
        default=DEFAULT_FAMILY,
        help="Result family. Default: auto.",
    )
    parser.add_argument("--n", type=int, default=DEFAULT_N, help="Target N for VaryN.")
    parser.add_argument("--m", type=int, default=DEFAULT_M, help="Target M for VaryM.")
    parser.add_argument(
        "--seed",
        default=DEFAULT_SEED,
        help="Seed selector: mean or a concrete seed value. Default: mean.",
    )
    parser.add_argument(
        "--metric",
        choices=sorted(METRIC_SPECS.keys()),
        default=DEFAULT_METRIC,
        help="Metric to plot. Default: utility.",
    )
    parser.add_argument("--output", help="Optional output file path.")
    return parser.parse_args(argv)


def main(argv=None):
    STYLE_HELPER.apply_rcparams()
    args = parse_args(argv or sys.argv[1:])

    dataset = load_dataset(args.input_path, family=args.family)
    target_value = resolve_target_value(dataset, n_value=args.n, m_value=args.m)
    seed_mode = resolve_seed_mode(dataset, args.seed)

    print("Loading data...")
    print(f"  family      = {dataset['family']}")
    print(f"  source      = {dataset['source_path']}")
    print(f"  {dataset['target_name']} target   = {target_value}")
    print(f"  seed mode   = {seed_mode}")
    print(f"  metric      = {args.metric}")
    print(f"  algorithms  = {dataset['alg_names']}")

    save_path = plot_detail_convergence(
        dataset,
        target_value=target_value,
        seed_mode=seed_mode,
        metric_key=args.metric,
        output_path=args.output,
    )

    print(f"Saved figure: {save_path}")
    if AUTO_SHOW_FIGURE and "agg" not in plt.get_backend().lower():
        plt.show()


if __name__ == "__main__":
    main()
