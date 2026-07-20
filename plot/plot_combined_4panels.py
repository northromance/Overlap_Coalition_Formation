"""
plot_combined_4panels.py
========================
将四个已有子图横向排列为论文组合大图（1×4 布局）：

  Panel 1 (左一): varyM fig1f  — M=?~? 效用分组柱状图
  Panel 2 (左二): varyM fig1d  — M=?~? 任务完成度折线图
  Panel 3 (左三): varyN fig1d bars only — N=?~? 效用柱状图（无右轴完成率线）
  Panel 4 (左四): varyN fig1b  — N=?~? 任务完成度折线图

布局参照: single_show/plot_single.py::plot_fig5hm_belief_and_convergence（双图扩展为四图）
字体/图例: 参照 single_show/plot_unified_config.py::fig5hm 面板设置

用法:
  python plot_combined_4panels.py          # 自动搜索最新结果
  修改脚本顶部 VARYM_PREFERRED_INPUT / VARYN_MAT_PATH 可指定输入
"""

import os
import sys
import glob
import numpy as np
import matplotlib.pyplot as plt
import matplotlib.ticker as mticker

from plot_unified_config import (
    get_family_plot_config,
    get_family_figure_config,
    get_alg_plot_style   as _resolve_alg_style,
    get_bar_layout       as _resolve_bar_layout,
    get_bar_plot_style   as _resolve_bar_style,
    compute_error_values as _compute_errors,
)
from plot_style_helper import (
    PlotStyleHelper,
    cm_size_to_inch,
    build_results_figures_dir,
)
from varym_result_aggregator import VaryMResultAggregator

try:
    import mat73
except ImportError:
    sys.exit("缺少依赖，请先执行: pip install mat73")


# ══════════════════════════════════════════════════════════════════════════════
# 路径配置（按需修改）
# ══════════════════════════════════════════════════════════════════════════════
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
ROOT_DIR   = os.path.dirname(SCRIPT_DIR)

# varyM 输入：运行目录名（在 results/batch/varyM/ 下）、完整路径、或 None（自动选最新）
VARYM_PREFERRED_INPUT = '20260329_190314_N8_M8-20_K6_S11'
VARYM_SEARCH_DIRS = [
    os.path.join(ROOT_DIR, 'results', 'batch', 'varyM'),
    os.path.join(ROOT_DIR, 'results', 'batch'),
]

# varyN 输入：.mat 文件完整路径，或 None（自动搜索最新）
VARYN_MAT_PATH = None
VARYN_SEARCH_DIRS = [
    os.path.join(ROOT_DIR, 'results', 'batch', 'varyN'),
    os.path.join(ROOT_DIR, 'results', 'batch'),
]

# 输出目录和文件名主干（不含扩展名）
OUTPUT_DIR  = build_results_figures_dir(ROOT_DIR, 'combined_4panels')
OUTPUT_STEM = 'combined_4panels'


# ══════════════════════════════════════════════════════════════════════════════
# 组合图版面参数（参照 single_show/plot_unified_config.py 中的 fig5hm）
# ══════════════════════════════════════════════════════════════════════════════

# 整体图尺寸：fig5hm 双图为 (8.89, 4.70) cm → 四图横向扩展为约两倍宽
FIGSIZE_CM = (17.78, 4.9)

# 子图间距
SUBPLOTS_ADJUST = dict(
    left=0.055,
    right=0.985,
    bottom=0.205,
    top=0.850,
    wspace=0.2,
)

# 字体与图例覆盖（匹配 fig5hm 的 left_panel / right_panel 设置）
PANEL_STYLE = {
    "xlabel_fontsize":      8,
    "ylabel_fontsize":      8,
    "tick_fontsize":        6,
    "title_fontsize":       7,   # ← 改这里调图题字号
    "title_pad":            3,   # ← 图题与图之间的间距（pt）
    "show_legend":          True,
    "legend_fontsize":      6,
    "legend_ncol":          1,
    "legend_handlelength":  1.2,
    "legend_labelspacing":  0.25,
    "legend_borderaxespad": 0.25,
    "show_title":           True,   # 各子图单独开启标题
    "show_titles":          True,
    "axes_box_aspect":      None,   # 不强制正方形子图
}


