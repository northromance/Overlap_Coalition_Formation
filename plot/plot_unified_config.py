"""
统一绘图配置入口。

这个文件是 `plot/` 目录下各绘图脚本共享默认参数的唯一来源。

建议阅读顺序：
1. 文件顶部的快速调节常量
2. COMMON_CONFIG：所有绘图族共享的默认模板
3. FAMILY_CONFIG：各绘图族自己的覆盖项和图级元数据
4. 底部辅助函数：对外提供整理后的配置读取接口

本文件主要负责：
- 统一字体、字号和单幅图尺寸
- 算法配色、marker、线型等默认样式
- 柱状图、组合图等局部布局默认值
- 各 family 的标题、坐标轴标签、范围和导出前缀
"""

import copy
import numpy as np


# ============================================================================
# 快速调节区
# ----------------------------------------------------------------------------
# 当你想统一调整整篇论文的字体排版，或者修改单幅图默认尺寸时，
# 首先改这一段。
#
# 这一段负责：
# - 全局标题开关
# - 公共字体族 / 字体样式 / 字重
# - 公共单幅图尺寸
# - 公共标题 / 坐标轴标签 / 刻度字号
#
# 这一段不负责：
# - 图例疏密和图例字号
# - 网格是否显示
# - 导出 dpi / 保存格式 / 导出边距
# - 各 family 自己的标题文案、坐标范围和布局策略
# ============================================================================
COMMON_SHOW_TITLES = True

# 所有显式接入“公共字体配置”的脚本都会使用这里的字体设置。
COMMON_FONT_FAMILY = ["Times New Roman"]
COMMON_FONT_STYLE = "normal"
COMMON_FONT_WEIGHT = "normal"

# 单幅图（一个主坐标轴）的默认物理尺寸，单位是厘米。
COMMON_SINGLE_FIGSIZE_IN = (3.5, 3.5)
COMMON_SINGLE_FIGSIZE_CM = tuple(round(v * 2.54, 2) for v in COMMON_SINGLE_FIGSIZE_IN)

# 标题、坐标轴标签、刻度共用的默认字号。
COMMON_TITLE_FONTSIZE = 8
COMMON_XLABEL_FONTSIZE = 8
COMMON_YLABEL_FONTSIZE = 8
COMMON_TICK_FONTSIZE = 8
COMMON_LEGEND_FONTSIZE = 8
COMMON_TITLE_PAD = 4


def get_shared_typography_config():
    """返回任意绘图脚本都可复用的排版默认值。

    这个辅助函数只返回和“字体排版”直接相关的字段：
    - show_titles
    - font family / style / weight
    - title / xlabel / ylabel / tick font sizes
    - title pad

    它不会包含图例策略、网格开关、dpi、保存格式，也不会包含
    某个 family 专属的坐标轴范围设置。
    """

    return {
        "show_titles": COMMON_SHOW_TITLES,
        "font_family": list(COMMON_FONT_FAMILY),
        "font_style": COMMON_FONT_STYLE,
        "font_weight": COMMON_FONT_WEIGHT,
        "title_fontsize": COMMON_TITLE_FONTSIZE,
        "xlabel_fontsize": COMMON_XLABEL_FONTSIZE,
        "ylabel_fontsize": COMMON_YLABEL_FONTSIZE,
        "tick_fontsize": COMMON_TICK_FONTSIZE,
        "legend_fontsize": COMMON_LEGEND_FONTSIZE,
        "subplot_title_fontsize": None,
        "legend_title_fontsize": None,
        "colorbar_label_fontsize": None,
        "colorbar_tick_fontsize": None,
        "title_pad": COMMON_TITLE_PAD,
    }


def get_shared_single_figure_config():
    """返回单幅图默认配置。

    这是 `get_shared_typography_config()` 的一个便捷包装，在公共排版
    配置基础上额外加入 `figsize_cm`。
    """

    cfg = get_shared_typography_config()
    cfg["figsize_in"] = tuple(COMMON_SINGLE_FIGSIZE_IN)
    cfg["figsize_cm"] = tuple(COMMON_SINGLE_FIGSIZE_CM)
    cfg["constrained_layout"] = True
    cfg["axes_box_aspect"] = 1.0
    return cfg


# 导出文件名 stem 组装时使用这里的前缀，避免不同 family 的命名规则
# 慢慢漂移成互不一致。
OUTPUT_PREFIX = {
    "varyN": "varyN",
    "varyM": "varyM",
    "belief": "belief",
    "belief_funnel": "belief_funnel",
    "ablation": "ablation",
    "single_viz": "single_viz",
    "convergence_detail": "detail_convergence",
}

# 前缀含义：
# - key：调用方使用的逻辑 family 名称
# - value：导出文件名 stem 前面实际插入的前缀
# 把它统一放在这里，可以避免不同脚本各自拼文件名导致风格漂移。

ALG_DISPLAY_NAMES = {
    "Huo2025": "NOCF",
    "Qi2023": "PCG-TS",
    "Shi2024": "JSE-OCF",
    "OCF_SAtabu": "BHTA",
}


def get_alg_display_name(aname):
    """Return the public-facing display name for an algorithm key."""
    return ALG_DISPLAY_NAMES.get(str(aname), str(aname))


def get_alg_display_names(alg_names):
    """Return display names in the same order as the internal algorithm keys."""
    return [get_alg_display_name(aname) for aname in alg_names]


def _apply_alg_display_labels(plot_cfg):
    """Inject unified display labels into merged style maps."""
    alg_style = plot_cfg.get("ALG_STYLE")
    if isinstance(alg_style, dict):
        for aname, style in alg_style.items():
            if isinstance(style, dict):
                style["label"] = get_alg_display_name(aname)

    combo_style = plot_cfg.get("COMBO_CHART_STYLE")
    if isinstance(combo_style, dict):
        bar_style_by_alg = combo_style.get("bar_style_by_alg")
        if isinstance(bar_style_by_alg, dict):
            for aname, style in bar_style_by_alg.items():
                if isinstance(style, dict):
                    style["label"] = get_alg_display_name(aname)

    return plot_cfg


