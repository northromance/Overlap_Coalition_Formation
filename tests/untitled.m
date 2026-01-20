function test_Value_order_scenarios()
% TEST_VALUE_ORDER_SCENARIOS 测试 Value_order 函数的核心逻辑
% 
% 测试内容：
% 1. 状态备份与回滚是否生效（资源是否干净转移）。
% 2. 决策逻辑是否正确（贪婪策略）。
% 3. 统计变量 (iteration) 是否仅在有效进化时更新。

    clc; clear; close all;
    fprintf('==============================================\n');
    fprintf('开始测试 Value_order 函数逻辑...\n');
    fprintf('==============================================\n');

    %% 全局参数设置 (简化环境)
    Value_Params.N = 1;     % 只有1个智能体 (简化干扰)
    Value_Params.M = 2;     % 2个真实任务 + 1个Void
    Value_Params.K = 1;     % 1种资源类型
    Value_Params.task_type = 1;
    Value_Params.obs_times = 1;
    
    % [关键参数] 资源置信度和需求
    Value_Params.resource_confidence = 1.0; 
    Value_Params.task_type_demands = [5]; % 假设第1类任务需要5单位资源

    %% ==========================================================
    %% 场景 1: 发现更优任务 (Evolution)
    %% ==========================================================
    % 设定：Agent 在 Task 2 (低价值)，Task 1 是高价值。
    % 预期：Agent 移动到 Task 1，incremental=1，iteration+1。
    fprintf('\n[测试场景 1]: 发现更优任务 (Evolution)\n');
    
    [agents, tasks, Value_data] = setup_environment(Value_Params);
    
    % --- 构造场景 ---
    % 任务1: 高价值 (1000), 距离近
    tasks(1).WORLD.value = 1000; 
    tasks(1).x = 0; tasks(1).y = 0;
    
    % 任务2: 低价值 (10), 距离近
    tasks(2).WORLD.value = 10;   
    tasks(2).x = 0; tasks(2).y = 0;
    
    % Agent: 初始状态强制设为在 Task 2
    agentID = 1;
    Value_data(1).agentID = agentID;
    
    % 手动设置初始位置
    Value_data(1).coalitionstru(:, :) = 0; % 清空
    Value_data(1).coalitionstru(2, 1) = agentID; % 在 Task 2
    
    % 手动设置初始资源
    Value_data(1).resources_matrix(:, :) = 0;
    Value_data(1).resources_matrix(2, 1) = 10;   % 投入资源到 Task 2
    
    % 手动设置 SC
    Value_data(1).SC{1}(:,:) = 0;
    Value_data(1).SC{2}(1, 1) = 10;              % SC同步
    
    % 记录初始 iteration
    init_iter = Value_data(1).iteration;
    
    % --- 执行函数 ---
    [incr, prev_task, new_data] = Value_order(agents, tasks, Value_data(1), Value_Params);
    
    % --- 验证结果 ---
    assert_check(incr == 1, 'Incremental 标志应为 1');
    assert_check(prev_task == 2, '前序任务索引应为 2');
    
    % 检查位置是否变到了 Task 1
    [curr_task, ~] = find(new_data.coalitionstru == agentID);
    assert_check(curr_task == 1, sprintf('Agent 应移动到 Task 1 (实际: %d)', curr_task));
    
    % 检查资源是否同步移动 (Task 1 有资源，Task 2 为 0)
    res_t1 = new_data.resources_matrix(1, 1);
    res_t2 = new_data.resources_matrix(2, 1);
    assert_check(res_t1 == 10 && res_t2 == 0, '资源应完全转移到 Task 1');
    
    % 检查 SC 是否同步
    sc_t1 = new_data.SC{1}(1,1);
    sc_t2 = new_data.SC{2}(1,1);
    assert_check(sc_t1 == 10 && sc_t2 == 0, '全局 SC 结构应同步更新');

    % 检查统计数据是否更新
    assert_check(new_data.iteration == init_iter + 1, 'Iteration 计数应 +1');
    
    fprintf('>> 场景 1 测试通过！\n');

    %% ==========================================================
    %% 场景 2: 当前即最优 (Stability)
    %% ==========================================================
    % 设定：Agent 在 Task 1 (高价值)，Task 2 是低价值。
    % 预期：Agent 保持在 Task 1，incremental=0，iteration不变。
    fprintf('\n[测试场景 2]: 当前即最优 (Stability)\n');
    
    [agents, tasks, Value_data] = setup_environment(Value_Params);
    
    % 任务1: 高价值
    tasks(1).WORLD.value = 1000;
    tasks(2).WORLD.value = 10;
    
    % Agent: 初始在 Task 1
    Value_data(1).coalitionstru(:, :) = 0;
    Value_data(1).coalitionstru(1, 1) = 1; 
    
    Value_data(1).resources_matrix(:, :) = 0;
    Value_data(1).resources_matrix(1, 1) = 10;
    
    Value_data(1).SC{1}(1, 1) = 10;
    Value_data(1).SC{2}(:, :) = 0;
    
    init_iter = Value_data(1).iteration;
    
    % --- 执行函数 ---
    [incr, prev_task, new_data] = Value_order(agents, tasks, Value_data(1), Value_Params);
    
    % --- 验证结果 ---
    assert_check(incr == 0, 'Incremental 标志应为 0');
    
    [curr_task, ~] = find(new_data.coalitionstru == agentID);
    assert_check(curr_task == 1, 'Agent 应保持在 Task 1');
    
    % 检查统计数据不应更新
    assert_check(new_data.iteration == init_iter, 'Iteration 计数应保持不变');
    
    fprintf('>> 场景 2 测试通过！\n');

    %% ==========================================================
    %% 场景 3: 无利可图 (Zero Utility -> Rest)
    %% ==========================================================
    % 设定：所有任务价值极低 (0)，不足以覆盖移动成本。
    % 预期：Agent 移动到 Void (M+1)，incremental=0，iteration不变。
    fprintf('\n[测试场景 3]: 无利可图 (Move to Void)\n');
    
    [agents, tasks, Value_data] = setup_environment(Value_Params);
    
    % 任务1 & 2: 价值为 0
    tasks(1).WORLD.value = 0;
    tasks(2).WORLD.value = 0;
    
    % Agent: 初始在 Task 1 (苦力)
    Value_data(1).coalitionstru(1, 1) = 1;
    Value_data(1).resources_matrix(1, 1) = 10;
    Value_data(1).SC{1}(1, 1) = 10;
    
    init_iter = Value_data(1).iteration;
    
    % --- 执行函数 ---
    [incr, prev_task, new_data] = Value_order(agents, tasks, Value_data(1), Value_Params);
    
    % --- 验证结果 ---
    assert_check(incr == 0, 'Incremental 标志应为 0 (去休息不算进化)');
    
    [curr_task, ~] = find(new_data.coalitionstru == agentID);
    void_task_idx = Value_Params.M + 1;
    assert_check(curr_task == void_task_idx, sprintf('Agent 应移动到 Void Task (实际: %d)', curr_task));
    
    % 检查资源是否被清空 (在 Void 任务不投入资源)
    total_res_invested = sum(new_data.resources_matrix(:));
    assert_check(total_res_invested == 0, 'Void 状态下资源投入应为 0');
    
    assert_check(new_data.iteration == init_iter, 'Iteration 计数应保持不变');
    
    fprintf('>> 场景 3 测试通过！\n');
    
    fprintf('\n==============================================\n');
    fprintf('所有测试场景执行完毕，逻辑验证成功。\n');
    fprintf('==============================================\n');

