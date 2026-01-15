# 结果文件夹说明

此文件夹用于存储所有算法对比实验的结果数据。

## ? 文件命名规则

```
comparison_results_seed[随机种子]_[时间戳].mat
```

**示例**:
```
comparison_results_seed2437_20260113_203025.mat
```

其中：
- `seed2437`: 实验使用的随机数种子为2437
- `20260113_203025`: 实验运行时间为2026年01月13日 20:30:25

## ? 文件内容

每个 `.mat` 文件包含以下变量：

### 1. results (结构体)
包含所有算法的完整输出：
- `results.alg1.name`: 算法名称
- `results.alg1.Value_data`: 联盟结构和效用数据
- `results.alg1.history_data`: 算法运行历史
- `results.alg1.computation_time`: 计算时间
- `results.alg2...`: 其他算法的结果

### 2. comparison_stats (结构体)
性能统计指标：
- 总效用
- 联盟数量
- 任务完成率
- 资源利用率
- 计算时间
- 智能体参与度
- 等...

### 3. agents (结构体数组)
实验场景中的智能体数据

### 4. tasks (结构体数组)
实验场景中的任务数据

### 5. Value_Params (结构体)
算法参数配置

### 6. WORLD (结构体)
世界空间参数

### 7. scenario_info (结构体)
场景信息（SEED、创建时间等）

### 8. enabled_algorithms (元胞数组)
本次实验启用的算法列表

## ? 如何加载结果

```matlab
% 加载特定结果文件
load('results/comparison_results_seed2437_20260113_203025.mat');

% 查看算法名称
fieldnames(results)

% 查看第一个算法的效用
results.alg1.Value_data(1).totalvalue

% 查看对比统计
comparison_stats.alg1
```

## ? 查找特定实验

### 按SEED查找
```matlab
% 查找所有使用SEED=2437的实验
dir('results/comparison_results_seed2437_*.mat')
```

### 按日期查找
```matlab
% 查找2026年1月13日的实验
dir('results/comparison_results_*20260113_*.mat')
```

## ? 批量分析

```matlab
% 加载所有结果文件进行批量分析
result_files = dir('results/comparison_results_*.mat');

for i = 1:length(result_files)
    filename = fullfile('results', result_files(i).name);
    data = load(filename);
    
    % 提取数据进行分析
    fprintf('文件: %s\n', result_files(i).name);
    fprintf('  SEED: %d\n', data.scenario_info.SEED);
    fprintf('  算法数量: %d\n', length(fieldnames(data.results)));
    % ... 更多分析
end
```

## ?? 文件管理建议

### 命名约定
文件名自动生成，包含SEED和时间戳，无需手动修改。

### 备份建议
- 重要实验结果应定期备份到其他位置
- 可以按实验类型创建子文件夹分类存储

### 清理策略
- 测试性运行的结果可以定期清理
- 正式实验结果应长期保存
- 建议保留文件至少到论文发表

## ? 注意事项

1. **不要手动修改** .mat文件中的数据
2. **不要重命名**结果文件（会导致时间戳信息丢失）
3. 如需筛选数据，**复制后再处理**
4. 大型实验建议创建子文件夹分类管理

## ? 相关文档

- [对比框架使用指南](../docs/COMPARISON_FRAMEWORK_GUIDE.md)
- [项目主README](../README.md)

---

**自动生成**: 由 `Compare_Algorithms.m` 自动创建和管理