# ============================================================================
# 公共模板
# ----------------------------------------------------------------------------
# COMMON_CONFIG 会先作为基础模板注入到每一个 plot family 中，除非某个
# family 在 FAMILY_CONFIG 里显式覆盖对应字段。
#
# 主要子块：
# - ALG_STYLE：折线图里各算法的完整样式定义
# - DEFAULT_STYLE：遇到未知算法名时的兜底样式
# - PLOT_GLOBAL：全局绘图 / 导出默认值
# - BAR_CHART_STYLE：分组柱状图共用的局部布局参数
# ============================================================================
COMMON_CONFIG = {
    # 每个算法默认的线型 / marker / 颜色样式。绘图脚本可以直接复用，
    # 也可以在此基础上再裁剪成更简化的样式。
    "ALG_STYLE": {
        "Huo2025": dict(
            color="#9B9B9B",
            marker="o",
            ls="--",
            lw=1,
            ms=4.0,
            mfc="#9B9B9B",
            mec="#9B9B9B",
            mew=1.2,
            label=ALG_DISPLAY_NAMES["Huo2025"],
        ),
        "Qi2023": dict(
            color="#A2DFF8",
            marker="s",
            ls="--",
            lw=1,
            ms=4.0,
            mfc="#A2DFF8",
            mec="#A2DFF8",
            mew=1.2,
            label=ALG_DISPLAY_NAMES["Qi2023"],
        ),
        "Shi2024": dict(
            color="#9DABD2",
            marker="^",
            ls="-.",
            lw=1,
            ms=4.0,
            mfc="#9DABD2",
            mec="#9DABD2",
            mew=1.2,
            label=ALG_DISPLAY_NAMES["Shi2024"],
        ),
        "OCF_SAtabu": dict(
            color="#555B9C",
            marker="o",
            ls="-",
            lw=1,
            ms=4.0,
            mfc="none",
            mec="#555B9C",
            mew=1.8,
            label=ALG_DISPLAY_NAMES["OCF_SAtabu"],
        ),
    },
    # 当绘图脚本遇到未知算法名时，使用这个兜底样式。
    "DEFAULT_STYLE": dict(
        color="#888888",
        marker="x",
        ls=":",
        lw=1.3,
        ms=4.0,
        mfc="#888888",
        mec="#888888",
        mew=0.8,
        label="Unknown",
    ),
    # 每个 family 共用的全局绘图默认值；如果某个 family 需要特殊行为，
    # 再在 FAMILY_CONFIG 中覆盖。
    "PLOT_GLOBAL": {
        # 单幅图尺寸，以及折线和 marker 的几何参数。
        "figsize_in": tuple(COMMON_SINGLE_FIGSIZE_IN),
        "figsize_cm": tuple(COMMON_SINGLE_FIGSIZE_CM),
        "constrained_layout": True,
        "axes_box_aspect": 1.0,
        "linewidth": 1.2,
        "markersize": 3.2,
        "markeredgewidth": 0.9,
        "capsize": 1,

        # varyN / varyM 一类脚本会用到的误差棒和 marker 开关。
        "show_errorbar_varyN": False,
        "show_errorbar_varyM": False,
        "show_markers_fig2c": False,
        "show_markers_fig3a": False,
        "show_markers_fig2d": False,
        "markevery_fig2c": None,
        "markevery_fig3a": None,
        "markevery_fig2d": None,
        "show_fig2d_band": True,
        "fig2d_band_alpha": 0.18,

        # 公共字体排版参数。论文润色阶段最常改动的通常就是这一块。
        "font_family": list(COMMON_FONT_FAMILY),
        "font_style": COMMON_FONT_STYLE,
        "font_weight": COMMON_FONT_WEIGHT,
        "xlabel_fontsize": COMMON_XLABEL_FONTSIZE,
        "ylabel_fontsize": COMMON_YLABEL_FONTSIZE,
        "label_fontweight": "normal",
        "show_titles": COMMON_SHOW_TITLES,
        "title_fontsize": COMMON_TITLE_FONTSIZE,
        "title_fontweight": "normal",
        "title_pad": COMMON_TITLE_PAD,
        "tick_fontsize": COMMON_TICK_FONTSIZE,
        "tick_fontweight": "normal",
        "subplot_title_fontsize": None,
        "legend_title_fontsize": None,
        "colorbar_label_fontsize": None,
        "colorbar_tick_fontsize": None,

        # 图例默认参数。某些脚本如果需要更紧凑或更松散的图例布局，
        # 仍然可以在本地单独覆盖。
        "legend_fontsize": COMMON_LEGEND_FONTSIZE,
        "legend_fontweight": "normal",
        "legend_loc": "lower right",
        "legend_bbox_to_anchor": None,
        "legend_ncol": 2,
        "legend_borderaxespad": 0.2,
        "legend_handlelength": 1.6,
        "legend_labelspacing": 0.25,

        # 网格和坐标轴边框的默认行为。
        "show_grid": False,
        "grid_linestyle": "--",
        "grid_linewidth": 0.4,
        "grid_alpha": 0.22,
        "show_legend": True,
        "legend_framealpha": 0.92,
        "legend_edgecolor": "#cccccc",
        "hide_top_spine": False,
        "hide_right_spine": False,

        # 导出默认值。大多数脚本使用 EPS 作为论文图输出，同时保留 PNG
        # 作为预览或栅格备份格式。
        "save_format": "eps",
        "save_formats": ["eps", "png"],
        "save_dpi": 300,
        "save_bbox_inches": "tight",
        "save_pad_inches": 0.02,
        "timestamp_first_in_name": True,
        "tight_layout": False,
        "use_fixed_export_margins": False,
        "export_margin_left_cm": 1.62,
        "export_margin_right_cm": 0.98,
        "export_margin_bottom_cm": 1.02,
        "export_margin_top_cm": 0.30,
    },
    # 分组柱状图共用的局部布局参数。
    "BAR_CHART_STYLE": {
        # `bar_width`：单个柱子的物理宽度。
        # `use_bar_spacing`：是否允许柱间距独立于柱宽单独控制。
        # `bar_offset_step`：同一组 x 位置内，相邻算法柱中心之间的偏移量。
        # 下面的 error-bar 参数只作用于柱状图，不作用于折线图。
        "bar_width": 0.22,
        "use_bar_spacing": False,
        "bar_offset_step": 0.19,
        "bar_alpha": 0.8,
        "show_bar_edge": False,
        "bar_edgecolor": "#000000",
        "bar_edgewidth": 0.5,
        "errorbar_color": "#000000",
        "errorbar_linewidth": 0.5,
        "errorbar_capthick": 0.3,
    },
}


