function [task_allocated] = display_task_allocated_resources(Value_data, K, M)
% 显示表2：任务-已分配资源矩阵 (M×K)，并返回 task_allocated
% 输入：Value_data（含SC资源分配cell），K资源类型数，M任务数
% 输出：task_allocated (M×K)

resNames = arrayfun(@(k) sprintf('Res%d', k), 1:K, 'UniformOutput', false);
taskNames = arrayfun(@(m) sprintf('T%d', m), 1:M, 'UniformOutput', false);

hasSC = isfield(Value_data(1), 'SC') && ~isempty(Value_data(1).SC);

task_allocated = zeros(M, K);
if hasSC
    for m = 1:M
        if m <= numel(Value_data(1).SC) && ~isempty(Value_data(1).SC{m})
            task_allocated(m, :) = sum(Value_data(1).SC{m}, 1);
        end
    end
end
fprintf('\n【表2：任务-已分配资源 (行=任务, 列=资源类型)】\n');
disp(array2table(task_allocated, 'VariableNames', resNames, 'RowNames', taskNames));
end
