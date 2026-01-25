%% test_overlap_logic.m
% 单元测试：验证 overlap_coalition_utility 的 BMBT 逻辑正确性
% 重点检查：g(新增), h(退出), o(维持) 的集合划分是否正确，是否重复计算。

clc; clear; close all;

%% ==================== 1. 模拟环境搭建 (Mocking) ====================
fprintf('正在构建测试环境...\n');

% 设定参数
Value_Params.N = 4; % 4个智能体: n(主角), g(新队友), h(老队友), o(吃瓜群众)
Value_Params.M = 3; % 3个任务: Task 1(老), Task 2(新), Task 3(维持)
Value_Params.K = 1; % 1种资源

% 构造智能体结构体 (agents)
% 为了简化，我们假设所有智能体属性一致，只通过 ID 区分
for i = 1:Value_Params.N
    agents(i).id = i;
    agents(i).pos = [0, 0]; % 位置不重要，我们Mock掉效用计算
end

% 构造任务结构体 (tasks)
for i = 1:Value_Params.M
    tasks(i).id = i;
    tasks(i).pos = [10, 10];
end

% 构造 Value_data (包含信念)
% 简单起见，所有人的 belief 都一样
Value_data.initbelief = struct('type', 'trust'); 
Value_data.other = cell(1, Value_Params.N);
for i = 1:Value_Params.N
    Value_data.other{i}.initbelief = Value_data.initbelief;
end

% 定义主角 ID
agentID = 1; % 我们是智能体 1

%% ==================== 2. 构造场景 (Scenario) ====================
% 场景：Join 操作
% 智能体 1 原本在 Task 1 和 Task 3。
% 智能体 1 现在决定 JOIN Task 2。
%
% 角色分配：
% - Task 1 (Source/Stable?): 在 P 中有。如果 Join 操作没退出，它就是 Stable(o)。
% - Task 2 (New): 在 Q 中有，P 中没有。这是 Gainer (g)。
% - Task 3 (Stable): 在 P 和 Q 中都有。这是 Other (o)。
%
% 队友分配：
% - Task 1 队友: Agent 2 (h - 如果退出; o - 如果维持)
% - Task 2 队友: Agent 3 (g)
% - Task 3 队友: Agent 4 (o)

% 构造旧结构 SC_P (M+1 x N 矩阵, 0表示未参与, 非0表示参与的AgentID)
% 假设 WorldSim 格式: 行是任务，列是智能体位置(简化理解，或者行是任务，列存成员ID)
% 这里我们使用最通用的 "Coalition Structure Matrix": (M) x (N) 逻辑矩阵或类似
% 为了适配你的 OCFUtils，我们需要 Mock 它的行为。
% 既然无法调用真实的 OCFUtils，我们在这个脚本底部重写 Mock 函数。

% --- 定义 SC_P (旧) ---
% Agent 1: Task 1, Task 3
% Agent 2: Task 1
% Agent 3: Task 2
% Agent 4: Task 3
SC_P.tasks = { [1, 2], [3], [4] }; % Task1成员, Task2成员, Task3成员
% 注意：Agent 1 在 Task 1 和 3

% --- 定义 SC_Q (新) ---
% Agent 1: Task 1, Task 2 (新加入), Task 3
% Agent 2: Task 1
% Agent 3: Task 2
% Agent 4: Task 3
SC_Q.tasks = { [1, 2], [1, 3], [1, 4] }; 
% 变化：Task 2 增加了 Agent 1

%% ==================== 3. 预设效用值 (Mocking Utilities) ====================
% 我们不真的去算路径积分，而是“注入”假的效用值，看逻辑加减对不对。
% 设定规则：
% - Agent 1 (Self): Q 比 P 累，效用 -10
% - Agent 3 (g, Task 2): 因为 1 来了，效用 +50 (Gainer)
% - Agent 2 (o, Task 1): 因为 1 变忙了，效用 -5 (Stable/Hurt)
% - Agent 4 (o, Task 3): 因为 1 变忙了，效用 -5 (Stable/Hurt)

% 我们通过一个全局变量 map 来控制 calc_agent_total_utility 的返回值
global MOCK_UTILS
MOCK_UTILS = containers.Map('KeyType','char','ValueType','double');

% 格式: 'SC状态_AgentID' -> Utility Value
MOCK_UTILS('P_1') = 100;  MOCK_UTILS('Q_1') = 90;  % Self: Delta = -10
MOCK_UTILS('P_3') = 10;   MOCK_UTILS('Q_3') = 60;  % g (Task 2): Delta = +50
MOCK_UTILS('P_2') = 20;   MOCK_UTILS('Q_2') = 15;  % o (Task 1): Delta = -5
MOCK_UTILS('P_4') = 30;   MOCK_UTILS('Q_4') = 25;  % o (Task 3): Delta = -5

% 预期结果：
% Delta U = (-10) + (+50) + (-5) + (-5) = 30
fprintf('预期 Delta U = 30\n');

%% ==================== 4. 运行测试 ====================

try
    % 调用待测函数 (函数体在脚本下方定义，模拟你的函数)
    real_delta = overlap_coalition_utility_TEST(tasks, agents, SC_P, SC_Q, agentID, Value_Params, Value_data);
    
    fprintf('实际 Delta U = %.2f\n', real_delta);
    
    if abs(real_delta - 30) < 1e-6
        fprintf('[通过] 测试成功！逻辑正确，没有重复计算。\n');
    else
        fprintf('[失败] 数值不匹配。请检查是否有集合重复或漏算。\n');
        % 调试提示：如果结果是 25，说明漏了一个 o；如果结果是 80，说明把 g 算了两遍。
    end
    