# ============================================================================
# Family 覆盖配置
# ----------------------------------------------------------------------------
# FAMILY_CONFIG 只存“某一个绘图族自己独有的内容”，例如：
# - 导出前缀
# - 每张图的标题 / 坐标轴标签 / 坐标范围
# - family 专属的局部样式，比如 varyN 的组合图样式
# ============================================================================
FAMILY_CONFIG = {
    # varyN 这一族主要包括：
    # - 随 agent 数量 N 变化的标量指标图
    # - 双 y 轴组合图
    # - 收敛过程图和 inner-loop 轨迹图
    "varyN": {
        "OUTPUT_PREFIX": OUTPUT_PREFIX["varyN"],

        # inner-loop 轨迹图的局部样式。
        "INNER_LOOP_STYLE": {
            "current_label": "Current Utility",
            "current_color": "#4878CF",
            "current_ls": "-",
            "current_marker": "o",
            "current_band_alpha": 0.15,
            "best_label": "Best Utility",
            "best_color": "#D65F5F",
            "best_ls": "--",
            "best_marker": "s",
            "best_band_alpha": 0.15,
            "round_label": 50,
        },

        # 效用 / 完成率双轴组合图的局部样式。
        "COMBO_CHART_STYLE": {
            "selected_n_values": [4, 6, 8, 10, 12, 14, 16],
            "bar_width": 0.22,
            "use_bar_spacing": False,
            "bar_offset_step": 0.19,
            "bar_alpha": 0.8,
            "show_bar_edge": False,
            "bar_edgecolor": "#000000",
            "bar_edgewidth": 0.5,
            "errorbar_color": "#000000",
            "errorbar_linewidth": 0.5,
            "errorbar_capthick": 0.3,
            "completion_ylim": (0.2, 1.3),
            "completion_yticks": [0.2, 0.4, 0.6, 0.8, 1.0],
            "line_style_by_alg": {
                "Huo2025": {
                    "color": "#7DBEE9",
                    "marker": "o",
                    "ls": "-",
                    "linewidth": 1.4,
                    "markersize": 4.2,
                    "markeredgewidth": 1.0,
                },
                "Qi2023": {
                    "color": "#3091CB",
                    "marker": "s",
                    "ls": "--",
                    "linewidth": 1.4,
                    "markersize": 4.2,
                    "markeredgewidth": 1.0,
                },
                "Shi2024": {
                    "color": "#FDB385",
                    "marker": "^",
                    "ls": "-.",
                    "linewidth": 1.4,
                    "markersize": 4.2,
                    "markeredgewidth": 1.0,
                },
                "OCF_SAtabu": {
                    "color": "#CE692E",
                    "marker": "o",
                    "ls": "-",
                    "linewidth": 1.6,
                    "markersize": 4.4,
                    "mfc": "none",
                    "mec": "#C92D2E",
                    "markeredgewidth": 1.2,
                },
            },
        },

        # varyN 脚本逐图读取的元数据：
        # - title / xlabel / ylabel 会交给 PlotStyleHelper 使用
        # - xlim / ylim / xticks / yticks 是可选的坐标轴控制项
        # - use_fixed_* 用于告诉绘图脚本是否强制使用固定刻度
        # - bottom_zero 表示当脚本没有显式给出 ylim 时，是否把 y 轴下界
        #   钉在 0 附近，避免自动缩放跑到负数
        #
        # 每个图配置里常见字段的含义：
        # - `show_title`：这张图自己的标题开关；实际使用时通常会再和
        #   PLOT_GLOBAL 里的总标题开关一起判断
        # - `title`：固定标题文本
        # - `title_template`：带占位符的标题模板，例如 n_target
        # - `xlabel` / `ylabel`：左侧主坐标轴标签
        # - `right_ylabel`：双 y 轴图右侧坐标轴标签
        # - `xlim` / `ylim`：显式坐标范围；None 表示自动
        # - `xticks` / `yticks`：显式刻度位置；None 表示自动
        # - `use_fixed_N_xticks`：即使 xticks 为 None，也按 N 的标准刻度
        #   进行固定
        # - `bottom_zero`：允许脚本把 y 轴下界夹到 0
        # - `show_errorbar` / `errorbar_mode`：是否绘制不确定性，以及用
        #   什么统计量
        # - `show_completion_line`：双轴效用/完成率图里是否绘制右轴完成率线
        "FIGURE_CONFIG": {
            # Fig. 1a/1b/1c：随 N 变化的标量指标图。
            "fig1a": {
                "show_title": False,
                "title": "Fig. 1a - Utility vs. N",
                "xlabel": "Number of Robots",
                "ylabel": "Final Coalition Utility",
                "xlim": None,
                "ylim": None,
                "xticks": None,
                "yticks": None,
                "use_fixed_N_xticks": True,
                "bottom_zero": False,
            },
            "fig1b": {
                "show_title": False,
                "title": "Fig. 1b - Completion vs. N",
                "xlabel": "Number of Robots",
                "ylabel": "Task Completion Degree",
                "xlim": None,
                "ylim": [0.15, 1.05],
                "xticks": None,
                "yticks": None,
                "use_fixed_N_xticks": True,
                "bottom_zero": True,
                "show_legend": True,
            },
            "fig1c": {
                "show_title": False,
                "title": "Fig. 1c - Total Completed Value vs. N",
                "xlabel": "Number of Robots",
                "ylabel": "Total Completed Value",
                "xlim": None,
                "ylim": [3000, 12000],
                "xticks": None,
                "yticks": None,
                "use_fixed_N_xticks": True,
                "bottom_zero": True,
            },

            # Fig. 1d/1e：双轴组合图。左轴通常是柱子，右轴可选显示完成率。
            "fig1d": {
                "show_title": False,
                "title": "Fig. 1d - Utility and Completion vs. N",
                "xlabel": "Number of Robots",
                "ylabel": "Final Coalition Utility",
                "right_ylabel": "Completion Rate",
                "show_completion_line": False,
                "show_errorbar": True,
                "errorbar_mode": "sem",
                "xlim": None,
                "ylim": None,
                "xticks": None,
                "yticks": None,
                "use_fixed_N_xticks": False,
                "bottom_zero": True,
            },
            "fig1e": {
                "show_title": False,
                "title": "Fig. 1e - Total Completed Value and Completion vs. N",
                "xlabel": "Number of Robots",
                "ylabel": "Total Completed Value",
                "right_ylabel": "Completion Rate",
                "show_completion_line": False,
                "show_errorbar": True,
                "errorbar_mode": "sem",
                "xlim": None,
                "ylim": [2500, 12000],
                "xticks": None,
                "yticks": None,
                "use_fixed_N_xticks": False,
                "bottom_zero": True,
            },

            # Fig. 2c：外层 round 上的平均收敛曲线。
            "fig2c": {
                "show_title": False,
                "title_template": "Fig. 2c - Convergence (N={n_target})",
                "xlabel": "Round",
                "ylabel": "Coalition Utility",
                "xlim": None,
                "ylim": None,
                "xticks": None,
                "yticks": None,
                "use_fixed_N_xticks": False,
                "bottom_zero": False,
            },

            # Fig. 3a：指定 round / N 下的 inner-loop 轨迹图。
            "fig3a": {
                "show_title": True,
                "title_template": "Fig. 3a - Inner Loop (Round {round_label}, N={n_target})",
                "xlabel": "Inner Iteration",
                "ylabel": "Utility",
                "xlim": None,
                "ylim": None,
                "xticks": None,
                "yticks": None,
                "use_fixed_N_xticks": False,
                "bottom_zero": False,
            },
        },
    },

    # varyM 这一族主要包括：
    # - 随任务数 M 变化的标量指标图
    # - 分组柱状图
    # - 外层 round 的收敛图
    "varyM": {
        "OUTPUT_PREFIX": OUTPUT_PREFIX["varyM"],
        "FIGURE_CONFIG": {
            # 这里字段含义与上面的 varyN FIGURE_CONFIG 基本一致，只是
            # x 轴变成任务数 M，因此使用 `use_fixed_M_xticks`。
            # Fig. 1c/1d/1e：随 M 变化的标量指标图。
            "fig1c": {
                "show_title": False,
                "title": "Fig. 1c - Utility vs. M",
                "xlabel": "Number of Tasks",
                "ylabel": "Final Coalition Utility",
                "xlim": None,
                "ylim": None,
                "xticks": None,
                "yticks": None,
                "use_fixed_M_xticks": True,
                "bottom_zero": False,
            },
            "fig1d": {
                "show_title": False,
                "title": "Fig. 1d - Completion vs. M",
                "xlabel": "Number of Tasks",
                "ylabel": "Task Completion Degree",
                "xlim": None,
                "ylim": [0.2, 1],
                "xticks": None,
                "yticks": None,
                "use_fixed_M_xticks": True,
                "bottom_zero": True,
                "show_legend": True,
            },
            "fig1e": {
                "show_title": False,
                "title": "Fig. 1e - Total Completed Value vs. M",
                "xlabel": "Number of Tasks",
                "ylabel": "Total Completed Value",
                "xlim": None,
                "ylim": [5000, 18000],
                "xticks": None,
                "yticks": None,
                "use_fixed_M_xticks": True,
                "bottom_zero": True,
            },

            # Fig. 1f/1g：可选带误差棒的分组柱状图。
            "fig1f": {
                "show_title": False,
                "title": "Fig. 1f - Utility Bar Chart vs. M",
                "xlabel": "Number of Tasks",
                "ylabel": "Final Coalition Utility",
                "xlim": None,
                "ylim": None,
                "xticks": None,
                "yticks": None,
                "use_fixed_M_xticks": True,
                "bottom_zero": False,
                "show_errorbar": True,
                "errorbar_mode": "sem",
            },
            "fig1g": {
                "show_title": False,
                "title": "Fig. 1g - Total Completed Value Bar Chart vs. M",
                "xlabel": "Number of Tasks",
                "ylabel": "Total Completed Value",
                "xlim": None,
                "ylim": [5000, 18000],
                "xticks": None,
                "yticks": None,
                "use_fixed_M_xticks": True,
                "bottom_zero": True,
                "show_errorbar": True,
                "errorbar_mode": "sem",
            },

            # Fig. 2d：指定 M 下的收敛曲线。
            "fig2d": {
                "show_title": False,
                "title_template": "Fig. 2d - Convergence (M={m_target})",
                "xlabel": "Round",
                "ylabel": "Coalition Utility",
                "xlim": None,
                "ylim": None,
                "xticks": None,
                "yticks": None,
                "use_fixed_M_xticks": False,
                "bottom_zero": False,
                "show_legend": True,
            },
        },
    },

    # single_viz 这一族：
    # 大部分仍复用公共默认值，但会重新打开标题 / 网格 / 图例，因为
    # 它更偏可视化检查和展示用途，而不是论文里那种紧凑排版的子图。
    "belief": {
        "OUTPUT_PREFIX": OUTPUT_PREFIX["belief"],
        "PLOT_GLOBAL": {
            "linewidth": 1.8,
            "agent_linewidth": 1.2,
            "band_alpha": 0.18,
            "show_band": True,
            "show_grid": True,
            "grid_linestyle": "--",
            "grid_linewidth": 0.6,
            "grid_alpha": 0.4,
            "show_legend": True,
            "legend_framealpha": 0.85,
            "legend_edgecolor": "#cccccc",
            "hide_top_spine": True,
            "hide_right_spine": True,
            "save_formats": ["png", "eps", "pdf"],
            "save_dpi": 150,
            "save_bbox_inches": "tight",
            "tight_layout": True,
            "summary_figsize_cm": (26.92, 11.18),
            "rep_figsize_per_panel_cm": (10.41, 9.91),
            "appendix_cell_size_cm": (10.41, 7.62),
            "fig2c_subplot_size_cm": (8.13, 6.60),
            "thin_linewidth": 1.0,
            "agent_mean_linewidth": 2.3,
            "thin_alpha": 0.22,
            "marker": "o",
            "markersize": 4.2,
        },
        "COND_STYLE": {
            "uniform": dict(color="#4878CF", ls="-", label="Uniform prior"),
            "heterogeneous": dict(color="#D65F5F", ls="--", label="Heterogeneous prior"),
        },
        "DEFAULT_COND_STYLE": dict(color="#888888", ls=":", label="Unknown"),
        "AGENT_COLORS": [
            "#0D80D2", "#ff7f0e", "#2ca02c", "#d62728", "#9467bd",
            "#8c564b", "#e377c2", "#7f7f7f", "#bcbd22", "#17becf",
            "#aec7e8", "#ffbb78", "#98df8a", "#ff9896", "#c5b0d5",
            "#c49c94", "#f7b6d2", "#c7c7c7", "#dbdb8d", "#9edae5",
        ],
        "TRUE_VALUE_STYLE": dict(color="#000000", ls=":", lw=2.0, label="True value"),
        "AGENT_TRACE_STYLE": dict(color="#B7B7B7", lw=0.9, alpha=0.55, label="Robot traces"),
        "FIGURE_CONFIG": {
            "fig2a": {
                "show_title": True,
                "title": "Fig. 2a - Belief Error vs. Round",
                "xlabel": "Round",
                "ylabel": "Avg. L1 Belief Error",
                "bottom_zero": True,
            },
            "fig2b": {
                "show_title": True,
                "title": "Fig. 2b - Expected Value Prediction vs. Round",
                "xlabel": "Round",
                "ylabel": "Avg. Expected Task Value",
                "bottom_zero": False,
            },
            "fig2c": {
                "show_title": True,
                "title_template": "Task {m} (true={v:.0f})",
                "suptitle_template": "Fig. 2c - Per-robot Belief Convergence [{cond}]",
                "xlabel": "Round",
                "ylabel": "Expected Value",
                "bottom_zero": False,
            },
            "summary_left": {
                "show_title": True,
                "title": "(a) Avg. L1 Belief Error",
                "xlabel": "Round",
                "ylabel": "Avg. L1 belief error",
                "bottom_zero": True,
            },
            "summary_right": {
                "show_title": True,
                "title": "(b) Avg. Relative Value Error",
                "xlabel": "Round",
                "ylabel": "Avg. relative value error",
                "bottom_zero": True,
            },
            "representative": {
                "show_title": True,
                "title": "Fig. 2b - Representative Task Convergence",
                "xlabel": "Round",
                "ylabel": "Expected task value",
                "bottom_zero": False,
            },
            "appendix_new": {
                "show_title": True,
                "title": "Fig. 2c - Robot-level Trajectories on Representative Tasks",
                "xlabel": "Round",
                "ylabel": "Expected task value",
                "bottom_zero": False,
            },
        },
    },

    "belief_funnel": {
        "OUTPUT_PREFIX": OUTPUT_PREFIX["belief_funnel"],
        "PLOT_GLOBAL": {
            "linewidth": 1.4,
            "ref_linewidth": 1.0,
            "ref_alpha": 0.85,
            "band_alpha": 0.20,
            "marker": "o",
            "markersize": 3.5,
            "markevery": 1,
            "show_band": True,
            "show_reference_line": True,
            "show_grid": True,
            "grid_linestyle": "--",
            "grid_linewidth": 0.45,
            "grid_alpha": 0.25,
            "show_legend": True,
            "legend_loc": "best",
            "legend_ncol": 2,
            "legend_borderaxespad": 0.3,
            "legend_handlelength": 2.0,
            "legend_labelspacing": 0.4,
            "legend_framealpha": 0.9,
            "legend_edgecolor": "#cccccc",
            "hide_top_spine": True,
            "hide_right_spine": True,
            "save_format": "eps",
            "save_formats": ["png", "eps", "pdf"],
            "save_dpi": 600,
            "save_bbox_inches": "tight",
            "timestamp_first_in_name": False,
            "tight_layout": True,
            "y_padding_min": 20.0,
            "y_padding_ratio": 0.05,
        },
        "TYPE_COLORS": {
            1: "#4878CF",
            2: "#6ACC65",
            3: "#D65F5F",
            4: "#EE854A",
            5: "#C4AD66",
            6: "#956CB4",
        },
        "FALLBACK_COLORS": ["#4878CF", "#6ACC65", "#D65F5F", "#EE854A", "#C4AD66", "#956CB4"],
        "FIGURE_CONFIG": {
            "belief_funnel": {
                "show_title": True,
                "show_legend": True,
                "title_template": "Belief Funnel Convergence [{condition_name}]",
                "xlabel": "Communication round",
                "ylabel": "Expected task value",
                "bottom_zero": True,
            },
        },
    },

    "ablation": {
        "OUTPUT_PREFIX": OUTPUT_PREFIX["ablation"],
        "PLOT_GLOBAL": {
            "legend_fontsize": 7,
            "subplot_w_cm": 4.50,
            "subplot_h_cm": 5.00,
            "convergence_subplot_w_cm": 4.50,
            "convergence_subplot_h_cm": 5.00,
            "show_grid": True,
            "grid_linewidth": 0.4,
            "grid_alpha": 0.35,
            "hide_top_spine": False,
            "hide_right_spine": False,
            "show_legend": False,
            "tight_layout": True,
            "save_dpi": 150,
            "save_format": "png",
            "save_formats": ["png", "eps", "pdf"],
            "save_bbox_inches": "tight",
            "band_alpha": 0.16,
            "use_scientific_utility_ticks": True,
            "utility_tick_power": 3,
            "fallback_markersize": 7.5,
            "fallback_markeredgewidth": 1.2,
            "fallback_linewidth": 2.0,
        },
        "CONDITION_STYLE_MAP": {
            "belief_off": {
                "color": "#C0392B",
                "marker": "o",
                "markersize": 2.5,
                "markeredgewidth": 1.8,
                "linewidth": 1.5,
                "label": "",
                "legend_label": "Non-Belief Update",
            },
            "belief_on": {
                "color": "#2E6DB4",
                "marker": "o",
                "markersize": 5,
                "markeredgewidth": 1.2,
                "linewidth": 2.0,
                "label": "belief_on",
                "legend_label": "Belief Update",
            },
            "belief_on_quantile": {
                "color": "#2E6DB4",
                "marker": "o",
                "markersize": 2.5,
                "markeredgewidth": 1.2,
                "linewidth": 1.5,
                "label": "belief_on_quantile",
                "legend_label": "Belief Update",
            },
            "belief_on_expected": {
                "color": "#1F8A5B",
                "marker": "^",
                "markersize": 8.0,
                "markeredgewidth": 1.2,
                "linewidth": 2.0,
                "label": "belief_on_expected",
                "legend_label": "BHTA with Expected Belief Update",
            },
        },
        "FALLBACK_COLORS": ["#7A5195", "#EF5675", "#FFA600", "#4C78A8", "#72B7B2"],
        "FALLBACK_MARKERS": ["s", "D", "P", "v", ">"],
        "CONN_LINE": {"color": "#B3B3B3", "linewidth": 0.8, "alpha": 0.7, "zorder": 2},
        "ROW_YLABELS": ["Coalition Utility", "Task Completion Rate"],
        "ROW_TITLES": ["Endpoint Utility", "Endpoint Completion"],
        "FIGURE_CONFIG": {
            "endpoint_scatter": {
                "show_title": True,
                "show_suptitle": False,
                "show_legend": True,
                "title": "Ablation endpoint comparison",
                "tight_layout": False,
                "ylim": [0.2, 1.0],
                "show_utility_row": False,
                "use_shared_row_ylabels": True,
                "shared_row_ylabels": ["Coalition Utility", "Task Completion Rate"],
                "shared_row_ylabel_x": 0.020,
                "legend_container": "axes",
                "legend_subplot_index": "last_active",
                "legend_loc": "lower right",
                "legend_ncol": 1,
                "subplot_title_template": "N = {n_value}",
                "suptitle_y": 0.98,
                "subplots_adjust_left": 0.085,
                "subplots_adjust_right": 0.985,
                "subplots_adjust_bottom": 0.18,
                "subplots_adjust_top": 0.88,
                "subplot_wspace": 0.25,
                "subplot_hspace": 0.35,
            },
            "convergence": {
                "show_title": True,
                "show_suptitle": False,
                "show_legend": True,
                "title_template": "Ablation convergence by N ({band_desc})",
                "xlabel": "Round",
                "ylabel": "Coalition Utility",
                "ylim": [2000, 12000],
                "tight_layout": False,
                "use_shared_ylabel": True,
                "shared_ylabel_text": "Coalition Utility",
                "shared_ylabel_x": 0.020,
                "legend_container": "axes",
                "legend_subplot_index": "last_active",
                "legend_loc": "lower right",
                "legend_ncol": 1,
                "subplot_title_template": "N = {n_value}",
                "suptitle_y": 0.98,
                "subplots_adjust_left": 0.085,
                "subplots_adjust_right": 0.985,
                "subplots_adjust_bottom": 0.18,
                "subplots_adjust_top": 0.88,
                "subplot_wspace": 0.25,
            },
        },
    },

    "single_viz": {
        "OUTPUT_PREFIX": OUTPUT_PREFIX["single_viz"],
        "PLOT_GLOBAL": {
            # single_viz 故意比论文图更“宽松”：
            # - 标题打开
            # - 网格打开
            # - 图例打开
            # 目标是交互检查和展示，而不是紧凑的论文多子图布局。
            "font_family": ["Times New Roman"],
            "linewidth": 1.5,
            "show_titles": True,
            "show_grid": True,
            "show_legend": True,
            "hide_top_spine": False,
            "hide_right_spine": False,
            "save_formats": ["eps", "png"],
            "save_dpi": 300,
            "save_bbox_inches": "tight",
            "tight_layout": False,
            "use_fixed_export_margins": False,
            "grid_linewidth": 0.5,
            "grid_alpha": 0.35,
            "legend_framealpha": 0.85,
            "legend_edgecolor": "#cccccc",
            "spine_color": "#000000",
            "spine_linewidth": 0.8,
            "markersize": 2,
        },
        "TEXT_STYLE": {
            "contrast_luminance_threshold": 0.52,
            "contrast_light_color": "#FFFFFF",
            "contrast_dark_color": "#1F1F1F",
            "secondary_color": "#333333",
            "muted_color": "#666666",
        },
        "HEATMAP_STYLE": {
            "bad_color": "#F2F2F2",
            "annot_light_text_color": "#FFFFFF",
            "annot_dark_text_color": "#000000",
            "annot_luminance_threshold": 0.60,
            "annot_fontsize": 8,
            "nan_text_color": "#666666",
            "colorbar_fraction": 0.045,
            "colorbar_pad": 0.02,
        },
        "TASK_STYLE": {
            "colors": {
                1: "#4878CF",
                2: "#6ACC65",
                3: "#D65F5F",
            },
            "labels": {
                1: "Type-1 (Low value)",
                2: "Type-2 (Med value)",
                3: "Type-3 (High value)",
            },
            "default_color": "#AAAAAA",
            "title_fallback_color": "#333333",
        },
        "RESOURCE_STYLE": {
            "colors": ["#4E79A7", "#F28E2B", "#59A14F", "#E15759", "#76B7B2", "#EDC948"],
        },
        "FIGURE_CONFIG": {
            "fig5a": {
                "show_title": False,
                "suptitle": "Fig. 5a - Resource Allocation per Task (SC matrix)",
                "max_ncols": 4,
                "subplot_w_cm": 6.60,
                "subplot_h_cm": 5.59,
                "colorbar_extra_w_cm": 1.20,
                "plain_extra_w_cm": 0.00,
                "cmap": "Blues",
                "shared_vmax": True,
                "show_colorbar": True,
                "xlabel": "Resource",
                "ylabel": "Robot",
                "cell_annot": False,
                "cell_fontsize": 7,
                "subplot_title_color": "#000000",
                "subplot_title_pad": 3,
                "subplot_hspace": 0.55,
                "subplot_wspace": 0.35,
                "colorbar_fraction": 0.045,
                "colorbar_pad": 0.03,
                "colorbar_label": "Allocated resource",
                "suptitle_y": 0.985,
            },
            "fig5b": {
                "show_title": False,
                "title": "Fig. 5b - Robot Task Execution Gantt",
                "xlabel": "Time",
                "ylabel": "Robot",
                "color_mode": "task_id_light",
                "show_legend": False,
                "uniform_task_color": "#2F2F2F",
                "task_default_color": "#DCE7F5",
                "task_id_colors": {},
                "bar_height": 0.45,
                "bar_linewidth": 0.8,
                "label_min_width": 8.0,
                "show_task_id_label": True,
                "task_label_fontweight": "bold",
                "task_label_color": "#333333",
                "show_value_legend": False,
                "legend_label": "Tasks",
                "legend_loc": "lower right",
                "legend_ncol": 1,
                "value_legend_mode": "compact",
                "value_shade_order": "high_darker",
                "task_hue_offset": 0.08,
                "task_color_saturation": 0.32,
                "task_color_lightness": 0.82,
                "task_edge_darken_delta": -0.12,
                "value_lightness_min": 0.42,
                "value_lightness_max": 0.78,
                "value_legend_hue": 0.58,
                "label_fontsize": 7,
                "max_fig_width_cm": 45.72,
                "min_fig_width_cm": 20.32,
                "time_per_cm": 15.75,
                "min_fig_height_cm": 8.89,
                "per_agent_height_cm": 1.40,
                "base_fig_height_cm": 2.54,
                "xlim_expand_ratio": 0.03,
            },
            "fig5c": {
                "show_title": True,
                "title": "Fig. 5c - Total Allocated Resource per Task",
                "xlabel": "Resource",
                "ylabel": "Task",
                "cmap": "YlGnBu",
                "annot": True,
                "value_fmt": "{:.0f}",
                "colorbar_label": "Total allocated resource",
            },
            "fig5d": {
                "show_title": False,
                "title": "Fig. 5d - Allocated Minus Demand per Task",
                "xlabel": "Resource Type",
                "ylabel": "Task",
                "cmap": "RdBu_r",
                "annot": True,
                "value_fmt": "{:+.0f}",
                "show_colorbar": False,
                "colorbar_label": "Allocated - Demand",
                "figsize_in_with_colorbar": (4.15, 3.5),
                "colorbar_axes_width_ratio": 0.12,
                "colorbar_axes_pad_ratio": 0.05,
                "center_value": 0.0,
            },
            "fig5e": {
                "show_title": True,
                "title": "Fig. 5e - Allocation-to-Demand Ratio per Task",
                "xlabel": "Resource",
                "ylabel": "Task",
                "cmap": "RdYlGn",
                "annot": True,
                "value_fmt": "{:.0%}",
                "nan_text": "",
                "colorbar_label": "Allocated / Demand",
                "center_value": 1.0,
                "vmin": 0.0,
                "vmax": 1.5,
                "bar_edgecolor": "#FFFFFF",
                "bar_linewidth": 0.6,
                "completion_text_color": "#333333",
                "completion_text_offset_ratio": 0.02,
                "completion_text_min_offset": 0.4,
                "role_demand_facecolor": "#FFFFFF",
                "role_demand_edgecolor": "#666666",
                "role_alloc_facecolor": "#666666",
                "role_alloc_edgecolor": "#666666",
                "role_demand_label": "Demand",
                "role_alloc_label": "Allocated",
                "role_legend_title": "Bar type",
                "role_legend_loc": "upper left",
                "resource_legend_title": "Resource",
                "resource_legend_loc": "upper right",
                "resource_legend_ncols_max": 3,
            },
            "fig5f": {
                "show_title": True,
                "title": "Fig. 5f - True Resource Demand per Task",
                "xlabel": "Resource",
                "ylabel": "Task",
                "cmap": "Oranges",
                "annot": True,
                "value_fmt": "{:.0f}",
                "colorbar_label": "Task demand",
            },
            "fig5g": {
                "show_title": True,
                "title": "Fig. 5g - Initial Robot and Task Layout",
                "xlabel": "X Coordinate",
                "ylabel": "Y Coordinate",
                "xlim": [-5, 110],
                "ylim": [-5, 110],
                "show_legend": True,
                "legend_loc": "upper right",
                "legend_ncol": 1,
                "aspect_equal": True,
                "agent_palette": ["#4878CF", "#6ACC65", "#D65F5F", "#B47CC7", "#C4AD66", "#77BEDB"],
                "agent_edgecolor": "#1F1F1F",
                "agent_marker": "o",
                "agent_markersize": 58,
                "agent_scatter_linewidth": 0.9,
                "agent_legend_label": "Robots",
                "task_marker": "*",
                "task_markersize": 68,
                "task_color": "#2F2F2F",
                "task_edgecolor": "#202020",
                "task_scatter_linewidth": 0.9,
                "task_legend_label": "Tasks",
                "annotate_agents": True,
                "annotate_tasks": True,
                "annotation_fontsize": 7,
                "annotation_dx": 0.8,
                "annotation_dy": 0.8,
                "x_margin_ratio": 0.05,
                "y_margin_ratio": 0.05,
            },
            "fig5h": {
                "show_title": False,
                "suptitle": "Fig. 5h - Belief-Implied Task Value Convergence",
                "xlabel": "Round",
                "ylabel": "Expected Task Value",
                "left_zero": True,
                "ncols": 4,
                "subplot_w_cm": 4.50,
                "subplot_h_cm": 5.00,
                "use_fixed_export_margins": False,
                "use_shared_ylabel": True,
                "shared_ylabel_text": "Expected Task Value",
                "shared_ylabel_x": 0.020,
                "show_legend": True,
                "legend_container": "axes",
                "legend_subplot_index": "last_active",
                "legend_loc": "upper center",
                "legend_ncol": 1,
                "subplot_title_pad": 4,
                "subplot_title_color": "#000000",
                "xlabel_pad": 1.5,
                "estimate_label": "Estimated value",
                "true_line_label": "True value",
                "curve_color": "#555B9C",
                "curve_linestyle": "-",
                "curve_marker": "o",
                "curve_markerfacecolor": "#555B9C",
                "curve_markeredgewidth": 1.2,
                "curve_markevery_step": 10,
                "curve_marker_rounds": None,
                "curve_markevery": None,
                "true_line_color": "#222222",
                "true_line_style": "--",
                "true_line_width": 1.2,
                "legend_bbox_to_anchor": (0.5, 0.995),
                "suptitle_y": 0.985,
                "subplots_adjust_left": 0.085,
                "subplots_adjust_right": 0.985,
                "subplots_adjust_bottom": 0.115,
                "subplots_adjust_top": 0.955,
                "subplot_hspace": 0.75,
                "subplot_wspace": 0.28,
            },
            "fig5i": {
                "show_title": True,
                "title": "Fig. 5i - Belief Value Error Convergence",
                "xlabel": "Round",
                "ylabel": "Mean Absolute Value Error",
                "left_zero": True,
                "show_legend": True,
                "legend_loc": "upper right",
                "legend_ncol": 1,
                "bottom_zero": True,
                "prepend_origin_zero": True,
                "curve_label": "Mean abs. value error",
                "curve_color": "#A65F2A",
                "curve_linestyle": "-",
                "curve_marker": "o",
                "curve_markerfacecolor": "#A65F2A",
                "curve_markeredgewidth": 1.2,
                "curve_markevery_step": 5,
                "curve_marker_rounds": None,
            },
            "fig5j": {
                "show_title": True,
                "title": "Fig. 5j - Coalition Utility Convergence",
                "xlabel": "Round",
                "ylabel": "Coalition Utility",
                "left_zero": True,
                "show_legend": True,
                "legend_loc": "best",
                "legend_ncol": 1,
                "bottom_zero": True,
                "prepend_origin_zero": True,
                "curve_color": "#555B9C",
                "curve_linestyle": "-",
                "curve_marker": "o",
                "curve_markerfacecolor": "#555B9C",
                "curve_markeredgewidth": 1.2,
                "curve_markevery_step": 5,
                "curve_marker_rounds": None,
            },
            "fig5k": {
                "show_title": True,
                "title": "Fig. 5k - Total Global Cost Convergence",
                "xlabel": "Round",
                "ylabel": "Total Global Cost",
                "left_zero": True,
                "show_legend": True,
                "legend_loc": "best",
                "legend_ncol": 1,
                "bottom_zero": True,
                "prepend_origin_zero": True,
                "curve_color": "#B25E24",
                "curve_linestyle": "-",
                "curve_marker": "o",
                "curve_markerfacecolor": "#B25E24",
                "curve_markeredgewidth": 1.2,
                "curve_markevery_step": 5,
                "curve_marker_rounds": None,
            },
            "fig5l": {
                "show_title": True,
                "title": "Fig. 5l - Total Completed Value Convergence",
                "xlabel": "Round",
                "ylabel": "Total Completed Value",
                "left_zero": True,
                "show_legend": True,
                "legend_loc": "best",
                "legend_ncol": 1,
                "bottom_zero": True,
                "prepend_origin_zero": True,
                "curve_color": "#2F7F5F",
                "curve_linestyle": "-",
                "curve_marker": "o",
                "curve_markerfacecolor": "#2F7F5F",
                "curve_markeredgewidth": 1.2,
                "curve_markevery_step": 5,
                "curve_marker_rounds": None,
            },
            "fig5m": {
                "show_title": False,
                "title": "Fig. 5m - Combined Convergence Curves",
                "xlabel": "Round",
                "ylabel": "Metric Value",
                "utility_curve_label": "Coalition Utility",
                "cost_curve_label": "Total Global Cost",
                "completed_value_curve_label": "Total Completed Value",
                "left_zero": True,
                "bottom_zero": True,
                "show_legend": True,
                "legend_loc": "lower right",
                "legend_ncol": 1,
                 "ylim": [-1000, 8200],
            },
            "fig5n": {
                "show_title": False,
                "title": "Fig. 5n - Scheduled Path Map",
                "xlabel": "X-axis",
                "ylabel": "Y-axis",
                "xlim": [-5, 110],
                "ylim": [-5, 110],
                "show_legend": True,
                "show_path_legend": True,
                "legend_loc": "upper right",
                "legend_ncol": 1,
                "aspect_equal": True,
                "agent_palette": ["#4878CF", "#6ACC65", "#D65F5F", "#B47CC7", "#C4AD66", "#77BEDB"],
                "agent_edgecolor": "#1F1F1F",
                "agent_marker": "o",
                "agent_markersize": 58,
                "agent_scatter_linewidth": 0.9,
                "agent_legend_label": "Robots",
                "task_marker": "*",
                "task_markersize": 68,
                "task_color": "#2F2F2F",
                "task_edgecolor": "#202020",
                "task_scatter_linewidth": 0.9,
                "task_legend_label": "Tasks",
                "annotate_agents": True,
                "annotate_tasks": True,
                "annotation_fontsize": 7,
                "annotation_dx": 0.8,
                "annotation_dy": 0.8,
                "x_margin_ratio": 0.05,
                "y_margin_ratio": 0.05,
                "path_style": "arrow",
                "path_linestyle": "--",
                "path_linewidth": 1.2,
                "path_alpha": 0.85,
                "path_arrowstyle": "-|>",
                "arrow_scale": 10,
            },
        },
    },

    "convergence_detail": {
        "OUTPUT_PREFIX": OUTPUT_PREFIX["convergence_detail"],
        "PLOT_GLOBAL": {
            "linewidth": 3.0,
            "markersize": 4.0,
            "markeredgewidth": 0.8,
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
            "save_formats": ["png", "eps"],
            "save_dpi": 150,
            "save_bbox_inches": "tight",
            "tight_layout": True,
        },
        "ALG_STYLE": {
            "Huo2025": dict(color="#4878CF", marker="o", ls="-", label=ALG_DISPLAY_NAMES["Huo2025"]),
            "Qi2023": dict(color="#6ACC65", marker="s", ls="--", label=ALG_DISPLAY_NAMES["Qi2023"]),
            "Shi2024": dict(color="#D65F5F", marker="^", ls="-.", label=ALG_DISPLAY_NAMES["Shi2024"]),
            "OCF_SAtabu": dict(color="#B47CC7", marker="D", ls="-", label=ALG_DISPLAY_NAMES["OCF_SAtabu"]),
        },
        "DEFAULT_STYLE": dict(color="#888888", marker="x", ls=":", label="Unknown"),
        "CURVE_DETAIL_STYLE": {
            "show_mean_band": True,
            "band_alpha": 0.16,
            "markevery_divisor": 10,
            "markevery_threshold": 12,
        },
        "METRIC_SPECS": {
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
        },
        "FIGURE_CONFIG": {
            "detail_curve": {
                "show_title": True,
                "xlabel": "Round",
                "ylabel": "Value",
            },
        },
    },
}


