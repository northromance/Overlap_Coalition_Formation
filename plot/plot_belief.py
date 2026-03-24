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

import os
import sys
import glob
import copy
import numpy as np
import matplotlib.pyplot as plt
import matplotlib.ticker as mticker

try:
    import mat73
except ImportError:
    sys.exit("缺少依赖，请先执行: pip install mat73")


# ══════════════════════════════════════════════════════════════════════════════
# 顶部可调参数区（建议以后优先在这里改）
# ══════════════════════════════════════════════════════════════════════════════

# ── 路径配置 ──────────────────────────────────────────────────────────────────
SCRIPT_DIR  = os.path.dirname(os.path.abspath(__file__))
ROOT_DIR    = os.path.dirname(SCRIPT_DIR)
FIGURES_DIR = os.path.join(ROOT_DIR, 'figures', 'paper')
SEARCH_DIRS = [
    os.path.join(ROOT_DIR, 'results', 'batch', 'belief'),
    os.path.join(ROOT_DIR, 'results', 'batch'),
]

# ── 信念条件显示样式（颜色 / 线型 / 图例名）────────────────────────────────────
COND_STYLE = {
    'uniform':      dict(color='#4878CF', ls='-',  label='Uniform prior'),
    'heterogeneous': dict(color='#D65F5F', ls='--', label='Heterogeneous prior'),
}
DEFAULT_COND_STYLE = dict(color='#888888', ls=':', label='Unknown')

# ── 图2c 每智能体曲线调色板（最多支持 20 个智能体）───────────────────────────
AGENT_COLORS = [
    "#0D80D2", '#ff7f0e', '#2ca02c', '#d62728', '#9467bd',
    '#8c564b', '#e377c2', '#7f7f7f', '#bcbd22', '#17becf',
    '#aec7e8', '#ffbb78', '#98df8a', '#ff9896', '#c5b0d5',
    '#c49c94', '#f7b6d2', '#c7c7c7', '#dbdb8d', '#9edae5',
]
TRUE_VALUE_STYLE = dict(color='#000000', ls=':', lw=2.0, label='True value')

# ── 图2c 子图布局（设 None 则自动按 ceil(sqrt(M)) 计算）──────────────────────
FIG2C_SUBPLOT_NCOLS = None   # 每行子图数，None=自动
FIG2C_SEED_IDX      = 1      # 用第几个（0-indexed）成功 seed 展示单 seed 图

# ── 全局绘图参数 ──────────────────────────────────────────────────────────────
PLOT_GLOBAL = {
    # 图尺寸（fig2a/2b 单图，fig2c 每个子图面积自动缩放）
    'figsize': (5.5, 4.2),
    'fig2c_subplot_size': (3.2, 2.6),   # 每个子图的目标尺寸（宽×高，inch）

    # 线条 / 误差带
    'linewidth': 1.8,
    'agent_linewidth': 1.2,             # 图2c 中智能体曲线线宽
    'band_alpha': 0.18,
    'show_band': True,     # 是否显示半透明误差带

    # 字体与版式
    'xlabel_fontsize': 11,
    'ylabel_fontsize': 11,
    'title_fontsize': 12,
    'title_pad': 8,
    'tick_fontsize': 10,
    'legend_fontsize': 9,
    'fig2c_title_fontsize': 9,          # 图2c 每个子图标题字号
    'fig2c_legend_fontsize': 7,         # 图2c 图例字号

    # 网格 / 图例 / 边框
    'show_grid': True,
    'grid_linestyle': '--',
    'grid_linewidth': 0.6,
    'grid_alpha': 0.4,
    'show_legend': True,
    'legend_framealpha': 0.85,
    'legend_edgecolor': '#cccccc',
    'hide_top_spine': True,
    'hide_right_spine': True,

    # 保存参数
    'save_dpi': 150,
    'save_bbox_inches': 'tight',

    # 画布
    'tight_layout': True,
}

# ── 每个图单独控制（坐标轴 / 刻度 / 标题 / 范围）──────────────────────────────
FIGURE_CONFIG = {
    'fig2a': {
        'show_title': True,
        'title': 'Fig. 2a — Belief Error vs. Round',
        'xlabel': 'Round',
        'ylabel': 'Avg. L1 Belief Error',
        'xlim': None,
        'ylim': None,
        'xticks': None,
        'yticks': None,
        'bottom_zero': True,
    },
    'fig2b': {
        'show_title': True,
        'title': 'Fig. 2b — Expected Value Prediction vs. Round',
        'xlabel': 'Round',
        'ylabel': 'Avg. Expected Task Value',
        'xlim': None,
        'ylim': None,
        'xticks': None,
        'yticks': None,
        'bottom_zero': False,
    },
    'fig2c': {
        'show_title': True,
        'title_template': 'Task {m} (true={v:.0f})',   # 每子图标题模板
        'suptitle_template': 'Fig. 2c — Per-agent Belief Convergence [{cond}]',
        'xlabel': 'Round',
        'ylabel': 'Expected Value',
        'xlim': None,
        'ylim': None,
        'bottom_zero': False,
    },
}

os.makedirs(FIGURES_DIR, exist_ok=True)


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
    cfg = copy.deepcopy(FIGURE_CONFIG[fig_key])
    cfg.update(kwargs)
    return cfg


