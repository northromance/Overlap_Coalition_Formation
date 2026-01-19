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
            % sort_tasks_by_priority 按任务优先级降序排序。
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
                [~, idx] = sort(priorities, 'descend');  % 修改为降序排序
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

        function target = sample_task_from_probs(probs_row, max_task_id)
            % sample_task_from_probs 从概率行向量中按累计概率采样任务索引。
            % 输入：
            %   probs_row    : 1×M 概率行向量（可未归一化，允许含 0）
            %   max_task_id  : 允许的最大任务编号 M
            % 输出：
            %   target       : 采样得到的任务索引；若概率和<=0则返回 []
            if isempty(probs_row)
                target = [];
                return;
            end

            total = sum(probs_row);
            if total <= 0
                target = [];
                return;
            end

            edges = cumsum(probs_row);
            x = rand() * edges(end);
            idx = find(edges >= x, 1, 'first');

            if isempty(idx)
                target = [];
                return;
            end

            if idx < 1 || idx > max_task_id
                error('sample_task_from_probs:OutOfBounds', ...
                      'Sampled index %d outside 1..%d', idx, max_task_id);
            end

            target = idx;
        end

        function participants = get_participants(SC, task_idx, N, tol)
            % get_participants 获取指定任务的所有参与者（智能体）ID列表
            % N 参数保留兼容性，当前不使用。
            %#ok<INUSD>
            if isempty(SC) || task_idx > numel(SC)
                participants = [];
                return;
            end
            participants = find(any(SC{task_idx} > tol, 2))';
        end

        function t_exec = calc_exec_time(task, R_row, Value_Params, tol)
            % calc_exec_time 单个智能体执行任务的时间（并行模型：取使用资源中的最长时间）
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
            % calc_coalition_exec_time 计算联盟执行任务的时间（取所有参与者中最长执行时间）
            alloc = SC{task_idx};
            exec_times = [];
            for i = 1:Value_Params.N
                if any(alloc(i, :) > tol)
                    exec_times = [exec_times, OCFUtils.calc_exec_time(task, alloc(i, :), Value_Params, tol)]; %#ok<AGROW>
                end
            end
            t_exec = max([exec_times, 0]);
        end

        function demand = calculate_demand_quantile(belief, task_type_demands, confidence)
            % calculate_demand_quantile 使用分位数法计算资源需求
            % 高置信度时直接使用最可能类型需求，低置信度时按置信度计算分位数需求。
            if nargin < 3
                error('calculate_demand_quantile:NotEnoughInputs', ...
                      '需要3个输入参数: belief, task_type_demands, confidence');
            end

            if confidence < 0 || confidence > 1
                error('calculate_demand_quantile:InvalidConfidence', ...
                      'confidence必须在0到1之间，当前值: %.2f', confidence);
            end

            [num_types, K] = size(task_type_demands);
            if numel(belief) ~= num_types
                error('calculate_demand_quantile:DimensionMismatch', ...
                      'belief长度(%d)必须等于task_type_demands行数(%d)', ...
                      numel(belief), num_types);
            end

            belief = belief(:).';
            demand = zeros(1, K);

            % 高确定性：直接选最大信念类型需求
            if max(belief) >= confidence
                [~, most_likely_type] = max(belief);
                demand = ceil(task_type_demands(most_likely_type, :));
                return;
            end

            % 低确定性：按资源独立计算分位数需求
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
        
        function [Value_data, summatrix] = collect_observations(Value_data, agents, tasks, Value_Params, curTaskList, summatrix)
            % collect_observations 执行观测并同步观测矩阵
            % 输入：
            %   Value_data   : 包含 observe/preobserve 的结构体数组
            %   agents       : 智能体数组（需含 detprob）
            %   tasks        : 任务数组（需含 value 与 WORLD.value）
            %   Value_Params : 参数结构（需含 M、N、task_type、obs_times）
            %   curTaskList  : 长度 N 的 cell，每个元素为该智能体本轮参与的任务ID列表
            %   summatrix    : 全局观测累积矩阵 (M×task_type)，可选，缺省则置零
            % 输出：
            %   Value_data   : 更新后的观测计数
            %   summatrix    : 累积后的全局观测矩阵
            if nargin < 6 || isempty(summatrix)
                summatrix = zeros(Value_Params.M, Value_Params.task_type);
            end
            
            % 单个智能体的观测采样
            for i = 1:Value_Params.N
                taskIds = curTaskList{i};
                if isempty(taskIds)
                    continue;
                end
                for tIdx = 1:numel(taskIds)
                    taskId = taskIds(tIdx);
                    % 真值索引与非真值索引
                    taskindex = find(tasks(taskId).value == tasks(taskId).WORLD.value, 1);
                    nontaskindex = find(tasks(taskId).value ~= tasks(taskId).WORLD.value);
                    if isempty(taskindex)
                        % 若未匹配到真值索引，跳过该观测，避免维度错误
                        continue;
                    end
                    for m = 1:Value_Params.obs_times
                        r = rand;
                        if r <= agents(i).detprob || isempty(nontaskindex)
                            % 正确观测
                            Value_data(i).observe(taskId, taskindex) = Value_data(i).observe(taskId, taskindex) + 1;
                        else
                            % 错误观测：均匀从非真值中选一类
                            chosen_idx = nontaskindex(randi(numel(nontaskindex)));
                            Value_data(i).observe(taskId, chosen_idx) = Value_data(i).observe(taskId, chosen_idx) + 1;
                        end
                    end
                end
            end
            
            % 聚合全体智能体的新增观测
            for j = 1:Value_Params.M
                for k = 1:Value_Params.task_type
                    for i = 1:Value_Params.N
                        summatrix(j, k) = summatrix(j, k) + Value_data(i).observe(j, k) - Value_data(i).preobserve(j, k);
                    end
                end
            end
            
            % 同步观测矩阵到所有智能体
            for i = 1:Value_Params.N
                for j = 1:Value_Params.M
                    for k = 1:Value_Params.task_type
                        Value_data(i).preobserve(j, k) = summatrix(j, k);
                        Value_data(i).observe(j, k) = summatrix(j, k);
                    end
                end
            end
        end
        
        function Value_data = update_belief_from_observations(Value_data, Value_Params)
            % update_belief_from_observations 基于观测计数做Dirichlet后验更新
            % 输入：
            %   Value_data   : 包含 observe 的结构体数组
            %   Value_Params : 参数结构（需含 N、M、task_type）
            for i = 1:Value_Params.N
                for j = 1:Value_Params.M
                    alpha_params = 1 + Value_data(i).observe(j, 1:Value_Params.task_type);
                    Value_data(i).initbelief(j, 1:end) = OCFUtils.drchrnd(alpha_params, 1)';
                end
            end
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
