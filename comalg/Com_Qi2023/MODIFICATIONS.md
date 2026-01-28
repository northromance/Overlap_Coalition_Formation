# Qi2023_main 算法修改说明

## 修改日期
2026-01-27

## 修改概述
本次修改完全重写了 `Qi2023_main.m` 文件，实现了基于论文伪代码的 **Preference Gravity-Guided Tabu Search (PGG-TS)** 算法，用于分布式重叠联盟形成问题。

---

## 主要修改内容

### 1. 函数名称修正
- **修改前**: `function [Value_data, history_data] = PGG_TS_main(...)`
- **修改后**: `function [Value_data, history_data] = Qi2023_main(...)`
- **原因**: 统一函数名与文件名，符合项目命名规范，确保 `Compare_Algorithms.m` 能正确调用

### 2. 算法结构优化
根据论文伪代码（alg_structure 文件），重新组织了算法流程：

#### 2.1 初始化阶段 (Initialization)
```matlab
% Algorithm Line: "Calculate F_n^(z)(1) and P_n^(z)(1) by (26) and (27)"
% Algorithm Line: "To get the initial coalition structure SC(1)..."
```
- 为每个智能体计算初始偏好引力 F 和选择概率 P
- 基于概率 P 进行初始资源分配
- 记录初始效用值

#### 2.2 主循环结构 (Main Loop)
```matlab
% Algorithm Line: "Loop ∀n∈N"
% Algorithm Line: "End loop if k_stable > K_len or k > K_max"
```

每轮迭代包含以下步骤：

**A. 离开操作 (Leave Operation)**
```matlab
% Algorithm Line: "UAV n randomly selects partial consumable resource
%                  to leave the current coalition"
```
- 智能体随机选择部分资源离开当前联盟
- 离开概率 p_leave = 0.3（可调参数）

**B. 偏好引力计算 (Gravity Calculation)**
```matlab
% Algorithm Line: "Calculate F_n^(z)(k) and P_n^(z)(k) by (26) and (27)"
```
- 计算偏好引力 F：`F = (Value × Remaining_Demand) / Distance²`
- 计算选择概率 P：使用 Boltzmann Softmax `P ∝ exp(F/Γ)`

**C. 交换操作 (Exchange Operation)**
```matlab
% Algorithm Line: "UAV n make an exchange operation based on
%                  selection probability vector P_n^(z)(k)"
```
- 基于概率 P 使用轮盘赌选择新任务
- 将资源重新分配到选中的任务

**D. 禁忌表检查 (Tabu Check)**
```matlab
% Algorithm Line: "If SC_new^(k) ∉ Tabu_SC"
```
- 检查新联盟结构是否在禁忌表中
- 如果在禁忌表中，直接拒绝

**E. 效用判断 (Utility Check)**
```matlab
% Algorithm Line: "If SC_new^(k) ≻_n SC^(k)"
% Algorithm Line: "SC^(k+1) ← SC_new^(k); k_stable ← 0"
% Algorithm Line: "Else: SC^(k+1) ← SC^(k); k_stable ← k_stable + 1"
```
- 计算新结构的全局效用
- 如果效用改进，接受新结构并重置稳定计数器
- 否则保持旧结构，增加稳定计数器

**F. 温度更新 (Temperature Update)**
```matlab
% Algorithm Line: "Update Boltzmann coefficient Γ(k+1) by (28)"
% Algorithm Line: "k ← k+1"
```
- 降温：`Γ(k+1) = α × Γ(k)`，其中 α = 0.98
- 更新禁忌表（FIFO队列）

### 3. 算法参数设置
```matlab
L_tabu = 10;    % 禁忌表长度 (Algorithm Input: L_tabu)
K_len = 20;     % 稳定阈值 (Algorithm Input: K_len)
K_max = num_rounds; % 最大迭代次数 (Algorithm Input: K_max)
Gamma = 100;    % 初始温度 (Boltzmann coefficient Γ)
alpha = 0.98;   % 降温系数
```

### 4. 辅助函数实现

#### 4.1 `calculate_gravity_and_prob`
- 实现论文公式 (26) 和 (27)
- 计算偏好引力 F 和选择概率 P
- 使用 Softmax 稳定性处理避免数值溢出

