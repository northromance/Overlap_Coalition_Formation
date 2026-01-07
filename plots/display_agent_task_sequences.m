function [agent_task_seq, num_tasks] = display_agent_task_sequences(coal, N, M)
% 显示表5：智能体-任务序列，并返回 agent_task_seq 与 num_tasks
% 输入：coal (M×N)，N智能体数，M任务数
% 输出：agent_task_seq (N×M, NaN填充), num_tasks (N×1)

agentNames = arrayfun(@(i) sprintf('A%d', i), 1:N, 'UniformOutput', false);
seqVarNames = arrayfun(@(t) sprintf('Seq%d', t), 1:M, 'UniformOutput', false);

agent_task_seq = nan(N, M);
num_tasks = zeros(N, 1);
for i = 1:N
    assigned_tasks = find(coal(:, i)' ~= 0);
    num_tasks(i) = numel(assigned_tasks);
    if ~isempty(assigned_tasks)
        agent_task_seq(i, 1:numel(assigned_tasks)) = assigned_tasks;
    end
end
T_seq = array2table(agent_task_seq, 'VariableNames', seqVarNames, 'RowNames', agentNames);
T_seq.NumTasks = num_tasks;
T_seq = movevars(T_seq, 'NumTasks', 'Before', 1);
fprintf('\n【表5：智能体-任务序列 (行=智能体, 列=第n个参与任务；NumTasks=任务数)】\n');
disp(T_seq);
end