# ══════════════════════════════════════════════════════════════════════════════
# 加载各 family 配置
# ══════════════════════════════════════════════════════════════════════════════
_M_cfg = get_family_plot_config('varyM')
_N_cfg = get_family_plot_config('varyN')

_M_ALG  = _M_cfg['ALG_STYLE']
_M_DEF  = _M_cfg['DEFAULT_STYLE']
_M_GLOB = _M_cfg['PLOT_GLOBAL']
_M_BAR  = _M_cfg['BAR_CHART_STYLE']

_N_ALG   = _N_cfg['ALG_STYLE']
_N_DEF   = _N_cfg['DEFAULT_STYLE']
_N_GLOB  = _N_cfg['PLOT_GLOBAL']
_N_COMBO = _N_cfg['COMBO_CHART_STYLE']

_M_helper = PlotStyleHelper(_M_GLOB)
_N_helper = PlotStyleHelper(_N_GLOB)


def _m_fig_cfg(fig_key):
    """返回 varyM 某图的最终配置，并叠加面板样式覆盖。"""
    return {**get_family_figure_config('varyM', fig_key), **PANEL_STYLE}


def _n_fig_cfg(fig_key):
    """返回 varyN 某图的最终配置，并叠加面板样式覆盖。"""
    return {**get_family_figure_config('varyN', fig_key), **PANEL_STYLE}


# ══════════════════════════════════════════════════════════════════════════════
# 数据加载
# ══════════════════════════════════════════════════════════════════════════════

def _to_scalar(val):
    if val is None:
        return np.nan
    arr = np.asarray(val, dtype=float).ravel()
    return float(arr[0]) if len(arr) > 0 else np.nan


def _iter_results(results):
    if isinstance(results, np.ndarray) and results.ndim == 2:
        for ri in range(results.shape[0]):
            for ci in range(results.shape[1]):
                yield ri, ci, results[ri, ci]
    elif isinstance(results, list):
        for ri, row in enumerate(results):
            if isinstance(row, list):
                for ci, entry in enumerate(row):
                    yield ri, ci, entry
            else:
                yield ri, 0, row
    else:
        yield 0, 0, results


def _get_shape(results):
    if isinstance(results, np.ndarray) and results.ndim == 2:
        return results.shape
    if isinstance(results, list):
        nr = len(results)
        nc = len(results[0]) if results and isinstance(results[0], list) else 1
        return nr, nc
    return 1, 1


def _parse_alg_names(config):
    raw = config.get('alg_names', [])
    if isinstance(raw, str):
        return [raw]
    if isinstance(raw, np.ndarray):
        return [str(v) for v in raw.ravel()]
    return [str(v) for v in raw]


def _extract_metrics(results, alg_names):
    """通用指标提取（utility / completion / completed_value / cost）。"""
    nX, nS  = _get_shape(results)
    metrics = {
        a: {k: np.full((nX, nS), np.nan)
            for k in ('utility', 'completion', 'completed_value', 'cost')}
        for a in alg_names
    }
    for xi, si, entry in _iter_results(results):
        if not entry or not entry.get('success', False):
            continue
        algs_data = entry.get('algs', {}) or {}
        for aname in alg_names:
            ae = algs_data.get(aname)
            if not ae or not ae.get('success', False):
                continue
            metrics[aname]['utility'][xi, si]        = _to_scalar(ae.get('final_utility'))
            metrics[aname]['completion'][xi, si]      = _to_scalar(ae.get('final_completion'))
            metrics[aname]['completed_value'][xi, si] = _to_scalar(ae.get('final_completed_value'))
            metrics[aname]['cost'][xi, si]            = _to_scalar(ae.get('final_cost'))
    return metrics


