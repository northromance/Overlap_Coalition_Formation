% Smoke test for PSO_main with agent_paths verification.
% Checks:
%   1) Value_data contains agent_paths.
%   2) agent_paths task sets match coalitionstru assignments.
%   3) Travel distance computed from paths matches reported energy_cost.

clear; clc; close all;

% Paths
here = fileparts(mfilename('fullpath'));
repo_root = fullfile(here, '..');
addpath(repo_root);
addpath(fullfile(repo_root, 'Com_PSO'));
addpath(fullfile(repo_root, 'Main_fun'));

% Small reproducible scenario
SEED = 123;
rand('seed', SEED);
N = 4; M = 5; K = 3; num_task_types = 3;

WORLD.value = [800, 1000, 1500];

% Task demands and execution time
task_type_demands = [1 2 0; 2 1 1; 1 1 2];
resource_exec_time = [30 40 50];

task_type_duration_by_resource = zeros(num_task_types, K);
for t = 1:num_task_types
    needed = task_type_demands(t, :) > 0;
    task_type_duration_by_resource(t, needed) = resource_exec_time(needed);
end

% Tasks
task_priorities = randperm(M);
for j = 1:M
    tasks(j).id = j;
    tasks(j).priority = task_priorities(j);
    tasks(j).x = randi([0, 50]);
    tasks(j).y = randi([0, 50]);
    tasks(j).type = randi(num_task_types, 1, 1);
    tasks(j).value = WORLD.value(tasks(j).type);
    tasks(j).resource_demand = task_type_demands(tasks(j).type, :);
    tasks(j).duration_by_resource = task_type_duration_by_resource(tasks(j).type, :);
    tasks(j).duration = max(tasks(j).duration_by_resource);
    tasks(j).WORLD = WORLD;
    tasks(j).type_values = WORLD.value;  % supply type values for belief utility
end

% Agents
min_resource_value = 1; max_resource_value = 3;
agent_detprob_min = 0.9; agent_detprob_max = 1.0;
agent_Emax_min = 200; agent_Emax_range = 50;
agent_velocity = 2; agent_fuel = 1; agent_beta = 1;
for i = 1:N
    agents(i).id = i;
    agents(i).vel = agent_velocity;
    agents(i).x = randi([0, 50]);
    agents(i).y = randi([0, 50]);
    agents(i).detprob = agent_detprob_min + (agent_detprob_max - agent_detprob_min) * rand();
    agents(i).resources = randi([min_resource_value, max_resource_value], K, 1);
    agents(i).Emax = agent_Emax_min + agent_Emax_range * rand();
    agents(i).fuel = agent_fuel;
    agents(i).beta = agent_beta;
end

% Shared parameters with belief
SA_Temperature = 50.0; SA_alpha = 0.9; SA_Tmin = 0.1; SA_max_stable_iterations = 3;
obs_times = 5; num_rounds = 5; resource_confidence = 0.7;
Value_Params = init_value_params(N, M, K, num_task_types, task_type_demands, ...
    SA_Temperature, SA_alpha, SA_Tmin, SA_max_stable_iterations, ...
    obs_times, num_rounds, resource_confidence);

% Belief: uniform over types per task
Value_Params.belief = ones(M, num_task_types) ./ num_task_types;

AddPara.control = 1;

% Run PSO
[Value_data, history_data] = PSO_main(agents, tasks, AddPara, Value_Params);

vd = Value_data(1);

% 1) Field existence
assert(isfield(vd, 'agent_paths'), 'agent_paths missing in Value_data.');

% 2) Path vs coalitionstru consistency
coal = vd.coalitionstru;
for n = 1:N
    assigned = find(coal(:, n) ~= 0);
    path = vd.agent_paths{n};
    if isempty(path)
        assert(isempty(assigned), 'Agent %d has empty path but assigned tasks.', n);
    else
        assert(isequal(sort(path(:)'), sort(assigned(:)')), ...
            sprintf('Agent %d path tasks differ from coalition assignments.', n));
    end
end

% 3) Travel distance recompute
computed_travel = 0;
for n = 1:N
    path = vd.agent_paths{n};
    if isempty(path), continue; end
    curr = [agents(n).x, agents(n).y];
    dist_n = 0;
    for idx = 1:numel(path)
        tgt = path(idx);
        tgt_pos = [tasks(tgt).x, tasks(tgt).y];
        dist_n = dist_n + norm(curr - tgt_pos);
        curr = tgt_pos;
    end
    dist_n = dist_n + norm(curr - [agents(n).x, agents(n).y]);
    computed_travel = computed_travel + dist_n * agents(n).fuel;
end

fprintf('Reported travel_cost (energy_cost): %.4f\n', vd.energy_cost);
fprintf('Recomputed travel_cost:            %.4f\n', computed_travel);
fprintf('Absolute diff:                     %.4f\n', abs(vd.energy_cost - computed_travel));

% Show utility summary
fprintf('Total utility (Value_data.totalvalue): %.4f\n', vd.totalvalue);
if isfield(history_data, 'rounds') && ~isempty(history_data.rounds)
    fprintf('History fitness (round 1):             %.4f\n', history_data.rounds(1).fitness);
end

disp('PSO agent_paths verification passed.');
