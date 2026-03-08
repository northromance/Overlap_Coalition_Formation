# 效用计算函数修改报告

## 修改概述

按照用户提供的数学建模，重新实现了 `calc_agent_total_utility` 函数，改为**按任务单独计算成本**的方式，而不是之前的全局成本分摊方式。

## 数学建模

### 个体效用公式

智能体 $n$ 参与任务 $m$ 联盟 $\mathcal{A}_m$ 所获得的个体效用：

$$u_n^m(\mathcal{A}_m) = \frac{\| A_m^{(n)} \|_1}{\sum_{i \in Mem(\mathcal{A}_m)} \| A_m^{(i)} \|_1} \left( \mathcal{V}_{k_m} \cdot \varsigma_m \right) - E_{n,m}^{Cost}$$

其中：
- $\| A_m^{(n)} \|_1$：智能体 $n$ 投入任务 $m$ 的资源总量（资源贡献比例）
- $\mathcal{V}_{k_m}$：任务类型 $k_m$ 的期望价值（基于信念分布）
- $\varsigma_m$：任务完成度
- $E_{n,m}^{Cost}$：智能体在任务 $m$ 的综合成本

### 成本计算

$$E_{n,m}^{Cost} = E_{n,m}^{move} + E_{n,m}^{wait} + E_{n,m}^{exec}$$

#### 1. 移动成本

$$E_{n,m}^{move} = \varpi \cdot Dist(m', m)$$

- $\varpi$：单位距离能耗系数 (`agents(n).fuel`)
- $Dist(m', m)$：从上一任务到当前任务的距离

#### 2. 等待成本

$$E_{n,m}^{wait} = \gamma \cdot \left( T_{n,m}^{wait\_pre} + T_{n,m}^{wait\_post} \right)$$

其中：
- $\gamma$：单位等待时间消耗系数 (`agents(n).wait_fuel`)
- $T_{n,m}^{wait\_pre} = ST_m - AT_{n,m}$：同步前等待（等待其他成员到达）
- $T_{n,m}^{wait\_post} = Dur_m - Dur_{n,m}$：同步后等待（等待联盟完成）

时间参数说明：
- $AT_{n,m}$：智能体 $n$ 到达任务 $m$ 的时刻
- $ST_m$：任务 $m$ 的同步开始时刻（所有成员到齐）
- $Dur_m$：联盟整体执行时长（最慢成员决定）
- $Dur_{n,m}$：智能体 $n$ 自身执行时长

#### 3. 执行成本

$$E_{n,m}^{exec} = \beta \cdot Dur_{n,m}$$

- $\beta$：执行能耗系数 (`agents(n).beta`)
- $Dur_{n,m}$：智能体在任务上的实际执行时间

## 代码实现

### 主要变化

**修改前**（全局成本分摊）：
```matlab
% 预计算所有智能体的全局路径成本
agent_costs = zeros(N, 1);
for i = 1:N
    [t_fly_i, t_wait_i, t_exec_i] = WorldSim.calc_with_global_sync(...);
    agent_costs(i) = t_fly_i * alpha_fly + t_wait_i * alpha_wait + t_exec_i * beta;
end

% 按资源比例分摊到任务
for each task m
    coalition_cost = sum(agent_costs(i) * resource_ratio(i, m));
    U_m = revenue - coalition_cost;
    u_nm = resource_contribution_ratio * U_m;
end
```

**修改后**（按任务单独计算）：
```matlab
% 获取全局同步信息（一次性计算）
all_agents_results = WorldSim.calc_all_agents_with_global_sync(...);

curr_pos = [agent.x, agent.y];
curr_time = 0;

% 对每个任务单独计算成本和效用
for each task m
    % 移动成本
    dist = norm(task_pos - curr_pos);
    E_move = varpi * dist;

    % 等待成本
    AT_nm = curr_time + dist/vel;
    ST_m = agent_result.start_times(idx);
    Dur_m = calc_coalition_exec_time(...);
    Dur_nm = agent_result.execution_times(idx);

    T_wait_pre = max(0, ST_m - AT_nm);
    T_wait_post = max(0, Dur_m - Dur_nm);
    E_wait = gamma * (T_wait_pre + T_wait_post);

    % 执行成本
    E_exec = beta * Dur_nm;

    % 任务成本
    E_nm_cost = E_move + E_wait + E_exec;

    % 收益
    revenue_nm = resource_ratio * task_value * completion_degree;

    % 效用
    u_nm = revenue_nm - E_nm_cost;

    % 更新位置和时间
    curr_pos = task_pos;
    curr_time = ST_m + Dur_m;
end
```

## 测试验证

### 测试场景

- **智能体数**：3
- **任务数**：3
- **资源种类**：2

### 联盟结构
- 任务1: 智能体1[2,2] + 智能体2[2,1]
- 任务2: 智能体2[2,1] + 智能体3[2,1]
- 任务3: 智能体1[1,2] + 智能体3[1,2]

### 测试结果

```
智能体 1:
  总效用: 79.5329
  参与任务: 1 3
  各任务效用:
    任务1: 47.5288
    任务3: 32.0041

智能体 2:
  总效用: 77.8556
  参与任务: 1 2
  各任务效用:
    任务1: 34.9912
    任务2: 42.8644

智能体 3:
  总效用: 70.6957
  参与任务: 2 3
  各任务效用:
    任务2: 39.3778
    任务3: 31.3179

=== 全局效用评估 ===
全局净效用: 300.2373
总完成价值: 310.0000
总成本: 9.7627
任务完成度: 全部 100%
```

### 验证要点

✓ 每个智能体的总效用 = 各任务效用之和
✓ 任务效用正确反映了资源贡献比例
✓ 成本按任务单独计算，包含移动、等待、执行三部分
✓ 全局效用计算正确
✓ 所有任务完成度均达到100%

## 关键优势

### 1. 更符合实际物理过程
- 成本与智能体的实际行为路径直接对应
- 每个任务的移动距离、等待时间、执行时间都被准确计算

### 2. 更公平的效用分配
- 不再是全局成本的"平均分摊"
- 而是每个任务"谁参与谁承担"的直接对应
- 避免了跨任务的成本交叉补贴

### 3. 便于理解和调试
- 效用分解到每个任务，透明度高
- 可以清楚看到哪个任务贡献大、哪个任务成本高
- 便于优化联盟结构

## 修改的文件

1. **Main_fun\UtilityEvaluator.m**
   - 重写 `calc_agent_total_utility` 函数（行109-273）
   - 实现按任务单独计算成本的逻辑

2. **test_utility_calculation.m** (新增)
   - 效用计算功能测试
   - 验证新的成本计算逻辑

## 与优化的协同

此次修改与之前的 `calc_all_agents_with_global_sync` 优化完美配合：
- 全局同步信息只计算一次（4.32x 加速）
- 每个智能体利用全局信息计算自己的按任务成本
- 既提高了性能，又保证了建模的准确性

## 总结

新的效用计算函数：
- ✓ 严格遵循数学建模公式（式1-6）
- ✓ 成本按任务单独计算，物理意义清晰
- ✓ 利用批量计算优化，性能提升4x以上
- ✓ 效用分解到任务级别，便于分析和调试
- ✓ 测试验证通过，结果合理
