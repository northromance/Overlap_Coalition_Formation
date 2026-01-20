function [Value_data, history_data]= SA_Value_main(agents,tasks,AddPara,Value_Params)
% SA_Value_main - 基于模拟退火的重叠联盟形成主函数
%
% 功能描述：
%   这是算法的顶层入口。它管理整个重叠联盟形成的生命周期，包括：
%   1. 初始化智能体状态、信念和资源分配。
%   2. 多轮次迭代（num_rounds）：每一轮代表一次完整的任务分配尝试。
%   3. 模拟退火（SA）内循环：在每一轮中，通过升温/降温和随机扰动，寻找最优联盟结构。
%   4. 信念更新：根据分配结果进行观测，更新对任务类型的认知。
%   5. 历史记录：记录每一轮的详细数据以便分析。
%
% 输入：
%   agents       - 智能体结构体数组（物理属性、位置等）
%   tasks        - 任务结构体数组（位置、真实需求等）
%   AddPara      - 附加控制参数
%   Value_Params - 算法全局参数（N, M, K, 温度, 轮数等）
%
% 输出：
%   Value_data    - 最终时刻的所有智能体状态
%   history_data  - 包含每轮详细数据的历史记录结构体

%% ==================== 1. 初始化阶段 ====================

%% 初始化智能体数据结构
for i=1:Value_Params.N
    Value_data(i).agentID=agents(i).id;
    Value_data(i).agentIndex=i;
    Value_data(i).iteration=0;       % 记录该智能体改变联盟的次数
    Value_data(i).unif=0;            % 用于随机决策的变量
    Value_data(i).coalitionstru=zeros(Value_Params.M+1,Value_Params.N); % 成员矩阵 (任务x智能体)
    Value_data(i).initbelief=zeros(Value_Params.M+1,Value_Params.task_type); % 信念矩阵
    
    % 初始化资源分配矩阵 (M×K): 记录该智能体对每个任务投入的具体资源量
    Value_data(i).resources_matrix = zeros(Value_Params.M, Value_Params.K);
    
    % 新联盟结构矩阵 (SC): 这是一个 Cell 数组，每个 Cell 存储一个任务的 (N×K) 分配详情
    % SC{m}(n, k) 表示智能体 n 在任务 m 上投入的第 k 种资源量
    Value_data(i).SC = cell(Value_Params.M, 1);      
    for m = 1:Value_Params.M
        Value_data(i).SC{m} = zeros(Value_Params.N, Value_Params.K);  
        % 初始时资源分配为0
        Value_data(i).SC{m}(i, :) = Value_data(i).resources_matrix(m, :);
    end
    Value_data(i).other = cell(Value_Params.N, 1);   % 用于存储它所认为的“队友的信念”
    
    % 任务执行序列与时间跟踪结构 (用于后续的同步机制计算)
    Value_data(i).task_schedule = struct();
    Value_data(i).task_schedule.task_sequence = [];           % 任务执行顺序
    Value_data(i).task_schedule.arrival_times = [];           % 到达时刻
    Value_data(i).task_schedule.start_times = [];             % 同步后的开始时刻
    Value_data(i).task_schedule.execution_times = [];         % 个人执行时长
    Value_data(i).task_schedule.completion_times = [];        % 完工时刻
    Value_data(i).task_schedule.total_flight_time = 0;        
    Value_data(i).task_schedule.total_execution_time = 0;     
    Value_data(i).task_schedule.total_energy = 0;             
end

%% 初始化void任务（第 M+1 个任务）
% void 任务代表“空闲”或“未分配”。初始状态下，所有智能体都在 void 任务中。
for k=1: Value_Params.N
    for j=1:Value_Params.M+1
        if j==Value_Params.M+1                       
            for i=1:Value_Params.N
                Value_data(k).coalitionstru(j,i)=agents(i).id;  
            end
        end
    end
end

%% 初始化信念分布（均匀先验）
% 初始时，智能体不知道任务类型，假设所有类型的概率相等 (1/TypeNum)
for i=1:Value_Params.N
    for j=1:Value_Params.M
        Value_data(i).initbelief(j,1:end)=ones(Value_Params.task_type,1)/Value_Params.task_type;  
    end
end

% 初始化邻居信念
% 每个智能体维护一份它认为其他智能体拥有的信念（用于通信或共识）
for i=1:Value_Params.N
    for j = 1:Value_Params.N
        Value_data(i).other{j}.initbelief = Value_data(j).initbelief;  
    end
end

%% 初始化观测矩阵
% 用于贝叶斯更新：记录在任务 j 上观测到属于类型 k 的次数
for i=1:Value_Params.N
    for j=1:Value_Params.M
        for k=1:Value_Params.task_type
            Value_data(i).observe(j,k)=0;        % 当前轮的观测计数
            Value_data(i).preobserve(j,k)=0;     % 累计的历史观测计数
            summatrix(j,k)=0;                    % 全局观测汇总
        end
    end
