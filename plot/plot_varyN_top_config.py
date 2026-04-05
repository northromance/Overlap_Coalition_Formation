"""
plot_varyN.py
=============
从 Batch_VaryN.m 生成的 .mat 文件绘制论文图：
  图1a  变N效用       (mean ± std 折线图，4算法)
  图1b  变N完成度     (mean ± std 折线图，4算法)
  图1c  变N总完成价值 (mean ± std 折线图，4算法)
  图1d  效用+完成率   (双Y轴柱状折线组合图，N=selected_n_values)
  图1e  总价值+完成率 (双Y轴柱状折线组合图，N=selected_n_values)
  图2c  效用收敛曲线  (对最大N，按种子平均)
  图3a  内循环轨迹    (OCF_SAtabu，current/best utility)

依赖:
  pip install mat73 numpy matplotlib scipy

用法:
  python plot_varyN_top_config.py                     # 自动搜索最新 .mat
  python plot_varyN_top_config.py path/to/varyN.mat   # 指定文件

说明:
  你可以直接在本文件最上方的“顶部可调参数区”中修改：
  - 图尺寸、线宽、字体、图例字号、输出 dpi
  - 每个图的标题、坐标轴名称、坐标范围、刻度
  - 是否显示网格、图例、标题
  - 图3a 内循环两条线的颜色、线型、阴影透明度
"""

import os
import sys
import glob
import copy
import json
import re
import numpy as np
import matplotlib.pyplot as plt
from datetime import datetime
from plot_style_helper import (
    PlotStyleHelper,
    build_results_figures_dir,
    cm_size_to_inch,
    infer_source_name,
)

try:
    import mat73
except ImportError:
    sys.exit("缺少依赖，请先执行: pip install mat73")


# ══════════════════════════════════════════════════════════════════════════════
# 顶部可调参数区（建议以后优先在这里改）
# ══════════════════════════════════════════════════════════════════════════════

# =========================
# 顶部可调绘图参数
# 建议优先在这里改尺寸、字体、图例和保存选项。
# =========================

# 路径配置
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))  # 当前脚本所在目录
ROOT_DIR = os.path.dirname(SCRIPT_DIR)  # 项目根目录
FIGURES_DIR = build_results_figures_dir(ROOT_DIR, 'varyN')  # 图片输出目录
SEARCH_DIRS = [
    os.path.join(ROOT_DIR, 'results', 'batch', 'varyN'),  # 优先搜索 varyN 实验结果目录
    os.path.join(ROOT_DIR, 'results', 'batch'),  # 兜底搜索通用 batch 目录
]

# 算法显示样式主配置
# 这里是本文件最核心的“调色板”：
# - fig1a / fig1b / fig1c 的折线样式直接读这里
# - fig1d / fig1e 的柱状图颜色也直接读这里
# - fig1d / fig1e 的右侧完成率折线默认也继承这里
# 因此通常只需要维护这一套参数即可。
#
# 字段说明：
# - color: 主颜色。普通折线用它，组合图柱子也用它。
# - marker: 点的形状，如 'o' 圆点、's' 方块、'^' 三角、'D' 菱形。
# - ls: 线型，如 '-' 实线、'--' 虚线、'-.' 点划线。
# - lw: 该算法自己的线宽；若设置了，会优先于 PLOT_GLOBAL['linewidth']。
# - ms: 该算法自己的 marker 大小；若设置了，会优先于 PLOT_GLOBAL['markersize']。
# - mfc: marker face color，点内部填充色；写成 'none' 就是空心。
# - mec: marker edge color，点边框颜色。
# - mew: marker edge width，点边框线宽。
# - label: 图例显示名称。
# 一句话理解：
# - color 控制线的主色；marker/mfc/mec/mew 控制点长什么样；lw/ms 控制线和点有多粗、多大。
#
# 常见调整：
# - 想统一换色：改各算法的 color / mfc / mec
# - 想把 OCF_SAtabu 从空心圆改成实心圆：把 mfc='none' 改成 mfc="#C92D2E"
# - 想让组合图和普通图完全统一：保持 COMBO_CHART_STYLE['line_style_by_alg'] 为空字典
# ALG_STYLE = {
#     'Huo2025': dict(color="#797979", marker='o', ls='-', label='Huo2025'),
#     'Qi2023': dict(color="#FFC570", marker='s', ls='--', label='Qi2023'),
#     'Shi2024': dict(color="#006AF4", marker='^', ls='--', label='Shi2024'),
#     'OCF_SAtabu': dict(color="#DA422A", marker='D', ls='-', label='Ours (OCF-SA)'),
#     # DA422A
# }

ALG_STYLE = {
    # 深灰：基线算法 1
    'Huo2025': dict(
        color="#9B9B9B",   # 主颜色：线条颜色；组合图柱子颜色默认也可复用它
        marker='o',        # 点形状：'o' 表示圆点
        ls='--',            # 线型：'-' 表示实线
        lw=1,              # 线宽：值越大，折线越粗
        ms=4.0,            # 点大小：值越大，marker 越大
        mfc="#9B9B9B",     # 点内部填充色（marker face color）
        mec="#9B9B9B",     # 点边框颜色（marker edge color）
        mew=1.2,           # 点边框线宽（marker edge width）
        label='Huo2025'    # 图例里显示的名称
    ),
    # 金黄：基线算法 2
    'Qi2023': dict(
        color="#A2DFF8",
        marker='s',
        ls='--',
      lw=1,
        ms=4.0,
        mfc="#A2DFF8",
        mec="#A2DFF8",
        mew=1.2,
        label='Qi2023'
    ),
    # 亮蓝：基线算法 3
    'Shi2024': dict(
        color="#9DABD2",
        marker='^',
        ls='-.',
      lw=1,
        ms=4.0,
        mfc="#9DABD2",
        mec="#9DABD2",
        mew=1.2,
        label='Shi2024'
    ),
    # 红色：本文方法；默认空心圆，便于与其余实心 marker 区分
    'OCF_SAtabu': dict(
        color="#555B9C",
        marker='o',          # 圆点；配合 mfc='none' 为空心，配合 mfc="#C92D2E" 为实心
        ls='-',
      lw=1,
        ms=4.0,
        mfc='none',          # 空心
        mec="#555B9C",       # 边框颜色
        mew=1.8,
        label='Ours (OCF-SA)'
    ),
}

# ALG_STYLE = {
#     'Huo2025': dict(color="#7F7F7F", marker='o', ls='-', label='Huo2025'),
#     'Qi2023': dict(color="#006AF4", marker='s', ls='-', label='Qi2023'),
#     'Shi2024': dict(color="#10E86E", marker='^', ls='-', label='Shi2024'),
#     'OCF_SAtabu': dict(color="#DA422A", marker='D', ls='-', label='Ours (OCF-SA)'),
#     # DA422A
# }


# ALG_STYLE = {
#     'Huo2025': dict(color="#4BA05C", marker='o', ls='-', label='Huo2025'),
#     'Qi2023': dict(color="#7EBBE2", marker='s', ls='--', label='Qi2023'),
#     'Shi2024': dict(color="#778AC1", marker='^', ls='-.', label='Shi2024'),
#     'OCF_SAtabu': dict(color="#DA422A", marker='D', ls='-', label='Ours (OCF-SA)'),
#     # DA422A
# }

# 未知算法或 mat 文件里出现了未在 ALG_STYLE 中声明的算法时，回退到这套默认样式。
# 一般不需要改；只有新增算法但暂时没做专门配色时，这里才会生效。
DEFAULT_STYLE = dict(
    color='#888888',
    marker='x',
    ls=':',
    lw=1.3,
    ms=4.0,
    mfc='#888888',
    mec='#888888',
    mew=0.8,
    label='Unknown',
)  # 未知算法的兜底样式

