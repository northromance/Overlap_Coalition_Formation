classdef OCFUtils
    % OCFUtils collects project-wide helper utilities.
    %   add_project_paths : add core subfolders to MATLAB path
    %   set_seed          : set random seed (rand/randn/rng)
    %   ensure_dir        : create directory if missing
    %   header            : print a formatted header block
    %   timestamp_tag     : generate a filename-safe timestamp
    % Extend by adding more static methods below.

    methods (Static)
        function added = add_project_paths()
            % Add main subfolders to the search path and return the added paths
            root = fileparts(mfilename('fullpath'));
            candidates = { ...
                'Main_fun', ...
                'SA', ...
                'plots', ...
                'Com_Baseline', ...
                'Com_Huo2025', ...
                'Com_Qi2023', ...
                'Com_PSO', ...
                'Com_Qin2025' ...
            };

            added = {};
            for i = 1:numel(candidates)
                p = fullfile(root, candidates{i});
                if exist(p, 'dir')
                    addpath(p);
                    added{end+1} = p; %#ok<AGROW>
                end
            end
        end

        function ordered = sort_tasks_by_priority(task_list, tasks)
            % Sort a task list by priority field (ascending); fall back to numeric sort
            if nargin < 2 || isempty(task_list)
                ordered = [];
                return;
            end

            if isfield(tasks, 'priority')
                priorities = arrayfun(@(t) tasks(t).priority, task_list);
                [~, idx] = sort(priorities);
                ordered = task_list(idx);
            else
                ordered = sort(task_list);
            end
        end

        function seed = set_seed(seed)
            % Set random seed; falls back to a clock-based seed when empty
            if nargin < 1 || isempty(seed)
                seed = floor(sum(1000 * clock));
            end

            rand('seed', seed);   % legacy interface
            randn('seed', seed);
            rng(seed, 'twister'); % modern interface
        end

        function ensure_dir(dirPath)
            % Create directory when it does not exist
            if nargin < 1 || isempty(dirPath)
                return;
            end

            if ~exist(dirPath, 'dir')
                mkdir(dirPath);
            end
        end

        function header(msg)
            % Print a formatted header block
            if nargin < 1 || isempty(msg)
                msg = '';
            end

            line_len = max(60, numel(msg) + 10);
            line = repmat('=', 1, line_len);
            fprintf('\n%s\n%s\n%s\n\n', line, msg, line);
        end

        function tag = timestamp_tag(fmt)
            % Generate a filename-safe timestamp string
            if nargin < 1 || isempty(fmt)
                fmt = 'yyyyMMdd_HHmmss';
            end

            tag = datestr(now, fmt);
        end
    end
end