def _deep_merge(base, override):
    """递归合并两个字典，并使用深拷贝语义。

    这样做可以避免运行期对某个合并结果的修改，反过来污染
    COMMON_CONFIG 或 FAMILY_CONFIG 里的共享模板。
    """

    result = copy.deepcopy(base)
    for key, value in override.items():
        if isinstance(value, dict) and isinstance(result.get(key), dict):
            result[key] = _deep_merge(result[key], value)
        else:
            result[key] = copy.deepcopy(value)
    return result


def _apply_typography_fallbacks(cfg):
    """Populate optional typography keys from semantic global defaults."""
    resolved = copy.deepcopy(cfg)
    fallback_pairs = (
        ("subplot_title_fontsize", "title_fontsize"),
        ("legend_title_fontsize", "legend_fontsize"),
        ("colorbar_label_fontsize", "ylabel_fontsize"),
        ("colorbar_tick_fontsize", "tick_fontsize"),
    )
    for key, fallback_key in fallback_pairs:
        if resolved.get(key) is None:
            resolved[key] = resolved.get(fallback_key)
    return resolved


def get_family_plot_config(family):
    """返回某个 plot family 最终可直接使用的合并配置。

    绘图脚本中的典型用法：
    - `cfg = get_family_plot_config("varyN")`
    - 从 `cfg["PLOT_GLOBAL"]` 读取公共样式
    - 从 `cfg["FIGURE_CONFIG"]` 读取逐图元数据
    - 如果该 family 定义了局部样式，还可以继续读取
      `cfg["BAR_CHART_STYLE"]`、`cfg["COMBO_CHART_STYLE"]`、
      `cfg["INNER_LOOP_STYLE"]`
    """

    family_key = str(family)
    if family_key not in FAMILY_CONFIG:
        raise KeyError(f"Unknown plot family: {family_key}")
    cfg = _deep_merge(COMMON_CONFIG, FAMILY_CONFIG[family_key])
    cfg = _apply_alg_display_labels(cfg)
    cfg.setdefault("PLOT_GLOBAL", {})
    cfg["PLOT_GLOBAL"] = _apply_typography_fallbacks(cfg["PLOT_GLOBAL"])
    cfg.setdefault("FIGURE_CONFIG", {})
    return cfg


