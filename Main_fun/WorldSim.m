classdef WorldSim

    methods (Static)
        function t_exec = calc_exec_time(task, R_row, Value_Params, tol)
            if ~isempty(R_row)
                used = R_row > tol;
            else
                used = true(1, Value_Params.K);
            end

            if isfield(task, 'duration_by_resource')
                dur = task.duration_by_resource(:)';
                if isscalar(dur)
                    t_exec = dur;
                else
                    dur = dur(1:min(numel(dur), Value_Params.K));
                    used = used(1:numel(dur));
                    t_exec = max([dur(used), 0]);
                end
            elseif isfield(task, 'duration')
                t_exec = task.duration;
            else
                t_exec = 1.0;
            end
        end

        function t_exec = calc_coalition_exec_time(SC, task_idx, task, Value_Params, tol)
            alloc = SC{task_idx};
            exec_times = [];

            for i = 1:Value_Params.N
                if any(alloc(i, :) > tol)
                    exec_times = [exec_times, WorldSim.calc_exec_time(task, alloc(i, :), Value_Params, tol)]; %#ok<AGROW>
                end
            end

            t_exec = max([exec_times, 0]);
        end


        function D_C = calc_task_completion_degree(allocated_resources, task_demand, K)
            if size(allocated_resources, 1) > 1
                allocated = sum(allocated_resources, 1);
            else
                allocated = allocated_resources;
            end

            if numel(allocated) < K
                allocated = [allocated, zeros(1, K - numel(allocated))];
            end
            if numel(task_demand) < K
                task_demand = [task_demand, zeros(1, K - numel(task_demand))];
            end

            Z_c = nnz(task_demand > 1e-9);
            if Z_c == 0
                D_C = 1; return;
            end

            D_C = 0;
            for k = 1:K
                if task_demand(k) > 1e-9
                    ratio = min(allocated(k) / task_demand(k), 1.0);
                    D_C = D_C + ratio;
                end
            end

            D_C = D_C / Z_c;
        end


        function [t_fly_total, t_wait_total, t_exec_total, start_times, execution_times, completion_times,mission_end_time] = calc_with_global_sync(...
                agentIdx, myOrderedTasks, agents, tasks, Value_Params, SC, tol)
            N = Value_Params.N;
            M = Value_Params.M;
            R_agent = OCFUtils.get_agent_resource_matrix(SC, agentIdx, Value_Params);

            agent_state = struct('pos', {}, 'ready_time', {});
            for i = 1:N
                agent_state(i).pos = [agents(i).x, agents(i).y];
                agent_state(i).ready_time = 0;
            end

            all_tasks = 1:M;
            global_order = OCFUtils.sort_tasks_by_priority(all_tasks, tasks);

            task_sync_start = zeros(M, 1);
            task_coalition_dur = zeros(M, 1);

            for order_idx = 1:M
                task_id = global_order(order_idx);
                task_pos = [tasks(task_id).x, tasks(task_id).y];

                participants = OCFUtils.get_participants(SC, task_id, tol);
                if isempty(participants), continue; end

                arrival_times = zeros(numel(participants), 1);
                for k = 1:numel(participants)
                    p_id = participants(k);
                    v = agents(p_id).vel;

                    dist = norm(task_pos - agent_state(p_id).pos);
                    fly_time = dist / max(v, tol);

                    arrival_times(k) = agent_state(p_id).ready_time + fly_time;
                end

                sync_start = max(arrival_times);
                task_sync_start(task_id) = sync_start;

                t_coalition = WorldSim.calc_coalition_exec_time(SC, task_id, tasks(task_id), Value_Params, tol);
                task_coalition_dur(task_id) = t_coalition;

                for k = 1:numel(participants)
                    p_id = participants(k);
                    agent_state(p_id).pos = task_pos;
                    agent_state(p_id).ready_time = sync_start + t_coalition;
                end
            end

            t_fly_total = 0;
            t_wait_total = 0;
            t_exec_total = 0;

            num_my_tasks = numel(myOrderedTasks);
            start_times = zeros(num_my_tasks, 1);
            execution_times = zeros(num_my_tasks, 1);
            completion_times = zeros(num_my_tasks, 1);

            curr_pos = [agents(agentIdx).x, agents(agentIdx).y];
            curr_clock = 0;
            v = agents(agentIdx).vel;

            for ii = 1:num_my_tasks
                task_id = myOrderedTasks(ii);
                task_pos = [tasks(task_id).x, tasks(task_id).y];

                dist = norm(task_pos - curr_pos);
                fly_time = dist / max(v, tol);
                t_fly_total = t_fly_total + fly_time;

                my_arrival = curr_clock + fly_time;

                sync_start = task_sync_start(task_id);
                coalition_dur = task_coalition_dur(task_id);

                wait_pre_start = max(0, sync_start - my_arrival);

                if ~isempty(SC) && task_id <= numel(SC) && ~isempty(SC{task_id})
                    R_row = SC{task_id}(agentIdx, :);
                else
                    R_row = R_agent(task_id, :);
                end
                my_exec_time = WorldSim.calc_exec_time(tasks(task_id), R_row, Value_Params, tol);
                t_exec_total = t_exec_total + my_exec_time;

                wait_post_exec = max(0, coalition_dur - my_exec_time);

                t_wait_total = t_wait_total + wait_pre_start + wait_post_exec;

                curr_clock = sync_start + coalition_dur;
                curr_pos = task_pos;

                start_times(ii) = sync_start;
                execution_times(ii) = my_exec_time;
                completion_times(ii) = curr_clock;
            end

            return_dist = norm([agents(agentIdx).x, agents(agentIdx).y] - curr_pos);
            return_time = return_dist / max(v, tol);

            t_fly_total = t_fly_total + return_time;

            mission_end_time = curr_clock + return_time;
        end


        function demand = calculate_demand_quantile(belief, task_type_demands, confidence)
            if nargin < 3
                error('calculate_demand_quantile:NotEnoughInputs', 'Need: belief, task_type_demands, confidence');
            end

            [num_types, K] = size(task_type_demands);

            belief = belief(:).';

            demand = zeros(1, K);

            if max(belief) >= confidence
                [~, most_likely_type] = max(belief);
                demand = ceil(task_type_demands(most_likely_type, :));
                return;
            end

            for r = 1:K
                demands_r = task_type_demands(:, r);

                [sorted_demands, idx] = sort(demands_r);

                sorted_belief = belief(idx);

                cumulative_prob = cumsum(sorted_belief);

                threshold_idx = find(cumulative_prob >= confidence, 1);

                if isempty(threshold_idx)
                    threshold_idx = num_types;
                end

                demand(r) = sorted_demands(threshold_idx);
            end

            demand = ceil(demand);
        end


        function Value_data = init_value_data(agents, tasks, Value_Params)
            N = Value_Params.N;
            M = Value_Params.M;
            K = Value_Params.K;

            for i = 1:N
                Value_data(i).agentID = agents(i).id;
                Value_data(i).agentIndex = i;
                Value_data(i).iteration = 0;
                Value_data(i).unif = 0;
                Value_data(i).coalitionstru = zeros(M+1, N);
                Value_data(i).initbelief = zeros(M+1, Value_Params.task_type);
                Value_data(i).cost_data = [];

                Value_data(i).resources_matrix = zeros(M, K);

                Value_data(i).SC = cell(M, 1);
                for m = 1:M
                    Value_data(i).SC{m} = zeros(N, K);
                end

                Value_data(i).other = cell(N, 1);

                Value_data(i).task_schedule = struct();
                Value_data(i).task_schedule.task_sequence = [];
                Value_data(i).task_schedule.arrival_times = [];
                Value_data(i).task_schedule.start_times = [];
                Value_data(i).task_schedule.mission_end_time = [];
                Value_data(i).task_schedule.execution_times = [];
                Value_data(i).task_schedule.completion_times = [];
                Value_data(i).task_schedule.total_flight_time = 0;
                Value_data(i).task_schedule.total_execution_time = 0;
                Value_data(i).task_schedule.total_energy = 0;
                Value_data(i).selectProb = zeros(K, M);

                Value_data(i).observe = zeros(M, Value_Params.task_type);
                Value_data(i).preobserve = zeros(M, Value_Params.task_type);

                Value_data(i).resources = agents(i).resources;
            end

            for k = 1:N
                for j = 1:M+1
                    if j == M+1
                        for i = 1:N
                            Value_data(k).coalitionstru(j, i) = agents(i).id;
                        end
                    end
                end
            end

            for i = 1:N
                for j = 1:M
                    Value_data(i).initbelief(j, 1:end) = ones(Value_Params.task_type, 1) / Value_Params.task_type;
                end
            end

            for i = 1:N
                for j = 1:N
                    Value_data(i).other{j}.initbelief = Value_data(j).initbelief;
                end
            end
        end


        function [Value_data, summatrix] = init_observe_belief_neighbor(Value_data, N, M, Value_Params)
            T = Value_Params.task_type;

            for i = 1:N
                Value_data(i).observe    = zeros(M, T);
                Value_data(i).preobserve = zeros(M, T);
            end

            summatrix = zeros(M, T);

            uniform_prior_row = ones(1, T) / T;
            for i = 1:N
                Value_data(i).initbelief(1:M, :) = repmat(uniform_prior_row, M, 1);
            end

            for i = 1:N
                for j = 1:N
                    Value_data(i).other{j}.initbelief = Value_data(j).initbelief;
                end
            end
        end


    end

end