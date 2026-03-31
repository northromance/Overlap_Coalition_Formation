function [allocated_resources, resource_gap] = calc_gaps(Value_data, Value_Params, AddPara)
    N = Value_Params.N;
    M = Value_Params.M;
    K = Value_Params.K;

    allocated_resources = zeros(N, K);
    resource_gap = zeros(M, K);

    SC = Value_data.SC;

    for i = 1:N
        for r = 1:K
            for m = 1:M
                allocated_resources(i, r) = allocated_resources(i, r) + SC{m}(i, r);
            end
        end
    end

    task_type_demands = Value_Params.task_type_demands;
    num_types = Value_Params.task_type;
    [demand_mode, demand_rounding_mode] = WorldSim.get_demand_estimation_settings(AddPara, Value_Params);

    for j = 1:M
        belief_j = Value_data.initbelief(j, :);
        belief_j = belief_j(:).';

        expected_demand_vec = WorldSim.estimate_demand_from_belief( ...
            belief_j(1:num_types), ...
            task_type_demands, ...
            demand_mode, ...
            Value_Params.resource_confidence, ...
            demand_rounding_mode);

        for r = 1:K
            task_allocated = sum(SC{j}(:, r));
            resource_gap(j, r) = expected_demand_vec(r) - task_allocated;
        end
    end
end
