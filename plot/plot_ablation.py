"""
plot_ablation.py
================
从 Batch_Ablation.m 生成的 .mat 文件绘制消融实验散点图：

  图版式：2行 × len(N_VALUES) 列
    第1行：最终联盟效用 (Coalition Utility)
    第2行：平均任务完成率 (Task Completion Rate)

  每个子图：
    横坐标 = 随机种子（seed 值作为刻度标签）
    每个 x 位置两个点：belief_on（蓝圆）和 belief_off（红叉），灰线连接

依赖:
  pip install h5py numpy matplotlib
  （mat73 不需要，直接用 h5py 绕过其 cell-array-of-structs 解析 bug）

用法:
  python plot_ablation.py                        # 自动搜索最新 .mat
  python plot_ablation.py path/to/ablation.mat   # 指定文件
"""

import os
import sys
import glob
import numpy as np
import matplotlib.pyplot as plt
import matplotlib.lines as mlines
from plot_style_helper import PlotStyleHelper
import h5py 

try:
    import h5py
except ImportError:
    sys.exit("缺少依赖，请先执行: pip install h5py")

# ══════════════════════════════════════════════════════════════════════════════
# 顶部可调参数区
# ══════════════════════════════════════════════════════════════════════════════

SCRIPT_DIR  = os.path.dirname(os.path.abspath(__file__))
ROOT_DIR    = os.path.dirname(SCRIPT_DIR)
FIGURES_DIR = os.path.join(ROOT_DIR, 'figures', 'paper')
SEARCH_DIRS = [
    os.path.join(ROOT_DIR, 'results', 'batch', 'ablation'),
    os.path.join(ROOT_DIR, 'results', 'batch'),
]

# ── 散点样式 ──────────────────────────────────────────────────────────────────
STYLE_ON = dict(
    color='#2E6DB4',   # 蓝
    marker='o',
    markersize=8,
    label='belief_on',
    zorder=4,
)
STYLE_OFF = dict(
    color='#C0392B',   # 红
    marker='x',
    markersize=9,
    markeredgewidth=2.0,
    label='belief_off',
    zorder=4,
)
CONN_LINE = dict(color='#AAAAAA', linewidth=0.9, zorder=2)

# ── 行标题 / 坐标轴标签 ───────────────────────────────────────────────────────
ROW_YLABELS = ['Coalition Utility', 'Task Completion Rate']
ROW_TITLES  = ['最终联盟效用', '平均任务完成率']

# ── 全局绘图参数 ──────────────────────────────────────────────────────────────
PLOT_GLOBAL = {
    'subplot_w':        3.4,
    'subplot_h':        3.2,
    'xlabel_fontsize':  10,
    'ylabel_fontsize':  10,
    'title_fontsize':   11,
    'tick_fontsize':    9,
    'legend_fontsize':  9,
    'show_grid':        True,
    'grid_alpha':       0.35,
    'grid_ls':          '--',
    'hide_top_spine':   True,
    'hide_right_spine': True,
    'save_dpi':         150,
}
PLOT_GLOBAL_ADAPTER = {
    'xlabel_fontsize': PLOT_GLOBAL['xlabel_fontsize'],
    'ylabel_fontsize': PLOT_GLOBAL['ylabel_fontsize'],
    'title_fontsize': PLOT_GLOBAL['title_fontsize'],
    'title_fontweight': 'bold',
    'tick_fontsize': PLOT_GLOBAL['tick_fontsize'],
    'show_grid': PLOT_GLOBAL['show_grid'],
    'grid_linestyle': PLOT_GLOBAL['grid_ls'],
    'grid_alpha': PLOT_GLOBAL['grid_alpha'],
    'show_legend': False,
    'hide_top_spine': PLOT_GLOBAL['hide_top_spine'],
    'hide_right_spine': PLOT_GLOBAL['hide_right_spine'],
    'save_dpi': PLOT_GLOBAL['save_dpi'],
    'save_bbox_inches': 'tight',
    'tight_layout': True,
}
STYLE_HELPER = PlotStyleHelper(PLOT_GLOBAL_ADAPTER, FIGURES_DIR)

# ══════════════════════════════════════════════════════════════════════════════
# HDF5 加载（直接用 h5py，绕过 mat73 的 cell-array-of-structs 解析 bug）
# ══════════════════════════════════════════════════════════════════════════════

def _read_scalar(ds, f=None):
    """
    从 h5py Dataset 读取 float 标量。
    若值是 HDF5 对象引用（object ref），先解引用再读取。
    """
    if ds is None:
        return np.nan
    val = ds[()]
    # 对象引用：再解一层
    if isinstance(val, np.ndarray) and val.dtype.kind == 'O':
        if f is None or val.size == 0:
            return np.nan
        try:
            val = f[val.flat[0]][()]
        except Exception:
            return np.nan
    try:
        return float(np.asarray(val, dtype=float).ravel()[0])
    except Exception:
        return np.nan