catch ME
    fprintf('[错误] 运行中断: %s\n', ME.message);
    fprintf('错误栈:\n');
    disp(ME.stack(1));
end

%% ==================== 5. 待测函数 (包含你的修改逻辑) ====================
function deltaU = overlap_coalition_utility_TEST(tasks, agents, SC_P, SC_Q, agentID, Value_Params, Value_data)
    % 这里粘贴你修改后的 overlap_coalition_utility 代码
    % 为了测试，我们将内部的 OCFUtils 和 calc_agent_total_utility 替换为本地 Mock 函数
    
    % --- 0. 基础准备 ---
    rows_n_Q = Mock_get_agent_tasks(SC_Q, agentID);
    rows_n_P = Mock_get_agent_tasks(SC_P, agentID);
    
    fprintf('  -> Agent %d 在 P 中的任务: [%s]\n', agentID, num2str(rows_n_P));
    fprintf('  -> Agent %d 在 Q 中的任务: [%s]\n', agentID, num2str(rows_n_Q));
    
    % --- 1. 集合划分 ---
    new_tasks    = setdiff(rows_n_Q, rows_n_P);
    source_tasks = setdiff(rows_n_P, rows_n_Q);
    stable_tasks = intersect(rows_n_P, rows_n_Q);
    
    fprintf('  -> [g] 新增任务: [%s]\n', num2str(new_tasks));
    fprintf('  -> [h] 退出任务: [%s]\n', num2str(source_tasks));
    fprintf('  -> [o] 维持任务: [%s]\n', num2str(stable_tasks));
    
    % --- 2. 自身效用 ---
    u_n_Q = Mock_calc_util(SC_Q, agentID);
    u_n_P = Mock_calc_util(SC_P, agentID);
    delta_self = u_n_Q - u_n_P;
    fprintf('  -> Self Delta: %.2f\n', delta_self);
    
    % --- 3. 新任务队友 (g) ---
    sum_gain_new = 0;
    for t = new_tasks
        mems = Mock_get_participants(SC_Q, t);
        mems(mems == agentID) = [];
        fprintf('     Task %d (New) Teammates: [%s]\n', t, num2str(mems));
        for g = mems
            d = Mock_calc_util(SC_Q, g) - Mock_calc_util(SC_P, g);
            sum_gain_new = sum_gain_new + d;
        end
    end
    fprintf('  -> New(g) Delta: %.2f\n', sum_gain_new);
    
    % --- 4. 旧任务队友 (h) ---
    sum_loss_old = 0;
    for t = source_tasks
        mems = Mock_get_participants(SC_P, t);
        mems(mems == agentID) = [];
        fprintf('     Task %d (Lost) Teammates: [%s]\n', t, num2str(mems));
        for h = mems
            d = Mock_calc_util(SC_P, h) - Mock_calc_util(SC_Q, h); % P - Q
            sum_loss_old = sum_loss_old + d;
        end
    end
    fprintf('  -> Old(h) Loss (P-Q): %.2f\n', sum_loss_old);
    
    % --- 5. 旁观队友 (o) ---
    sum_diff_other = 0;
    for t = stable_tasks
        mems = Mock_get_participants(SC_Q, t); % Q和P成员通常一致
        mems(mems == agentID) = [];
        fprintf('     Task %d (Stable) Teammates: [%s]\n', t, num2str(mems));
        for o = mems
            d = Mock_calc_util(SC_Q, o) - Mock_calc_util(SC_P, o);
            sum_diff_other = sum_diff_other + d;
        end
    end
    fprintf('  -> Other(o) Delta: %.2f\n', sum_diff_other);
    
    % --- 6. 汇总 ---
    deltaU = delta_self + sum_gain_new - sum_loss_old + sum_diff_other;
end

%% ==================== Mock 辅助函数 ====================

% 模拟：获取某人在某结构下参与的任务列表
function tasks = Mock_get_agent_tasks(SC, agentID)
    tasks = [];
    for t = 1:length(SC.tasks)
        if ismember(agentID, SC.tasks{t})
            tasks = [tasks, t];
        end
    end
end

% 模拟：获取某任务的参与者
function mems = Mock_get_participants(SC, taskID)
    mems = SC.tasks{taskID};
end

% 模拟：计算效用 (查表法)
function u = Mock_calc_util(SC, agentID)
    global MOCK_UTILS
    % 简单的状态哈希: 根据任务列表长度判断是 P 还是 Q (不仅如此，这是个Hack)
    % 在本脚本中，P结构里 Agent 1 参加 2 个任务，Q结构里参加 3 个。
    % 但为了更准确，我们看 SC.tasks{2} (Task 2) 是否包含 Agent 1
    
    is_Q = ismember(1, SC.tasks{2}); % Agent 1 在 Task 2 里吗？
    
    if is_Q
        key = sprintf('Q_%d', agentID);
    else
        key = sprintf('P_%d', agentID);
    end
    
    if isKey(MOCK_UTILS, key)
        u = MOCK_UTILS(key);
    else
        u = 0; % 默认
    end
end