# 全局绘图参数
# 所有物理尺寸统一使用 cm 配置，真正传给 Matplotlib 时再换算为英寸。
# 注意：
# - 这里的 linewidth / markersize / markeredgewidth 是“全局默认值”
# - 若某个算法在 ALG_STYLE 里写了 lw / ms / mew，则优先使用算法自己的设置
PLOT_GLOBAL = {
    'figsize_cm': (8.76, 6.48),  # 单张图尺寸（宽, 高），单位 cm
    'linewidth': 1.2,  # 主曲线线宽；IEEE 单栏图中保持清晰但不过粗
    'markersize': 3.2,  # marker 大小；保证缩放后仍可辨识
    'markeredgewidth': 0.9,  # marker 边框线宽
    'capsize': 2,  # 误差棒帽宽
    'show_errorbar_varyN': False,  # fig1a/fig1b/fig1c 是否显示 mean±std 误差棒
    'show_markers_fig2c': False,  # fig2c 是否显示 marker
    'show_markers_fig3a': False,  # fig3a 是否显示 marker
    'markevery_fig2c': None,  # fig2c 的 marker 抽样步长；None 表示全部点
    'markevery_fig3a': None,  # fig3a 的 marker 抽样步长；None 表示全部点
    'font_family': ['Times New Roman', 'SimSun', 'DejaVu Sans'],  # 全局字体候选顺序
    'font_style': 'normal',  # 字体样式：normal / italic / oblique
    'font_weight': 'normal',  # 全局默认字重：normal / bold
    'xlabel_fontsize': 8,  # x 轴标题字号；适合 IEEE 单栏插图
    'ylabel_fontsize': 8,  # y 轴标题字号；适合 IEEE 单栏插图
    'label_fontweight': 'normal',  # 坐标轴标题字重
    'show_titles': False,  # 全局标题总开关；False 时所有子图都不显示标题
    'title_fontsize': 8,  # 标题字号；当前标题默认关闭，仅保留统一配置
    'title_fontweight': 'bold',  # 标题字重
    'title_pad': 4,  # 标题与坐标轴之间的间距
    'tick_fontsize': 8,  # 刻度字号；保证在论文缩放后仍可读
    'tick_fontweight': 'normal',  # 刻度字重
    'legend_fontsize': 7,  # 图例字号；适合 IEEE 插图
    'legend_fontweight': 'normal',  # 图例字重
    'legend_loc': 'best',  # 图例位置
    'legend_bbox_to_anchor': None,  # 图例锚点；None 表示不额外指定
    'legend_ncol': 2,  # 图例列数
    'legend_borderaxespad': 0.2,  # 图例与坐标轴边界的间距
    'legend_handlelength': 1.6,  # 图例示意线长度
    'legend_labelspacing': 0.25,  # 图例条目垂直间距
    'show_grid': False,  # 是否显示网格
    'grid_linestyle': '--',  # 网格线型
    'grid_linewidth': 0.4,  # 网格线宽
    'grid_alpha': 0.22,  # 网格透明度
    'show_legend': False,  # 全局图例总开关
    'legend_framealpha': 0.92,  # 图例边框透明度
    'legend_edgecolor': '#cccccc',  # 图例边框颜色
    'hide_top_spine': False,  # 是否隐藏上边框
    'hide_right_spine': False,  # 是否隐藏右边框
    'save_format': 'eps',  # 主保存格式
    'save_formats': ['eps', 'png'],  # 实际输出格式列表
    'save_dpi': 300,  # 位图输出 dpi
    'save_bbox_inches': None,  # 关闭自动裁白边，保证所有图导出的外框尺寸一致
    'timestamp_first_in_name': True,  # True 表示时间戳放在文件名前面
    'tight_layout': False,  # 关闭自动紧凑布局，改为使用下面的固定边距
    'use_fixed_export_margins': True,  # 是否对所有图使用同一套固定边距
    'export_margin_left_cm': 1.62,  # 图片左边缘到绘图区左侧的保留距离，单位 cm；按五位数刻度和左侧 ylabel 预留
    'export_margin_right_cm': 0.98,  # 图片右边缘到绘图区右侧的保留距离，单位 cm；保证双Y轴图右侧副轴不拥挤
    'export_margin_bottom_cm': 1.02,  # 图片下边缘到绘图区下侧的保留距离，单位 cm；保证 x 轴标题和刻度留白一致
    'export_margin_top_cm': 0.30,  # 图片上边缘到绘图区上侧的保留距离，单位 cm；顶部留白适中，便于论文排版
}

# fig3a 内循环专用样式
# 这一块只影响图3a，不影响 fig1a~fig1e。
# 如果只想改内循环图的颜色，不要去改 ALG_STYLE，直接改这里。
INNER_LOOP_STYLE = {
    'current_label': 'Current Utility',  # 当前效用曲线的图例名称
    'current_color': '#4878CF',  # 当前效用曲线颜色
    'current_ls': '-',  # 当前效用曲线线型
    'current_marker': 'o',  # 当前效用曲线 marker，仅在 show_markers_fig3a=True 时生效
    'current_band_alpha': 0.15,  # 当前效用阴影带透明度
    'best_label': 'Best Utility',  # 最优效用曲线的图例名称
    'best_color': '#D65F5F',  # 最优效用曲线颜色
    'best_ls': '--',  # 最优效用曲线线型
    'best_marker': 's',  # 最优效用曲线 marker，仅在 show_markers_fig3a=True 时生效
    'best_band_alpha': 0.15,  # 最优效用阴影带透明度
    'round_label': 50,  # 标题里显示的 round 标签，不影响实际数据提取
}

# fig1d / fig1e 双Y轴组合图专用样式
# 这一块不是主配色板，它主要控制组合图的“局部外观”：
# - 柱子宽度、透明度
# - 误差棒颜色和粗细
# - 右侧完成率坐标轴范围
# - 图例位置
# - line_style_by_alg：仅在你想让组合图折线与 ALG_STYLE 不同时才填写
#
# 当前约定：
# - bar_style_by_alg 只影响 fig1d / fig1e 的柱状图
# - line_style_by_alg 只影响 fig1d / fig1e 的右侧完成率折线
# - 如果这里只写了 color，而没有单独写 mfc / mec，
#   则折线 marker 会默认与折线同色
COMBO_CHART_STYLE = {
    'selected_n_values': [4,  6, 8, 10, 12, 16],  # 组合图只画这些 N
    'bar_width': 0.22,  # 分组柱状图中单个算法柱子的实际宽度
    'use_bar_spacing': False ,  # 是否启用同组柱子之间的额外间距；False 时柱子按 bar_width 紧贴排列
    'bar_offset_step': 0.19,  # 同一组相邻柱子的中心间距；略大于 bar_width 时柱子之间会留一点空隙
    'bar_alpha': 0.8,  # 柱子透明度
    'show_bar_edge': False,  # 是否给每个柱子额外绘制外侧边框
    'bar_edgecolor': '#000000',  # 柱子外侧边框颜色
    'bar_edgewidth': 0.5,  # 柱子外侧边框线宽
    'errorbar_color': '#000000',  # 柱状图误差棒颜色；通常用黑色最清晰
    'errorbar_linewidth': 0.5,  # 柱状图误差棒线宽
    'errorbar_capthick': 0.3,  # 柱状图误差棒帽子线宽
    'completion_ylim': (0.2, 1.3),  # 右侧完成率坐标轴范围
    'completion_yticks': [0.2, 0.4, 0.6, 0.8, 1.0],  # 右侧完成率刻度
    'legend_loc': 'upper center',  # 组合图图例位置
    'legend_bbox_to_anchor': (0.5, 0.995),  # 组合图图例锚点，控制不越界
    'legend_ncol': 2,  # 组合图图例列数
    'bar_style_by_alg': {
        # 这里只控制 fig1d / fig1e 的柱状图；不再依赖 ALG_STYLE
        'Huo2025': {
            'color': '#606060',
            'label': 'Huo2025',
        },
        'Qi2023': {
            'color': '#EFAF2E',
            'label': 'Qi2023',
        },
        'Shi2024': {
            'color': '#195CF8',
            'label': 'Shi2024',
        },
        'OCF_SAtabu': {
            'color': '#C92D2E',
            'label': 'Ours (OCF-SA)',
        },
    },
    'line_style_by_alg': {
        # 这里只控制 fig1d / fig1e 的右侧完成率折线
        'Huo2025': {
            'color': "#7DBEE9",
            'marker': 'o',
            'ls': '-',
            'linewidth': 1.4,
            'markersize': 4.2,
            'markeredgewidth': 1.0,
        },
        'Qi2023': {
            'color': '#3091CB',
            'marker': 's',
            'ls': '--',
            'linewidth': 1.4,
            'markersize': 4.2,
            'markeredgewidth': 1.0,
        },
        'Shi2024': {
            'color': '#FDB385',
            'marker': '^',
            'ls': '-.',
            'linewidth': 1.4,
            'markersize': 4.2,
            'markeredgewidth': 1.0,
        },
        'OCF_SAtabu': {
            'color': '#CE692E',
            'marker': 'o',
            'ls': '-',
            'linewidth': 1.6,
            'markersize': 4.4,
            'mfc': 'none',
            'mec': '#C92D2E',
            'markeredgewidth': 1.2,
        },
    },
}

