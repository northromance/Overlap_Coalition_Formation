function test_coalitionstru_logic()
% TEST_COALITIONSTRU_LOGIC 验证联盟结构矩阵的构建逻辑
%
% 数据结构定义：
%   SC: Mx1 Cell数组。
%   SC{j}: NxK 矩阵 (行=智能体, 列=资源类型)。
%   规则：只要 SC{j}(i, :) 中有任意非零值，即视为 Agent i 参与了 Task j。
%
% 目标矩阵 coalitionstru ((M+1)xN):
%   1~M 行: 对应 Task 1~M。如果 Agent i 参与，则填入 AgentID，否则 0。
%   M+1 行: 对应 Void。如果 Agent i 未参与任何真实任务，填入 AgentID，否则 0。

    clc; clear;
    fprintf('==============================================\n');
    fprintf('验证 CoalitionStructure 构建 (SC = N行Agents x K列Resources)...\n');
    fprintf('==============================================\n');

    %% 1. 环境设置
    Value_Params.M = 3; % 3个任务
    Value_Params.N = 5; % 5个智能体
    Value_Params.K = 2; % 2种资源 (例如：算力，带宽)
    
    M = Value_Params.M;
    N = Value_Params.N;
    K = Value_Params.K;
    
    % 模拟 Agent ID (1..N)
    agents = struct('id', num2cell(1:N)); 

    %% 2. 构造模拟的资源分配 (SC)
    SC = cell(M, 1);
    % 初始化 N x K 全零矩阵
    for j = 1:M
        SC{j} = zeros(N, K);
    end
    
    % --- 场景设定 ---
    
    % [Agent 1] -> Task 1 (只投入资源类型 1)
    SC{1}(1, 1) = 10; 
    SC{1}(1, 2) = 0;
    
    % [Agent 2] -> Task 2 (只投入资源类型 2)
    SC{2}(2, 1) = 0;
    SC{2}(2, 2) = 20;
    
    % [Agent 3] -> 重叠联盟 (Task 1 和 Task 3)
    % Task 1 投入资源 1, Task 3 投入资源 2
    SC{1}(3, 1) = 5; 
    SC{3}(3, 2) = 8;
    
    % [Agent 4] -> Task 2 (混合投入，两种资源都投了)
    SC{2}(4, 1) = 3;
    SC{2}(4, 2) = 3;
    
    % [Agent 5] -> 无任务 (全零)
    % (保持 SC 中所有对应位置为 0)

    fprintf('场景设定 (N=%d, K=%d)：\n', N, K);
    fprintf('  Agent 1: Task 1 (Res 1)\n');
    fprintf('  Agent 2: Task 2 (Res 2)\n');
    fprintf('  Agent 3: Task 1 (Res 1) & Task 3 (Res 2) -> [重叠]\n');
    fprintf('  Agent 4: Task 2 (Res 1 & 2)\n');
    fprintf('  Agent 5: None -> [Void]\n\n');

    %% 3. 执行构建逻辑
    % 调用核心函数
    coalitionstru = build_coalitionstru_from_SC(SC, Value_Params, agents);

    %% 4. 打印结果矩阵
    fprintf('生成的 coalitionstru 矩阵 ((M+1) 行 x N 列):\n');
    fprintf('------------------------------------------------------------\n');
    fprintf('Task\\Agent\t');
    for i = 1:N
        fprintf('A%d\t', i);
    end
    fprintf('\n');
    
    for j = 1 : M+1
        if j <= M
            row_name = sprintf('Task %d   ', j);
        else
            row_name = 'Void (M+1)';
        end
        
        fprintf('%s\t', row_name);
        for i = 1:N
            val = coalitionstru(j, i);
            if val == 0
                fprintf('. \t'); % 0 显示为点，更清晰
            else
                fprintf('%d\t', val);
            end
        end
        fprintf('\n');
    end
    fprintf('------------------------------------------------------------\n');

    %% 5. 自动断言验证
    fprintf('\n开始自动逻辑验证...\n');
    
    % 验证 Agent 1
    assert(coalitionstru(1, 1) == 1, '❌ A1 应在 T1');
    assert(coalitionstru(M+1, 1) == 0, '❌ A1 忙碌，Void应为0');
    fprintf('✅ Agent 1 通过\n');

    % 验证 Agent 2 (资源类型2生效)
    assert(coalitionstru(2, 2) == 2, '❌ A2 应在 T2');
    assert(coalitionstru(M+1, 2) == 0, '❌ A2 忙碌，Void应为0');
    fprintf('✅ Agent 2 通过\n');

    % 验证 Agent 3 (重叠)
    assert(coalitionstru(1, 3) == 3, '❌ A3 应在 T1');
    assert(coalitionstru(3, 3) == 3, '❌ A3 应在 T3');
    assert(coalitionstru(2, 3) == 0, '❌ A3 不在 T2');
    assert(coalitionstru(M+1, 3) == 0, '❌ A3 忙碌，Void应为0');
    fprintf('✅ Agent 3 (重叠) 通过\n');
    
    % 验证 Agent 5 (Void)
    if any(coalitionstru(1:M, 5) ~= 0)
        error('❌ A5 不应在任何任务中');
    end
    assert(coalitionstru(M+1, 5) == 5, '❌ A5 空闲，Void行应为 AgentID(5)');
    fprintf('✅ Agent 5 (Void) 通过\n');

    fprintf('\n🎉 验证成功！函数逻辑与您的描述完全一致。\n');
end

%% --- 核心构建函数 ---
function coalitionstru = build_coalitionstru_from_SC(SC, Value_Params, agents)
% BUILD_COALITIONSTRU_FROM_SC 根据 N*K 资源矩阵反推联盟结构
% 输入:
%   SC: M个Cell，每个是 N*K 矩阵
%   agents: 智能体结构体 (用于获取 ID)
% 输出:
%   coalitionstru: (M+1)*N 矩阵

    M = Value_Params.M;
    N = Value_Params.N;
    tol = 1e-6; % 容差，防止浮点数误差
    
    % 1. 初始化 (M+1) x N 矩阵
    coalitionstru = zeros(M + 1, N);
    
    % 2. 遍历真实任务 (1~M)
    for j = 1:M
        % 取出第 j 个任务的资源分配矩阵 (N x K)
        task_res_matrix = SC{j};
        
        if ~isempty(task_res_matrix)
            % 遍历每个智能体 i (矩阵的行)
            for i = 1:N
                % 获取该智能体的真实 ID
                if ~isempty(agents)
                    aid = agents(i).id;
                else
                    aid = i;
                end
                
                % 防越界检查
                if i <= size(task_res_matrix, 1)
                    % [关键逻辑] 检查该智能体行的“所有资源列”
                    % 只要有任意一列资源 > 0，就算参与了该任务
                    agent_resources = task_res_matrix(i, :);
                    
                    if any(agent_resources > tol)
                        coalitionstru(j, i) = aid;
                    end
                end
            end
        end
    end
    
    % 3. 处理 Void 任务 (M+1)
    % 逻辑：如果智能体在 1~M 任务行中全是 0，说明它空闲
    for i = 1:N
        if ~isempty(agents)
            aid = agents(i).id;
        else
            aid = i;
        end
        
        % 检查 1~M 行这一列是否有非零值
        is_busy = any(coalitionstru(1:M, i) ~= 0);
        
        if ~is_busy
            % 空闲 -> 填入 ID
            coalitionstru(M + 1, i) = aid;
        else
            % 忙碌 -> 填入 0
            coalitionstru(M + 1, i) = 0;
        end
    end
end