% tests/test_compute_allocated_and_gap.m
% 测试 compute_allocated_and_gap 函数的资源分配和缺口计算

clear; clc;

thisFile = mfilename('fullpath');
[thisDir, ~, ~] = fileparts(thisFile);
projectRoot = fileparts(thisDir);
addpath(fullfile(projectRoot, 'SA'));

fprintf('=== 测试 compute_allocated_and_gap ===\n\n');

%% 初始化参数
Value_Params.M = 3;  % 3个任务
Value_Params.K = 2;  % 2种资源类型
Value_Params.N = 4;  % 4个智能体

% 任务类型需求矩阵 task_type_demands (T×K)
% 这里设 T=3 个任务类型，每种类型对 K=2 种资源的需求不同
Value_Params.task_type_demands = [10 8;
                                 11 7;
                                  9 9];

%% 初始化智能体
for i = 1:Value_Params.N
    agents(i).id = i;
    agents(i).x = i;
    agents(i).y = 0;
    agents(i).resources = [5; 3];  % 每个智能体有5单位资源类型1，3单位资源类型2
end

%% 初始化任务
for j = 1:Value_Params.M
    tasks(j).id = j;
    tasks(j).x = j;
    tasks(j).y = 0;
    % 注意：在本测试中，compute_allocated_and_gap 使用“信念+task_type_demands”的期望需求
    % tasks(j).resource_demand 在这里不参与缺口计算，仅保留字段不影响运行
    tasks(j).resource_demand = [0, 0];
end

%% 初始化 Value_data
for i = 1:Value_Params.N
    Value_data(i).agentID = agents(i).id;
    Value_data(i).agentIndex = i;
    Value_data(i).iteration = 0;
    Value_data(i).unif = 0;
    Value_data(i).coalitionstru = zeros(Value_Params.M+1, Value_Params.N);
    % initbelief(j,:)：对任务j属于各类型的信念分布（长度=任务类型数T）
    % 与 SA_Value_main 一致：维度 (M+1)×T（第 M+1 行可留作 void）
    Value_data(i).initbelief = zeros(Value_Params.M+1, size(Value_Params.task_type_demands, 1));
    
    % SC：资源联盟结构，cell数组格式（与SA_Value_main一致）
    % SC{m} 是一个 N×K 矩阵，表示任务m上N个机器人分配的K种资源类型的数量
    Value_data(i).SC = cell(Value_Params.M, 1);
    for m = 1:Value_Params.M
        Value_data(i).SC{m} = zeros(Value_Params.N, Value_Params.K);
    end
end

%% 设置任务类型信念（用于期望需求计算）
% 让每个任务的信念为 one-hot，便于人工核对：
% - 任务1：100% 类型1 -> 期望需求 = [10,8]
% - 任务2：100% 类型2 -> 期望需求 = [11,7]
% - 任务3：100% 类型3 -> 期望需求 = [ 9,9]
Value_data(1).initbelief(1, :) = [1 0 0];
Value_data(1).initbelief(2, :) = [0 1 0];
Value_data(1).initbelief(3, :) = [0 0 1];

% 同步belief到所有智能体（在工程中belief通常是每个智能体各自维护，这里为了测试一致性统一）
for i = 2:Value_Params.N
    Value_data(i).initbelief = Value_data(1).initbelief;
end

%% 设置一个示例资源分配场景
% SC(m, n, k) 表示：任务m上，智能体n分配的资源类型k的数量
% 
% 场景说明：
% - 任务1：由智能体1和2共同执行（重叠联盟）
% - 任务2：由智能体1和3共同执行（重叠联盟）
% - 任务3：由智能体2和4共同执行（重叠联盟）
% - 智能体1参与了任务1和2（一个智能体可参与多个任务）

% 任务1的资源分配：
%   智能体1贡献：资源类型1=2单位，资源类型2=1单位
Value_data(1).SC{1}(1, :) = [2, 1];  % SC{任务1}(智能体1, [资源1, 资源2])
%   智能体2贡献：资源类型1=3单位，资源类型2=2单位
Value_data(1).SC{1}(2, :) = [3, 2];  % SC{任务1}(智能体2, [资源1, 资源2])
%   任务1总获得：资源1=2+3=5，资源2=1+2=3

% 任务2的资源分配：
%   智能体1贡献：资源类型1=1单位，资源类型2=0单位
Value_data(1).SC{2}(1, :) = [1, 0];  % SC{任务2}(智能体1, [资源1, 资源2])
%   智能体3贡献：资源类型1=2单位，资源类型2=3单位
Value_data(1).SC{2}(3, :) = [2, 3];  % SC{任务2}(智能体3, [资源1, 资源2])
%   任务2总获得：资源1=1+2=3，资源2=0+3=3

% 任务3的资源分配：
%   智能体2贡献：资源类型1=0单位，资源类型2=1单位
Value_data(1).SC{3}(2, :) = [0, 1];  % SC{任务3}(智能体2, [资源1, 资源2])
%   智能体4贡献：资源类型1=4单位，资源类型2=2单位
Value_data(1).SC{3}(4, :) = [4, 2];  % SC{任务3}(智能体4, [资源1, 资源2])
%   任务3总获得：资源1=0+4=4，资源2=1+2=3

