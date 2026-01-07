function [task_demand] = display_task_resource_demand(tasks, K, M)
% 显示表1：任务-资源需求矩阵 (M×K)，并返回 task_demand
% 输入：tasks, K资源类型数, M任务数
% 输出：task_demand (M×K)

resNames = arrayfun(@(k) sprintf('Res%d', k), 1:K, 'UniformOutput', false);
taskNames = arrayfun(@(m) sprintf('T%d', m), 1:M, 'UniformOutput', false);

task_demand = zeros(M, K);
for m = 1:M
    if isfield(tasks(m), 'resource_demand') && ~isempty(tasks(m).resource_demand)
        task_demand(m, :) = tasks(m).resource_demand(:)';
    end
end
fprintf('【表1：任务-资源需求 (行=任务, 列=资源类型)】\n');
disp(array2table(task_demand, 'VariableNames', resNames, 'RowNames', taskNames));
end
