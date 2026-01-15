% 简化的Huo2025测试脚本
clear; clc;

% 添加所有必需路径
addpath('Main_fun');
addpath('Com_Huo2025');
addpath('SA');

fprintf('测试Huo2025算法...\n\n');

% 初始化场景
SEED = 2437;
fprintf('初始化场景 (SEED=%d)...\n', SEED);
[agents, tasks, Value_Params, WORLD, ~] = initialize_scenario(SEED);
fprintf('完成! N=%d, M=%d\n\n', length(agents), length(tasks));

% 运行算法
fprintf('运行Huo2025算法...\n');
AddPara.control = 1;
tic;
[Value_data, history_data] = Huo2025_main(agents, tasks, AddPara, Value_Params);
elapsed = toc;

fprintf('完成! 耗时: %.2f秒\n\n', elapsed);

% 显示结果
fprintf('结果:\n');
fprintf('  总效用: %.2f\n', Value_data.totalvalue);
fprintf('  联盟结构大小: %dx%d\n', size(Value_data.coalitionstru));

fprintf('\n? 测试通过!\n');
