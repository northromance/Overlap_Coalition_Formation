# 论文图表批量实验脚本说明

本文档说明为论文绘图设计的 5 个批量实验脚本的用途、配置方式、输出结构及注意事项。

---

## 一、脚本总览

| 脚本 | 实验代号 | 覆盖图表 | 输出文件 | 预估耗时 |
|------|----------|----------|----------|----------|
| `Batch_VaryN.m` | Exp-A | 图1a/1b + 图2c + 图3 | `varyN_N4-20_S20_*.mat` | ~2–3h |
| `Batch_VaryM.m` | Exp-B | 图1c/1d | `varyM_M5-20_S20_*.mat` | ~2–3h |
| `Batch_Belief.m` | Exp-C | 图2a/2b | `belief_*.mat` | ~30min |
| `Batch_Ablation.m` | Exp-D | 图4全部 | `ablation_*.mat` | ~1–2h |
| `Single_Viz.m` | Exp-E | 图5全部 | `visualize_*.mat` | ~2min |

所有输出文件保存在 `results/batch/`，文件名含时间戳，格式为 `-v7.3`（支持大文件）。

---

## 二、图表 → 数据需求映射

| 图 | 子图 | 横轴 | 纵轴 | 数据字段 | 来源脚本 |
|----|------|------|------|----------|----------|
| 1a | 变N效用 | N值 | final_utility（mean±std） | `scale_N_results{ni,si}.algs.AlgName.final_utility` | Batch_VaryN |
| 1b | 变N完成度 | N值 | final_completion（mean±std） | `scale_N_results{ni,si}.algs.AlgName.final_completion` | Batch_VaryN |
| 1c | 变M效用 | M值 | final_utility（mean±std） | `scale_M_results{mi,si}.algs.AlgName.final_utility` | Batch_VaryM |
| 1d | 变M完成度 | M值 | final_completion（mean±std） | `scale_M_results{mi,si}.algs.AlgName.final_completion` | Batch_VaryM |
| 2a | 信念误差 | 轮次 | KL/L1误差（per agent） | `belief_results{ci,si}.belief_history` + `true_task_types` | Batch_Belief |
| 2b | 鲁棒性 | 轮次 | 期望价值预测 | `belief_results{ci,si}.belief_history`（3种条件） | Batch_Belief |
| 2c | 效用演化 | 轮次 | convergence_utility | `scale_N_results{ni,si}.algs.AlgName.convergence_utility` | Batch_VaryN |
| 3a | 内循环 | 内层iter | 系统效用 | `scale_N_results{ni,si}.algs.OCF_SAtabu.inner_loop_r50` | Batch_VaryN |
| 4a | 消融演化 | 轮次 | convergence_utility | `ablation_results{ni,si,ci}.convergence_utility` | Batch_Ablation |
| 4b | 消融散点 | seed | final_utility | `ablation_results{ni,si,ci}.final_utility` | Batch_Ablation |
| 5a | 分配矩阵 | 任务 | 智能体 | `viz_data.final_SC` | Single_Viz |
| 5b | 路线/Gantt | 空间/时间 | 路线/时序 | `viz_data.timing` + `viz_data.agents` + `viz_data.tasks` | Single_Viz |

---

## 三、各脚本详细说明

### 3.1 `Batch_VaryN.m`（实验 A）

**用途**：在固定 M=10、K=6 的条件下，遍历 7 种智能体规模，运行 4 个算法，评估规模扩展性。

**参数配置**：
```matlab
N_VALUES = [4, 6, 8, 10, 12, 16, 20];  % 7 种规模
SEEDS    = 1001:1020;                   % 20 个种子
algorithms_to_run_ids = [2, 3, 4, 7];  % Huo2025 / Qi2023 / Shi2024 / OCF_SAtabu
INNER_LOOP_ROUND = 50;                 % 保存第50轮内循环轨迹（用于图3）
```

**输出变量**：

