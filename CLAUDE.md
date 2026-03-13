# 项目规范 (CLAUDE.md)

本文件由 AI 在每次对话开始时自动读取，用于防止重复犯已知错误。

## 项目概述

MATLAB 多智能体重叠联盟形成（Overlap Coalition Formation）项目。
N 个智能体协作完成 M 个任务，每个任务需要 K 种资源，智能体可同时参与多个任务（重叠联盟）。

---

## 编码规范

- 所有 .m 文件以 **UTF-8** 编码保存
- Windows MATLAB 中文乱码修复：在脚本开头执行 `feature('DefaultCharacterSet', 'UTF-8')`
- 中文注释统一使用，不要在同一文件内混用中英文注释风格

**已解决（2026-03-12）**：VSCode `settings.json` 已配置 `"files.encoding": "utf8"` 和 `"[matlab]": {"files.encoding": "utf8"}`，MATLAB 编辑器也设为默认 UTF-8 保存。三层（VSCode读写 / MATLAB保存 / fprintf输出）全部对齐，不再出现乱码。


## 关键数据结构

### SC（联盟结构，Coalition Structure）
- `SC` 是 M×1 的 Cell Array
- `SC{m}` 是 N×K 矩阵：第 n 行第 k 列 = 智能体 n 分配给任务 m 的第 k 种资源量
- 访问方式：`SC{task_id}(agent_id, resource_type)`

### Value_Params（全局参数）

所有参数统一在 `Compare_Algorithms.m` 中注入，各算法只读不写。

**场景维度**
- `Value_Params.N` — 智能体数量
- `Value_Params.M` — 任务数量
- `Value_Params.K` — 资源种类数
- `Value_Params.task_type` — 任务类型数（`num_task_types`）
- `Value_Params.task_type_demands` — num_task_types×K 矩阵，各类型任务的资源需求模板
- `Value_Params.seed` — 随机种子

**迭代控制（所有算法共用）**
- `Value_Params.num_rounds` — 总轮数
- `Value_Params.max_inner_iter` — 每轮最大内层迭代次数（`MaxIter`）
- `Value_Params.K_stable_max` — 稳定性阈值（连续无改进迭代次数，SA/Fang/Tabu 系列）

**SA 温度调度（SA/Fang/Tabu 系列共用）**
- `Value_Params.Temperature` — 当前温度（运行时动态更新，每轮开始时重置）
- `Value_Params.T0_round` — 每轮初始温度
- `Value_Params.T_min_round` — 温度下界
- `Value_Params.T_decay` — 轮间温度衰减系数
- `Value_Params.T_init_construction` — 初始构造阶段温度（低温近贪婪）
- `Value_Params.resource_confidence` — 初始构造阶段需求分位置信度

**TabuEnhanced 专属（算法 7）**
- `Value_Params.tabu_tenure` — 禁忌期限
- `Value_Params.p_leave` — 离开概率（与 Qi2023 共用）

**Qi2023 专属**
- `Value_Params.Qi_L_tabu` — 禁忌表长度
- `Value_Params.Qi_K_stable_max` — 稳定性阈值
- `Value_Params.Qi_Gamma_init` — 初始 Boltzmann 系数
- `Value_Params.Qi_Gamma_max` — 最大 Boltzmann 系数

**Shi2024 专属**
- `Value_Params.Shi_K_stable_max` — 稳定性阈值
- `Value_Params.C` — 算法内部常数（当前值 2000）

### Value_data（单个智能体状态）
- `Value_data.agentID` 或 `Value_data.agentIndex` — 智能体编号
- `Value_data.initbelief` — M×task_type 信念矩阵（对任务类型的概率分布）
- `Value_data.SC` — 该智能体视角下的全局联盟结构
- `Value_data.coalitionstru` — 联盟成员结构
- `Value_data.selectProb` — 任务选择概率

