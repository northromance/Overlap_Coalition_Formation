function [Value_data, history_data]= SA_Value_main(agents,tasks,AddPara,Value_Params)
% SA_Value_main - 基于模拟退火的重叠联盟形成主函数
%
% 输出参数：
%   Value_data    - 最终智能体状态（联盟结构、信念等）
%   history_data  - 历史记录结构体，包含：
%                   .belief(round, agent, task, :) - 每轮每个智能体对每个任务的信念分布
%                   .coalition_structure(round)     - 每轮的联盟结构
%                   .Rcost(round)                   - 每轮的路径成本
%                   .cost_sum(round)                - 每轮的总成本
%                   .net_profit(round)              - 每轮的净收益

%% 初始化智能体数据结构
for i=1:Value_Params.N
    Value_data(i).agentID=agents(i).id;
    Value_data(i).agentIndex=i;
    Value_data(i).iteration=0;%联盟改变次数
    Value_data(i).unif=0;%均匀随机变量
    Value_data(i).coalitionstru=zeros(Value_Params.M+1,Value_Params.N);
    Value_data(i).initbelief=zeros(Value_Params.M+1,Value_Params.task_type);
    
    % 初始化资源分配矩阵 (M×K)
    Value_data(i).resources_matrix = zeros(Value_Params.M, Value_Params.K);
    
    % 新联盟结构矩阵
    Value_data(i).SC = cell(Value_Params.M, 1);      % 资源联盟结构cell
    for m = 1:Value_Params.M
        Value_data(i).SC{m} = zeros(Value_Params.N, Value_Params.K);  % 任务m的N×K资源分配矩阵
        % 将当前智能体的资源分配到SC对应行
        Value_data(i).SC{m}(i, :) = Value_data(i).resources_matrix(m, :);
    end
    Value_data(i).other = cell(Value_Params.N, 1);   % 存储其他智能体信念
end

%% 初始化void任务（所有智能体初始未分配）
for k=1: Value_Params.N
    for j=1:Value_Params.M+1
        if j==Value_Params.M+1                       % void任务（第M+1行）
            for i=1:Value_Params.N
                Value_data(k).coalitionstru(j,i)=agents(i).id;  % 所有智能体放入void
            end
        end
    end
end

%% 初始化信念分布（均匀分布）
for i=1:Value_Params.N
    for j=1:Value_Params.M
        Value_data(i).initbelief(j,1:end)=ones(Value_Params.task_type,1)/Value_Params.task_type;  % 均匀先验信念
    end
end
% 初始化认为其他机器人的信念值
for i=1:Value_Params.N
    for j = 1:Value_Params.N
        Value_data(i).other{j}.initbelief = Value_data(j).initbelief;  % 智能体j的信念分布
    end
end

%% 初始化观测矩阵
for i=1:Value_Params.N
    for j=1:Value_Params.M
        for k=1:Value_Params.task_type
            Value_data(i).observe(j,k)=0;        % 当前观测计数
            Value_data(i).preobserve(j,k)=0;     % 前次观测计数
            summatrix(j,k)=0;                    % 全局观测累计
        end
    end
end


for i=1:Value_Params.N
    Value_data(i).resources = agents(i).resources;  % 赋予智能体资源
end

%% 初始化历史记录结构体
% 结构说明：按轮次组织数据
%   - history_data.rounds(counter).agents(i).belief(j,:) - 第counter轮，智能体i对任务j的信念
%   - history_data.rounds(counter).coalition_structure    - 第counter轮的联盟结构
%   - history_data.rounds(counter).Rcost                  - 第counter轮的路径成本
%   - history_data.rounds(counter).cost_sum               - 第counter轮的总成本
%   - history_data.rounds(counter).net_profit             - 第counter轮的净收益

% 预分配结构体数组
for round = 1:Value_Params.num_rounds
    for i = 1:Value_Params.N
        history_data.rounds(round).agents(i).belief = zeros(Value_Params.M, Value_Params.task_type);
        history_data.rounds(round).agents(i).observations = zeros(Value_Params.M, Value_Params.task_type);
        history_data.rounds(round).agents(i).quantile_demand = zeros(Value_Params.M, Value_Params.K);  % 分位数需求
    end
    history_data.rounds(round).coalition_structure = [];
    history_data.rounds(round).SC = [];  % 资源联盟结构
    history_data.rounds(round).task_utilities = zeros(Value_Params.M, 1);  % 每个任务的联盟效用
    history_data.rounds(round).Rcost = 0;
    history_data.rounds(round).cost_sum = 0;
    history_data.rounds(round).net_profit = 0;
