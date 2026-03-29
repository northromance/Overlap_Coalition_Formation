"""
plot_belief_funnel.py
=====================
Plot belief-to-value funnel figures from Batch_Belief.m outputs.

Usage:
  python plot_belief_funnel.py
  python plot_belief_funnel.py path/to/belief.mat
"""

import glob
import os
import re
import sys

import matplotlib
import numpy as np
from plot_style_helper import PlotStyleHelper

try:
    import mat73
except ImportError:
    sys.exit("Missing dependency: please run `pip install mat73` first.")


SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
ROOT_DIR = os.path.dirname(SCRIPT_DIR)
FIGURES_DIR = os.path.join(ROOT_DIR, "figures", "paper")
SEARCH_DIRS = [
    os.path.join(ROOT_DIR, "results", "batch", "belief"),
    os.path.join(ROOT_DIR, "results", "batch"),
]

TYPE_COLORS = {
    1: "#4878CF",
    2: "#6ACC65",
    3: "#D65F5F",
    4: "#EE854A",
    5: "#C4AD66",
    6: "#956CB4",
}
FALLBACK_COLORS = ["#4878CF", "#6ACC65", "#D65F5F", "#EE854A", "#C4AD66", "#956CB4"]
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
GUI_BACKEND_CANDIDATES = ("TkAgg", "QtAgg", "Qt5Agg")
PLOT_EVERY_N_ROUNDS = 3  # 1 = plot every round; 5 = plot rounds 0,5,10,...

PLOT_STYLE = {
    "figsize": (7.2, 4.8),
    "linewidth": 2.1,
    "ref_linewidth": 1.2,
    "band_alpha": 0.35,
    "marker": "o",
    "markersize": 4.2,
    "grid_linestyle": "--",
    "grid_linewidth": 0.55,
    "grid_alpha": 0.35,
    "title_fontsize": 12,
    "label_fontsize": 11,
    "tick_fontsize": 10,
    "legend_fontsize": 9,
    "save_dpi": 160,
}

os.makedirs(FIGURES_DIR, exist_ok=True)

PLOT_GLOBAL = {
    "title_fontsize": PLOT_STYLE["title_fontsize"],
    "xlabel_fontsize": PLOT_STYLE["label_fontsize"],
    "ylabel_fontsize": PLOT_STYLE["label_fontsize"],
    "tick_fontsize": PLOT_STYLE["tick_fontsize"],
    "legend_fontsize": PLOT_STYLE["legend_fontsize"],
    "show_grid": True,
    "grid_linestyle": PLOT_STYLE["grid_linestyle"],
    "grid_linewidth": PLOT_STYLE["grid_linewidth"],
    "grid_alpha": PLOT_STYLE["grid_alpha"],
    "show_legend": False,
    "legend_framealpha": 0.9,
    "legend_edgecolor": "#cccccc",
    "hide_top_spine": True,
    "hide_right_spine": True,
    "save_dpi": PLOT_STYLE["save_dpi"],
    "save_bbox_inches": "tight",
    "tight_layout": True,
}
STYLE_HELPER = PlotStyleHelper(PLOT_GLOBAL, FIGURES_DIR)


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


def find_mat_file(argv):
    if len(argv) > 1:
        path = argv[1]
        if os.path.isfile(path):
            return path
        print(f"Warning: file not found: {path}. Falling back to auto-search.")

    candidates = []
    for directory in SEARCH_DIRS:
        candidates.extend(glob.glob(os.path.join(directory, "*.mat")))

    belief_files = [
        path
        for path in candidates
        if "belief" in os.path.basename(path).lower()
        or os.path.join("belief", "") in path.replace("\\", "/").lower()
    ]
    pool = belief_files if belief_files else candidates
    if not pool:
        sys.exit("No belief .mat file found. Run Batch_Belief.m first or pass a path.")

    chosen = max(pool, key=os.path.getmtime)
    print(f"Using latest result: {chosen}")
    return chosen


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

    fig, ax = plt.subplots(figsize=PLOT_STYLE["figsize"])
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

        ax.fill_between(rounds, low, high, color=color, alpha=PLOT_STYLE["band_alpha"])
        line, = ax.plot(
            rounds,
            center,
            color=color,
            linewidth=PLOT_STYLE["linewidth"],
            marker=PLOT_STYLE["marker"],
            markersize=PLOT_STYLE["markersize"],
            markevery=1,
            solid_capstyle="round",
        )
        ax.axhline(true_value, color=color, linestyle="--", linewidth=PLOT_STYLE["ref_linewidth"], alpha=0.9)

        legend_handles.append(line)
        legend_labels.append(f"Type-{type_id} (V*={true_value:.0f})")
        ymax_candidates.extend([np.nanmax(high), true_value])
        ymin_candidates.extend([np.nanmin(low), true_value])

    ymax = max(ymax_candidates) if ymax_candidates else 1.0
    ymin = min(ymin_candidates) if ymin_candidates else 0.0
    ypad = max(50.0, 0.08 * (ymax - ymin if ymax > ymin else ymax))

    STYLE_HELPER.apply_common_style(
        ax,
        cfg={
            "title": f"Belief Funnel Convergence [{condition_name}]",
            "xlabel": "Communication round",
            "ylabel": "Expected task value",
        },
    )
    ax.set_xlim(0, max(len(v["center"]) for v in aggregated.values()) - 1)
    ax.set_ylim(max(0.0, ymin - ypad), ymax + ypad)
    ax.legend(
        legend_handles,
        legend_labels,
        fontsize=PLOT_STYLE["legend_fontsize"],
        framealpha=0.9,
        edgecolor="#cccccc",
        loc="best",
    )

    STYLE_HELPER.finalize_and_save(fig, save_path)
    return fig


def load_successful_entries(mat_path):
    data = mat73.loadmat(mat_path)
    results = data.get("belief_results")
    config = data.get("belief_config", {})
    if results is None:
        sys.exit("belief_results not found in the .mat file.")

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
        print(f"\nFigures were saved only; no interactive backend available (backend={backend}).")
    else:
        print(f"\nFigures saved. Close the windows to exit (backend={backend}).")
        plt.show()


def main():
    mat_path = find_mat_file(sys.argv)
    grouped, config, results = load_successful_entries(mat_path)
    task_type_values = get_task_type_values(config, results)
    timestamp = str(config.get("timestamp") or "").strip() or os.path.splitext(os.path.basename(mat_path))[0]

    print(f"Matplotlib backend: {plt.get_backend()}")
    print(f"Plot every N rounds: {PLOT_EVERY_N_ROUNDS}")
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

        filename = f"fig_belief_funnel_{sanitize_name(condition_name)}_{timestamp}.png"
        save_path = os.path.join(FIGURES_DIR, filename)
        fig = plot_condition_funnel(condition_name, aggregated, task_type_values, save_path)
        if fig is not None:
            figures.append(fig)

    maybe_show_figures(figures)


if __name__ == "__main__":
    main()
