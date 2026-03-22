
## verbose 四级控制 + 计时器（2026-03-21）

- `Compare_Algorithms.m` — `AddPara.verbose` 改为 0/1/2/3 四级整数（0=静默 1=轮次 2=迭代 3=详细）；新增 `total_tic` 总计时器，算法结束后打印各算法耗时及总耗时汇总表
- `comalg/alg2_Huo2025/Value_order.m`、`Main_fun/validate_feasibility.m` — 旧式 `if AddPara.verbose` 改为 `>= 3`；`check_coalition_consistency` 调用改传 `AddPara.verbose >= 2`；OCF T校准输出改为 `>= 2`

## Shi2024 性能优化（2026-03-21）

- `Main_fun/UtilityEvaluator.m` — `calc_agent_total_utility` 内加 `persistent` 缓存，同一 SC 下 `calc_all_agents_with_global_sync` 只调用一次（解决 Preference_gain 链式重复调用问题，约 20x 加速）
- `comalg/alg4_Shi2024/Shi2024_main.m` — `get_SC_hash` 替换为快速数值哈希（替代 `mat2str`，约 50x 加速）；`TabuList` 改为 `containers.Map + FIFO 队列`（O(1) 查找替代 O(L) 线性搜索）；Transfer 接受后改为增量更新 `resource_gap`（替代全量 `calc_gaps`）
