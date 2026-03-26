# 批量实验脚本使用指南

本文档说明 2026-03-25 重构后的批量实验体系：新增了哪些共享工具、如何运行各脚本、
各脚本的职责边界，以及如何读取产出的 `.mat` 文件。

---

## 一、重构概要（相较旧版的变化）

### 新增共享工具（`Main_fun/` 目录）

| 文件 | 作用 |
|------|------|
| `build_scenario.m` | 统一场景生成函数，封装 WORLD/tasks/agents 构建逻辑 |
| `get_all_algorithms.m` | 统一算法注册表，返回含 id/name/func/folder/color 的 cell array |

**意义**：以前每个脚本内嵌 ~50 行相同的场景生成代码，参数容易漂移。
现在所有脚本调用 `build_scenario(seed, cfg)` 一行完成，共享参数通过
`Exp_Config.ScenarioCfg` 统一管理。

### 参数管理变化（`experiments/Exp_Params.m`）

`Exp_Params.m` 末尾新增了一个公共块 `Exp_Config.ScenarioCfg`，
包含所有场景维度参数（世界边界、智能体属性、任务需求模板等）。
各批量脚本在调用 `build_scenario` 前，只需在 `ScenarioCfg` 上覆盖本实验变化的
`N`、`M`、`K`，其余参数自动继承。

### 内循环轨迹（图3a）归属调整

`Batch_VaryN.m` **不再**保存 `inner_loop_r50` 字段。
图3a 所需的内循环轨迹改由 `Single_Viz.m`（单批次深度运行）提供，
更适合单次细粒度分析，避免批量实验保存大量中间数据。

---

## 二、快速启动

### 前提

1. MATLAB 当前目录切换到项目根目录（`Compare_Algorithms.m` 所在位置）
2. 首次运行任一批量脚本前，无需手动 `addpath`，脚本内部自动添加

### 运行顺序建议

```
正式数据收集顺序（耗时从短到长）：
  1. Single_Viz.m      (~2 min)  — 先验证场景与算法能跑通
  2. Batch_Belief.m    (~30 min) — 信念演化
  3. Batch_Ablation.m  (~1-2 h)  — 消融实验
  4. Batch_VaryN.m     (~2-3 h)  — 变 N 规模
  5. Batch_VaryM.m     (~2-3 h)  — 变 M 规模
```

---

## 三、各脚本职责与配置

### 3.1 `Single_Viz.m`（单批次可视化 + 内循环数据）

**覆盖图表**：图3a（内循环轨迹）、图5a（分配矩阵）、图5b（Gantt/路线图）

**要修改的参数**（位于脚本开头从 `Exp_Config.SingleViz` 读取）：
```matlab
% 在 Exp_Params.m 中修改：
Exp_Config.SingleViz.SEED = 2476;   % 要分析的单个种子
Exp_Config.SingleViz.N = 10;
Exp_Config.SingleViz.M = 10;
```

**输出**：`results/batch/visualize/N10_M10_K6_seed2476_YYYYMMDD_HHMMSS.mat`
```
viz_data
  .agents, .tasks              % 场景原始数据
  .final_SC                    % cell{M×1}，SC{m}=[N×K] → 图5a
  .timing(i)                   % struct array [1×N]     → 图5b
  .convergence_utility         % [num_rounds×1]
  .coalition_utility, .total_global_cost, .total_completed_value
  .computation_time
```

> 若算法记录了 `history_data.inner_loop`，可在脚本结束后手动提取：
> ```matlab
> inner_loop_data = history_data.inner_loop{round_idx};
> ```

---

### 3.2 `Batch_VaryN.m`（实验 A — 变智能体数量）

**覆盖图表**：图1a（效用 vs N）、图1b（完成度 vs N）、图2c（效用收敛曲线）

**要修改的参数**（位于 `Exp_Params.m` 的 `Exp_Config.VaryN` 块）：
```matlab
Exp_Config.VaryN.N_VALUES             = [4, 6, 8, 10, 12];  % 要遍历的 N 值
Exp_Config.VaryN.M                    = 10;                  % 固定任务数
Exp_Config.VaryN.SEEDS                = 2476:1:2477;         % 随机种子列表
Exp_Config.VaryN.algorithms_to_run_ids = [2, 3, 4, 7];      % 要运行的算法 ID
```

