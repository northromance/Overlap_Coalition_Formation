"""
plot_belief_funnel.py
=====================
Plot belief-to-value funnel figures from Batch_Belief.m outputs.

Usage:
  python plot_belief_funnel.py
  python plot_belief_funnel.py <belief_run_name>
  python plot_belief_funnel.py <path/to/belief_run_dir>
  python plot_belief_funnel.py <legacy_belief.mat>

Optional top-level selector:
  PREFERRED_INPUT = None
  PREFERRED_INPUT = "20260330_120000_N10_M10_K6_C2_S5"
  PREFERRED_INPUT = "results/batch/belief/20260330_120000_N10_M10_K6_C2_S5"
  PREFERRED_INPUT = "N10_M10_K6_S2_20260326_213543.mat"
"""

import os
import re
import sys
import copy

import matplotlib
import numpy as np
from belief_result_aggregator import BeliefResultAggregator
from plot_style_helper import PlotStyleHelper, build_results_figures_dir, cm_size_to_inch, infer_source_name


# =========================
# 顶部可调绘图参数
# 这里集中放置输入选择、轮次抽样、曲线样式和保存设置。
# =========================

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
ROOT_DIR = os.path.dirname(SCRIPT_DIR)
FIGURES_DIR = build_results_figures_dir(ROOT_DIR, "belief")
SEARCH_DIRS = [
    os.path.join(ROOT_DIR, "results", "batch", "belief"),  # belief 实验结果主目录
    os.path.join(ROOT_DIR, "results", "batch"),  # 兜底搜索目录
]

# 输入选择器
# - None / "": 自动选择最新的 belief 运行目录；找不到时再回退到旧 MAT
# - run name: 按目录名精确匹配
# - file name: 按文件名精确匹配旧 MAT
# - relative / abs path: 直接使用运行目录、缓存文件或旧 MAT 路径
PREFERRED_INPUT = None

# 任务类型颜色映射
TYPE_COLORS = {
    1: "#4878CF",
    2: "#6ACC65",
    3: "#D65F5F",
    4: "#EE854A",
    5: "#C4AD66",
    6: "#956CB4",
}
FALLBACK_COLORS = ["#4878CF", "#6ACC65", "#D65F5F", "#EE854A", "#C4AD66", "#956CB4"]

# 非交互后端标记：命中后 show() 可能不会弹窗，只会保存文件
NON_INTERACTIVE_BACKEND_MARKERS = (
    "agg",
    "pdf",
    "ps",
    "svg",
    "template",
    "cairo",
    "pgf",
    "module://matplotlib_inline",
)

# 若当前后端不可交互，则按顺序尝试切换到这些 GUI 后端
GUI_BACKEND_CANDIDATES = ("TkAgg", "QtAgg", "Qt5Agg")

# 横轴抽样步长
# 1 表示每一轮都画；3 表示只画 round 0/3/6/...，最后一轮会强制保留
PLOT_EVERY_N_ROUNDS = 3

# belief funnel 单图样式
PLOT_STYLE = {
    "figsize_cm": (8.89, 6.35),  # 单张图尺寸（宽, 高），单位 cm
    "linewidth": 1.4,  # 主曲线线宽
    "ref_linewidth": 1.0,  # 参考线线宽
    "ref_alpha": 0.85,  # 参考线透明度
    "band_alpha": 0.20,  # 阴影带透明度
    "marker": "o",  # marker 形状
    "markersize": 3.5,  # marker 大小
    "markevery": 1,  # marker 抽样步长
    "show_band": True,  # 是否显示阴影带
    "show_reference_line": True,  # 是否显示参考线
    "grid_linestyle": "--",  # 网格线型
    "grid_linewidth": 0.45,  # 网格线宽
    "grid_alpha": 0.25,  # 网格透明度
    "title_fontsize": 8,  # 标题字号
    "label_fontsize": 8,  # 坐标轴标题字号
    "tick_fontsize": 8,  # 刻度字号
    "legend_fontsize": 7.5,  # 图例字号
    "save_dpi": 600,  # 位图输出 dpi
    "y_padding_min": 20.0,  # y 轴最小留白，单位为数据值
    "y_padding_ratio": 0.05,  # y 轴留白比例
}
os.makedirs(FIGURES_DIR, exist_ok=True)

