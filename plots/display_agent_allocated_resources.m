function [agent_allocated] = display_agent_allocated_resources(Value_data, K, N, M)
% 显示表4：智能体-已分配资源矩阵 (N×K)，并返回 agent_allocated
% 输入：Value_data（含SC资源分配cell），K资源类型数，N智能体数，M任务数
% 输出：agent_allocated (N×K)

resNames = arrayfun(@(k) sprintf('Res%d', k), 1:K, 'UniformOutput', false);
agentNames = arrayfun(@(i) sprintf('A%d', i), 1:N, 'UniformOutput', false);

hasSC = isfield(Value_data(1), 'SC') && ~isempty(Value_data(1).SC);

agent_allocated = zeros(N, K);
if hasSC
    for m = 1:M
        if m <= numel(Value_data(1).SC) && ~isempty(Value_data(1).SC{m})
            agent_allocated = agent_allocated + Value_data(1).SC{m};
        end
    end
end
fprintf('\n【表4：智能体-已分配资源 (行=智能体, 列=资源类型)】\n');
disp(array2table(agent_allocated, 'VariableNames', resNames, 'RowNames', agentNames));
end
