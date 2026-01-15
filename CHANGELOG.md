# 项目整理日志

## 2026-01-13 文件结构重组

### ? 创建的新文件夹

1. **`docs/`** - 文档存储目录
   - 集中存放所有Markdown文档
   - 包含项目说明、使用指南、文件清单等

2. **`results/`** - 结果存储目录
   - 存放所有算法对比实验的.mat文件
   - 自动生成，包含时间戳和SEED信息

### ? 移动的文件

#### 移至 `docs/` 文件夹：
- `COMPARISON_FRAMEWORK_GUIDE.md` - 对比框架使用指南
- `FILE_SUMMARY.md` - 项目文件清单
- `效用计算说明.md` - 效用计算说明

#### 移至 `results/` 文件夹：
- `comparison_results_seed2437_*.mat` - 对比实验结果文件

### ? 新建的文件

1. **`README.md`** (根目录)
   - 项目总体说明
   - 快速开始指南
   - 文件夹结构图
   - 使用建议

2. **`docs/README.md`**
   - 文档目录索引
   - 按用途和读者分类
   - 快速查找指南
   - 阅读建议

3. **`results/README.md`**
   - 结果文件说明
   - 文件命名规则
   - 数据加载方法
   - 批量分析示例

### ? 代码更新

**`Compare_Algorithms.m`**
- 第188-195行：更新结果保存路径为 `results/` 文件夹
- 添加自动创建results文件夹的逻辑

### ? 整理后的目录结构

```
Overlap_Coalition_Formation/
├── ? README.md                    # 项目主说明（新建）
├── ? Compare_Algorithms.m         # 对比框架（已更新）
├── ? Main.m                       # 单算法运行脚本
├── ? [其他.m文件...]
│
├── ? docs/                        # 文档目录（新建）
│   ├── README.md                   # 文档索引（新建）
│   ├── COMPARISON_FRAMEWORK_GUIDE.md
│   ├── FILE_SUMMARY.md
│   └── 效用计算说明.md
│
├── ? results/                     # 结果目录（新建）
│   ├── README.md                   # 结果说明（新建）
│   └── comparison_results_*.mat
│
├── ? SA/                          # SA算法
├── ? Com_Baseline/                # 基线算法
├── ? Com_Huo2025/                 # 对比算法
├── ? Com_Qi2023/                  # 对比算法
├── ? Com_Qin2025/                 # 对比算法
├── ? plots/                       # 可视化函数
└── ? tests/                       # 测试脚本
```

### ? 改进效果

#### 之前的问题：
- ? Markdown文档散落在根目录，难以管理
- ? 实验结果文件混在代码文件中
- ? 缺少统一的文档索引
- ? 项目结构不够清晰

#### 整理后的优势：
- ? 所有文档集中在 `docs/` 文件夹，便于查找和维护
- ? 实验结果自动保存到 `results/` 文件夹，分类清晰
- ? 根目录更简洁，只保留核心代码文件
- ? 每个文件夹都有README说明，结构清晰
- ? 文档有明确的索引和分类

### ? 使用建议

#### 日常开发：
```matlab
% 运行单算法
run Main.m

% 运行对比实验（结果自动保存到results/）
run Compare_Algorithms.m
```

#### 查看文档：
1. 先看根目录 `README.md` 了解项目概况
2. 进入 `docs/` 查看详细文档
3. 查看 `docs/README.md` 找到需要的文档

#### 管理结果：
- 所有实验结果在 `results/` 文件夹
- 查看 `results/README.md` 了解如何加载和分析
- 文件名包含SEED和时间戳，便于追溯

### ? 后续维护

#### 添加新文档时：
1. 将文档放在 `docs/` 文件夹
2. 更新 `docs/README.md` 添加索引

#### 运行实验时：
- 结果会自动保存到 `results/` 文件夹
- 无需手动管理路径

#### 版本控制建议：
- `docs/` 和代码文件应纳入版本控制
- `results/` 中的大型.mat文件建议添加到 `.gitignore`
- 重要实验结果单独备份

### ? 注意事项

1. **不要手动移动** `results/` 中的文件
2. **不要删除** `docs/README.md` 和 `results/README.md`
3. **添加新文档时** 记得更新 `docs/README.md`
4. **清理结果文件前** 确认不再需要

---

**整理日期**: 2026-01-13  
**整理人**: AI Assistant  
**版本**: 1.0