```
scale_N_results{ni, si}           % cell(7, 20)
  .N, .seed, .success, .error
  .algs.(AlgName):
    .final_utility          % scalar
    .final_cost             % scalar
    .final_completion       % scalar
    .convergence_utility    % [100×1]（不足100轮的后缀为NaN）
    .convergence_cost       % [100×1]
    .convergence_completion % [100×1]
    .computation_time       % scalar（秒）
    .inner_loop_r50         % struct（仅 OCF_SAtabu 有有效内容）
      .iteration            % [iter×1]
      .temperature          % [iter×1]
      .current_utility      % [iter×1]
      .best_utility         % [iter×1]
      .num_coalitions       % [iter×1]

scale_config
  .N_values, .M, .K, .seeds
  .alg_ids, .alg_names
  .num_rounds, .max_inner_iter
  .inner_loop_round         % = 50
  .timestamp
```

> **注意**：`inner_loop_r50` 对 Huo2025 / Qi2023 / Shi2024 也会尝试提取，
> 但这三个算法是否记录 `inner_loop` 取决于其自身实现，字段可能为空 struct。
> 若算法轮次不足50轮，则自动取最后一轮的内循环数据。

---

### 3.2 `Batch_VaryM.m`（实验 B）

**用途**：在固定 N=10、K=6 的条件下，遍历 7 种任务规模，评估任务数量的影响。

**参数配置**：
```matlab
M_VALUES = [5, 8, 10, 12, 15, 18, 20];  % 7 种任务规模
SEEDS    = 1001:1020;
N        = 10;  % 固定
algorithms_to_run_ids = [2, 3, 4, 7];
```

**输出变量**：

```
scale_M_results{mi, si}           % cell(7, 20)
  .M, .seed, .success, .error
  .algs.(AlgName):
    .final_utility, .final_completion
    .convergence_utility    % [100×1]
    .convergence_cost, .convergence_completion
    .computation_time

scale_config
  .M_values, .N, .K, .seeds, ...
```

> 此实验不保存内循环轨迹（图3仅需变N实验数据）。

---

### 3.3 `Batch_Belief.m`（实验 C）

**用途**：分析信念演化行为，比较三种初始信念条件下算法的信念收敛过程与效用表现。

**参数配置**：
```matlab
SEEDS      = 1001:1010;                          % 10 个种子
CONDITIONS = {'uniform', 'optimistic', 'pessimistic'};
N=10, M=10, K=6
% 仅运行 OCF_SAtabu (算法 7)
```

**三种初始信念**：

| 条件 | 分布（type1 / type2 / type3） | 含义 |
|------|-------------------------------|------|
| `uniform` | [1/3, 1/3, 1/3] | 默认均匀先验 |
| `optimistic` | [0.1, 0.1, 0.8] | 偏向高价值任务（value=1500） |
| `pessimistic` | [0.8, 0.1, 0.1] | 偏向低价值任务（value=800） |

**输出变量**：

```
belief_results{ci, si}             % cell(3, 10)
  .condition        % 'uniform' / 'optimistic' / 'pessimistic'
  .seed
  .true_task_types  % [M×1] integer，tasks(j).type，用于计算信念误差
  .belief_history   % [num_rounds × N × M × task_type]
                    %   belief_history(r, i, m, :) = agent i 第r轮对任务m的信念分布
  .convergence_utility  % [num_rounds×1]
  .success, .error

belief_config
  .conditions, .N, .M, .K, .seeds
  .task_type_values    % = [800, 1000, 1500]
  .belief_uniform, .belief_optimistic, .belief_pessimistic
  .num_rounds, .timestamp
```

**Python 端计算方法**：