end

% 赋予智能体初始物理资源
for i=1:Value_Params.N
    Value_data(i).resources = agents(i).resources;  
end

%% 初始化历史记录结构体 (预分配内存以提高速度)
for round = 1:Value_Params.num_rounds 
    for i = 1:Value_Params.N  
        % 记录信念演变
        history_data.rounds(round).agents(i).belief = zeros(Value_Params.M, Value_Params.task_type);  
        history_data.rounds(round).agents(i).observations = zeros(Value_Params.M, Value_Params.task_type);  
        % 记录基于分位数法计算出的“估计需求”
        history_data.rounds(round).agents(i).quantile_demand = zeros(Value_Params.M, Value_Params.K);  
        % 记录时间表
        history_data.rounds(round).agents(i).task_schedule = struct();  
        % ... (初始化 task_schedule 内部字段，略)
    end
    % 记录每一轮最终的联盟结构
    history_data.rounds(round).coalition_structure = [];  
    history_data.rounds(round).SC = [];  
    history_data.rounds(round).task_utilities = zeros(Value_Params.M, 1);  
    % 记录经济指标
    history_data.rounds(round).Rcost = 0;      % 资源成本
    history_data.rounds(round).cost_sum = 0;   % 总成本 (包含移动等)
    history_data.rounds(round).net_profit = 0; % 净收益
end


