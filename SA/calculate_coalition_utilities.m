function task_utilities = calculate_coalition_utilities(SC, agents, tasks, Value_Params, Value_data)
% CALCULATE_COALITION_UTILITIES - 计算每个任务的联盟总效用（基于实际需求和价值）
%
% 输入参数：
%   SC - 资源联盟结构（cell数组，长度M），SC{m}是N×K矩阵
%   agents - 智能体信息数组
%   tasks - 任务信息数组
%   Value_Params - 参数结构体
%   Value_data - 智能体数据结构（包含信念）- 本函数中未使用，为保持接口兼容性而保留
%
% 输出参数：
%   task_utilities - M×1向量，每个任务的联盟总效用（基于实际需求和价值）

M = Value_Params.M;
N = Value_Params.N;
task_utilities = zeros(M, 1);

% 对每个任务，计算所有参与智能体的效用总和
for m = 1:M
    % 找出参与该任务的智能体（从SC中判断）
    participating_agents = [];
    for i = 1:N
        if any(SC{m}(i, :) > 0)
            participating_agents = [participating_agents, i];
        end
    end
    
    % 如果没有智能体参与该任务，效用为0
    if isempty(participating_agents)
        task_utilities(m) = 0;
        continue;
    end
    
    % 累加该任务联盟中所有智能体的个体效用
    total_utility = 0;
    for i = participating_agents
        % 使用实际需求和价值计算个体效用（不使用信念）
        individual_utility = overlap_coalition_self_utility_actual(i, m, SC, agents, tasks, Value_Params);
        
        total_utility = total_utility + individual_utility;
    end
    
    task_utilities(m) = total_utility;
end

end
