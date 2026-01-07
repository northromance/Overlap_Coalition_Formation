function display_belief_evolution(history_data, tasks, WORLD, N, M, num_task_types, num_rounds)
% 显示智能体信念演化和观测统计
% 输入：
%   history_data - 历史数据
%   tasks - 任务数组
%   WORLD - 世界参数（包含value）
%   N - 智能体数量
%   M - 任务数量
%   num_task_types - 任务类型数量
%   num_rounds - 游戏轮数

fprintf('\n========================================\n');
fprintf('     智能体信念演化和观测统计\n');
fprintf('========================================\n\n');

% 为每个智能体显示信念演化
for i = 1:N
    fprintf('\n【智能体 A%d 的信念演化】\n', i);
    fprintf('----------------------------------------\n');
    
    % 为每个任务显示信念和观测的演化
    for j = 1:M
        fprintf('\n任务 T%d (真实价值=%d):\n', j, tasks(j).value);
        
        % 打印表头
        fprintf('  轮次 | ');
        for v_idx = 1:num_task_types
            fprintf('信念[%d] | ', WORLD.value(v_idx));
        end
        fprintf('期望价值 | ');
        for v_idx = 1:num_task_types
            fprintf('观测[%d] | ', WORLD.value(v_idx));
        end
        fprintf('总观测\n');
        
        fprintf('  -----|');
        for v_idx = 1:num_task_types
            fprintf('--------|');
        end
        fprintf('---------|');
        for v_idx = 1:num_task_types
            fprintf('--------|');
        end
        fprintf('------\n');
        
        % 打印每轮的数据
        for round = 1:num_rounds
            belief = history_data.rounds(round).agents(i).belief(j, :);
            obs = history_data.rounds(round).agents(i).observations(j, :);
            
            % 计算期望价值
            expected_value = sum(belief .* WORLD.value);
            
            fprintf('  %4d | ', round);
            for v_idx = 1:num_task_types
                fprintf(' %6.3f | ', belief(v_idx));
            end
            fprintf(' %7.1f | ', expected_value);
            for v_idx = 1:num_task_types
                fprintf('  %5d | ', obs(v_idx));
            end
            fprintf('%5d\n', sum(obs));
        end
        
        % 显示最终信念统计
        final_belief = history_data.rounds(num_rounds).agents(i).belief(j, :);
        final_expected = sum(final_belief .* WORLD.value);
        fprintf('  ----\n');
        fprintf('  最终期望价值: %.1f (真实值: %d, 偏差: %.1f)\n', ...
                final_expected, tasks(j).value, final_expected - tasks(j).value);
    end
    fprintf('\n');
end

fprintf('========================================\n\n');
end
