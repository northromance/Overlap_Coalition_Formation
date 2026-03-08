% 测试修改后的效用计算函数
% 验证按任务单独计算成本的逻辑

clear; clc;

addpath('Main_fun');
addpath('comalg');

fprintf('=== 测试效用计算函数 ===\n\n');

%% 创建简单测试场景
N = 3;  % 3个智能体
M = 3;  % 3个任务
K = 2;  % 2种资源

% 创建智能体
agents(1).id = 1;
agents(1).x = 0;
agents(1).y = 0;
agents(1).vel = 10;
agents(1).fuel = 0.1;      % 移动能耗系数 ϖ
agents(1).wait_fuel = 0.05; % 等待能耗系数 γ
agents(1).beta = 0.08;      % 执行能耗系数 β
agents(1).resources = [5, 5];

agents(2).id = 2;
agents(2).x = 50;
agents(2).y = 0;
agents(2).vel = 10;
agents(2).fuel = 0.1;
agents(2).wait_fuel = 0.05;
agents(2).beta = 0.08;
agents(2).resources = [5, 5];

agents(3).id = 3;
agents(3).x = 0;
agents(3).y = 50;
agents(3).vel = 10;
agents(3).fuel = 0.1;
agents(3).wait_fuel = 0.05;
agents(3).beta = 0.08;
agents(3).resources = [5, 5];

% 创建任务
tasks(1).id = 1;
tasks(1).x = 30;
tasks(1).y = 30;
tasks(1).priority = 0.9;
tasks(1).resource_demand = [3, 3];
tasks(1).duration = 10;
tasks(1).duration_by_resource = [10, 10];
tasks(1).value = 100;  % 上帝视角的真实价值
tasks(1).WORLD.value = [100, 80];  % 两种类型的价值（智能体信念）

tasks(2).id = 2;
tasks(2).x = 60;
tasks(2).y = 40;
tasks(2).priority = 0.7;
tasks(2).resource_demand = [4, 2];
tasks(2).duration = 8;
tasks(2).duration_by_resource = [8, 8];
tasks(2).value = 120;
tasks(2).WORLD.value = [120, 100];

tasks(3).id = 3;
tasks(3).x = 20;
tasks(3).y = 60;
tasks(3).priority = 0.5;
tasks(3).resource_demand = [2, 4];
tasks(3).duration = 12;
tasks(3).duration_by_resource = [12, 12];
tasks(3).value = 90;
tasks(3).WORLD.value = [90, 110];

% Value_Params
Value_Params.N = N;
Value_Params.M = M;
Value_Params.K = K;
Value_Params.task_type = 2;
Value_Params.resource_confidence = 0.9;
Value_Params.task_type_demands = [3, 3; 4, 2];  % 2种类型，每种K个资源需求

% 创建联盟结构 SC
% 任务1: 智能体1和2参与
SC{1} = zeros(N, K);
SC{1}(1, :) = [2, 2];  % 智能体1投入2单位资源
SC{1}(2, :) = [2, 1];  % 智能体2投入资源

% 任务2: 智能体2和3参与
SC{2} = zeros(N, K);
SC{2}(2, :) = [2, 1];
SC{2}(3, :) = [2, 1];

% 任务3: 智能体1和3参与
SC{3} = zeros(N, K);
SC{3}(1, :) = [1, 2];
SC{3}(3, :) = [1, 2];

% 创建 Value_data
for i = 1:N
    Value_data(i).agentID = i;
    Value_data(i).agentIndex = i;
    Value_data(i).initbelief = zeros(M, 2);
    % 设置信念分布（简单起见，每个任务类型1的概率0.6，类型2的概率0.4）
    for j = 1:M
        Value_data(i).initbelief(j, :) = [0.6, 0.4];
    end
end

tol = 1e-9;

%% 测试效用计算
fprintf('测试场景:\n');
fprintf('  智能体数: %d\n', N);
fprintf('  任务数: %d\n', M);
fprintf('  资源种类: %d\n\n', K);

fprintf('联盟结构:\n');
fprintf('  任务1: 智能体1[2,2] + 智能体2[2,1]\n');
fprintf('  任务2: 智能体2[2,1] + 智能体3[2,1]\n');
fprintf('  任务3: 智能体1[1,2] + 智能体3[1,2]\n\n');

fprintf('计算每个智能体的效用:\n');
for i = 1:N
    [utility, task_utils] = UtilityEvaluator.calc_agent_total_utility(...
        SC, agents, tasks, Value_Params, Value_data(i), []);

    fprintf('\n智能体 %d:\n', i);
    fprintf('  总效用: %.4f\n', utility);

    task_list = OCFUtils.get_agent_tasks_fast(SC, i, tol);
    task_list = task_list(task_list <= M);

    if ~isempty(task_list)
        fprintf('  参与任务: ');
        fprintf('%d ', task_list);
        fprintf('\n');

        fprintf('  各任务效用:\n');
        for task_id = task_list
            if isKey(task_utils, task_id)
                fprintf('    任务%d: %.4f\n', task_id, task_utils(task_id));
            end
        end
    end
end

%% 验证全局效用
fprintf('\n\n=== 全局效用评估 ===\n');
[global_utility, total_cost, total_value, completion_degrees] = ...
    UtilityEvaluator.evaluate_coalition_metrics(SC, agents, tasks, Value_Params, tol);

fprintf('全局净效用: %.4f\n', global_utility);
fprintf('总完成价值: %.4f\n', total_value);
fprintf('总成本: %.4f\n', total_cost);
fprintf('\n任务完成度:\n');
for j = 1:M
    fprintf('  任务%d: %.2f%%\n', j, completion_degrees(j) * 100);
end

fprintf('\n测试完成!\n');
