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
import numpy as np
import matplotlib.pyplot as plt
import matplotlib.patches as mpatches
from matplotlib.colors import Normalize, TwoSlopeNorm
from matplotlib.cm import ScalarMappable
from plot_style_helper import PlotStyleHelper

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
    os.path.join(ROOT_DIR, 'results', 'batch', 'visualize'),
    os.path.join(ROOT_DIR, 'results', 'batch'),
]

# ── 任务类型颜色（甘特图 / 子图标题颜色）─────────────────────────────────────
TASK_TYPE_COLOR = {
    1: '#4878CF',   # 低价值 — 蓝
    2: '#6ACC65',   # 中价值 — 绿
    3: '#D65F5F',   # 高价值 — 红
}
TASK_TYPE_LABEL = {
    1: 'Type-1 (Low value)',
    2: 'Type-2 (Med value)',
    3: 'Type-3 (High value)',
}
DEFAULT_TASK_COLOR = '#AAAAAA'
RESOURCE_COLORS = ['#4E79A7', '#F28E2B', '#59A14F', '#E15759', '#76B7B2', '#EDC948']

# ── 图5a（热图网格）配置 ──────────────────────────────────────────────────────
FIG5A_CONFIG = {
    'show_title':     True,
    'suptitle':       'Fig. 5a — Resource Allocation per Task  (SC matrix)',
    'ncols':          5,         # 每行子图数（None → 自动 ceil(sqrt(M))）
    'subplot_w':      2.6,       # 每个子图宽度（inch）
    'subplot_h':      2.2,       # 每个子图高度（inch）
    'cmap':           'Blues',   # 热图颜色映射
    'shared_vmax':    True,      # True = 所有子图共享同一颜色上限，便于跨任务比较
    'show_colorbar':  True,      # 是否显示统一 colorbar
    'xlabel':         'Resource',
    'ylabel':         'Agent',
    'cell_annot':     False,     # True = 在每格写数值（N、K 较小时好看）
    'cell_fontsize':  7,
    'subplot_title_fontsize': 8, # 子图标题字号
    'tick_fontsize':  7,
}

# ── 图5b（甘特图）配置 ────────────────────────────────────────────────────────
FIG5B_CONFIG = {
    'show_title':          True,
    'title':               'Fig. 5b — Agent Task Execution Gantt',
    'xlabel':              'Time',
    'ylabel':              'Agent',
    'bar_height':          0.55,  # 甘特条高度（0~1）
    'label_min_width':     8.0,   # 时间宽度大于此值才在条上显示 Task ID
    'show_task_id_label':  True,  # 是否在条上写任务 ID
    'label_fontsize':      7,
    'max_fig_width':       18.0,  # 图宽上限（inch）
    'min_fig_width':       8.0,   # 图宽下限（inch）
    'time_per_inch':       40.0,  # 每 inch 对应多少时间单位（自适应图宽用）
}

# ── 全局绘图参数 ──────────────────────────────────────────────────────────────
FIG5C_CONFIG = {
    'show_title': True,
    'title': 'Fig. 5c - Total Allocated Resource per Task',
    'xlabel': 'Resource',
    'ylabel': 'Task',
    'cmap': 'YlGnBu',
    'annot': True,
    'value_fmt': '{:.0f}',
}

FIG5D_CONFIG = {
    'show_title': True,
    'title': 'Fig. 5d - Allocated Minus Demand per Task',
    'xlabel': 'Resource',
    'ylabel': 'Task',
    'cmap': 'RdBu_r',
    'annot': True,
    'value_fmt': '{:+.0f}',
}

FIG5E_CONFIG = {
    'show_title': True,
    'title': 'Fig. 5e - Allocation-to-Demand Ratio per Task',
    'xlabel': 'Resource',
    'ylabel': 'Task',
    'cmap': 'RdYlGn',
    'annot': True,
    'value_fmt': '{:.0%}',
    'nan_text': '',
}

