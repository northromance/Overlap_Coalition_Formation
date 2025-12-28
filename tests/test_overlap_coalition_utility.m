% tests/test_overlap_coalition_utility.m
% 测试 overlap_coalition_utility 函数的计算逻辑和结果正确性
% 验证 BMBT 偏好判别式：deltaU = LHS - RHS

clear; clc;

% 添加路径
thisFile = mfilename('fullpath');
[thisDir, ~, ~] = fileparts(thisFile);
projectRoot = fileparts(thisDir);
addpath(fullfile(projectRoot, 'SA'));

% 重置随机数生成器（兼容旧生成器）
rng('default');
rng(123, 'twister');

fprintf('========== 测试 overlap_coalition_utility 函数 ==========\n\n');

%% ==================== 环境初始化 ====================
Value_Params.M = 4;  % 4个任务
Value_Params.K = 3;  % 3种资源类型
Value_Params.N = 3;  % 3个智能体
Value_Params.alpha = 1.0;  % 移动能耗（供 self_utility 使用）
Value_Params.beta = 1.0;   % 执行能耗（供 self_utility 使用）

% 智能体初始化
for i = 1:Value_Params.N
    agents(i).id = i;
    agents(i).x = (i-1) * 20;
    agents(i).y = 0;
    agents(i).vel = 10;
    agents(i).speed = 10;  % overlap_coalition_self_utility 使用 speed 字段
    agents(i).fuel = 1;
    agents(i).beta = 1;
    agents(i).resources = [5; 6; 7];
    agents(i).Emax = 500;
end

% 任务初始化
task_value_options = [100, 200, 300];
for j = 1:Value_Params.M
    tasks(j).id = j;
    tasks(j).priority = j;
    tasks(j).x = 10 * j;
    tasks(j).y = 10;
    tasks(j).resource_demand = [2 3 2];
    tasks(j).duration_by_resource = [5 10 8];  % 每种资源类型执行时间
    tasks(j).duration = sum(tasks(j).duration_by_resource);
    tasks(j).value = task_value_options(mod(j-1, 3) + 1);
    
    % overlap_coalition_self_utility 需要 tasks.WORLD.value
    tasks(j).WORLD.value = task_value_options;
end

% Value_data 初始化
Value_data.agentID = 2;  % 测试智能体2
Value_data.resources = agents(Value_data.agentID).resources;

% 初始化信念分布（3种价值水平的概率）
Value_data.initbelief = zeros(Value_Params.M, 3);
for j = 1:Value_Params.M
    Value_data.initbelief(j, :) = [0.3, 0.4, 0.3];  % 示例分布
end

%% ==================== Case 1: 智能体2从空任务加入任务1 ====================
fprintf('Case 1: 智能体2从空任务(M+1行)加入任务1\n');
fprintf('--------------------------------------\n');

agentID = 2;

% SC_P：初始状态
% - 智能体1在任务1，智能体3在任务2
% - 智能体2在空任务(M+1行)
SC_P = zeros(Value_Params.M + 1, Value_Params.N);
SC_P(1, 1) = 1;  % 智能体1在任务1
SC_P(2, 3) = 3;  % 智能体3在任务2
SC_P(Value_Params.M + 1, 2) = 2;  % 智能体2在空任务

% SC_Q：智能体2加入任务1后的状态
SC_Q = SC_P;
SC_Q(1, 2) = 2;  % 智能体2加入任务1
SC_Q(Value_Params.M + 1, 2) = 0;  % 清除空任务行

% 资源分配初始化（简化版：每个agent对其参与的任务分配部分资源）
Value_data.resources_matrix = zeros(Value_Params.M, Value_Params.K);
% 对于SC_P：智能体1在任务1分配[2 3 2]
Value_data.resources_matrix(1, :) = [2 3 2];
% 智能体3在任务2分配[2 2 2]
Value_data.resources_matrix(2, :) = [2 2 2];

fprintf('SC_P (操作前联盟结构):\n');
disp(SC_P);
fprintf('SC_Q (操作后联盟结构 - 智能体2加入任务1):\n');
disp(SC_Q);
fprintf('\n');

% 调用 overlap_coalition_utility
deltaU_case1 = overlap_coalition_utility(tasks, agents, SC_P, SC_Q, agentID, Value_Params, Value_data);