def _read_1d(ds, f=None):
    """从 h5py Dataset 读取 1D float array（含对象引用解包）。"""
    if ds is None:
        return np.array([])
    val = ds[()]
    if isinstance(val, np.ndarray) and val.dtype.kind == 'O':
        if f is None or val.size == 0:
            return np.array([])
        try:
            val = f[val.flat[0]][()]
        except Exception:
            return np.array([])
    return np.asarray(val, dtype=float).ravel()


def load_ablation_h5py(mat_path):
    """
    用 h5py 直接解析 MATLAB v7.3 (.mat) 中的 ablation_results cell array。

    MATLAB cell array 在 HDF5 中存储为对象引用数组，维度顺序是 Fortran（列优先）：
      MATLAB shape (num_N, num_seeds, num_cond=2)
      → HDF5 shape  (2, num_seeds, num_N)
    每个引用指向一个 HDF5 Group（对应 MATLAB struct entry）。

    返回:
      n_values   : list[int]
      seeds      : list[int]
      utility    : np.ndarray  (num_N, num_seeds, 2)
      completion : np.ndarray  (num_N, num_seeds, 2)
    """
    with h5py.File(mat_path, 'r') as f:
        # ── 1. 读取 config ─────────────────────────────────────────────────
        cfg = f['ablation_config']
        n_values_arr = _read_1d(cfg.get('N_values'), f)
        seeds_arr    = _read_1d(cfg.get('seeds'),    f)

        num_N = int(n_values_arr.size)
        num_S = int(seeds_arr.size)
        n_values = [int(x) for x in n_values_arr]
        seeds    = [int(x) for x in seeds_arr]

        # ── 2. 读取 ablation_results cell array ───────────────────────────
        refs_ds   = f['ablation_results']
        hdf5_shape = refs_ds.shape   # (num_cond, num_seeds, num_N) Fortran 顺序
        print(f"  ablation_results HDF5 shape = {hdf5_shape}  "
              f"(期望 ({2}, {num_S}, {num_N}))")

        utility    = np.full((num_N, num_S, 2), np.nan)
        completion = np.full((num_N, num_S, 2), np.nan)

        for hdf5_idx in np.ndindex(hdf5_shape):
            # HDF5 Fortran 顺序 → MATLAB 顺序：反转下标
            # hdf5_idx = (ci, si, ni)  →  MATLAB idx = (ni, si, ci)
            rev = tuple(reversed(hdf5_idx))
            if len(rev) != 3:
                continue
            ni, si, ci = rev
            if ni >= num_N or si >= num_S or ci >= 2:
                continue

            ref = refs_ds[hdf5_idx]
            try:
                entry = f[ref]
            except Exception:
                continue
            if not isinstance(entry, h5py.Group):
                continue

            # success 字段
            succ = _read_scalar(entry.get('success'), f)
            if succ != 1.0:
                continue

            utility[ni, si, ci]    = _read_scalar(entry.get('final_utility'),         f)
            completion[ni, si, ci] = _read_scalar(entry.get('final_task_completion'),  f)

    return n_values, seeds, utility, completion


# ══════════════════════════════════════════════════════════════════════════════
# 查找文件
# ══════════════════════════════════════════════════════════════════════════════

def find_mat_file(argv):
    if len(argv) > 1:
        p = argv[1]
        if os.path.isfile(p):
            return p
        print(f"警告: 指定文件不存在 '{p}'，尝试自动搜索。")

    candidates = []
    for d in SEARCH_DIRS:
        candidates.extend(glob.glob(os.path.join(d, '*.mat')))

    ablation = [f for f in candidates
                if 'ablation' in os.path.basename(f).lower()
                or os.path.join('ablation', '') in f.replace('\\', '/')]
    pool = ablation if ablation else candidates
    if not pool:
        sys.exit("找不到 .mat 文件，请先运行 Batch_Ablation.m，或手动指定路径。")

    chosen = max(pool, key=os.path.getmtime)
    print(f"自动选择: {chosen}")
    return chosen


# ══════════════════════════════════════════════════════════════════════════════
# 绘图
# ══════════════════════════════════════════════════════════════════════════════

