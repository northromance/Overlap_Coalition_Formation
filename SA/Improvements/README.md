# SA 改进算法说明

本文件夹包含基于 SA_Value_main 的多个改进版本，用于对比测试不同的优化策略。

## 算法列表

| ID | 算法名称 | 文件名 | 改进点 | 状态 |
|----|---------|--------|--------|------|
| 7  | SA_TabuEnhanced | SA_Value_TabuEnhanced_main.m | 结合禁忌搜索，避免重复访问相同解 | 待实现 |
| 8  | SA_AdaptiveAlpha | SA_Value_AdaptiveAlpha_main.m | 根据搜索状态自适应调整降温系数 | 待实现 |
| 9  | SA_ImprovedTemp | SA_Value_ImprovedTemp_main.m | 根据接受率动态调整温度策略 | 待实现 |
| 10 | SA_MultiStart | SA_Value_MultiStart_main.m | 多起点重启，降低对初始解的依赖 | 待实现 |
| 11 | SA_HybridGreedy | SA_Value_HybridGreedy_main.m | 高温探索+低温贪心的混合策略 | 待实现 |
| 12 | SA_EnhancedNeighbor | SA_Value_EnhancedNeighbor_main.m | 扩展邻域操作（swap/shift） | 待实现 |

## 使用方法

### 1. 在 Compare_Algorithms.m 中选择算法

编辑 `Main_fun/Compare_Algorithms.m` 文件，修改 `algorithms_to_run_ids` 变量：

```matlab
% 示例1：对比原始 SA 与所有改进版本
algorithms_to_run_ids = [1, 7, 8, 9, 10, 11, 12];

% 示例2：对比原始 SA、Qi2023 和两个改进版本
algorithms_to_run_ids = [1, 4, 7, 9];

% 示例3：只测试 SA 改进算法
algorithms_to_run_ids = [7, 8, 9, 10, 11, 12];
```

### 2. 运行对比实验

```matlab
% 在 MATLAB 命令行中运行
Compare_Algorithms;
```

### 3. 查看结果

结果会保存在 `results/` 文件夹中，包括：
- 性能对比图表
- 详细的数值结果
- 资源分配详情

## 实现建议

每个改进算法的实现步骤：

1. **复制原始代码**：从 `SA_Value_main.m` 复制主体代码到对应的改进文件
2. **实现改进点**：根据文件中的 TODO 注释实现具体改进
3. **测试验证**：单独运行该算法，确保功能正确
4. **对比分析**：使用 Compare_Algorithms.m 与其他算法对比

## 改进算法详细说明

### SA_TabuEnhanced（禁忌搜索增强）
- **核心思想**：维护一个禁忌表，记录最近访问过的解，避免循环搜索
- **实现要点**：
  - 使用队列存储最近 N 个 SC 结构（N=20-50）
  - 计算新解与禁忌表中解的相似度（汉明距离或资源分配差异）
  - 如果相似度过高，拒绝该移动
  - 特赦准则：如果新解优于历史最优，忽略禁忌

### SA_AdaptiveAlpha（自适应降温系数）
- **核心思想**：根据搜索状态动态调整 alpha
- **实现要点**：
  - 跟踪连续未改进的迭代次数 k_no_improve
  - 找到更好解时：alpha = max(0.85, alpha - 0.05)（加速收敛）
  - 长时间未改进时：alpha = min(0.98, alpha + 0.03)（增强探索）

### SA_ImprovedTemp（改进温度策略）
- **核心思想**：根据接受率动态调整降温速度
- **实现要点**：
  - 跟踪最近 N 次迭代的接受率
  - 接受率过低（<0.1）：减缓降温（alpha=0.98）
  - 接受率过高（>0.5）：加速降温（alpha=0.90）
  - 接受率适中：使用标准 alpha

### SA_MultiStart（多起点重启）
- **核心思想**：运行多次 SA，每次使用不同初始解
- **实现要点**：
  - 设置 num_restarts = 3-5
  - 每次重启使用不同随机种子
  - 调整每次运行的轮数：num_rounds / num_restarts
  - 返回所有运行中的最优解

### SA_HybridGreedy（混合贪心策略）
- **核心思想**：高温时随机探索，低温时贪心优化
- **实现要点**：
  - 设置温度阈值 T_greedy = T_0 * 0.3
  - T > T_greedy：使用原始 SA 概率接受
  - T <= T_greedy：只接受改进解（贪心）

### SA_EnhancedNeighbor（增强邻域搜索）
- **核心思想**：扩展邻域操作，增加搜索空间连通性
- **实现要点**：
  - 除了 join/leave，增加 swap 和 shift 操作
  - swap：两个智能体交换部分资源分配
  - shift：将智能体的资源从任务 A 转移到任务 B
  - 随机选择操作类型

## 性能评估指标

对比时关注以下指标：
- **总效用**：所有任务的净收益总和
- **任务完成度**：平均任务完成度
- **收敛速度**：达到最优解的迭代次数
- **计算时间**：算法运行时间
- **稳定性**：多次运行的结果方差

## 注意事项

1. 所有改进算法的输入输出接口必须与 `SA_Value_main` 完全一致
2. 实现时保持代码风格与原算法一致
3. 添加详细的注释说明改进点
4. 在 `AddPara.verbose = true` 时输出调试信息
5. 确保随机种子设置正确，保证结果可复现