def _resolve_varym_input(selector):
    """将运行目录名/路径字符串解析为真实路径（仿 plot_varyM_top_config.resolve_input_selector）。"""
    if not selector:
        return None
    selector = str(selector).strip()
    for candidate in (os.path.abspath(selector),
                      os.path.abspath(os.path.join(ROOT_DIR, selector))):
        if os.path.exists(candidate):
            return candidate
    matches = []
    for search_dir in VARYM_SEARCH_DIRS:
        if not os.path.isdir(search_dir):
            continue
        direct = os.path.join(search_dir, selector)
        if os.path.exists(direct):
            matches.append(os.path.abspath(direct))
        for p in glob.glob(os.path.join(search_dir, '**', selector), recursive=True):
            if os.path.basename(os.path.normpath(p)) == selector:
                matches.append(os.path.abspath(p))
    matches = sorted(set(matches))
    if len(matches) == 1:
        return matches[0]
    if len(matches) > 1:
        raise FileNotFoundError(f'多个目录匹配 "{selector}"，请使用完整路径: {matches}')
    raise FileNotFoundError(
        f'找不到 varyM 运行目录 "{selector}"，请检查 VARYM_PREFERRED_INPUT 或 VARYM_SEARCH_DIRS。'
    )


def load_varyM(input_path=None):
    """加载 varyM 数据，返回 (M_values, alg_names, metrics)。"""
    resolved = _resolve_varym_input(input_path) if input_path else None
    aggregator = VaryMResultAggregator(search_dirs=VARYM_SEARCH_DIRS)
    results, config, run_meta = aggregator.load_results(input_path=resolved)
    print(f'  [varyM] {run_meta.get("source_path", "")}')
    M_values  = list(np.asarray(config['M_values'], dtype=int).ravel())
    alg_names = _parse_alg_names(config)
    metrics   = _extract_metrics(results, alg_names)
    return M_values, alg_names, metrics


def load_varyN(mat_path):
    """从 .mat 文件加载 varyN 数据，返回 (N_values, alg_names, metrics)。"""
    raw     = mat73.loadmat(mat_path)
    results = raw['scale_N_results']
    config  = raw['scale_config']
    print(f'  [varyN] {mat_path}')
    N_values  = list(np.asarray(config['N_values'], dtype=int).ravel())
    alg_names = _parse_alg_names(config)
    metrics   = _extract_metrics(results, alg_names)
    return N_values, alg_names, metrics


def _find_varyn_mat():
    """找最新 varyN .mat 文件（或使用 VARYN_MAT_PATH）。"""
    if VARYN_MAT_PATH and os.path.isfile(VARYN_MAT_PATH):
        return VARYN_MAT_PATH
    if VARYN_MAT_PATH:
        print(f'  警告: VARYN_MAT_PATH 不存在 "{VARYN_MAT_PATH}"，自动搜索。')
    candidates = []
    for d in VARYN_SEARCH_DIRS:
        candidates.extend(glob.glob(os.path.join(d, '*.mat')))
    pool = [f for f in candidates if 'varyN' in os.path.basename(f)] or candidates
    if not pool:
        sys.exit('找不到 varyN .mat 文件，请设置 VARYN_MAT_PATH。')
    chosen = max(pool, key=os.path.getmtime)
    print(f'  自动选择 varyN: {chosen}')
    return chosen


def _get_selected_n_indices(all_n_values, selected_n_values):
    index_map = {int(n): idx for idx, n in enumerate(all_n_values)}
    missing   = [n for n in selected_n_values if int(n) not in index_map]
    if missing:
        raise ValueError(f'组合图所需 N 值缺失: {missing}；当前 N = {list(all_n_values)}')
    return [index_map[int(n)] for n in selected_n_values]


# ══════════════════════════════════════════════════════════════════════════════
# 面板绘图函数（各接受预创建的 ax，不自建 figure）
# ══════════════════════════════════════════════════════════════════════════════