# 交给 PlotStyleHelper 的全局样式适配器
PLOT_GLOBAL = {
    "title_fontsize": PLOT_STYLE["title_fontsize"],  # 标题字号
    "title_fontweight": "bold",  # 标题字重
    "title_pad": 8,  # 标题与坐标轴之间的间距
    "xlabel_fontsize": PLOT_STYLE["label_fontsize"],  # x 轴标题字号
    "ylabel_fontsize": PLOT_STYLE["label_fontsize"],  # y 轴标题字号
    "label_fontweight": "normal",  # 坐标轴标题字重
    "tick_fontsize": PLOT_STYLE["tick_fontsize"],  # 刻度字号
    "tick_fontweight": "normal",  # 刻度字重
    "legend_fontsize": PLOT_STYLE["legend_fontsize"],  # 图例字号
    "legend_fontweight": "normal",  # 图例字重
    "show_titles": True,  # 是否显示标题
    "show_grid": True,  # 是否显示网格
    "grid_linestyle": PLOT_STYLE["grid_linestyle"],  # 网格线型
    "grid_linewidth": PLOT_STYLE["grid_linewidth"],  # 网格线宽
    "grid_alpha": PLOT_STYLE["grid_alpha"],  # 网格透明度
    "show_legend": True,  # 是否显示图例
    "legend_loc": "best",  # 图例位置
    "legend_bbox_to_anchor": None,  # 图例锚点；None 表示不额外指定
    "legend_ncol": 1,  # 图例列数
    "legend_borderaxespad": 0.3,  # 图例与坐标轴边界的间距
    "legend_handlelength": 2.0,  # 图例示意线长度
    "legend_labelspacing": 0.4,  # 图例条目垂直间距
    "legend_framealpha": 0.9,  # 图例边框透明度
    "legend_edgecolor": "#cccccc",  # 图例边框颜色
    "hide_top_spine": True,  # 是否隐藏上边框
    "hide_right_spine": True,  # 是否隐藏右边框
    "save_format": "eps",  # 主保存格式
    "save_formats": ["png", "eps"],  # 实际输出格式列表
    "save_dpi": PLOT_STYLE["save_dpi"],  # 位图输出 dpi
    "save_bbox_inches": "tight",  # 保存时裁掉多余白边
    "timestamp_first_in_name": False,  # False 表示文件名采用 stem_timestamp 形式
    "tight_layout": True,  # 保存前是否执行 tight_layout
}
STYLE_HELPER = PlotStyleHelper(PLOT_GLOBAL, FIGURES_DIR)
STYLE_HELPER_NO_LEGEND = PlotStyleHelper(dict(PLOT_GLOBAL, show_legend=False), FIGURES_DIR)

# 单图显式配置
# - show_title / show_legend: 当前图的局部开关，仍受全局总开关影响
# - xlim / ylim = None: 自动范围
# - xticks / yticks = None: 自动刻度
# - bottom_zero = True: y 轴下界至少为 0
FIGURE_CONFIG = {
    "belief_funnel": {
        "show_title": True,
        "show_legend": True,
        "title_template": "Belief Funnel Convergence [{condition_name}]",
        "xlabel": "Communication round",
        "ylabel": "Expected task value",
        "xlim": None,
        "ylim": None,
        "xticks": None,
        "yticks": None,
        "bottom_zero": True,
    },
}

# 每张图的显式配置。
# 这里控制标题文本、坐标轴标签、坐标轴范围、是否从 0 开始等。
def merge_figure_config(fig_key, **kwargs):
    cfg = copy.deepcopy(FIGURE_CONFIG[fig_key])
    cfg.update(kwargs)
    return cfg


def apply_plot_rcparams():
    STYLE_HELPER.apply_rcparams()


def build_output_path(timestamp, stem):
    _ = timestamp
    return STYLE_HELPER.build_output_stem(stem)


def apply_common_style(ax, cfg, title=None, legend_handles=None, legend_labels=None):
    show_legend = cfg.get("show_legend", PLOT_GLOBAL.get("show_legend", False))
    helper = STYLE_HELPER if show_legend else STYLE_HELPER_NO_LEGEND

    legend_kwargs = None
    if show_legend and legend_handles and legend_labels:
        legend_kwargs = {
            "handles": legend_handles,
            "labels": legend_labels,
        }

    helper.apply_common_style(ax, cfg=cfg, title=title, legend_kwargs=legend_kwargs)