# 各子图单独控制
# - show_title: 当前图是否允许标题，仍受 PLOT_GLOBAL['show_titles'] 总开关控制
# - title / title_template: 固定标题或动态标题模板
# - xlim / ylim = None: 自动范围
# - xticks / yticks = None: 自动刻度
# - use_fixed_N_xticks = True: 强制使用 N_values 作为 x 轴刻度
# - bottom_zero = True: y 轴下界至少为 0
FIGURE_CONFIG = {
    'fig1a': {
        'show_title': True,
        'title': 'Fig. 1a - Utility vs. N',
        'xlabel': 'Number of Agents',
        'ylabel': 'Final Coalition Utility',
        'xlim': None,
        'ylim': None,
        'xticks': None,
        'yticks': None,
        'use_fixed_N_xticks': True,
        'bottom_zero': False,
    },
    'fig1b': {
        'show_title': True,
        'title': 'Fig. 1b - Completion vs. N',
        'xlabel': 'Number of Agents',
        'ylabel': 'Task Completion Degree',
        'xlim': None,
        'ylim': [0.15,1.05],
        'xticks': None,
        'yticks': None,
        'use_fixed_N_xticks': True,
        'bottom_zero': True,
    },
    'fig1c': {
        'show_title': True,
        'title': 'Fig. 1c - Total Completed Value vs. N',
        'xlabel': 'Number of Agents',
        'ylabel': 'Total Completed Value',
        'xlim': None,
        'ylim': [3000,12000],
        'xticks': None,
        'yticks': None,
        'use_fixed_N_xticks': True,
        'bottom_zero': True,
    },
    'fig1d': {
        'show_title': True,
        'title': 'Fig. 1d - Utility and Completion vs. N',
        'xlabel': 'Number of Agents',
        'ylabel': 'Final Coalition Utility',
        'right_ylabel': 'Completion Rate',
        'show_completion_line': False,
        'show_errorbar': True,
        'errorbar_mode': 'sem',
        'xlim': None,
        'ylim': None,
        'xticks': None,
        'yticks': None,
        'use_fixed_N_xticks': False,
        'bottom_zero': True,
    },
    'fig1e': {
        'show_title': True,
        'title': 'Fig. 1e - Total Completed Value and Completion vs. N',
        'xlabel': 'Number of Agents',
        'ylabel': 'Total Completed Value',
        'right_ylabel': 'Completion Rate',
        'show_completion_line': False,
        'show_errorbar': True,
        'errorbar_mode': 'sem',
        'xlim': None,
        'ylim': [2500,12000],
        'xticks': None,
        'yticks': None,
        'use_fixed_N_xticks': False,
        'bottom_zero': True,
    },
    'fig2c': {
        'show_title': True,
        'title_template': 'Fig. 2c - Convergence (N={n_target})',
        'xlabel': 'Round',
        'ylabel': 'Coalition Utility',
        'xlim': None,
        'ylim': None,
        'xticks': None,
        'yticks': None,
        'use_fixed_N_xticks': False,
        'bottom_zero': False,
    },
    'fig3a': {
        'show_title': True,
        'title_template': 'Fig. 3a - Inner Loop (Round {round_label}, N={n_target})',
        'xlabel': 'Inner Iteration',
        'ylabel': 'Utility',
        'xlim': None,
        'ylim': None,
        'xticks': None,
        'yticks': None,
        'use_fixed_N_xticks': False,
        'bottom_zero': False,
    },
}

os.makedirs(FIGURES_DIR, exist_ok=True)
STYLE_HELPER = PlotStyleHelper(PLOT_GLOBAL, FIGURES_DIR)

# ══════════════════════════════════════════════════════════════════════════════
# 工具函数
# ══════════════════════════════════════════════════════════════════════════════

def find_mat_file(argv):
    """优先命令行参数，否则在 SEARCH_DIRS 中找最新的 .mat 文件。"""
    if len(argv) > 1:
        p = argv[1]
        if os.path.isfile(p):
            return p
        print(f"警告: 指定的文件不存在 '{p}'，尝试自动搜索。")

    candidates = []
    for d in SEARCH_DIRS:
        candidates.extend(glob.glob(os.path.join(d, '*.mat')))

    varyN = [
        f for f in candidates
        if 'varyN' in os.path.basename(f) or os.path.basename(f).startswith('N')
    ]
    pool = varyN if varyN else candidates
    if not pool:
        sys.exit("找不到 .mat 文件，请先运行 Batch_VaryN.m，或手动指定路径作为命令行参数。")

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


def iter_results(results):
    """
    mat73 加载的 cell array 可能是 list-of-list 或 numpy object array。
    统一返回 (ni, si, entry_dict) 迭代器。
    """
    if isinstance(results, np.ndarray):
        rows, cols = results.shape
        for ni in range(rows):
            for si in range(cols):
                yield ni, si, results[ni, si]
    elif isinstance(results, list):
        for ni, row in enumerate(results):
            if isinstance(row, list):
                for si, entry in enumerate(row):
                    yield ni, si, entry
            else:
                yield ni, 0, row
    else:
        yield 0, 0, results


def get_shape(results):
    """返回 (nN, nS)。"""
    if isinstance(results, np.ndarray):
        return results.shape
    if isinstance(results, list):
        nN = len(results)
        nS = len(results[0]) if results and isinstance(results[0], list) else 1
        return nN, nS
    return 1, 1


def parse_alg_names(config):
    """从 config 中提取算法名列表。"""
    raw = config.get('alg_names', [])
    if isinstance(raw, str):
        return [raw]
    if isinstance(raw, np.ndarray):
        return list(raw.ravel())
    return list(raw)


def parse_N_values(config):
    return list(np.asarray(config['N_values'], dtype=int).ravel())


def merge_figure_config(fig_key, **kwargs):
    """复制并补充每个图的配置，避免运行中修改全局字典。"""
    cfg = copy.deepcopy(FIGURE_CONFIG[fig_key])
    cfg.update(kwargs)
    return cfg


def get_text_style(size_key, weight_key):
    """返回一组可复用的字体配置。"""
    return STYLE_HELPER.get_text_style(size_key, weight_key)


def apply_plot_rcparams():
    """设置 matplotlib 的全局字体默认值。"""
    STYLE_HELPER.apply_rcparams()


def get_marker_kwargs(show_markers, marker, markevery=None):
    """根据配置生成 marker 参数。"""
    return STYLE_HELPER.get_marker_kwargs(show_markers, marker, markevery)


def build_output_path(ts, stem):
    """按配置生成输出文件路径。"""
    _ = ts
    return STYLE_HELPER.build_output_stem(stem)


def extract_timestamp_tag(mat_path):
    """从结果文件名中提取时间戳；提取失败时回退到当前时间。"""
    basename = os.path.splitext(os.path.basename(mat_path))[0]
    match = re.search(r'(\d{8})_(\d{6})$', basename)
    if match:
        return f'{match.group(1)}_{match.group(2)}'
    return datetime.now().strftime('%Y%m%d_%H%M%S')


def apply_common_style(ax, cfg, title=None):
    """统一处理坐标轴标签、标题、网格、图例和边框。"""
    STYLE_HELPER.apply_common_style(ax, cfg=cfg, title=title)


def apply_axis_controls(ax, cfg, n_values=None):
    """统一处理 xlim / ylim / xticks / yticks / 底部从 0 开始等。"""
    STYLE_HELPER.apply_axis_controls(
        ax,
        cfg=cfg,
        fixed_values=n_values,
        fixed_locator_key='use_fixed_N_xticks',
    )