### 时间三分量
- `t_fly` — 飞行时间（移动成本系数 `agents(n).fuel` = varpi）
- `t_wait` — 等待时间（等待成本系数 `agents(n).wait_fuel` = gamma）
- `t_exec` — 执行时间（执行成本系数 `agents(n).beta` = beta）

---

## 效用计算架构

### 个体效用公式（UtilityEvaluator.calc_agent_total_utility）
```
u_n^m = revenue_nm - E_nm_cost
revenue_nm = r_nm * V_km * varsigma_m
E_nm_cost  = E_move + E_wait + E_exec
           = varpi*dist + gamma*(T_wait_pre + T_wait_post) + beta*Dur_nm
```

### 全局效用（UtilityEvaluator.evaluate_coalition_metrics）
- 上帝视角，使用任务真实需求 `tasks(j).resource_demand` 和真实价值 `tasks(j).value`，仅在数据保存结算的时候使用而不在分布式决策中使用
- 个体视角使用信念分布 `Value_data.initbelief` 和分位数需求

### 全局时间同步（WorldSim.calc_all_agents_with_global_sync）
- **在使用他的时候尽量少调用并且其可以返回所有智能体的时间结果因此在计算的时候减少调用**，返回所有智能体的时间结果 `all_agents_results`（struct 数组，下标即 agent_id）
- 每个 `all_agents_results(i)` 包含：`t_fly_total`, `t_wait_total`, `t_exec_total`, `task_sequence`, `start_times`, `execution_times`

---

## 已知 Bug 与修复记录

### Bug 1：个体效用负值截断（commit 3cfbbc0，2026-03-06）
- **错误做法**：`agentutility = max(0, agentutility)` 或 `u_nm = max(0, u_nm)`
- **正确做法**：效用可以为负值，不应截断。负效用表示该智能体参与该任务是亏损的，这是合法状态 

### Bug 2：全局同步在循环内重复调用（commit 5760a30）
- **错误做法**：在每次迭代或每个智能体的效用计算内部调用 `calc_all_agents_with_global_sync`
- **正确做法**：在外层只调用一次，将结果传入或缓存，避免 O(N²) 的重复计算

### Bug 3：跨轮效用比较失效（commit c6e41a3）
- **错误做法**：继承上一轮的 SC 效用值，直接与当前轮的新 SC 效用比较
- **正确做法**：每轮开始时，必须基于"当前信念"重新计算继承 SC 的效用，再与新 SC 效用比较
- **原因**：信念在每轮更新，同一 SC 在不同信念下效用不同

### Bug 4：时间同步逻辑错误（commit 1b5fa7b，2026-03-12）
- **修复内容**：`WorldSim.calc_all_agents_with_global_sync` 中的时间推进逻辑
- 任务同步开始时刻 `ST_m` = 所有参与者到达时刻的最大值
- 同步前等待：`T_wait_pre = max(0, ST_m - AT_nm)`
- 同步后等待：`T_wait_post = max(0, Dur_m - Dur_nm)`（联盟整体执行时长 - 个体执行时长）

---

## 算法实现注意事项

### 任务完成度（WorldSim.calc_task_completion_degree）
- `D_C = (1/Z_c) * sum_k min(allocated_k / demand_k, 1.0)`，其中 Z_c 为有需求的资源种类数
- 返回值在 [0, 1] 之间

### 路径管理
- 使用 `OCFUtils.add_project_paths()` 动态添加子目录，不要硬编码路径
- 根目录由 `fileparts(mfilename('fullpath'))` 自动获取

### 测试与文档规范
- **测试文件**统一放在 `tests/` 目录，文件名以 `test_` 开头
- **算法/模块说明文档**（新建的 `.md` 注释说明）统一放在 `docs/` 目录
- **操作日志**：每次会话中有代码修改时，在 `docs/` 下创建或追加当天的
  changelog 文件，命名格式 `changelog_YYYYMMDD.md`。
  每条记录保持简短：改了哪些文件 + 一句话说明原因，不需要详细展开。
  当天已有文件则追加，不新建。


