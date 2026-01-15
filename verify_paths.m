%% 路径验证脚本
% 检查Compare_Algorithms.m所需的所有路径和文件是否正确

clear; clc;
fprintf('\n========================================\n');
fprintf('   Compare_Algorithms 路径验证\n');
fprintf('========================================\n\n');

%% 1. 模拟添加路径（与Compare_Algorithms.m一致）
fprintf('1. 添加路径...\n');
addpath("Main_fun\")
addpath("SA\")
addpath("plots\")
addpath("Com_Baseline\")
addpath("Com_Huo2025\")
addpath("Com_Qi2023\")
addpath("Com_Qin2025\")
fprintf('  ? 路径已添加\n\n');

%% 2. 检查核心函数
fprintf('2. 检查核心函数...\n');
core_functions = {
    'initialize_scenario'
    'compare_results'
    'init_value_params'
    'drchrnd'
};

all_core_exist = true;
for i = 1:length(core_functions)
    func_name = core_functions{i};
    if exist(func_name, 'file')
        func_path = which(func_name);
        fprintf('  ? %s\n', func_name);
        fprintf('    位置: %s\n', func_path);
    else
        fprintf('  ? %s (未找到)\n', func_name);
        all_core_exist = false;
    end
end

if all_core_exist
    fprintf('  结果: 所有核心函数可访问 ?\n\n');
else
    fprintf('  结果: 部分核心函数缺失 ?\n\n');
    return;
end

%% 3. 检查SA算法函数
fprintf('3. 检查SA算法函数...\n');
sa_functions = {
    'SA_Value_main'
    'Overlap_Coalition_Formation'
};

for i = 1:length(sa_functions)
    func_name = sa_functions{i};
    if exist(func_name, 'file')
        fprintf('  ? %s\n', func_name);
    else
        fprintf('  ? %s (未找到，算法可能无法运行)\n', func_name);
    end
end
fprintf('\n');

%% 4. 检查对比算法函数
fprintf('4. 检查对比算法函数...\n');
comparison_algorithms = {
    'Greedy_Baseline_main', 'Com_Baseline'
    'Huo2025_main', 'Com_Huo2025'
};

for i = 1:size(comparison_algorithms, 1)
    func_name = comparison_algorithms{i, 1};
    folder = comparison_algorithms{i, 2};
    
    if exist(func_name, 'file')
        fprintf('  ? %s (%s)\n', func_name, folder);
    else
        fprintf('  ? %s (%s) (未找到)\n', func_name, folder);
    end
end
fprintf('\n');

%% 5. 检查可视化函数
fprintf('5. 检查可视化函数...\n');
plot_functions = {
    'plot_algorithm_comparison'
    'plot_main_results'
};

for i = 1:length(plot_functions)
    func_name = plot_functions{i};
    if exist(func_name, 'file')
        fprintf('  ? %s\n', func_name);
    else
        fprintf('  ? %s (未找到，图表显示可能受影响)\n', func_name);
    end
end
fprintf('\n');

%% 6. 测试核心功能
fprintf('6. 测试核心功能...\n');

% 测试场景初始化
fprintf('  测试 initialize_scenario...\n');
try
    SEED = 2437;
    [agents, tasks, Value_Params, WORLD, scenario_info] = initialize_scenario(SEED);
    fprintf('    ? 场景初始化成功 (N=%d, M=%d, K=%d)\n', ...
            length(agents), length(tasks), Value_Params.K);
catch ME
    fprintf('    ? 场景初始化失败: %s\n', ME.message);
    return;
end

% 测试compare_results（使用模拟数据）
fprintf('  测试 compare_results...\n');
try
    % 创建模拟结果
    test_results = struct();
    test_results.alg1.name = '测试算法';
    test_results.alg1.Value_data.totalvalue = 1000;
    test_results.alg1.Value_data.coalitionstru = zeros(length(tasks), length(agents));
    test_results.alg1.Value_data.agentresources = zeros(length(agents), length(tasks), Value_Params.K);
    test_results.alg1.computation_time = 1.5;
    
    stats = compare_results(test_results, agents, tasks, Value_Params);
    fprintf('    ? compare_results 运行成功\n');
catch ME
    fprintf('    ? compare_results 失败: %s\n', ME.message);
end
fprintf('\n');

%% 7. 检查算法函数可调用性
fprintf('7. 检查算法函数句柄...\n');
algorithms = {
    'SA_Value_main'
    'Greedy_Baseline_main'
    'Huo2025_main'
};

for i = 1:length(algorithms)
    func_name = algorithms{i};
    try
        func_handle = str2func(func_name);
        fprintf('  ? @%s 可创建函数句柄\n', func_name);
    catch ME
        fprintf('  ? @%s 无法创建函数句柄: %s\n', func_name, ME.message);
    end
end
fprintf('\n');

%% 总结
fprintf('========================================\n');
fprintf('   验证总结\n');
fprintf('========================================\n\n');

if all_core_exist
    fprintf('? 路径配置正确!\n\n');
    fprintf('可以安全运行:\n');
    fprintf('  run Compare_Algorithms.m\n\n');
    fprintf('注意事项:\n');
    fprintf('  ? 确保所有算法的 enabled 设置正确\n');
    fprintf('  ? SA算法和Huo算法可能需要较长运行时间\n');
    fprintf('  ? 结果会自动保存到 results/ 文件夹\n\n');
else
    fprintf('?? 部分路径或文件有问题\n');
    fprintf('请检查上述输出中标记为 ? 或 ? 的项目\n\n');
end

fprintf('========================================\n\n');
