# Changelog 2026-03-24

## plot/plot_ablation.py（新增）
- 创建消融实验 Python 画图脚本，迁移自已删除的 experiments/Plot_Ablation.m；自动加载最新 ablation .mat，输出至 figures/paper/。

## experiments/Plot_Ablation.m（已删除）
- 新增信念更新开关读取（`enable_belief_update`，默认 true），用 `if enable_belief_update` 包裹第337-348行的观测+信念更新+信念广播代码块，修复消融实验 `Batch_Ablation.m` 中 `belief_off` 条件实际无效的问题。