def finalize_and_save(fig, save_path):
    if PLOT_GLOBAL.get('use_fixed_export_margins', False):
        fig_width_cm = fig.get_figwidth() * 2.54
        fig_height_cm = fig.get_figheight() * 2.54

        left_margin_cm = float(PLOT_GLOBAL.get('export_margin_left_cm', 1.58))
        right_margin_cm = float(PLOT_GLOBAL.get('export_margin_right_cm', 1.23))
        bottom_margin_cm = float(PLOT_GLOBAL.get('export_margin_bottom_cm', 1.17))
        top_margin_cm = float(PLOT_GLOBAL.get('export_margin_top_cm', 0.26))

        if left_margin_cm + right_margin_cm >= fig_width_cm:
            raise ValueError(
                f"固定导出边距非法: 左右边距之和 {left_margin_cm + right_margin_cm:.3f} cm "
                f"必须小于图宽 {fig_width_cm:.3f} cm"
            )
        if bottom_margin_cm + top_margin_cm >= fig_height_cm:
            raise ValueError(
                f"固定导出边距非法: 上下边距之和 {bottom_margin_cm + top_margin_cm:.3f} cm "
                f"必须小于图高 {fig_height_cm:.3f} cm"
            )

        left = left_margin_cm / fig_width_cm
        right = 1.0 - right_margin_cm / fig_width_cm
        bottom = bottom_margin_cm / fig_height_cm
        top = 1.0 - top_margin_cm / fig_height_cm

        fig.subplots_adjust(
            left=left,
            right=right,
            bottom=bottom,
            top=top,
        )
    STYLE_HELPER.finalize_and_save(fig, save_path)


def configure_output_dir(mat_path):
    global FIGURES_DIR
    source_name = infer_source_name(mat_path, fallback='varyN')
    FIGURES_DIR = build_results_figures_dir(ROOT_DIR, 'varyN', source_name)
    os.makedirs(FIGURES_DIR, exist_ok=True)
    STYLE_HELPER.set_figures_dir(FIGURES_DIR)
    return FIGURES_DIR


def get_selected_n_indices(all_n_values, selected_n_values=None):
    """校验目标 N 子集是否存在，并按指定顺序返回索引。"""
    target_values = list(selected_n_values or COMBO_CHART_STYLE['selected_n_values'])
    index_map = {int(n): idx for idx, n in enumerate(all_n_values)}
    missing_values = [n for n in target_values if int(n) not in index_map]
    if missing_values:
        raise ValueError(
            '组合图所需的 N 值缺失: '
            f'{missing_values}；当前数据仅包含 {list(all_n_values)}'
        )
    return [index_map[int(n)] for n in target_values]


def apply_secondary_axis_style(ax, ylabel, ylim=None, yticks=None):
    """统一设置双Y轴右侧坐标轴样式。"""
    ax.set_ylabel(
        ylabel,
        **get_text_style('ylabel_fontsize', 'label_fontweight'),
    )

    if ylim is not None:
        ax.set_ylim(*ylim)
    if yticks is not None:
        ax.set_yticks(yticks)

    tick_fontsize = PLOT_GLOBAL.get('tick_fontsize')
    if tick_fontsize is not None:
        ax.tick_params(axis='y', labelsize=tick_fontsize)

    font_family = PLOT_GLOBAL.get('font_family')
    font_style = PLOT_GLOBAL.get('font_style')
    tick_fontweight = PLOT_GLOBAL.get('tick_fontweight')
    for tick in ax.get_yticklabels():
        if font_family:
            tick.set_fontfamily(font_family)
        if font_style:
            tick.set_fontstyle(font_style)
        if tick_fontweight:
            tick.set_fontweight(tick_fontweight)

    if PLOT_GLOBAL.get('hide_top_spine', False):
        ax.spines['top'].set_visible(False)
    ax.spines['right'].set_visible(True)


def json_safe_data(obj):
    """递归将 numpy / NaN 转成可安全写入 JSON 的 Python 对象。"""
    if isinstance(obj, dict):
        return {str(k): json_safe_data(v) for k, v in obj.items()}
    if isinstance(obj, (list, tuple)):
        return [json_safe_data(v) for v in obj]
    if isinstance(obj, np.ndarray):
        return [json_safe_data(v) for v in obj.tolist()]
    if isinstance(obj, np.bool_):
        return bool(obj)
    if isinstance(obj, np.integer):
        return int(obj)
    if isinstance(obj, np.floating):
        val = float(obj)
        return None if (np.isnan(val) or np.isinf(val)) else val
    if isinstance(obj, float):
        return None if (np.isnan(obj) or np.isinf(obj)) else obj
    return obj


def write_plot_data_json(output_path, payload):
    """将绘图数据导出为 JSON。"""
    with open(output_path, 'w', encoding='utf-8') as fp:
        json.dump(json_safe_data(payload), fp, ensure_ascii=False, indent=2)
    print(f"  [OK] {output_path}")


def get_alg_plot_style(aname):
    """读取算法折线样式，并支持 mfc/mec/lw/ms/mew。"""
    base = ALG_STYLE.get(aname, DEFAULT_STYLE)
    color = base.get('color', DEFAULT_STYLE['color'])
    return {
        'color': color,
        'marker': base.get('marker', DEFAULT_STYLE['marker']),
        'ls': base.get('ls', DEFAULT_STYLE['ls']),
        'linewidth': base.get('lw', PLOT_GLOBAL['linewidth']),
        'markersize': base.get('ms', PLOT_GLOBAL['markersize']),
        'markerfacecolor': base.get('mfc', color),
        'markeredgecolor': base.get('mec', color),
        'markeredgewidth': base.get('mew', PLOT_GLOBAL['markeredgewidth']),
        'label': base.get('label', aname),
    }


def build_completion_lookup(metrics, N_values, alg_names, selected_n_values):
    """按算法和 N 构建完成率均值查找表，用于组合图精简 JSON 兜底。"""
    selected_indices = get_selected_n_indices(N_values, selected_n_values)
    lookup = {}
    for aname in alg_names:
        completion_values = metrics[aname]['completion'][selected_indices, :]
        completion_mu = np.nanmean(completion_values, axis=1)
        lookup[aname] = {
            int(n_val): value
            for n_val, value in zip(selected_n_values, completion_mu)
        }
    return lookup


def build_combo_point_map(points, value_key, figure_name, aname, series_kind):
    """将组合图单条序列的点转换为按 N 索引的查找表。"""
    point_map = {}
    for point in points:
        if 'x_value' not in point:
            raise ValueError(
                f"{figure_name} 的 {aname} {series_kind} 序列缺少 x_value"
            )
        n_val = int(point['x_value'])
        if n_val in point_map:
            raise ValueError(
                f"{figure_name} 的 {aname} {series_kind} 序列存在重复 N={n_val}"
            )
        if value_key not in point:
            raise ValueError(
                f"{figure_name} 的 {aname} {series_kind} 序列缺少 {value_key}"
            )
        point_map[n_val] = point[value_key]
    return point_map


def build_combo_only_figure_data(
    figure_name,
    figure_data,
    alg_names,
    selected_n_values,
    left_metric,
    left_value_key,
    completion_lookup,
):
    """从组合图完整导出数据中提取精简版 JSON 结构。"""
    if not isinstance(figure_data, dict) or figure_data.get('status') != 'generated':
        raise ValueError(f'{figure_name} 未成功生成，无法导出精简 JSON')

    show_completion_line = bool(figure_data.get('show_completion_line', True))
    bar_series_by_alg = {}
    line_series_by_alg = {}

    for series in figure_data.get('series', []):
        aname = series.get('algorithm')
        if aname not in alg_names:
            continue
        kind = series.get('series_kind')
        if kind == 'bar':
            if aname in bar_series_by_alg:
                raise ValueError(f'{figure_name} 中算法 {aname} 存在重复 bar 序列')
            bar_series_by_alg[aname] = series
        elif kind == 'line':
            if aname in line_series_by_alg:
                raise ValueError(f'{figure_name} 中算法 {aname} 存在重复 line 序列')
            line_series_by_alg[aname] = series

    algorithms = {}
    for aname in alg_names:
        if aname not in bar_series_by_alg:
            raise ValueError(f'{figure_name} 缺少算法 {aname} 的 bar 数据')

        bar_points = build_combo_point_map(
            bar_series_by_alg[aname].get('points', []),
            value_key='mean',
            figure_name=figure_name,
            aname=aname,
            series_kind='bar',
        )

        if show_completion_line:
            if aname not in line_series_by_alg:
                raise ValueError(f'{figure_name} 缺少算法 {aname} 的 completion line 数据')
            completion_points = build_combo_point_map(
                line_series_by_alg[aname].get('points', []),
                value_key='value',
                figure_name=figure_name,
                aname=aname,
                series_kind='line',
            )
        else:
            completion_points = completion_lookup.get(aname, {})

        rows = []
        for n_val in selected_n_values:
            n_int = int(n_val)
            if n_int not in bar_points:
                raise ValueError(f'{figure_name} 的算法 {aname} 缺少 N={n_int} 的柱状值')
            if n_int not in completion_points:
                raise ValueError(f'{figure_name} 的算法 {aname} 缺少 N={n_int} 的完成率')
            rows.append({
                'N': n_int,
                left_value_key: bar_points[n_int],
                'completion_rate': completion_points[n_int],
            })
        algorithms[aname] = rows

    return {
        'left_metric': left_metric,
        'right_metric': 'Completion Rate',
        'algorithms': algorithms,
    }