def apply_axis_controls(ax, cfg):
    STYLE_HELPER.apply_axis_controls(ax, cfg=cfg)


def finalize_and_save(fig, save_path):
    STYLE_HELPER.finalize_and_save(fig, save_path)


def configure_output_dir(source_name):
    global FIGURES_DIR
    FIGURES_DIR = build_results_figures_dir(ROOT_DIR, "belief", source_name)
    os.makedirs(FIGURES_DIR, exist_ok=True)
    STYLE_HELPER.set_figures_dir(FIGURES_DIR)
    STYLE_HELPER_NO_LEGEND.set_figures_dir(FIGURES_DIR)
    return FIGURES_DIR


def get_timestamp_tag(config, run_meta):
    timestamp = str(config.get("timestamp") or "").strip()
    if timestamp:
        return timestamp
    run_name = str(run_meta.get("run_name") or "").strip()
    if run_name:
        return run_name
    source_path = str(run_meta.get("source_path") or "").strip()
    return os.path.splitext(os.path.basename(source_path))[0]


def is_noninteractive_backend(backend_name):
    backend_name = str(backend_name).lower()
    return any(marker in backend_name for marker in NON_INTERACTIVE_BACKEND_MARKERS)


def configure_gui_backend():
    current_backend = matplotlib.get_backend()
    forced_backend = os.environ.get("MPLBACKEND", "").strip()
    if forced_backend:
        return str(current_backend), False
    if not is_noninteractive_backend(current_backend):
        return str(current_backend), False

    for candidate in GUI_BACKEND_CANDIDATES:
        try:
            matplotlib.use(candidate, force=True)
            return candidate, True
        except Exception:
            continue
    return str(matplotlib.get_backend()), False


SELECTED_BACKEND, BACKEND_SWITCHED = configure_gui_backend()

import matplotlib.pyplot as plt


def resolve_input_selector(input_selector):
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

    return selector


def to_scalar(val, default=np.nan):
    if val is None:
        return default
    arr = np.asarray(val, dtype=float).ravel()
    return float(arr[0]) if arr.size else default


def parse_conditions(config):
    raw = config.get("conditions", [])
    if isinstance(raw, str):
        return [raw]
    if isinstance(raw, np.ndarray):
        return [str(x) for x in raw.ravel()]
    if isinstance(raw, list):
        out = []
        for item in raw:
            if isinstance(item, list):
                out.extend(str(x) for x in item)
            else:
                out.append(str(item))
        return out
    return list(raw)


def iter_belief_results(results):
    if isinstance(results, np.ndarray):
        rows, cols = results.shape
        for ci in range(rows):
            for si in range(cols):
                yield ci, si, results[ci, si]
    elif isinstance(results, list):
        for ci, row in enumerate(results):
            if isinstance(row, list):
                for si, entry in enumerate(row):
                    yield ci, si, entry
            else:
                yield ci, 0, row
    else:
        yield 0, 0, results


def entry_condition_name(entry):
    raw = entry.get("condition", None)
    if raw is None:
        return None
    if isinstance(raw, str):
        return raw.strip().rstrip("\x00")
    if isinstance(raw, bytes):
        return raw.decode("utf-8", errors="replace").strip().rstrip("\x00")
    arr = np.asarray(raw).ravel()
    if not arr.size:
        return None
    item = arr[0]
    if isinstance(item, bytes):
        return item.decode("utf-8", errors="replace").strip().rstrip("\x00")
    return str(item).strip().rstrip("\x00")


def normalize_init_belief(init_b_raw, n_agents, n_types):
    default = np.full((n_agents, n_types), 1.0 / max(n_types, 1), dtype=float)
    if init_b_raw is None:
        return default

    try:
        init_b = np.asarray(init_b_raw, dtype=float)
    except Exception:
        return default

    init_b = np.squeeze(init_b)
    if init_b.ndim == 1:
        init_b = np.tile(init_b[:n_types], (n_agents, 1))
    elif init_b.ndim == 2:
        if init_b.shape == (n_types, n_agents):
            init_b = init_b.T
        elif init_b.shape[0] != n_agents and init_b.shape[1] == n_agents:
            init_b = init_b.T
    else:
        return default

    fixed = default.copy()
    rows = min(n_agents, init_b.shape[0])
    cols = min(n_types, init_b.shape[1])
    fixed[:rows, :cols] = init_b[:rows, :cols]
    fixed = np.clip(fixed, 0.0, None)
    row_sums = fixed.sum(axis=1, keepdims=True)
    row_sums[row_sums <= 0] = 1.0
    return fixed / row_sums


