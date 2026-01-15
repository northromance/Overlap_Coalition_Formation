clear; clc; close all;

% Add required paths (relative to repo root)
here = fileparts(mfilename('fullpath'));
repo_root = fullfile(here, '..');
addpath(repo_root);
addpath(fullfile(repo_root, 'Com_Qin2025'));
addpath(fullfile(repo_root, 'SA'));
addpath(fullfile(repo_root, 'Main_fun'));

% Basic reproducible scenario
SEED = 2437;
rand('seed', SEED);

N = 4;                     % agents
M = 5;                     % tasks
K = 3;                     % resource types
num_task_types = 3;

% Resource demand ranges for three task types
task_type_demands = zeros(num_task_types, K);
task_type_demands(1, :) = randi([0, 2], 1, K);
task_type_demands(2, :) = randi([1, 3], 1, K);
task_type_demands(3, :) = randi([2, 3], 1, K);

% Resource execution times
resource_exec_time = [30, 40, 50];

% Compute per-type duration by resource
task_type_duration_by_resource = zeros(num_task_types, K);
for t = 1:num_task_types
    needed = task_type_demands(t, :) > 0;
    task_type_duration_by_resource(t, needed) = resource_exec_time(needed);
end

% Initialize tasks
task_priorities = randperm(M);
WORLD.XMIN = 0; WORLD.XMAX = 50;
WORLD.YMIN = 0; WORLD.YMAX = 50;
WORLD.ZMIN = 0; WORLD.ZMAX = 0;
WORLD.value = [800, 1000, 1500];
for j = 1:M
    tasks(j).id = j;
    tasks(j).priority = task_priorities(j);
    tasks(j).x = round(rand(1) * (WORLD.XMAX - WORLD.XMIN) + WORLD.XMIN);
    tasks(j).y = round(rand(1) * (WORLD.YMAX - WORLD.YMIN) + WORLD.YMIN);
    tasks(j).type = randi(num_task_types, 1, 1);
    tasks(j).value = WORLD.value(tasks(j).type);
    tasks(j).resource_demand = task_type_demands(tasks(j).type, :);
    tasks(j).duration_by_resource = task_type_duration_by_resource(tasks(j).type, :);
    tasks(j).duration = max(tasks(j).duration_by_resource);
    tasks(j).WORLD = WORLD;
end

% Initialize agents
min_resource_value = 1; max_resource_value = 3;
agent_detprob_min = 0.9; agent_detprob_max = 1.0;
agent_Emax_min = 200; agent_Emax_range = 50;
agent_velocity = 2; agent_fuel = 1; agent_beta = 1;
for i = 1:N
    agents(i).id = i;
    agents(i).vel = agent_velocity;
    agents(i).x = round(rand(1) * (WORLD.XMAX - WORLD.XMIN) + WORLD.XMIN);
    agents(i).y = round(rand(1) * (WORLD.YMAX - WORLD.YMIN) + WORLD.YMIN);
    agents(i).detprob = agent_detprob_min + (agent_detprob_max - agent_detprob_min) * rand();
    agents(i).resources = randi([min_resource_value, max_resource_value], K, 1);
    agents(i).Emax = agent_Emax_min + agent_Emax_range * rand();
    agents(i).fuel = agent_fuel;
    agents(i).beta = agent_beta;
end

% Shared algorithm parameters
SA_Temperature = 50.0;
SA_alpha = 0.9;
SA_Tmin = 0.1;
SA_max_stable_iterations = 3;
obs_times = 5;
num_rounds = 10;
resource_confidence = 0.7;

Value_Params = init_value_params(N, M, K, num_task_types, task_type_demands, ...
                                 SA_Temperature, SA_alpha, SA_Tmin, SA_max_stable_iterations, ...
                                 obs_times, num_rounds, resource_confidence);
AddPara.control = 1;

% Sanity check on function availability
assert(exist('Qin2025_main', 'file') == 2, 'Qin2025_main is not on the MATLAB path.');

[Value_data, history_data] = Qin2025_main(agents, tasks, AddPara, Value_Params);

% Basic structural assertions to ensure the pipeline runs
assert(~isempty(Value_data), 'Qin2025_main returned empty Value_data.');
assert(isfield(Value_data(1), 'coalitionstru'), 'Value_data missing coalitionstru field.');

fprintf('Qin2025_main smoke test OK: coalitions matrix %dx%d, rounds=%d\n', ...
        size(Value_data(1).coalitionstru, 1), size(Value_data(1).coalitionstru, 2), num_rounds);
