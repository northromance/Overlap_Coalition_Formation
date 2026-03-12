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
                'Main_fun', ...                % 框架层：效用/时间/工具 + 共享算法辅助函数
                'plots', ...                   % 绘图与可视化工具函数
                'comalg/alg1_SA', ...          % 算法 1: SA_Value（早期算法）
                'comalg/alg2_Huo2025', ...     % 算法 2: Huo2025
                'comalg/alg3_Qi2023', ...      % 算法 3: Qi2023
                'comalg/alg4_Shi2024', ...     % 算法 4: Shi2024
                'comalg/alg7_OCF_SAtabu' ...   % 算法 7: OCF_SAtabu_global（主算法）
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
    % 
    % 计算方式：(该智能体投入资源的综合数量) / (联盟所有成员投入资源的总数量)。
    % 使用一范数 (sum) 替代二范数 (norm)，保证多维资源相加的物理公平性。
    %
    % 输入：
    %   SC_m: (Matrix) 当前任务的资源分配矩阵 (N x K)。
    %   agent_idx: (Int) 当前计算的智能体ID。
    %   member_indices: (Array) 联盟所有成员的ID列表。

    % 1. 计算当前智能体的总资源投入 (对行向量求和)
    A_n = sum(SC_m(agent_idx, :)); 
    
    % 2. 向量化计算整个联盟的总资源投入 (提取子矩阵，一并求和)
    % 取出所有参与者的行，对所有元素求和
    total_resources = sum(SC_m(member_indices, :), "all"); 
    
    % 3. 防护与比例计算
    if total_resources > 1e-9
        r_n = A_n / total_resources; 
    else
        % 避免除以零：若总投入为0，假设贡献均等
        r_n = 1 / max(numel(member_indices), 1);
    end
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


        function task_list = get_agent_tasks_fast(SC, agent_idx, tol)
            % GET_AGENT_TASKS_FAST 快速获取智能体参与的任务列表 (安全版)
            %
            % 输入:
            %   SC        : 联盟结构
            %   agent_idx : 智能体ID
            %   tol       : (可选) 容差，默认 1e-6

            if nargin < 3 || isempty(tol)
                tol = 1e-6;
            end

            % 使用 cellfun 进行向量化查询
            % 逻辑: 非空 && 行数足够 && 有资源投入
            is_involved = cellfun(@(x) ~isempty(x) && ...
                size(x, 1) >= agent_idx && ...
                any(x(agent_idx, :) > tol), SC);

            % 转换为索引
            task_list = find(is_involved);

            % 确保输出始终是行向量 (1 x N)，方便后续遍历
            if iscolumn(task_list)
                task_list = task_list';
            end
        end


        function Value_Params = init_value_params(N, M, K, num_task_types, task_type_demands, SA_alpha, SA_Tmin, K_stable_max, obs_times, num_rounds)
            % INIT_VALUE_PARAMS 初始化算法参数结构
            %
            % 输入参数:
            %   N                          - 智能体数量
            %   M                          - 任务数量
            %   K                          - 资源类型数量
            %   num_task_types             - 任务价值类型数量
            %   task_type_demands          - 任务类型资源需求矩阵
            %   SA_alpha                   - 模拟退火温度衰减率
            %   SA_Tmin                    - 模拟退火最小温度
            %   K_stable_max               - 稳定性阈值（连续无改进迭代次数）
            %   obs_times                  - 每个任务的观测次数
            %   num_rounds                 - 游戏总轮数
            %
            % 输出参数:
            %   Value_Params               - 算法参数结构体
            %
            % 示例:
            %   Value_Params = init_value_params(8, 5, 6, 3, task_type_demands, 100.0, 0.95, 0.01, 20, 20, 100);

            % 基本参数
            Value_Params.N = N;
            Value_Params.M = M;
            Value_Params.K = K;
            Value_Params.task_type = num_task_types;  % 任务价值类型数量（低、中、高）
            Value_Params.task_type_demands = task_type_demands;

            % 模拟退火算法参数（统一命名）
            Value_Params.alpha = SA_alpha;
            Value_Params.Tmin = SA_Tmin;
            Value_Params.K_stable_max = K_stable_max;  % 稳定性阈值（各算法共用概念）

            % 观测参数
            Value_Params.obs_times = obs_times;

            % 游戏参数
            Value_Params.num_rounds = num_rounds;

        end

        function coalitionstru = build_coalitionstru_from_SC(SC, Value_Params, agents)
            % BUILD_COALITIONSTRU_FROM_SC 根据 N*K 资源矩阵反推联盟结构
            % 输入:
            %   SC: M个Cell，每个是 N*K 矩阵
            %   agents: 智能体结构体 (用于获取 ID)
            % 输出:
            %   coalitionstru: (M+1)*N 矩阵

            M = Value_Params.M;
            N = Value_Params.N;
            tol = 1e-6; % 容差，防止浮点数误差

            % 1. 初始化 (M+1) x N 矩阵
            coalitionstru = zeros(M + 1, N);

            % 2. 遍历真实任务 (1~M)
            for j = 1:M
                % 取出第 j 个任务的资源分配矩阵 (N x K)
                task_res_matrix = SC{j};

                if ~isempty(task_res_matrix)
                    % 遍历每个智能体 i (矩阵的行)
                    for i = 1:N
                        % 获取该智能体的真实 ID
                        if ~isempty(agents)
                            aid = agents(i).id;
                        else
                            aid = i;
                        end

                        % 防越界检查
                        if i <= size(task_res_matrix, 1)
                            % [关键逻辑] 检查该智能体行的“所有资源列”
                            % 只要有任意一列资源 > 0，就算参与了该任务
                            agent_resources = task_res_matrix(i, :);

                            if any(agent_resources > tol)
                                coalitionstru(j, i) = aid;
                            end
                        end
                    end
                end
            end

            % 3. 处理 Void 任务 (M+1)
            % 逻辑：如果智能体在 1~M 任务行中全是 0，说明它空闲
            for i = 1:N
                if ~isempty(agents)
                    aid = agents(i).id;
                else
                    aid = i;
                end

                % 检查 1~M 行这一列是否有非零值
                is_busy = any(coalitionstru(1:M, i) ~= 0);

                if ~is_busy
                    % 空闲 -> 填入 ID
                    coalitionstru(M + 1, i) = aid;
                else
                    % 忙碌 -> 填入 0
                    coalitionstru(M + 1, i) = 0;
                end
            end
        end
    end
end