import os
import re

import matplotlib.ticker as mticker
from matplotlib import font_manager


DEFAULT_SAVE_FORMATS = ("png", "eps")
VECTOR_FORMATS = {"eps", "pdf", "ps", "svg"}
CM_PER_INCH = 2.54
FONT_SIZE_FALLBACK_KEYS = {
    "subplot_title_fontsize": "title_fontsize",
    "legend_title_fontsize": "legend_fontsize",
    "colorbar_label_fontsize": "ylabel_fontsize",
    "colorbar_tick_fontsize": "tick_fontsize",
}


def cm_to_inch(value_cm):
    return float(value_cm) / CM_PER_INCH


def cm_size_to_inch(size_cm):
    if size_cm is None:
        return None
    width_cm, height_cm = size_cm
    return cm_to_inch(width_cm), cm_to_inch(height_cm)


def normalize_size_inch(size_value):
    if size_value is None:
        return None
    width_in, height_in = size_value
    return float(width_in), float(height_in)


def sanitize_path_component(name, default="unnamed"):
    text = "" if name is None else str(name).strip()
    if not text:
        return default

    text = text.replace("\\", "_").replace("/", "_")
    text = re.sub(r"[^A-Za-z0-9._-]+", "_", text)
    text = re.sub(r"_+", "_", text).strip("._-")
    return text or default


def build_results_figures_dir(root_dir, family, source_name=None):
    base_dir = os.path.join(
        root_dir,
        "results",
        "figs",
        sanitize_path_component(family, default="misc"),
    )
    if source_name:
        return os.path.join(base_dir, sanitize_path_component(source_name, default="result"))
    return base_dir


def infer_source_name(path, fallback="result"):
    if not path:
        return fallback

    normalized = os.path.abspath(path)
    if os.path.isdir(normalized):
        return os.path.basename(normalized) or fallback

    stem, _ = os.path.splitext(os.path.basename(normalized))
    return stem or fallback