def build_combo_only_payload(plot_data, N_values, alg_names, metrics):
    """构建仅包含 fig1d / fig1e 的精简 JSON。"""
    selected_n_values = list(plot_data.get('selected_n_values', COMBO_CHART_STYLE['selected_n_values']))
    completion_lookup = build_completion_lookup(
        metrics,
        N_values,
        alg_names,
        selected_n_values,
    )
    figures = plot_data.get('figures', {})
    return {
        'source_mat_path': plot_data.get('source_mat_path'),
        'output_dir': plot_data.get('output_dir'),
        'selected_n_values': selected_n_values,
        'alg_names': list(alg_names),
        'figures': {
            'fig1d_utility_completion_combo': build_combo_only_figure_data(
                'fig1d',
                figures.get('fig1d'),
                alg_names,
                selected_n_values,
                left_metric='Final Coalition Utility',
                left_value_key='utility_value',
                completion_lookup=completion_lookup,
            ),
            'fig1e_completed_value_completion_combo': build_combo_only_figure_data(
                'fig1e',
                figures.get('fig1e'),
                alg_names,
                selected_n_values,
                left_metric='Total Completed Value',
                left_value_key='completed_value',
                completion_lookup=completion_lookup,
            ),
        },
    }


def get_combo_line_style(aname):
    """读取组合图中某个算法的折线样式。"""
    base = get_alg_plot_style(aname)
    custom = COMBO_CHART_STYLE.get('line_style_by_alg', {}).get(aname, {})
    line_color = custom.get('color', base['color'])
    base_markerfacecolor = base['markerfacecolor']
    markerfacecolor = custom['mfc'] if 'mfc' in custom else (
        base_markerfacecolor
        if str(base_markerfacecolor).lower() == 'none'
        else (line_color if 'color' in custom else base_markerfacecolor)
    )
    markeredgecolor = custom['mec'] if 'mec' in custom else (
        line_color if 'color' in custom else base['markeredgecolor']
    )
    return {
        'color': line_color,
        'marker': custom.get('marker', base['marker']),
        'ls': custom.get('ls', base['ls']),
        'linewidth': custom.get('linewidth', base['linewidth']),
        'markersize': custom.get('markersize', base['markersize']),
        'markerfacecolor': markerfacecolor,
        'markeredgecolor': markeredgecolor,
        'markeredgewidth': custom.get('markeredgewidth', base['markeredgewidth']),
    }


def get_combo_bar_style(aname):
    """读取组合图中某个算法的柱状图样式。"""
    base = ALG_STYLE.get(aname, DEFAULT_STYLE)
    custom = COMBO_CHART_STYLE.get('bar_style_by_alg', {}).get(aname, {})
    return {
        'color': custom.get('color', base.get('color', DEFAULT_STYLE['color'])),
        'label': custom.get('label', base.get('label', aname)),
    }


def compute_combo_error_values(values_2d, errorbar_mode='std'):
    """按指定模式计算组合图柱状图误差棒。"""
    mode = str(errorbar_mode or 'std').lower()
    std = np.nanstd(values_2d, axis=1)

    if mode == 'std':
        return std, mode, std

    valid_counts = np.sum(~np.isnan(values_2d), axis=1).astype(float)
    sem = np.divide(
        std,
        np.sqrt(valid_counts),
        out=np.full_like(std, np.nan, dtype=float),
        where=valid_counts > 0,
    )

    if mode == 'sem':
        return sem, mode, std
    if mode == 'ci95':
        return 1.96 * sem, mode, std

    raise ValueError(
        f"不支持的组合图误差棒模式: {errorbar_mode}；可选值为 'std' / 'sem' / 'ci95'"
    )


def fill_curve_tail(curve):
    """用最后一个有效值填充尾部 NaN，保持与实际绘图一致。"""
    if curve is None:
        return None
    arr = np.asarray(curve, dtype=float).copy()
    mask = ~np.isnan(arr)
    if not np.any(mask):
        return arr
    last_valid = np.where(mask)[0][-1]
    arr[last_valid + 1:] = arr[last_valid]
    return arr


def build_scalar_points(x_values, means, stds):
    """构建 mean/std 标量图的数据点列表。"""
    points = []
    for x_val, mu, std in zip(x_values, means, stds):
        points.append({
            'x_label': str(int(x_val)),
            'x_value': int(x_val),
            'mean': mu,
            'std': std,
        })
    return points


def build_scalar_figure_data(fig_key, cfg, alg_names, metric_key, metrics, N_values):
    """构建 fig1a / fig1b / fig1c 的导出数据。"""
    series = []
    for aname in alg_names:
        st = get_alg_plot_style(aname)
        means = np.nanmean(metrics[aname][metric_key], axis=1)
        stds = np.nanstd(metrics[aname][metric_key], axis=1)
        series.append({
            'name': st['label'],
            'algorithm': aname,
            'series_kind': 'line',
            'style': {
                'color': st['color'],
                'marker': st['marker'],
                'ls': st['ls'],
                'linewidth': st['linewidth'],
                'markersize': st['markersize'],
                'markerfacecolor': st['markerfacecolor'],
                'markeredgecolor': st['markeredgecolor'],
                'markeredgewidth': st['markeredgewidth'],
            },
            'points': build_scalar_points(N_values, means, stds),
        })

    return {
        'status': 'generated',
        'figure_type': 'line_chart',
        'x_axis': cfg.get('xlabel'),
        'left_y_axis': cfg.get('ylabel'),
        'series': series,
    }


def build_convergence_figure_data(cfg, alg_names, mean_curves, num_rounds):
    """构建 fig2c 的导出数据。"""
    rounds = np.arange(1, num_rounds + 1)
    series = []
    for aname in alg_names:
        curve = fill_curve_tail(mean_curves.get(aname))
        if curve is None or np.all(np.isnan(curve)):
            continue
        st = get_alg_plot_style(aname)
        points = []
        for round_idx, value in zip(rounds, curve):
            points.append({
                'round': int(round_idx),
                'value': value,
            })
        series.append({
            'name': st['label'],
            'algorithm': aname,
            'series_kind': 'line',
            'style': {
                'color': st['color'],
                'marker': st['marker'],
                'ls': st['ls'],
                'linewidth': st['linewidth'],
                'markersize': st['markersize'],
                'markerfacecolor': st['markerfacecolor'],
                'markeredgecolor': st['markeredgecolor'],
                'markeredgewidth': st['markeredgewidth'],
            },
            'points': points,
        })

    return {
        'status': 'generated',
        'figure_type': 'convergence_line_chart',
        'x_axis': cfg.get('xlabel'),
        'left_y_axis': cfg.get('ylabel'),
        'series': series,
    }


