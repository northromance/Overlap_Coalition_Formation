classdef WorldSim
    % AgentOps 智能体认知与行为操作类
    % 职责：处理观测数据的收集、全局信息的融合与同步，以及信念的贝叶斯更新。
    
    methods (Static)
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
                    exec_times = [exec_times, WorldSim.calc_exec_time(task, alloc(i, :), Value_Params, tol)]; %#ok<AGROW>
                end
            end
            
            % 整个联盟的耗时 = 所有参与者中的最大耗时
            t_exec = max([exec_times, 0]);
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
        
        
        function [t_fly_total, t_wait_total, t_exec_total, start_times, execution_times, completion_times,mission_end_time] = calc_with_global_sync(...
                agentIdx, myOrderedTasks, agents, tasks, Value_Params, SC, tol)
            % CALC_WITH_GLOBAL_SYNC 计算基于全局同步机制的时间与能耗，并返回详细时间表
            % myOrderedTasks 需要对之前的任务进行优先级排序好
            % 输入：
            %   agentIdx       - 当前计算的智能体ID
            %   myOrderedTasks - 该智能体的任务序列（已按优先级排序）
            %   ... (其他标准参数)
            %
            % 输出：
            %   t_fly_total     - 总飞行时间
            %   t_wait_total    - 总等待时间（含“等到齐”和“等完工”）
            %   t_exec_total    - 总有效执行时间
            %   start_times     - [向量] 每个任务的统一开始时刻
            %   execution_times - [向量] 每个任务的个体有效执行时长
            %   completion_times- [向量] 每个任务的统一结束/离开时刻
            
            %% ========== 参数提取 ==========
            N = Value_Params.N;
            M = Value_Params.M;
            R_agent = OCFUtils.get_agent_resource_matrix(SC, agentIdx, Value_Params);
            
            %% ========== 阶段一：全局状态模拟 (God View) ==========
            % 目的：推演全世界的运行时间表，确定每个任务的“法定开始时间”和“法定结束时间”。
            
            % 1. 初始化虚拟状态
            agent_state = struct('pos', {}, 'ready_time', {});
            for i = 1:N
                agent_state(i).pos = [agents(i).x, agents(i).y];
                agent_state(i).ready_time = 0;
            end
            
            % 2. 全局排序
            all_tasks = 1:M;
            global_order = OCFUtils.sort_tasks_by_priority(all_tasks, tasks);
            
            % 3. 记录全局时间锚点
            task_sync_start = zeros(M, 1);    % 任务 m 的统一开始时刻
            task_coalition_dur = zeros(M, 1); % 任务 m 的联盟总耗时（法定执行时长）
            
            % 4. 模拟推演
            for order_idx = 1:M
                task_id = global_order(order_idx);
                task_pos = [tasks(task_id).x, tasks(task_id).y];
                
                participants = OCFUtils.get_participants(SC, task_id, tol);
                if isempty(participants), continue; end
                
                % --- 计算每个参与者的到达时刻 ---
                arrival_times = zeros(numel(participants), 1);
                for k = 1:numel(participants)
                    p_id = participants(k);
                    v = agents(p_id).vel;
                    
                    dist = norm(task_pos - agent_state(p_id).pos);
                    fly_time = dist / max(v, tol);
                    
                    arrival_times(k) = agent_state(p_id).ready_time + fly_time;
                end
                
                % --- 确定同步开始时间 (木桶效应) ---
                sync_start = max(arrival_times);
                task_sync_start(task_id) = sync_start;
                
                % --- 计算联盟总耗时 ---
                t_coalition = WorldSim.calc_coalition_exec_time(SC, task_id, tasks(task_id), Value_Params, tol);
                task_coalition_dur(task_id) = t_coalition;
                
                % --- 更新参与者状态 (强制同步离开) ---
                for k = 1:numel(participants)
                    p_id = participants(k);
                    agent_state(p_id).pos = task_pos;
                    agent_state(p_id).ready_time = sync_start + t_coalition;
                end
            end
            
            %% ========== 阶段二：计算目标智能体的详细指标 (Agent View) ==========
            
            t_fly_total = 0;
            t_wait_total = 0;
            t_exec_total = 0;
            
            % 初始化详细记录数组
            num_my_tasks = numel(myOrderedTasks);
            start_times = zeros(num_my_tasks, 1);      % 记录开始时刻
            execution_times = zeros(num_my_tasks, 1);  % 记录有效执行时长
            completion_times = zeros(num_my_tasks, 1); % 记录结束/离开时刻
            
            % 重置状态，专门跑一遍 agentIdx 的路径
            curr_pos = [agents(agentIdx).x, agents(agentIdx).y];
            curr_clock = 0;
            v = agents(agentIdx).vel;
            
            for ii = 1:num_my_tasks
                task_id = myOrderedTasks(ii);
                task_pos = [tasks(task_id).x, tasks(task_id).y];
                
                % --- 1. 飞行阶段 ---
                dist = norm(task_pos - curr_pos);
                fly_time = dist / max(v, tol);
                t_fly_total = t_fly_total + fly_time;
                
                my_arrival = curr_clock + fly_time;
                
                % --- 2. 获取全局时间锚点 ---
                sync_start = task_sync_start(task_id);
                coalition_dur = task_coalition_dur(task_id);
                
                % --- 3. 计算“到达等待” ---
                wait_pre_start = max(0, sync_start - my_arrival);
                
                % --- 4. 计算“执行时间” ---
                if ~isempty(SC) && task_id <= numel(SC) && ~isempty(SC{task_id})
                    R_row = SC{task_id}(agentIdx, :);
                else
                    R_row = R_agent(task_id, :);
                end
                my_exec_time = WorldSim.calc_exec_time(tasks(task_id), R_row, Value_Params, tol);
                t_exec_total = t_exec_total + my_exec_time;
                
                % --- 5. 计算“完工等待” ---
                wait_post_exec = max(0, coalition_dur - my_exec_time);
                
                % --- 6. 累加总等待 ---
                t_wait_total = t_wait_total + wait_pre_start + wait_post_exec;
                
                % --- 7. 更新状态前往下一站 ---
                % 离开时刻 = 开始时刻 + 联盟总耗时
                curr_clock = sync_start + coalition_dur;
                curr_pos = task_pos;
                
                % ========== [新增] 详细时间记录 ==========
                start_times(ii) = sync_start;           % 任务统一开始的时间
                execution_times(ii) = my_exec_time;     % 我实际干活的时间
                completion_times(ii) = curr_clock;      % 我离开任务的时间 (含完工等待)
            end
            
            % --- 8. 返回基地的飞行 ---
            return_dist = norm([agents(agentIdx).x, agents(agentIdx).y] - curr_pos);
            return_time = return_dist / max(v, tol); % 计算返航耗时
            
            t_fly_total = t_fly_total + return_time; % 计入总成本
            
            % [新增] 计算最终落地时间
            mission_end_time = curr_clock + return_time;
        end
        
        
        function demand = calculate_demand_quantile(belief, task_type_demands, confidence)
            % CALCULATE_DEMAND_QUANTILE 基于信念分布估算所需的资源量
            %
            % 核心逻辑：
            %   智能体不知道任务的确切类型，只知道属于各类型的概率 (belief)。
            %   为了保证任务成功率，智能体需要准备足够的资源，使得资源“够用”的概率至少达到 confidence。
            %
            % 策略逻辑：
            %   1. 【高确定性捷径】：如果智能体非常确定任务是某一种类型（概率 > confidence），
            %      则直接按照该类型的标准需求携带资源，避免复杂的计算。
            %   2. 【低确定性兜底】：如果智能体犹豫不决（概率分散），则构建需求的累积分布函数 (CDF)，
            %      找到覆盖 confidence 概率所需的最小资源量（即分位数概念）。
            %
            % 输入：
            %   belief            : (1xN double) 任务属于各类型的概率分布向量 [p1, p2, ..., pN]。和应为1。
            %   task_type_demands : (NxK double) N种任务类型对K种资源的需求矩阵。第i行是第i类任务的需求。
            %   confidence        : (double)     置信度阈值 (0~1)，例如 0.95 表示要有95%的把握资源够用。
            %
            % 输出：
            %   demand            : (1xK double) 最终决定的各类资源携带量。
            
            % --- 1. 输入校验 ---
            if nargin < 3
                error('calculate_demand_quantile:NotEnoughInputs', '错误：必须提供 belief, task_type_demands 和 confidence 三个参数');
            end
            
            % --- 2. 数据预处理 ---
            % num_types: 潜在的任务类型数量 (N)
            % K: 资源种类的数量 (例如：燃油、弹药、算力等)
            [num_types, K] = size(task_type_demands);
            
            % 确保 belief 是行向量 (1xN)，方便后续矩阵操作
            belief = belief(:).';
            
            % 初始化输出需求向量
            demand = zeros(1, K);
            
            % --- 3. 策略一：确定性主导 (High Confidence Strategy) ---
            % 目的：计算加速。如果已经“几乎确定”是某种任务，就没必要做复杂的统计学计算。
            % 逻辑：如果某类型的概率 >= 置信度，那只准备该类型的资源就足以满足置信度要求。
            if max(belief) >= confidence
                % 找到概率最大的那个类型索引
                [~, most_likely_type] = max(belief);
                
                % 直接读取该类型的需求作为最终需求
                % ceil: 向上取整，防止物理资源出现小数（如0.5个机器人）
                demand = ceil(task_type_demands(most_likely_type, :));
                return; % 直接结束函数
            end
            
            % --- 4. 策略二：风险规避 (Quantile/CDF Strategy) ---
            % 目的：当不确定性较高时（例如觉得是A类任务概率0.4，B类0.6），需要综合考虑所有可能。
            % 逻辑：对于每一种资源 k，我们要找到一个数值 d，使得 P(实际需求 <= d) >= confidence。
            
            % 遍历每一种资源类型 (列)
            for r = 1:K
                % 4.1 获取当前资源 r 在所有可能任务类型下的需求量
                demands_r = task_type_demands(:, r);
                
                % 4.2 排序：将需求从小到大排列
                % sorted_demands: 排序后的需求值
                % idx: 排序后的索引，用于同步重排对应的概率
                [sorted_demands, idx] = sort(demands_r);
                
                % 4.3 重排概率：让概率与排序后的需求对应
                % 例如：需求为 [10, 5, 20]，概率为 [0.2, 0.3, 0.5]
                % 排序后需求: [5, 10, 20]，对应概率: [0.3, 0.2, 0.5]
                sorted_belief = belief(idx);
                
                % 4.4 计算累积概率 (CDF - Cumulative Distribution Function)
                % 继续上例：cumulative_prob = [0.3, 0.5, 1.0]
                % 含义：需求 <= 5 的概率是 0.3；需求 <= 10 的概率是 0.5；需求 <= 20 的概率是 1.0
                cumulative_prob = cumsum(sorted_belief);
                
                % 4.5 寻找阈值截断点
                % 找到第一个累积概率超过 confidence 的位置
                % 假设 confidence = 0.4，则在 index=2 (对应需求10) 处，累积概率达到 0.5 >= 0.4
                % 这意味着带 10 个单位资源，有 50% 的概率够用（满足 >40% 的要求）
                threshold_idx = find(cumulative_prob >= confidence, 1);
                
                % 4.6 异常处理
                % 如果 confidence 设置为 1.0 或者浮点数误差导致没找到，默认取最大需求（最保守策略）
                if isempty(threshold_idx)
                    threshold_idx = num_types;
                end
                
                % 4.7 赋值
                demand(r) = sorted_demands(threshold_idx);
            end
            
            % --- 5. 最终取整 ---
            % 确保所有资源量为整数（如无人机数量、电池包数量等通常为离散值）
            demand = ceil(demand);
        end
        
        
    end
    
    
    
end