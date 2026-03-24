# Changelog 2026-03-23

## experiments/ 重构

- `experiments/Exp_Params.m`（新建）：集中存放所有实验共享参数（超参、SA/禁忌、场景、智能体、任务需求等），各 Batch 脚本通过 `run(Exp_Params.m)` 引用。
- `Batch_VaryN.m`：加画图用途+保存字段说明头注释；替换参数块为 Exp_Params；删除 inner_loop_r50 相关代码（INNER_LOOP_ROUND 变量、alg_entry 字段、提取逻辑、scale_config 字段）；修复重复 fprintf 块。
- `Batch_VaryM.m`：加头注释；替换参数块为 Exp_Params。
- `Batch_Belief.m`：加头注释；替换参数块为 Exp_Params；信念模板变量留在本文件。
- `Batch_Ablation.m`：加头注释；替换参数块为 Exp_Params。
- `Single_Viz.m`：加画图用途+保存字段说明头注释；替换参数块为 Exp_Params。

## plot/plot_varyM_top_config.py（新建）

- 仿照 `plot_varyN_top_config.py` 为 `Batch_VaryM.m` 结果写绘图脚本。
- 画四张图：fig1c（效用 vs M）、fig1d（完成度 vs M）、fig1e（总完成价值 vs M）、fig2d（收敛曲线，取最大 M）。
- 读取变量 `scale_M_results` / `scale_config`，解析 `M_values`，x 轴刻度自动固定到 M 取值列表。

## validate_feasibility.m 修复

- `Main_fun/validate_feasibility.m`：修复"间接受害者"漏检 bug。
  原逻辑只检查与 agentID 直接共任务的队友；当新加入的 agent 通过时间同步链传递延迟给下游任务的非直接参与者时，这些智能体的能量溢出无法被捕获。
  修复方案：`check_teammates=true` 时改为调用 `WorldSim.calc_all_agents_with_global_sync` 一次，直接对全部 N 个智能体做能量校验；`check_teammates=false` 保留原有单智能体轻量路径不变。
  同时将原 `check_single_agent` 拆分为纯资源约束检查 `check_resource_constraints`（无时序开销），删除已不再需要的 `get_teammates` 辅助函数。

## 2026-03-24 新增 plot_belief.py

- `plot/plot_belief.py`（新建）：仿照 plot_varyM_top_config.py 风格，从 Batch_Belief.m 生成的 .mat 文件绘制图2a（L1信念误差曲线）和图2b（期望价值预测曲线），3种初始信念条件（uniform/optimistic/pessimistic）对比，均值±半透明误差带。

## 2026-03-24 信念实验条件重构 + 图2c 新增

### 修改文件
- `experiments/Exp_Params.m`：`Batch_Belief.CONDITIONS` 改为 `{'uniform', 'heterogeneous'}`，删除 belief_optimistic/pessimistic。
- `experiments/Batch_Belief.m`：按条件在主循环内生成初始信念矩阵（uniform=全员相同均匀先验；heterogeneous=每智能体随机 Dirichlet 先验），通过 `AddPara_run.init_belief`（N×T）传入算法；entry 新增 `true_task_values` 和 `init_belief_matrix` 字段；belief_config 移除 optimistic/pessimistic 字段。
- `comalg/alg7_OCF_SAtabu/OCF_SAtabu_global_main.m`：`init_observe_belief_neighbor` 调用后，若 `AddPara.init_belief` 存在则用 N×T 矩阵覆盖默认均匀先验，同步更新 `Value_data(i).other{j}.initbelief`。
- `plot/plot_belief.py`：更新条件样式（heterogeneous 替换 optimistic/pessimistic）；新增 `extract_per_agent_data` 和 `plot_fig2c_per_condition`，每个条件输出一张含 M 个子图的大图（每子图：N 条智能体期望价值曲线 + 1 条真实价值虚线）。