def build_inner_loop_figure_data(cfg, mean_curr, std_curr, mean_best, std_best):
    """构建 fig3a 的导出数据。"""
    if mean_curr is None and mean_best is None:
        return {
            'status': 'skipped',
            'figure_type': 'inner_loop_line_chart',
            'x_axis': cfg.get('xlabel'),
            'left_y_axis': cfg.get('ylabel'),
            'reason': 'inner_loop data unavailable',
            'series': [],
        }

    series = []
    if mean_curr is not None:
        points = []
        for iter_idx, (mu, std) in enumerate(zip(mean_curr, std_curr if std_curr is not None else np.full_like(mean_curr, np.nan)), start=1):
            points.append({
                'iteration': int(iter_idx),
                'mean': mu,
                'std': std,
            })
        series.append({
            'name': INNER_LOOP_STYLE['current_label'],
            'algorithm': 'OCF_SAtabu',
            'series_kind': 'line',
            'style': {
                'color': INNER_LOOP_STYLE['current_color'],
                'ls': INNER_LOOP_STYLE['current_ls'],
                'linewidth': PLOT_GLOBAL['linewidth'],
            },
            'points': points,
        })

    if mean_best is not None:
        points = []
        for iter_idx, (mu, std) in enumerate(zip(mean_best, std_best if std_best is not None else np.full_like(mean_best, np.nan)), start=1):
            points.append({
                'iteration': int(iter_idx),
                'mean': mu,
                'std': std,
            })
        series.append({
            'name': INNER_LOOP_STYLE['best_label'],
            'algorithm': 'OCF_SAtabu',
            'series_kind': 'line',
            'style': {
                'color': INNER_LOOP_STYLE['best_color'],
                'ls': INNER_LOOP_STYLE['best_ls'],
                'linewidth': PLOT_GLOBAL['linewidth'],
            },
            'points': points,
        })

    return {
        'status': 'generated',
        'figure_type': 'inner_loop_line_chart',
        'x_axis': cfg.get('xlabel'),
        'left_y_axis': cfg.get('ylabel'),
        'series': series,
    }


# ══════════════════════════════════════════════════════════════════════════════
# 数据提取
# ══════════════════════════════════════════════════════════════════════════════

def extract_final_metrics(results, config):
    """
    返回:
      N_values  : list[int]
      alg_names : list[str]
      metrics   : {alg: {'utility': (nN, nS), 'completion': (nN, nS),
                          'completed_value': (nN, nS), 'cost': (nN, nS), 'time': (nN, nS)}}
    """
    N_values = parse_N_values(config)
    alg_names = parse_alg_names(config)
    nN, nS = get_shape(results)

    metrics = {
        a: {k: np.full((nN, nS), np.nan) for k in ('utility', 'completion', 'completed_value', 'cost', 'time')}
        for a in alg_names
    }

    for ni, si, entry in iter_results(results):
        if not entry or not entry.get('success', False):
            continue
        algs_data = entry.get('algs', {}) or {}
        for aname in alg_names:
            ae = algs_data.get(aname)
            if not ae or not ae.get('success', False):
                continue
            utility = to_scalar(ae.get('final_utility'))
            completion = to_scalar(ae.get('final_completion'))
            cost = to_scalar(ae.get('final_cost'))
            completed_value = to_scalar(ae.get('final_completed_value'))
            if np.isnan(completed_value) and not np.isnan(utility) and not np.isnan(cost):
                completed_value = utility + cost

            metrics[aname]['utility'][ni, si] = utility
            metrics[aname]['completion'][ni, si] = completion
            metrics[aname]['completed_value'][ni, si] = completed_value
            metrics[aname]['cost'][ni, si] = cost
            metrics[aname]['time'][ni, si] = to_scalar(ae.get('computation_time'))

    return N_values, alg_names, metrics


def extract_convergence(results, config, n_target=None):
    """
    提取收敛曲线（图2c）。
    n_target: 取哪个 N 值（None → 取最大 N）。
    返回: mean_curves {alg: [R,]}, num_rounds, n_target
    """
    N_values = parse_N_values(config)
    alg_names = parse_alg_names(config)
    num_rounds = int(to_scalar(config.get('num_rounds', 100)))
    if n_target is None:
        n_target = max(N_values)
    ni_target = N_values.index(n_target)

    curves = {a: [] for a in alg_names}

    for ni, si, entry in iter_results(results):
        if ni != ni_target:
            continue
        if not entry or not entry.get('success', False):
            continue
        algs_data = entry.get('algs', {}) or {}
        for aname in alg_names:
            ae = algs_data.get(aname)
            if not ae or not ae.get('success', False):
                continue
            arr = to_1d(ae.get('convergence_utility'), length=num_rounds)
            curves[aname].append(arr)

    mean_curves = {}
    for aname in alg_names:
        if curves[aname]:
            mat = np.vstack(curves[aname])
            mean_curves[aname] = np.nanmean(mat, axis=0)
        else:
            mean_curves[aname] = np.full(num_rounds, np.nan)

    return mean_curves, num_rounds, n_target


def extract_inner_loop(results, config, n_target=None):
    """
    提取 OCF_SAtabu 的内循环轨迹（图3a），对各种子求均值。
    返回: mean_curr, std_curr, mean_best, std_best, n_target
    """
    N_values = parse_N_values(config)
    if n_target is None:
        n_target = max(N_values)
    ni_target = N_values.index(n_target)

    all_curr, all_best = [], []

    for ni, si, entry in iter_results(results):
        if ni != ni_target:
            continue
        if not entry or not entry.get('success', False):
            continue
        ae = (entry.get('algs', {}) or {}).get('OCF_SAtabu')
        if not ae or not ae.get('success', False):
            continue
        il = ae.get('inner_loop_r50') or {}
        if not il:
            continue
        curr = to_1d(il.get('current_utility'))
        best = to_1d(il.get('best_utility'))
        if len(curr) > 0 and not np.all(np.isnan(curr)):
            all_curr.append(curr)
        if len(best) > 0 and not np.all(np.isnan(best)):
            all_best.append(best)

    def mean_ragged(lst):
        if not lst:
            return None, None
        max_len = max(len(a) for a in lst)
        mat = np.full((len(lst), max_len), np.nan)
        for i, a in enumerate(lst):
            mat[i, :len(a)] = a
        return np.nanmean(mat, axis=0), np.nanstd(mat, axis=0)

    mean_curr, std_curr = mean_ragged(all_curr)
    mean_best, std_best = mean_ragged(all_best)
    return mean_curr, std_curr, mean_best, std_best, n_target


# ══════════════════════════════════════════════════════════════════════════════
# 绘图函数
# ══════════════════════════════════════════════════════════════════════════════

def plot_fig1a(N_values, alg_names, metrics, save_path):
    """图1a：变N效用（mean ± std 折线图）"""
    cfg = merge_figure_config('fig1a')
    fig, ax = plt.subplots(figsize=cm_size_to_inch(PLOT_GLOBAL['figsize_cm']))

    for aname in alg_names:
        st = get_alg_plot_style(aname)
        mu = np.nanmean(metrics[aname]['utility'], axis=1)
        std = np.nanstd(metrics[aname]['utility'], axis=1)

        if PLOT_GLOBAL.get('show_errorbar_varyN', True):
            ax.errorbar(
                N_values, mu, yerr=std,
                color=st['color'], marker=st['marker'], ls=st['ls'],
                lw=st['linewidth'], ms=st['markersize'],
                mfc=st['markerfacecolor'], mec=st['markeredgecolor'],
                mew=st['markeredgewidth'],
                capsize=PLOT_GLOBAL['capsize'],
                label=st['label'], zorder=3,
            )
        else:
            ax.plot(
                N_values, mu,
                color=st['color'], marker=st['marker'], ls=st['ls'],
                lw=st['linewidth'], ms=st['markersize'],
                mfc=st['markerfacecolor'], mec=st['markeredgecolor'],
                mew=st['markeredgewidth'],
                label=st['label'], zorder=3,
            )

    apply_axis_controls(ax, cfg, n_values=N_values)
    apply_common_style(ax, cfg, title=cfg.get('title'))
    finalize_and_save(fig, save_path)
    return build_scalar_figure_data('fig1a', cfg, alg_names, 'utility', metrics, N_values)

def plot_fig1b(N_values, alg_names, metrics, save_path):
    """图1b：变N完成度（mean ± std 折线图）"""
    cfg = merge_figure_config('fig1b')
    fig, ax = plt.subplots(figsize=cm_size_to_inch(PLOT_GLOBAL['figsize_cm']))

    for aname in alg_names:
        st = get_alg_plot_style(aname)
        mu = np.nanmean(metrics[aname]['completion'], axis=1)
        std = np.nanstd(metrics[aname]['completion'], axis=1)

        if PLOT_GLOBAL.get('show_errorbar_varyN', True):
            ax.errorbar(
                N_values, mu, yerr=std,
                color=st['color'], marker=st['marker'], ls=st['ls'],
                lw=st['linewidth'], ms=st['markersize'],
                mfc=st['markerfacecolor'], mec=st['markeredgecolor'],
                mew=st['markeredgewidth'],
                capsize=PLOT_GLOBAL['capsize'],
                label=st['label'], zorder=3,
            )
        else:
            ax.plot(
                N_values, mu,
                color=st['color'], marker=st['marker'], ls=st['ls'],
                lw=st['linewidth'], ms=st['markersize'],
                mfc=st['markerfacecolor'], mec=st['markeredgecolor'],
                mew=st['markeredgewidth'],
                label=st['label'], zorder=3,
            )

    apply_axis_controls(ax, cfg, n_values=N_values)
    apply_common_style(ax, cfg, title=cfg.get('title'))
    finalize_and_save(fig, save_path)
    return build_scalar_figure_data('fig1b', cfg, alg_names, 'completion', metrics, N_values)

