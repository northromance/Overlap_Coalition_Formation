function snapshot = build_exp_params_snapshot(context)
%BUILD_EXP_PARAMS_SNAPSHOT Build a structured parameter snapshot for result files.
%
% Input:
%   context - struct with optional fields:
%       exp_params_source
%       experiment_script
%       experiment_name
%       common_config
%       scenario_cfg_base
%       experiment_cfg
%       common_params
%       algorithm_params
%       effective_run
%
% Output:
%   snapshot - struct with fields:
%       source
%       config_snapshot
%       effective_run

if nargin < 1 || ~isstruct(context)
    error('build_exp_params_snapshot:InvalidInput', ...
        'context must be a struct.');
end

snapshot = struct();

snapshot.source = struct();
snapshot.source.exp_params_source = field_or_default(context, 'exp_params_source', '');
snapshot.source.experiment_script = field_or_default(context, 'experiment_script', '');
snapshot.source.experiment_name = field_or_default(context, 'experiment_name', '');

snapshot.config_snapshot = struct();
snapshot.config_snapshot.common_config = field_or_default(context, 'common_config', struct());
snapshot.config_snapshot.scenario_cfg_base = field_or_default(context, 'scenario_cfg_base', struct());
snapshot.config_snapshot.experiment_cfg = field_or_default(context, 'experiment_cfg', struct());
snapshot.config_snapshot.common_params = field_or_default(context, 'common_params', struct());
snapshot.config_snapshot.algorithm_params = field_or_default(context, 'algorithm_params', struct());

snapshot.effective_run = field_or_default(context, 'effective_run', struct());
end


function value = field_or_default(s, field_name, default_value)
if isfield(s, field_name)
    value = s.(field_name);
else
    value = default_value;
end
end