def _apply_sci_yaxis(ax, cfg, power=3):
    """将 y 轴格式化为整数刻度 + ×10^power 偏移标签（仿 plot_ablation._apply_scientific_utility_ticks）。"""
    formatter = mticker.ScalarFormatter(useMathText=True)
    formatter.set_scientific(True)
    formatter.set_powerlimits((power, power))
    formatter.set_useOffset(False)
    ax.yaxis.set_major_formatter(formatter)
    ax.ticklabel_format(axis='y', style='sci', scilimits=(power, power), useMathText=True)
    offset_text = ax.yaxis.get_offset_text()
    tick_fs = cfg.get('tick_fontsize')
    if tick_fs is not None:
        offset_text.set_fontsize(tick_fs)
    font_family = cfg.get('font_family')
    if font_family:
        offset_text.set_fontfamily(font_family)
    font_style = cfg.get('font_style')
    if font_style:
        offset_text.set_fontstyle(font_style)

def _draw_varyM_utility_bar(ax, M_values, alg_names, metrics):
    """Panel 1: varyM fig1f — 效用分组柱状图（仿 plot_grouped_bar_vs_M）。"""
    cfg       = _m_fig_cfg('fig1f')
    cfg['title'] = 'FU'
    cfg['ylabel'] = ''
    x_centers = np.arange(len(M_values), dtype=float)
    bar_width, offsets = _resolve_bar_layout(_M_BAR, len(alg_names))
    show_eb   = bool(cfg.get('show_errorbar', True))
    eb_mode   = str(cfg.get('errorbar_mode', 'std')).lower()
    show_edge = bool(_M_BAR.get('show_bar_edge', False))
    edgecol   = _M_BAR.get('bar_edgecolor', '#000000') if show_edge else 'none'
    edgew     = float(_M_BAR.get('bar_edgewidth', 0.0)) if show_edge else 0.0

    for idx, aname in enumerate(alg_names):
        st   = _resolve_bar_style(aname, _M_ALG, _M_DEF)
        vals = metrics[aname]['utility']
        mu   = np.nanmean(vals, axis=1)
        err, eb_mode, _ = _compute_errors(vals, eb_mode)
        ax.bar(
            x_centers + offsets[idx], mu,
            width=bar_width,
            yerr=err if show_eb else None,
            color=st['color'],
            alpha=_M_BAR.get('bar_alpha', 0.8),
            edgecolor=edgecol, linewidth=edgew,
            label=st['label'], zorder=3,
            error_kw=dict(
                ecolor=     _M_BAR.get('errorbar_color', '#000000'),
                elinewidth= _M_BAR.get('errorbar_linewidth', 0.5),
                capsize=    _M_GLOB['capsize'],
                capthick=   _M_BAR.get('errorbar_capthick', 0.3),
            ),
        )

    _M_helper.apply_axis_controls(ax, cfg=cfg, fixed_values=x_centers,
                                  fixed_locator_key='use_fixed_M_xticks')
    ax.set_xticklabels([str(int(m)) for m in M_values])
    _M_helper.apply_common_style(ax, cfg=cfg)
    _apply_sci_yaxis(ax, cfg)


