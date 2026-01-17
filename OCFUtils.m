classdef OCFUtils
    % OCFUtils 项目级工具集合，集中存放通用函数。
    % 主要功能：
    %   - add_project_paths    统一添加常用子目录到 MATLAB 路径
    %   - sort_tasks_by_priority 按任务优先级排序
    %   - get_task_positions   获取任务坐标矩阵
    %   - compute_route_distance 计算任务行进总距离
    %   - set_seed             设置随机种子（rand/randn/rng）
    %   - ensure_dir           确保目录存在
    %   - header               打印统一风格标题块
    %   - timestamp_tag        生成文件名友好的时间戳
    % 后续复用逻辑可在此扩展。

    methods (Static)
        function added = add_project_paths()
            % add_project_paths 将核心子目录加入 MATLAB 搜索路径。
            % 输入：无（默认以当前文件所在目录为项目根）
            % 输出：
            %   added : 成功添加的绝对路径 cell 数组（便于调试或日志记录）。
            % 备注：仅在子目录存在时添加，避免报错。
            root = fileparts(mfilename('fullpath'));
            candidates = { ...
                'Main_fun', ...
                'SA', ...
                'plots', ...
                'comalg/Com_Baseline', ...
                'comalg/Com_Huo2025', ...
                'comalg/Com_Qi2023', ...
                'comalg/Com_PSO', ...
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
            % sort_tasks_by_priority 按任务优先级升序排序。
            % 输入：
            %   task_list : 任务下标向量
            %   tasks     : 任务结构体数组，需包含 priority 字段；缺省时按编号排序
            % 输出：
            %   ordered   : 排序后的任务下标向量
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

        function pos = get_task_positions(task_list, tasks)
            % get_task_positions 返回任务列表的坐标矩阵。
            % 输入：
            %   task_list : 任务下标向量（可为空）
            %   tasks     : 任务结构体数组，需包含 x, y 字段
            % 输出：
            %   pos       : n×2 矩阵，每行对应一个任务的 [x, y]
            if nargin < 1 || isempty(task_list)
                pos = zeros(0, 2);
                return;
            end
            n = numel(task_list);
            pos = zeros(n, 2);
            for ii = 1:n
                pos(ii, :) = [tasks(task_list(ii)).x, tasks(task_list(ii)).y];
            end
        end

        function [dist, pts] = compute_route_distance(start_xy, task_ids, tasks, close_loop)
            % compute_route_distance 计算路径总距离。
            % 输入：
            %   start_xy  : 起点坐标 [x, y]
            %   task_ids  : 按访问顺序的任务下标向量（可为空）
            %   tasks     : 任务结构体数组，需包含 x, y 字段
            %   close_loop: 布尔，是否返回起点，默认 true
            % 输出：
            %   dist      : 总路程（标量）
            %   pts       : 路径节点坐标序列（用于可视化或调试）
            % 说明：close_loop=false 时，路径为 start -> tasks，不再回到起点。
            if nargin < 4 || isempty(close_loop)
                close_loop = true;
            end
            if isempty(start_xy)
                dist = 0;
                pts = zeros(0, 2);
                return;
            end

            pts = [start_xy; OCFUtils.get_task_positions(task_ids, tasks)];
            if close_loop
                pts = [pts; start_xy];
            end

            diffs = diff(pts, 1, 1);
            dist = sum(sqrt(sum(diffs.^2, 2)));
        end

        function r = drchrnd(a, n)
            % drchrnd 从 Dirichlet 分布采样
            % 输入：
            %   a : 1×p 或 p×1 的浓度参数向量
            %   n : 样本数量（可选，默认 1）
            % 输出：
            %   r : n×p 的样本矩阵，每行元素和为 1
            if nargin < 2 || isempty(n)
                n = 1;
            end
            a = a(:).';
            p = numel(a);
            r = gamrnd(repmat(a, n, 1), 1, n, p);
            r = r ./ sum(r, 2);
        end

        function r_n = calc_resource_contribution_ratio(SC_m, agent_idx, member_indices)
            % calc_resource_contribution_ratio 计算智能体在联盟中的资源贡献比例 r_n(C)
            % 计算公式：r_n(C) = ||A_n|| / Σ||A_i||，其中 A_n 为 agent 的资源向量
            % 输入：
            %   SC_m           : 任务m的资源分配矩阵 (N×K)
            %   agent_idx      : 要计算贡献比例的智能体索引（行号）
            %   member_indices : 参与该任务的所有智能体索引向量
            % 输出：
            %   r_n            : 资源贡献比例 (0~1)，若总资源为0则平均分配
            A_n = norm(SC_m(agent_idx, :));
            total_norm = 0;
            for i = 1:numel(member_indices)
                member_id = member_indices(i);
                total_norm = total_norm + norm(SC_m(member_id, :));
            end
            if total_norm > 1e-9
                r_n = A_n / total_norm;
            else
                r_n = 1 / max(numel(member_indices), 1);
            end
        end

        function D_C = calc_task_completion_degree(allocated_resources, task_demand, K)
            % calc_task_completion_degree 计算任务的资源完成度 D_C
            % 计算公式：D_C = (1/Z_c) × Σ min(allocated_k / demand_k, 1.0)
            % 输入：
            %   allocated_resources : 分配给任务的资源向量 (1×K) 或矩阵 (N×K)
            %   task_demand          : 任务的资源需求向量 (1×K)
            %   K                    : 资源类型数量
            % 输出：
            %   D_C                  : 任务完成度 (0~1)，表示资源满足程度
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
                D_C = 1;
                return;
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

        function seed = set_seed(seed)
            % set_seed 设置随机种子，兼容 rand/randn/rng。
            % 输入：
            %   seed : 随机种子，缺省时使用基于时钟的种子
            % 输出：
            %   seed : 实际使用的种子值（便于记录与复现实验）
            if nargin < 1 || isempty(seed)
                seed = floor(sum(1000 * clock));
            end

            rand('seed', seed);   % 兼容旧接口
            randn('seed', seed);
            rng(seed, 'twister'); % 新接口
        end
    end
end