FIG5F_CONFIG = {
    'show_title': True,
    'title': 'Fig. 5f - True Resource Demand per Task',
    'xlabel': 'Resource',
    'ylabel': 'Task',
    'cmap': 'Oranges',
    'annot': True,
    'value_fmt': '{:.0f}',
}

PLOT_GLOBAL = {
    'title_fontsize':     12,
    'title_pad':           8,
    'xlabel_fontsize':    11,
    'ylabel_fontsize':    11,
    'tick_fontsize':      10,
    'legend_fontsize':     9,

    'show_grid':          True,
    'grid_linestyle':     '--',
    'grid_linewidth':     0.5,
    'grid_alpha':         0.35,

    'show_legend':        True,
    'legend_framealpha':  0.85,
    'legend_edgecolor':   '#cccccc',

    'hide_top_spine':     True,
    'hide_right_spine':   True,

    'save_dpi':           150,
    'save_bbox_inches':   'tight',
}

os.makedirs(FIGURES_DIR, exist_ok=True)

PLOT_STYLE_ADAPTER = dict(PLOT_GLOBAL)
PLOT_STYLE_ADAPTER['show_grid'] = False
PLOT_STYLE_ADAPTER['show_legend'] = False
STYLE_HELPER = PlotStyleHelper(PLOT_STYLE_ADAPTER, FIGURES_DIR)


# ══════════════════════════════════════════════════════════════════════════════
# 工具函数
# ══════════════════════════════════════════════════════════════════════════════

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


def apply_common_style(ax, xlabel, ylabel, title=None):
    STYLE_HELPER.apply_common_style(ax, xlabel=xlabel, ylabel=ylabel, title=title)


def finalize_and_save(fig, save_path):
    STYLE_HELPER.finalize_and_save(fig, save_path)


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

    M = max(len(ids), len(degrees), M_hint)
    # 补齐长度
    def pad(lst, length, fill=0.0):
        return lst + [fill] * (length - len(lst))

    ids    = pad(ids,    M, fill=0.0)
    types  = pad(types,  M, fill=0.0)
    values = pad(values, M, fill=0.0)
    if len(degrees) < M:
        degrees = np.concatenate([degrees, np.full(M - len(degrees), np.nan)])

    return {'id': ids, 'type': types, 'value': values, 'degree': degrees, 'M': M}


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
        t_fly     = to_scalar(get_agent_field(timing_raw, 't_fly_total',  i), default=0.0)
        t_wait    = to_scalar(get_agent_field(timing_raw, 't_wait_total', i), default=0.0)
        t_exec    = to_scalar(get_agent_field(timing_raw, 't_exec_total', i), default=0.0)

        L = min(len(task_seq), len(starts), len(execs))
        result.append({
            'task_seq': task_seq[:L],
            'starts':   starts[:L],
            'execs':    execs[:L],
            't_fly':    t_fly,
            't_wait':   t_wait,
            't_exec':   t_exec,
        })
    return result


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


