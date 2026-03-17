# Changelog 2026-03-17

## 修复 algorithm_issues_20260317.md 中的 6 个问题

- `comalg/alg2_Huo2025/Value_utility.m` — 问题1：需求估计从期望值法改为分位数法（与 Qi2023/OCF 对齐）；问题2：时间计算从单智能体 `calc_with_global_sync` 改为全局同步 `calc_all_agents_with_global_sync`，等待时间基于所有参与者到达时刻的最大值
- `comalg/alg3_Qi2023/Qi2023_main.m` — 问题3：主循环前新增 `other` 字段初始化，确保第1轮 `Preference_gain` 调用时不走兜底逻辑；信念广播改为无条件执行（不受 `enable_belief_update` 限制）
- `comalg/alg7_OCF_SAtabu/OCF_SAtabu_global_main.m` — 问题4：`global_utility_diff` 调用处增加 `GSU_current` 缓存，SC_current 未变时跳过重复计算；accept 后同步更新缓存；问题5：更正温度参数注释（`Tmin`=内循环终止阈值，`T_min_round`=每轮初始温度下界）
- `comalg/alg7_OCF_SAtabu/OCF_SAtabu_global_main.m` — 问题4：`global_utility_diff` 函数增加可选第8参数 `precomputed_GSU_current`，有缓存时跳过 SC_current 的 GSU 计算
- `Compare_Algorithms.m` — 问题6：修复 addpath 路径逻辑，直接用 `script_dir`（项目根目录）拼接子目录，删除绕父目录的 `project_root` 中间层和已删除的 `Com_Fang2025` 路径

## Plot 相关修复

- `Plot_Results.m` — 修复路径逻辑（与 Compare_Algorithms.m 对齐，用 `script_dir` 直接拼接）；修复字段名不匹配 `task_completion_rate` → `avg_task_completion`（与 ResultProcessor 保存字段一致）
- `comalg/alg2_Huo2025/Huo2025_main.m` — 修复稳定性判断逻辑：改为比较通信前后全局 SC 是否变化（`isequal(SC_before_comm, SC_after_comm)`），与 Qi2023/OCF 保持一致；删除原来基于 `incremental` 和 `prev_coalitionstru` 的双重判断（后者用 agent 1 局部视图代理全局稳定性，只要 agent 1 不是 winner 就永远 false）
- `comalg/alg2_Huo2025/Huo2025_main.m` — 进一步修复：将 `SC_before_sweep` 采样移到 while 顶部（决策之前），修复 agent 1 移动时漏检导致的 0/1 震荡问题；详见 `docs/huo2025_kstable_analysis.md`
- `Plot_InnerLoop_Evolution.m` — 新增 `is_huo` 检测；子图1对 Huo2025 显示 k_stable 稳定性计数而非温度；子图4、末尾统计对 Huo2025 独立标注"贪婪搜索"说明
