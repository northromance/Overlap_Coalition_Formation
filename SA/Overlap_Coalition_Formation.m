function [incremental, Value_data] = Overlap_Coalition_Formation(agents, tasks, Value_data, Value_Params, resource_gap)
% Overlap_Coalition_Formation - single-agent coalition update (overlapping coalitions allowed)
%
% Inputs:
%   agents       - agent structs
%   tasks        - task structs
%   Value_data   - current agent state (coalitions, resources, etc.)
%   Value_Params - global params (N, M, K)
%   resource_gap - MxK matrix of per-task resource gaps
%
% Outputs:
%   incremental  - 1 if coalition structure changed, 0 otherwise
%   Value_data   - updated agent state

%% Backup current state
backup.coalition = Value_data.coalitionstru;
backup.iteration = Value_data.iteration;
backup.unif = Value_data.unif;
backup.SC = Value_data.SC;
backup.resources_matrix = Value_data.resources_matrix;

%% Task selection probabilities (K x M)
% 根据资源缺口 优先级 距离等计算 每个任务的选择概率 
probs = select_probs(Value_data, agents, tasks, Value_Params, resource_gap);
Value_data.selectProb = probs;

%% Coalition operations: try join, else leave
% 尝试加入任务 
[Value_data, incremental_join] = join_operation(Value_data, agents, tasks, Value_Params, probs);
if ~incremental_join
    [Value_data, ~] = leave_operation(Value_data, agents, tasks, Value_Params, probs);
end

%% Detect changes in SC
SC_changed = false;
for m = 1:Value_Params.M
    if ~isequal(backup.SC{m}, Value_data.SC{m})
        SC_changed = true;
        break;
    end
end

%% Apply or rollback
if SC_changed
    incremental = 1;
else
    incremental = 0;
    Value_data.coalitionstru = backup.coalition;
    Value_data.SC = backup.SC;
    Value_data.resources_matrix = backup.resources_matrix;
end

end
