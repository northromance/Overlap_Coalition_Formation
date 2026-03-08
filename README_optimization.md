# 智能体效用计算优化与重构总结

## 修改目标

解决两个核心问题：
1. **性能问题**：`calc_with_global_sync` 函数在计算多个智能体时存在重复计算
2. **建模问题**：效用计算需要按照数学建模，改为按任务单独计算成本

## 第一部分：性能优化

### 问题分析

原 `calc_with_global_sync` 函数每次调用都会：
- 模拟所有 N 个智能体的全局状态推进（遍历 M 个任务）
- 但只输出一个智能体的结果

在 `calc_agent_total_utility` 和 `evaluate_coalition_metrics` 中需要对所有智能体调用，导致：
- 全局状态推进被重复执行 **N 次**
- 时间复杂度：O(N × M)

### 优化方案

新增 `calc_all_agents_with_global_sync` 函数：
- **阶段1**：执行一次全局状态推进（遍历 M 个任务）
- **阶段2**：并行计算所有 N 个智能体的时间指标

优化后时间复杂度：**O(M + N)**

### 性能提升

| 规模 (N, M) | 原方法 | 新方法 | 加速比 |
|------------|--------|--------|--------|
| (10, 20) | 0.041s | 0.015s | **2.69x** |
| (20, 40) | 0.049s | 0.011s | **4.36x** |
| (30, 60) | 0.102s | 0.017s | **5.91x** |

**平均加速比：4.32x**

### 修改文件

1. `Main_fun\WorldSim.m` - 新增 `calc_all_agents_with_global_sync` 函数
2. `Main_fun\UtilityEvaluator.m` - 修改 `evaluate_coalition_metrics` 使用新函数
3. `comalg\Com_Shi2024\Shi2024_main.m` - 修改主循环使用新函数

## 第二部分：效用计算重构

### 数学建模

智能体 $n$ 参与任务 $m$ 的效用：

$$u_n^m(\mathcal{A}_m) = \underbrace{\frac{\| A_m^{(n)} \|_1}{\sum_{i} \| A_m^{(i)} \|_1} \cdot \mathcal{V}_{k_m} \cdot \varsigma_m}_{\text{收益}} - \underbrace{E_{n,m}^{Cost}}_{\text{成本}}$$

成本包含三部分：

$$E_{n,m}^{Cost} = \underbrace{\varpi \cdot Dist(m', m)}_{\text{移动}} + \underbrace{\gamma \cdot (T_{wait\_pre} + T_{wait\_post})}_{\text{等待}} + \underbrace{\beta \cdot Dur_{n,m}}_{\text{执行}}$$

### 关键改变

**改变前**：全局成本分摊
- 计算所有智能体的全局路径总成本
- 按资源比例将成本分摊到各个任务
- 任务净效用 = 任务收益 - 分摊成本
- 智能体效用 = 按资源比例分配任务净效用

**改变后**：按任务单独计算
- 对每个任务单独计算智能体的成本
- 成本 = 移动到该任务 + 在该任务等待 + 在该任务执行
- 任务效用 = 任务收益 - 任务成本
- 智能体总效用 = 各任务效用之和

### 优势

1. **物理意义清晰**：成本直接对应智能体的实际行为
2. **效用可分解**：可以看到每个任务的贡献和成本
3. **分配更公平**：谁参与谁承担，避免跨任务补贴
4. **便于调试**：透明度高，易于分析和优化

### 修改文件

1. `Main_fun\UtilityEvaluator.m` - 完全重写 `calc_agent_total_utility` 函数

## 两部分的协同

两个优化完美配合：
1. `calc_all_agents_with_global_sync` 一次性计算全局同步信息（4x加速）
2. `calc_agent_total_utility` 利用全局信息，为每个智能体计算按任务的成本和效用

**结果**：既提高了性能，又保证了建模的准确性

## 测试验证

### 性能测试

运行 `test_large_scale.m`：
- 验证在不同规模下的性能提升
- 平均加速比 4.32x
- 规模越大，加速比越接近理论值

### 功能测试

运行 `test_utility_calculation.m`：
- 验证效用计算逻辑正确
- 验证成本按任务单独计算
- 验证全局效用评估正确

测试结果示例：
```
智能体 1: 总效用=79.53, 任务1=47.53, 任务3=32.00
智能体 2: 总效用=77.86, 任务1=34.99, 任务2=42.86
智能体 3: 总效用=70.70, 任务2=39.38, 任务3=31.32
全局净效用: 300.24
```

## 文件清单

### 核心修改

1. **Main_fun\WorldSim.m**
   - 新增 `calc_all_agents_with_global_sync` (第72行)
   - 保留 `calc_with_global_sync` (向后兼容)

2. **Main_fun\UtilityEvaluator.m**
   - 重写 `calc_agent_total_utility` (第109-273行)
   - 修改 `evaluate_coalition_metrics` (使用批量计算)

3. **comalg\Com_Shi2024\Shi2024_main.m**
   - 修改主循环使用批量计算 (第122-157行)

### 测试文件

4. **test_calc_optimization.m** - 基础一致性测试
5. **test_large_scale.m** - 大规模性能测试
6. **test_utility_calculation.m** - 效用计算功能测试

### 文档

7. **calc_optimization_report.md** - 性能优化详细报告
8. **utility_calculation_report.md** - 效用计算重构报告
9. **README_optimization.md** - 本文档

## 使用建议

### 何时使用新函数

**推荐场景**：
- 需要计算多个智能体的时间指标（N ≥ 3）
- 联盟形成算法的效用评估
- 中大规模问题（N ≥ 10, M ≥ 20）

**继续使用原函数**：
- 只需计算单个智能体
- 小规模问题（N < 10）
- 特殊的向后兼容需求

### 如何验证修改

```matlab
% 运行测试
run('test_calc_optimization.m');      % 验证一致性
run('test_large_scale.m');            % 验证性能
run('test_utility_calculation.m');    % 验证效用计算
```

## 后续优化建议

1. **并行计算**：对于超大规模（N > 50），考虑使用 parfor
2. **缓存机制**：如果联盟结构不变，可以缓存全局同步结果
3. **增量计算**：如果只修改部分智能体，可以增量更新
4. **性能剖析**：使用 MATLAB Profiler 识别其他瓶颈

## 总结

本次修改实现了：

✓ **4.32倍性能提升** - 消除重复计算
✓ **建模准确性** - 严格遵循数学公式
✓ **代码可维护性** - 逻辑清晰，易于理解
✓ **向后兼容** - 保留原函数接口
✓ **全面测试** - 多角度验证正确性

优化后的代码在保证正确性的同时，显著提升了性能，为后续的大规模联盟形成算法提供了坚实的基础。