% 各智能体的资源分配汇总：
%   智能体1：参与任务1和2，总分配 资源1=2+1=3，资源2=1+0=1
%   智能体2：参与任务1和3，总分配 资源1=3+0=3，资源2=2+1=3
%   智能体3：仅参与任务2，总分配 资源1=2，资源2=3
%   智能体4：仅参与任务3，总分配 资源1=4，资源2=2

% 同步SC到所有智能体
for i = 2:Value_Params.N
    Value_data(i).SC = Value_data(1).SC;
end

%% 调用函数
[allocated_resources, resource_gap] = compute_allocated_and_gap(Value_data, agents, tasks, Value_Params);

%% 打印输入设置
fprintf('输入设置:\n');
fprintf('- 任务数 M = %d\n', Value_Params.M);
fprintf('- 智能体数 N = %d\n', Value_Params.N);
fprintf('- 资源类型数 K = %d\n\n', Value_Params.K);

fprintf('每个智能体的资源容量: [%d, %d]\n', agents(1).resources(1), agents(1).resources(2));
fprintf('task\_type\_demands (T×K) =\n');
disp(Value_Params.task_type_demands);
fprintf('任务信念 initbelief(1:M,:) =\n');
disp(Value_data(1).initbelief(1:Value_Params.M, :));
fprintf('\n');

%% 打印SC矩阵（资源分配情况）
fprintf('SC 资源分配矩阵:\n');
for m = 1:Value_Params.M
    fprintf('  任务%d:\n', m);
    for n = 1:Value_Params.N
        resources = Value_data(1).SC{m}(n, :);
        if any(resources > 0)
            fprintf('    智能体%d -> [资源1=%d, 资源2=%d]\n', n, resources(1), resources(2));
        end
    end
end
fprintf('\n');

%% 打印计算结果
fprintf('计算结果:\n\n');

fprintf('1. allocated_resources (每个智能体已分配的资源总量):\n');
fprintf('   维度: %d×%d (智能体×资源类型)\n\n', size(allocated_resources, 1), size(allocated_resources, 2));
for i = 1:Value_Params.N
    fprintf('   智能体%d: 资源类型1=%d, 资源类型2=%d\n', ...
        i, allocated_resources(i, 1), allocated_resources(i, 2));
end
fprintf('\n');

fprintf('2. resource_gap (每个任务的资源缺口):\n');
fprintf('   维度: %d×%d (任务×资源类型)\n\n', size(resource_gap, 1), size(resource_gap, 2));
for j = 1:Value_Params.M
    fprintf('   任务%d: 资源类型1缺口=%d, 资源类型2缺口=%d\n', ...
        j, resource_gap(j, 1), resource_gap(j, 2));
end
fprintf('\n');

%% 手动验证
fprintf('手动验证:\n\n');

fprintf('智能体已分配资源 (应该等于对所有任务分配的总和):\n');
for i = 1:Value_Params.N
    total_r1 = 0;
    total_r2 = 0;
    for m = 1:Value_Params.M
        total_r1 = total_r1 + Value_data(1).SC{m}(i, 1);
        total_r2 = total_r2 + Value_data(1).SC{m}(i, 2);
    end
    fprintf('   智能体%d: 资源1总和=%d (函数返回=%d), 资源2总和=%d (函数返回=%d)\n', ...
        i, total_r1, allocated_resources(i, 1), total_r2, allocated_resources(i, 2));
    
    % 断言检查
    assert(total_r1 == allocated_resources(i, 1), '智能体%d资源1计算错误', i);
    assert(total_r2 == allocated_resources(i, 2), '智能体%d资源2计算错误', i);
end
fprintf('\n');

fprintf('任务资源缺口 (需求 - 已获得):\n');
for j = 1:Value_Params.M
    allocated_r1 = sum(Value_data(1).SC{j}(:, 1));
    allocated_r2 = sum(Value_data(1).SC{j}(:, 2));

    % 期望需求 = belief * task_type_demands
    belief_j = Value_data(1).initbelief(j, :);
    expected_demand_vec = belief_j * Value_Params.task_type_demands; % 1×K
    gap_r1 = expected_demand_vec(1) - allocated_r1;
    gap_r2 = expected_demand_vec(2) - allocated_r2;
    
    fprintf('   任务%d: E[需求]=[%g,%g], 已获得=[%d,%d], 缺口=[%g,%g] (函数返回=[%g,%g])\n', ...
        j, expected_demand_vec(1), expected_demand_vec(2), ...
        allocated_r1, allocated_r2, gap_r1, gap_r2, ...
        resource_gap(j, 1), resource_gap(j, 2));
    
    % 断言检查
    assert(gap_r1 == resource_gap(j, 1), '任务%d资源1缺口计算错误', j);
    assert(gap_r2 == resource_gap(j, 2), '任务%d资源2缺口计算错误', j);
end
fprintf('\n');

fprintf('? 所有测试通过！\n');
