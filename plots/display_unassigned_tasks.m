function [unassigned_tasks] = display_unassigned_tasks(coal, M)
% 显示表6：未执行任务列表，并返回未分配任务ID数组
% 输入：coal (M×N)，M任务数
% 输出：unassigned_tasks (1×p)

unassigned_tasks = [];
for m = 1:M
    if sum(coal(m, :)) == 0
        unassigned_tasks = [unassigned_tasks, m];
    end
end
fprintf('\n【表6：未执行任务列表】\n');
if isempty(unassigned_tasks)
    fprintf('所有任务均已分配智能体执行。\n');
else
    fprintf('以下任务未分配智能体：');
    fprintf(' T%d', unassigned_tasks);
    fprintf('\n共 %d 个任务未执行。\n', length(unassigned_tasks));
end
end