def plot_task_resource_heatmap(matrix, save_path, cfg, colorbar_label,
                               center_value=None, vmin=None, vmax=None):
    if matrix.size == 0:
        print(f"  ! {os.path.basename(save_path)} 鏁版嵁涓虹┖锛岃烦杩?")
        return

    M, K = matrix.shape
    fig_w = max(6.5, 1.0 + 0.9 * K)
    fig_h = max(4.2, 1.2 + 0.5 * M)
    fig, ax = plt.subplots(figsize=(fig_w, fig_h))
    finite_vals = matrix[np.isfinite(matrix)]
    cmap = plt.get_cmap(cfg['cmap']).copy()
    cmap.set_bad('#f2f2f2')

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

    if cfg.get('annot', False):
        for m in range(M):
            for k in range(K):
                val = matrix[m, k]
                if not np.isfinite(val):
                    nan_text = cfg.get('nan_text', '')
                    if nan_text:
                        ax.text(k, m, nan_text,
                                ha='center', va='center',
                                fontsize=max(PLOT_GLOBAL['tick_fontsize'] - 1, 8),
                                color='#666666')
                    continue
                rgba = im.cmap(im.norm(val))
                luminance = 0.299 * rgba[0] + 0.587 * rgba[1] + 0.114 * rgba[2]
                text_color = 'black' if luminance > 0.6 else 'white'
                ax.text(k, m, cfg['value_fmt'].format(val),
                        ha='center', va='center',
                        fontsize=max(PLOT_GLOBAL['tick_fontsize'] - 1, 8),
                        color=text_color)

    ax.set_xticks(range(K))
    ax.set_xticklabels([f'R{k+1}' for k in range(K)], fontsize=PLOT_GLOBAL['tick_fontsize'])
    ax.set_yticks(range(M))
    ax.set_yticklabels([f'T{m+1}' for m in range(M)], fontsize=PLOT_GLOBAL['tick_fontsize'])
    apply_common_style(ax, cfg['xlabel'], cfg['ylabel'],
                       title=cfg['title'] if cfg.get('show_title', True) else None)

    cbar = fig.colorbar(im, ax=ax, fraction=0.045, pad=0.02)
    cbar.set_label(colorbar_label, fontsize=PLOT_GLOBAL['tick_fontsize'])
    cbar.ax.tick_params(labelsize=PLOT_GLOBAL['tick_fontsize'] - 1)

    fig.tight_layout()
    finalize_and_save(fig, save_path)


def plot_fig5e_stacked_compare(alloc_mat, demand_mat, task_info, save_path):
    ratio_mat = build_fulfillment_ratio_matrix(alloc_mat, demand_mat)
    return plot_fig5e_ratio_heatmap(ratio_mat, save_path)

    cfg = FIG5E_CONFIG
    if alloc_mat.size == 0 or demand_mat.size == 0:
        print("  ! fig5e 鏁版嵁涓虹┖锛岃烦杩?")
        return

    M = min(alloc_mat.shape[0], demand_mat.shape[0], task_info.get('M', alloc_mat.shape[0]))
    K = min(alloc_mat.shape[1], demand_mat.shape[1])
    if M == 0 or K == 0:
        print("  ! fig5e 鏁版嵁缁村害鏃犳晥锛岃烦杩?")
        return

    x = np.arange(M, dtype=float)
    width = cfg['bar_width']
    fig_w = max(8.0, min(16.0, 2.8 + 0.8 * M))
    fig_h = 5.2
    fig, ax = plt.subplots(figsize=(fig_w, fig_h))

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
            edgecolor='white',
            linewidth=0.6,
            hatch=cfg['hatch_demand'],
            label=label,
        )
        ax.bar(
            x + width / 2,
            alloc_mat[:M, k],
            width,
            bottom=bottom_alloc,
            color=color,
            edgecolor='white',
            linewidth=0.6,
            hatch=cfg['hatch_alloc'],
        )
        bottom_demand += demand_mat[:M, k]
        bottom_alloc += alloc_mat[:M, k]
        resource_handles.append(bars_d[0])

    if cfg.get('show_completion_text', False):
        degrees = task_info.get('degree', np.full(M, np.nan))
        y_top = np.maximum(bottom_demand, bottom_alloc)
        offset = max(np.nanmax(y_top) * 0.02, 0.4)
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
                color='#333333',
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
        mpatches.Patch(facecolor='white', edgecolor='#666666', hatch=cfg['hatch_demand'], label='Demand'),
        mpatches.Patch(facecolor='#666666', edgecolor='#666666', hatch=cfg['hatch_alloc'], label='Allocated'),
    ]

    legend1 = ax.legend(
        handles=role_handles,
        fontsize=PLOT_GLOBAL['legend_fontsize'],
        framealpha=PLOT_GLOBAL['legend_framealpha'],
        edgecolor=PLOT_GLOBAL['legend_edgecolor'],
        loc='upper left',
        title='Bar type',
    )
    ax.add_artist(legend1)
    ax.legend(
        handles=resource_handles,
        fontsize=PLOT_GLOBAL['legend_fontsize'],
        framealpha=PLOT_GLOBAL['legend_framealpha'],
        edgecolor=PLOT_GLOBAL['legend_edgecolor'],
        loc='upper right',
        title='Resource',
        ncols=min(K, 3),
    )

    fig.tight_layout()
    finalize_and_save(fig, save_path)