def plot_fig1c(N_values, alg_names, metrics, save_path):
    """Plot total completed value vs N."""
    cfg = merge_figure_config('fig1c')
    fig, ax = plt.subplots(figsize=cm_size_to_inch(PLOT_GLOBAL['figsize_cm']))

    for aname in alg_names:
        st = get_alg_plot_style(aname)
        mu = np.nanmean(metrics[aname]['completed_value'], axis=1)
        std = np.nanstd(metrics[aname]['completed_value'], axis=1)

        if PLOT_GLOBAL.get('show_errorbar_varyN', True):
            ax.errorbar(
                N_values, mu, yerr=std,
                color=st['color'], marker=st['marker'], ls=st['ls'],
                lw=st['linewidth'], ms=st['markersize'],
                mfc=st['markerfacecolor'], mec=st['markeredgecolor'],
                mew=st['markeredgewidth'],
                capsize=PLOT_GLOBAL['capsize'],
                label=st['label'], zorder=3,
            )
        else:
            ax.plot(
                N_values, mu,
                color=st['color'], marker=st['marker'], ls=st['ls'],
                lw=st['linewidth'], ms=st['markersize'],
                mfc=st['markerfacecolor'], mec=st['markeredgecolor'],
                mew=st['markeredgewidth'],
                label=st['label'], zorder=3,
            )

    apply_axis_controls(ax, cfg, n_values=N_values)
    apply_common_style(ax, cfg, title=cfg.get('title'))
    finalize_and_save(fig, save_path)
    return build_scalar_figure_data('fig1c', cfg, alg_names, 'completed_value', metrics, N_values)


def plot_dual_axis_combo(fig_key, left_metric_key, N_values, alg_names, metrics, save_path):
    """双Y轴柱状折线组合图：左轴柱状图，右轴完成率折线图。"""
    cfg = merge_figure_config(fig_key)
    selected_indices = get_selected_n_indices(
        N_values,
        COMBO_CHART_STYLE['selected_n_values'],
    )
    selected_n_values = [N_values[idx] for idx in selected_indices]
    x_centers = np.arange(len(selected_n_values), dtype=float)
    show_completion_line = bool(cfg.get('show_completion_line', True))
    show_errorbar = bool(cfg.get('show_errorbar', True))
    errorbar_mode = str(cfg.get('errorbar_mode', 'std')).lower()

    fig, ax = plt.subplots(figsize=cm_size_to_inch(PLOT_GLOBAL['figsize_cm']))
    ax2 = ax.twinx() if show_completion_line else None
    if ax2 is not None:
        ax2.patch.set_alpha(0.0)

    num_algs = len(alg_names)
    bar_width = COMBO_CHART_STYLE['bar_width']
    use_bar_spacing = bool(COMBO_CHART_STYLE.get('use_bar_spacing', True))
    bar_offset_step = (
        COMBO_CHART_STYLE.get('bar_offset_step', bar_width)
        if use_bar_spacing else bar_width
    )
    show_bar_edge = bool(COMBO_CHART_STYLE.get('show_bar_edge', True))
    bar_edgecolor = COMBO_CHART_STYLE['bar_edgecolor'] if show_bar_edge else 'none'
    bar_edgewidth = COMBO_CHART_STYLE['bar_edgewidth'] if show_bar_edge else 0.0
    offsets = (
        np.arange(num_algs, dtype=float) - (num_algs - 1) / 2.0
    ) * bar_offset_step
    series = []

    for alg_idx, aname in enumerate(alg_names):
        bar_style = ALG_STYLE.get(aname, DEFAULT_STYLE)
        line_style = get_combo_line_style(aname)
        x_positions = x_centers + offsets[alg_idx]

        left_values = metrics[aname][left_metric_key][selected_indices, :]
        left_mu = np.nanmean(left_values, axis=1)
        left_error, errorbar_mode, left_std = compute_combo_error_values(
            left_values,
            errorbar_mode=errorbar_mode,
        )

        ax.bar(
            x_positions,
            left_mu,
            width=bar_width,
            color=bar_style['color'],
            alpha=COMBO_CHART_STYLE['bar_alpha'],
            edgecolor=bar_edgecolor,
            linewidth=bar_edgewidth,
            yerr=left_error if show_errorbar else None,
            error_kw={
                'ecolor': COMBO_CHART_STYLE['errorbar_color'],
                'elinewidth': COMBO_CHART_STYLE['errorbar_linewidth'],
                'capsize': PLOT_GLOBAL['capsize'],
                'capthick': COMBO_CHART_STYLE['errorbar_capthick'],
            },
            label=bar_style['label'],
            zorder=2,
        )
        bar_points = []
        for x_idx, n_val, mu, std, err in zip(
            range(len(selected_n_values)),
            selected_n_values,
            left_mu,
            left_std,
            left_error,
        ):
            bar_points.append({
                'x_label': str(int(n_val)),
                'x_index': int(x_idx),
                'x_value': int(n_val),
                'mean': mu,
                'std': std,
                'errorbar': err if show_errorbar else None,
            })
        series.append({
            'name': bar_style['label'],
            'algorithm': aname,
            'series_kind': 'bar',
            'style': {
                'color': bar_style['color'],
                'alpha': COMBO_CHART_STYLE['bar_alpha'],
                'bar_width': bar_width,
                'use_bar_spacing': use_bar_spacing,
                'bar_offset_step': bar_offset_step,
                'show_bar_edge': show_bar_edge,
                'edgecolor': bar_edgecolor,
                'edgewidth': bar_edgewidth,
                'errorbar_color': COMBO_CHART_STYLE['errorbar_color'],
                'errorbar_linewidth': COMBO_CHART_STYLE['errorbar_linewidth'],
                'errorbar_capthick': COMBO_CHART_STYLE['errorbar_capthick'],
                'capsize': PLOT_GLOBAL['capsize'],
                'errorbar_mode': errorbar_mode,
            },
            'points': bar_points,
        })

        if show_completion_line and ax2 is not None:
            completion_values = metrics[aname]['completion'][selected_indices, :]
            completion_mu = np.nanmean(completion_values, axis=1)
            ax2.plot(
                x_centers,
                completion_mu,
                color=line_style['color'],
                marker=line_style['marker'],
                ls=line_style['ls'],
                lw=line_style['linewidth'],
                ms=line_style['markersize'],
                mfc=line_style['markerfacecolor'],
                mec=line_style['markeredgecolor'],
                mew=line_style['markeredgewidth'],
                label='_nolegend_',
                zorder=4,
            )
            line_points = []
            for x_idx, n_val, value in zip(range(len(selected_n_values)), selected_n_values, completion_mu):
                line_points.append({
                    'x_label': str(int(n_val)),
                    'x_index': int(x_idx),
                    'x_value': int(n_val),
                    'value': value,
                })
            series.append({
                'name': bar_style['label'],
                'algorithm': aname,
                'series_kind': 'line',
                'style': line_style,
                'points': line_points,
            })

    ax.set_xticks(x_centers)
    ax.set_xticklabels([str(int(n)) for n in selected_n_values])

    if cfg.get('xlim') is None and len(x_centers) > 0:
        x_pad = ((num_algs - 1) / 2.0) * bar_offset_step + bar_width / 2.0 + 0.12
        ax.set_xlim(x_centers[0] - x_pad, x_centers[-1] + x_pad)

    apply_axis_controls(ax, cfg)
    STYLE_HELPER.apply_common_style(
        ax,
        cfg=cfg,
        title=cfg.get('title'),
        legend_kwargs={
            'loc': COMBO_CHART_STYLE['legend_loc'],
            'bbox_to_anchor': COMBO_CHART_STYLE['legend_bbox_to_anchor'],
            'ncol': COMBO_CHART_STYLE['legend_ncol'],
        },
    )
    if show_completion_line and ax2 is not None:
        apply_secondary_axis_style(
            ax2,
            cfg.get('right_ylabel', 'Completion Rate'),
            ylim=COMBO_CHART_STYLE['completion_ylim'],
            yticks=COMBO_CHART_STYLE['completion_yticks'],
        )
    finalize_and_save(fig, save_path)
    return {
        'status': 'generated',
        'figure_type': 'dual_axis_bar_line_combo',
        'x_axis': cfg.get('xlabel'),
        'left_y_axis': cfg.get('ylabel'),
        'right_y_axis': cfg.get('right_ylabel', 'Completion Rate') if show_completion_line else None,
        'show_completion_line': show_completion_line,
        'show_errorbar': show_errorbar,
        'errorbar_mode': errorbar_mode,
        'series': series,
    }