**输出**：`results/batch/varyN/N4-12_M10_K6_S2_YYYYMMDD_HHMMSS.mat`
```
scale_N_results{ni, si}     % cell(length(N_VALUES), length(SEEDS))
  .N, .seed, .success, .error
  .algs.(AlgName)            % AlgName = 'Huo2025'/'Qi2023'/'Shi2024'/'OCF_SAtabu'
    .final_utility           % 最终轮联盟效用
    .final_cost              % 最终轮全局成本
    .final_completion        % 最终轮平均完成度
    .final_completed_value   % 最终轮总完成价值
    .convergence_utility     % [num_rounds×1]
    .convergence_cost        % [num_rounds×1]
    .convergence_completion  % [num_rounds×1]
    .convergence_completed_value % [num_rounds×1]
    .computation_time        % 算法运行耗时（秒）

scale_config
  .N_values, .M, .K, .seeds, .alg_ids, .alg_names
  .num_rounds, .max_inner_iter, .timestamp
```

**Python 读取示例**：
```python
import scipy.io as sio, numpy as np

data = sio.loadmat('N4-12_M10_K6_S2_*.mat', simplify_cells=True)
res  = data['scale_N_results']   # shape: (n_N, n_seeds)
cfg  = data['scale_config']

N_values = cfg['N_values'].flatten()

# 提取 OCF_SAtabu 在各 N 下的 final_utility（均值±标准差）
alg = 'OCF_SAtabu'
means, stds = [], []
for ni in range(len(N_values)):
    vals = [res[ni, si]['algs'][alg]['final_utility']
            for si in range(res.shape[1])
            if res[ni, si]['success']]
    means.append(np.mean(vals))
    stds.append(np.std(vals))
```

---

### 3.3 `Batch_VaryM.m`（实验 B — 变任务数量）

**覆盖图表**：图1c（效用 vs M）、图1d（完成度 vs M）

**要修改的参数**（`Exp_Config.VaryM` 块）：
```matlab
Exp_Config.VaryM.M_VALUES             = [8, 10, 12];
Exp_Config.VaryM.N                    = 6;
Exp_Config.VaryM.SEEDS                = 2476:1:2477;
Exp_Config.VaryM.algorithms_to_run_ids = [3, 4, 7];
```

**输出**：`results/batch/varyM/N6_M8-12_K6_S2_YYYYMMDD_HHMMSS.mat`
```
scale_M_results{mi, si}
  .M, .seed, .success, .error
  .algs.(AlgName)
    .final_utility, .final_cost, .final_completion
    .final_completed_value        ← 本次新增字段
    .convergence_utility, .convergence_cost, .convergence_completion
    .convergence_completed_value  ← 本次新增字段
    .computation_time
```

---

### 3.4 `Batch_Belief.m`（实验 C — 信念演化）

**覆盖图表**：图2a（信念误差随轮次）、图2b（期望价值预测演化）

**两种信念条件**（`Exp_Config.Belief.CONDITIONS`）：

| 条件 | 含义 |
|------|------|
| `uniform` | 所有智能体均匀先验 [1/T, 1/T, 1/T] |
| `heterogeneous` | 每智能体偏向低/中/高价值中某一类，带随机扰动 |

**要修改的参数**（`Exp_Config.Belief` 块）：
```matlab
Exp_Config.Belief.SEEDS = 2476:1:2477;
Exp_Config.Belief.N = 10;
Exp_Config.Belief.M = 10;
```

**输出**：`results/batch/belief/N10_M10_K6_S2_YYYYMMDD_HHMMSS.mat`
```
belief_results{ci, si}    % cell(2, length(SEEDS))，ci=1: uniform, ci=2: heterogeneous
  .condition              % 'uniform' 或 'heterogeneous'
  .seed
  .true_task_types        % [M×1] 各任务真实类型（1/2/3）
  .true_task_values       % [M×1] 各任务真实价值
  .init_belief_matrix     % [N×T] 本条件的初始信念矩阵
  .belief_history         % [num_rounds × N × M × task_type]
  .convergence_utility    % [num_rounds×1]
  .success, .error
```

**Python 计算信念误差**：
```python
import numpy as np, scipy.io as sio

data = sio.loadmat('belief_*.mat', simplify_cells=True)
res  = data['belief_results']   # shape: (2, n_seeds)

# 取 uniform 条件，第一个 seed
entry = res[0, 0]
bh    = entry['belief_history']       # [R, N, M, T]
types = entry['true_task_types'] - 1  # 转 0-indexed

T = bh.shape[3]
true_onehot = np.zeros((len(types), T))
for m, t in enumerate(types):
    true_onehot[m, t] = 1.0

# L1 误差：[R, N, M]
l1_err = np.sum(np.abs(bh - true_onehot[np.newaxis, np.newaxis]), axis=3)
mean_err_per_round = l1_err.mean(axis=(1, 2))   # [R]
```

