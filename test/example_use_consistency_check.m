% EXAMPLE_USE_CONSISTENCY_CHECK 示例：如何在算法主文件中使用一致性检查
%
% 功能：
%   展示如何在算法主文件（如Qi2023_main.m, Shi2024_main.m）的末尾
%   添加联盟一致性检查，以验证算法输出的正确性
%
% 使用场景：
%   1. 在算法主函数的最后，返回结果之前调用检查函数
%   2. 根据算法类型选择合适的检查模式（OCF或Non-OCF）
%   3. 如果检查失败，可以选择抛出错误或仅显示警告

%% ========== 示例1：在OCF算法中使用（如Shi2024, Qi2023）==========
%
% 在 Shi2024_main.m 或 Qi2023_main.m 的末尾添加以下代码：
%
% function [Value_data, history_data] = Shi2024_main(agents, tasks, AddPara, Value_Params)
%     ... 算法主体代码 ...
%
%     %% 最终一致性检查
%     fprintf('\n========== 最终一致性检查 ==========\n');
%     [is_valid, error_log] = check_coalition_consistency(...
%         Value_data, agents, tasks, Value_Params, 'OCF');
%
%     if ~is_valid
%         warning('算法输出存在一致性问题，请检查error_log');
%         % 可选：将错误日志保存到history_data中
%         history_data.consistency_errors = error_log;
%
%         % 可选：如果检查失败，抛出错误（严格模式）
%         % error('联盟一致性检查失败！');
%     end
%
%     return;
% end

%% ========== 示例2：在Non-OCF算法中使用 ==========
%
% 在非重叠联盟算法的主文件末尾添加以下代码：
%
% function [Value_data, history_data] = NonOCF_Algorithm_main(agents, tasks, AddPara, Value_Params)
%     ... 算法主体代码 ...
%
%     %% 最终一致性检查
%     fprintf('\n========== 最终一致性检查 ==========\n');
%     [is_valid, error_log] = check_coalition_consistency(...
%         Value_data, agents, tasks, Value_Params, 'Non-OCF');
%
%     if ~is_valid
%         warning('算法输出存在一致性问题，请检查error_log');
%         history_data.consistency_errors = error_log;
%     end
%
%     return;
% end

%% ========== 示例3：根据参数动态选择检查模式 ==========
%
% 如果算法支持多种模式，可以根据参数动态选择：
%
% function [Value_data, history_data] = Flexible_Algorithm_main(agents, tasks, AddPara, Value_Params)
%     ... 算法主体代码 ...
%
%     %% 确定算法类型
%     if isfield(AddPara, 'allow_overlap') && AddPara.allow_overlap
%         algorithm_type = 'OCF';
%     else
%         algorithm_type = 'Non-OCF';
%     end
%
%     %% 最终一致性检查
%     fprintf('\n========== 最终一致性检查 [%s模式] ==========\n', algorithm_type);
%     [is_valid, error_log] = check_coalition_consistency(...
%         Value_data, agents, tasks, Value_Params, algorithm_type);
%
%     if ~is_valid
%         warning('算法输出存在一致性问题');
%         history_data.consistency_errors = error_log;
%     else
%         fprintf('✅ 算法输出通过所有一致性检查\n');
%     end
%
%     return;
% end

%% ========== 示例4：在调试模式下使用 ==========
%
% 可以添加一个调试开关，只在需要时进行检查：
%
% function [Value_data, history_data] = Algorithm_main(agents, tasks, AddPara, Value_Params)
%     ... 算法主体代码 ...
%
%     %% 可选的一致性检查（仅在调试模式下）
%     if isfield(Value_Params, 'debug_mode') && Value_Params.debug_mode
%         fprintf('\n========== [调试模式] 一致性检查 ==========\n');
%         [is_valid, error_log] = check_coalition_consistency(...
%             Value_data, agents, tasks, Value_Params, 'OCF');
%
%         if ~is_valid
%             fprintf('⚠️  发现 %d 处一致性问题\n', length(error_log));
%             % 在调试模式下，可以暂停执行以便检查
%             keyboard;  % 进入调试模式
%         end
%     end
%
%     return;
% end

%% ========== 示例5：批量测试多个算法 ==========
%
% 创建一个测试脚本，对多个算法进行一致性检查：

clear; clc;

% 初始化测试环境
fprintf('========== 批量算法一致性测试 ==========\n\n');

% 加载测试数据
load('test_scenario.mat', 'agents', 'tasks', 'Value_Params');

% 定义要测试的算法列表
algorithms = {
    'Qi2023_main',   'OCF';
    'Shi2024_main',  'OCF';
    % 'Other_Algorithm', 'Non-OCF';  % 添加其他算法
};

% 测试每个算法
results = struct();
for i = 1:size(algorithms, 1)
    algo_name = algorithms{i, 1};
    algo_type = algorithms{i, 2};

    fprintf('\n【测试算法 %d/%d】%s (%s模式)\n', i, size(algorithms, 1), algo_name, algo_type);
    fprintf('----------------------------------------------\n');

    try
        % 运行算法
        AddPara = struct();
        algo_func = str2func(algo_name);
        [Value_data, ~] = algo_func(agents, tasks, AddPara, Value_Params);

        % 执行一致性检查
        [is_valid, error_log] = check_coalition_consistency(...
            Value_data, agents, tasks, Value_Params, algo_type);

        % 记录结果
        results.(algo_name).is_valid = is_valid;
        results.(algo_name).error_count = length(error_log);
        results.(algo_name).errors = error_log;

        if is_valid
            fprintf('✅ %s 通过一致性检查\n', algo_name);
        else
            fprintf('❌ %s 未通过一致性检查（%d个错误）\n', algo_name, length(error_log));
        end

    catch ME
        fprintf('❌ %s 运行失败: %s\n', algo_name, ME.message);
        results.(algo_name).is_valid = false;
        results.(algo_name).error_count = -1;
        results.(algo_name).errors = {ME.message};
    end
end

% 输出总结
fprintf('\n========== 测试总结 ==========\n');
algo_names = fieldnames(results);
pass_count = 0;
for i = 1:length(algo_names)
    if results.(algo_names{i}).is_valid
        pass_count = pass_count + 1;
    end
end
fprintf('通过率: %d/%d (%.1f%%)\n', pass_count, length(algo_names), ...
    100 * pass_count / length(algo_names));

%% ========== 使用建议 ==========
%
% 1. 开发阶段：
%    - 在算法主文件末尾添加一致性检查
%    - 设置为严格模式（检查失败时抛出错误）
%    - 这样可以及时发现算法实现中的问题
%
% 2. 测试阶段：
%    - 使用批量测试脚本验证多个算法
%    - 对比不同算法的一致性表现
%    - 记录错误日志用于分析
%
% 3. 生产阶段：
%    - 可以将检查设置为警告模式（不中断执行）
%    - 或者完全关闭检查以提高性能
%    - 保留检查代码以便需要时重新启用
%
% 4. 调试技巧：
%    - 如果检查失败，查看error_log了解具体问题
%    - 使用keyboard命令在检查失败时暂停执行
%    - 检查Value_data中的SC和coalitionstru是否正确同步
%    - 验证资源分配是否满足约束条件
%    - 确认能量计算是否正确

fprintf('\n示例代码已准备就绪，请参考上述示例在算法主文件中添加检查代码。\n');