end

%% 辅助函数：环境构建
function [agents, tasks, Value_data] = setup_environment(P)
    % 构建最简化的数据结构以支持 Value_utility 运行
    
    % 1. Agents
    agents(1).id = 1;
    agents(1).x = 0; agents(1).y = 0;
    agents(1).vel = 10;
    agents(1).resources = [10]; % 能力值 > 需求(5)，确保能完成
    agents(1).fuel = 0.1;       % 飞行能耗
    agents(1).wait_fuel = 0.05; % 等待能耗
    agents(1).beta = 0.1;       % 执行能耗
    
    % 2. Tasks
    for j = 1:P.M
        tasks(j).x = 10; tasks(j).y = 0; % 默认位置
        tasks(j).value = 100;            % 标称价值 (兼容旧代码)
        tasks(j).WORLD.value = 100;      % 真实价值
        tasks(j).resource_demand = [5];  % 需求
        tasks(j).priority = 1;
    end
    
    % 3. Value_data 初始化
    Value_data(1).agentID = 1;
    Value_data(1).iteration = 0;
    Value_data(1).unif = 0;
    
    % 联盟结构
    Value_data(1).coalitionstru = zeros(P.M+1, P.N);
    Value_data(1).SC = cell(P.M, 1);
    for m=1:P.M
        Value_data(1).SC{m} = zeros(P.N, P.K);
    end
    Value_data(1).resources_matrix = zeros(P.M, P.K);
    
    % 信念 (Belief) - 设为 1.0 确信
    % M+1 行，Types 列
    Value_data(1).initbelief = ones(P.M+1, P.task_type); 
end

%% 辅助函数：断言检查
function assert_check(condition, msg)
    if ~condition
        error('测试失败: %s', msg);
    else
        fprintf('  [PASS] %s\n', msg);
    end
end