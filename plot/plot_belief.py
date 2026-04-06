"""
plot_belief.py
==============
从 Batch_Belief.m 生成的 .mat 文件绘制论文图：
  图2a  信念误差（L1）随轮次变化  (2种初始信念条件对比，mean ± std)
  图2b  期望任务价值预测随轮次变化 (2种初始信念条件对比，mean ± std)
  图2c* 每任务·每智能体期望价值收敛图
        （每个条件输出 1 张大图，包含 M 个子图；
         每个子图：N 条智能体曲线 + 1 条真实价值水平线）

依赖:
  pip install mat73 numpy matplotlib scipy

用法:
  python plot_belief.py                     # 自动搜索最新 .mat
  python plot_belief.py path/to/belief.mat   # 指定文件

说明:
  你可以直接在本文件最上方的"顶部可调参数区"中修改：
  - 图尺寸、线宽、字体、图例字号、输出 dpi
  - 每个图的标题、坐标轴名称、坐标范围、刻度
  - 是否显示网格、图例、标题、误差带
  - 图2c 的子图网格布局、哪个 seed 用于单 seed 展示
"""

import glob
import os
import sys
import warnings

import matplotlib.pyplot as plt
import numpy as np
from plot_style_helper import (
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
    import mat73
except ImportError:
    sys.exit("缺少依赖，请先执行: pip install mat73")


# ══════════════════════════════════════════════════════════════════════════════
# 顶部可调参数区（建议以后优先在这里改）
# ══════════════════════════════════════════════════════════════════════════════

# ── 路径配置 ──────────────────────────────────────────────────────────────────
# =========================
# 顶部可调绘图参数
# 建议优先在这里改尺寸、字体、图例和各子图布局。
# =========================

# 路径配置
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
ROOT_DIR = os.path.dirname(SCRIPT_DIR)
FAMILY = 'belief'
FIGURES_DIR = build_results_figures_dir(ROOT_DIR, FAMILY)
SEARCH_DIRS = [
    os.path.join(ROOT_DIR, 'results', 'batch', 'belief'),
    os.path.join(ROOT_DIR, 'results', 'batch'),
]
# fig2c ????
FIG2C_SUBPLOT_NCOLS = None  # ???????None ????? ceil(sqrt(M)) ??
FIG2C_SEED_IDX = 1  # ?????? seed ?? seed ???0 ?????

MIN_SEEDS_FOR_CI = 10
CONV_THRESHOLD = 0.05
CONV_STREAK = 3

PLOT_CONFIG = get_family_plot_config(FAMILY)
PLOT_GLOBAL = PLOT_CONFIG['PLOT_GLOBAL']
FIGURE_CONFIG = PLOT_CONFIG['FIGURE_CONFIG']
COND_STYLE = PLOT_CONFIG['COND_STYLE']
DEFAULT_COND_STYLE = PLOT_CONFIG['DEFAULT_COND_STYLE']
AGENT_COLORS = PLOT_CONFIG['AGENT_COLORS']
TRUE_VALUE_STYLE = PLOT_CONFIG['TRUE_VALUE_STYLE']
AGENT_TRACE_STYLE = PLOT_CONFIG['AGENT_TRACE_STYLE']
os.makedirs(FIGURES_DIR, exist_ok=True)
STYLE_HELPER = PlotStyleHelper(PLOT_GLOBAL, FIGURES_DIR)
STYLE_HELPER_NO_LEGEND = PlotStyleHelper(dict(PLOT_GLOBAL, show_legend=False), FIGURES_DIR)


# ══════════════════════════════════════════════════════════════════════════════
# 工具函数
# ══════════════════════════════════════════════════════════════════════════════

def find_mat_file(argv):
    """优先命令行参数，否则在 SEARCH_DIRS 中找最新的 belief .mat 文件。"""
    if len(argv) > 1:
        p = argv[1]
        if os.path.isfile(p):
            return p
        print(f"警告: 指定的文件不存在 '{p}'，尝试自动搜索。")

    candidates = []
    for d in SEARCH_DIRS:
        candidates.extend(glob.glob(os.path.join(d, '*.mat')))

    belief = [
        f for f in candidates
        if 'belief' in os.path.basename(f).lower()
        or os.path.join('belief', '') in f.replace('\\', '/')
    ]
    pool = belief if belief else candidates
    if not pool:
        sys.exit(
            "找不到 .mat 文件，请先运行 Batch_Belief.m，或手动指定路径作为命令行参数。"
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


def to_1d(val, length=None):
    """将字段转为 1D float array，不足 length 时 NaN 后缀。"""
    if val is None:
        return np.full(length or 0, np.nan)
    arr = np.asarray(val, dtype=float).ravel()
    if length is not None and len(arr) < length:
        arr = np.concatenate([arr, np.full(length - len(arr), np.nan)])
    return arr


def parse_conditions(config):
    """从 belief_config 中提取条件名称列表。"""
    raw = config.get('conditions', [])
    if isinstance(raw, str):
        return [raw]
    if isinstance(raw, np.ndarray):
        flat = raw.ravel()
        return [str(x) for x in flat]
    if isinstance(raw, list):
        result = []
        for x in raw:
            if isinstance(x, list):
                result.extend([str(i) for i in x])
            else:
                result.append(str(x))
        return result
    return list(raw)


def iter_belief_results(results):
    """
    mat73 加载的 belief_results cell array 可能是 list-of-list 或 numpy object array。
    统一返回 (ci, si, entry_dict) 迭代器。
    """
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


def get_belief_shape(results):
    """返回 (nCond, nSeeds)。"""
    if isinstance(results, np.ndarray):
        return results.shape
    if isinstance(results, list):
        nC = len(results)
        nS = len(results[0]) if results and isinstance(results[0], list) else 1
        return nC, nS
    return 1, 1


def get_entry(results, ci, si):
    """安全取 results[ci][si]。"""
    if isinstance(results, np.ndarray):
        return results[ci, si]
    if isinstance(results, list):
        row = results[ci]
        if isinstance(row, list):
            return row[si]
        return row
    return results


def entry_condition_name(entry):
    """从 entry 中读取条件名称字符串，兼容 str / bytes / numpy string。"""
    raw = entry.get('condition', None)
    if raw is None:
        return None
    if isinstance(raw, str):
        return raw.strip().rstrip('\x00')
    if isinstance(raw, bytes):
        return raw.decode('utf-8', errors='replace').strip().rstrip('\x00')
    arr = np.asarray(raw).ravel()
    if len(arr) == 0:
        return None
    item = arr[0]
    if isinstance(item, bytes):
        return item.decode('utf-8', errors='replace').strip().rstrip('\x00')
    return str(item).strip().rstrip('\x00')


def merge_figure_config(fig_key, **kwargs):
    """复制并补充每个图的配置，避免运行中修改全局字典。"""
    return get_family_figure_config(FAMILY, fig_key, **kwargs)


def apply_common_style(ax, cfg, title=None, legend_fontsize=None):
    """统一处理坐标轴标签、标题、网格、图例和边框。"""
    legend_kwargs = None
    if legend_fontsize is not None:
        legend_kwargs = {'fontsize': legend_fontsize}
    STYLE_HELPER.apply_common_style(ax, cfg=cfg, title=title, legend_kwargs=legend_kwargs)


def apply_axis_controls(ax, cfg):
    """统一处理 xlim / ylim / xticks / yticks / 底部从 0 开始等。"""
    STYLE_HELPER.apply_axis_controls(ax, cfg=cfg)


def finalize_and_save(fig, save_path, tight_layout_rect=None):
    STYLE_HELPER.finalize_and_save(fig, save_path, tight_layout_rect=tight_layout_rect)


def configure_output_dir(source_name):
    global FIGURES_DIR
    FIGURES_DIR = build_results_figures_dir(ROOT_DIR, FAMILY, source_name)
    os.makedirs(FIGURES_DIR, exist_ok=True)
    STYLE_HELPER.set_figures_dir(FIGURES_DIR)
    STYLE_HELPER_NO_LEGEND.set_figures_dir(FIGURES_DIR)
    return FIGURES_DIR


def build_output_stem(stem):
    return STYLE_HELPER.build_output_stem(build_prefixed_stem(FAMILY, stem))


def build_png_output_path(stem):
    return f"{build_output_stem(stem)}.png"


def build_condition_token(name):
    return sanitize_path_component(name, default='condition')


def set_save_formats(formats):
    normalized = list(formats)
    PLOT_GLOBAL['save_formats'] = list(normalized)
    STYLE_HELPER.plot_global['save_formats'] = list(normalized)
    STYLE_HELPER_NO_LEGEND.plot_global['save_formats'] = list(normalized)


def ffill(arr):
    """将 arr 中 NaN 用上一个有效值向右填充。"""
    out = arr.copy()
    mask = np.isnan(out)
    idx  = np.where(~mask)[0]
    if len(idx) == 0:
        return out
    last = idx[-1]
    out[last + 1:] = out[last]
    return out


def normalize_init_belief(init_b_raw, n_agents, n_types):
    """Normalize stored init_belief_matrix to shape [N, T]."""
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
    """Normalize stored init_belief_tensor to shape [N, M, T]."""
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


def build_round0_belief(init_b_raw, init_b_tensor_raw, n_agents, n_tasks, n_types):
    """Expand stored initial priors to per-agent-per-task beliefs at round 0."""
    init_b_tensor = normalize_init_belief_tensor(init_b_tensor_raw, n_agents, n_tasks, n_types)
    if init_b_tensor is not None:
        return init_b_tensor

    init_b = normalize_init_belief(init_b_raw, n_agents, n_types)
    return np.repeat(init_b[:, np.newaxis, :], n_tasks, axis=1)


# ══════════════════════════════════════════════════════════════════════════════
# 数据提取
# ══════════════════════════════════════════════════════════════════════════════

def extract_belief_curves(results, config):
    """
    提取各条件下的信念误差曲线和期望价值预测曲线（跨 seed 均值 ± std）。

    返回:
      conditions     : list[str]
      num_rounds     : int
      task_values    : np.ndarray  [T]
      belief_error   : {cond: {'mean': [R], 'std': [R]}}
      expected_value : {cond: {'mean': [R], 'std': [R]}}
    """
    conditions  = parse_conditions(config)
    num_rounds  = int(to_scalar(config.get('num_rounds', 100)))
    num_points  = num_rounds + 1   # round 0 + round 1..num_rounds
    task_values = np.asarray(config.get('task_type_values', [800, 1000, 1500]), dtype=float).ravel()

    cond_belief_error:   dict[str, list] = {c: [] for c in conditions}
    cond_expected_value: dict[str, list] = {c: [] for c in conditions}

    for ci, si, entry in iter_belief_results(results):
        if not entry:
            continue
        succ = entry.get('success', False)
        if not (succ is True or float(succ) == 1.0):
            continue

        cond_name = entry_condition_name(entry)
        if cond_name is None or cond_name not in cond_belief_error:
            if ci < len(conditions):
                cond_name = conditions[ci]
            else:
                continue

        bh_raw = entry.get('belief_history')
        tt_raw = entry.get('true_task_types')
        init_b_raw = entry.get('init_belief_matrix')
        init_b_tensor_raw = entry.get('init_belief_tensor')
        if bh_raw is None or tt_raw is None:
            continue

        bh = np.asarray(bh_raw, dtype=float)
        if bh.ndim != 4:
            continue
        R, N_dim, M_dim, T_dim = bh.shape

        true_types = np.asarray(tt_raw, dtype=int).ravel() - 1  # 0-indexed

        # ── L1 信念误差 ──────────────────────────────────────────
        true_onehot = np.zeros((M_dim, T_dim), dtype=float)
        for m, t in enumerate(true_types):
            if 0 <= t < T_dim:
                true_onehot[m, t] = 1.0

        round0_belief = build_round0_belief(init_b_raw, init_b_tensor_raw, N_dim, M_dim, T_dim)   # [N,M,T]

        diff     = bh - true_onehot[np.newaxis, np.newaxis, :, :]  # [R,N,M,T]
        l1       = np.sum(np.abs(diff), axis=3)                     # [R,N,M]
        seed_err = np.nanmean(l1, axis=(1, 2))                      # [R]
        round0_err = np.nanmean(
            np.sum(np.abs(round0_belief - true_onehot[np.newaxis, :, :]), axis=2)
        )
        seed_err = np.concatenate([[round0_err], seed_err])
        seed_err = to_1d(seed_err, length=num_points)
        cond_belief_error[cond_name].append(seed_err[:num_points])

        # ── 期望价值预测 ────────────────────────────────────────
        ev      = np.tensordot(bh, task_values, axes=([3], [0]))    # [R,N,M]
        ev0     = np.tensordot(round0_belief, task_values, axes=([2], [0]))  # [N,M]
        seed_ev = np.nanmean(ev, axis=(1, 2))                       # [R]
        round0_ev = np.nanmean(ev0)
        seed_ev = np.concatenate([[round0_ev], seed_ev])
        seed_ev = to_1d(seed_ev, length=num_points)
        cond_expected_value[cond_name].append(seed_ev[:num_points])

    belief_error:   dict[str, dict] = {}
    expected_value: dict[str, dict] = {}

    def _aggregate(curve_list, nr):
        if not curve_list:
            return np.full(nr, np.nan), np.full(nr, np.nan)
        mat = np.vstack(curve_list)
        return np.nanmean(mat, axis=0), np.nanstd(mat, axis=0)

    for cond in conditions:
        m_err, s_err = _aggregate(cond_belief_error[cond],   num_points)
        m_ev,  s_ev  = _aggregate(cond_expected_value[cond], num_points)
        belief_error[cond]   = {'mean': m_err, 'std': s_err}
        expected_value[cond] = {'mean': m_ev,  'std': s_ev}

    return conditions, num_rounds, task_values, belief_error, expected_value


def extract_per_agent_data(results, config, conditions, seed_idx=0):
    """
    提取指定 seed（第 seed_idx 个成功的 seed）下各条件的
    每智能体·每任务的期望价值随轮次变化曲线，以及各任务的真实价值。

    若 seed_idx 超出该条件的实际成功 seed 数，自动 fallback 到最后一个成功 seed。

    返回:
      per_agent : {cond: {'ev': [R, N, M], 'true_val': [M], 'used_seed_idx': int}}
                  ev[r, i, m] = 智能体 i 对任务 m 的期望价值预测（第 r 轮）
    """
    num_rounds  = int(to_scalar(config.get('num_rounds', 100)))
    num_points  = num_rounds + 1
    task_values = np.asarray(config.get('task_type_values', [800, 1000, 1500]),
                              dtype=float).ravel()

    # 第一遍：收集所有成功条目，按条件分组
    # cond_entries[cond] = list of (bh, tt, tv)
    cond_entries: dict[str, list] = {c: [] for c in conditions}

    for ci, si, entry in iter_belief_results(results):
        if not entry:
            continue
        succ = entry.get('success', False)
        if not (succ is True or float(succ) == 1.0):
            continue

        # 条件名：与 extract_belief_curves 保持相同的 fallback 逻辑
        cond_name = entry_condition_name(entry)
        if cond_name is None or cond_name not in cond_entries:
            cond_name = conditions[ci] if ci < len(conditions) else None
        if cond_name is None or cond_name not in cond_entries:
            print(f"  [fig2c 警告] ci={ci} si={si}: 无法匹配条件名，跳过。"
                  f" (entry_condition={entry_condition_name(entry)!r})")
            continue

        bh_raw = entry.get('belief_history')
        tt_raw = entry.get('true_task_types')
        tv_raw = entry.get('true_task_values')
        init_b_raw = entry.get('init_belief_matrix')
        init_b_tensor_raw = entry.get('init_belief_tensor')
        if bh_raw is None or tt_raw is None:
            print(f"  [fig2c 警告] ci={ci} si={si} ({cond_name}): "
                  f"belief_history 或 true_task_types 为空，跳过。")
            continue

        try:
            bh = np.asarray(bh_raw, dtype=float)
        except Exception as e:
            print(f"  [fig2c 警告] ci={ci} si={si} ({cond_name}): "
                  f"belief_history 转换失败: {e}，跳过。")
            continue

        if bh.ndim != 4:
            print(f"  [fig2c 警告] ci={ci} si={si} ({cond_name}): "
                  f"belief_history 维度={bh.ndim}（期望4），跳过。shape={bh.shape}")
            continue

        print(f"  [fig2c] ci={ci} si={si} ({cond_name}): belief_history shape={bh.shape}")
        cond_entries[cond_name].append((bh, tt_raw, tv_raw, init_b_raw, init_b_tensor_raw))

    # 第二遍：按 seed_idx（若越界则取最后一个）提取目标条目
    per_agent: dict[str, dict] = {}

    for cond in conditions:
        entries = cond_entries[cond]
        if not entries:
            print(f"  [fig2c] 条件 '{cond}' 无成功数据，跳过。")
            continue

        actual_idx = min(seed_idx, len(entries) - 1)
        if actual_idx != seed_idx:
            print(f"  [fig2c] 条件 '{cond}': seed_idx={seed_idx} 超出范围"
                  f"（共 {len(entries)} 个成功 seed），使用最后一个 (idx={actual_idx})。")

        bh, tt_raw, tv_raw, init_b_raw, init_b_tensor_raw = entries[actual_idx]
        R, N_dim, M_dim, T_dim = bh.shape

        round0_belief = build_round0_belief(init_b_raw, init_b_tensor_raw, N_dim, M_dim, T_dim)  # [N,M,T]
        ev = np.tensordot(bh, task_values, axes=([3], [0]))   # [R, N, M]
        ev0 = np.tensordot(round0_belief, task_values, axes=([2], [0]))[np.newaxis, :, :]  # [1,N,M]
        ev = np.concatenate([ev0, ev], axis=0)
        if ev.shape[0] < num_points:
            pad = np.full((num_points - ev.shape[0], N_dim, M_dim), np.nan)
            ev  = np.concatenate([ev, pad], axis=0)

        if tv_raw is not None:
            true_val = np.asarray(tv_raw, dtype=float).ravel()[:M_dim]
        else:
            true_types = np.asarray(tt_raw, dtype=int).ravel() - 1
            true_val = np.array([
                task_values[t] if 0 <= t < len(task_values) else np.nan
                for t in true_types
            ])

        per_agent[cond] = {
            'ev':             ev[:num_points],
            'true_val':       true_val,
            'used_seed_idx':  actual_idx,
        }

    return per_agent


# ══════════════════════════════════════════════════════════════════════════════
# 绘图函数
# ══════════════════════════════════════════════════════════════════════════════

def _plot_belief_curve(fig_key, data_dict, conditions, num_rounds, save_path, title=None):
    """
    通用：画某个按条件区分的逐轮曲线（均值 + 半透明误差带）。
    data_dict: {cond: {'mean': [R], 'std': [R]}}
    """
    cfg    = merge_figure_config(fig_key)
    fig, ax = plt.subplots(figsize=cm_size_to_inch(PLOT_GLOBAL['figsize_cm']))
    rounds  = np.arange(0, num_rounds + 1)

    for cond in conditions:
        entry = data_dict.get(cond)
        if entry is None:
            continue

        mu  = entry['mean']
        std = entry['std']

        if np.all(np.isnan(mu)):
            continue

        st = COND_STYLE.get(cond, DEFAULT_COND_STYLE)

        filled     = ffill(mu)
        std_filled = ffill(std) if std is not None else np.zeros_like(filled)

        if PLOT_GLOBAL.get('show_band', True) and not np.all(np.isnan(std)):
            ax.fill_between(
                rounds,
                filled - std_filled,
                filled + std_filled,
                color=st['color'],
                alpha=PLOT_GLOBAL.get('band_alpha', 0.18),
                linewidth=0,
            )

        ax.plot(
            rounds, filled,
            color=st['color'], ls=st['ls'],
            lw=PLOT_GLOBAL['linewidth'],
            label=st['label'],
        )

    apply_axis_controls(ax, cfg)
    apply_common_style(ax, cfg, title=title or cfg.get('title'))
    finalize_and_save(fig, save_path)


def plot_fig2a(conditions, num_rounds, belief_error, save_path):
    """图2a：信念误差（L1）随轮次变化（2种初始信念条件）"""
    _plot_belief_curve('fig2a', belief_error, conditions, num_rounds, save_path)


def plot_fig2b(conditions, num_rounds, expected_value, save_path):
    """图2b：期望价值预测随轮次变化（2种初始信念条件）"""
    _plot_belief_curve('fig2b', expected_value, conditions, num_rounds, save_path)


def plot_fig2c_per_condition(cond_name, ev_data, true_val, num_rounds, save_path):
    """
    图2c：某个条件下，每个任务一个子图，显示每个智能体的期望价值收敛曲线
          + 真实价值水平线。

    ev_data  : [R, N, M]  期望价值
    true_val : [M]        每个任务的真实价值
    """
    cfg     = merge_figure_config('fig2c')
    R, N_dim, M_dim = ev_data.shape
    rounds  = np.arange(0, num_rounds + 1)[:R]

    # 计算子图网格
    ncols = FIG2C_SUBPLOT_NCOLS or int(np.ceil(np.sqrt(M_dim)))
    nrows = int(np.ceil(M_dim / ncols))

    sw, sh = PLOT_GLOBAL['fig2c_subplot_size_cm']
    fig, axes = plt.subplots(
        nrows, ncols,
        figsize=cm_size_to_inch((sw * ncols, sh * nrows)),
        squeeze=False,
    )

    for m in range(M_dim):
        row, col = divmod(m, ncols)
        ax = axes[row][col]

        true_v = float(true_val[m]) if not np.isnan(true_val[m]) else None

        # 画每个智能体曲线
        for i in range(N_dim):
            curve = ev_data[:, i, m].copy()
            curve = ffill(curve)
            color = AGENT_COLORS[i % len(AGENT_COLORS)]
            ax.plot(
                rounds, curve,
                color=color,
                lw=PLOT_GLOBAL['agent_linewidth'],
                alpha=0.85,
                label=f'Agent {i+1}',
            )

        # 画真实价值水平线
        if true_v is not None:
            ax.axhline(
                true_v,
                color=TRUE_VALUE_STYLE['color'],
                ls=TRUE_VALUE_STYLE['ls'],
                lw=TRUE_VALUE_STYLE['lw'],
                label=TRUE_VALUE_STYLE['label'],
                zorder=5,
            )

        # 子图标题
        v_str = f'{true_v:.0f}' if true_v is not None else '?'
        if PLOT_GLOBAL.get('show_titles', True) and cfg.get('show_title', True):
            ax.set_title(
                cfg['title_template'].format(m=m + 1, v=true_v or 0),
                fontsize=PLOT_GLOBAL['fig2c_title_fontsize'],
                pad=PLOT_GLOBAL['title_pad'],
            )

        ax.set_xlabel(cfg['xlabel'], fontsize=PLOT_GLOBAL['xlabel_fontsize'])
        ax.set_ylabel(cfg['ylabel'], fontsize=PLOT_GLOBAL['ylabel_fontsize'])
        ax.tick_params(labelsize=PLOT_GLOBAL['tick_fontsize'])

        if PLOT_GLOBAL['show_grid']:
            ax.grid(True, linestyle=PLOT_GLOBAL['grid_linestyle'],
                    linewidth=PLOT_GLOBAL['grid_linewidth'],
                    alpha=PLOT_GLOBAL['grid_alpha'])

        if PLOT_GLOBAL['hide_top_spine']:
            ax.spines['top'].set_visible(False)
        if PLOT_GLOBAL['hide_right_spine']:
            ax.spines['right'].set_visible(False)

        if cfg.get('bottom_zero', False):
            ymin, ymax = ax.get_ylim()
            ax.set_ylim(bottom=0, top=ymax)

        # 仅在第一个子图显示图例
        if m == 0 and PLOT_GLOBAL['show_legend']:
            ax.legend(
                fontsize=PLOT_GLOBAL['fig2c_legend_fontsize'],
                framealpha=PLOT_GLOBAL['legend_framealpha'],
                edgecolor=PLOT_GLOBAL['legend_edgecolor'],
                loc='upper right',
                ncol=2,
            )

    # 隐藏多余的子图格
    for idx in range(M_dim, nrows * ncols):
        r, c = divmod(idx, ncols)
        axes[r][c].set_visible(False)

    # 整体标题
    cond_label = COND_STYLE.get(cond_name, DEFAULT_COND_STYLE).get('label', cond_name)
    if PLOT_GLOBAL.get('show_titles', True) and cfg.get('show_title', True):
        fig.suptitle(
            cfg['suptitle_template'].format(cond=cond_label),
            fontsize=PLOT_GLOBAL['title_fontsize'],
            y=1.01,
        )

    finalize_and_save(fig, save_path, tight_layout_rect=(0.0, 0.0, 1.0, 0.965))


def entry_success(entry):
    succ = entry.get('success', False)
    return bool(succ is True or to_scalar(succ) == 1.0)


def entry_seed(entry, fallback_seed):
    return int(round(to_scalar(entry.get('seed'), default=float(fallback_seed))))


def nanmean(arr, axis=None):
    with warnings.catch_warnings():
        warnings.simplefilter('ignore', category=RuntimeWarning)
        return np.nanmean(arr, axis=axis)


def nanstd(arr, axis=None):
    with warnings.catch_warnings():
        warnings.simplefilter('ignore', category=RuntimeWarning)
        return np.nanstd(arr, axis=axis)


def ffill_1d(arr):
    out = np.asarray(arr, dtype=float).copy()
    mask = np.isnan(out)
    valid = np.where(~mask)[0]
    if len(valid) == 0:
        return out
    first = valid[0]
    out[:first] = out[first]
    for idx in range(first + 1, len(out)):
        if np.isnan(out[idx]):
            out[idx] = out[idx - 1]
    return out


def pad_first_axis(arr, length, fill_value=np.nan):
    arr = np.asarray(arr, dtype=float)
    if arr.shape[0] >= length:
        return arr[:length]
    pad_shape = (length - arr.shape[0],) + arr.shape[1:]
    pad = np.full(pad_shape, fill_value, dtype=float)
    return np.concatenate([arr, pad], axis=0)


def align_task_values(task_values, n_types):
    out = np.zeros(n_types, dtype=float)
    vals = np.asarray(task_values, dtype=float).ravel()
    out[:min(n_types, len(vals))] = vals[:n_types]
    return out


def true_task_values_from_entry(entry, true_types, task_values, n_tasks):
    raw = entry.get('true_task_values')
    if raw is not None:
        vals = np.asarray(raw, dtype=float).ravel()
        if len(vals) >= n_tasks:
            return vals[:n_tasks]

    mapped = np.full(n_tasks, np.nan, dtype=float)
    for m, task_type in enumerate(true_types[:n_tasks]):
        if 0 <= task_type < len(task_values):
            mapped[m] = task_values[task_type]
    return mapped


def process_belief_entry(entry, cond_name, seed_value, num_points, task_values):
    bh_raw = entry.get('belief_history')
    tt_raw = entry.get('true_task_types')
    init_b_raw = entry.get('init_belief_matrix')
    init_b_tensor_raw = entry.get('init_belief_tensor')
    if bh_raw is None or tt_raw is None:
        return None

    try:
        bh = np.asarray(bh_raw, dtype=float)
    except Exception:
        return None

    if bh.ndim != 4:
        return None

    _, n_agents, n_tasks, n_types = bh.shape
    round0 = build_round0_belief(init_b_raw, init_b_tensor_raw, n_agents, n_tasks, n_types)
    beliefs = np.concatenate([round0[np.newaxis, :, :, :], bh], axis=0)
    beliefs = pad_first_axis(beliefs, num_points, fill_value=np.nan)

    aligned_task_values = align_task_values(task_values, n_types)
    true_types = np.asarray(tt_raw, dtype=int).ravel()[:n_tasks] - 1
    true_onehot = np.zeros((n_tasks, n_types), dtype=float)
    for m, task_type in enumerate(true_types):
        if 0 <= task_type < n_types:
            true_onehot[m, task_type] = 1.0

    true_values = true_task_values_from_entry(entry, true_types, aligned_task_values, n_tasks)
    denom = true_values.copy()
    denom[denom <= 0] = np.nan

    diff = beliefs - true_onehot[np.newaxis, np.newaxis, :, :]
    l1 = np.nansum(np.abs(diff), axis=3)
    v_hat = np.tensordot(beliefs, aligned_task_values, axes=([3], [0]))
    rel_abs_err = np.abs(v_hat - true_values[np.newaxis, np.newaxis, :]) / denom[np.newaxis, np.newaxis, :]
    signed_bias = (v_hat - true_values[np.newaxis, np.newaxis, :]) / denom[np.newaxis, np.newaxis, :]

    return {
        'condition': cond_name,
        'seed': seed_value,
        'beliefs': beliefs,
        'l1': l1,
        'v_hat': v_hat,
        'rel_abs_err': rel_abs_err,
        'signed_bias': signed_bias,
        'true_values': true_values,
        'num_agents': n_agents,
        'num_tasks': n_tasks,
        'num_types': n_types,
    }


def collect_condition_entries(results, config):
    conditions = parse_conditions(config)
    num_rounds = int(to_scalar(config.get('num_rounds', 100)))
    num_points = num_rounds + 1
    task_values = np.asarray(config.get('task_type_values', [500, 1000, 2000]), dtype=float).ravel()

    cond_entries = {cond: [] for cond in conditions}
    skipped = 0

    for ci, si, entry in iter_belief_results(results):
        if not entry or not entry_success(entry):
            continue

        cond_name = entry_condition_name(entry)
        if cond_name is None or cond_name not in cond_entries:
            cond_name = conditions[ci] if ci < len(conditions) else None
        if cond_name is None or cond_name not in cond_entries:
            skipped += 1
            continue

        seed_value = entry_seed(entry, fallback_seed=si)
        processed = process_belief_entry(entry, cond_name, seed_value, num_points, task_values)
        if processed is None:
            skipped += 1
            continue
        cond_entries[cond_name].append(processed)

    for cond in conditions:
        cond_entries[cond] = sorted(cond_entries[cond], key=lambda x: x['seed'])

    return conditions, num_rounds, task_values, cond_entries, skipped


def compute_curve_stats(curves):
    if len(curves) == 0:
        return {
            'curves': np.empty((0, 0), dtype=float),
            'mean': np.array([], dtype=float),
            'std': np.array([], dtype=float),
            'ci95': np.array([], dtype=float),
            'n_seed': 0,
        }

    mat = np.vstack(curves).astype(float)
    mean = nanmean(mat, axis=0)
    std = nanstd(mat, axis=0)
    n_valid = np.sum(np.isfinite(mat), axis=0)
    ci95 = np.full(mean.shape, np.nan, dtype=float)
    mask = n_valid > 1
    ci95[mask] = 1.96 * std[mask] / np.sqrt(n_valid[mask])
    return {
        'curves': mat,
        'mean': mean,
        'std': std,
        'ci95': ci95,
        'n_seed': mat.shape[0],
    }


def build_summary_data(cond_entries):
    summary = {}
    for cond, entries in cond_entries.items():
        l1_curves = [nanmean(entry['l1'], axis=(1, 2)) for entry in entries]
        rel_curves = [nanmean(entry['rel_abs_err'], axis=(1, 2)) for entry in entries]
        summary[cond] = {
            'l1': compute_curve_stats(l1_curves),
            'rel': compute_curve_stats(rel_curves),
            'n_seed': len(entries),
        }
    return summary


def select_reference_seed(cond_entries, conditions, seed_idx):
    seed_sets = []
    for cond in conditions:
        entries = cond_entries.get(cond, [])
        if not entries:
            return None, {}
        seed_sets.append({entry['seed'] for entry in entries})

    common_seeds = sorted(set.intersection(*seed_sets)) if seed_sets else []
    if not common_seeds:
        return None, {}

    actual_idx = min(seed_idx, len(common_seeds) - 1)
    seed_value = common_seeds[actual_idx]
    ref_entries = {}
    for cond in conditions:
        for entry in cond_entries[cond]:
            if entry['seed'] == seed_value:
                ref_entries[cond] = entry
                break
    return seed_value, ref_entries


def first_convergence_round(abs_bias_curve, threshold=CONV_THRESHOLD, streak=CONV_STREAK, fail_round=None):
    arr = np.asarray(abs_bias_curve, dtype=float).ravel()
    for start in range(0, max(len(arr) - streak + 1, 0)):
        window = arr[start:start + streak]
        if np.all(np.isfinite(window) & (window < threshold)):
            return start
    return fail_round if fail_round is not None else len(arr) - 1


def unique_keep_order(seq):
    seen = set()
    out = []
    for item in seq:
        if item in seen:
            continue
        seen.add(item)
        out.append(item)
    return out


def select_representative_tasks(reference_entries, conditions, num_rounds):
    if not reference_entries:
        return [], {}, np.array([], dtype=float)

    first_entry = reference_entries[conditions[0]]
    n_tasks = first_entry['num_tasks']
    true_values = first_entry['true_values'][:n_tasks]
    conv_by_cond = {}

    for cond in conditions:
        entry = reference_entries.get(cond)
        if entry is None:
            continue
        mean_bias = nanmean(entry['signed_bias'], axis=1)
        conv = np.full(n_tasks, num_rounds + 1, dtype=float)
        for task_idx in range(n_tasks):
            conv[task_idx] = first_convergence_round(
                np.abs(mean_bias[:, task_idx]),
                threshold=CONV_THRESHOLD,
                streak=CONV_STREAK,
                fail_round=num_rounds + 1,
            )
        conv_by_cond[cond] = conv

    if not conv_by_cond:
        return [], {}, true_values

    difficulty = np.full(n_tasks, -np.inf, dtype=float)
    for task_idx in range(n_tasks):
        vals = [conv_by_cond[cond][task_idx] for cond in conv_by_cond]
        difficulty[task_idx] = np.nanmax(vals)

    order = np.argsort(difficulty)[::-1]
    if n_tasks == 1:
        selected = [int(order[0])]
        role_map = {int(order[0]): 'representative'}
    elif n_tasks == 2:
        selected = unique_keep_order([int(order[0]), int(order[-1])])
        role_labels = ['hardest', 'easiest'][:len(selected)]
        role_map = {task_idx: role_labels[i] for i, task_idx in enumerate(selected)}
    else:
        selected = unique_keep_order([int(order[0]), int(order[len(order) // 2]), int(order[-1])])
        role_labels = ['hardest', 'median', 'easiest'][:len(selected)]
        role_map = {task_idx: role_labels[i] for i, task_idx in enumerate(selected)}

    return selected, role_map, true_values


def apply_axes_style(ax, xlabel, ylabel, title=None, bottom_zero=False):
    STYLE_HELPER_NO_LEGEND.apply_common_style(
        ax,
        xlabel=xlabel,
        ylabel=ylabel,
        title=title,
    )
    if bottom_zero:
        ymin, ymax = ax.get_ylim()
        ax.set_ylim(bottom=0.0, top=ymax)


def get_markevery(num_points):
    if num_points <= 12:
        return 1
    return max(1, int(np.ceil(num_points / 10)))


def plot_policy_curve(ax, rounds, stats, style):
    mean = ffill_1d(stats['mean'])
    if np.all(np.isnan(mean)):
        return

    if stats['n_seed'] < MIN_SEEDS_FOR_CI:
        for curve in stats['curves']:
            seed_curve = ffill_1d(curve)
            if np.all(np.isnan(seed_curve)):
                continue
            ax.plot(
                rounds,
                seed_curve,
                color=style['color'],
                ls=style['ls'],
                lw=PLOT_GLOBAL['thin_linewidth'],
                alpha=PLOT_GLOBAL['thin_alpha'],
                zorder=1,
            )
    else:
        ci = ffill_1d(stats['ci95'])
        if not np.all(np.isnan(ci)):
            ax.fill_between(
                rounds,
                mean - ci,
                mean + ci,
                color=style['color'],
                alpha=PLOT_GLOBAL['band_alpha'],
                linewidth=0.0,
                zorder=1,
            )

    ax.plot(
        rounds,
        mean,
        color=style['color'],
        ls=style['ls'],
        lw=PLOT_GLOBAL['linewidth'],
        marker=PLOT_GLOBAL['marker'],
        markersize=PLOT_GLOBAL['markersize'],
        markevery=get_markevery(len(rounds)),
        markerfacecolor='white',
        markeredgewidth=1.0,
        label=f"{style['label']} (n={stats['n_seed']})",
        zorder=3,
    )


def compute_y_limits(curves, extra_values=None, lower_zero=False):
    vals = []
    for curve in curves:
        arr = np.asarray(curve, dtype=float).ravel()
        vals.extend(arr[np.isfinite(arr)].tolist())
    if extra_values is not None:
        arr = np.asarray(extra_values, dtype=float).ravel()
        vals.extend(arr[np.isfinite(arr)].tolist())

    if not vals:
        return (0.0, 1.0) if lower_zero else (-1.0, 1.0)

    ymin = min(vals)
    ymax = max(vals)
    if lower_zero:
        ymin = 0.0
    if ymax <= ymin:
        ymax = ymin + 1.0
    pad = 0.08 * (ymax - ymin)
    return ymin - (0.0 if lower_zero else pad), ymax + pad


def plot_summary_figure(conditions, num_rounds, summary_data, save_path):
    rounds = np.arange(0, num_rounds + 1)
    fig, axes = plt.subplots(1, 2, figsize=cm_size_to_inch(PLOT_GLOBAL['summary_figsize_cm']), squeeze=False)
    axes = axes.ravel()

    panel_specs = [
        ('summary_left', 'l1'),
        ('summary_right', 'rel'),
    ]

    for ax, (cfg_key, metric_key) in zip(axes, panel_specs):
        cfg = merge_figure_config(cfg_key)
        for cond in conditions:
            stats = summary_data.get(cond, {}).get(metric_key)
            if stats is None or stats['n_seed'] == 0:
                continue
            plot_policy_curve(ax, rounds, stats, COND_STYLE.get(cond, DEFAULT_COND_STYLE))

        ax.set_xlim(0, num_rounds)
        apply_axes_style(
            ax,
            cfg['xlabel'],
            cfg['ylabel'],
            title=cfg['title'],
            bottom_zero=cfg.get('bottom_zero', False),
        )

    handles, labels = axes[0].get_legend_handles_labels()
    if handles:
        fig.legend(
            handles,
            labels,
            loc='upper center',
            ncol=max(1, len(labels)),
            fontsize=PLOT_GLOBAL['legend_fontsize'],
            framealpha=PLOT_GLOBAL['legend_framealpha'],
            edgecolor=PLOT_GLOBAL['legend_edgecolor'],
        )
    finalize_and_save(fig, save_path, tight_layout_rect=(0.0, 0.0, 1.0, 0.92))


def plot_representative_tasks(reference_entries, conditions, selected_tasks, role_map, true_values,
                              num_rounds, save_path, reference_seed):
    if not selected_tasks:
        print('  Skip representative-task figure: no valid task selected.')
        return

    rounds = np.arange(0, num_rounds + 1)
    ncols = len(selected_tasks)
    fig, axes = plt.subplots(
        1,
        ncols,
        figsize=cm_size_to_inch((PLOT_GLOBAL['rep_figsize_per_panel_cm'][0] * ncols, PLOT_GLOBAL['rep_figsize_per_panel_cm'][1])),
        squeeze=False,
        sharey=True,
    )
    axes = axes.ravel()

    all_curves = []
    for task_idx in selected_tasks:
        for cond in conditions:
            entry = reference_entries.get(cond)
            if entry is None:
                continue
            all_curves.append(nanmean(entry['v_hat'][:, :, task_idx], axis=1))
    y_limits = compute_y_limits(all_curves, extra_values=true_values[selected_tasks], lower_zero=False)

    for ax, task_idx in zip(axes, selected_tasks):
        for cond in conditions:
            entry = reference_entries.get(cond)
            if entry is None:
                continue
            mean_curve = ffill_1d(nanmean(entry['v_hat'][:, :, task_idx], axis=1))
            st = COND_STYLE.get(cond, DEFAULT_COND_STYLE)
            ax.plot(
                rounds,
                mean_curve,
                color=st['color'],
                ls=st['ls'],
                lw=PLOT_GLOBAL['linewidth'],
                marker=PLOT_GLOBAL['marker'],
                markersize=PLOT_GLOBAL['markersize'],
                markevery=get_markevery(len(rounds)),
                markerfacecolor='white',
                markeredgewidth=1.0,
                label=st['label'],
                zorder=3,
            )

        true_val = true_values[task_idx]
        if np.isfinite(true_val):
            ax.axhline(
                true_val,
                color=TRUE_VALUE_STYLE['color'],
                ls=TRUE_VALUE_STYLE['ls'],
                lw=TRUE_VALUE_STYLE['lw'],
                label=TRUE_VALUE_STYLE['label'],
                zorder=2,
            )

        role = role_map.get(task_idx, 'selected')
        ax.set_xlim(0, num_rounds)
        ax.set_ylim(*y_limits)
        apply_axes_style(
            ax,
            FIGURE_CONFIG['representative']['xlabel'],
            FIGURE_CONFIG['representative']['ylabel'] if ax is axes[0] else '',
            title=f"{role.title()} | T{task_idx + 1} | V={true_val:.0f}",
            bottom_zero=False,
        )

    handles, labels = axes[0].get_legend_handles_labels()
    if handles:
        fig.legend(
            handles,
            labels,
            loc='upper center',
            bbox_to_anchor=(0.5, 1.00),
            ncol=max(1, len(labels)),
            fontsize=PLOT_GLOBAL['legend_fontsize'],
            framealpha=PLOT_GLOBAL['legend_framealpha'],
            edgecolor=PLOT_GLOBAL['legend_edgecolor'],
        )
    if PLOT_GLOBAL.get('show_titles', True):
        fig.suptitle(
            f"{FIGURE_CONFIG['representative']['title']}  [reference seed = {reference_seed}]",
            fontsize=PLOT_GLOBAL['subtitle_fontsize'],
            y=1.07,
        )
    finalize_and_save(fig, save_path, tight_layout_rect=(0.0, 0.0, 1.0, 0.88))


def plot_appendix_agent_examples(reference_entries, conditions, selected_tasks, role_map, true_values,
                                 num_rounds, save_path, reference_seed):
    if not selected_tasks:
        print('  Skip appendix figure: no valid task selected.')
        return

    appendix_tasks = unique_keep_order(
        [selected_tasks[0], selected_tasks[-1]] if len(selected_tasks) > 1 else [selected_tasks[0]]
    )
    avail_conditions = [cond for cond in conditions if cond in reference_entries]
    if not avail_conditions:
        print('  Skip appendix figure: no reference entries available.')
        return

    rounds = np.arange(0, num_rounds + 1)
    nrows = len(avail_conditions)
    ncols = len(appendix_tasks)
    fig, axes = plt.subplots(
        nrows,
        ncols,
        figsize=cm_size_to_inch((PLOT_GLOBAL['appendix_cell_size_cm'][0] * ncols, PLOT_GLOBAL['appendix_cell_size_cm'][1] * nrows)),
        squeeze=False,
        sharex=True,
        sharey=True,
    )

    all_curves = []
    for cond in avail_conditions:
        entry = reference_entries[cond]
        for task_idx in appendix_tasks:
            all_curves.extend(entry['v_hat'][:, :, task_idx].T)
    y_limits = compute_y_limits(all_curves, extra_values=true_values[appendix_tasks], lower_zero=False)

    for row, cond in enumerate(avail_conditions):
        entry = reference_entries[cond]
        st = COND_STYLE.get(cond, DEFAULT_COND_STYLE)
        for col, task_idx in enumerate(appendix_tasks):
            ax = axes[row][col]
            n_agents = entry['v_hat'].shape[1]
            for agent_idx in range(n_agents):
                agent_curve = ffill_1d(entry['v_hat'][:, agent_idx, task_idx])
                ax.plot(
                    rounds,
                    agent_curve,
                    color=AGENT_TRACE_STYLE['color'],
                    lw=AGENT_TRACE_STYLE['lw'],
                    alpha=AGENT_TRACE_STYLE['alpha'],
                    label=AGENT_TRACE_STYLE['label'] if (row == 0 and col == 0 and agent_idx == 0) else '_nolegend_',
                    zorder=1,
                )

            mean_curve = ffill_1d(nanmean(entry['v_hat'][:, :, task_idx], axis=1))
            ax.plot(
                rounds,
                mean_curve,
                color=st['color'],
                ls=st['ls'],
                lw=PLOT_GLOBAL['agent_mean_linewidth'],
                marker=PLOT_GLOBAL['marker'],
                markersize=PLOT_GLOBAL['markersize'] - 0.4,
                markevery=get_markevery(len(rounds)),
                markerfacecolor='white',
                markeredgewidth=1.0,
                label=st['label'] if (row == 0 and col == 0) else '_nolegend_',
                zorder=3,
            )

            true_val = true_values[task_idx]
            if np.isfinite(true_val):
                ax.axhline(
                    true_val,
                    color=TRUE_VALUE_STYLE['color'],
                    ls=TRUE_VALUE_STYLE['ls'],
                    lw=TRUE_VALUE_STYLE['lw'],
                    label=TRUE_VALUE_STYLE['label'] if (row == 0 and col == 0) else '_nolegend_',
                    zorder=2,
                )

            ax.set_xlim(0, num_rounds)
            ax.set_ylim(*y_limits)
            title = f"{role_map.get(task_idx, 'selected').title()} | T{task_idx + 1} | V={true_val:.0f}"
            if row == 0 and PLOT_GLOBAL.get('show_titles', True):
                ax.set_title(title, fontsize=PLOT_GLOBAL['subtitle_fontsize'], pad=PLOT_GLOBAL['title_pad'])

            ylabel = f"{st['label']}\nExpected value" if col == 0 else ''
            apply_axes_style(
                ax,
                FIGURE_CONFIG['appendix_new']['xlabel'],
                ylabel,
                title=None,
                bottom_zero=False,
            )

    handles, labels = axes[0][0].get_legend_handles_labels()
    if handles:
        fig.legend(
            handles,
            labels,
            loc='upper center',
            bbox_to_anchor=(0.5, 1.00),
            ncol=max(1, len(labels)),
            fontsize=PLOT_GLOBAL['appendix_legend_fontsize'],
            framealpha=PLOT_GLOBAL['legend_framealpha'],
            edgecolor=PLOT_GLOBAL['legend_edgecolor'],
        )
    if PLOT_GLOBAL.get('show_titles', True):
        fig.suptitle(
            f"{FIGURE_CONFIG['appendix_new']['title']}  [reference seed = {reference_seed}]",
            fontsize=PLOT_GLOBAL['subtitle_fontsize'],
            y=1.07,
        )
    finalize_and_save(fig, save_path, tight_layout_rect=(0.0, 0.0, 1.0, 0.88))


# ══════════════════════════════════════════════════════════════════════════════
# 主程序
# ══════════════════════════════════════════════════════════════════════════════

def legacy_main():
    STYLE_HELPER.apply_rcparams()
    mat_path = find_mat_file(sys.argv)
    source_name = infer_source_name(mat_path, fallback='belief')
    configure_output_dir(source_name)
    original_save_formats = list(PLOT_GLOBAL.get('save_formats', ['png', 'eps']))
    set_save_formats(['png'])

    try:
        print("\n加载数据...")
        raw     = mat73.loadmat(mat_path)
        results = raw['belief_results']
        config  = raw['belief_config']

        conditions = parse_conditions(config)
        num_rounds = int(to_scalar(config.get('num_rounds', 100)))
        nC, nS     = get_belief_shape(results)

        print(f"  conditions = {conditions}")
        print(f"  num_rounds = {num_rounds} (+ round 0)")
        print(f"  形状       = {nC}×{nS} (条件×seed)")

    # 时间戳
        basename = os.path.splitext(os.path.basename(mat_path))[0]
        parts    = basename.split('_')
        ts       = '_'.join(parts[-2:]) if len(parts) >= 2 else 'ts'

    # ── 图2a / 图2b：跨 seed 均值 ± 误差带 ─────────────────────────────────
        print("\n提取信念曲线（均值/误差）...")
        conditions, num_rounds, task_values, belief_error, expected_value = \
            extract_belief_curves(results, config)

        print(f"  task_values = {task_values}")
        print(f"\n绘图 → {FIGURES_DIR}")

        plot_fig2a(
            conditions, num_rounds, belief_error,
            build_png_output_path(f'belief_error_curve_{ts}'),
        )
        plot_fig2b(
            conditions, num_rounds, expected_value,
            build_png_output_path(f'expected_value_curve_{ts}'),
        )

        # ── 图2c：每任务·每智能体收敛图（单个 seed，每条件一张大图）─────────────
        print(f"\n提取每智能体数据（seed_idx={FIG2C_SEED_IDX}）...")
        per_agent = extract_per_agent_data(
            results,
            config,
            conditions,
            seed_idx=FIG2C_SEED_IDX,
        )

        for cond_name in conditions:
            if cond_name not in per_agent:
                print(f"  跳过 {cond_name}（无有效数据）")
                continue

            ev_data  = per_agent[cond_name]['ev']       # [R, N, M]
            true_val = per_agent[cond_name]['true_val']  # [M]

            print(f"  绘制 fig2c [{cond_name}]: {ev_data.shape[2]} 个任务, "
                  f"{ev_data.shape[1]} 个智能体")

            save_path = build_png_output_path(
                f'per_agent_belief_convergence_{build_condition_token(cond_name)}_{ts}'
            )
            plot_fig2c_per_condition(cond_name, ev_data, true_val, num_rounds, save_path)

        print("\n完成。图窗已弹出，关闭后程序退出。")
        plt.show()
    finally:
        set_save_formats(original_save_formats)


def main():
    STYLE_HELPER.apply_rcparams()
    mat_path = find_mat_file(sys.argv)
    source_name = infer_source_name(mat_path, fallback='belief')
    configure_output_dir(source_name)

    print("\nLoading data...")
    raw = mat73.loadmat(mat_path)
    results = raw['belief_results']
    config = raw['belief_config']

    conditions = parse_conditions(config)
    num_rounds = int(to_scalar(config.get('num_rounds', 100)))
    nC, nS = get_belief_shape(results)

    print(f"  conditions = {conditions}")
    print(f"  num_rounds = {num_rounds} (+ round 0)")
    print(f"  raw shape  = {nC} x {nS} (condition x seed)")

    print("\nExtracting valid entries...")
    conditions, num_rounds, task_values, cond_entries, skipped = collect_condition_entries(results, config)
    print(f"  task_values = {task_values.tolist()}")
    for cond in conditions:
        seeds = [entry['seed'] for entry in cond_entries[cond]]
        print(f"  {cond}: {len(seeds)} successful seed(s) -> {seeds}")
    if skipped > 0:
        print(f"  skipped invalid entries = {skipped}")

    print(f"\nFigure output dir = {FIGURES_DIR}")
    summary_data = build_summary_data(cond_entries)
    plot_summary_figure(
        conditions,
        num_rounds,
        summary_data,
        build_output_stem('summary_belief_and_value_error'),
    )

    reference_seed, reference_entries = select_reference_seed(cond_entries, conditions, FIG2C_SEED_IDX)
    if reference_seed is None:
        print("  No common successful seed across all conditions. Skip task-level figures.")
    else:
        print(f"  reference seed for task-level figures = {reference_seed}")
        selected_tasks, role_map, true_values = select_representative_tasks(reference_entries, conditions, num_rounds)
        if selected_tasks:
            print(
                "  representative tasks = "
                + ", ".join(
                    f"T{task_idx + 1}({role_map.get(task_idx, 'selected')}, V={true_values[task_idx]:.0f})"
                    for task_idx in selected_tasks
                )
            )

        plot_representative_tasks(
            reference_entries,
            conditions,
            selected_tasks,
            role_map,
            true_values,
            num_rounds,
            build_output_stem('representative_task_convergence'),
            reference_seed=reference_seed,
        )
        plot_appendix_agent_examples(
            reference_entries,
            conditions,
            selected_tasks,
            role_map,
            true_values,
            num_rounds,
            build_output_stem('agent_level_representative_task_trajectories'),
            reference_seed=reference_seed,
        )

    backend = plt.get_backend().lower()
    if 'agg' in backend:
        print("\nDone. Non-interactive backend detected; skip plt.show().")
    else:
        print("\nDone. Close the figure windows to exit.")
        plt.show()


if __name__ == '__main__':
    main()
