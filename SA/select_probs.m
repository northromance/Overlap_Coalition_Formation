function probs = select_probs(Value_data, agents, tasks, Value_Params, resource_gap)
% Compute per-resource task selection probabilities for the current agent.
agentID = Value_data.agentID;

% Init probability matrix (K x M)
probs = zeros(Value_Params.K, Value_Params.M);

% Normalizers (avoid divide-by-zero)
max_priority = max([tasks.priority]);
if max_priority <= 0
    max_priority = 1;
end

max_remaining_demand = max(resource_gap(:));
if max_remaining_demand <= 0
    max_remaining_demand = 1;
end

max_agent_resource = max(Value_data.resources);
if max_agent_resource <= 0
    max_agent_resource = 1;
end

max_distance = max(arrayfun(@(task) sqrt((task.x - agents(agentID).x)^2 + (task.y - agents(agentID).y)^2), tasks));
if max_distance <= 0
    max_distance = 1;
end

% Iterate each resource type
for r = 1:Value_Params.K
    for j = 1:Value_Params.M
        % Remaining demand for task j on resource r
        remaining_demand = 0;
        if ~isempty(resource_gap)
            remaining_demand = max(resource_gap(j, r), 0);
        end
        remaining_demand_norm = remaining_demand / max_remaining_demand;

        % Available resource from current agent
        agent_resource_available = Value_data.resources(r);
        agent_resource_available_norm = agent_resource_available / max_agent_resource;

        % Distance to task j
        task_distance = sqrt((tasks(j).x - agents(agentID).x)^2 + ...
            (tasks(j).y - agents(agentID).y)^2);
        if task_distance <= 0
            task_distance = eps;
        end
        task_distance_norm = max(task_distance / max_distance, eps);

        % Normalized priority (larger = higher priority)
        priority_norm = tasks(j).priority / max_priority;

        % Weight
        task_probability = (priority_norm)^2 * remaining_demand_norm * agent_resource_available_norm / task_distance_norm;
        probs(r, j) = task_probability;
    end

    % Normalize row
    total_prob = sum(probs(r, :));
    if total_prob > 0
        probs(r, :) = probs(r, :) / total_prob;
    end
end
end