# ══════════════════════════════════════════════════════════════════════════════
# 绘图函数
# ══════════════════════════════════════════════════════════════════════════════

def plot_fig5e_ratio_heatmap(ratio_mat, save_path):
    plot_task_resource_heatmap(
        ratio_mat,
        save_path,
        FIG5E_CONFIG,
        colorbar_label='Allocated / Demand',
        center_value=1.0,
        vmin=0.0,
        vmax=1.5,
    )


def plot_fig5a(sc_list, task_info, N, K, save_path):
    """
    图5a：M 个任务资源分配矩阵热图网格。
    每个子图 = 一个任务的 SC{m}，[N×K] 热图，共享 colorbar 颜色上限。
    """
    cfg = FIG5A_CONFIG
    M   = len(sc_list)
    if M == 0:
        print("  ! final_SC 为空，跳过图5a")
        return

    ncols = cfg['ncols'] or max(1, int(np.ceil(np.sqrt(M))))
    ncols = min(ncols, M)
    nrows = int(np.ceil(M / ncols))

    fig_w = ncols * cfg['subplot_w'] + (1.0 if cfg['show_colorbar'] else 0.2)
    fig_h = nrows * cfg['subplot_h']
    fig, axes = plt.subplots(nrows, ncols, figsize=(fig_w, fig_h))
    axes = np.array(axes).reshape(nrows, ncols)

    # 决定共享 vmax
    if cfg['shared_vmax']:
        vmax_vals = [sc.max() for sc in sc_list if sc.size > 0 and sc.max() > 0]
        vmax = max(vmax_vals) if vmax_vals else 1.0
    else:
        vmax = None

    ims = []
    for m in range(M):
        row, col = divmod(m, ncols)
        ax = axes[row, col]
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
                                color='white' if v > (vmax or 1) * 0.6 else 'black')

        # 子图标题（颜色与任务类型对应）
        task_type = int(round(task_info['type'][m])) if m < len(task_info['type']) else 0
        task_val  = task_info['value'][m]              if m < len(task_info['value']) else 0
        deg       = task_info['degree'][m]              if m < len(task_info['degree']) else np.nan
        deg_str   = f'{deg*100:.0f}%' if not np.isnan(deg) else '?'
        t_color   = TASK_TYPE_COLOR.get(task_type, '#333333')
        ax.set_title(f'T{m+1}  type={task_type}  v={task_val:.0f}  d={deg_str}',
                     fontsize=cfg['subplot_title_fontsize'], color=t_color, pad=3)

        # 轴刻度
        ax.set_xticks(range(cur_K))
        ax.set_xticklabels([f'R{k+1}' for k in range(cur_K)],
                           fontsize=cfg['tick_fontsize'])
        ax.set_yticks(range(cur_N))
        ax.set_yticklabels([f'A{n+1}' for n in range(cur_N)],
                           fontsize=cfg['tick_fontsize'])
        if row == nrows - 1:
            ax.set_xlabel(cfg['xlabel'], fontsize=cfg['tick_fontsize'])
        if col == 0:
            ax.set_ylabel(cfg['ylabel'], fontsize=cfg['tick_fontsize'])

    # 隐藏多余子图
    for m in range(M, nrows * ncols):
        row, col = divmod(m, ncols)
        axes[row, col].set_visible(False)

    # 统一 colorbar
    if cfg['show_colorbar'] and ims:
        fig.subplots_adjust(right=0.87, hspace=0.55, wspace=0.35)
        cbar_ax = fig.add_axes([0.89, 0.15, 0.025, 0.70])
        norm = Normalize(vmin=0, vmax=vmax if vmax else 1)
        sm   = ScalarMappable(cmap=cfg['cmap'], norm=norm)
        sm.set_array([])
        cb = fig.colorbar(sm, cax=cbar_ax)
        cb.set_label('Allocated resource', fontsize=PLOT_GLOBAL['tick_fontsize'])
        cb.ax.tick_params(labelsize=PLOT_GLOBAL['tick_fontsize'] - 1)
    else:
        fig.tight_layout()

    if cfg['show_title']:
        fig.suptitle(cfg['suptitle'],
                     fontsize=PLOT_GLOBAL['title_fontsize'] + 1, y=1.02)

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

    fig_w = np.clip(t_max / cfg['time_per_inch'], cfg['min_fig_width'], cfg['max_fig_width'])
    fig_h = max(3.5, N * 0.55 + 1.0)
    fig, ax = plt.subplots(figsize=(fig_w, fig_h))

    # task_id → type 映射
    task_type_map = {}
    for m in range(task_info['M']):
        tid = int(round(task_info['id'][m]))
        task_type_map[tid] = int(round(task_info['type'][m]))

    used_types = set()
    for i, ag in enumerate(timing_list):
        y = N - 1 - i    # 智能体 1 在最顶行
        for task_id, start, dur in zip(ag['task_seq'], ag['starts'], ag['execs']):
            t_type  = task_type_map.get(task_id, 0)
            color   = TASK_TYPE_COLOR.get(t_type, DEFAULT_TASK_COLOR)
            used_types.add(t_type)

            ax.barh(y, dur, left=start, height=bar_h,
                    color=color, edgecolor='white', linewidth=0.5,
                    align='center', zorder=2)

            if cfg['show_task_id_label'] and dur >= cfg['label_min_width']:
                ax.text(start + dur / 2, y, f'T{task_id}',
                        ha='center', va='center',
                        fontsize=cfg['label_fontsize'],
                        color='white', fontweight='bold', zorder=3)

    # y 轴：智能体标签（从上到下 A1→AN）
    ax.set_yticks(range(N))
    ax.set_yticklabels([f'Agent {N - i}' for i in range(N)],
                       fontsize=PLOT_GLOBAL['tick_fontsize'])
    ax.set_ylim(-0.8, N - 0.2)
    ax.set_xlim(0, t_max * 1.03)

    # 纵向网格线（方便读时间）
    if PLOT_GLOBAL['show_grid']:
        ax.xaxis.grid(True, linestyle=PLOT_GLOBAL['grid_linestyle'],
                      linewidth=PLOT_GLOBAL['grid_linewidth'],
                      alpha=PLOT_GLOBAL['grid_alpha'], zorder=0)
    ax.set_axisbelow(True)

    # 图例：任务类型
    if PLOT_GLOBAL['show_legend']:
        patches = [
            mpatches.Patch(
                color=TASK_TYPE_COLOR.get(t, DEFAULT_TASK_COLOR),
                label=TASK_TYPE_LABEL.get(t, f'Type {t}')
            )
            for t in sorted(used_types)
        ]
        if patches:
            ax.legend(handles=patches,
                      fontsize=PLOT_GLOBAL['legend_fontsize'],
                      framealpha=PLOT_GLOBAL['legend_framealpha'],
                      edgecolor=PLOT_GLOBAL['legend_edgecolor'],
                      loc='lower right')

    apply_common_style(ax, cfg['xlabel'], cfg['ylabel'],
                       title=cfg['title'] if cfg['show_title'] else None)

    fig.tight_layout()
    finalize_and_save(fig, save_path)


