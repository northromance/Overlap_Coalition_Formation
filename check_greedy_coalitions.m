%% 查看贪婪算法的联盟分配详情
try
    addpath('Main_fun', 'Com_Baseline');

    % 初始化场景
    [agents, tasks, Value_Params] = initialize_scenario(2437);
    AddPara = struct();

    % 运行贪婪算法
    [Value_data, ~] = Greedy_Baseline_main(agents, tasks, AddPara, Value_Params);

    fprintf('========================================\n');
    fprintf('  贪婪算法联盟分配详情\n');
    fprintf('========================================\n\n');

    coalitionstru = Value_data.coalitionstru;  % M×N矩阵

    fprintf('联盟结构矩阵 (任务×智能体):\n');
    fprintf('每行代表一个任务，1表示该智能体参与此任务\n\n');
    fprintf('    智能体:  1  2  3  4  5  6  | 成员数\n');
    fprintf('    ----------------------------------------\n');

    for j = 1:Value_Params.M
        fprintf('    任务%2d: ', j);
        members = find(coalitionstru(j, :) ~= 0);
        for i = 1:Value_Params.N
            fprintf(' %d ', coalitionstru(j, i));
        end
        fprintf(' |   %d', length(members));
        if isempty(members)
            fprintf('  (未分配)');
        end
        fprintf('\n');
    end

    fprintf('\n');
    fprintf('统计信息:\n');
    fprintf('  - 形成联盟的任务数: %d / %d\n', Value_data.num_coalitions, Value_Params.M);
    fprintf('  - 未分配的任务数: %d\n', Value_Params.M - Value_data.num_coalitions);
    fprintf('\n');

    fprintf('智能体参与情况:\n');
    for i = 1:Value_Params.N
        tasks_participated = find(coalitionstru(:, i) ~= 0);
        fprintf('  智能体%d 参与了 %d 个任务: [', i, length(tasks_participated));
        if ~isempty(tasks_participated)
            fprintf('%d', tasks_participated(1));
            for k = 2:length(tasks_participated)
                fprintf(', %d', tasks_participated(k));
            end
        end
        fprintf(']\n');
    end

    fprintf('\n');
    fprintf('关键发现:\n');
    fprintf('  因为贪婪算法当前是互斥资源分配（资源不可复用）\n');
    fprintf('  所以每个智能体只能参与少数任务\n');
    fprintf('  这与重叠联盟模型的设计初衷不符\n');

    fprintf('\n========================================\n');
    
catch ME
    fprintf('错误: %s\n', ME.message);
    fprintf('位置: %s (第%d行)\n', ME.stack(1).name, ME.stack(1).line);
end
