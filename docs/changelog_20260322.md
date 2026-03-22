
## 新增批量实验调度器（2026-03-22）

- `Batch_Experiments.m` — 新建，20 seeds × 多 N 规模批量实验脚本；输出 `results/batch/summary_*.mat`（-v7.3），含逐轮收敛曲线 + 最终指标，供 Python 画图。

## 论文图表实验脚本架构（2026-03-22 追加）

新增 5 个批量实验脚本，覆盖论文全部图表所需数据：

- `Batch_VaryN.m` — 实验A：变N规模（图1a/1b+图2c+图3）；4算法×20seeds×7N值；额外保存第50轮内循环轨迹（`inner_loop_r50`）；输出 `varyN_N4-20_S20_*.mat`。
- `Batch_VaryM.m` — 实验B：变M规模（图1c/1d）；4算法×20seeds×7M值；固定N=10；输出 `varyM_M5-20_S20_*.mat`。
- `Batch_Belief.m` — 实验C：信念演化（图2a/2b）；仅OCF_SAtabu；3种初始信念条件（uniform/optimistic/pessimistic）×10seeds；保存完整 `belief_history[num_rounds×N×M×task_type]`；输出 `belief_*.mat`。
- `Batch_Ablation.m` — 实验D：消融实验（图4）；仅OCF_SAtabu；belief_on vs belief_off×20seeds×7N值；输出 `ablation_*.mat`。
- `Single_Viz.m` — 实验E：单次可视化（图5）；N=10,M=10,seed=1001；保存 `final_SC`/`agents`/`tasks`/`WorldSim timing`；输出 `visualize_*.mat`。

---

## Shi2024 Transfer/Join 阶段去除 Preference_gain（2026-03-22）

- `comalg/alg4_Shi2024/Shi2024_main.m` — Transfer（C段）和 Join（D段）不再调用 Preference_gain，改为可行性通过即直接接受到工作副本；Preference_gain 仅在最终门控（E段）调用一次，与 Qi2023 结构对齐。预期每 agent 每迭代调用次数从 ~67 次降至 1 次（约 67 倍加速）。
