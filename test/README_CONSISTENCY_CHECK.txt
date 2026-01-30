% 联盟一致性检查系统使用说明
% =====================================

## 概述

本系统提供了一个统一的联盟一致性检查函数 `check_coalition_consistency.m`，
用于验证联盟形成算法输出的正确性。该函数整合了以下检查功能：

1. 全局一致性检查
2. 资源约束检查（支持OCF和Non-OCF两种模式）
3. 结构对应关系检查
4. 自洽性检查
5. 能量可行性检查

## 文件结构

```
E:\Overlap_Coalition_Formation\
├── check_coalition_consistency.m          # 统一的检查函数（主文件）
├── test\
│   ├── test_coalition_consistency.m       # 测试脚本
│   └── example_use_consistency_check.m    # 使用示例
└── comalg\
    ├── Com_Qi2023\
    │   └── Qi2023_main.m                  # 已集成检查（第303行）
    └── Com_Shi2024\
        └── Shi2024_main.m                 # 已集成检查（第147行）
```

## 主要功能

### 1. check_coalition_consistency.m

**功能描述：**
根据算法类型（OCF或Non-OCF）执行相应的一致性检查。

**函数签名：**
```matlab
[is_valid, error_log] = check_coalition_consistency(Value_data, agents, tasks, Value_Params, algorithm_type)
```

**输入参数：**
- `Value_data`     : 1xN 结构体数组，包含所有智能体的数据
- `agents`         : 智能体数组
- `tasks`          : 任务数组
- `Value_Params`   : 全局参数结构体 (M, N, K等)
- `algorithm_type` : 算法类型字符串
  - `'OCF'`     : 重叠联盟（资源可复用）
  - `'Non-OCF'` : 非重叠联盟（资源不可复用）

**输出参数：**
- `is_valid`   : 布尔值，true表示所有检查通过
- `error_log`  : 错误信息元胞数组

**检查内容：**

#### 检查1：全局一致性检查
- 验证所有智能体的SC是否完全一致
- 验证所有智能体的coalitionstru是否完全一致
- 确保分布式系统达成全局共识

#### 检查2：资源约束检查
- **OCF模式**：检查单任务资源投入是否超过智能体上限（资源可复用）
- **Non-OCF模式**：检查所有任务的资源总和是否超过智能体上限（资源不可复用）

#### 检查3：结构对应关系检查
- 验证coalitionstru与SC的双向映射关系
- 确保在SC中有资源投入的智能体都在coalitionstru中
- 确保在coalitionstru中的成员都在SC中有资源投入

#### 检查4：自洽性检查
- 验证每个智能体的resources_matrix与SC的一致性
- 确保个体视图与全局视图保持同步

#### 检查5：能量可行性检查
- 验证每个智能体的能量约束是否满足
- 检查是否存在能量不足的情况
- 确保生成的联盟结构在实际上是可行的

## 使用方法

### 方法1：在算法主文件中使用（推荐）

在算法主函数的末尾，返回结果之前添加检查代码：

```matlab
function [Value_data, history_data] = YourAlgorithm_main(agents, tasks, AddPara, Value_Params)
    % ... 算法主体代码 ...

    %% 最终一致性检查
    fprintf('\n[YourAlgorithm] 执行最终一致性检查...\n');
    [is_valid, error_log] = check_coalition_consistency(...
        Value_data, agents, tasks, Value_Params, 'OCF');  % 或 'Non-OCF'

    if ~is_valid
        warning('[YourAlgorithm] 联盟一致性检查发现 %d 处问题！', length(error_log));
        history_data.consistency_errors = error_log;
    else
        fprintf('✅ [YourAlgorithm] 所有一致性检查通过！\n');
    end

    return;
end
```

### 方法2：独立测试

```matlab
% 运行算法
[Value_data, history_data] = Qi2023_main(agents, tasks, AddPara, Value_Params);

% 执行检查
[is_valid, error_log] = check_coalition_consistency(...
    Value_data, agents, tasks, Value_Params, 'OCF');

% 查看结果
if ~is_valid
    disp('检查失败，错误列表：');
    for i = 1:length(error_log)
        fprintf('%d. %s\n', i, error_log{i});
    end
end
```

