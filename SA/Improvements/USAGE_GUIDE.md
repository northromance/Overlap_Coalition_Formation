# SA 改进算法框架使用指南

## 📁 项目结构

```
Overlap_Coalition_Formation/
├── SA/
│   ├── SA_Value_main.m              # 原始 SA 算法
│   ├── Improvements/                # 新建：SA 改进算法文件夹
│   │   ├── README.md                # 改进算法详细说明
│   │   ├── quick_compare_configs.m  # 快速对比配置
│   │   ├── test_sa_improvements.m   # 快速测试脚本
│   │   ├── SA_Value_TabuEnhanced_main.m       # 禁忌搜索增强
│   │   ├── SA_Value_AdaptiveAlpha_main.m      # 自适应降温系数
│   │   ├── SA_Value_ImprovedTemp_main.m       # 改进温度策略
│   │   ├── SA_Value_MultiStart_main.m         # 多起点重启
│   │   ├── SA_Value_HybridGreedy_main.m       # 混合贪心策略
│   │   └── SA_Value_EnhancedNeighbor_main.m   # 增强邻域搜索
│   └── ...
├── Main_fun/
│   ├── Compare_Algorithms.m         # 已修改：支持 SA 改进算法
│   └── ...
└── comalg/                          # 对比算法文件夹
    ├── Com_Qi2023/
    ├── Com_Huo2025/
    └── ...
```

## 🎯 快速开始

### 1. 测试改进算法是否正常工作

```matlab
% 在 MATLAB 命令行中运行
cd SA/Improvements
test_sa_improvements
```

这会在小规模场景下快速测试所有改进算法，确保它们能正常运行。

### 2. 运行算法对比

#### 方法 A：使用预定义配置

```matlab
% 打开 quick_compare_configs.m 查看所有预定义配置
edit SA/Improvements/quick_compare_configs.m

% 选择一个配置并运行
algorithms_to_run_ids = [1, 7, 8, 9];  % SA + 3个改进
Compare_Algorithms;
```

#### 方法 B：直接修改 Compare_Algorithms.m

```matlab
% 编辑 Main_fun/Compare_Algorithms.m
edit Main_fun/Compare_Algorithms.m

% 修改第 8 行左右的 algorithms_to_run_ids
algorithms_to_run_ids = [1, 7, 8];  % 你想对比的算法 ID

% 保存后运行
Compare_Algorithms;
```

## 📊 算法 ID 对照表

| ID | 算法名称 | 类型 | 说明 |
|----|---------|------|------|
| 1  | SA_Value | 原始算法 | 你的主算法 |
| 2  | Greedy baseline | 对比算法 | 贪心基线 |
| 3  | Huo2025 | 对比算法 | Huo2025 算法 |
| 4  | Qi2023 | 对比算法 | Qi2023 算法 |
| 5  | Shi2024 | 对比算法 | Shi2024 OCF |
| 6  | PSO | 对比算法 | 粒子群优化 |
| **7**  | **SA_TabuEnhanced** | **SA改进** | **禁忌搜索增强** |
| **8**  | **SA_AdaptiveAlpha** | **SA改进** | **自适应降温系数** |
| **9**  | **SA_ImprovedTemp** | **SA改进** | **改进温度策略** |
| **10** | **SA_MultiStart** | **SA改进** | **多起点重启** |
| **11** | **SA_HybridGreedy** | **SA改进** | **混合贪心策略** |
| **12** | **SA_EnhancedNeighbor** | **SA改进** | **增强邻域搜索** |

## 🔧 常用对比配置

### 配置 1：测试所有 SA 改进
```matlab
algorithms_to_run_ids = [1, 7, 8, 9, 10, 11, 12];
```
**用途**：全面评估所有改进算法的性能

### 配置 2：SA vs 对比算法 vs 最佳改进
```matlab
algorithms_to_run_ids = [1, 3, 4, 7];  % SA + Huo2025 + Qi2023 + TabuEnhanced
```
**用途**：在论文中展示你的算法及其改进版本与其他算法的对比