```python
import numpy as np
import scipy.io as sio

data = sio.loadmat('belief_*.mat', simplify_cells=True)
belief_history  = data['belief_results'][0, 0]['belief_history']  # [R, N, M, T]
true_task_types = data['belief_results'][0, 0]['true_task_types']  # [M]
task_values     = [800, 1000, 1500]

# 图2a：L1 信念误差
T = belief_history.shape[3]
true_onehot = np.zeros((len(true_task_types), T))
for m, t in enumerate(true_task_types - 1):  # MATLAB 1-indexed → Python 0-indexed
    true_onehot[m, t] = 1.0
# belief_error[r, i, m] = L1 误差
belief_error = np.sum(np.abs(belief_history - true_onehot[np.newaxis, np.newaxis, :, :]), axis=3)

# 图2b：期望价值预测
tv = np.array(task_values)
expected_value = np.einsum('rnmt,t->rnm', belief_history, tv)  # [R, N, M]
```

> **已知限制**：当前算法接口（`OCF_SAtabu_global_main`）内部会重新调用 `WorldSim.init_value_data` 以均匀先验初始化信念，三种条件的差异**目前未注入算法内部**。若需精确控制初始信念条件，需修改算法接口以支持传入预设 `Value_data`。`belief_history` 当前反映的是均匀初始化后的演化结果。

---

### 3.4 `Batch_Ablation.m`（实验 D）

**用途**：消融实验，评估信念更新模块对算法性能的贡献。

**参数配置**：
```matlab
N_VALUES   = [4, 6, 8, 10, 12, 16, 20];
SEEDS      = 1001:1020;
M          = 10;
CONDITIONS = {'belief_on', 'belief_off'};
% 仅运行 OCF_SAtabu (算法 7)
```

**消融开关**：

| 条件 | `AddPara.enable_belief_update` | 含义 |
|------|-------------------------------|------|
| `belief_on` | `true` | 启用贝叶斯信念更新（完整算法） |
| `belief_off` | `false` | 禁用，仅使用均匀初始信念 |

**设计亮点**：同一 `(N, seed)` 对共享一次场景生成（`rng(seed)` 保证相同的随机场景），两种条件独立 `rng(seed)` 重置后运行，确保公平对比。

**输出变量**：

```
ablation_results{ni, si, ci}       % cell(7, 20, 2)
  .N, .seed
  .belief_on           % logical：true=belief_on, false=belief_off
  .convergence_utility % [100×1]  → 图4a
  .final_utility       % scalar   → 图4b
  .computation_time
  .success, .error

ablation_config
  .N_values, .M, .K, .seeds
  .conditions          % {'belief_on', 'belief_off'}
  .num_rounds, .timestamp
```

**Python 端读取示例**：

```python
data = sio.loadmat('ablation_*.mat', simplify_cells=True)
results = data['ablation_results']      # shape: (7, 20, 2)
config  = data['ablation_config']

# 提取 belief_on 条件下 N=10（ni=3，0-indexed）所有 seed 的 final_utility
final_on  = [results[3, si, 0]['final_utility'] for si in range(20)]
final_off = [results[3, si, 1]['final_utility'] for si in range(20)]
```

---

### 3.5 `Single_Viz.m`（实验 E）

**用途**：单次完整运行，保存所有可视化所需的原始数据，用于绘制分配矩阵（图5a）和 Gantt / 路线图（图5b）。

**参数配置**：
```matlab
SEED = 1001;  N = 10;  M = 10;  K = 6;
% 仅运行 OCF_SAtabu，AddPara.verbose = 1
```

**输出变量**：

```
viz_data
  .N, .M, .K, .seed

  % 场景原始数据
  .agents(i)            % struct array [1×N]
    .id, .x, .y, .vel
    .resources          % [K×1]
    .fuel, .wait_fuel, .beta, .Emax, .detprob

  .tasks(j)             % struct array [1×M]
    .id, .x, .y, .type, .value
    .resource_demand    % [1×K]
    .duration, .priority

  % 分配结果
  .final_SC             % cell{M×1}，SC{m} = [N×K]  → 图5a
  .task_completion_degrees  % [M×1]

  % 时间同步结果（WorldSim 调用一次返回）
  .timing(i)            % struct array [1×N]  → 图5b
    .t_fly_total        % scalar
    .t_wait_total       % scalar
    .t_exec_total       % scalar
    .task_sequence      % [1×num_tasks_assigned]
    .start_times        % [1×num_tasks_assigned]
    .execution_times    % [1×num_tasks_assigned]

  % 收敛曲线（辅助参考）
  .convergence_utility  % [num_r×1]

  % 全局指标
  .coalition_utility, .total_global_cost
  .total_completed_value, .computation_time
```

