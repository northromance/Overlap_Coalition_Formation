%% Huo2025算法快速测试
% 验证Huo2025算法是否能在对比框架中正常运行

clear; clc;
fprintf('\n========================================\n');
fprintf('   Huo2025算法验证测试\n');
fprintf('========================================\n\n');

%% 添加路径
addpath("Com_Huo2025\")
addpath("SA\")
addpath("plots\")

% 确保当前目录正确
if ~exist('initialize_scenario.m', 'file')
    error('无法找到initialize_scenario.m，请确保在项目根目录运行');
end

%% 1. 初始化场景
fprintf('1. 初始化测试场景...\n');
try
    SEED = 2437;
    [agents, tasks, Value_Params, WORLD, scenario_info] = initialize_scenario(SEED);
    fprintf('  ? 场景初始化成功\n');
    fprintf('    - 智能体数量: %d\n', length(agents));
    fprintf('    - 任务数量: %d\n', length(tasks));
    fprintf('\n');
catch ME
    fprintf('  ? 场景初始化失败: %s\n\n', ME.message);
    return;
end

%% 2. 检查必需文件
fprintf('2. 检查Huo2025算法文件...\n');
required_files = {
    'Com_Huo2025\Huo2025_main.m'
    'Com_Huo2025\Value_init.m'
    'Com_Huo2025\Value_order.m'
    'Com_Huo2025\Value_communication.m'
    'Com_Huo2025\drchrnd.m'
};

all_exist = true;
for i = 1:length(required_files)
    if exist(required_files{i}, 'file')
        fprintf('  ? %s\n', required_files{i});
    else
        fprintf('  ? %s (缺失)\n', required_files{i});
        all_exist = false;
    end
end

if ~all_exist
    fprintf('\n  ? 部分文件缺失，算法可能无法运行\n\n');
    return;
end
fprintf('\n');

%% 3. 测试函数接口
fprintf('3. 测试函数接口...\n');
try
    % 检查函数签名
    func_info = functions(@Huo2025_main);
    fprintf('  ? 函数句柄有效\n');
    fprintf('    函数名: %s\n', func_info.function);
catch ME
    fprintf('  ? 函数句柄错误: %s\n\n', ME.message);
    return;
end
fprintf('\n');

%% 4. 运行Huo2025算法
fprintf('4. 运行Huo2025算法（这可能需要一些时间）...\n');
AddPara.control = 1;

try
    tic;
    [Value_data, history_data] = Huo2025_main(agents, tasks, AddPara, Value_Params);
    elapsed = toc;
    
    fprintf('  ? 算法运行成功!\n');
    fprintf('    运行时间: %.2f秒\n', elapsed);
    fprintf('\n');
    
catch ME
    fprintf('  ? 算法运行失败:\n');
    fprintf('    错误: %s\n', ME.message);
    if ~isempty(ME.stack)
        fprintf('    位置: %s (第%d行)\n', ME.stack(1).name, ME.stack(1).line);
        if length(ME.stack) > 1
            fprintf('    调用栈:\n');
            for i = 2:min(3, length(ME.stack))
                fprintf('      - %s (第%d行)\n', ME.stack(i).name, ME.stack(i).line);
            end
        end
    end
    fprintf('\n');
    return;
end

%% 5. 验证输出格式
fprintf('5. 验证输出格式...\n');
try
    % 检查Value_data必需字段
    assert(isstruct(Value_data), 'Value_data应该是结构体');
    assert(isfield(Value_data, 'totalvalue'), '缺少totalvalue字段');
    assert(isfield(Value_data, 'coalitionstru'), '缺少coalitionstru字段');
    fprintf('  ? Value_data结构正确\n');
    
    % 检查history_data
    assert(isstruct(history_data), 'history_data应该是结构体');
    fprintf('  ? history_data结构正确\n');
    fprintf('\n');
    
catch ME
    fprintf('  ? 输出格式验证失败: %s\n\n', ME.message);
    return;
end

%% 6. 显示结果
fprintf('6. 算法结果摘要...\n');
fprintf('  总效用: %.2f\n', Value_data.totalvalue);

% 统计联盟
coal = Value_data.coalitionstru;
num_coalitions = 0;
for j = 1:size(coal, 1)
    if sum(coal(j, :) ~= 0) > 0
        num_coalitions = num_coalitions + 1;
    end
end
fprintf('  联盟数量: %d\n', num_coalitions);

if isfield(Value_data, 'cost_sum')
    fprintf('  总成本: %.2f\n', Value_data.cost_sum);
end

if isfield(history_data, 'num_rounds')
    fprintf('  迭代轮数: %d\n', history_data.num_rounds);
end
fprintf('\n');

%% 7. 测试总结
fprintf('========================================\n');
fprintf('   测试总结\n');
fprintf('========================================\n\n');

fprintf('? Huo2025算法验证通过!\n\n');
fprintf('可以执行以下操作:\n');
fprintf('  1. 运行 Compare_Algorithms.m 进行完整对比\n');
fprintf('  2. Huo2025算法已在对比框架中启用\n');
fprintf('  3. 结果会自动保存到 results/ 文件夹\n\n');

fprintf('========================================\n\n');
