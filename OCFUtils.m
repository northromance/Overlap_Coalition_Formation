classdef OCFUtils
    % OCFUtils 项目级工具集合，集中存放通用函数。
    % 该类设计为"静态类"，无需实例化对象即可通过类名直接调用。
    % 示例调用: OCFUtils.sort_tasks_by_priority(...)

    methods (Static)
        %% ==================== 1. 系统与路径管理 ====================

        function added = add_project_paths()
            % add_project_paths 将项目的核心子目录添加到 MATLAB 的搜索路径中。
            % 功能：
            %   动态获取当前文件所在位置作为根目录，避免硬编码路径。
            %   确保主程序在任何层级运行时，都能正确调用子文件夹（如算法库、绘图库）中的函数。
            % 输出：
            %   added: (Cell Array) 成功添加的路径列表。

            % 获取 OCFUtils.m 所在文件夹的绝对路径作为项目根目录
            root = fileparts(mfilename('fullpath'));

            % 定义需要添加到路径的子文件夹列表
            candidates = { ...
                'Main_fun', ...           % 存放核心功能与主逻辑函数
                'SA', ...                 % 模拟退火 (Simulated Annealing) 相关代码
                'plots', ...              % 绘图与可视化工具函数
                'comalg/Com_Baseline', ...% 对比算法：基线贪婪策略
                'comalg/Com_Huo2025', ... % 对比算法：参考文献 Huo2025
                'comalg/Com_Qi2023', ...  % 对比算法：参考文献 Qi2023
                'comalg/Com_PSO', ...     % 对比算法：粒子群优化 (PSO)
                'Com_Qin2025' ...         % 当前研究提出的算法实现
                };

            added = {};
            for i = 1:numel(candidates)
                % 拼接根目录与子文件夹名，生成完整路径
                p = fullfile(root, candidates{i});

                % 检查文件夹是否存在，防止 addpath 抛出警告或错误
                if exist(p, 'dir')
                    addpath(p);
                    added{end+1} = p; %#ok<AGROW> % 将成功添加的路径存入列表
                end
            end
        end

        %% ==================== 2. 任务排序与几何计算 ====================

        function ordered = sort_tasks_by_priority(task_list, tasks)
            % sort_tasks_by_priority 根据任务的优先级字段对任务ID列表进行降序排序。
            % 应用场景：在资源分配或贪婪算法中，通常优先处理高优先级 (priority) 的任务。
            % 输入：
            %   task_list: (Array) 待排序的任务ID数组。
            %   tasks: (Struct Array) 包含所有任务信息的结构体数组。

            if nargin < 2 || isempty(task_list)
                ordered = []; return; % 输入为空则直接返回
            end

            if isfield(tasks, 'priority')
                % 提取 task_list 中每个任务对应的优先级数值，生成数组
                priorities = arrayfun(@(t) tasks(t).priority, task_list);

                % 使用 sort 进行降序排列 ('descend')
                % ~: 忽略排序后的具体数值结果
                % idx: 获取排序后元素在原数组中的索引位置
                [~, idx] = sort(priorities, 'descend');

                % 根据排序后的索引重新排列任务ID列表
                ordered = task_list(idx);
            else
                % 若任务结构体无 priority 字段，默认按任务ID从小到大排序
                ordered = sort(task_list);
            end
        end

        function pos = get_task_positions(task_list, tasks)
            % get_task_positions 批量提取指定任务列表的二维坐标。
            % 输入：
            %   task_list: (Array) 任务ID数组。
            %   tasks: (Struct Array) 任务全量数据。
            % 输出：
            %   pos: (N x 2 Matrix) 每一行代表一个任务的 [x, y] 坐标，便于向量化计算。

            if nargin < 1 || isempty(task_list)
                pos = zeros(0, 2); return;
            end

            n = numel(task_list);
            pos = zeros(n, 2); % 预分配内存
            for ii = 1:n
                % 从结构体中提取 x 和 y 坐标填入矩阵
                pos(ii, :) = [tasks(task_list(ii)).x, tasks(task_list(ii)).y];
            end
        end


        function task_list = get_agent_tasks_fast(SC, agent_idx)
            % 设定容差
            tol = 1e-6;

            % cellfun 遍历每个 cell：
            % x 代表 SC{m}
            % any(x(agent_idx, :) > tol) 判断该行是否有非零元素
            % 结果是一个逻辑向量 (Logical Vector)
            is_involved = cellfun(@(x) ~isempty(x) && any(x(agent_idx, :) > tol), SC);

            % find 将逻辑向量转换为索引列表
            task_list = find(is_involved)';
        end


        function [dist, pts] = compute_route_distance(start_xy, task_ids, tasks, close_loop)
            % compute_route_distance 计算路径的总欧氏距离。
            % 路径顺序：起点 -> 任务1 -> ... -> 任务N -> (可选: 回到起点)。
            % 输入：
            %   start_xy: (1x2) 起点坐标。
            %   task_ids: (Array) 按访问顺序排列的任务ID。
            %   tasks: (Struct) 任务数据源。
            %   close_loop: (Bool) 是否闭环（最后是否回到起点），默认为 true。

            if nargin < 4 || isempty(close_loop)
                close_loop = true; % 默认开启闭环模式
            end
            if isempty(start_xy)
                dist = 0; pts = zeros(0, 2); return;
            end

            % 1. 获取所有途经任务的坐标矩阵
            task_pos = OCFUtils.get_task_positions(task_ids, tasks);

            % 2. 构建完整的路径点序列：[起点; 任务点序列]
            pts = [start_xy; task_pos];
            if close_loop
                pts = [pts; start_xy];  % 在末尾追加起点坐标以形成闭环
            end

            % 3. 向量化计算总距离
            % diff(pts, 1, 1): 计算相邻点坐标差 [dx, dy]
            diffs = diff(pts, 1, 1);

            % sum(diffs.^2, 2): 计算每段的 dx^2 + dy^2
            % sqrt(...): 开方得到每段的欧氏距离
            % sum(...): 将所有段距离累加得到总路程
            dist = sum(sqrt(sum(diffs.^2, 2)));
        end

        %% ==================== 3. 概率采样 ====================

        function target = sample_task_from_probs(probs_row, max_task_id)
            % sample_task_from_probs 基于"轮盘赌"算法 (Roulette Wheel Selection) 进行随机采样。
            % 原理：概率值越大的索引，在累积分布函数(CDF)占据的区间越宽，被随机数击中的概率越高。
            % 输入：
            %   probs_row: (Array) 概率权重向量（无需归一化，函数内处理）。
            %   max_task_id: (Int) 允许采样的最大索引值，用于越界检查。

            if isempty(probs_row)
                target = []; return;
            end

            total = sum(probs_row);
            % 若总概率非正（无有效候选项），返回空
            if total <= 0
                target = []; return;
            end

            % 1. 计算累积概率分布 (Cumulative Sum)
            % 例如: probs=[0.2, 0.5, 0.3] -> edges=[0.2, 0.7, 1.0]
            edges = cumsum(probs_row);

            % 2. 生成 [0, total] 之间的随机浮点数
            x = rand() * edges(end);

            % 3. 查找第一个大于等于 x 的位置索引
            idx = find(edges >= x, 1, 'first');

            if isempty(idx)
                target = []; return;
            end

            % 4. 安全检查：确保索引在合法范围内
            if idx < 1 || idx > max_task_id
                error('sample_task_from_probs:OutOfBounds', 'Sampled index %d outside 1..%d', idx, max_task_id);
            end
            target = idx;
        end

        %% ==================== 4. 任务执行与时间计算 ====================

        function participants = get_participants(SC, task_idx, tol)
            % get_participants 从联盟结构中识别参与特定任务的智能体列表。
            % 输入：
            %   SC: (Cell Array) 联盟结构，SC{task_idx} 是 (N x K) 的分配矩阵。
            %   task_idx: (Int) 目标任务索引。
            %   tol: (Float) 数值容差，投入资源大于此值视为参与。

            if isempty(SC) || task_idx > numel(SC)
                participants = []; return;
            end

            % SC{task_idx} 行代表智能体，列代表资源类型
            % any(..., 2): 检查每一行是否存在任意一个资源维度的投入 > tol
            % find: 返回满足条件的行号（即智能体ID）
            participants = find(any(SC{task_idx} > tol, 2))';
        end

        function t_exec = calc_exec_time(task, R_row, Value_Params, tol)
            % calc_exec_time 计算单个智能体（或资源组合）完成任务所需的执行时间。
            % 假设：多维资源并行处理，执行时间取决于"短板"（耗时最长的那一种资源）。
            % 输入：
            %   task: (Struct) 任务对象，包含 duration_by_resource 或 duration 字段。
            %   R_row: (Vector) 当前投入的资源向量。
            %   Value_Params: (Struct) 全局参数，包含资源维度 K。
            %   tol: (Float) 零值判定阈值。

            % 确定哪些资源维度被使用了（投入 > 0）
            if ~isempty(R_row)
                used = R_row > tol;
            else
                used = true(1, Value_Params.K); % 若未指定，假设全维度参与
            end

            if isfield(task, 'duration_by_resource')
                % 若任务定义了分资源的具体耗时
                dur = task.duration_by_resource(:)';
                if isscalar(dur)
                    t_exec = dur; % 若为标量，统一时间
                else
                    % 截断或对齐资源维度
                    dur = dur(1:min(numel(dur), Value_Params.K));
                    used = used(1:numel(dur));
                    % 并行逻辑：取被使用资源中的最大耗时
                    t_exec = max([dur(used), 0]);
                end
            elseif isfield(task, 'duration')
                t_exec = task.duration; % 使用固定时长
            else
                t_exec = 1.0; % 默认兜底值
            end
        end

        function t_exec = calc_coalition_exec_time(SC, task_idx, task, Value_Params, tol)
            % calc_coalition_exec_time 计算整个联盟完成某项任务的总时间。
            % 逻辑：联盟成员并行工作，任务完成时间由最慢的成员决定（木桶效应）。
            % 输入：
            %   SC: (Cell) 联盟结构。
            %   task_idx: (Int) 任务ID。
            %   task: (Struct) 任务详情。
            %   Value_Params: (Struct) 全局参数。

            alloc = SC{task_idx}; % 提取该任务的分配矩阵 (N x K)
            exec_times = [];

            % 遍历所有智能体，计算参与者的个体时间
            for i = 1:Value_Params.N
                if any(alloc(i, :) > tol) % 如果智能体 i 参与了任务
                    % 计算该成员的执行时间并加入列表
                    exec_times = [exec_times, OCFUtils.calc_exec_time(task, alloc(i, :), Value_Params, tol)]; %#ok<AGROW>
                end
            end

            % 整个联盟的耗时 = 所有参与者中的最大耗时
            t_exec = max([exec_times, 0]);
        end

        %% ==================== 5. 资源需求估算 (分位数法) ====================

        function demand = calculate_demand_quantile(belief, task_type_demands, confidence)
            % calculate_demand_quantile 基于智能体的不确定性信念估算资源需求。
            % 策略：
            %   1. 高确定性：若对某类型的信念极高，直接按该类型准备资源。
            %   2. 低确定性：按置信度 (confidence) 计算分位数，确保有 confidence% 的概率资源够用（风险规避）。
            % 输入：
            %   belief: (Vector) 智能体对任务类型的概率分布 [p1, p2, ...]。
            %   task_type_demands: (Matrix) 各任务类型对应的资源需求表。
            %   confidence: (Float) 置信度阈值 (0~1)，例如 0.95。

            if nargin < 3
                error('calculate_demand_quantile:NotEnoughInputs', '需要3个输入参数');
            end

            [num_types, K] = size(task_type_demands);
            belief = belief(:).'; % 转为行向量
            demand = zeros(1, K);

            % --- 策略 1：确定性主导 (High Confidence) ---
            if max(belief) >= confidence
                [~, most_likely_type] = max(belief); % 找到概率最大的类型
                demand = ceil(task_type_demands(most_likely_type, :)); % 直接取该类型的需求
                return;
            end

            % --- 策略 2：风险规避 (Quantile based) ---
            % 对 K 种资源分别计算满足置信度所需的量
            for r = 1:K
                demands_r = task_type_demands(:, r); % 提取第 r 种资源在所有类型下的需求
                [sorted_demands, idx] = sort(demands_r); % 按需求量从小到大排序
                sorted_belief = belief(idx);             % 对应的概率值重排

                cumulative_prob = cumsum(sorted_belief); % 计算累积概率 CDF

                % 找到累积概率首次达到 confidence 的位置，该位置的需求量即为覆盖风险所需的量
                threshold_idx = find(cumulative_prob >= confidence, 1);
                if isempty(threshold_idx)
                    threshold_idx = num_types;
                end

                demand(r) = sorted_demands(threshold_idx);
            end
            demand = ceil(demand); % 向上取整确保资源为整数
        end

        %% ==================== 6. 统计学工具 (Dirichlet分布) ====================

        function r = drchrnd(a, n)
            % drchrnd 生成狄利克雷分布 (Dirichlet Distribution) 的随机样本。
            % 用途：贝叶斯推断中，用于从 Dirichlet 后验分布中采样生成新的信念 (Belief)。
            % 原理：利用 Gamma 分布构造。若 X_i ~ Gamma(a_i, 1)，则 Y_i = X_i / sum(X) 服从 Dir(a)。
            % 输入：
            %   a: (Vector) Dirichlet 分布的参数向量 (alpha)。
            %   n: (Int) 需要生成的样本数量，默认为 1。

            if nargin < 2 || isempty(n)
                n = 1;
            end
            a = a(:).';
            p = numel(a);

            % 1. 生成对应的 Gamma 分布随机数
            r = gamrnd(repmat(a, n, 1), 1, n, p);

            % 2. 对每一行进行归一化，确保概率和为 1
            r = r ./ sum(r, 2);
        end

        %% ==================== 7. 效用与完成度计算 ====================

        function r_n = calc_resource_contribution_ratio(SC_m, agent_idx, member_indices)
            % calc_resource_contribution_ratio 计算智能体在联盟中的相对贡献占比。
            % 计算方式：(该智能体投入资源的范数) / (联盟所有成员投入资源的总范数)。
            % 输入：
            %   SC_m: (Matrix) 当前任务的资源分配矩阵 (N x K)。
            %   agent_idx: (Int) 当前计算的智能体ID。
            %   member_indices: (Array) 联盟所有成员的ID列表。

            A_n = norm(SC_m(agent_idx, :)); % 当前智能体投入向量的模长
            total_norm = 0;

            % 累加所有成员的投入模长
            for i = 1:numel(member_indices)
                member_id = member_indices(i);
                total_norm = total_norm + norm(SC_m(member_id, :));
            end

            if total_norm > 1e-9
                r_n = A_n / total_norm; % 正常计算比率
            else
                % 避免除以零：若总投入为0，假设贡献均等
                r_n = 1 / max(numel(member_indices), 1);
            end
        end

        function D_C = calc_task_completion_degree(allocated_resources, task_demand, K)
            % calc_task_completion_degree 计算任务完成度 D_C (范围 0.0 ~ 1.0)。
            % 核心指标：衡量当前分配的资源在多大程度上满足了任务需求。
            % 输入：
            %   allocated_resources: (Matrix/Vector) 已分配的资源，若是矩阵则先求和。
            %   task_demand: (Vector) 任务实际需求向量。
            %   K: (Int) 资源维度数。

            % 若输入是多行矩阵（多个智能体），先按列求和得到总资源
            if size(allocated_resources, 1) > 1
                allocated = sum(allocated_resources, 1);
            else
                allocated = allocated_resources;
            end

            % 维度对齐：不足 K 维补零
            if numel(allocated) < K
                allocated = [allocated, zeros(1, K - numel(allocated))];
            end
            if numel(task_demand) < K
                task_demand = [task_demand, zeros(1, K - numel(task_demand))];
            end

            % 统计有实际需求（非零）的资源维度数量
            Z_c = nnz(task_demand > 1e-9);
            if Z_c == 0
                D_C = 1; return; % 若任务无需求，视为直接完成
            end

            D_C = 0;
            for k = 1:K
                if task_demand(k) > 1e-9
                    % 计算第 k 维度的满足率，封顶为 1.0 (资源溢出不增加完成度)
                    ratio = min(allocated(k) / task_demand(k), 1.0);
                    D_C = D_C + ratio;
                end
            end

            % 取所有有效维度的平均满足率
            D_C = D_C / Z_c;
        end

        %% ==================== 8. 观测与信念更新 ====================

        function [Value_data, summatrix] = collect_observations(Value_data, agents, tasks, Value_Params,summatrix,SC)
            % collect_observations 模拟智能体对任务类型的观测过程与信息共享。
            % 过程：
            %   1. 智能体根据探测概率(detprob)对任务类型进行观测（可能出错）。
            %   2. 将观测结果汇总到全局矩阵(summatrix)，实现通信共享。
            % 输入：
            %   Value_data: (Struct) 包含观测计数的数据结构。
            %   agents: (Struct) 智能体属性（含探测概率）。
            %   curTaskList: (Cell) 每个智能体当前处理的任务列表。
            %   summatrix: (Matrix) 全局累计观测计数矩阵。

            if nargin < 6 || isempty(summatrix)
                summatrix = zeros(Value_Params.M, Value_Params.task_type);
            end

            SC_global = SC;

            % --- 阶段1：各智能体独立观测 ---
            for i = 1:Value_Params.N
                taskIds = OCFUtils.get_agent_tasks_fast(SC_global, i);% 获取智能体 i 当前关注的任务
                if isempty(taskIds), continue; end

                for tIdx = 1:numel(taskIds)
                    taskId = taskIds(tIdx);

                    % 确定任务的真实类型索引与错误类型索引集合
                    taskindex = find(tasks(taskId).value == tasks(taskId).WORLD.value, 1);
                    nontaskindex = find(tasks(taskId).value ~= tasks(taskId).WORLD.value);

                    if isempty(taskindex), continue; end

                    % 根据 obs_times 执行多次观测采样
                    for m = 1:Value_Params.obs_times
                        r = rand;
                        % 逻辑：随机数 < 探测概率 -> 观测正确；否则 -> 随机产生一个错误观测
                        if r <= agents(i).detprob || isempty(nontaskindex)
                            Value_data(i).observe(taskId, taskindex) = Value_data(i).observe(taskId, taskindex) + 1;
                        else
                            % 随机选择一个错误的类型进行累加
                            chosen_idx = nontaskindex(randi(numel(nontaskindex)));
                            Value_data(i).observe(taskId, chosen_idx) = Value_data(i).observe(taskId, chosen_idx) + 1;
                        end
                    end
                end
            end

            % --- 阶段2：信息融合与同步 ---
            % 更新全局观测矩阵：加上各智能体自上次同步以来的新增观测
            for j = 1:Value_Params.M
                for k = 1:Value_Params.task_type
                    for i = 1:Value_Params.N
                        % 新增量 = 当前累计观测 - 上次同步时的快照
                        summatrix(j, k) = summatrix(j, k) + Value_data(i).observe(j, k) - Value_data(i).preobserve(j, k);
                    end
                end
            end

            % 将全局信息回写给每个智能体，完成信息共享
            for i = 1:Value_Params.N
                for j = 1:Value_Params.M
                    for k = 1:Value_Params.task_type
                        Value_data(i).preobserve(j, k) = summatrix(j, k); % 更新快照
                        Value_data(i).observe(j, k) = summatrix(j, k);    % 更新当前认知
                    end
                end
            end
        end

        function Value_data = update_belief_from_observations(Value_data, Value_Params)
            % update_belief_from_observations 利用贝叶斯公式更新智能体的信念 (Belief)。
            % 方法：Dirichlet 分布作为 Multinomial 分布的共轭先验。
            % 公式：后验 Alpha 参数 = 先验 Alpha (通常为1) + 观测次数 (observe count)。

            for i = 1:Value_Params.N
                for j = 1:Value_Params.M
                    % 计算 Dirichlet 分布的参数 alpha (加1代表均匀先验)
                    alpha_params = 1 + Value_data(i).observe(j, 1:Value_Params.task_type);

                    % 从更新后的 Dirichlet 分布中采样，得到新的信念概率分布
                    Value_data(i).initbelief(j, 1:end) = OCFUtils.drchrnd(alpha_params, 1)';
                end
            end
        end

        %% ==================== 9. 随机数与状态控制 ====================

        function seed = set_seed(seed)
            % set_seed 统一设置随机数种子，确保实验结果可复现。
            % 输入：
            %   seed: (Int, 可选) 种子值。若为空，则使用当前时间生成动态种子。

            if nargin < 1 || isempty(seed)
                seed = floor(sum(1000 * clock)); % 基于系统时钟生成
            end

            rand('seed', seed);   % 设置旧版均匀分布种子
            randn('seed', seed);  % 设置旧版正态分布种子
            rng(seed, 'twister'); % 使用现代 Mersenne Twister 生成器设置 rng
        end

        function [SC_P, SC_Q, R_agent_P, R_agent_Q] = calc_move_changes(Value_data, agents, Value_Params, cur_task_idx, target_task_idx, agent_col_idx)
            % calc_move_changes 计算智能体从一个任务迁移到另一个任务时的资源状态变化。
            % 核心修正：针对个体资源矩阵 R_agent 采用"全盘清零"策略，防止脏数据残留。
            % 输入：
            %   Value_data: 当前数据状态。
            %   agents: 智能体列表。
            %   cur_task_idx: 当前所在任务ID。
            %   target_task_idx: 目标任务ID。
            %   agent_col_idx: 智能体在矩阵中的行索引。

            %% 1. 初始化与备份
            M = Value_Params.M;
            K = Value_Params.K;
            agentID = Value_data.agentID;

            % 备份原始状态 (P状态)
            SC_P = Value_data.SC;
            R_agent_P = Value_data.resources_matrix;

            % 初始化新状态 (Q状态)，先复制 SC
            SC_Q = SC_P;

            %% 2. 准备智能体资源向量
            raw_res = agents(agentID).resources(:)';
            % 确保资源向量维度为 K
            if length(raw_res) >= K
                agent_full_res = raw_res(1:K);
            else
                agent_full_res = [raw_res, zeros(1, K - length(raw_res))];
            end

            %% 3. [关键操作] 个体资源矩阵全盘清零
            % 无论之前在哪，新状态 R_agent_Q 应只包含目标任务的资源，其余归零
            R_agent_Q = zeros(M, K);

            %% 4. 执行"撤出"逻辑 (更新 SC 全局矩阵)
            % 个体矩阵 R_agent_Q 已在上方清零，此处只需处理 SC_Q
            if cur_task_idx <= M
                % 从旧任务的小组中移除该智能体的资源贡献
                if cur_task_idx <= numel(SC_Q) && ~isempty(SC_Q{cur_task_idx})
                    SC_Q{cur_task_idx}(agent_col_idx, :) = 0;
                end
            end

            %% 5. 执行"加入"逻辑 (更新 SC 和 R_agent)
            if target_task_idx <= M
                % A. 个体视图：在目标任务行填入资源 (唯一非零行)
                R_agent_Q(target_task_idx, :) = agent_full_res;

                % B. 全局视图：将资源加入新任务的分配矩阵中
                if target_task_idx <= numel(SC_Q)
                    if isempty(SC_Q{target_task_idx})
                        SC_Q{target_task_idx} = zeros(Value_Params.N, K);
                    end
                    cols_to_fill = min(K, size(SC_Q{target_task_idx}, 2));
                    SC_Q{target_task_idx}(agent_col_idx, 1:cols_to_fill) = agent_full_res(1:cols_to_fill);
                end
            end
        end

        function R_agent = get_agent_resource_matrix(SC, agent_idx, Value_Params)
            % extract_agent_resource_matrix 从全局联盟结构 SC 中提取指定智能体的资源分配矩阵。
            % 功能：
            %   将三维视角的全局 SC (Cell Array of N x K matrices) 转换为
            %   二维视角的个体资源矩阵 (M x K matrix)。
            %   矩阵的第 m 行表示该智能体在第 m 个任务上投入的 K 种资源量。
            % 输入：
            %   SC: (Cell Array) 联盟结构，长度为 M。SC{m} 是 N x K 矩阵。
            %   agent_idx: (Int) 智能体在矩阵中的行索引 (1..N)。
            %   Value_Params: (Struct) 包含 M (任务数) 和 K (资源维度)。
            % 输出：
            %   R_agent: (Matrix) M x K 的个体资源分配矩阵。

            M = Value_Params.M;
            K = Value_Params.K;

            % 预分配 M x K 的零矩阵，确保未分配的任务行默认为 0
            R_agent = zeros(M, K);

            for m = 1:M
                % 边界检查：确保 SC 包含该任务且内容非空
                if m <= numel(SC) && ~isempty(SC{m})
                    % 提取：SC{m} 的第 agent_idx 行 -> R_agent 的第 m 行
                    R_agent(m, :) = SC{m}(agent_idx, :);
                end
            end
        end
    end
end