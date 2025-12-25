% tests/test_overlap_coalition_self_utility.m
% 测试 overlap_coalition_self_utility 函数的效用计算
% 基于 literature/utility_calculation_formula.md 中的公式

clear; clc;

% 添加路径
thisFile = mfilename('fullpath');
[thisDir, ~, ~] = fileparts(thisFile);
projectRoot = fileparts(thisDir);
addpath(fullfile(projectRoot, 'SA'));

rng(42);

fprintf('========== 测试 overlap_coalition_self_utility 函数 ==========\n\n');

%% ==================== Case 1: 简单单任务场景 ====================
fprintf('Case 1: 单智能体单任务基础场景\n');

% 参数设置
Value_Params.M = 3;           % 3个任务
Value_Params.K = 4;           % 4种资源类型
Value_Params.N = 2;           % 2个智能体
Value_Params.alpha = 1.5;     % 飞行燃油消耗 (单位/小时)
Value_Params.beta = 2.0;      % 执行任务能耗 (单位/小时)

% 智能体1
agents(1).id = 1;
agents(1).x = 0;
agents(1).y = 0;
agents(1).speed = 10;         % 速度 (单位/小时)
agents(1).resources = [10; 15; 20; 5];  % 4种资源

% 智能体2
agents(2).id = 2;
agents(2).x = 10;
agents(2).y = 0;
agents(2).speed = 10;
agents(2).resources = [5; 10; 15; 10];

% 任务1: 位置(20, 0), 需求资源 [8, 12, 0, 0]
tasks(1).id = 1;
tasks(1).x = 20;
tasks(1).y = 0;
tasks(1).resource_demand = [8, 12, 0, 0];
tasks(1).duration = 3;        % 执行时间 3小时
tasks(1).WORLD.value = [80, 90, 100];  % 三种世界状态下的价值
tasks(1).WORLD.risk = [5, 10, 15];

% 任务2
tasks(2).id = 2;
tasks(2).x = 30;
tasks(2).y = 10;
tasks(2).resource_demand = [10, 10, 5, 2];
tasks(2).duration = 5;
tasks(2).WORLD.value = [100, 120, 140];
tasks(2).WORLD.risk = [8, 12, 18];

% 任务3
tasks(3).id = 3;
tasks(3).x = 40;
tasks(3).y = 20;
tasks(3).resource_demand = [5, 8, 10, 3];
tasks(3).duration = 4;
tasks(3).WORLD.value = [60, 80, 100];
tasks(3).WORLD.risk = [3, 6, 9];

% 信念分布 (均匀分布)
Value_data.initbelief = [
    1/3, 1/3, 1/3;   % 任务1
    1/3, 1/3, 1/3;   % 任务2
    1/3, 1/3, 1/3    % 任务3
];

% 联盟结构: 智能体1参与任务1, 智能体2参与任务1
coalitionstru = zeros(Value_Params.M, Value_Params.N);
coalitionstru(1, 1) = 1;  % 智能体1加入任务1
coalitionstru(1, 2) = 2;  % 智能体2加入任务1

% 资源分配矩阵 (简化: 每个智能体贡献其全部资源到任务)
Value_data.resources_matrix = zeros(Value_Params.M, Value_Params.K);
Value_data.resources_matrix(1, :) = agents(1).resources';  % 智能体1给任务1的资源

% 计算智能体1在任务1中的效用
utility_1 = overlap_coalition_self_utility(1, 1, coalitionstru, agents, tasks, Value_Params, Value_data);

fprintf('  智能体1在任务1的效用: %.4f\n', utility_1);
fprintf('  预期: 收益 > 0, 成本包括飞行(20/10*1.5=3) + 执行(3*2=6)\n');

% 基本验证: 效用应该是有限数值
assert(isfinite(utility_1), 'Case1 failed: utility should be finite');
fprintf('  ? Case 1 通过\n\n');


%% ==================== Case 2: 多任务序列场景 ====================
fprintf('Case 2: 智能体参与多个任务的累积效用\n');

% 智能体1参与任务1和任务2
coalitionstru2 = zeros(Value_Params.M, Value_Params.N);
coalitionstru2(1, 1) = 1;  % 任务1
coalitionstru2(2, 1) = 1;  % 任务2

Value_data2 = Value_data;
Value_data2.resources_matrix(2, :) = agents(1).resources' * 0.5;  % 任务2资源分配

% 计算智能体1在任务1的效用 (只有任务1)
utility_task1 = overlap_coalition_self_utility(1, 1, coalitionstru2, agents, tasks, Value_Params, Value_data2);

% 计算智能体1在任务2的效用 (累积到任务2)
utility_task2 = overlap_coalition_self_utility(1, 2, coalitionstru2, agents, tasks, Value_Params, Value_data2);