fprintf('计算结果: deltaU = %.4f\n', deltaU_case1);
fprintf('解释: deltaU = LHS - RHS\n');
fprintf('  LHS = u_n(SC_Q) + Σ新联盟其他成员效用差 + Σ相关成员效用(Q)\n');
fprintf('  RHS = u_n(SC_P) + Σ原联盟其他成员效用差 + Σ相关成员效用(P)\n');
fprintf('\n详细计算过程:\n');

% 手动验证各项计算
% 1) u_n(SC_Q)：智能体2在SC_Q中参与任务1
rows_n_Q = find(SC_Q(1:Value_Params.M, agentID) == agentID);
fprintf('  智能体%d在SC_Q中参与的任务: %s\n', agentID, mat2str(rows_n_Q));

% 2) u_n(SC_P)：智能体2在SC_P中参与任务（空任务，效用为0）
rows_n_P = find(SC_P(1:Value_Params.M, agentID) == agentID);
fprintf('  智能体%d在SC_P中参与的任务: %s (空=>效用为0)\n', agentID, mat2str(rows_n_P));

% 3) 新增任务行
new_tasks = setdiff(rows_n_Q, rows_n_P);
fprintf('  新增加入的任务行: %s\n', mat2str(new_tasks));
for idx = 1:length(new_tasks)
    A_j = new_tasks(idx);
    members_Aj = find(SC_Q(A_j, :) ~= 0);
    fprintf('    任务%d的成员(SC_Q): %s\n', A_j, mat2str(members_Aj));
end

% 4) 离开任务行
source_tasks = setdiff(rows_n_P, rows_n_Q);
fprintf('  离开的任务行: %s\n', mat2str(source_tasks));

% 5) Mem(A(n))：智能体2相关的联盟成员并集
all_members_An = [];
for idx = 1:length(rows_n_Q)
    task_row = rows_n_Q(idx);
    members_task = find(SC_Q(task_row, :) ~= 0);
    all_members_An = union(all_members_An, members_task);
end
all_members_An(all_members_An == agentID) = [];
fprintf('  Mem(A(n))\\{n} (相关成员): %s\n', mat2str(all_members_An));

fprintf('\n');

%% ==================== Case 2: 智能体2从任务1转移到任务3 ====================
fprintf('Case 2: 智能体2从任务1转移到任务3（join任务3，离开任务1）\n');
fprintf('--------------------------------------------------------------\n');

agentID = 2;

% SC_P：智能体2在任务1
SC_P2 = zeros(Value_Params.M + 1, Value_Params.N);
SC_P2(1, 1) = 1;  % 智能体1在任务1
SC_P2(1, 2) = 2;  % 智能体2在任务1
SC_P2(2, 3) = 3;  % 智能体3在任务2

% SC_Q：智能体2转移到任务3
SC_Q2 = SC_P2;
SC_Q2(1, 2) = 0;  % 智能体2离开任务1
SC_Q2(3, 2) = 2;  % 智能体2加入任务3

% 资源分配
Value_data.resources_matrix = zeros(Value_Params.M, Value_Params.K);
Value_data.resources_matrix(1, :) = [3 3 3];  % 任务1的分配（智能体1+2）
Value_data.resources_matrix(2, :) = [2 2 2];  % 任务2的分配（智能体3）

fprintf('SC_P (操作前联盟结构 - 智能体2在任务1):\n');
disp(SC_P2);
fprintf('SC_Q (操作后联盟结构 - 智能体2转到任务3):\n');
disp(SC_Q2);
fprintf('\n');

deltaU_case2 = overlap_coalition_utility(tasks, agents, SC_P2, SC_Q2, agentID, Value_Params, Value_data);

fprintf('计算结果: deltaU = %.4f\n', deltaU_case2);

rows_n_Q2 = find(SC_Q2(1:Value_Params.M, agentID) == agentID);
rows_n_P2 = find(SC_P2(1:Value_Params.M, agentID) == agentID);
new_tasks2 = setdiff(rows_n_Q2, rows_n_P2);
source_tasks2 = setdiff(rows_n_P2, rows_n_Q2);

fprintf('详细计算过程:\n');
fprintf('  智能体%d在SC_P中参与的任务: %s\n', agentID, mat2str(rows_n_P2));
fprintf('  智能体%d在SC_Q中参与的任务: %s\n', agentID, mat2str(rows_n_Q2));
fprintf('  新增加入的任务行: %s\n', mat2str(new_tasks2));
fprintf('  离开的任务行: %s\n', mat2str(source_tasks2));