def get_family_section(family, section, default=None):
    """Return a deep-copied family section."""
    family_cfg = get_family_plot_config(family)
    if section in family_cfg:
        return copy.deepcopy(family_cfg[section])
    return copy.deepcopy(default)


def get_family_figure_config(family, fig_key, **overrides):
    """Return the final config for one figure with global fallback."""
    family_cfg = get_family_plot_config(family)
    plot_global = family_cfg.get("PLOT_GLOBAL", {})
    figure_cfg = family_cfg.get("FIGURE_CONFIG", {}).get(fig_key, {})
    cfg = _deep_merge(plot_global, figure_cfg)
    if overrides:
        cfg = _deep_merge(cfg, overrides)
    cfg = _apply_typography_fallbacks(cfg)
    cfg["family"] = str(family)
    cfg["figure_key"] = str(fig_key)
    return cfg


def build_prefixed_stem(family, stem):
    """给输出 stem 自动补上 family 前缀。"""

    prefix = OUTPUT_PREFIX.get(str(family), str(family))
    stem_text = str(stem)
    if stem_text.startswith(f"{prefix}_"):
        return stem_text
    return f"{prefix}_{stem_text}"


def get_alg_plot_style(aname, alg_style, default_style, plot_global):
    """把某个算法样式整理成折线图直接可用的格式。

    输入含义：
    - `aname`：算法名，例如 "OCF_SAtabu"
    - `alg_style`：样式表，通常就是 cfg["ALG_STYLE"]
    - `default_style`：兜底样式
    - `plot_global`：合并后的 PLOT_GLOBAL，用来提供线宽、marker 大小等
      缺省值

    返回值里的字段已经整理成大多数绘图调用直接可用的名字，例如
    `linewidth`、`markersize`、marker face/edge color 等。
    """

    base = alg_style.get(aname, default_style)
    color = base.get("color", default_style["color"])
    return {
        "color": color,
        "marker": base.get("marker", default_style["marker"]),
        "ls": base.get("ls", default_style["ls"]),
        "linewidth": base.get("lw", plot_global["linewidth"]),
        "markersize": base.get("ms", plot_global["markersize"]),
        "markerfacecolor": base.get("mfc", color),
        "markeredgecolor": base.get("mec", color),
        "markeredgewidth": base.get("mew", plot_global["markeredgewidth"]),
        "label": get_alg_display_name(aname),
    }