---

### 3.5 `Batch_Ablation.m`（实验 D — 消融实验）

**覆盖图表**：图4a（收敛曲线 belief_on vs off）、图4b（最终效用散点）

**两种条件**（`Exp_Config.Ablation.CONDITIONS = {'belief_on', 'belief_off'}`）：
相同场景 (N, seed) 各跑一次，仅 `AddPara.enable_belief_update` 不同。

**要修改的参数**（`Exp_Config.Ablation` 块）：
```matlab
Exp_Config.Ablation.N_VALUES = [10];
Exp_Config.Ablation.SEEDS    = 2476:1:2477;
```

**输出**：`results/batch/ablation/N10-10_M10_K6_S2_YYYYMMDD_HHMMSS.mat`
```
ablation_results{ni, si, ci}   % cell(n_N, n_seeds, 2)
  .N, .seed
  .belief_on           % logical：ci=1→true，ci=2→false
  .convergence_utility % [num_rounds×1]
  .final_utility       % scalar
  .final_task_completion % scalar
  .computation_time
  .success, .error
```

---

## 四、`build_scenario` 与 `get_all_algorithms` 直接调用

### `build_scenario`

```matlab
% 在自定义脚本中使用（需已 addpath Main_fun）
run('experiments/Exp_Params.m');   % 加载公共参数（含 ScenarioCfg）
cfg = Exp_Config.ScenarioCfg;
cfg.N = 8;  cfg.M = 10;  cfg.K = 6;
[WORLD, tasks, agents, task_type_demands] = build_scenario(2476, cfg);
```

**注意**：`build_scenario` 内部调用 `rng('default'); rng(seed)`，
因此每次调用会重置随机状态。若需要在调用后使用确定性随机数，
在 `build_scenario` 之后再次 `rng(seed)` 重置。

### `get_all_algorithms`

```matlab
all_algs = get_all_algorithms();
% 过滤需要运行的算法
ids = [3, 7];
enabled = all_algs(cellfun(@(a) ismember(a.id, ids), all_algs));

% 调用算法
for i = 1:length(enabled)
    alg = enabled{i};
    [Value_data, history_data] = alg.func(agents, tasks, AddPara, Value_Params);
end
```

**算法 ID 速查**：

| ID | name | 说明 |
|----|------|------|
| 2 | `Huo2025` | 对比基线 |
| 3 | `Qi2023` | 对比基线 |
| 4 | `Shi2024` | 对比基线 |
| 7 | `OCF_SAtabu` | 主算法（SA + TabuEnhanced + 全局效用） |

---

## 五、常见问题

**Q：修改了 `Exp_Params.m` 中的参数，如何确保所有脚本都用最新值？**
A：直接重新运行目标脚本即可，每个脚本开头通过 `run(fullfile(script_dir, 'Exp_Params.m'))` 重新加载。

**Q：如何在同一次实验中对比不同 N_VALUES？**
A：修改 `Exp_Config.VaryN.N_VALUES` 后运行 `Batch_VaryN.m`，结果会包含所有 N 值的数据，Python 端按 `scale_config.N_values` 索引即可。

**Q：`Single_Viz.m` 如何获取内循环轨迹（图3a）？**
A：`history_data.inner_loop` 是 cell array，`history_data.inner_loop{r}` 是第 r 轮的内循环记录。
运行 `Single_Viz.m` 后，在 MATLAB 工作区执行：
```matlab
% 提取第 50 轮的内循环轨迹
r = 50;
inner = history_data.inner_loop{r};
% inner.iteration, inner.temperature, inner.current_utility, inner.best_utility
```
然后将 `inner` 一并保存进 `viz_data` 或单独保存。

**Q：结果文件太大，Python 读取很慢怎么办？**
A：使用 `h5py` 按需读取字段，而非 `scipy.io.loadmat` 一次性加载全部：
```python
import h5py
with h5py.File('varyN_*.mat', 'r') as f:
    # 仅读取 OCF_SAtabu 的 final_utility
    pass  # 路径结构视 MATLAB 版本而定，建议先用 loadmat 探明结构
```