def normalize_init_belief_tensor(init_b_raw, n_agents, n_tasks, n_types):
    if init_b_raw is None:
        return None

    try:
        init_b = np.asarray(init_b_raw, dtype=float)
    except Exception:
        return None

    init_b = np.squeeze(init_b)
    if init_b.ndim != 3:
        return None

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
    else:
        return None

    fixed = np.full((n_agents, n_tasks, n_types), 1.0 / max(n_types, 1), dtype=float)
    rows = min(n_agents, tensor.shape[0])
    tasks = min(n_tasks, tensor.shape[1])
    cols = min(n_types, tensor.shape[2])
    fixed[:rows, :tasks, :cols] = tensor[:rows, :tasks, :cols]
    fixed = np.clip(fixed, 0.0, None)
    row_sums = fixed.sum(axis=2, keepdims=True)
    row_sums[row_sums <= 0] = 1.0
    return fixed / row_sums


def build_round0_belief(entry, n_agents, n_tasks, n_types):
    init_b_tensor = normalize_init_belief_tensor(entry.get("init_belief_tensor"), n_agents, n_tasks, n_types)
    if init_b_tensor is not None:
        return init_b_tensor

    init_b = normalize_init_belief(entry.get("init_belief_matrix"), n_agents, n_types)
    return np.repeat(init_b[:, np.newaxis, :], n_tasks, axis=1)


def sanitize_name(name):
    return re.sub(r"[^A-Za-z0-9_-]+", "_", str(name)).strip("_") or "condition"


def condition_style(type_id):
    color = TYPE_COLORS.get(type_id)
    if color is None:
        color = FALLBACK_COLORS[(type_id - 1) % len(FALLBACK_COLORS)]
    return color


def select_round_indices(num_points, stride):
    stride = max(1, int(stride))
    if num_points <= 0:
        return np.array([], dtype=int)

    indices = np.arange(0, num_points, stride, dtype=int)
    if indices[-1] != num_points - 1:
        indices = np.append(indices, num_points - 1)
    return np.unique(indices)


def combine_round0_with_history(entry, n_types):
    history = np.asarray(entry.get("belief_history"), dtype=float)
    if history.ndim != 4:
        raise ValueError(f"belief_history must be 4D [R,N,M,T], got shape {history.shape}")

    n_rounds, n_agents, n_tasks, history_types = history.shape
    if history_types != n_types:
        n_types = history_types

    round0 = build_round0_belief(entry, n_agents, n_tasks, n_types)
    round0 = round0[np.newaxis, :, :, :]

    if history.shape[-1] != round0.shape[-1]:
        common_types = min(history.shape[-1], round0.shape[-1])
        history = history[:, :, :, :common_types]
        round0 = round0[:, :, :, :common_types]

    return np.concatenate([round0, history], axis=0)


def get_task_type_values(config, results):
    values = np.asarray(config.get("task_type_values", []), dtype=float).ravel()
    if values.size:
        return values

    fallback = {}
    for _, _, entry in iter_belief_results(results):
        if not entry or not entry.get("success", False):
            continue
        task_types = np.asarray(entry.get("true_task_types"), dtype=float).ravel().astype(int)
        task_values = np.asarray(entry.get("true_task_values"), dtype=float).ravel()
        for task_type, task_value in zip(task_types, task_values):
            fallback.setdefault(int(task_type), float(task_value))

    if not fallback:
        sys.exit("Cannot infer task type values from belief results.")

    max_type = max(fallback)
    values = np.full(max_type, np.nan, dtype=float)
    for task_type, task_value in fallback.items():
        values[task_type - 1] = task_value
    return values


