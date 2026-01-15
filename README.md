# 联盟形成算法对比框架

## ? 项目结构

```
Overlap_Coalition_Formation/
│
├── ? Main.m                           # 原始单算法运行脚本
├── ? Compare_Algorithms.m             # 多算法对比框架（主入口）
├── ? initialize_scenario.m            # 统一场景初始化函数
├── ? compare_results.m                # 结果对比分析函数
├── ? test_framework.m                 # 框架测试脚本
├── ? README.md                        # 本文件
│
├── ? docs/                            # ? 文档目录
│   ├── COMPARISON_FRAMEWORK_GUIDE.md   # 对比框架使用指南
│   ├── FILE_SUMMARY.md                 # 文件清单
│   └── 效用计算说明.md                  # 效用计算说明
│
├── ? results/                         # ? 结果存储目录
│   └── comparison_results_*.mat        # 对比实验结果文件
│
├── ? SA/                              # 模拟退火算法（本文算法）
│   ├── SA_Value_main.m                 # SA算法主函数
│   ├── Overlap_Coalition_Formation.m   # 联盟形成核心算法
│   └── [其他SA相关函数...]
│
├── ? Com_Baseline/                    # 贪心基线算法
│   ├── Greedy_Baseline_main.m          # 主函数
│   └── README.md                       # 算法说明
│
├── ? Com_Huo2025/                     # Huo2025对比算法
├── ? Com_Qi2023/                      # Qi2023对比算法
├── ? Com_Qin2025/                     # Qin2025对比算法
│
├── ? plots/                           # 可视化函数
│   ├── plot_algorithm_comparison.m     # 算法对比图表
│   ├── plot_main_results.m             # 主结果可视化
│   └── [其他绘图函数...]
│
├── ? tests/                           # 测试脚本
└── ? literature/                      # 参考文献

```

## ? 快速开始

### 运行单个算法
```matlab
run Main.m
```

### 运行算法对比
```matlab
run Compare_Algorithms.m
```

### 测试框架
```matlab
run test_framework.m
```

## ? 结果文件说明

所有对比实验结果自动保存在 `results/` 文件夹中，文件命名格式：
```
results/comparison_results_seed[种子]_[时间戳].mat
```

包含内容：
- `results`: 各算法的详细输出
- `comparison_stats`: 性能统计数据
- `agents`, `tasks`: 场景数据
- `Value_Params`: 算法参数
- `scenario_info`: 场景信息

## ? 文档说明

所有项目文档统一存放在 `docs/` 文件夹：

- **[COMPARISON_FRAMEWORK_GUIDE.md](docs/COMPARISON_FRAMEWORK_GUIDE.md)** - 对比框架完整使用指南
- **[FILE_SUMMARY.md](docs/FILE_SUMMARY.md)** - 项目文件详细清单
- **[效用计算说明.md](docs/效用计算说明.md)** - 效用函数计算说明

## ? 添加新算法

1. 在对应的 `Com_XXX/` 文件夹中创建算法主函数
2. 遵循统一的输入输出接口（参考 `Com_Baseline/Greedy_Baseline_main.m`）
3. 在 `Compare_Algorithms.m` 中注册算法
4. 运行对比框架

详细步骤请参考 [对比框架使用指南](docs/COMPARISON_FRAMEWORK_GUIDE.md)

## ? 文件夹用途

| 文件夹 | 用途 | 说明 |
|--------|------|------|
| `docs/` | 存放所有文档 | Markdown文档、说明文件 |
| `results/` | 存放实验结果 | .mat数据文件、对比结果 |
| `SA/` | SA算法实现 | 本文提出的算法 |
| `Com_XXX/` | 对比算法实现 | 各种对比算法 |
| `plots/` | 可视化函数 | 绘图和图表生成 |
| `tests/` | 测试脚本 | 单元测试和功能测试 |
| `literature/` | 参考文献 | 相关论文和资料 |

## ? 使用建议

### 日常开发
- 单算法调试：使用 `Main.m`
- 算法对比：使用 `Compare_Algorithms.m`

### 论文实验
1. 确保所有对比算法都已实现并启用
2. 设置统一的随机数种子
3. 运行 `Compare_Algorithms.m`
4. 结果自动保存到 `results/` 文件夹
5. 使用生成的图表和统计数据

### 结果管理
- 所有 `.mat` 文件自动保存在 `results/` 文件夹
- 文件名包含时间戳，便于追溯
- 可通过SEED值快速定位相同场景的实验

## ? 参考文档

- 快速开始：运行 `test_framework.m` 验证环境
- 详细指南：查看 [docs/COMPARISON_FRAMEWORK_GUIDE.md](docs/COMPARISON_FRAMEWORK_GUIDE.md)
- 文件清单：查看 [docs/FILE_SUMMARY.md](docs/FILE_SUMMARY.md)

## ? 版本信息

- **框架版本**: 1.0
- **创建日期**: 2026-01-13
- **主要算法**: SA_Value (模拟退火联盟形成算法)

