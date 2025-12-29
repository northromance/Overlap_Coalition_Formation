% 简单快速测试 SA_Value_main 的核心功能
clear; clc;

% 添加路径（相对于tests目录）
testDir = fileparts(mfilename('fullpath'));
projectRoot = fileparts(testDir);
addpath(fullfile(projectRoot, 'SA'));
addpath(projectRoot);  % 根目录（包含 drchrnd.m 等辅助函数）
addpath(testDir);

fprintf('========== SA_Value_main 简单测试 ==========\n\n');

% 创建最小测试数据
N = 2;  % 2个智能体
M = 2;  % 2个任务  
K = 2;  % 2种资源类型

% 初始化智能体
for i = 1:N
    agents(i).id = i;
    agents(i).vel = 2;
    agents(i).fuel = 1;
    agents(i).x = rand() * 100;
    agents(i).y = rand() * 100;
    agents(i).detprob = 0.8;
    agents(i).resources = randi([2, 5], K, 1);
    agents(i).Emax = 1000;
    agents(i).beta = 1;
end

% 初始化任务
WORLD_value = [300, 500, 1000];
task_type_demands = randi([0, 3], 2, K);

for j = 1:M
    tasks(j).id = j;
    tasks(j).priority = j;
    tasks(j).x = rand() * 100;
    tasks(j).y = rand() * 100;
    tasks(j).value = WORLD_value(randi(length(WORLD_value)));
    tasks(j).type = 1;
    tasks(j).resource_demand = task_type_demands(1, :);
    tasks(j).duration_by_resource = ones(1, K) * 50;
    tasks(j).duration = sum(tasks(j).duration_by_resource);
    tasks(j).WORLD.value = WORLD_value;
end

% 初始化参数
Value_Params.N = N;
Value_Params.M = M;
Value_Params.K = K;
Value_Params.task_type_demands = task_type_demands;
Value_Params.Temperature = 10.0;
Value_Params.alpha = 0.5;  % 快速衰减
Value_Params.Tmin = 0.1;
Value_Params.max_stable_iterations = 2;  % 快速收敛

% 初始化图结构
Graph = ones(N, N) - eye(N);

% 初始化AddPara
AddPara.control = 1;

fprintf('测试参数:\n');
fprintf('  智能体数: %d\n', N);
fprintf('  任务数: %d\n', M);
fprintf('  资源类型数: %d\n', K);
fprintf('  初始温度: %.2f\n', Value_Params.Temperature);
fprintf('  温度衰减率: %.2f\n', Value_Params.alpha);
fprintf('\n');

try
    fprintf('开始运行 SA_Value_main...\n');
    tic;
    [Value_data, Rcost, cost_sum, net_profit, initial_coalition] = ...
        SA_Value_main(agents, tasks, Graph, AddPara, Value_Params);
    elapsed = toc;
    fprintf('运行完成！耗时: %.3f 秒\n\n', elapsed);
    
    % 验证输出
    fprintf('========== 结果验证 ==========\n');
    
    fprintf('1. Value_data 结构:\n');
    fprintf('   - 长度: %d (期望: %d) %s\n', length(Value_data), N, ...
        ifeq(length(Value_data), N));
    
    fprintf('2. 关键字段检查:\n');
    all_have_SC = true;
    all_have_coalition = true;
    for i = 1:N
        if ~isfield(Value_data(i), 'SC')
            all_have_SC = false;
        end
        if ~isfield(Value_data(i), 'coalitionstru')
            all_have_coalition = false;
        end
    end
    fprintf('   - 所有智能体包含 SC: %s\n', bool2str(all_have_SC));
    fprintf('   - 所有智能体包含 coalitionstru: %s\n', bool2str(all_have_coalition));
    
    fprintf('3. SC 结构验证:\n');
    SC_valid = true;
    for i = 1:N
        if ~iscell(Value_data(i).SC) || length(Value_data(i).SC) ~= M
            SC_valid = false;
            break;
        end
        for m = 1:M
            if ~ismatrix(Value_data(i).SC{m}) || ...
                    any(size(Value_data(i).SC{m}) ~= [N, K])
                SC_valid = false;
                break;
            end
        end
    end
    fprintf('   - SC 维度正确: %s\n', bool2str(SC_valid));
    
    fprintf('4. SC 同步性验证:\n');
    SC_synced = true;
    for i = 2:N
        for m = 1:M
            if ~isequal(Value_data(1).SC{m}, Value_data(i).SC{m})
                SC_synced = false;
                break;
            end
        end
        if ~SC_synced
            break;
        end
    end
    fprintf('   - 所有智能体 SC 同步: %s\n', bool2str(SC_synced));
    
    fprintf('5. initial_coalition 验证:\n');
    fprintf('   - 维度: %d×%d (期望: %d×%d) %s\n', ...
        size(initial_coalition, 1), size(initial_coalition, 2), ...
        M+1, N, ifeq([size(initial_coalition, 1), size(initial_coalition, 2)], [M+1, N]));
    
    fprintf('\n========== 测试通过 ==========\n');
    
catch ME
    fprintf('\n========== 测试失败 ==========\n');
    fprintf('错误信息: %s\n', ME.message);
    fprintf('错误位置:\n');
    for i = 1:length(ME.stack)
        fprintf('  %s (行 %d)\n', ME.stack(i).name, ME.stack(i).line);
    end
    exit(1);
end

function str = bool2str(val)
    if val
        str = '? 是';
    else
        str = '? 否';
    end
end

function str = ifeq(a, b)
    if isequal(a, b)
        str = '?';
    else
        str = '?';
    end
end
