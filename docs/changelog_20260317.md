# Changelog 2026-03-17

## 修复 algorithm_issues_20260317.md 中的 6 个问题

- `comalg/alg2_Huo2025/Value_utility.m` — 问题1：需求估计从期望值法改为分位数法（与 Qi2023/OCF 对齐）；问题2：时间计算从单智能体 `calc_with_global_sync` 改为全局同步 `calc_all_agents_with_global_sync`，等待时间基于所有参与者到达时刻的最大值
- `comalg/alg3_Qi2023/Qi2023_main.m` — 问题3：主循环前新增 `other` 字段初始化，确保第1轮 `Preference_gain` 调用时不走兜底逻辑；信念广播改为无条件执行（不受 `enable_belief_update` 限制）
- `comalg/alg7_OCF_SAtabu/OCF_SAtabu_global_main.m` — 问题4：`global_utility_diff` 调用处增加 `GSU_current` 缓存，SC_current 未变时跳过重复计算；accept 后同步更新缓存；问题5：更正温度参数注释（`Tmin`=内循环终止阈值，`T_min_round`=每轮初始温度下界）
- `comalg/alg7_OCF_SAtabu/OCF_SAtabu_global_main.m` — 问题4：`global_utility_diff` 函数增加可选第8参数 `precomputed_GSU_current`，有缓存时跳过 SC_current 的 GSU 计算
- `Compare_Algorithms.m` — 问题6：修复 addpath 路径逻辑，直接用 `script_dir`（项目根目录）拼接子目录，删除绕父目录的 `project_root` 中间层和已删除的 `Com_Fang2025` 路径

## Shi2024 修复（对比算法对齐）

- `comalg/alg4_Shi2024/Shi2024_main.m` — 修改项1：初始构造去掉 `best_utility > 0` 门槛，只要可行任务存在即加入，允许负效用（与 Qi2023/OCF 对齐）
- `comalg/alg4_Shi2024/Shi2024_main.m` — 修改项3：信念更新默认改为 `true`（与 Qi2023/OCF_SAtabu 对齐）
- `comalg/alg4_Shi2024/Shi2024_main.m` — 修改项4：`record_round_data` 中任务完成度改用真实需求 `tasks(j).resource_demand`，去掉硬编码 agent 1 信念，与最终评估口径一致

## Plot 相关修复

- `Plot_Results.m` — 修复路径逻辑（与 Compare_Algorithms.m 对齐，用 `script_dir` 直接拼接）；修复字段名不匹配 `task_completion_rate` → `avg_task_completion`（与 ResultProcessor 保存字段一致）
- `comalg/alg2_Huo2025/Huo2025_main.m` — 修复稳定性判断逻辑：改为比较通信前后全局 SC 是否变化（`isequal(SC_before_comm, SC_after_comm)`），与 Qi2023/OCF 保持一致；删除原来基于 `incremental` 和 `prev_coalitionstru` 的双重判断（后者用 agent 1 局部视图代理全局稳定性，只要 agent 1 不是 winner 就永远 false）
- `comalg/alg2_Huo2025/Huo2025_main.m` — 进一步修复：将 `SC_before_sweep` 采样移到 while 顶部（决策之前），修复 agent 1 移动时漏检导致的 0/1 震荡问题；详见 `docs/huo2025_kstable_analysis.md`
- `Plot_InnerLoop_Evolution.m` — 新增 `is_huo` 检测；子图1对 Huo2025 显示 k_stable 稳定性计数而非温度；子图4、末尾统计对 Huo2025 独立标注"贪婪搜索"说明

## Shi2024 四项重构（效用曲线/性能/口径对齐）

- `comalg/alg4_Shi2024/Shi2024_main.m` — 修改1：去掉 Phase 1 的 Quit 分支，只保留 Transfer 操作
- `comalg/alg4_Shi2024/Shi2024_main.m` — 修改2：Transfer 和 Join 的任务选择改用 `Qi2023_Select_probs` 概率采样（替换原来的全遍历 + 确定性降序），每次迭代 `Preference_gain` 调用次数从 >4000 降至约 N×K×2；新增 `sample_from_probs` 辅助函数
- `comalg/alg4_Shi2024/Shi2024_main.m` — 修改3：每次接受移动后广播 SC 给所有智能体（`for ii = 1:N, Value_data(ii).SC = SC`）
- `comalg/alg4_Shi2024/Shi2024_main.m` — 修改4：`record_round_data` 改用 `UtilityEvaluator.evaluate_coalition_metrics` 统一计算效用/成本/完成度，删除原来混用信念视角和真实视角的分散计算；同步删除已无用的 `calc_global_utility` 和 `calc_agent_cost` 内部函数