end

%% 主循环：游戏迭代
for counter=1:Value_Params.num_rounds
    %% 记录当前轮次的信念和观测次数到历史记录
    for i=1:Value_Params.N
        history_data.rounds(counter).agents(i).belief = Value_data(i).initbelief(1:Value_Params.M, :);
        history_data.rounds(counter).agents(i).observations = Value_data(i).observe(1:Value_Params.M, :);
        
        % 记录分位数法计算的资源需求
        if isfield(Value_Params, 'resource_confidence') && Value_Params.resource_confidence > 0
            for j = 1:Value_Params.M
                belief_j = Value_data(i).initbelief(j, :);
                quantile_demand_j = calculate_demand_quantile(belief_j, ...
                    Value_Params.task_type_demands, ...
                    Value_Params.resource_confidence);
                history_data.rounds(counter).agents(i).quantile_demand(j, :) = quantile_demand_j;
            end
        end
    end
    
    % SA迭代初始化
    T=1;                                  % 迭代计数
    lastTime=T-1;                         % 上次时间
    previous_SC = Value_data(1).SC;       % 前次资源联盟结构
    k_stable = 0;                         % 稳定计数
    doneflag = 0;                         % 收敛标志
    
    
    %% SA主循环
    while(doneflag == 0)
        incremental = zeros(1, Value_Params.N);  % 各智能体效用增量
        
        % 计算已分配资源和缺口
        
        % 顺序遍历各智能体进行联盟优化
        for ii = 1:Value_Params.N
            % 计算已分配资源和缺口
            
            % 计算已经分配的资源和剩余资源的缺口
            [allocated_resources, resource_gap] = calc_gaps(Value_data(ii), agents, tasks, Value_Params);
            
            % 重叠联盟形成
            [inc_ii, Value_data_ii] = Overlap_Coalition_Formation(agents, tasks, Value_data(ii), Value_Params,counter,AddPara, allocated_resources, resource_gap);  % 联盟形成
            incremental(ii) = inc_ii;  % 记录效用增量
            
            
            % 传递联盟结构给下一智能体
            if ii < Value_Params.N
                Value_data(ii + 1).coalitionstru = Value_data_ii.coalitionstru;  % 传递成员结构
                Value_data(ii + 1).SC = Value_data_ii.SC;                        % 传递资源分配
            end
        end
        
        % SA温度衰减
        Value_Params.Temperature = Value_Params.alpha * Value_Params.Temperature;  % 温度退火
        
        % 获取最终联盟结构
        final_SC = Value_data(Value_Params.N).SC;                      % 最终资源分配
        final_coalitionstru = Value_data(Value_Params.N).coalitionstru;  % 最终成员结构
        T = T + 1;                                                      % 迭代计数+1
        
        % 收敛性检测
        if isequal(previous_SC, final_SC)
            k_stable = k_stable + 1;  % 结构未变，稳定计数+1
        else
            k_stable = 0;             % 结构改变，重置计数
        end
        
        % 判断收敛条件
        if k_stable >= Value_Params.max_stable_iterations || Value_Params.Temperature < Value_Params.Tmin
            disp('Convergence detected: Coalition structure has stabilized for multiple iterations.');
            doneflag = 1;  % 设置收敛标志
        end
        
        previous_SC = final_SC;  % 保存当前SC用于下轮对比
        
        % 同步全局联盟结构
        for ii = 1:Value_Params.N
            Value_data(ii).coalitionstru = final_coalitionstru;  % 同步成员结构
            Value_data(ii).SC = final_SC;                        % 同步资源分配
        end
    end
    
    %% 记录本轮联盟结构
    history_data.rounds(counter).coalition_structure = final_coalitionstru;
    history_data.rounds(counter).SC = final_SC;  % 保存资源联盟结构
    
    %% 计算并记录每个任务的联盟效用
    task_utilities = calculate_coalition_utilities(final_SC, agents, tasks, Value_Params, Value_data);
    history_data.rounds(counter).task_utilities = task_utilities;
    
    %% 计算并记录每个任务的完成度 D_C（基于真实需求）
    history_data.rounds(counter).task_completion = zeros(Value_Params.M, 1);
    for m = 1:Value_Params.M
        % 计算任务m的完成度D_C
        % 获取参与该任务的成员
        member_idx = find(final_coalitionstru(m, :) ~= 0);
        
        if ~isempty(member_idx)
            % 使用任务的真实资源需求（而非智能体的估计需求）
            actual_demand = tasks(m).resource_demand;
            
            % 计算D_C
            Z_c = nnz(actual_demand > 1e-9);
            if Z_c > 0
                D_C = 0;
                for j = 1:Value_Params.K
                    actual_R_j_m = actual_demand(j);
                    if actual_R_j_m > 1e-9
                        % 从SC中获取分配的资源总量
                        total_allocated_j = sum(final_SC{m}(:, j));
                        % 单个资源类型的完成度，超过需求则截断到1.0
                        resource_ratio = min(total_allocated_j / actual_R_j_m, 1.0);
                        D_C = D_C + resource_ratio;
                    end
                end
                D_C = D_C / Z_c;
                history_data.rounds(counter).task_completion(m) = D_C;
            end
        end
    end
    
    %% 提取各智能体参与的任务集合
    curTaskList = cell(1, Value_Params.N);
    for i = 1:Value_Params.N
        curTaskList{i} = find(final_coalitionstru(1:Value_Params.M, i) ~= 0);
    end
    
    %% 记录观测（每个参与任务各采样obs_times次）
    for i = 1:Value_Params.N
        taskIds = curTaskList{i};
        if isempty(taskIds)
            continue; % 该智能体本轮未参与任何真实任务(只在void)，不产生观测
        end
        
        for tIdx = 1:numel(taskIds)
            taskId = taskIds(tIdx);
            
            % 真实价值在候选集中的索引(1..3)
            taskindex = find(tasks(taskId).value == tasks(taskId).WORLD.value);
            % 非真实价值的索引(长度=2)
            nontaskindex = find(tasks(taskId).value ~= tasks(taskId).WORLD.value);
            
            for m = 1:Value_Params.obs_times
                % 观测模型：正确检测概率=detprob，误检均匀分布到其他类别
                r = rand;
                if r <= agents(i).detprob
                    % 正确检测
                    Value_data(i).observe(taskId, taskindex) = Value_data(i).observe(taskId, taskindex) + 1;
                else
                    % 误检：均匀随机选择一个非真实类别（50%-50%）
                    chosen_idx = nontaskindex(randi(2));
                    Value_data(i).observe(taskId, chosen_idx) = Value_data(i).observe(taskId, chosen_idx) + 1;
                end
            end
        end
    end
    
    % 聚合所有智能体的新观测
    for j=1:Value_Params.M
        for k=1:Value_Params.task_type
            for i=1:Value_Params.N
                summatrix(j,k)=summatrix(j,k)+ Value_data(i).observe(j,  k)-Value_data(i).preobserve(j,  k);  % 累计新观测
            end
        end
    end
    
    % 同步观测给所有智能体

    for i=1:Value_Params.N
        for j=1:Value_Params.M
            for k=1:Value_Params.task_type
                Value_data(i).preobserve(j,k)= summatrix(j,k);  % 更新前次观测
                Value_data(i).observe(j,  k)= summatrix(j,k);   % 更新当前观测
            end
        end
    end
    
    %% 根据观测更新信念（Dirichlet后验）
    for i=1:Value_Params.N
        for j=1:Value_Params.M
            alpha_params = ones(1, Value_Params.task_type);
            for k=1:Value_Params.task_type
                alpha_params(k) = 1 + Value_data(i).observe(j,k);
            end
            Value_data(i).initbelief(j,1:end)=drchrnd(alpha_params,1)';  % Dirichlet采样
        end
    end
    
    %% 信念广播：同步各智能体的信念到other中
    for i = 1:Value_Params.N
        for j = 1:Value_Params.N
            Value_data(i).other{j}.initbelief = Value_data(j).initbelief;  % 智能体i更新其对智能体j信念的认知
        end
    end
    
end
end