#### 4.2 `execute_exchange_operation`
- 基于概率矩阵 P 进行轮盘赌选择
- 考虑任务需求上限，避免过度分配
- 清空旧分配，建立新分配

#### 4.3 `get_SC_hash`
- 将联盟结构转换为字符串哈希
- 用于禁忌表比较

#### 4.4 `is_in_tabu`
- 检查结构是否在禁忌表中

#### 4.5 `update_tabu_list`
- 更新禁忌表（FIFO队列）
- 保持表长度不超过 L_tabu

#### 4.6 `init_value_data`
- 初始化 Value_data 结构
- 保持与项目其他算法的接口一致

#### 4.7 `record_history`
- 记录每轮的历史数据
- 包括联盟结构、效用值、迭代次数

### 5. 代码注释改进
- 所有关键步骤都添加了对应的算法伪代码行号引用
- 使用中英文双语注释，提高可读性
- 添加了详细的函数文档说明

### 6. 输出信息优化
```matlab
fprintf('[Qi2023] Generating Initial Coalition Structure...\n');
fprintf('[Qi2023] Initial utility: %.4f\n', current_utility);
fprintf('[Qi2023] Round %d: Utility = %.4f, Stability = %d, Temp = %.4f\n', ...);
fprintf('[Qi2023] Algorithm converged after %d iterations.\n', k_iter-1);
```
- 所有输出信息添加 `[Qi2023]` 前缀，便于识别
- 输出关键指标：效用、稳定性、温度

---

## 算法核心思想

### 1. 偏好引力场 (Preference Gravity)
- 模拟物理引力场，任务对智能体的吸引力与任务价值、剩余需求成正比，与距离平方成反比
- 引导智能体选择高价值、近距离、需求未满足的任务

### 2. 禁忌搜索 (Tabu Search)
- 维护一个禁忌表，记录最近访问过的联盟结构
- 避免算法陷入循环，提高搜索效率

### 3. Boltzmann 温度调节
- 初始高温：允许较大的探索空间
- 逐渐降温：逐步收敛到局部最优
- 平衡探索 (Exploration) 与利用 (Exploitation)

---

## 与其他算法的接口兼容性

### 输入接口
```matlab
function [Value_data, history_data] = Qi2023_main(agents, tasks, AddPara, Value_Params)
```
- 与 `SA_Value_main`、`Huo2025_main` 等算法保持一致
- 可直接在 `Compare_Algorithms.m` 中调用

### 输出接口
- `Value_data`: 包含最终联盟结构 SC
- `history_data`: 包含每轮的效用和联盟结构历史

---

## 测试文件

创建了 `tests/test_Qi2023.m` 测试文件，包含以下测试：

1. **基本功能测试**: 验证算法能否正常运行
2. **输出格式测试**: 检查返回值结构是否正确
3. **收敛性测试**: 验证算法是否收敛
4. **效用改进测试**: 检查效用是否随迭代改进
5. **资源约束测试**: 验证资源分配是否满足约束

### 运行测试
```matlab
cd tests
test_Qi2023
```

---

## 已知问题与改进方向

### 当前实现的简化
1. **离开操作**: 使用简单的随机离开策略，可改进为基于效用的智能离开
2. **哈希函数**: 使用 `mat2str` 生成哈希，大规模问题建议使用 `DataHash`
3. **特赦准则**: 未实现 Aspiration Criterion（允许接受禁忌表中的优秀解）

### 未来改进方向
1. 实现自适应参数调整（L_tabu, K_len, p_leave）
2. 添加多目标优化支持
3. 实现并行化加速
4. 添加更详细的性能分析工具

---

## 参考文献
- Qi et al. (2023). "Preference Gravity-Guided Tabu Search for Distributed Overlapping Coalition Formation"
- 算法伪代码见: `comalg/Com_Qi2023/alg_structure`

---

## 修改者
Claude Sonnet 4.5

## 审核状态
- [x] 代码编写完成
- [x] 测试文件创建
- [x] 文档编写完成
- [ ] 用户验证通过
- [ ] 集成测试通过