%% ==================== 2. 主循环：多轮博弈迭代 ====================
% counter 代表“第几轮”。每轮结束后，智能体会更新信念，下一轮基于新信念重新分配。
for counter=1:Value_Params.num_rounds
    
    %% 2.1 记录当前轮次的初始状态
    for i=1:Value_Params.N
        % 记录当前的信念
        history_data.rounds(counter).agents(i).belief = Value_data(i).initbelief(1:Value_Params.M, :);
        history_data.rounds(counter).agents(i).observations = Value_data(i).observe(1:Value_Params.M, :);
        
        % 计算并记录当前的“估计需求” (Quantile Demand)
        % 这是智能体决策的依据：它不使用真实需求，而是根据信念和置信度估算需求
        if isfield(Value_Params, 'resource_confidence') && Value_Params.resource_confidence > 0
            for j = 1:Value_Params.M
                belief_j = Value_data(i).initbelief(j, :);
                quantile_demand_j = OCFUtils.calculate_demand_quantile(belief_j, ...
                    Value_Params.task_type_demands, ...
                    Value_Params.resource_confidence);
                history_data.rounds(counter).agents(i).quantile_demand(j, :) = quantile_demand_j;
            end
        end
    end
    
    %% 2.2 SA (模拟退火) 迭代初始化
    T=1;                                  % 迭代步数
    lastTime=T-1;                         
    previous_SC = Value_data(1).SC;       % 记录上一次的联盟结构用于检测收敛
    k_stable = 0;                         % 稳定计数器 (连续多少次结构没变)
    doneflag = 0;                         % 收敛标志位
    
    
    %% ==================== 3. SA 内循环：联盟形成 ====================
    % 在当前信念下，寻找最优的联盟结构
    while(doneflag == 0)
        
        % --- 3.1 顺序博弈：智能体逐个决策 ---
        % 这种顺序更新机制避免了同时决策导致的冲突
        for ii = 1:Value_Params.N
            % 调用核心函数：重叠联盟形成
            % 智能体 ii 根据当前状态，尝试加入新任务或离开旧任务以提升效用
            [Value_data_ii] = Overlap_Coalition_Formation(agents, tasks, Value_data(ii), Value_Params); 
            
            % --- 3.2 状态传递 ---
            % 将智能体 ii 更新后的全局联盟结构传递给下一个智能体 (ii+1)
            % 这样 ii+1 决策时看到的是包含 ii 最新变动的环境
            if ii < Value_Params.N
                Value_data(ii + 1).coalitionstru = Value_data_ii.coalitionstru;  
                Value_data(ii + 1).SC = Value_data_ii.SC;                        
            end
        end
        
        % --- 3.3 SA 温度衰减 ---
        % 降低温度，减少接受劣解的概率 (Exploration -> Exploitation)
        Value_Params.Temperature = Value_Params.alpha * Value_Params.Temperature;  
        
        % 获取本轮迭代结束后的最终结构
        final_SC = Value_data(Value_Params.N).SC;                      
        final_coalitionstru = Value_data(Value_Params.N).coalitionstru;  
        T = T + 1;                                                      
        
        % --- 3.4 收敛性检测 ---
        % 如果联盟结构 (SC) 与上一次迭代完全一致，则稳定计数 +1
        if isequal(previous_SC, final_SC)
            k_stable = k_stable + 1;  
        else
            k_stable = 0;             % 结构发生变化，重置计数
        end
        
        % 判断是否收敛：
        % 条件1: 结构连续稳定 max_stable_iterations 次
        % 条件2: 温度降到了最低阈值 Tmin
        if k_stable >= Value_Params.max_stable_iterations || Value_Params.Temperature < Value_Params.Tmin
            disp('Convergence detected: Coalition structure has stabilized for multiple iterations.');
            doneflag = 1;  % 退出 SA 循环
        end
        
        previous_SC = final_SC;  % 更新前次结构
        
        % --- 3.5 同步全局状态 ---
        % 确保所有智能体的本地 Value_data 都更新为最新的一致结构
        for ii = 1:Value_Params.N
            Value_data(ii).coalitionstru = final_coalitionstru;  
            Value_data(ii).SC = final_SC;                        
        end
        
        % --- 3.6 更新任务调度与能耗 ---
        % 根据确定下来的 SC，计算具体的路径、等待时间、同步时间等
        % 这是计算 Net Profit (净收益) 的基础
        Value_data = update_task_schedule(Value_data, agents, tasks, Value_Params);
    end
    
    %% ==================== 4. 结果记录与评估 ====================
    
    %% 4.1 记录本轮最终的联盟结构
    history_data.rounds(counter).coalition_structure = final_coalitionstru;
    history_data.rounds(counter).SC = final_SC;  
    
    %% 4.2 记录每个智能体的调度详情
    for i = 1:Value_Params.N
        history_data.rounds(counter).agents(i).task_schedule = Value_data(i).task_schedule;
    end
    
    %% 4.3 计算联盟效用 (Utility)
    % 基于当前的分配，计算每个联盟产生的总价值
    task_utilities = calculate_coalition_utilities(final_SC, agents, tasks, Value_Params, Value_data);
    history_data.rounds(counter).task_utilities = task_utilities;
    
    %% 4.4 计算任务完成度 D_C (基于真实需求)
    % 注意：虽然分配时用的是估计需求，但评估结果时必须对比真实需求 (Ground Truth)
    history_data.rounds(counter).task_completion = zeros(Value_Params.M, 1);
    for m = 1:Value_Params.M
        member_idx = find(final_coalitionstru(m, :) ~= 0);
        
        if ~isempty(member_idx)
            % 获取 Ground Truth (真实需求)
            actual_demand = tasks(m).resource_demand;
            
            % 只有当真实需求 > 0 时才计算完成度
            Z_c = nnz(actual_demand > 1e-9);
            if Z_c > 0
                % 计算实际完成度
                D_C = OCFUtils.calc_task_completion_degree(final_SC{m}, actual_demand, Value_Params.K);
                history_data.rounds(counter).task_completion(m) = D_C;
            end
        end
    end
    
    %% 4.5 提取各智能体的任务列表 (用于后续观测)
    curTaskList = cell(1, Value_Params.N);
    for i = 1:Value_Params.N
        curTaskList{i} = find(final_coalitionstru(1:Value_Params.M, i) ~= 0);
    end
    
    %% 4.6 观测与信念更新 (Bayesian Update)
    % 1. 收集观测：智能体在参与任务时，会观测到任务的某种特征，从而推断类型
    [Value_data, summatrix] = OCFUtils.collect_observations(Value_data, agents, tasks, Value_Params, curTaskList, summatrix);
    % 2. 更新信念：基于狄利克雷分布更新后验概率
    Value_data = OCFUtils.update_belief_from_observations(Value_data, Value_Params);
    
    %% 4.7 记录本轮的总价值
    % 总完成价值 = sum(任务名义价值 * 实际完成度)
    task_values = arrayfun(@(t) t.value, tasks);
    completion_vec = history_data.rounds(counter).task_completion(:);
    history_data.rounds(counter).total_completed_value = sum(task_values(:) .* completion_vec);
    history_data.rounds(counter).total_value_possible = sum(task_values);
    
    %% 4.8 信念广播 (Consensus)
    % 简单的全连接通信：每个智能体将自己的最新信念同步给其他智能体
    for i = 1:Value_Params.N
        for j = 1:Value_Params.N
            Value_data(i).other{j}.initbelief = Value_data(j).initbelief;  
        end
    end
    
    %% 4.9 汇总历史数据
    % 整理这几轮下来的总价值曲线，便于画图
    total_value_history = zeros(1, Value_Params.num_rounds);
    for rr = 1:Value_Params.num_rounds
        if rr <= numel(history_data.rounds) && isfield(history_data.rounds(rr), 'total_completed_value')
            val = history_data.rounds(rr).total_completed_value;
            if ~isscalar(val)
                val = sum(val(:));
            end
            total_value_history(rr) = val;
        end
    end
    history_data.total_value_history = total_value_history;
    history_data.total_value_possible = sum(arrayfun(@(t) t.value, tasks));
    
end

% 假设 Value_data 是 1xN 的结构体数组
[is_valid, error_log] = check_OCF_consistency(Value_data, agents, Value_Params);

if ~is_consistent
    disp('数据有严重问题，停止后续分析！');
    % 可以打印 logs 查看详情
end





end