def get_bar_plot_style(aname, alg_style, default_style):
    """提取分组柱状图真正需要的最小样式集合。

    柱状图通常只关心填充颜色和图例标签，因此这里会把折线图专用的
    marker、线型等字段剥离掉。
    """

    base = alg_style.get(aname, default_style)
    return {
        "color": base.get("color", default_style["color"]),
        "label": get_alg_display_name(aname),
    }


def get_bar_layout(bar_chart_style, num_algs):
    """计算分组柱状图中所有算法的柱宽和横向偏移。

    Returns
    -------
    (bar_width, offsets)
        `bar_width`：单个柱子的宽度。
        `offsets`：以 0 为中心的对称偏移数组，用来把不同算法的柱子
        摆在同一组名义 x 位置的左右两侧。
    """

    bar_width = float(bar_chart_style.get("bar_width", 0.34))
    use_bar_spacing = bool(bar_chart_style.get("use_bar_spacing", True))
    offset_step = float(bar_chart_style.get("bar_offset_step", bar_width))
    if not use_bar_spacing:
        offset_step = bar_width
    offsets = (np.arange(num_algs) - (num_algs - 1) / 2.0) * offset_step
    return bar_width, offsets


def compute_error_values(values_2d, mode="std"):
    """从二维指标矩阵中计算误差棒数值。

    Parameters
    ----------
    values_2d:
        期望形状为 [x_points, seeds]。
    mode:
        支持以下模式：
        - "std"：标准差
        - "sem"：均值标准误
        - "ci95"：基于 1.96 * sem 的 95% 置信区间

    Returns
    -------
    (error_values, normalized_mode, std)
        error_values:
            实际传给绘图逻辑的误差棒数值。
        normalized_mode:
            归一化为小写后的模式字符串。
        std:
            原始标准差，方便调用方在绘图之外继续导出统计量。
    """

    error_mode = str(mode or "std").lower()
    std = np.nanstd(values_2d, axis=1)

    if error_mode == "std":
        return std, error_mode, std

    valid_counts = np.sum(~np.isnan(values_2d), axis=1).astype(float)
    sem = np.divide(
        std,
        np.sqrt(valid_counts),
        out=np.full_like(std, np.nan, dtype=float),
        where=valid_counts > 0,
    )

    if error_mode == "sem":
        return sem, error_mode, std
    if error_mode == "ci95":
        return 1.96 * sem, error_mode, std

    raise ValueError(
        f"Unsupported errorbar mode: {mode}; expected 'std', 'sem', or 'ci95'"
    )
