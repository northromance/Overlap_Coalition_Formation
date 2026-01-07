# Energy Cost 函数测试

本目录包含 `energy_cost.m` 函数的测试脚本。

## 测试文件

### 1. `quick_test_energy.m` - 快速测试 ?
**推荐用于日常验证**

- **用途**: 快速验证基本功能和同步机制
- **运行时间**: < 1秒
- **测试内容**:
  - 单智能体顺序执行
  - 双智能体同步到达

**运行方式**:
```matlab
cd tests
quick_test_energy
```

**预期输出**:
```
=== 测试1: 单智能体执行 ===
任务序列: [1 2]
飞行时间: XX.XX, 执行时间: XX.XX
...

=== 测试2: 双智能体同步到任务2 ===
智能体1到达任务2: XX.XX
智能体2到达任务2: XX.XX
? 同步成功!
```

---

### 2. `test_energy_cost.m` - 完整测试 ?
**用于详细验证和调试**

- **用途**: 全面测试所有功能
- **运行时间**: 1-2秒
- **测试内容**:
  1. 基础功能测试（单智能体）
  2. 同步机制测试（多智能体协同）
  3. 速度调整验证

**运行方式**:
```matlab
cd tests
test_energy_cost
```

**测试项目**:

#### 测试1: 基础功能
- 验证飞行距离计算
- 验证飞行时间计算
- 验证执行时间计算
- 验证能量消耗计算
- 对比预期值与实际值

#### 测试2: 同步机制
- 模拟多智能体协同任务
- 验证同步到达时间
- 检查联盟结构正确性

#### 测试3: 速度调整
- 测试快慢智能体配合
- 验证降速机制
- 检查速度调整范围

---

## 数据结构说明

### Agents (智能体)
```matlab
agents(i).id       % 智能体ID
agents(i).x        % X坐标
agents(i).y        % Y坐标
agents(i).vel      % 速度
agents(i).fuel     % 燃料消耗系数 (α)
agents(i).beta     % 执行能耗系数 (β)
agents(i).resources % 资源向量 (K×1)
```

### Tasks (任务)
```matlab
tasks(j).id         % 任务ID
tasks(j).x          % X坐标
tasks(j).y          % Y坐标
tasks(j).priority   % 优先级 (数值越小越先执行)
tasks(j).duration   % 总执行时间
tasks(j).duration_by_resource  % 按资源类型的执行时间 (1×K)
tasks(j).value      % 任务价值
```

### SC (资源联盟结构)
```matlab
SC{m}         % 任务m的资源分配 (N×K矩阵)
SC{m}(i, k)   % 智能体i分配给任务m的资源类型k的数量
```

### Value_Params (参数)
```matlab
Value_Params.N  % 智能体数量
Value_Params.M  % 任务数量
Value_Params.K  % 资源类型数量
```

---

## 关键验证点

### ? 应该通过的检查

1. **飞行距离准确性**: 误差 < 1e-6
2. **能量消耗公式**: `energy = t_fly × fuel + t_exec × beta`
3. **同步到达**: 协同任务的智能体到达时间差 < 0.01
4. **速度调整**: 快速智能体会降速等待慢速智能体
5. **任务排序**: 按 priority 升序执行

### ?? 可能的问题

1. **速度限制**: 如果 `v_min = 0.3 × v_max`，极端情况下可能无法完全同步
2. **时间累积误差**: 浮点运算可能导致微小误差
3. **空任务列表**: 应该返回零值而不是报错

---

## 调试建议

### 查看中间变量
在 `energy_cost.m` 中添加调试输出:
```matlab
fprintf('Debug: task_idx=%d, dist=%.2f, t_fly=%.2f\n', task_idx, dist, t_fly);
```

### 可视化路径
```matlab
figure;
hold on;
plot(agents(1).x, agents(1).y, 'ro', 'MarkerSize', 10);  % 起点
plot([tasks.x], [tasks.y], 'b*', 'MarkerSize', 10);      % 任务点
% 绘制路径...
```

### 检查联盟结构
```matlab
for m = 1:M
    fprintf('任务%d参与者: ', m);
    for i = 1:N
        if any(SC{m}(i, :) > 0)
            fprintf('%d ', i);
        end
    end
    fprintf('\n');
end
```

---

## 修改建议

如果测试失败，检查以下内容:

1. **路径**: 确保 `addpath('../SA')` 正确
2. **数据结构**: 确保所有字段都存在
3. **参数范围**: 速度、距离、时间是否合理
4. **同步逻辑**: SC 结构是否正确设置

---

## 扩展测试

可以添加更多测试场景:

```matlab
% 测试4: 大规模场景
N = 10; M = 20; K = 6;

% 测试5: 边界情况
% - 零距离
% - 零速度
% - 空任务列表

% 测试6: 性能测试
tic;
for i = 1:1000
    energy_cost(...);
end
toc;
```

---

**作者**: GitHub Copilot  
**日期**: 2026-01-07  
**版本**: 1.0
