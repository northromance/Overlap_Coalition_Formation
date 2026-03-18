# Changelog 2026-03-18

## 绘图开关补全

- `Plot_Results.m` — `plot_config` 新增 `radar`/`history`/`belief` 三个开关（默认 true）；调用 `plot_algorithm_comparison` 时传入 `plot_config`
- `Main_fun/PlotClass.m` — `plot_algorithm_comparison` 新增第7参数 `plot_config`，内部综合对比图、雷达图、历史演化图、期望价值演化图均受对应开关控制；不传参数时向后兼容全部开启

## 图形尺寸统一调整

- `Compare_Algorithms.m` — 新增6个图形尺寸参数（`fig_size_main/radar/history/belief/alloc/inner`）并注入 `Value_Params`，方便集中调整所有图窗大小
- `Plot_InnerLoop_Evolution.m` — 内循环演化图从 1400×900 改为从 `Value_Params.fig_size_inner` 读取（默认 900×600）
- `Main_fun/PlotClass.m` — 所有 figure Position 改为从 `Value_Params` 对应字段读取：综合对比图、雷达图、历史演化图、期望价值图、资源分配图、动画图均缩小至合理尺寸
