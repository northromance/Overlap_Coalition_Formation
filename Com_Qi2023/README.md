# Qi2023 算法模块

## 算法来源
- **论文**: [在此填写论文标题]
- **作者**: Qi et al.
- **年份**: 2023
- **期刊/会议**: [在此填写]

## 文件结构
```
Com_Qi2023/
├── Qi2023_main.m       # 算法主入口
├── README.md           # 本说明文件
└── [其他辅助函数]       # 根据需要添加
```

## 算法描述

### 核心思想
[在此描述算法的核心思想]

### 算法流程
1. 初始化阶段
   - 
2. 迭代阶段
   - 
3. 输出阶段
   - 

### 与其他算法的区别
| 特性 | SA_Value (本文) | Huo2025 | Qi2023 |
|------|-----------------|---------|--------|
| 联盟形成机制 | | | |
| 效用计算 | | | |
| 信息共享 | | | |

## 接口说明

### 输入
```matlab
[Value_data, history_data] = Qi2023_main(agents, tasks, AddPara, Value_Params)
```

- `agents`: 智能体结构体数组
- `tasks`: 任务结构体数组
- `AddPara`: 附加参数
- `Value_Params`: 算法参数
  - `.N`: 智能体数量
  - `.M`: 任务数量
  - `.K`: 资源类型数量
  - `.num_rounds`: 迭代轮数

### 输出
- `Value_data.totalvalue`: 总效用
- `Value_data.coalitionstru`: 联盟结构矩阵 (M×N)
- `Value_data.agentresources`: 资源分配矩阵 (N×M×K)
- `Value_data.num_coalitions`: 形成的联盟数量

## 使用方法

### 单独运行
```matlab
addpath('Main_fun', 'Com_Qi2023');
[agents, tasks, Value_Params] = initialize_scenario(2437);
[Value_data, history_data] = Qi2023_main(agents, tasks, struct(), Value_Params);
fprintf('总效用: %.2f\n', Value_data.totalvalue);
```

### 在对比框架中运行
在 `Compare_Algorithms.m` 中设置:
```matlab
algorithms_to_run_ids = [1, 4];  % 运行SA_Value和Qi2023
```

## TODO
- [ ] 实现算法核心逻辑
- [ ] 添加辅助函数
- [ ] 验证效用计算
- [ ] 添加历史记录功能