def _draw_varyM_completion(ax, M_values, alg_names, metrics):
    """Panel 2: varyM fig1d — 任务完成度折线图（仿 _plot_scalar_vs_M）。"""
    cfg = _m_fig_cfg('fig1d')
    cfg['title'] = 'CR'
    cfg['ylabel'] = ''
    for aname in alg_names:
        st  = _resolve_alg_style(aname, _M_ALG, _M_DEF, _M_GLOB)
        mu  = np.nanmean(metrics[aname]['completion'], axis=1)
        std = np.nanstd(metrics[aname]['completion'], axis=1)
        if _M_GLOB.get('show_errorbar_varyM', False):
            ax.errorbar(M_values, mu, yerr=std,
                color=st['color'], marker=st['marker'], ls=st['ls'],
                lw=st['linewidth'], ms=st['markersize'],
                markerfacecolor=st['markerfacecolor'],
                markeredgecolor=st['markeredgecolor'],
                markeredgewidth=st['markeredgewidth'],
                capsize=_M_GLOB['capsize'], label=st['label'], zorder=3)
        else:
            ax.plot(M_values, mu,
                color=st['color'], marker=st['marker'], ls=st['ls'],
                lw=st['linewidth'], ms=st['markersize'],
                markerfacecolor=st['markerfacecolor'],
                markeredgecolor=st['markeredgecolor'],
                markeredgewidth=st['markeredgewidth'],
                label=st['label'], zorder=3)
    _M_helper.apply_axis_controls(ax, cfg=cfg, fixed_values=M_values,
                                  fixed_locator_key='use_fixed_M_xticks')
    _M_helper.apply_common_style(ax, cfg=cfg)
    _apply_sci_yaxis(ax, cfg, power=-1)


def _draw_varyN_utility_bar(ax, N_values, alg_names, metrics):
    """Panel 3: varyN fig1d bars only — 效用柱状图，无右轴完成率线（仿 plot_dual_axis_combo）。"""
    cfg         = _n_fig_cfg('fig1d')
    cfg['title'] = 'FU'
    cfg['ylabel'] = ''
    sel_n       = _N_COMBO['selected_n_values']
    sel_indices = _get_selected_n_indices(N_values, sel_n)
    sel_n_disp  = [N_values[i] for i in sel_indices]
    x_centers   = np.arange(len(sel_n_disp), dtype=float)
    show_eb     = bool(cfg.get('show_errorbar', True))
    eb_mode     = str(cfg.get('errorbar_mode', 'std')).lower()
    num_algs    = len(alg_names)
    bar_width   = _N_COMBO['bar_width']
    offset_step = (
        _N_COMBO.get('bar_offset_step', bar_width)
        if _N_COMBO.get('use_bar_spacing', True)
        else bar_width
    )
    show_edge = bool(_N_COMBO.get('show_bar_edge', False))
    edgecol   = _N_COMBO['bar_edgecolor'] if show_edge else 'none'
    edgew     = _N_COMBO['bar_edgewidth']  if show_edge else 0.0
    offsets   = (np.arange(num_algs, dtype=float) - (num_algs - 1) / 2.0) * offset_step

    for alg_idx, aname in enumerate(alg_names):
        st   = _resolve_bar_style(aname, _N_ALG, _N_DEF)
        vals = metrics[aname]['utility'][sel_indices, :]
        mu   = np.nanmean(vals, axis=1)
        err, eb_mode, _ = _compute_errors(vals, eb_mode)
        ax.bar(
            x_centers + offsets[alg_idx], mu,
            width=bar_width,
            color=st['color'],
            alpha=_N_COMBO['bar_alpha'],
            edgecolor=edgecol, linewidth=edgew,
            yerr=err if show_eb else None,
            error_kw=dict(
                ecolor=     _N_COMBO['errorbar_color'],
                elinewidth= _N_COMBO['errorbar_linewidth'],
                capsize=    _N_GLOB['capsize'],
                capthick=   _N_COMBO['errorbar_capthick'],
            ),
            label=st['label'], zorder=2,
        )

    ax.set_xticks(x_centers)
    ax.set_xticklabels([str(int(n)) for n in sel_n_disp])
    if cfg.get('xlim') is None and len(x_centers) > 0:
        x_pad = ((num_algs - 1) / 2.0) * offset_step + bar_width / 2.0 + 0.12
        ax.set_xlim(x_centers[0] - x_pad, x_centers[-1] + x_pad)
    _N_helper.apply_axis_controls(ax, cfg=cfg)
    _N_helper.apply_common_style(ax, cfg=cfg)
    _apply_sci_yaxis(ax, cfg, power=3)