def plot_ablation_scatter(n_values, seeds, utility, completion, save_path):
    num_N   = len(n_values)
    num_S   = len(seeds)
    x_ticks  = np.arange(1, num_S + 1)
    x_labels = [str(s) for s in seeds]

    pg = PLOT_GLOBAL
    fig_w = pg['subplot_w'] * num_N
    fig_h = pg['subplot_h'] * 2
    fig, axes = plt.subplots(2, num_N, figsize=(fig_w, fig_h), squeeze=False)

    for row, (data, ylabel) in enumerate(zip(
            [utility, completion], ROW_YLABELS)):

        for col in range(num_N):
            ax = axes[row][col]

            # 灰线：连接同 seed 的两个条件
            for si in range(num_S):
                y_on  = data[col, si, 0]
                y_off = data[col, si, 1]
                if not (np.isnan(y_on) or np.isnan(y_off)):
                    ax.plot([x_ticks[si], x_ticks[si]], [y_on, y_off],
                            **CONN_LINE)

            # belief_on（蓝圆）
            y_on  = data[col, :, 0]
            valid = ~np.isnan(y_on)
            ax.plot(x_ticks[valid], y_on[valid],
                    marker=STYLE_ON['marker'],
                    color=STYLE_ON['color'],
                    markersize=STYLE_ON['markersize'],
                    linestyle='none',
                    label=STYLE_ON['label'],
                    zorder=STYLE_ON['zorder'])

            # belief_off（红叉）
            y_off = data[col, :, 1]
            valid = ~np.isnan(y_off)
            ax.plot(x_ticks[valid], y_off[valid],
                    marker=STYLE_OFF['marker'],
                    color=STYLE_OFF['color'],
                    markersize=STYLE_OFF['markersize'],
                    markeredgewidth=STYLE_OFF['markeredgewidth'],
                    linestyle='none',
                    label=STYLE_OFF['label'],
                    zorder=STYLE_OFF['zorder'])

            ax.set_xticks(x_ticks)
            ax.set_xticklabels(x_labels, fontsize=pg['tick_fontsize'])
            ax.tick_params(axis='y', labelsize=pg['tick_fontsize'])
            STYLE_HELPER.apply_common_style(
                ax,
                xlabel='Seed',
                ylabel=ylabel,
                title=f'N = {n_values[col]}',
            )
            ax.set_xlim(0.5, num_S + 0.5)

    # 统一图例（右上角第1行最后一列）
    h_on  = mlines.Line2D([], [], color=STYLE_ON['color'],  marker='o',
                          markersize=8,  linestyle='none', label='belief_on')
    h_off = mlines.Line2D([], [], color=STYLE_OFF['color'], marker='x',
                          markersize=9,  markeredgewidth=2.0,
                          linestyle='none', label='belief_off')
    axes[0][-1].legend(handles=[h_on, h_off],
                       fontsize=pg['legend_fontsize'],
                       framealpha=0.85, edgecolor='#cccccc', loc='best')

    # 左侧行标题
    for row, title in enumerate(ROW_TITLES):
        axes[row][0].annotate(
            title, xy=(0, 0.5), xycoords='axes fraction',
            xytext=(-0.30, 0.5), textcoords='axes fraction',
            fontsize=9, fontweight='bold',
            rotation=90, va='center', ha='center',
            annotation_clip=False,
        )

    fig.suptitle('消融实验：信念更新机制对比  (belief_on ● vs belief_off ✕)',
                 fontsize=12, fontweight='bold', y=1.01)
    os.makedirs(os.path.dirname(save_path), exist_ok=True)
    STYLE_HELPER.finalize_and_save(fig, save_path)
    return fig


# ══════════════════════════════════════════════════════════════════════════════
# 主程序
# ══════════════════════════════════════════════════════════════════════════════

def main():
    mat_path = find_mat_file(sys.argv)

    print("\n加载数据（h5py 直接解析）...")
    n_values, seeds, utility, completion = load_ablation_h5py(mat_path)

    print(f"  N_values   = {n_values}")
    print(f"  seeds      = {seeds}")
    print(f"  utility    有效: on={int(np.sum(~np.isnan(utility[:,:,0])))} "
          f"off={int(np.sum(~np.isnan(utility[:,:,1])))}")
    print(f"  completion 有效: on={int(np.sum(~np.isnan(completion[:,:,0])))} "
          f"off={int(np.sum(~np.isnan(completion[:,:,1])))}")

    if np.all(np.isnan(completion)):
        print("\n⚠ 警告: 未找到 final_task_completion 字段（旧版 .mat 不含此字段）。")
        print("  任务完成率子图将为空。重新运行 Batch_Ablation.m 可修复。")

    basename = os.path.splitext(os.path.basename(mat_path))[0]
    parts    = basename.split('_')
    ts       = '_'.join(parts[-2:]) if len(parts) >= 2 else 'ts'

    save_path = os.path.join(FIGURES_DIR, f'ablation_scatter_{ts}.png')
    print(f"\n绘图 → {save_path}")
    plot_ablation_scatter(n_values, seeds, utility, completion, save_path)

    print("\n完成。")
    plt.show()


if __name__ == '__main__':
    main()
