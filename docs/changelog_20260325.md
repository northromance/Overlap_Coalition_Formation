# Changelog 2026-03-25

## 场景生成统一化 + 结果字段收口 + 文档一致性修复

- `Main_fun/build_scenario.m` **新建** — 统一场景生成函数，封装 rng+WORLD+tasks+agents 生成逻辑
- `Main_fun/get_all_algorithms.m` **新建** — 统一算法注册表（id/name/func/folder/color）
- `experiments/Exp_Params.m` — 新增 `Exp_Config.ScenarioCfg` 公共场景参数块
- `experiments/Batch_VaryN.m` — 场景/注册重构；移除 `inner_loop_r50`（图3a 改由 Single_Viz 提供）
- `experiments/Batch_VaryM.m` — 场景/注册重构；补充缺失的 `convergence_completed_value` / `final_completed_value` 字段
- `experiments/Batch_Belief.m` — 场景生成替换；头注释 condition 命名修正（`optimistic/pessimistic` → `heterogeneous`）
- `experiments/Batch_Ablation.m` — 场景生成替换
- `experiments/Single_Viz.m` — 场景生成替换
- `Compare_Algorithms.m` — 场景生成替换；算法注册替换
- `experiments/batch_experiments_guide.md` — 全面更新：3.1节移除 inner_loop 输出；3.2节补充两个缺失字段；3.3节信念命名（2种条件/heterogeneous）；图表映射表更新；注意事项精简
- `docs/batch_experiments_howto.md` **新建** — 重构后的完整使用指南（脚本职责、配置方法、输出结构、Python 读取示例、FAQ）
- `plot/plot_single_viz.py` **新建** — 图5a（M任务热图网格）+ 图5b（N智能体执行甘特图），读取 Single_Viz.m 产出的 .mat
