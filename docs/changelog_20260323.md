# Changelog 2026-03-23

## experiments/ 重构

- `experiments/Exp_Params.m`（新建）：集中存放所有实验共享参数（超参、SA/禁忌、场景、智能体、任务需求等），各 Batch 脚本通过 `run(Exp_Params.m)` 引用。
- `Batch_VaryN.m`：加画图用途+保存字段说明头注释；替换参数块为 Exp_Params；删除 inner_loop_r50 相关代码（INNER_LOOP_ROUND 变量、alg_entry 字段、提取逻辑、scale_config 字段）；修复重复 fprintf 块。
- `Batch_VaryM.m`：加头注释；替换参数块为 Exp_Params。
- `Batch_Belief.m`：加头注释；替换参数块为 Exp_Params；信念模板变量留在本文件。
- `Batch_Ablation.m`：加头注释；替换参数块为 Exp_Params。
- `Single_Viz.m`：加画图用途+保存字段说明头注释；替换参数块为 Exp_Params。