def _draw_varyN_completion(ax, N_values, alg_names, metrics):
    """Panel 4: varyN fig1b — 任务完成度折线图（仿 plot_fig1b）。"""
    cfg = _n_fig_cfg('fig1b')
    cfg['title'] = 'CR'
    cfg['ylabel'] = ''
    for aname in alg_names:
        st  = _resolve_alg_style(aname, _N_ALG, _N_DEF, _N_GLOB)
        mu  = np.nanmean(metrics[aname]['completion'], axis=1)
        std = np.nanstd(metrics[aname]['completion'], axis=1)
        if _N_GLOB.get('show_errorbar_varyN', True):
            ax.errorbar(N_values, mu, yerr=std,
                color=st['color'], marker=st['marker'], ls=st['ls'],
                lw=st['linewidth'], ms=st['markersize'],
                mfc=st['markerfacecolor'], mec=st['markeredgecolor'],
                mew=st['markeredgewidth'],
                capsize=_N_GLOB['capsize'], label=st['label'], zorder=3)
        else:
            ax.plot(N_values, mu,
                color=st['color'], marker=st['marker'], ls=st['ls'],
                lw=st['linewidth'], ms=st['markersize'],
                mfc=st['markerfacecolor'], mec=st['markeredgecolor'],
                mew=st['markeredgewidth'],
                label=st['label'], zorder=3)
    _N_helper.apply_axis_controls(ax, cfg=cfg, fixed_values=N_values,
                                  fixed_locator_key='use_fixed_N_xticks')
    _N_helper.apply_common_style(ax, cfg=cfg)
    _apply_sci_yaxis(ax, cfg, power=-1)


# ══════════════════════════════════════════════════════════════════════════════
# 组合图主函数
# ══════════════════════════════════════════════════════════════════════════════

def plot_combined_4panels(M_values, m_alg_names, metrics_M,
                          N_values, n_alg_names, metrics_N,
                          save_stem):
    """绘制四面板横向组合图并保存为 eps + png。"""
    figsize = cm_size_to_inch(FIGSIZE_CM)
    fig, axes = plt.subplots(1, 4, figsize=figsize, squeeze=False)
    ax1, ax2, ax3, ax4 = axes.ravel()

    _draw_varyN_utility_bar(ax1, N_values,  n_alg_names, metrics_N)
    _draw_varyN_completion( ax2, N_values,  n_alg_names, metrics_N)
    _draw_varyM_utility_bar(ax3, M_values, m_alg_names, metrics_M)
    _draw_varyM_completion( ax4, M_values, m_alg_names, metrics_M)

    fig.subplots_adjust(**SUBPLOTS_ADJUST)

    save_dir = os.path.dirname(save_stem)
    if save_dir:
        os.makedirs(save_dir, exist_ok=True)
    for fmt in ('eps', 'png'):
        path = f'{save_stem}.{fmt}'
        fig.savefig(path, format=fmt, dpi=300, bbox_inches='tight', pad_inches=0.02)
        print(f'  [OK] {path}')
    return fig


# ══════════════════════════════════════════════════════════════════════════════
# 入口
# ══════════════════════════════════════════════════════════════════════════════

def main():
    print('\n加载数据...')
    M_values, m_alg_names, metrics_M = load_varyM(VARYM_PREFERRED_INPUT)
    varyn_mat = _find_varyn_mat()
    N_values, n_alg_names, metrics_N = load_varyN(varyn_mat)

    print(f'\n  M_values     = {M_values}')
    print(f'  N_values     = {N_values}')
    print(f'  alg_names(M) = {m_alg_names}')
    print(f'  alg_names(N) = {n_alg_names}')

    os.makedirs(OUTPUT_DIR, exist_ok=True)
    save_stem = os.path.join(OUTPUT_DIR, OUTPUT_STEM)
    print(f'\n绘图 → {save_stem}')

    fig = plot_combined_4panels(
        M_values, m_alg_names, metrics_M,
        N_values, n_alg_names, metrics_N,
        save_stem,
    )

    print('\n完成。关闭窗口后退出。')
    plt.show()


if __name__ == '__main__':
    main()