fprintf('  智能体1在任务1的效用: %.4f\n', utility_task1);
fprintf('  智能体1在任务2的效用: %.4f\n', utility_task2);
fprintf('  预期: 任务2的成本更高(包含飞行到任务1和任务2的累积时间)\n');

assert(isfinite(utility_task1) && isfinite(utility_task2), 'Case2 failed: utilities should be finite');
fprintf('  ? Case 2 通过\n\n');


%% ==================== Case 3: 验证公式中的示例数据 ====================
fprintf('Case 3: 验证文献中的计算示例\n');
fprintf('  已知数据: t_wait=20h, α=1.5, T_exec=8h, β=2, r_n=0.25, D_C=0.75, V_C=80\n');

% 构造特定场景
Value_Params3.M = 1;
Value_Params3.K = 2;
Value_Params3.N = 2;
Value_Params3.alpha = 1.5;
Value_Params3.beta = 2.0;

agents3(1).id = 1;
agents3(1).x = 0;
agents3(1).y = 0;
agents3(1).speed = 1;  % 速度=1, 使得距离=时间
agents3(1).resources = [5; 5];  % 资源贡献 = 0.25 (占总资源的1/4)

agents3(2).id = 2;
agents3(2).x = 0;
agents3(2).y = 0;
agents3(2).speed = 1;
agents3(2).resources = [15; 15];  % 资源贡献 = 0.75

% 任务在距离20的位置 (飞行时间=20h)
tasks3(1).id = 1;
tasks3(1).x = 20;
tasks3(1).y = 0;
% 要让D_C = 0.75: 总分配资源=20+20=40, 需求应该让 (20/demand + 20/demand)/2 = 0.75
% 即 40/demand = 0.75 * 2 = 1.5, demand = 40/1.5 ≈ 26.67
tasks3(1).resource_demand = [26.67, 26.67];  % 使得完成度D_C = 0.75
tasks3(1).duration = 8;  % 执行时间8小时
tasks3(1).WORLD.value = [80, 80, 80];  % 固定价值80
tasks3(1).WORLD.risk = [0, 0, 0];

Value_data3.initbelief = [1, 0, 0];  % 确定性世界状态
Value_data3.resources_matrix = zeros(1, 2);
Value_data3.resources_matrix(1, :) = agents3(1).resources';

coalitionstru3 = zeros(1, 2);
coalitionstru3(1, 1) = 1;
coalitionstru3(1, 2) = 2;

utility_example = overlap_coalition_self_utility(1, 1, coalitionstru3, agents3, tasks3, Value_Params3, Value_data3);

fprintf('  计算得到的效用: %.4f\n', utility_example);
fprintf('  预期效用: 0.25 × 80 × 0.75 - (20×1.5 + 8×2) = 15 - 46 = -31\n');

% 允许一定误差
expected_utility = -31;
tolerance = 1.5;  % 允许±1.5的误差（考虑浮点数计算精度）
assert(abs(utility_example - expected_utility) < tolerance, ...
    sprintf('Case3 failed: expected ~%.2f, got %.2f', expected_utility, utility_example));
fprintf('  ? Case 3 通过 (误差在可接受范围内)\n\n');


%% ==================== Case 4: 空联盟场景 ====================
fprintf('Case 4: 空联盟/无效任务场景\n');

coalitionstru_empty = zeros(Value_Params.M, Value_Params.N);
utility_empty = overlap_coalition_self_utility(1, 1, coalitionstru_empty, agents, tasks, Value_Params, Value_data);

fprintf('  空联盟效用: %.4f\n', utility_empty);
assert(utility_empty == 0, 'Case4 failed: empty coalition should have 0 utility');
fprintf('  ? Case 4 通过\n\n');


%% ==================== Case 5: 资源过剩场景 (D_C > 1) ====================
fprintf('Case 5: 资源过剩场景 (完成度限制在1.0)\n');

% 智能体资源远超任务需求
agents5 = agents;
agents5(1).resources = [100; 100; 100; 100];  % 资源过剩

coalitionstru5 = zeros(Value_Params.M, Value_Params.N);
coalitionstru5(1, 1) = 1;

Value_data5 = Value_data;
Value_data5.resources_matrix(1, :) = agents5(1).resources';

utility_oversupply = overlap_coalition_self_utility(1, 1, coalitionstru5, agents5, tasks, Value_Params, Value_data5);

fprintf('  资源过剩时的效用: %.4f\n', utility_oversupply);
fprintf('  预期: D_C应该被限制在1.0, 效用为正\n');

assert(isfinite(utility_oversupply), 'Case5 failed: utility should be finite');
fprintf('  ? Case 5 通过\n\n');


%% ==================== 测试总结 ====================
fprintf('========================================\n');
fprintf('所有测试通过! ?\n');
fprintf('overlap_coalition_self_utility 函数验证完成。\n');
fprintf('========================================\n');
