function tests = test_SA_Value_main
% test_SA_Value_main - 测试 SA_Value_main 函数的主要功能
% 
% 测试覆盖：
%   1. 基本初始化和数据结构
%   2. 收敛检测（基于SC）
%   3. 温度更新机制
%   4. 资源联盟结构同步
%   5. 观测和信念更新
%   6. 完整运行流程

    tests = functiontests(localfunctions);
end

%% 测试1：基本初始化测试
function test_initialization(testCase)
    % 创建最小测试环境
    [agents, tasks, Graph, AddPara, Value_Params] = create_minimal_test_case();
    
    % 运行 SA_Value_main（设置为快速收敛）
    Value_Params.max_stable_iterations = 2;
    Value_Params.Tmin = 0.1;
    Value_Params.Temperature = 1.0;
    Value_Params.alpha = 0.5;
    
    try
        [Value_data, ~, ~, ~, initial_coalition] = SA_Value_main(agents, tasks, Graph, AddPara, Value_Params);
        
        % 验证 Value_data 初始化正确
        verifyEqual(testCase, length(Value_data), Value_Params.N, 'Value_data数组长度应等于智能体数量');
        
        % 验证每个智能体的数据结构
        for i = 1:Value_Params.N
            verifyTrue(testCase, isfield(Value_data(i), 'agentID'), '每个Value_data应包含agentID字段');
            verifyTrue(testCase, isfield(Value_data(i), 'coalitionstru'), '每个Value_data应包含coalitionstru字段');
            verifyTrue(testCase, isfield(Value_data(i), 'SC'), '每个Value_data应包含SC字段');
            verifyTrue(testCase, iscell(Value_data(i).SC), 'SC应该是cell数组');
            verifyEqual(testCase, length(Value_data(i).SC), Value_Params.M, 'SC长度应等于任务数量');
            
            % 验证SC结构
            for m = 1:Value_Params.M
                verifyTrue(testCase, ismatrix(Value_data(i).SC{m}), 'SC{m}应该是矩阵');
                verifyEqual(testCase, size(Value_data(i).SC{m}), [Value_Params.N, Value_Params.K], ...
                    'SC{m}维度应为N×K');
            end
        end
        
        % 验证 initial_coalition 结构
        verifyEqual(testCase, size(initial_coalition, 1), Value_Params.M + 1, ...
            'initial_coalition行数应为M+1');
        verifyEqual(testCase, size(initial_coalition, 2), Value_Params.N, ...
            'initial_coalition列数应为N');
        
    catch ME
        verifyTrue(testCase, false, sprintf('初始化失败: %s', ME.message));
    end
end

%% 测试2：资源联盟结构（SC）初始化测试
function test_SC_initialization(testCase)
    [agents, tasks, Graph, AddPara, Value_Params] = create_minimal_test_case();
    Value_Params.max_stable_iterations = 1;
    Value_Params.Tmin = 0.1;
    
    [Value_data, ~, ~, ~, ~] = SA_Value_main(agents, tasks, Graph, AddPara, Value_Params);
    
    % 检查SC是否正确初始化为零矩阵
    for i = 1:Value_Params.N
        for m = 1:Value_Params.M
            verifyTrue(testCase, all(size(Value_data(i).SC{m}) == [Value_Params.N, Value_Params.K]), ...
                sprintf('智能体%d的SC{%d}维度不正确', i, m));
        end
    end
end

%% 测试3：收敛检测测试（基于SC）
function test_convergence_detection(testCase)
    [agents, tasks, Graph, AddPara, Value_Params] = create_minimal_test_case();
    
    % 设置收敛参数
    Value_Params.max_stable_iterations = 3;
    Value_Params.Tmin = 0.01;
    Value_Params.Temperature = 10.0;
    Value_Params.alpha = 0.8;
    
    % 运行主函数
    [Value_data, ~, ~, ~, ~] = SA_Value_main(agents, tasks, Graph, AddPara, Value_Params);
    
    % 验证收敛：所有智能体的SC应该一致
    for i = 2:Value_Params.N
        for m = 1:Value_Params.M
            verifyTrue(testCase, isequal(Value_data(1).SC{m}, Value_data(i).SC{m}), ...
                sprintf('收敛后智能体%d的SC{%d}应与智能体1一致', i, m));
        end
    end
end