## 禁止事项

1. **禁止**将个体效用负值截断为 0（`max(0, utility)` 是错误的）
2. **禁止**在每次迭代内重复调用 `calc_all_agents_with_global_sync`（性能问题，且逻辑错误）
3. **禁止**跨轮直接复用旧效用值进行比较，必须用当前信念重新计算
4. **禁止**使用已注释掉的旧版效用计算函数（`UtilityEvaluator.m` 顶部的注释块是废弃代码）
5. **禁止**硬编码项目路径 


## AddPara（算法接口参数）

通过函数参数传入，不在 Value_Params 中：
- `AddPara.enable_belief_update` — 信念更新开关（true=启用贝叶斯更新）
- `AddPara.verbose` — 调试输出开关

注：`resource_confidence` 已从 AddPara 移除，统一由 `Value_Params.resource_confidence` 控制。

---

## 关键文件索引

**核心框架**（修改效用/时间/工具逻辑时查阅）
- `Main_fun/UtilityEvaluator.m` — 效用计算（个体视角 + 全局视角）
- `Main_fun/WorldSim.m` — 时间同步、任务完成度、场景初始化
- `Main_fun/OCFUtils.m` — 工具函数（路径管理、任务排序、资源贡献比例）
- `Compare_Algorithms.m` — 实验入口，**所有参数在此注入**

**各算法详细规范**（仅在修改对应算法时查阅）
- `docs/alg_SA_TabuEnhanced.md` — 我们的主算法（SA + TabuEnhance，算法 7）
- `docs/alg_Qi2023.md` — Qi2023 对比算法（算法 3）
- `docs/alg_Huo2025.md` — Huo2025 对比算法（算法 2）
- `docs/alg_Shi2024.md` — Shi2024 对比算法（算法 4）

**算法 ID 速查**（`algorithms_to_run_ids` 中使用）
```
2=Huo2025  3=Qi2023  4=Shi2024  7=OCF_SAtabu_global（主算法）
```

**算法状态说明**
- `OCF_SAtabu_global_main` — 当前主算法（算法 7），Compare 中使用
- `SA_Value_main` — 早期算法（算法 1），保留代码但 Compare 中不运行
- `SA_TabuEnhanced_Altruistic`、`Fang2025` — 已删除

---

## 目录结构重构记录（2026-03-12）

### 变更内容

**共享辅助函数从 `SA/` 移入 `Main_fun/`**（多算法复用，属于共享工具层）：
- `SA/calc_gaps.m` → `Main_fun/calc_gaps.m`
- `SA/SA_Select_probs.m` → `Main_fun/SA_Select_probs.m`
- `SA/Preference_gain.m` → `Main_fun/Preference_gain.m`
- `SA/update_task_schedule.m` → `Main_fun/update_task_schedule.m`

**算法 1 专属文件从 `SA/` 移入 `comalg/alg1_SA/`**：
- `SA_Value_main.m`、`Overlap_Coalition_Formation.m`、`join_operation.m`、`leave_operation.m`、`Select_probs.m`、`energy_cost.m`

**`comalg/` 子目录统一重命名**：
- `Com_Huo2025` → `alg2_Huo2025`
- `Com_Qi2023` → `alg3_Qi2023`
- `Com_Shi2024` → `alg4_Shi2024`
- `SA_TabuEnhance` → `alg7_OCF_SAtabu`

**旧 `SA/` 目录已删除。**

**同步更新的文件**：
- `Compare_Algorithms.m` — addpath 路径 + all_algorithms folder 字段
- `Main_fun/OCFUtils.m` — `add_project_paths()` 候选路径列表

### 当前三层架构
```
Layer 1 框架层：  Main_fun/（含共享辅助函数）
Layer 2 算法层：  comalg/alg1_SA/、alg2_Huo2025/、alg3_Qi2023/、alg4_Shi2024/、alg7_OCF_SAtabu/
```

