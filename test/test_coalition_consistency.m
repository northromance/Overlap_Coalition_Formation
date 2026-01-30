% TEST_COALITION_CONSISTENCY 测试联盟一致性检查函数
%
% 功能：
%   测试 check_coalition_consistency 函数在不同场景下的表现
%   包括正常情况和各种异常情况的测试
%
% 测试场景：
%   1. 正常情况：合法的OCF联盟结构
%   2. 异常情况1：全局不一致（不同智能体的SC不同）
%   3. 异常情况2：资源越界（单任务投入超过上限）
%   4. 异常情况3：结构不对应（coalitionstru与SC不匹配）
%   5. 异常情况4：自洽性错误（个体矩阵与SC不一致）
%   6. 异常情况5：能量不足
%
% 使用方法：
%   直接运行此脚本：test_coalition_consistency

clear; clc;

% 添加必要的路径
addpath(genpath('E:\Overlap_Coalition_Formation'));

fprintf('==============================================\n');
fprintf('联盟一致性检查函数测试\n');
fprintf('==============================================\n\n');

%% 测试准备：初始化基本参数
Value_Params = struct();
Value_Params.N = 5;   % 5个智能体
Value_Params.M = 3;   % 3个任务
Value_Params.K = 2;   % 2种资源类型

% 创建简单的智能体数据
agents = struct('id', {}, 'resources', {}, 'Emax', {}, 'position', {});
for i = 1:Value_Params.N
    agents(i).id = i;
    agents(i).resources = [10, 10];  % 每个智能体有10单位的两种资源
    agents(i).Emax = 1000;           % 最大能量
    agents(i).position = [rand()*100, rand()*100];  % 随机位置
end

% 创建简单的任务数据
tasks = struct('id', {}, 'position', {}, 'priority', {});
for j = 1:Value_Params.M
    tasks(j).id = j;
    tasks(j).position = [rand()*100, rand()*100];
    tasks(j).priority = j;  % 优先级按任务ID递增
end

%% 测试1：正常情况 - 合法的OCF联盟结构
fprintf('\n【测试1】正常情况 - 合法的OCF联盟结构\n');
fprintf('----------------------------------------------\n');

Value_data = create_valid_coalition(Value_Params);
[is_valid, error_log] = check_coalition_consistency(Value_data, agents, tasks, Value_Params, 'OCF');

if is_valid
    fprintf('✅ 测试1通过：正常情况检查成功\n');
else
    fprintf('❌ 测试1失败：正常情况应该通过检查\n');
    disp(error_log);
end

%% 测试2：异常情况1 - 全局不一致
fprintf('\n【测试2】异常情况 - 全局不一致（不同智能体的SC不同）\n');
fprintf('----------------------------------------------\n');

Value_data = create_valid_coalition(Value_Params);
% 故意修改Agent 2的SC，使其与Agent 1不一致
Value_data(2).SC{1}(1, 1) = 999;  % 修改一个值

[is_valid, error_log] = check_coalition_consistency(Value_data, agents, tasks, Value_Params, 'OCF');

if ~is_valid
    fprintf('✅ 测试2通过：成功检测到全局不一致\n');
else
    fprintf('❌ 测试2失败：应该检测到全局不一致\n');
end

%% 测试3：异常情况2 - 资源越界（OCF模式）
fprintf('\n【测试3】异常情况 - 资源越界（单任务投入超过上限）\n');
fprintf('----------------------------------------------\n');

Value_data = create_valid_coalition(Value_Params);
% 故意让Agent 1在Task 1的资源投入超过上限
for i = 1:Value_Params.N
    Value_data(i).SC{1}(1, 1) = 15;  % 超过上限10
end

[is_valid, error_log] = check_coalition_consistency(Value_data, agents, tasks, Value_Params, 'OCF');

if ~is_valid
    fprintf('✅ 测试3通过：成功检测到资源越界\n');
else
    fprintf('❌ 测试3失败：应该检测到资源越界\n');
end

%% 测试4：异常情况3 - 结构不对应
fprintf('\n【测试4】异常情况 - 结构不对应（coalitionstru与SC不匹配）\n');
fprintf('----------------------------------------------\n');