# ══════════════════════════════════════════════════════════════════════════════
# 主程序
# ══════════════════════════════════════════════════════════════════════════════

def main():
    mat_path = find_mat_file(sys.argv)

    print("\n加载数据...")
    raw      = mat73.loadmat(mat_path)
    viz_data = raw.get('viz_data', raw)

    N    = to_int(viz_data.get('N'),    default=0)
    M    = to_int(viz_data.get('M'),    default=0)
    K    = to_int(viz_data.get('K'),    default=0)
    seed = to_int(viz_data.get('seed'), default=0)

    print(f"  N={N}  M={M}  K={K}  seed={seed}")
    print(f"  coalition_utility     = {to_scalar(viz_data.get('coalition_utility')):.2f}")
    print(f"  total_completed_value = {to_scalar(viz_data.get('total_completed_value')):.2f}")
    print(f"  computation_time      = {to_scalar(viz_data.get('computation_time')):.2f} s")

    basename = os.path.splitext(os.path.basename(mat_path))[0]
    parts    = basename.split('_')
    ts       = '_'.join(parts[-2:]) if len(parts) >= 2 else 'ts'

    print("\n提取数据...")
    sc_list     = extract_sc_matrices(viz_data)
    task_info   = extract_task_info(viz_data, M_hint=M)
    demand_mat  = extract_task_demand_matrix(viz_data, M_hint=M, K_hint=K)
    timing_list = extract_timing(viz_data, N)
    alloc_mat   = build_total_allocation_matrix(sc_list, K_hint=K)
    gap_mat     = alloc_mat - demand_mat
    ratio_mat   = build_fulfillment_ratio_matrix(alloc_mat, demand_mat)

    print(f"  final_SC: {len(sc_list)} 个任务矩阵")
    active_sc = sum(1 for sc in sc_list if sc.max() > 1e-9)
    print(f"           其中 {active_sc} 个有联盟分配")
    active_agents = sum(1 for ag in timing_list if len(ag['task_seq']) > 0)
    print(f"  timing:   {len(timing_list)} 个智能体，其中 {active_agents} 个有任务分配")

    print(f"\n绘图 → {FIGURES_DIR}")

    plot_fig5a(
        sc_list, task_info, N, K,
        os.path.join(FIGURES_DIR, f'fig5a_alloc_N{N}_M{M}_seed{seed}_{ts}.png'),
    )
    plot_fig5b(
        timing_list, task_info, N,
        os.path.join(FIGURES_DIR, f'fig5b_gantt_N{N}_M{M}_seed{seed}_{ts}.png'),
    )
    plot_task_resource_heatmap(
        alloc_mat,
        os.path.join(FIGURES_DIR, f'fig5c_allocsum_N{N}_M{M}_seed{seed}_{ts}.png'),
        FIG5C_CONFIG,
        colorbar_label='Total allocated resource',
    )
    plot_task_resource_heatmap(
        gap_mat,
        os.path.join(FIGURES_DIR, f'fig5d_gap_N{N}_M{M}_seed{seed}_{ts}.png'),
        FIG5D_CONFIG,
        colorbar_label='Allocated - Demand',
        center_value=0.0,
    )
    plot_fig5e_ratio_heatmap(
        ratio_mat,
        os.path.join(FIGURES_DIR, f'fig5e_ratio_N{N}_M{M}_seed{seed}_{ts}.png'),
    )
    plot_task_resource_heatmap(
        demand_mat,
        os.path.join(FIGURES_DIR, f'fig5f_demand_N{N}_M{M}_seed{seed}_{ts}.png'),
        FIG5F_CONFIG,
        colorbar_label='Task demand',
    )

    print("\n完成。图窗已弹出，关闭后程序退出。")
    plt.show()


if __name__ == '__main__':
    main()
