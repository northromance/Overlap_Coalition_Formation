# 路径配置说明

## ? 项目路径结构

```
Overlap_Coalition_Formation/
├── Main_fun/              ? 核心函数（必需）
│   ├── initialize_scenario.m
│   ├── compare_results.m
│   ├── init_value_params.m
│   └── drchrnd.m
│
├── SA/                    ? SA算法（本文算法）
│   ├── SA_Value_main.m
│   └── [其他SA函数...]
│
├── plots/                 ? 可视化函数
│   ├── plot_algorithm_comparison.m
│   ├── plot_main_results.m
│   └── [其他绘图函数...]
│
├── Com_Baseline/          对比算法
│   └── Greedy_Baseline_main.m
│
├── Com_Huo2025/          对比算法
│   ├── Huo2025_main.m
│   ├── Value_init.m
│   └── [其他Huo函数...]
│
├── Com_Qi2023/           对比算法（待实现）
└── Com_Qin2025/          对比算法（待实现）
```

## ? 已修正的路径配置

### Compare_Algorithms.m 路径设置

```matlab
%% 添加路径
% 核心函数路径
addpath("Main_fun\")              % 场景初始化、结果对比等核心函数 ? 新增
addpath("SA\")                    % SA算法
addpath("plots\")                 % 可视化函数
% 添加对比算法路径
addpath("Com_Baseline\")          % 贪心基线算法
addpath("Com_Huo2025\")           # Huo2025算法
addpath("Com_Qi2023\")            % Qi2023算法
addpath("Com_Qin2025\")           % Qin2025算法
```

### 关键修改

**之前的问题** ?:
- 缺少 `Main_fun\` 路径
- 导致无法找到 `initialize_scenario`, `compare_results` 等核心函数

**现在的配置** ?:
- 添加了 `Main_fun\` 路径
- 所有核心函数可正常访问
- 路径设置完整且有序

## ? 各路径包含的关键文件

### Main_fun/ (核心函数)
| 文件 | 用途 |
|------|------|
| `initialize_scenario.m` | 统一场景初始化 |
| `compare_results.m` | 结果对比分析 |
| `init_value_params.m` | 参数初始化 |
| `drchrnd.m` | Dirichlet随机数生成 |

### SA/ (SA算法)
| 文件 | 用途 |
|------|------|
| `SA_Value_main.m` | SA算法主函数 |
| `Overlap_Coalition_Formation.m` | 联盟形成核心 |
| [其他函数] | SA算法辅助函数 |

### plots/ (可视化)
| 文件 | 用途 |
|------|------|
| `plot_algorithm_comparison.m` | 算法对比图表 |
| `plot_main_results.m` | 主结果可视化 |
| [其他函数] | 各种专项可视化 |

### Com_XXX/ (对比算法)
| 文件夹 | 主函数 | 状态 |
|--------|--------|------|
| `Com_Baseline/` | `Greedy_Baseline_main.m` | ? 可用 |
| `Com_Huo2025/` | `Huo2025_main.m` | ? 已适配 |
| `Com_Qi2023/` | `Qi2023_main.m` | ? 待实现 |
| `Com_Qin2025/` | `Qin2025_main.m` | ? 待实现 |

## ? 路径验证

运行验证脚本检查路径配置:

```matlab
run verify_paths.m
```

该脚本会检查:
- ? 所有路径是否正确添加
- ? 核心函数是否可访问
- ? 算法函数是否存在
- ? 可视化函数是否可用
- ? 函数句柄是否可创建

## ?? 其他脚本的路径配置

### test_huo_simple.m
```matlab
addpath('Main_fun');      % 核心函数
addpath('Com_Huo2025');   % Huo算法
addpath('SA');            % SA相关
```

### Main.m (原始脚本)
```matlab
addpath("SA\")
addpath("plots\")
% Main.m 不需要对比算法路径
```

## ? 最佳实践

### 1. 运行前检查
```matlab
% 验证路径
run verify_paths.m

% 确认无误后运行对比
run Compare_Algorithms.m
```

### 2. 添加新算法时
1. 在对应 `Com_XXX/` 文件夹中实现算法
2. 确保 `Compare_Algorithms.m` 已添加该路径
3. 在 `algorithms_to_run` 中注册算法
4. 运行 `verify_paths.m` 验证

### 3. 路径管理原则
- ? 在脚本开头集中添加所有路径
- ? 添加注释说明各路径用途
- ? 按功能分类组织路径
- ? 避免在脚本中间添加路径
- ? 避免重复添加相同路径

## ? 常见路径问题

### 问题1: "未定义函数 'initialize_scenario'"
**原因**: 缺少 `Main_fun\` 路径  
**解决**: 添加 `addpath("Main_fun\")`

### 问题2: "未定义函数 'SA_Value_main'"
**原因**: 缺少 `SA\` 路径  
**解决**: 添加 `addpath("SA\")`

### 问题3: "未定义函数 'Huo2025_main'"
**原因**: 缺少 `Com_Huo2025\` 路径  
**解决**: 添加 `addpath("Com_Huo2025\")`

### 问题4: 函数存在但无法访问
**检查方法**:
```matlab
which function_name  % 查看函数位置
path                 % 查看当前路径列表
```

## ? 路径配置检查清单

使用前确认:

- [ ] `Main_fun\` 已添加（核心函数）
- [ ] `SA\` 已添加（SA算法）
- [ ] `plots\` 已添加（可视化）
- [ ] `Com_Baseline\` 已添加（基线算法）
- [ ] `Com_Huo2025\` 已添加（Huo算法）
- [ ] 运行 `verify_paths.m` 通过所有检查
- [ ] 所有启用的算法函数都可访问

---

**最后更新**: 2026-01-13  
**状态**: ? 路径配置已修正完成
