%% test_task_schedule.m
% 测试任务调度跟踪功能
% 验证 Value_data.task_schedule 结构的正确性

clear; clc; close all;

fprintf('========== 任务调度跟踪功能测试 ==========\n\n');

%% 1. 初始化测试参数
Value_Params.N = 4;  % 4个智能体
Value_Params.M = 3;  % 3个任务
Value_Params.K = 3;  % 3种资源类型

%% 2. 创建测试智能体
agents = struct();
positions = [0, 0; 10, 0; 0, 10; 10, 10];  % 四角分布
for i = 1:Value_Params.N
    agents(i).id = i;
    agents(i).x = positions(i, 1);
    agents(i).y = positions(i, 2);
    agents(i).vel = 2;      % 速度
    agents(i).fuel = 1;     % 飞行能耗系数
    agents(i).beta = 1;     % 执行能耗系数
    agents(i).resources = [3, 3, 3];  % 每种资源3单位
end

%% 3. 创建测试任务
tasks = struct();
task_positions = [5, 5; 15, 5; 5, 15];  % 任务位置
task_priorities = [1, 2, 3];
task_demands = [4, 0, 0; 0, 4, 0; 0, 0, 4];  % 每个任务需要一种资源

for m = 1:Value_Params.M
    tasks(m).id = m;
    tasks(m).x = task_positions(m, 1);
    tasks(m).y = task_positions(m, 2);
    tasks(m).priority = task_priorities(m);
    tasks(m).resource_demand = task_demands(m, :);
    tasks(m).duration_by_resource = [5, 8, 6];  % 各资源类型执行时间
end

%% 4. 构造测试联盟结构
% 场景：
%   - 任务1: 智能体1和智能体2参与（各贡献2单位资源类型1）
%   - 任务2: 智能体3单独参与（贡献4单位资源类型2）
%   - 任务3: 智能体1、3、4参与（各贡献部分资源类型3）

SC = cell(Value_Params.M, 1);
for m = 1:Value_Params.M
    SC{m} = zeros(Value_Params.N, Value_Params.K);
end

% 任务1的资源分配
SC{1}(1, 1) = 2;  % 智能体1贡献2单位资源类型1
SC{1}(2, 1) = 2;  % 智能体2贡献2单位资源类型1

% 任务2的资源分配
SC{2}(3, 2) = 4;  % 智能体3贡献4单位资源类型2

% 任务3的资源分配
SC{3}(1, 3) = 2;  % 智能体1贡献2单位资源类型3
SC{3}(3, 3) = 1;  % 智能体3贡献1单位资源类型3
SC{3}(4, 3) = 1;  % 智能体4贡献1单位资源类型3

%% 5. 初始化 Value_data 结构
for i = 1:Value_Params.N
    Value_data(i).agentID = agents(i).id;
    Value_data(i).agentIndex = i;
    Value_data(i).SC = SC;
    
    % 从SC计算resources_matrix
    Value_data(i).resources_matrix = zeros(Value_Params.M, Value_Params.K);
    for m = 1:Value_Params.M
        Value_data(i).resources_matrix(m, :) = SC{m}(i, :);
    end
    
    % 初始化task_schedule（空结构）
    Value_data(i).task_schedule = struct();
    Value_data(i).task_schedule.task_sequence = [];
    Value_data(i).task_schedule.arrival_times = [];
    Value_data(i).task_schedule.start_times = [];
    Value_data(i).task_schedule.execution_times = [];
    Value_data(i).task_schedule.completion_times = [];
    Value_data(i).task_schedule.total_flight_time = 0;
    Value_data(i).task_schedule.total_execution_time = 0;
    Value_data(i).task_schedule.total_energy = 0;
end

%% 6. 调用 update_task_schedule 更新调度信息
fprintf('测试 update_task_schedule 函数...\n');
Value_data = update_task_schedule(Value_data, agents, tasks, Value_Params);
fprintf('? update_task_schedule 执行成功\n\n');

%% 7. 验证结果
fprintf('验证结果:\n');
fprintf('%s\n', repmat('-', 1, 60));

for i = 1:Value_Params.N
    schedule = Value_data(i).task_schedule;
    
    fprintf('\n智能体 %d:\n', i);
    fprintf('  参与任务: ');
    
    if isempty(schedule.task_sequence)
        fprintf('无\n');
    else
        fprintf('%s\n', mat2str(schedule.task_sequence));
        fprintf('  到达时间: %s\n', mat2str(schedule.arrival_times', 4));
        fprintf('  开始时间: %s\n', mat2str(schedule.start_times', 4));
        fprintf('  执行时间: %s\n', mat2str(schedule.execution_times', 4));
        fprintf('  完成时间: %s\n', mat2str(schedule.completion_times', 4));
        fprintf('  总飞行时间: %.2f\n', schedule.total_flight_time);
        fprintf('  总执行时间: %.2f\n', schedule.total_execution_time);
        fprintf('  总能量: %.2f\n', schedule.total_energy);
    end
end

%% 8. 验证同步机制
fprintf('\n\n========== 验证同步机制 ==========\n');

% 任务1有两个智能体参与，检查它们的开始时间是否一致
schedule_1 = Value_data(1).task_schedule;
schedule_2 = Value_data(2).task_schedule;

% 找到任务1在各智能体序列中的位置
idx_1_in_agent1 = find(schedule_1.task_sequence == 1);
idx_1_in_agent2 = find(schedule_2.task_sequence == 1);

if ~isempty(idx_1_in_agent1) && ~isempty(idx_1_in_agent2)
    start_1_agent1 = schedule_1.start_times(idx_1_in_agent1);
    start_1_agent2 = schedule_2.start_times(idx_1_in_agent2);
    
    fprintf('任务1开始时间:\n');
    fprintf('  智能体1: %.2f\n', start_1_agent1);
    fprintf('  智能体2: %.2f\n', start_1_agent2);
    
    if abs(start_1_agent1 - start_1_agent2) < 1e-6
        fprintf('? 同步验证通过: 两个智能体同时开始任务1\n');
    else
        fprintf('? 同步验证失败: 开始时间不一致\n');
    end
    
    % 检查执行时间是否一致
    exec_1_agent1 = schedule_1.execution_times(idx_1_in_agent1);
    exec_1_agent2 = schedule_2.execution_times(idx_1_in_agent2);
    
    fprintf('任务1执行时间:\n');
    fprintf('  智能体1: %.2f\n', exec_1_agent1);
    fprintf('  智能体2: %.2f\n', exec_1_agent2);
    
    if abs(exec_1_agent1 - exec_1_agent2) < 1e-6
        fprintf('? 执行时间验证通过: 两个智能体执行时间一致\n');
    else
        fprintf('? 执行时间验证失败: 执行时间不一致\n');
    end
end

%% 9. 可视化调度
fprintf('\n\n========== 调用可视化函数 ==========\n');

% 调用文本显示
display_task_schedule(Value_data, agents, tasks, Value_Params);

% 调用甘特图
plot_task_schedule_gantt(Value_data, agents, tasks, Value_Params);

fprintf('\n========== 测试完成 ==========\n');