def aggregate_condition(entries, task_type_values):
    stats_by_type = {}
    skipped = []

    for entry in entries:
        seed = int(round(to_scalar(entry.get("seed"), default=np.nan)))
        all_beliefs = combine_round0_with_history(entry, len(task_type_values))
        true_task_types = np.asarray(entry.get("true_task_types"), dtype=float).ravel().astype(int)

        if all_beliefs.shape[2] != true_task_types.size:
            raise ValueError(
                f"Task count mismatch for seed {seed}: "
                f"belief_history has {all_beliefs.shape[2]} tasks but true_task_types has {true_task_types.size}."
            )

        v_hat = np.tensordot(all_beliefs, task_type_values, axes=([-1], [0]))

        for type_id in range(1, len(task_type_values) + 1):
            task_mask = true_task_types == type_id
            if not np.any(task_mask):
                skipped.append((seed, type_id))
                continue

            samples = v_hat[:, :, task_mask].reshape(v_hat.shape[0], -1)
            center = np.nanmean(samples, axis=1)
            low = np.nanpercentile(samples, 10, axis=1)
            high = np.nanpercentile(samples, 90, axis=1)

            stats_by_type.setdefault(type_id, []).append(
                {
                    "seed": seed,
                    "center": center,
                    "low": low,
                    "high": high,
                    "n_tasks": int(np.sum(task_mask)),
                }
            )

    aggregated = {}
    for type_id, rows in stats_by_type.items():
        max_len = max(len(row["center"]) for row in rows)
        center_stack = np.full((len(rows), max_len), np.nan)
        low_stack = np.full((len(rows), max_len), np.nan)
        high_stack = np.full((len(rows), max_len), np.nan)

        for idx, row in enumerate(rows):
            length = len(row["center"])
            center_stack[idx, :length] = row["center"]
            low_stack[idx, :length] = row["low"]
            high_stack[idx, :length] = row["high"]

        aggregated[type_id] = {
            "center": np.nanmean(center_stack, axis=0),
            "low": np.nanmean(low_stack, axis=0),
            "high": np.nanmean(high_stack, axis=0),
            "seed_count": len(rows),
            "seeds": [row["seed"] for row in rows],
        }

    return aggregated, skipped


def plot_condition_funnel(condition_name, aggregated, task_type_values, save_path):
    if not aggregated:
        print(f"Skip {condition_name}: no valid task-type data.")
        return None

    cfg = merge_figure_config(
        "belief_funnel",
        title=FIGURE_CONFIG["belief_funnel"]["title_template"].format(condition_name=condition_name),
    )
    fig, ax = plt.subplots(figsize=cm_size_to_inch(PLOT_STYLE["figsize_cm"]))
    legend_handles = []
    legend_labels = []
    ymax_candidates = []
    ymin_candidates = []

    for type_id in sorted(aggregated):
        row = aggregated[type_id]
        round_idx = select_round_indices(len(row["center"]), PLOT_EVERY_N_ROUNDS)
        rounds = round_idx
        center = row["center"][round_idx]
        low = row["low"][round_idx]
        high = row["high"][round_idx]
        color = condition_style(type_id)
        true_value = float(task_type_values[type_id - 1])

        if PLOT_STYLE.get("show_band", True):
            ax.fill_between(rounds, low, high, color=color, alpha=PLOT_STYLE["band_alpha"])
        line, = ax.plot(
            rounds,
            center,
            color=color,
            linewidth=PLOT_STYLE["linewidth"],
            marker=PLOT_STYLE["marker"],
            markersize=PLOT_STYLE["markersize"],
            markevery=PLOT_STYLE["markevery"],
            solid_capstyle="round",
        )
        if PLOT_STYLE.get("show_reference_line", True):
            ax.axhline(
                true_value,
                color=color,
                linestyle="--",
                linewidth=PLOT_STYLE["ref_linewidth"],
                alpha=PLOT_STYLE["ref_alpha"],
            )

        legend_handles.append(line)
        legend_labels.append(f"Type-{type_id} (V*={true_value:.0f})")
        ymax_candidates.extend([np.nanmax(high), true_value])
        ymin_candidates.extend([np.nanmin(low), true_value])

    ymax = max(ymax_candidates) if ymax_candidates else 1.0
    ymin = min(ymin_candidates) if ymin_candidates else 0.0
    yspan = ymax - ymin if ymax > ymin else ymax
    ypad = max(PLOT_STYLE["y_padding_min"], PLOT_STYLE["y_padding_ratio"] * yspan)

    cfg["xlim"] = cfg.get("xlim") or (0, max(len(v["center"]) for v in aggregated.values()) - 1)
    y_bottom = ymin - ypad
    if cfg.get("bottom_zero", False):
        y_bottom = max(0.0, y_bottom)
    cfg["ylim"] = cfg.get("ylim") or (y_bottom, ymax + ypad)

    apply_common_style(
        ax,
        cfg=cfg,
        title=cfg.get("title"),
        legend_handles=legend_handles,
        legend_labels=legend_labels,
    )
    apply_axis_controls(ax, cfg)
    finalize_and_save(fig, save_path)
    return fig