class PlotStyleHelper:
    def __init__(self, plot_global, figures_dir=None):
        self.plot_global = plot_global or {}
        self.figures_dir = figures_dir

    def set_figures_dir(self, figures_dir):
        self.figures_dir = figures_dir

    def _merge_cfg(self, cfg=None):
        merged = dict(self.plot_global)
        for key, value in (cfg or {}).items():
            if isinstance(value, dict) and isinstance(merged.get(key), dict):
                nested = dict(merged[key])
                nested.update(value)
                merged[key] = nested
            else:
                merged[key] = value
        return merged

    def resolve_fontsize(self, size_key, default=None, cfg=None):
        merged = self._merge_cfg(cfg)
        current_key = size_key
        visited = set()

        while current_key and current_key not in visited:
            visited.add(current_key)
            value = merged.get(current_key)
            if value is not None:
                return value
            current_key = FONT_SIZE_FALLBACK_KEYS.get(current_key)

        return default

    def apply_rcparams(self):
        font_family = self.plot_global.get('font_family')
        font_style = self.plot_global.get('font_style')
        font_weight = self.plot_global.get('font_weight')
        base_fontsize = self.resolve_fontsize('tick_fontsize', cfg=self.plot_global)
        title_fontsize = self.resolve_fontsize('title_fontsize', cfg=self.plot_global)
        label_fontsize = self.resolve_fontsize('xlabel_fontsize', cfg=self.plot_global)
        legend_fontsize = self.resolve_fontsize('legend_fontsize', cfg=self.plot_global)
        legend_title_fontsize = self.resolve_fontsize('legend_title_fontsize', cfg=self.plot_global)

        if font_family:
            try:
                import matplotlib.pyplot as plt
                plt.rcParams['font.family'] = font_family
            except Exception:
                pass
        if font_style:
            try:
                import matplotlib.pyplot as plt
                plt.rcParams['font.style'] = font_style
            except Exception:
                pass
        if font_weight:
            try:
                import matplotlib.pyplot as plt
                plt.rcParams['font.weight'] = font_weight
            except Exception:
                pass
        try:
            import matplotlib.pyplot as plt
            plt.rcParams['axes.unicode_minus'] = False
            if base_fontsize is not None:
                plt.rcParams['font.size'] = base_fontsize
                plt.rcParams['xtick.labelsize'] = base_fontsize
                plt.rcParams['ytick.labelsize'] = base_fontsize
            if title_fontsize is not None:
                plt.rcParams['axes.titlesize'] = title_fontsize
                plt.rcParams['figure.titlesize'] = title_fontsize
            if label_fontsize is not None:
                plt.rcParams['axes.labelsize'] = label_fontsize
            if legend_fontsize is not None:
                plt.rcParams['legend.fontsize'] = legend_fontsize
            if legend_title_fontsize is not None:
                plt.rcParams['legend.title_fontsize'] = legend_title_fontsize
        except Exception:
            pass

    def create_single_axis_figure(self, cfg=None, **subplot_kwargs):
        merged = self._merge_cfg(cfg)

        try:
            import matplotlib.pyplot as plt
        except Exception as exc:
            raise RuntimeError("matplotlib.pyplot is required to create figures") from exc

        figsize_in = normalize_size_inch(merged.get('figsize_in'))
        if figsize_in is None:
            figsize_in = cm_size_to_inch(merged.get('figsize_cm'))

        fig, ax = plt.subplots(
            figsize=figsize_in,
            constrained_layout=bool(merged.get('constrained_layout', False)),
            **subplot_kwargs,
        )

        axes_box_aspect = merged.get('axes_box_aspect')
        if axes_box_aspect is not None and hasattr(ax, 'set_box_aspect'):
            ax.set_box_aspect(float(axes_box_aspect))

        return fig, ax

    def get_text_style(self, size_key, weight_key, default_size=None, default_weight='normal', cfg=None):
        merged = self._merge_cfg(cfg)
        style = {}

        fontsize = self.resolve_fontsize(size_key, default=default_size, cfg=merged)
        if fontsize is not None:
            style['fontsize'] = fontsize

        fontfamily = merged.get('font_family')
        if fontfamily:
            style['fontfamily'] = fontfamily

        fontstyle = merged.get('font_style')
        if fontstyle:
            style['fontstyle'] = fontstyle

        fontweight = merged.get(weight_key, default_weight)
        if fontweight is not None:
            style['fontweight'] = fontweight

        return style

    def get_marker_kwargs(self, show_markers, marker, markevery=None, cfg=None):
        merged = self._merge_cfg(cfg)
        if not show_markers:
            return {}

        kwargs = {
            'marker': marker,
        }

        markersize = merged.get('markersize')
        if markersize is not None:
            kwargs['ms'] = markersize

        markeredgewidth = merged.get('markeredgewidth')
        if markeredgewidth is not None:
            kwargs['mew'] = markeredgewidth

        if markevery is not None:
            kwargs['markevery'] = markevery

        return kwargs

    def build_output_path(self, timestamp, stem, default_ext='png'):
        ext = str(self.plot_global.get('save_format', default_ext)).lstrip('.')
        if self.plot_global.get('timestamp_first_in_name', False):
            filename = f'{timestamp}_{stem}.{ext}'
        else:
            filename = f'{stem}_{timestamp}.{ext}'

        if self.figures_dir:
            return os.path.join(self.figures_dir, filename)
        return filename

    def build_output_stem(self, stem):
        if self.figures_dir:
            return os.path.join(self.figures_dir, stem)
        return stem

    def apply_common_style(
        self,
        ax,
        cfg=None,
        xlabel=None,
        ylabel=None,
        title=None,
        legend_kwargs=None,
        tick_fontsize_key='tick_fontsize',
    ):
        cfg = cfg or {}
        merged = self._merge_cfg(cfg)
        legend_kwargs = dict(legend_kwargs or {})

        xlabel = merged.get('xlabel', xlabel)
        ylabel = merged.get('ylabel', ylabel)
        title = merged.get('title', title)

        if xlabel is not None:
            ax.set_xlabel(
                xlabel,
                labelpad=merged.get('xlabel_pad'),
                **self.get_text_style('xlabel_fontsize', 'label_fontweight', cfg=merged),
            )
        if ylabel is not None:
            ax.set_ylabel(
                ylabel,
                labelpad=merged.get('ylabel_pad'),
                **self.get_text_style('ylabel_fontsize', 'label_fontweight', cfg=merged),
            )

        show_titles = merged.get('show_titles', True)
        if show_titles and merged.get('show_title', True) and title:
            ax.set_title(
                title,
                pad=merged.get('title_pad', 8),
                **self.get_text_style('title_fontsize', 'title_fontweight', cfg=merged),
            )

        if merged.get('show_grid', False):
            ax.grid(
                True,
                linestyle=merged.get('grid_linestyle', '--'),
                linewidth=merged.get('grid_linewidth', 0.6),
                alpha=merged.get('grid_alpha', 0.4),
            )

        tick_fontsize = self.resolve_fontsize(tick_fontsize_key, cfg=merged)
        if tick_fontsize is not None:
            ax.tick_params(labelsize=tick_fontsize)

        font_family = merged.get('font_family')
        font_style = merged.get('font_style')
        tick_fontweight = merged.get('tick_fontweight')
        if font_family or font_style or tick_fontweight:
            for tick in ax.get_xticklabels() + ax.get_yticklabels():
                if font_family:
                    tick.set_fontfamily(font_family)
                if font_style:
                    tick.set_fontstyle(font_style)
                if tick_fontweight:
                    tick.set_fontweight(tick_fontweight)

        if merged.get('show_legend', False):
            explicit_handles = legend_kwargs.get('handles')
            explicit_labels = legend_kwargs.get('labels')
            handles, labels = ax.get_legend_handles_labels()
            has_explicit_legend = explicit_handles is not None and explicit_labels is not None

            if has_explicit_legend or (handles and labels):
                legend_kwargs.setdefault(
                    'framealpha',
                    merged.get('legend_framealpha', 0.85),
                )
                legend_kwargs.setdefault(
                    'edgecolor',
                    merged.get('legend_edgecolor', '#cccccc'),
                )
                legend_kwargs.setdefault(
                    'loc',
                    merged.get('legend_loc', 'best'),
                )

                bbox = merged.get('legend_bbox_to_anchor')
                if bbox is not None:
                    legend_kwargs.setdefault('bbox_to_anchor', bbox)

                if 'ncol' not in legend_kwargs and merged.get('legend_ncol') is not None:
                    legend_kwargs['ncol'] = merged.get('legend_ncol')
                if 'borderaxespad' not in legend_kwargs and merged.get('legend_borderaxespad') is not None:
                    legend_kwargs['borderaxespad'] = merged.get('legend_borderaxespad')
                if 'handlelength' not in legend_kwargs and merged.get('legend_handlelength') is not None:
                    legend_kwargs['handlelength'] = merged.get('legend_handlelength')
                if 'labelspacing' not in legend_kwargs and merged.get('legend_labelspacing') is not None:
                    legend_kwargs['labelspacing'] = merged.get('legend_labelspacing')

                if 'prop' not in legend_kwargs and 'fontsize' not in legend_kwargs:
                    prop = self._build_legend_prop(merged)
                    if prop is not None:
                        legend_kwargs['prop'] = prop
                    elif merged.get('legend_fontsize') is not None:
                        legend_kwargs['fontsize'] = merged.get('legend_fontsize')

                legend = ax.legend(**legend_kwargs)
                legend_cfg = merged
                if legend_kwargs.get('fontsize') is not None:
                    legend_cfg = dict(merged)
                    legend_cfg['legend_fontsize'] = legend_kwargs['fontsize']
                self.style_legend(legend, cfg=legend_cfg)

        self.apply_spine_style(ax, cfg=merged)

    def apply_spine_style(self, ax, cfg=None):
        merged = self._merge_cfg(cfg)

        spine_color = merged.get('spine_color')
        spine_linewidth = merged.get('spine_linewidth')
        for spine in ax.spines.values():
            if spine_color is not None:
                spine.set_color(spine_color)
            if spine_linewidth is not None:
                spine.set_linewidth(spine_linewidth)

        if merged.get('hide_top_spine', False):
            ax.spines['top'].set_visible(False)
        if merged.get('hide_right_spine', False):
            ax.spines['right'].set_visible(False)

    def add_figure_legend(self, fig, handles, labels, cfg=None, **legend_kwargs):
        merged = self._merge_cfg(cfg)
        if not handles or not labels:
            return None

        legend_kwargs = dict(legend_kwargs)
        legend_kwargs.setdefault('framealpha', merged.get('legend_framealpha', 0.85))
        legend_kwargs.setdefault('edgecolor', merged.get('legend_edgecolor', '#cccccc'))
        legend_kwargs.setdefault('loc', merged.get('legend_loc', 'best'))

        bbox = merged.get('legend_bbox_to_anchor')
        if bbox is not None:
            legend_kwargs.setdefault('bbox_to_anchor', bbox)

        if 'ncol' not in legend_kwargs and merged.get('legend_ncol') is not None:
            legend_kwargs['ncol'] = merged.get('legend_ncol')

        if 'prop' not in legend_kwargs and 'fontsize' not in legend_kwargs:
            prop = self._build_legend_prop(merged)
            if prop is not None:
                legend_kwargs['prop'] = prop
            elif merged.get('legend_fontsize') is not None:
                legend_kwargs['fontsize'] = merged.get('legend_fontsize')

        legend = fig.legend(handles, labels, **legend_kwargs)
        legend_cfg = merged
        if legend_kwargs.get('fontsize') is not None:
            legend_cfg = dict(merged)
            legend_cfg['legend_fontsize'] = legend_kwargs['fontsize']
        self.style_legend(legend, cfg=legend_cfg)
        return legend

    def apply_colorbar_style(self, cbar, cfg=None, label=None):
        merged = self._merge_cfg(cfg)

        if label is not None:
            cbar.set_label(
                label,
                **self.get_text_style('colorbar_label_fontsize', 'label_fontweight', cfg=merged),
            )

        tick_fontsize = self.resolve_fontsize('colorbar_tick_fontsize', cfg=merged)
        if tick_fontsize is not None:
            cbar.ax.tick_params(labelsize=tick_fontsize)

        font_family = merged.get('font_family')
        font_style = merged.get('font_style')
        tick_fontweight = merged.get('tick_fontweight')
        if font_family or font_style or tick_fontweight:
            for tick in cbar.ax.get_yticklabels() + cbar.ax.get_xticklabels():
                if font_family:
                    tick.set_fontfamily(font_family)
                if font_style:
                    tick.set_fontstyle(font_style)
                if tick_fontweight:
                    tick.set_fontweight(tick_fontweight)

        self.apply_spine_style(cbar.ax, cfg=merged)

    def style_legend(self, legend, cfg=None):
        if legend is None:
            return None

        merged = self._merge_cfg(cfg)
        label_fontsize = self.resolve_fontsize('legend_fontsize', cfg=merged)
        title_fontsize = self.resolve_fontsize('legend_title_fontsize', cfg=merged)
        font_family = merged.get('font_family')
        font_style = merged.get('font_style')
        font_weight = merged.get('legend_fontweight')

        for text in legend.get_texts():
            if label_fontsize is not None:
                text.set_fontsize(label_fontsize)
            if font_family:
                text.set_fontfamily(font_family)
            if font_style:
                text.set_fontstyle(font_style)
            if font_weight:
                text.set_fontweight(font_weight)

        title = legend.get_title()
        if title is not None:
            if title_fontsize is not None:
                title.set_fontsize(title_fontsize)
            if font_family:
                title.set_fontfamily(font_family)
            if font_style:
                title.set_fontstyle(font_style)
            if font_weight:
                title.set_fontweight(font_weight)

        return legend

    def apply_axis_controls(self, ax, cfg=None, fixed_values=None, fixed_locator_key=None):
        cfg = self._merge_cfg(cfg)

        if fixed_locator_key and cfg.get(fixed_locator_key, False) and fixed_values is not None:
            ax.xaxis.set_major_locator(mticker.FixedLocator(fixed_values))

        if cfg.get('xticks') is not None:
            ax.set_xticks(cfg['xticks'])
        if cfg.get('yticks') is not None:
            ax.set_yticks(cfg['yticks'])

        if cfg.get('xlim') is not None:
            ax.set_xlim(*cfg['xlim'])
        if cfg.get('ylim') is not None:
            ax.set_ylim(*cfg['ylim'])

        if cfg.get('left_zero', False) and cfg.get('xlim') is None:
            _, xmax = ax.get_xlim()
            ax.set_xlim(left=0, right=xmax)

        if cfg.get('bottom_zero', False) and cfg.get('ylim') is None:
            _, ymax = ax.get_ylim()
            ax.set_ylim(bottom=0, top=ymax)

    def finalize_and_save(self, fig, save_path, tight_layout_rect=None, cfg=None):
        merged = self._merge_cfg(cfg)
        constrained_layout_active = False
        try:
            constrained_layout_active = bool(fig.get_constrained_layout())
        except Exception:
            constrained_layout_active = False

        if merged.get('tight_layout', False) and not constrained_layout_active:
            if tight_layout_rect is None:
                fig.tight_layout()
            else:
                fig.tight_layout(rect=tight_layout_rect)

        save_stem, save_formats = self._normalize_save_target(save_path, merged)
        save_dir = os.path.dirname(save_stem)
        if save_dir:
            os.makedirs(save_dir, exist_ok=True)

        saved_paths = []
        for ext in save_formats:
            output_path = f'{save_stem}.{ext}'
            save_kwargs = {
                'format': ext,
            }
            save_bbox_inches = merged.get('save_bbox_inches')
            if save_bbox_inches is not None:
                save_kwargs['bbox_inches'] = save_bbox_inches
                save_pad_inches = merged.get('save_pad_inches')
                if save_pad_inches is not None:
                    save_kwargs['pad_inches'] = save_pad_inches
            if ext not in VECTOR_FORMATS:
                save_kwargs['dpi'] = merged.get('save_dpi', 150)
            fig.savefig(output_path, **save_kwargs)
            print(f'  [OK] {output_path}')
            saved_paths.append(output_path)
        return saved_paths

    def _normalize_save_target(self, save_path, plot_global=None):
        normalized = os.path.abspath(save_path)
        default_formats = self._get_default_save_formats(plot_global=plot_global)
        stem, ext = os.path.splitext(normalized)
        requested_ext = ext.lstrip('.').lower()

        if requested_ext:
            if requested_ext in default_formats:
                formats = [requested_ext] + [fmt for fmt in default_formats if fmt != requested_ext]
            else:
                formats = [requested_ext]
            return stem, formats

        return normalized, default_formats

    def _get_default_save_formats(self, plot_global=None):
        plot_global = plot_global or self.plot_global
        raw_formats = plot_global.get('save_formats')
        if raw_formats is None:
            legacy_format = plot_global.get('save_format')
            if legacy_format:
                if isinstance(legacy_format, (list, tuple)):
                    raw_formats = legacy_format
                else:
                    raw_formats = DEFAULT_SAVE_FORMATS if str(legacy_format).lower() in DEFAULT_SAVE_FORMATS else [legacy_format]
            else:
                raw_formats = DEFAULT_SAVE_FORMATS

        if isinstance(raw_formats, str):
            raw_formats = [raw_formats]

        normalized = []
        for item in raw_formats:
            fmt = str(item).strip().lstrip('.').lower()
            if fmt and fmt not in normalized:
                normalized.append(fmt)

        return normalized or list(DEFAULT_SAVE_FORMATS)

    def _build_legend_prop(self, plot_global=None):
        plot_global = plot_global or self.plot_global
        family = plot_global.get('font_family')
        style = plot_global.get('font_style')
        weight = plot_global.get('legend_fontweight')
        size = self.resolve_fontsize('legend_fontsize', cfg=plot_global)

        if not any(v is not None for v in (family, style, weight, size)):
            return None

        return font_manager.FontProperties(
            family=family,
            style=style or 'normal',
            weight=weight or 'normal',
            size=size,
        )
