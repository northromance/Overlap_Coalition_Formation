import os

import matplotlib.ticker as mticker
from matplotlib import font_manager


class PlotStyleHelper:
    def __init__(self, plot_global, figures_dir=None):
        self.plot_global = plot_global or {}
        self.figures_dir = figures_dir

    def apply_rcparams(self):
        font_family = self.plot_global.get('font_family')
        font_style = self.plot_global.get('font_style')
        font_weight = self.plot_global.get('font_weight')

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
        except Exception:
            pass

    def get_text_style(self, size_key, weight_key, default_size=None, default_weight='normal'):
        style = {}

        fontsize = self.plot_global.get(size_key, default_size)
        if fontsize is not None:
            style['fontsize'] = fontsize

        fontfamily = self.plot_global.get('font_family')
        if fontfamily:
            style['fontfamily'] = fontfamily

        fontstyle = self.plot_global.get('font_style')
        if fontstyle:
            style['fontstyle'] = fontstyle

        fontweight = self.plot_global.get(weight_key, default_weight)
        if fontweight is not None:
            style['fontweight'] = fontweight

        return style

    def get_marker_kwargs(self, show_markers, marker, markevery=None):
        if not show_markers:
            return {}

        kwargs = {
            'marker': marker,
        }

        markersize = self.plot_global.get('markersize')
        if markersize is not None:
            kwargs['ms'] = markersize

        markeredgewidth = self.plot_global.get('markeredgewidth')
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
        legend_kwargs = dict(legend_kwargs or {})

        xlabel = cfg.get('xlabel', xlabel)
        ylabel = cfg.get('ylabel', ylabel)
        title = cfg.get('title', title)

        if xlabel is not None:
            ax.set_xlabel(
                xlabel,
                **self.get_text_style('xlabel_fontsize', 'label_fontweight'),
            )
        if ylabel is not None:
            ax.set_ylabel(
                ylabel,
                **self.get_text_style('ylabel_fontsize', 'label_fontweight'),
            )

        show_titles = self.plot_global.get('show_titles', True)
        if show_titles and cfg.get('show_title', True) and title:
            ax.set_title(
                title,
                pad=self.plot_global.get('title_pad', 8),
                **self.get_text_style('title_fontsize', 'title_fontweight'),
            )

        if self.plot_global.get('show_grid', False):
            ax.grid(
                True,
                linestyle=self.plot_global.get('grid_linestyle', '--'),
                linewidth=self.plot_global.get('grid_linewidth', 0.6),
                alpha=self.plot_global.get('grid_alpha', 0.4),
            )

        tick_fontsize = self.plot_global.get(tick_fontsize_key)
        if tick_fontsize is not None:
            ax.tick_params(labelsize=tick_fontsize)

        font_family = self.plot_global.get('font_family')
        font_style = self.plot_global.get('font_style')
        tick_fontweight = self.plot_global.get('tick_fontweight')
        if font_family or font_style or tick_fontweight:
            for tick in ax.get_xticklabels() + ax.get_yticklabels():
                if font_family:
                    tick.set_fontfamily(font_family)
                if font_style:
                    tick.set_fontstyle(font_style)
                if tick_fontweight:
                    tick.set_fontweight(tick_fontweight)

        if self.plot_global.get('show_legend', False):
            explicit_handles = legend_kwargs.get('handles')
            explicit_labels = legend_kwargs.get('labels')
            handles, labels = ax.get_legend_handles_labels()
            has_explicit_legend = explicit_handles is not None and explicit_labels is not None

            if has_explicit_legend or (handles and labels):
                legend_kwargs.setdefault(
                    'framealpha',
                    self.plot_global.get('legend_framealpha', 0.85),
                )
                legend_kwargs.setdefault(
                    'edgecolor',
                    self.plot_global.get('legend_edgecolor', '#cccccc'),
                )
                legend_kwargs.setdefault(
                    'loc',
                    self.plot_global.get('legend_loc', 'best'),
                )

                bbox = self.plot_global.get('legend_bbox_to_anchor')
                if bbox is not None:
                    legend_kwargs.setdefault('bbox_to_anchor', bbox)

                if 'ncol' not in legend_kwargs and self.plot_global.get('legend_ncol') is not None:
                    legend_kwargs['ncol'] = self.plot_global.get('legend_ncol')
                if 'borderaxespad' not in legend_kwargs and self.plot_global.get('legend_borderaxespad') is not None:
                    legend_kwargs['borderaxespad'] = self.plot_global.get('legend_borderaxespad')
                if 'handlelength' not in legend_kwargs and self.plot_global.get('legend_handlelength') is not None:
                    legend_kwargs['handlelength'] = self.plot_global.get('legend_handlelength')
                if 'labelspacing' not in legend_kwargs and self.plot_global.get('legend_labelspacing') is not None:
                    legend_kwargs['labelspacing'] = self.plot_global.get('legend_labelspacing')

                if 'prop' not in legend_kwargs and 'fontsize' not in legend_kwargs:
                    prop = self._build_legend_prop()
                    if prop is not None:
                        legend_kwargs['prop'] = prop
                    elif self.plot_global.get('legend_fontsize') is not None:
                        legend_kwargs['fontsize'] = self.plot_global.get('legend_fontsize')

                ax.legend(**legend_kwargs)

        if self.plot_global.get('hide_top_spine', False):
            ax.spines['top'].set_visible(False)
        if self.plot_global.get('hide_right_spine', False):
            ax.spines['right'].set_visible(False)

    def apply_axis_controls(self, ax, cfg=None, fixed_values=None, fixed_locator_key=None):
        cfg = cfg or {}

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

        if cfg.get('bottom_zero', False):
            _, ymax = ax.get_ylim()
            ax.set_ylim(bottom=0, top=ymax)

    def finalize_and_save(self, fig, save_path, tight_layout_rect=None):
        if self.plot_global.get('tight_layout', False):
            if tight_layout_rect is None:
                fig.tight_layout()
            else:
                fig.tight_layout(rect=tight_layout_rect)

        save_dir = os.path.dirname(save_path)
        if save_dir:
            os.makedirs(save_dir, exist_ok=True)

        default_ext = os.path.splitext(save_path)[1].lstrip('.') or 'png'
        fig.savefig(
            save_path,
            format=self.plot_global.get('save_format', default_ext),
            dpi=self.plot_global.get('save_dpi', 150),
            bbox_inches=self.plot_global.get('save_bbox_inches', 'tight'),
        )
        print(f'  [OK] {save_path}')

    def _build_legend_prop(self):
        family = self.plot_global.get('font_family')
        style = self.plot_global.get('font_style')
        weight = self.plot_global.get('legend_fontweight')
        size = self.plot_global.get('legend_fontsize')

        if not any(v is not None for v in (family, style, weight, size)):
            return None

        return font_manager.FontProperties(
            family=family,
            style=style or 'normal',
            weight=weight or 'normal',
            size=size,
        )