def group_successful_entries(results, config):
    if results is None:
        sys.exit("belief_results not found in the selected belief input.")

    conditions = parse_conditions(config)
    grouped = {condition: [] for condition in conditions}

    for ci, _, entry in iter_belief_results(results):
        if not entry:
            continue
        success = entry.get("success", False)
        if not (success is True or float(success) == 1.0):
            continue

        cond_name = entry_condition_name(entry)
        if cond_name is None:
            if ci < len(conditions):
                cond_name = conditions[ci]
            else:
                cond_name = f"condition_{ci + 1}"

        grouped.setdefault(cond_name, []).append(entry)

    return grouped, config, results


def print_condition_summary(grouped):
    print("\nSuccessful seeds by condition:")
    for condition_name, entries in grouped.items():
        seeds = [int(round(to_scalar(entry.get("seed"), default=np.nan))) for entry in entries]
        print(f"  {condition_name}: {len(entries)} entries, seeds={seeds}")


def maybe_show_figures(figures):
    if not figures:
        return
    backend = str(plt.get_backend())
    if is_noninteractive_backend(backend):
        print(f"\nBackend {backend} is non-interactive; calling plt.show() may not open GUI windows.")
    else:
        print(f"\nFigures saved. Close the windows to exit (backend={backend}).")
    plt.show(block=True)


def main(input_path=None):
    apply_plot_rcparams()

    if input_path is None and len(sys.argv) > 1:
        input_path = sys.argv[1]
    if input_path is None:
        input_path = PREFERRED_INPUT

    input_path = resolve_input_selector(input_path)
    aggregator = BeliefResultAggregator(search_dirs=SEARCH_DIRS)

    print("\nLoading belief data...")
    results, config, run_meta = aggregator.load_results(input_path=input_path)
    output_source = run_meta.get("run_name") or infer_source_name(run_meta.get("source_path"), fallback="belief")
    configure_output_dir(output_source)
    print(f"  Source path = {run_meta.get('source_path', '')}")
    print(f"  Source type = {run_meta.get('source_type', '')}")
    if run_meta.get("run_name"):
        print(f"  Run name    = {run_meta.get('run_name', '')}")
    if run_meta.get("cache_path"):
        if run_meta.get("source_type") == "run_dir":
            cache_state = "cache hit" if run_meta.get("used_cache") else "cache rebuilt"
        elif run_meta.get("source_type") == "cache_file":
            cache_state = "direct cache file"
        else:
            cache_state = "cache available"
        print(f"  Cache       = {cache_state}")
        print(f"  Cache path  = {run_meta.get('cache_path', '')}")

    grouped, config, results = group_successful_entries(results, config)
    task_type_values = get_task_type_values(config, results)
    print(f"Matplotlib backend: {plt.get_backend()}")
    print(f"Plot every N rounds: {PLOT_EVERY_N_ROUNDS}")
    print(f"Figure output dir: {FIGURES_DIR}")
    print_condition_summary(grouped)

    figures = []
    for condition_name, entries in grouped.items():
        if not entries:
            print(f"Skip {condition_name}: no successful entries.")
            continue

        aggregated, skipped = aggregate_condition(entries, task_type_values)
        for seed, type_id in skipped:
            print(f"  Skip seed {seed} for {condition_name}, Type-{type_id}: no tasks of this type.")
        for type_id in range(1, len(task_type_values) + 1):
            if type_id not in aggregated:
                print(f"  {condition_name}: Type-{type_id} absent in all valid seeds, not plotted.")
            else:
                info = aggregated[type_id]
                print(
                    f"  {condition_name}: Type-{type_id} uses {info['seed_count']} seed(s), "
                    f"V*={task_type_values[type_id - 1]:.0f}."
                )

        save_path = build_output_path(
            None,
            f"fig_belief_funnel_{sanitize_name(condition_name)}",
        )
        fig = plot_condition_funnel(condition_name, aggregated, task_type_values, save_path)
        if fig is not None:
            figures.append(fig)

    maybe_show_figures(figures)


if __name__ == "__main__":
    main()