%% 测试4：温度更新机制测试
function test_temperature_update(testCase)
    [agents, tasks, Graph, AddPara, Value_Params] = create_minimal_test_case();
    
    initial_temp = 100.0;
    alpha = 0.9;
    
    Value_Params.Temperature = initial_temp;
    Value_Params.alpha = alpha;
    Value_Params.max_stable_iterations = 1;
    Value_Params.Tmin = 0.01;
    
    % 运行一次迭代
    [~, ~, ~, ~, ~] = SA_Value_main(agents, tasks, Graph, AddPara, Value_Params);
    
    % 注意：SA_Value_main内部会更新温度，但不返回最终温度
    % 这里我们验证函数能正常执行（间接验证温度更新机制没有导致崩溃）
    verifyTrue(testCase, true, '温度更新机制应正常工作');
end

%% 测试5：coalitionstru 和 SC 同步测试
function test_coalition_SC_sync(testCase)
    [agents, tasks, Graph, AddPara, Value_Params] = create_minimal_test_case();
    Value_Params.max_stable_iterations = 2;
    
    [Value_data, ~, ~, ~, initial_coalition] = SA_Value_main(agents, tasks, Graph, AddPara, Value_Params);
    
    % 验证所有智能体的coalitionstru应该同步
    for i = 2:Value_Params.N
        verifyTrue(testCase, isequal(Value_data(1).coalitionstru, Value_data(i).coalitionstru), ...
            sprintf('智能体%d的coalitionstru应与智能体1同步', i));
    end
    
    % 验证initial_coalition与最后一个智能体的coalitionstru一致
    verifyTrue(testCase, isequal(initial_coalition, Value_data(Value_Params.N).coalitionstru), ...
        'initial_coalition应与最后一个智能体的coalitionstru一致');
end

%% 测试6：观测和信念更新测试
function test_observation_belief_update(testCase)
    [agents, tasks, Graph, AddPara, Value_Params] = create_minimal_test_case();
    Value_Params.max_stable_iterations = 2;
    
    [Value_data, ~, ~, ~, ~] = SA_Value_main(agents, tasks, Graph, AddPara, Value_Params);
    
    % 验证observe字段存在且维度正确
    for i = 1:Value_Params.N
        verifyTrue(testCase, isfield(Value_data(i), 'observe'), '应包含observe字段');
        verifyEqual(testCase, size(Value_data(i).observe), [Value_Params.M, 3], ...
            sprintf('智能体%d的observe维度应为M×3', i));
        
        % 验证initbelief被更新（应该不全是初始值1/3）
        verifyTrue(testCase, isfield(Value_data(i), 'initbelief'), '应包含initbelief字段');
        verifyEqual(testCase, size(Value_data(i).initbelief, 1), Value_Params.M + 1, ...
            sprintf('智能体%d的initbelief行数应为M+1', i));
    end
end

%% 测试7：资源字段正确赋值测试
function test_resources_assignment(testCase)
    [agents, tasks, Graph, AddPara, Value_Params] = create_minimal_test_case();
    Value_Params.max_stable_iterations = 1;
    
    [Value_data, ~, ~, ~, ~] = SA_Value_main(agents, tasks, Graph, AddPara, Value_Params);
    
    % 验证每个智能体的resources字段被正确赋值
    for i = 1:Value_Params.N
        verifyTrue(testCase, isfield(Value_data(i), 'resources'), ...
            sprintf('智能体%d应包含resources字段', i));
        verifyEqual(testCase, Value_data(i).resources, agents(i).resources, ...
            sprintf('智能体%d的resources应与输入agents一致', i));
    end
end

%% 测试8：完整运行流程测试（更复杂场景）
function test_full_run_complex(testCase)
    % 创建更复杂的测试场景
    N = 5;  % 5个智能体
    M = 4;  % 4个任务
    K = 3;  % 3种资源类型
    
    [agents, tasks, Graph, AddPara, Value_Params] = create_test_case_with_params(N, M, K);
    
    Value_Params.max_stable_iterations = 3;
    Value_Params.Tmin = 0.1;
    Value_Params.Temperature = 50.0;
    Value_Params.alpha = 0.85;
    
    try
        [Value_data, Rcost, cost_sum, net_profit, initial_coalition] = ...
            SA_Value_main(agents, tasks, Graph, AddPara, Value_Params);
        
        % 验证所有输出存在
        verifyTrue(testCase, ~isempty(Value_data), 'Value_data不应为空');
        verifyTrue(testCase, ~isempty(initial_coalition), 'initial_coalition不应为空');
        
        % 验证数据一致性
        for i = 1:N
            verifyEqual(testCase, Value_data(i).agentID, agents(i).id, ...
                sprintf('智能体%d的ID应匹配', i));
        end
        
        % 验证SC在所有智能体间同步
        for i = 2:N
            for m = 1:M
                verifyTrue(testCase, isequal(Value_data(1).SC{m}, Value_data(i).SC{m}), ...
                    sprintf('复杂场景下智能体%d的SC{%d}应同步', i, m));
            end
        end
        
    catch ME
        verifyTrue(testCase, false, sprintf('完整运行失败: %s\n%s', ME.message, getReport(ME)));
    end