### 方法3：批量测试多个算法

参考 `test/example_use_consistency_check.m` 中的示例5。

## 已集成的算法

以下算法已经集成了统一的一致性检查：

1. **Qi2023_main.m** (OCF模式)
   - 位置：`comalg/Com_Qi2023/Qi2023_main.m:303`
   - 检查类型：OCF（重叠联盟）

2. **Shi2024_main.m** (OCF模式)
   - 位置：`comalg/Com_Shi2024/Shi2024_main.m:147`
   - 检查类型：OCF（重叠联盟）

## 测试

### 运行单元测试

```matlab
cd test
test_coalition_consistency
```

测试脚本会验证以下场景：
- 测试1：正常情况（合法的OCF联盟结构）
- 测试2：全局不一致
- 测试3：资源越界（OCF模式）
- 测试4：结构不对应
- 测试5：自洽性错误
- 测试6：Non-OCF模式资源总和越界

### 查看使用示例

```matlab
cd test
edit example_use_consistency_check.m
```

## 与旧版本的区别

### 旧版本（已废弃）
- `check_data_consistency.m` - 针对重叠联盟的检查
- `check_OCF_consistency.m` - 针对重叠联盟的检查
- `check_validate_feasibility.m` - 可行性检查

### 新版本（推荐使用）
- `check_coalition_consistency.m` - 统一的检查函数
  - 整合了所有检查功能
  - 支持OCF和Non-OCF两种模式
  - 代码更简洁，易于维护
  - 提供详细的中文注释

## 常见问题

### Q1: 检查失败时应该怎么办？

A: 检查失败通常表示算法实现存在问题。建议：
1. 查看error_log中的具体错误信息
2. 检查算法中的数据同步逻辑
3. 验证资源分配是否正确
4. 确认能量计算是否准确

### Q2: OCF和Non-OCF模式有什么区别？

A:
- **OCF模式**：重叠联盟，资源可复用。检查单任务资源投入是否超过上限。
- **Non-OCF模式**：非重叠联盟，资源不可复用。检查所有任务的资源总和是否超过上限。

### Q3: 如何在新算法中集成检查？

A: 在算法主函数的末尾，返回结果之前，添加以下代码：

```matlab
%% 最终一致性检查
fprintf('\n执行最终一致性检查...\n');
[is_valid, error_log] = check_coalition_consistency(...
    Value_data, agents, tasks, Value_Params, 'OCF');  % 根据算法类型选择

if ~is_valid
    warning('联盟一致性检查发现问题！');
    history_data.consistency_errors = error_log;
end
```

### Q4: 检查会影响性能吗？

A: 检查会增加一定的计算开销，但通常可以忽略不计。如果需要，可以：
1. 在开发阶段启用检查
2. 在生产阶段通过参数控制是否执行检查
3. 使用调试模式开关

### Q5: 如何添加自定义检查？

A: 可以在 `check_coalition_consistency.m` 中添加新的子函数，并在主函数中调用。
参考现有的子函数结构（如 `check_global_consensus`）。

## 维护说明

### 添加新的检查项

1. 在 `check_coalition_consistency.m` 中添加新的子函数
2. 在主函数中调用新的子函数
3. 更新本文档的"检查内容"部分
4. 在测试脚本中添加相应的测试用例

### 修改现有检查逻辑

1. 找到对应的子函数（如 `check_resource_constraints_OCF`）
2. 修改检查逻辑
3. 更新相关注释
4. 运行测试脚本验证修改

## 联系方式

如有问题或建议，请联系开发团队。

## 更新日志

- 2026-01-30: 创建统一的检查系统
  - 整合了三个旧的检查函数
  - 支持OCF和Non-OCF两种模式
  - 添加了详细的中文注释
  - 创建了测试脚本和使用示例
  - 在Qi2023和Shi2024算法中集成了检查