for idx = 1:length(new_tasks2)
    A_j = new_tasks2(idx);
    members_Aj = find(SC_Q2(A_j, :) ~= 0);
    fprintf('    新联盟任务%d的成员(SC_Q): %s\n', A_j, mat2str(members_Aj));
end

for idx = 1:length(source_tasks2)
    A_i = source_tasks2(idx);
    members_Ai = find(SC_P2(A_i, :) ~= 0);
    fprintf('    原联盟任务%d的成员(SC_P): %s\n', A_i, mat2str(members_Ai));
end

fprintf('\n');

%% ==================== Case 3: 多智能体联盟效用变化（复杂场景）====================
fprintf('Case 3: 复杂场景 - 智能体2加入已有多成员的任务4\n');
fprintf('----------------------------------------------------\n');

agentID = 2;

% SC_P：初始状态
SC_P3 = zeros(Value_Params.M + 1, Value_Params.N);
SC_P3(1, 1) = 1;  % 智能体1在任务1
SC_P3(2, 2) = 2;  % 智能体2在任务2
SC_P3(4, 1) = 1;  % 智能体1同时在任务4（重叠）
SC_P3(4, 3) = 3;  % 智能体3在任务4

% SC_Q：智能体2加入任务4（形成三方联盟）
SC_Q3 = SC_P3;
SC_Q3(4, 2) = 2;  % 智能体2也加入任务4

% 资源分配
Value_data.resources_matrix = zeros(Value_Params.M, Value_Params.K);
Value_data.resources_matrix(1, :) = [2 2 2];  % 任务1
Value_data.resources_matrix(2, :) = [3 3 3];  % 任务2
Value_data.resources_matrix(4, :) = [4 4 4];  % 任务4（智能体1+3）

fprintf('SC_P (操作前 - 任务4有智能体1,3):\n');
disp(SC_P3);
fprintf('SC_Q (操作后 - 智能体2也加入任务4，形成三方联盟):\n');
disp(SC_Q3);
fprintf('\n');

deltaU_case3 = overlap_coalition_utility(tasks, agents, SC_P3, SC_Q3, agentID, Value_Params, Value_data);

fprintf('计算结果: deltaU = %.4f\n', deltaU_case3);

rows_n_Q3 = find(SC_Q3(1:Value_Params.M, agentID) == agentID);
rows_n_P3 = find(SC_P3(1:Value_Params.M, agentID) == agentID);
new_tasks3 = setdiff(rows_n_Q3, rows_n_P3);

fprintf('详细计算过程:\n');
fprintf('  智能体%d在SC_P中参与的任务: %s\n', agentID, mat2str(rows_n_P3));
fprintf('  智能体%d在SC_Q中参与的任务: %s\n', agentID, mat2str(rows_n_Q3));
fprintf('  新增加入的任务行: %s (任务4)\n', mat2str(new_tasks3));

% 任务4的其他成员（智能体1和3）
members_task4_Q = find(SC_Q3(4, :) ~= 0);
members_task4_Q(members_task4_Q == agentID) = [];
fprintf('  任务4其他成员(SC_Q): %s\n', mat2str(members_task4_Q));
fprintf('  => 需要计算这些成员在SC_Q和SC_P下的效用差\n');

% Mem(A(n))
all_members_An3 = [];
for idx = 1:length(rows_n_Q3)
    task_row = rows_n_Q3(idx);
    members_task = find(SC_Q3(task_row, :) ~= 0);
    all_members_An3 = union(all_members_An3, members_task);
end
all_members_An3(all_members_An3 == agentID) = [];
fprintf('  Mem(A(n))\\{n}: %s\n', mat2str(all_members_An3));
fprintf('  => 需要计算这些成员在SC_Q和SC_P下的总效用\n');

fprintf('\n');

%% ==================== 总结 ====================
fprintf('========== 测试总结 ==========\n');
fprintf('Case 1 (从空任务加入): deltaU = %.4f\n', deltaU_case1);
fprintf('Case 2 (任务转移):      deltaU = %.4f\n', deltaU_case2);
fprintf('Case 3 (加入多成员联盟): deltaU = %.4f\n', deltaU_case3);
fprintf('\n');

% 基本合理性检查
fprintf('合理性验证:\n');
if deltaU_case1 > 0
    fprintf('  ? Case1 deltaU>0: 从空任务加入有价值任务，效用应增加\n');
else
    fprintf('  ? Case1 deltaU<=0: 可能受信念、成本等因素影响\n');
end

fprintf('\n所有测试完成。\n');
fprintf('请根据打印的中间过程验证计算逻辑是否正确。\n');
