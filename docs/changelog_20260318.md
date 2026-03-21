# Changelog 2026-03-18

## 绘图开关补全

- `Plot_Results.m` — `plot_config` 新增 `radar`/`history`/`belief` 三个开关（默认 true）；调用 `plot_algorithm_comparison` 时传入 `plot_config`
- `Main_fun/PlotClass.m` — `plot_algorithm_comparison` 新增第7参数 `plot_config`，内部综合对比图、雷达图、历史演化图、期望价值演化图均受对应开关控制；不传参数时向后兼容全部开启

## Huo2025 改造为顺序决策结构

- `comalg/alg2_Huo2025/Huo2025_main.m` — 去除并发决策+共识协议，改为顺序扫描内循环，消除多智能体循环博弈震荡；新增 verbose 关键节点打印；每轮初始化禁忌表并传递给 Value_order
- `comalg/alg2_Huo2025/Value_order.m` — 新签名含 TabuList 参数；决策标准从个体效用改为全局效用增量；**性能优化：利用非重叠联盟特性，只计算受影响成员（cur_task∪目标任务成员）的效用差，避免每次 What-If 重算全部 N 个智能体**；禁忌检查与 Qi2023 逻辑一致
- `docs/alg_Huo2025.md` — 新建算法说明文档

## 图形尺寸统一调整

- `Compare_Algorithms.m` — 新增6个图形尺寸参数（`fig_size_main/radar/history/belief/alloc/inner`）并注入 `Value_Params`，方便集中调整所有图窗大小
- `Plot_InnerLoop_Evolution.m` — 内循环演化图从 1400×900 改为从 `Value_Params.fig_size_inner` 读取（默认 900×600）
- `Main_fun/PlotClass.m` — 所有 figure Position 改为从 `Value_Params` 对应字段读取：综合对比图、雷达图、历史演化图、期望价值图、资源分配图、动画图均缩小至合理尺寸