def apply_common_style(ax, cfg, title=None, legend_fontsize=None):
    """统一处理坐标轴标签、标题、网格、图例和边框。"""
    ax.set_xlabel(cfg['xlabel'], fontsize=PLOT_GLOBAL['xlabel_fontsize'])
    ax.set_ylabel(cfg['ylabel'], fontsize=PLOT_GLOBAL['ylabel_fontsize'])

    if cfg.get('show_title', True) and title:
        ax.set_title(
            title,
            fontsize=PLOT_GLOBAL['title_fontsize'],
            pad=PLOT_GLOBAL['title_pad'],
        )

    if PLOT_GLOBAL['show_grid']:
        ax.grid(
            True,
            linestyle=PLOT_GLOBAL['grid_linestyle'],
            linewidth=PLOT_GLOBAL['grid_linewidth'],
            alpha=PLOT_GLOBAL['grid_alpha'],
        )

    ax.tick_params(labelsize=PLOT_GLOBAL['tick_fontsize'])

    if PLOT_GLOBAL['show_legend']:
        ax.legend(
            fontsize=legend_fontsize or PLOT_GLOBAL['legend_fontsize'],
            framealpha=PLOT_GLOBAL['legend_framealpha'],
            edgecolor=PLOT_GLOBAL['legend_edgecolor'],
        )

    if PLOT_GLOBAL['hide_top_spine']:
        ax.spines['top'].set_visible(False)
    if PLOT_GLOBAL['hide_right_spine']:
        ax.spines['right'].set_visible(False)


def apply_axis_controls(ax, cfg):
    """统一处理 xlim / ylim / xticks / yticks / 底部从 0 开始等。"""
    if cfg.get('xticks') is not None:
        ax.set_xticks(cfg['xticks'])
    if cfg.get('yticks') is not None:
        ax.set_yticks(cfg['yticks'])

    if cfg.get('xlim') is not None:
        ax.set_xlim(*cfg['xlim'])
    if cfg.get('ylim') is not None:
        ax.set_ylim(*cfg['ylim'])

    if cfg.get('bottom_zero', False):
        ymin, ymax = ax.get_ylim()
        ax.set_ylim(bottom=0, top=ymax)


def finalize_and_save(fig, save_path, tight_layout_rect=None):
    if PLOT_GLOBAL['tight_layout']:
        if tight_layout_rect is None:
            fig.tight_layout()
        else:
            fig.tight_layout(rect=tight_layout_rect)
    fig.savefig(
        save_path,
        dpi=PLOT_GLOBAL['save_dpi'],
        bbox_inches=PLOT_GLOBAL['save_bbox_inches'],
    )
    print(f"  ✓ {save_path}")


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


def build_round0_belief(init_b_raw, n_agents, n_tasks, n_types):
    """Expand per-agent initial priors to per-agent-per-task beliefs at round 0."""
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

        round0_belief = build_round0_belief(init_b_raw, N_dim, M_dim, T_dim)   # [N,M,T]

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
        cond_entries[cond_name].append((bh, tt_raw, tv_raw, init_b_raw))

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

        bh, tt_raw, tv_raw, init_b_raw = entries[actual_idx]
        R, N_dim, M_dim, T_dim = bh.shape

        round0_belief = build_round0_belief(init_b_raw, N_dim, M_dim, T_dim)  # [N,M,T]
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
    fig, ax = plt.subplots(figsize=PLOT_GLOBAL['figsize'])
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

    sw, sh = PLOT_GLOBAL['fig2c_subplot_size']
    fig, axes = plt.subplots(
        nrows, ncols,
        figsize=(sw * ncols, sh * nrows),
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
        ax.set_title(
            cfg['title_template'].format(m=m + 1, v=true_v or 0),
            fontsize=PLOT_GLOBAL['fig2c_title_fontsize'],
        )

        ax.set_xlabel(cfg['xlabel'], fontsize=PLOT_GLOBAL['xlabel_fontsize'] - 1)
        ax.set_ylabel(cfg['ylabel'], fontsize=PLOT_GLOBAL['ylabel_fontsize'] - 1)
        ax.tick_params(labelsize=PLOT_GLOBAL['tick_fontsize'] - 1)

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
    if cfg.get('show_title', True):
        fig.suptitle(
            cfg['suptitle_template'].format(cond=cond_label),
            fontsize=PLOT_GLOBAL['title_fontsize'],
            y=1.01,
        )

    finalize_and_save(fig, save_path, tight_layout_rect=(0.0, 0.0, 1.0, 0.965))


# ══════════════════════════════════════════════════════════════════════════════
# 主程序
# ══════════════════════════════════════════════════════════════════════════════

def main():
    mat_path = find_mat_file(sys.argv)

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
        os.path.join(FIGURES_DIR, f'fig2a_belief_error_{ts}.png'),
    )
    plot_fig2b(
        conditions, num_rounds, expected_value,
        os.path.join(FIGURES_DIR, f'fig2b_expected_value_{ts}.png'),
    )

    # ── 图2c：每任务·每智能体收敛图（单个 seed，每条件一张大图）─────────────
    print(f"\n提取每智能体数据（seed_idx={FIG2C_SEED_IDX}）...")
    per_agent = extract_per_agent_data(results, config, conditions,
                                        seed_idx=FIG2C_SEED_IDX)

    for cond_name in conditions:
        if cond_name not in per_agent:
            print(f"  跳过 {cond_name}（无有效数据）")
            continue

        ev_data  = per_agent[cond_name]['ev']       # [R, N, M]
        true_val = per_agent[cond_name]['true_val']  # [M]

        print(f"  绘制 fig2c [{cond_name}]: {ev_data.shape[2]} 个任务, "
              f"{ev_data.shape[1]} 个智能体")

        save_path = os.path.join(
            FIGURES_DIR, f'fig2c_per_agent_{cond_name}_{ts}.png'
        )
        plot_fig2c_per_condition(cond_name, ev_data, true_val, num_rounds, save_path)

    print("\n完成。图窗已弹出，关闭后程序退出。")
    plt.show()


if __name__ == '__main__':
    main()