Value_data = create_valid_coalition(Value_Params);
% 故意让Agent 3在Task 2的SC中有资源，但不在coalitionstru中
for i = 1:Value_Params.N
    Value_data(i).SC{2}(3, :) = [5, 5];  % Agent 3投入资源
    % 但不修改coalitionstru，使其不包含Agent 3
end

[is_valid, error_log] = check_coalition_consistency(Value_data, agents, tasks, Value_Params, 'OCF');

if ~is_valid
    fprintf('✅ 测试4通过：成功检测到结构不对应\n');
else
    fprintf('❌ 测试4失败：应该检测到结构不对应\n');
end

%% 测试5：异常情况4 - 自洽性错误
fprintf('\n【测试5】异常情况 - 自洽性错误（个体矩阵与SC不一致）\n');
fprintf('----------------------------------------------\n');

Value_data = create_valid_coalition(Value_Params);
% 故意让Agent 2的个体矩阵与SC不一致
Value_data(2).resources_matrix(1, :) = [999, 999];  % 修改个体矩阵

[is_valid, error_log] = check_coalition_consistency(Value_data, agents, tasks, Value_Params, 'OCF');

if ~is_valid
    fprintf('✅ 测试5通过：成功检测到自洽性错误\n');
else
    fprintf('❌ 测试5失败：应该检测到自洽性错误\n');
end

%% 测试6：Non-OCF模式测试
fprintf('\n【测试6】Non-OCF模式 - 资源总和越界\n');
fprintf('----------------------------------------------\n');

Value_data = create_valid_coalition(Value_Params);
% 在Non-OCF模式下，让Agent 1在多个任务的总资源投入超过上限
for i = 1:Value_Params.N
    Value_data(i).SC{1}(1, :) = [6, 6];  % Task 1投入6
    Value_data(i).SC{2}(1, :) = [5, 5];  % Task 2投入5
    % 总和11 > 上限10，在Non-OCF模式下应该报错
end

[is_valid, error_log] = check_coalition_consistency(Value_data, agents, tasks, Value_Params, 'Non-OCF');

if ~is_valid
    fprintf('✅ 测试6通过：成功检测到Non-OCF模式下的资源总和越界\n');
else
    fprintf('❌ 测试6失败：应该检测到资源总和越界\n');
end

%% 测试总结
fprintf('\n==============================================\n');
fprintf('测试完成\n');
fprintf('==============================================\n');

%% 辅助函数：创建合法的联盟结构
function Value_data = create_valid_coalition(Value_Params)
    % 创建一个合法的联盟结构用于测试
    N = Value_Params.N;
    M = Value_Params.M;
    K = Value_Params.K;

    % 初始化SC（全局联盟结构）
    SC = cell(M, 1);
    for j = 1:M
        SC{j} = zeros(N, K);
    end

    % 初始化coalitionstru（联盟成员结构）
    coalitionstru = zeros(M, N);

    % 为每个任务分配一些智能体
    % Task 1: Agent 1, 2
    SC{1}(1, :) = [5, 5];
    SC{1}(2, :) = [4, 4];
    coalitionstru(1, 1:2) = [1, 2];

    % Task 2: Agent 2, 3
    SC{2}(2, :) = [6, 6];
    SC{2}(3, :) = [5, 5];
    coalitionstru(2, 1:2) = [2, 3];

    % Task 3: Agent 1, 4, 5
    SC{3}(1, :) = [3, 3];
    SC{3}(4, :) = [4, 4];
    SC{3}(5, :) = [5, 5];
    coalitionstru(3, 1:3) = [1, 4, 5];

    % 为每个智能体创建Value_data
    Value_data = struct('SC', {}, 'coalitionstru', {}, 'resources_matrix', {});
    for i = 1:N
        Value_data(i).SC = SC;
        Value_data(i).coalitionstru = coalitionstru;

        % 创建个体资源矩阵（与SC保持一致）
        Value_data(i).resources_matrix = zeros(M, K);
        for j = 1:M
            if ~isempty(SC{j}) && i <= size(SC{j}, 1)
                Value_data(i).resources_matrix(j, :) = SC{j}(i, :);
            end
        end
    end
end