def plot_fig2c(mean_curves, num_rounds, n_target, alg_names, save_path):
    """图2c：效用收敛曲线（对指定N均值化）"""
    cfg = merge_figure_config(
        'fig2c',
        title=FIGURE_CONFIG['fig2c']['title_template'].format(n_target=n_target),
    )
    fig, ax = plt.subplots(figsize=cm_size_to_inch(PLOT_GLOBAL['figsize_cm']))
    rounds = np.arange(1, num_rounds + 1)

    for aname in alg_names:
        curve = mean_curves.get(aname)
        if curve is None or np.all(np.isnan(curve)):
            continue
        st = get_alg_plot_style(aname)
        filled = fill_curve_tail(curve)
        mask = ~np.isnan(filled)
        if not np.any(mask):
            continue
        marker_kwargs = {}
        if PLOT_GLOBAL['show_markers_fig2c']:
            marker_kwargs = {
                'marker': st['marker'],
                'ms': st['markersize'],
                'mfc': st['markerfacecolor'],
                'mec': st['markeredgecolor'],
                'mew': st['markeredgewidth'],
            }
            if PLOT_GLOBAL['markevery_fig2c'] is not None:
                marker_kwargs['markevery'] = PLOT_GLOBAL['markevery_fig2c']
        ax.plot(
            rounds, filled,
            color=st['color'], ls=st['ls'],
            lw=st['linewidth'], label=st['label'],
            **marker_kwargs,
        )

    apply_axis_controls(ax, cfg)
    apply_common_style(ax, cfg, title=cfg.get('title'))
    finalize_and_save(fig, save_path)
    return build_convergence_figure_data(cfg, alg_names, mean_curves, num_rounds)


def plot_fig3a(mean_curr, std_curr, mean_best, std_best, n_target, save_path):
    """图3a：OCF_SAtabu 内循环 current / best utility 轨迹"""
    cfg = merge_figure_config(
        'fig3a',
        title=FIGURE_CONFIG['fig3a']['title_template'].format(
            round_label=INNER_LOOP_STYLE['round_label'],
            n_target=n_target,
        ),
    )
    if mean_curr is None and mean_best is None:
        print("  ! 内循环数据为空（OCF_SAtabu 未记录 inner_loop），跳过图3a")
        return build_inner_loop_figure_data(cfg, mean_curr, std_curr, mean_best, std_best)

    fig, ax = plt.subplots(figsize=cm_size_to_inch(PLOT_GLOBAL['figsize_cm']))
    ref = mean_curr if mean_curr is not None else mean_best
    iters = np.arange(1, len(ref) + 1)

    if mean_curr is not None:
        marker_kwargs = get_marker_kwargs(
            PLOT_GLOBAL['show_markers_fig3a'],
            INNER_LOOP_STYLE['current_marker'],
            PLOT_GLOBAL['markevery_fig3a'],
        )
        ax.plot(
            iters, mean_curr,
            color=INNER_LOOP_STYLE['current_color'],
            ls=INNER_LOOP_STYLE['current_ls'],
            lw=PLOT_GLOBAL['linewidth'],
            label=INNER_LOOP_STYLE['current_label'],
            **marker_kwargs,
        )
        if std_curr is not None:
            ax.fill_between(
                iters,
                mean_curr - std_curr,
                mean_curr + std_curr,
                alpha=INNER_LOOP_STYLE['current_band_alpha'],
                color=INNER_LOOP_STYLE['current_color'],
            )

    if mean_best is not None:
        marker_kwargs = get_marker_kwargs(
            PLOT_GLOBAL['show_markers_fig3a'],
            INNER_LOOP_STYLE['best_marker'],
            PLOT_GLOBAL['markevery_fig3a'],
        )
        ax.plot(
            iters, mean_best,
            color=INNER_LOOP_STYLE['best_color'],
            ls=INNER_LOOP_STYLE['best_ls'],
            lw=PLOT_GLOBAL['linewidth'],
            label=INNER_LOOP_STYLE['best_label'],
            **marker_kwargs,
        )
        if std_best is not None:
            ax.fill_between(
                iters,
                mean_best - std_best,
                mean_best + std_best,
                alpha=INNER_LOOP_STYLE['best_band_alpha'],
                color=INNER_LOOP_STYLE['best_color'],
            )

    apply_axis_controls(ax, cfg)
    apply_common_style(ax, cfg, title=cfg.get('title'))
    finalize_and_save(fig, save_path)
    return build_inner_loop_figure_data(cfg, mean_curr, std_curr, mean_best, std_best)


# ══════════════════════════════════════════════════════════════════════════════
# 主程序
# ══════════════════════════════════════════════════════════════════════════════

def main():
    apply_plot_rcparams()
    mat_path = find_mat_file(sys.argv)
    configure_output_dir(mat_path)

    print("\n加载数据...")
    raw = mat73.loadmat(mat_path)
    results = raw['scale_N_results']
    config = raw['scale_config']

    N_values = parse_N_values(config)
    alg_names = parse_alg_names(config)
    nN, nS = get_shape(results)
    n_conv = max(N_values)

    print(f"  N_values  = {N_values}")
    print(f"  alg_names = {alg_names}")
    print(f"  形状      = {nN}×{nS} (N×seed)")

    print("\n提取指标...")
    N_values, alg_names, metrics = extract_final_metrics(results, config)
    plot_data = {
        'source_mat_path': os.path.abspath(mat_path),
        'output_dir': os.path.abspath(FIGURES_DIR),
        'selected_n_values': list(COMBO_CHART_STYLE['selected_n_values']),
        'all_n_values': list(N_values),
        'alg_names': list(alg_names),
        'figures': {},
    }

    print(f"\n绘图 → {FIGURES_DIR}")

    plot_data['figures']['fig1a'] = plot_fig1a(
        N_values, alg_names, metrics,
        build_output_path(None, 'fig1a_utility'),
    )

    plot_data['figures']['fig1b'] = plot_fig1b(
        N_values, alg_names, metrics,
        build_output_path(None, 'fig1b_completion'),
    )

    plot_data['figures']['fig1c'] = plot_fig1c(
        N_values, alg_names, metrics,
        build_output_path(None, 'fig1c_completed_value'),
    )

    plot_data['figures']['fig1d'] = plot_dual_axis_combo(
        'fig1d', 'utility', N_values, alg_names, metrics,
        build_output_path(None, 'fig1d_utility_completion_combo'),
    )

    plot_data['figures']['fig1e'] = plot_dual_axis_combo(
        'fig1e', 'completed_value', N_values, alg_names, metrics,
        build_output_path(None, 'fig1e_completed_value_completion_combo'),
    )

    mean_curves, num_rounds, n_target = extract_convergence(
        results, config, n_target=n_conv,
    )
    plot_data['figures']['fig2c'] = plot_fig2c(
        mean_curves, num_rounds, n_target, alg_names,
        build_output_path(None, 'fig2c_convergence'),
    )

    mc, sc, mb, sb, nt = extract_inner_loop(results, config, n_target=n_conv)
    plot_data['figures']['fig3a'] = plot_fig3a(
        mc, sc, mb, sb, nt,
        build_output_path(None, 'fig3a_innerloop'),
    )

    write_plot_data_json(
        os.path.join(FIGURES_DIR, 'varyN_plot_data_all.json'),
        plot_data,
    )
    write_plot_data_json(
        os.path.join(FIGURES_DIR, 'varyN_plot_data_combo_only.json'),
        build_combo_only_payload(plot_data, N_values, alg_names, metrics),
    )

    print("\n完成。图窗已弹出，关闭后程序退出。")
    plt.show()


if __name__ == '__main__':
    main()
