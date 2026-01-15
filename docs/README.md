# 文档目录

本目录包含项目的所有文档和说明文件。

## ? 文档列表

### ? 核心文档

#### [COMPARISON_FRAMEWORK_GUIDE.md](COMPARISON_FRAMEWORK_GUIDE.md)
**算法对比框架完整使用指南**
- 快速开始教程
- 配置参数说明
- 添加新算法的详细步骤
- 性能指标解释
- 调试技巧
- 常见问题解答

**适合人群**: 所有使用对比框架的用户

---

#### [FILE_SUMMARY.md](FILE_SUMMARY.md)
**项目文件详细清单**
- 所有文件的功能说明
- 文件夹结构图
- 核心优势总结
- 性能指标清单
- 快速上手指南

**适合人群**: 新用户了解项目结构

---

#### [效用计算说明.md](效用计算说明.md)
**效用函数和计算方法说明**
- 效用函数定义
- 计算公式
- 参数解释

**适合人群**: 需要了解算法细节的研究人员

---

## ?? 文档分类

### 按用途分类

| 类别 | 文档 | 用途 |
|------|------|------|
| **入门指南** | COMPARISON_FRAMEWORK_GUIDE.md | 学习如何使用对比框架 |
| **项目概览** | FILE_SUMMARY.md | 快速了解项目结构 |
| **算法理论** | 效用计算说明.md | 深入理解算法原理 |

### 按读者分类

| 读者类型 | 推荐阅读顺序 |
|----------|--------------|
| **新用户** | 1. FILE_SUMMARY.md<br>2. COMPARISON_FRAMEWORK_GUIDE.md |
| **算法开发者** | 1. COMPARISON_FRAMEWORK_GUIDE.md<br>2. 效用计算说明.md |
| **论文作者** | 1. 效用计算说明.md<br>2. COMPARISON_FRAMEWORK_GUIDE.md |

## ? 快速查找

### 我想...

- **运行对比实验** → [COMPARISON_FRAMEWORK_GUIDE.md](COMPARISON_FRAMEWORK_GUIDE.md) - 快速开始章节
- **添加新算法** → [COMPARISON_FRAMEWORK_GUIDE.md](COMPARISON_FRAMEWORK_GUIDE.md) - 添加新算法章节  
- **了解文件结构** → [FILE_SUMMARY.md](FILE_SUMMARY.md)
- **理解效用计算** → [效用计算说明.md](效用计算说明.md)
- **查看性能指标** → [COMPARISON_FRAMEWORK_GUIDE.md](COMPARISON_FRAMEWORK_GUIDE.md) - 性能指标章节
- **解决问题** → [COMPARISON_FRAMEWORK_GUIDE.md](COMPARISON_FRAMEWORK_GUIDE.md) - 常见问题章节

## ? 阅读建议

### 第一次使用项目？

1. 先阅读 [FILE_SUMMARY.md](FILE_SUMMARY.md) 了解项目整体结构
2. 然后阅读 [COMPARISON_FRAMEWORK_GUIDE.md](COMPARISON_FRAMEWORK_GUIDE.md) 的快速开始部分
3. 运行 `test_framework.m` 验证环境
4. 运行 `Compare_Algorithms.m` 体验对比功能

### 要开发新算法？

1. 详细阅读 [COMPARISON_FRAMEWORK_GUIDE.md](COMPARISON_FRAMEWORK_GUIDE.md) 中的"添加新算法"章节
2. 参考 `Com_Baseline/Greedy_Baseline_main.m` 的实现
3. 理解 [效用计算说明.md](效用计算说明.md) 中的计算方法
4. 单独测试算法后再加入对比框架

### 准备发表论文？

1. 阅读 [效用计算说明.md](效用计算说明.md) 确保理解算法原理
2. 查看 [COMPARISON_FRAMEWORK_GUIDE.md](COMPARISON_FRAMEWORK_GUIDE.md) 中的性能指标说明
3. 使用对比框架生成标准的对比数据和图表
4. 结果文件保存在 `results/` 文件夹中

## ? 其他资源

### 项目主要文件
- **主README**: [../README.md](../README.md) - 项目总体说明
- **对比框架**: [../Compare_Algorithms.m](../Compare_Algorithms.m) - 主程序
- **测试脚本**: [../test_framework.m](../test_framework.m) - 环境测试

### 示例代码
- **基线算法**: [../Com_Baseline/Greedy_Baseline_main.m](../Com_Baseline/Greedy_Baseline_main.m)
- **SA算法**: [../SA/SA_Value_main.m](../SA/SA_Value_main.m)

### 结果数据
- **实验结果**: [../results/](../results/) - 所有对比实验结果

## ? 文档维护

### 文档更新
如果您修改了框架或添加了新功能，请相应更新文档。

### 建议改进
如果您发现文档有不清楚的地方，欢迎提出改进建议。

### 新文档
如果需要添加新的说明文档，请放在此目录下，并更新本README。

---

**文档目录创建日期**: 2026-01-13  
**最后更新**: 2026-01-13