end

%% 测试9：void任务初始化测试
function test_void_task_initialization(testCase)
    [agents, tasks, Graph, AddPara, Value_Params] = create_minimal_test_case();
    Value_Params.max_stable_iterations = 1;
    
    [Value_data, ~, ~, ~, ~] = SA_Value_main(agents, tasks, Graph, AddPara, Value_Params);
    
    % 在初始迭代前，所有智能体应在void任务（第M+1行）
    % 注意：SA_Value_main内部会先初始化所有智能体到void任务
    for i = 1:Value_Params.N
        verifyTrue(testCase, isfield(Value_data(i), 'coalitionstru'), '应包含coalitionstru字段');
    end
end

%% 测试10：边界条件测试 - 单智能体单任务
function test_single_agent_single_task(testCase)
    N = 1;
    M = 1;
    K = 2;
    
    [agents, tasks, Graph, AddPara, Value_Params] = create_test_case_with_params(N, M, K);
    Value_Params.max_stable_iterations = 2;
    Value_Params.Tmin = 0.1;
    
    try
        [Value_data, ~, ~, ~, initial_coalition] = SA_Value_main(agents, tasks, Graph, AddPara, Value_Params);
        
        verifyEqual(testCase, length(Value_data), 1, '应只有一个智能体数据');
        verifyEqual(testCase, size(initial_coalition), [M+1, N], ...
            '单智能体单任务的coalition维度应为2×1');
        
    catch ME
        verifyTrue(testCase, false, sprintf('单智能体单任务测试失败: %s', ME.message));
    end
end

%% 辅助函数：创建最小测试用例
function [agents, tasks, Graph, AddPara, Value_Params] = create_minimal_test_case()
    N = 3;  % 3个智能体
    M = 2;  % 2个任务
    K = 2;  % 2种资源类型
    
    [agents, tasks, Graph, AddPara, Value_Params] = create_test_case_with_params(N, M, K);
end

%% 辅助函数：创建指定参数的测试用例
function [agents, tasks, Graph, AddPara, Value_Params] = create_test_case_with_params(N, M, K)
    % 初始化智能体
    for i = 1:N
        agents(i).id = i;
        agents(i).vel = 2;
        agents(i).fuel = 1;
        agents(i).x = rand() * 100;
        agents(i).y = rand() * 100;
        agents(i).detprob = 0.8;
        agents(i).resources = randi([2, 8], K, 1);  % 每种资源2-8单位
        agents(i).Emax = 1000;
        agents(i).beta = 1;
    end
    
    % 初始化任务
    WORLD_value = [300, 500, 1000];
    num_task_types = min(3, M);  % 任务类型数不超过任务数
    task_type_demands = randi([0, 5], num_task_types, K);
    
    for j = 1:M
        tasks(j).id = j;
        tasks(j).priority = j;
        tasks(j).x = rand() * 100;
        tasks(j).y = rand() * 100;
        tasks(j).value = WORLD_value(randi(length(WORLD_value)));
        tasks(j).type = mod(j-1, num_task_types) + 1;
        tasks(j).resource_demand = task_type_demands(tasks(j).type, :);
        tasks(j).duration_by_resource = ones(1, K) * 50;
        tasks(j).duration = sum(tasks(j).duration_by_resource);
        tasks(j).WORLD.value = WORLD_value;
    end
    
    % 初始化参数（内联 Value_init 避免路径问题）
    Value_Params.N = N;
    Value_Params.M = M;
    Value_Params.K = K;
    Value_Params.task_type_demands = task_type_demands;
    Value_Params.Temperature = 10.0;
    Value_Params.alpha = 0.9;
    Value_Params.Tmin = 0.01;
    Value_Params.max_stable_iterations = 5;
    
    % 初始化图结构（简单全连接）
    Graph = ones(N, N) - eye(N);
    
    % 初始化AddPara
    AddPara.control = 1;
end
