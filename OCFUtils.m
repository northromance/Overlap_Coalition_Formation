classdef OCFUtils
    % OCFUtils 项目级工具集合，集中存放通用函数。
    % 该类是一个"静态类"，不需要实例化即可直接调用，例如 OCFUtils.sort_tasks_by_priority(...)
    
    methods (Static)
        %% ==================== 1. 系统与路径管理 ====================
        
        function added = add_project_paths()
            % add_project_paths 将项目的核心子目录添加到 MATLAB 的搜索路径中。
            % 作用：确保在任何目录下运行主程序时，都能调用到子文件夹里的函数。
            
            % 获取当前文件 (OCFUtils.m) 所在的文件夹路径，作为项目的根目录
            root = fileparts(mfilename('fullpath'));
            
            % 定义需要添加的子目录列表
            candidates = { ...
                'Main_fun', ...           % 主功能函数
                'SA', ...                 % 模拟退火算法相关
                'plots', ...              % 绘图函数
                'comalg/Com_Baseline', ...% 对比算法：基线贪婪
                'comalg/Com_Huo2025', ... % 对比算法：Huo2025
                'comalg/Com_Qi2023', ...  % 对比算法：Qi2023
                'comalg/Com_PSO', ...     % 对比算法：粒子群
                'Com_Qin2025' ...         % 当前算法
                };
            
            added = {};
            for i = 1:numel(candidates)
                % 拼接完整路径
                p = fullfile(root, candidates{i});
                % 检查文件夹是否存在，避免 addpath 报错
                if exist(p, 'dir')
                    addpath(p);
                    added{end+1} = p; %#ok<AGROW> % 记录已添加的路径
                end
            end
        end
        
        %% ==================== 2. 任务排序与几何计算 ====================
        
        function ordered = sort_tasks_by_priority(task_list, tasks)
            % sort_tasks_by_priority 根据任务的 priority 字段进行降序排序。
            % 作用：在分配资源时，通常优先处理高优先级的任务。
            
            if nargin < 2 || isempty(task_list)
                ordered = [];
                return;
            end
            
            if isfield(tasks, 'priority')
                % 提取 task_list 中所有任务对应的优先级值，组成数组
                priorities = arrayfun(@(t) tasks(t).priority, task_list);
                % 使用 sort 函数进行降序排序 ('descend')
                % ~ : 忽略排序后的值
                % idx : 排序后的原索引位置
                [~, idx] = sort(priorities, 'descend');  
                ordered = task_list(idx); % 根据索引重新排列任务列表
            else
                % 如果没有优先级字段，默认按任务ID从小到大排序
                ordered = sort(task_list);
            end
        end
        
        function pos = get_task_positions(task_list, tasks)
            % get_task_positions 批量提取任务的 (x, y) 坐标。
            % 输出：N x 2 的矩阵，方便后续进行向量化的距离计算。
            
            if nargin < 1 || isempty(task_list)
                pos = zeros(0, 2);
                return;
            end
            n = numel(task_list);
            pos = zeros(n, 2);
            for ii = 1:n
                % 逐个提取坐标并填入矩阵
                pos(ii, :) = [tasks(task_list(ii)).x, tasks(task_list(ii)).y];
            end
        end
        
        function [dist, pts] = compute_route_distance(start_xy, task_ids, tasks, close_loop)
            % compute_route_distance 计算一条路径的总长度（欧氏距离）。
            % 逻辑：起点 -> 任务1 -> 任务2 -> ... -> 任务N -> 起点(可选)
            
            if nargin < 4 || isempty(close_loop)
                close_loop = true; % 默认是闭环（回到起点）
            end
            if isempty(start_xy)
                dist = 0;
                pts = zeros(0, 2);
                return;
            end
            
            % 1. 获取所有途经任务的坐标
            task_pos = OCFUtils.get_task_positions(task_ids, tasks);
            
            % 2. 构建完整的路径点序列
            pts = [start_xy; task_pos]; % 起点 + 任务点
            if close_loop
                pts = [pts; start_xy];  % 最后加上起点，形成闭环
            end
            
            % 3. 向量化计算距离
            % diff(pts, 1, 1) 计算相邻点坐标差：[x2-x1, y2-y1; x3-x2, y3-y2; ...]
            diffs = diff(pts, 1, 1);
            % sum(diffs.^2, 2) 计算 dx^2 + dy^2
            % sqrt(...) 开根号得到每段距离
            % sum(...) 所有段距离求和
            dist = sum(sqrt(sum(diffs.^2, 2)));
        end
        
        %% ==================== 3. 概率采样 ====================
        
        function target = sample_task_from_probs(probs_row, max_task_id)
            % sample_task_from_probs "轮盘赌"算法 (Roulette Wheel Selection)。
            % 作用：根据给定的概率向量，随机选择一个索引。概率越大的索引被选中的机会越大。
            
            if isempty(probs_row)
                target = [];
                return;
            end
            total = sum(probs_row);
            % 如果总概率<=0（说明没有可行任务），返回空
            if total <= 0
                target = [];
                return;
            end
            
            % 1. 计算累积概率分布 (CDF)
            % 例如 probs=[0.2, 0.5, 0.3] -> edges=[0.2, 0.7, 1.0]
            edges = cumsum(probs_row);
            
            % 2. 生成一个 0 到 total 之间的随机数
            x = rand() * edges(end);
            
            % 3. 找到第一个大于等于随机数 x 的位置
            % 例如 x=0.4，大于0.2但小于0.7，所以 idx=2
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
        
        %% ==================== 4. 任务执行与时间计算 ====================
        
        function participants = get_participants(SC, task_idx, N, tol)
            % get_participants 从联盟结构 SC 中找出参与特定任务的所有智能体 ID。
            
            if isempty(SC) || task_idx > numel(SC)
                participants = [];
                return;
            end
            
            % SC{task_idx} 是一个 N x K 的矩阵
            % any(..., 2) 检查每一行（每个智能体）是否有任意资源投入 > tol
            % find(...) 返回投入资源大于0的智能体索引
            participants = find(any(SC{task_idx} > tol, 2))';
        end
        
        function t_exec = calc_exec_time(task, R_row, Value_Params, tol)
            % calc_exec_time 计算单个智能体在某任务上的执行时间。
            % 假设：任务由多种资源并行处理，取决于最慢的那种资源。
            
            % 确定哪些资源类型被使用了
            if ~isempty(R_row)
                used = R_row > tol;
            else
                used = true(1, Value_Params.K); % 如果未指定分配，假设全用
            end
            
            if isfield(task, 'duration_by_resource')
                % 如果任务定义了每种资源的执行时间
                dur = task.duration_by_resource(:)';
                if isscalar(dur)
                    t_exec = dur; % 单一值，所有资源一样
                else
                    % 截断或对齐维度
                    dur = dur(1:min(numel(dur), Value_Params.K));
                    used = used(1:numel(dur));
                    % 并行模型：时间取决于被使用的资源中，耗时最长的那个 (Max)
                    t_exec = max([dur(used), 0]);
                end
            elseif isfield(task, 'duration')
                t_exec = task.duration; % 固定时长
            else
                t_exec = 1.0; % 默认值
            end
        end
        
        function t_exec = calc_coalition_exec_time(SC, task_idx, task, Value_Params, tol)
            % calc_coalition_exec_time 计算整个联盟完成任务的时间。
            % 逻辑：所有参与者并行工作，任务完成时间取决于最慢的那个参与者（或最慢的资源环节）。
            
            alloc = SC{task_idx}; % 获取该任务的资源分配矩阵 (N x K)
            exec_times = [];
            
            % 遍历所有智能体
            for i = 1:Value_Params.N
                % 如果智能体 i 参与了任务
                if any(alloc(i, :) > tol)
                    % 计算该智能体贡献部分的执行时间
                    exec_times = [exec_times, OCFUtils.calc_exec_time(task, alloc(i, :), Value_Params, tol)]; %#ok<AGROW>
                end
            end
            % 取最大值作为联盟总耗时（木桶短板效应，或者是必须等所有人干完）
            t_exec = max([exec_times, 0]);
        end
        
        %% ==================== 5. 资源需求估算 (分位数法) ====================
        
        function demand = calculate_demand_quantile(belief, task_type_demands, confidence)
            % calculate_demand_quantile 智能体基于不确定性信念估算任务需求。
            % 核心思想：
            %   - 如果我很确定任务是某种类型（置信度高），就按那种类型准备资源。
            %   - 如果我不确定（信念分散），为了保险起见，我按“分位数”准备资源，
            %     即保证有 confidence% 的概率资源是够用的。
            
            if nargin < 3
                error('calculate_demand_quantile:NotEnoughInputs', '需要3个输入参数');
            end
            
            [num_types, K] = size(task_type_demands);
            belief = belief(:).'; % 确保信念是行向量
            
            demand = zeros(1, K);
            
            % 策略 1：高确定性 (High Confidence)
            % 如果某种类型的概率已经超过了设定的阈值，直接认为就是这种类型
            if max(belief) >= confidence
                [~, most_likely_type] = max(belief);
                demand = ceil(task_type_demands(most_likely_type, :));
                return;
            end
            
            % 策略 2：低确定性 (分位数/风险规避)
            % 对每种资源分别计算：我要准备多少资源，才能覆盖 confidence% 的可能性？
            for r = 1:K
                demands_r = task_type_demands(:, r); % 获取该资源在所有类型下的需求
                [sorted_demands, idx] = sort(demands_r); % 从小到大排序
                sorted_belief = belief(idx);             % 对应的概率
                
                % 计算累积概率分布
                cumulative_prob = cumsum(sorted_belief);
                
                % 找到第一个累积概率 >= confidence 的位置
                threshold_idx = find(cumulative_prob >= confidence, 1);
                if isempty(threshold_idx)
                    threshold_idx = num_types;
                end
                
                % 选定该需求量
                demand(r) = sorted_demands(threshold_idx);
            end
            demand = ceil(demand); % 向上取整，保证资源量是整数
        end
        
        %% ==================== 6. 统计学工具 (Dirichlet分布) ====================
        
        function r = drchrnd(a, n)
            % drchrnd 生成狄利克雷分布 (Dirichlet Distribution) 的随机样本。
            % 用途：用于初始化或更新信念 (Belief)。信念是一个概率分布向量，和为1。
            % 原理：利用 Gamma 分布生成 Dirichlet 分布。
            %   如果 X_i ~ Gamma(a_i, 1)，那么 Y_i = X_i / sum(X) 服从 Dir(a)。
            
            if nargin < 2 || isempty(n)
                n = 1;
            end
            a = a(:).';
            p = numel(a);
            
            % 1. 生成 Gamma 分布随机数
            r = gamrnd(repmat(a, n, 1), 1, n, p);
            
            % 2. 归一化，使每一行的和为 1
            r = r ./ sum(r, 2);
        end
        
        %% ==================== 7. 效用与完成度计算 ====================
        
        function r_n = calc_resource_contribution_ratio(SC_m, agent_idx, member_indices)
            % calc_resource_contribution_ratio 计算贡献比率。
            % 这里的"贡献"是按向量范数 (Norm) 计算的。
            % 贡献比 = (我投入资源的模长) / (联盟所有成员投入资源的模长之和)
            
            A_n = norm(SC_m(agent_idx, :)); % 当前智能体的投入量
            
            total_norm = 0;
            for i = 1:numel(member_indices)
                member_id = member_indices(i);
                total_norm = total_norm + norm(SC_m(member_id, :));
            end
            
            if total_norm > 1e-9
                r_n = A_n / total_norm;
            else
                % 如果总投入为0，平分贡献
                r_n = 1 / max(numel(member_indices), 1);
            end
        end
        
        function D_C = calc_task_completion_degree(allocated_resources, task_demand, K)
            % calc_task_completion_degree 计算任务完成度 D_C (0 到 1)。
            % 这是一个核心指标，衡量分配的资源在多大程度上满足了需求。
            % 公式：平均每个维度满足了多少比例。
            
            % 如果输入是矩阵 (N x K)，先求和变成总资源向量 (1 x K)
            if size(allocated_resources, 1) > 1
                allocated = sum(allocated_resources, 1);
            else
                allocated = allocated_resources;
            end
            
            % 维度对齐处理
            if numel(allocated) < K
                allocated = [allocated, zeros(1, K - numel(allocated))];
            end
            if numel(task_demand) < K
                task_demand = [task_demand, zeros(1, K - numel(task_demand))];
            end
            
            % 统计有非零需求的资源类型数量 Z_c
            Z_c = nnz(task_demand > 1e-9);
            if Z_c == 0
                D_C = 1; % 如果没有需求，视为完成
                return;
            end
            
            D_C = 0;
            for k = 1:K
                if task_demand(k) > 1e-9
                    % 计算第 k 种资源的满足率，最高为 1.0 (溢出不加分)
                    ratio = min(allocated(k) / task_demand(k), 1.0);
                    D_C = D_C + ratio;
                end
            end
            % 取平均值
            D_C = D_C / Z_c;
        end
        
        %% ==================== 8. 观测与信念更新 ====================
        
        function [Value_data, summatrix] = collect_observations(Value_data, agents, tasks, Value_Params, curTaskList, summatrix)
            % collect_observations 模拟智能体对任务类型的观测过程。
            % 这是一个仿真函数：根据智能体的探测概率 (detprob)，生成观测结果。
            
            if nargin < 6 || isempty(summatrix)
                summatrix = zeros(Value_Params.M, Value_Params.task_type);
            end
            
            for i = 1:Value_Params.N
                taskIds = curTaskList{i}; % 智能体 i 当前参与的任务
                if isempty(taskIds)
                    continue;
                end
                
                for tIdx = 1:numel(taskIds)
                    taskId = taskIds(tIdx);
                    
                    % 找到任务真实类型对应的索引
                    taskindex = find(tasks(taskId).value == tasks(taskId).WORLD.value, 1);
                    % 找到其他错误类型的索引
                    nontaskindex = find(tasks(taskId).value ~= tasks(taskId).WORLD.value);
                    
                    if isempty(taskindex)
                        continue;
                    end
                    
                    % 进行 obs_times 次观测
                    for m = 1:Value_Params.obs_times
                        r = rand;
                        % 逻辑：随机数 r 小于探测概率，或者没有其他选项时 -> 观测正确
                        if r <= agents(i).detprob || isempty(nontaskindex)
                            Value_data(i).observe(taskId, taskindex) = Value_data(i).observe(taskId, taskindex) + 1;
                        else
                            % 否则 -> 观测错误（随机选一个错误的类型）
                            chosen_idx = nontaskindex(randi(numel(nontaskindex)));
                            Value_data(i).observe(taskId, chosen_idx) = Value_data(i).observe(taskId, chosen_idx) + 1;
                        end
                    end
                end
            end
            
            % 更新全局观测矩阵 (summatrix)
            % 将各智能体的新增观测同步到全局
            for j = 1:Value_Params.M
                for k = 1:Value_Params.task_type
                    for i = 1:Value_Params.N
                        % 累加逻辑：当前总观测 = 全局累积 + (我的当前观测 - 我上次同步时的观测)
                        summatrix(j, k) = summatrix(j, k) + Value_data(i).observe(j, k) - Value_data(i).preobserve(j, k);
                    end
                end
            end
            
            % 将全局观测同步回每个智能体 (实现信息共享)
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
            % update_belief_from_observations 基于狄利克雷共轭先验更新信念。
            % 贝叶斯公式：后验 Alpha = 先验 Alpha + 观测次数
            
            for i = 1:Value_Params.N
                for j = 1:Value_Params.M
                    % 1 + observe: 加 1 是因为 Dirichlet 分布的先验参数通常设为 1 (均匀分布)
                    alpha_params = 1 + Value_data(i).observe(j, 1:Value_Params.task_type);
                    
                    % 使用 drchrnd 从更新后的 Dirichlet 分布中采样，得到新的信念分布
                    Value_data(i).initbelief(j, 1:end) = OCFUtils.drchrnd(alpha_params, 1)';
                end
            end
        end
        
        %% ==================== 9. 随机数控制 ====================
        
        function seed = set_seed(seed)
        % set_seed 统一设置随机数种子，保证实验可复现。
        
        if nargin < 1 || isempty(seed)
            % 如果没提供种子，使用系统时钟生成一个动态种子
            seed = floor(sum(1000 * clock));
        end
        
        rand('seed', seed);   % 设置 rand (均匀分布) 的种子
        randn('seed', seed);  % 设置 randn (正态分布) 的种子
        rng(seed, 'twister'); % 使用现代的 Mersenne Twister 生成器设置 rng
        end
        
        
        function [SC_P, SC_Q, R_agent_P, R_agent_Q] = calc_move_changes(Value_data, agents, Value_Params, cur_task_idx, target_task_idx, agent_col_idx)
        % CALC_MOVE_CHANGES 计算智能体从当前任务移动到目标任务后的状态变化
        %
        % 假设：
        %   这是一个“全额”移动操作。智能体会将所有资源从 cur_task 撤出，
        %   并将其所有资源投入到 target_task 中。
        %
        % 输入：
        %   Value_data      : 包含 SC 和 resources_matrix 的数据结构
        %   agents          : 智能体数组 (用于获取资源能力)
        %   Value_Params    : 全局参数 (M, K 等)
        %   cur_task_idx    : 当前任务 ID (若 > M 则视为 Void/无任务)
        %   target_task_idx : 目标任务 ID (若 > M 则视为 Void/无任务)
        %   agent_col_idx   : 智能体在 SC 矩阵中的列索引 (通常等于 agentID)
        %
        % 输出：
        %   SC_P, R_agent_P : 移动前的状态 (Previous)
        %   SC_Q, R_agent_Q : 移动后的状态 (Query)
        
        %% 1. 准备基础数据
        M = Value_Params.M;
        K = Value_Params.K;
        agentID = Value_data.agentID;
        
        % 获取智能体的完整资源能力 (1 x K)
        raw_res = agents(agentID).resources(:)';
        if length(raw_res) >= K
            agent_res_profile = raw_res(1:K);
        else
            agent_res_profile = [raw_res, zeros(1, K - length(raw_res))];
        end
        
        %% 2. 记录操作前状态 (P - Previous)
        SC_P = Value_data.SC;
        R_agent_P = Value_data.resources_matrix;
        
        %% 3. 构造操作后状态 (Q - Query) - 先复制
        SC_Q = SC_P;
        R_agent_Q = R_agent_P;
        
        %% 4. 执行“撤出” (Leave Current)
        % 如果当前任务是有效任务 (<= M)，则将其资源清零
        if cur_task_idx <= M
            % A. 更新个体资源矩阵
            R_agent_Q(cur_task_idx, :) = 0;
            
            % B. 更新全局联盟结构 SC
            if cur_task_idx <= numel(SC_Q) && ~isempty(SC_Q{cur_task_idx})
                % 确保索引不越界
                if agent_col_idx <= size(SC_Q{cur_task_idx}, 1)
                    SC_Q{cur_task_idx}(agent_col_idx, :) = 0;
                end
            end
        end
        
        %% 5. 执行“加入” (Join Target)
        % 如果目标任务是有效任务 (<= M)，则投入所有资源
        % (如果是 Void 任务 M+1，则不做任何操作，相当于只撤出不加入)
        if target_task_idx <= M
            % A. 更新个体资源矩阵
            R_agent_Q(target_task_idx, :) = agent_res_profile;
            
            % B. 更新全局联盟结构 SC
            if target_task_idx <= numel(SC_Q)
                % 如果该任务的 SC 尚未初始化，则初始化
                if isempty(SC_Q{target_task_idx})
                    SC_Q{target_task_idx} = zeros(Value_Params.N, K);
                end
                
                % 写入资源
                if agent_col_idx <= size(SC_Q{target_task_idx}, 1)
                    SC_Q{target_task_idx}(agent_col_idx, :) = agent_res_profile;
                end
            end
        end
        
        end
    end
end