**Python 绘图示例**：

```python
data = sio.loadmat('visualize_*.mat', simplify_cells=True)
vd = data['viz_data']

# 图5a：分配矩阵热力图（任务 m 的 N×K 资源分配）
import matplotlib.pyplot as plt
SC = vd['final_SC']   # list of M matrices, each [N, K]
fig, axes = plt.subplots(2, 5, figsize=(15, 6))
for m, ax in enumerate(axes.flat):
    ax.imshow(SC[m], aspect='auto', cmap='Blues')
    ax.set_title(f'Task {m+1}')

# 图5b：Gantt 图
timing = vd['timing']  # list of N dicts
for i, t in enumerate(timing):
    for k, task_id in enumerate(t['task_sequence']):
        start = t['start_times'][k]
        dur   = t['execution_times'][k]
        plt.barh(i, dur, left=start, label=f'T{task_id}')
```

---

## 四、快速验证（小规模测试）

在正式运行前，建议先用以下小规模配置验证脚本正确性：

```matlab
% Batch_VaryN.m 小规模测试
SEEDS    = 1001:1003;
N_VALUES = [5, 8];

% Batch_VaryM.m 小规模测试
SEEDS    = 1001:1003;
M_VALUES = [5, 8];

% Batch_Belief.m 小规模测试
SEEDS = 1001;   % 单个种子，3种条件

% Batch_Ablation.m 小规模测试
SEEDS    = 1001:1003;
N_VALUES = [5];

% Single_Viz.m 无需修改，直接运行
```

**验证检查点**：

| 脚本 | 检查内容 |
|------|----------|
| `Batch_VaryN` | `scale_N_results{1,1}.algs.OCF_SAtabu.inner_loop_r50.iteration` 是否为非空向量 |
| `Batch_Belief` | `belief_results{1,1}.belief_history` 尺寸是否为 `[100 × 10 × 10 × 3]` |
| `Batch_Ablation` | `ablation_results{1,1,1}.belief_on == true` 且 `{1,1,2}.belief_on == false` |
| `Single_Viz` | `viz_data.timing(1).task_sequence` 非空；`sum(cellfun(@(s) any(s(:)>1e-9), viz_data.final_SC))` > 0 |

---

## 五、注意事项

1. **NaN 填充**：收敛曲线长度为 `num_rounds`（=100），若算法提前收敛，后缀保持 `NaN`。Python 端读取时使用 `np.nanmean` 或前向填充（`ffill`）处理。

2. **内循环轨迹**：`inner_loop_r50` 仅对 `OCF_SAtabu` 有完整数据（该算法在每一轮结束时记录 `history_data.inner_loop{r}`）。其他算法若无此记录则字段为空 struct，Python 端需做 `None` 判断。

3. **信念条件注入**：`Batch_Belief.m` 当前版本运行时使用算法内部的均匀初始化。若需精确注入 `optimistic` / `pessimistic` 初始信念，需修改 `OCF_SAtabu_global_main` 接口，支持外部传入 `Value_data`（已用 TODO 注释标注）。

4. **随机种子**：场景生成用 `rng(seed)`，每个算法运行前再次 `rng(seed)` 重置，保证不同算法在完全相同的随机场景下公平对比。

5. **文件大小**：使用 `-v7.3` 格式（HDF5），支持超过 2GB 的变量。Python 使用 `scipy.io.loadmat` 或 `h5py` 读取。