### 配置 3：温度策略对比
```matlab
algorithms_to_run_ids = [1, 8, 9, 11];  % SA + AdaptiveAlpha + ImprovedTemp + HybridGreedy
```
**用途**：研究不同温度策略的影响

### 配置 4：搜索策略对比
```matlab
algorithms_to_run_ids = [1, 7, 10, 12];  % SA + TabuEnhanced + MultiStart + EnhancedNeighbor
```
**用途**：研究不同搜索策略的影响

### 配置 5：单个改进详细分析
```matlab
algorithms_to_run_ids = [1, 7];  % 只对比 SA 和 TabuEnhanced
```
**用途**：深入分析某个改进算法的行为

## 💡 实现改进算法的步骤

目前所有改进算法都是**模板文件**（调用原始 SA_Value_main），需要你根据需求实现。

### 步骤 1：选择要实现的改进算法

例如，选择 `SA_Value_TabuEnhanced_main.m`（禁忌搜索增强）

### 步骤 2：复制原始算法代码

```matlab
% 打开原始算法
edit SA/SA_Value_main.m

% 复制全部代码到改进算法文件
edit SA/Improvements/SA_Value_TabuEnhanced_main.m
```

### 步骤 3：实现改进点

根据文件中的 TODO 注释和 README.md 中的说明实现改进。

例如，对于 TabuEnhanced：
- 在主循环前初始化禁忌表
- 在每次迭代后将当前解加入禁忌表
- 在接受新解前检查是否在禁忌表中

### 步骤 4：测试验证

```matlab
% 快速测试
cd SA/Improvements
test_sa_improvements

% 完整对比
algorithms_to_run_ids = [1, 7];  % 原始 vs 改进
Compare_Algorithms;
```

## 📈 结果分析

运行 `Compare_Algorithms` 后，结果会保存在 `results/` 文件夹中：

- **性能对比图表**：各算法的效用、完成度等指标对比
- **详细数值结果**：CSV 格式的详细数据
- **资源分配详情**：每个算法的资源分配方案

## ⚠️ 注意事项

1. **接口一致性**：所有改进算法的输入输出必须与 `SA_Value_main` 完全一致
   ```matlab
   function [Value_data, history_data] = SA_Value_XXX_main(agents, tasks, AddPara, Value_Params)
   ```

2. **随机种子**：确保设置随机种子以保证结果可复现
   ```matlab
   if isfield(Value_Params, 'seed')
       rng(Value_Params.seed);
   end
   ```

3. **调试信息**：使用 `AddPara.verbose` 控制输出
   ```matlab
   if AddPara.verbose
       fprintf('  [算法名] 调试信息...\n');
   end
   ```

4. **代码风格**：保持与原算法一致的代码风格和注释格式

## 🚀 推荐工作流程

### 阶段 1：快速验证（1-2天）
1. 运行 `test_sa_improvements.m` 确保框架正常
2. 实现 1-2 个最简单的改进（如 AdaptiveAlpha）
3. 在小规模场景下验证改进效果

### 阶段 2：全面实现（3-5天）
1. 实现所有 6 个改进算法
2. 在中等规模场景下测试
3. 调试和优化代码

### 阶段 3：性能对比（2-3天）
1. 使用 `Compare_Algorithms` 进行全面对比
2. 分析各改进算法的优劣
3. 选择最佳改进方向

### 阶段 4：论文撰写（根据需要）
1. 使用配置 2 生成与对比算法的对比图
2. 使用配置 3/4 分析改进机制的影响
3. 整理实验数据和图表

## 📞 需要帮助？

如果在实现过程中遇到问题：
1. 查看 `SA/Improvements/README.md` 中的详细说明
2. 参考原始 `SA_Value_main.m` 的实现
3. 使用 `AddPara.verbose = true` 查看详细调试信息

## 📝 总结

你现在拥有：
- ✅ 6 个 SA 改进算法的模板文件
- ✅ 修改后的 `Compare_Algorithms.m`，支持灵活的算法对比
- ✅ 快速测试脚本 `test_sa_improvements.m`
- ✅ 预定义的对比配置 `quick_compare_configs.m`
- ✅ 详细的实现指南和文档

下一步：选择一个改进算法开始实现，或者直接运行对比实验！
