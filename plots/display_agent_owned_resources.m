function [agent_owned] = display_agent_owned_resources(agents, K, N)
% 显示表3：智能体-具备资源矩阵 (N×K)，并返回 agent_owned
% 输入：agents，K资源类型数，N智能体数
% 输出：agent_owned (N×K)

resNames = arrayfun(@(k) sprintf('Res%d', k), 1:K, 'UniformOutput', false);
agentNames = arrayfun(@(i) sprintf('A%d', i), 1:N, 'UniformOutput', false);

agent_owned = zeros(N, K);
for i = 1:N
    agent_owned(i, :) = agents(i).resources(:)';
end
fprintf('\n【表3：智能体-具备资源 (行=智能体, 列=资源类型)】\n');
disp(array2table(agent_owned, 'VariableNames', resNames, 'RowNames', agentNames));
end
