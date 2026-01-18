function [Value_data, history_data] = Huo2025_main(agents, tasks, AddPara, Value_Params)
% =========================================================================
%  函数名称：Value_main
%
%  算法主要功能：
%  ------------------------------------------------------------------------
%  本算法基于多智能体联盟形成（Coalition Formation）与任务值估计机制，
%  完成以下核心流程：
%    1. 初始化 agent 的 belief、联盟结构和观测矩阵。
%    2. 通过迭代过程：每个 agent 根据 belief 选择任务并形成联盟。
%    3. 按通信拓扑 Graph 执行邻居信息共享，更新任务估计。
%    4. 每轮联盟形成后，agent 通过模拟观测更新 Dirichlet belief。
%    5. 计算每轮联盟结构下的成本、收益与净收益。
%    6. 重复多次（counter=1:num_rounds，默认50），用于统计不同联盟的收益表现。
%
%  输入参数：
%  ------------------------------------------------------------------------
%  agents：结构体数组，包含：
%       - id：agent ID
%       - x, y：空间坐标
%       - fuel：燃料单价（决定行动成本）
%       - detprob：观测正确概率
%
%  tasks：结构体数组，包含：
%       - x, y：任务位置
%       - value：任务当前可能值（长度为任务类型数的向量）
%       - WORLD.value：任务真实值（环境设定）
%
%  Graph：通信邻接矩阵（N×N），Graph(i,j)=1 表示 agent i 和 j 可通信
%
%
%  输出参数：
%  ------------------------------------------------------------------------
%  Value_data：包含每个 agent 在各轮迭代中的 belief、观测、联盟结构等信息
%
%  Rcost：联盟中 agent 的行动成本（距离 × fuel）
%
%  cost_sum：50 次联盟形成中，每次的总成本
%
%  net_profit：50 次联盟形成中，每次的（收益 - 成本）
%
%  initial_coalition：第一次联盟形成的联盟成员结构
%
%  注：算法内部会运行多轮 belief 更新、联盟优化和通信，最终输出每轮的成本与收益。
%
% =========================================================================

% 生成全连通的通信图（所有智能体可以相互通信）
Graph = ones(Value_Params.N, Value_Params.N);
task_types = Value_Params.task_type;  % 任务类型数量（统一由参数控制）
if isempty(task_types)
    task_types = numel(tasks(1).WORLD.value);
end

for i=1:Value_Params.N %包括agent标号，索引以及初始联盟结构
    Value_data(i).agentID=agents(i).id;
    Value_data(i).agentIndex=i;
    Value_data(i).iteration=0;%联盟改变次数
    Value_data(i).unif=0;%均匀随机变量
    Value_data(i).coalitionstru=zeros(Value_Params.M+1,Value_Params.N);
    Value_data(i).initbelief=zeros(Value_Params.M+1,task_types);
    Value_data(i).observe = zeros(Value_Params.M, task_types);
    Value_data(i).preobserve = zeros(Value_Params.M, task_types);
end
summatrix = zeros(Value_Params.M, task_types);  % 汇总观测矩阵
total_value_history = zeros(1, Value_Params.num_rounds);  % 每轮完成价值
total_value_possible = sum(arrayfun(@(t) t.value, tasks));  % 所有任务的总潜在价值

for k=1: Value_Params.N   %所有agents放在void 任务中
    for j=1:Value_Params.M+1
        if j==Value_Params.M+1
            for i=1:Value_Params.N
                Value_data(k).coalitionstru(j,i)=agents(i).id;
            end
        end
    end
end

for i=1:Value_Params.N %每一个agent对所有任务的任务值持有一个初始belief
    for j=1:Value_Params.M
        %Value_data(i).initbelief(j,1:end)=OCFUtils.drchrnd(ones(1, task_types),1)';
        Value_data(i).initbelief(j,1:end)=ones(1, task_types)/task_types;
    end
end

%此处应该有个for/which循环

for counter=1:Value_Params.num_rounds
    for i=1:Value_Params.N   %一会要改回来
        for j=1:Value_Params.M
            Value_data(i).tasks(j).prob(counter,:)=Value_data(i).initbelief(j,1:end);
        end
    end
    
    T=1;   %迭代次数
    lastTime=T-1;
    doneflag=0;   %初始标志位0，收敛标志位为1
    
    while( doneflag==0)
        
        %communication
        
        %所有agents选择自主任务
        for ii=1:Value_Params.N
            [incremental(ii),curnumberrow(ii),Value_data(ii)]=Value_order(agents, tasks, Value_data(ii), Value_Params);
            incremental(ii);
        end
        
        if (length(find(incremental==0))==Value_Params.N)
            lastTime= lastTime;
        else
            lastTime=T;
        end
        % length(find(incremental==0))
        Value_data=Value_communication(agents, tasks, Value_data, Value_Params,Graph);%邻居agent间彼此通信
        
        %convergence check
        
        if (T-lastTime>2)
            %     if (T==100)
            doneflag=1;
        else
            T=T+1;
        end
    end
    
    if counter==1
        for j=1:Value_Params.M
            initial_coalition(j).member=find(Value_data(1).coalitionstru(j,:)~=0);
        end
    end
    
    % 记录一次联盟形成后观测次数（统一函数）
    curTaskList = cell(1, Value_Params.N);
    for i=1:Value_Params.N
        if curnumberrow(i)~=Value_Params.M+1
            curTaskList{i} = curnumberrow(i);
        else
            curTaskList{i} = [];
        end
    end
    [Value_data, summatrix] = OCFUtils.collect_observations(Value_data, agents, tasks, Value_Params, curTaskList, summatrix);
    Value_data = OCFUtils.update_belief_from_observations(Value_data, Value_Params);

    % 计算基于资源分配的联盟效用
    Rcost = zeros(Value_Params.M, Value_Params.N);
    coalition_utility = zeros(1, Value_Params.M);  % 每个联盟的效用
    
    % 获取资源类型数量K
    if isfield(Value_Params, 'K')
        K = Value_Params.K;
    elseif isfield(agents(1), 'resources')
        K = length(agents(1).resources);
    else
        K = 6;  % 默认值
    end
    
    eps_val = 1e-9;  % 数值容差

    total_completed_value = 0;  % 本轮完成价值累计
    for j = 1:Value_Params.M
        lianmeng(j).member = find(Value_data(1).coalitionstru(j,:) ~= 0);
        
        if isempty(lianmeng(j).member)
            coalition_utility(j) = 0;
            continue;
        end
        
        % 获取联盟成员的真实agent ID
        member_ids = [];
        for idx = 1:length(lianmeng(j).member)
            col_idx = lianmeng(j).member(idx);
            agent_id = Value_data(1).coalitionstru(j, col_idx);
            if agent_id > 0 && agent_id <= length(agents)
                member_ids = [member_ids, agent_id];
            end
        end
        
        if isempty(member_ids)
            coalition_utility(j) = 0;
            continue;
        end
        
        % 获取任务的资源需求
        if isfield(tasks(j), 'resource_demand')
            demand = tasks(j).resource_demand(:)';
            if length(demand) < K
                demand = [demand, zeros(1, K - length(demand))];
            end
        else
            demand = ones(1, K) * 2;  % 默认需求
        end
        
        % 计算联盟总资源贡献
        total_resources = zeros(1, K);
        for i = 1:length(member_ids)
            member_id = member_ids(i);
            if isfield(agents(member_id), 'resources')
                member_res = agents(member_id).resources(:)';
                if length(member_res) >= K
                    total_resources = total_resources + member_res(1:K);
                elseif ~isempty(member_res)
                    total_resources(1:length(member_res)) = total_resources(1:length(member_res)) + member_res;
                end
            end
        end
        
        % 计算资源完成度 D_C
        % 使用通用函数计算任务完成度
        D_C = OCFUtils.calc_task_completion_degree(total_resources, demand, K);
        
        % 计算期望价值 V_C
        values = tasks(j).WORLD.value;
        tlen = min(task_types, numel(values));
        V_C = sum(values(1:tlen) .* Value_data(1).initbelief(j,1:tlen));
        
        % 计算联盟收益 = V_C × D_C
        coalition_revenue = V_C * D_C;

        % 计算等待/飞行/执行成本，参考 Value_utility 中的模型
        % 1) 各成员到达时间（单程，不返回）
        arrival_times = zeros(1, numel(member_ids));
        for idx = 1:numel(member_ids)
            mid = member_ids(idx);
            start_xy = [agents(mid).x, agents(mid).y];
            one_way_dist = OCFUtils.compute_route_distance(start_xy, j, tasks, false);
            v_mid = eps_val;
            if isfield(agents(mid), 'vel') && ~isempty(agents(mid).vel)
                v_mid = max(agents(mid).vel, eps_val);
            end
            arrival_times(idx) = one_way_dist / v_mid;
        end
        sync_start = max(arrival_times);

        % 2) 任务执行时间：取需求中最耗时资源（并行执行模型）
        task_exec_time = 0;
        if isfield(tasks(j), 'duration_by_resource') && ~isempty(tasks(j).duration_by_resource)
            task_exec_time = max(tasks(j).duration_by_resource(:));
        elseif isfield(tasks(j), 'duration')
            task_exec_time = tasks(j).duration;
        end

        % 3) 成员成本（往返飞行 + 等待 + 执行）
        coalition_cost = 0;
        for idx = 1:numel(member_ids)
            member_id = member_ids(idx);
            start_xy = [agents(member_id).x, agents(member_id).y];
            total_dist = OCFUtils.compute_route_distance(start_xy, j, tasks); % 闭环往返
            v_mid = eps_val;
            if isfield(agents(member_id), 'vel') && ~isempty(agents(member_id).vel)
                v_mid = max(agents(member_id).vel, eps_val);
            end
            fly_time = total_dist / v_mid;

            my_arrival = arrival_times(idx);
            wait_time = max(0, sync_start - my_arrival);

            alpha_fly = agents(member_id).fuel;
            alpha_wait = alpha_fly * 0.5;
            if isfield(agents, 'wait_fuel') && isfield(agents(member_id), 'wait_fuel') && ~isempty(agents(member_id).wait_fuel)
                alpha_wait = agents(member_id).wait_fuel;
            end
            beta = 0;
            if isfield(agents, 'beta') && isfield(agents(member_id), 'beta')
                beta = agents(member_id).beta;
            end

            member_cost = fly_time * alpha_fly + wait_time * alpha_wait + task_exec_time * beta;
            Rcost(j, member_id) = member_cost;
            coalition_cost = coalition_cost + member_cost;
        end
        
        % 联盟效用 = 收益 - 代价
        coalition_utility(j) = max(coalition_revenue - coalition_cost, 0);

        % 按实际完成度累积完成价值（用于统计）
        total_completed_value = total_completed_value + tasks(j).value * D_C;
    end

    % 记录本轮完成价值
    total_value_history(counter) = total_completed_value;
    
    % 计算总代价
    cost_sum(counter) = sum(Rcost(:));
    
    % 计算总效用（所有联盟效用之和）
    net_profit(counter) = sum(coalition_utility);
    
    counter=counter+1;
    
end

%% 适配对比框架的输出格式
% 将Huo算法的输出转换为框架期望的格式

% 1. 重组Value_data为统一格式
% Huo算法的Value_data是每个agent一个结构，现在需要合并为一个
final_Value_data = struct();
final_Value_data.coalitionstru = Value_data(1).coalitionstru;  % M×N 联盟结构矩阵

% 2. 计算总效用（使用最后一次的净收益）
final_Value_data.totalvalue = net_profit(end);

% 3. 构建资源分配矩阵（用于计算资源利用率）
% Huo算法中，每个智能体将其全部资源贡献给参与的任务
final_Value_data.agentresources = zeros(Value_Params.N, Value_Params.M, Value_Params.K);
for j = 1:Value_Params.M
    member_ids = find(Value_data(1).coalitionstru(j, :) ~= 0);
    for i = 1:length(member_ids)
        member_id = member_ids(i);
        if isfield(agents(member_id), 'resources')
            member_res = agents(member_id).resources(:)';
            if length(member_res) >= Value_Params.K
                final_Value_data.agentresources(member_id, j, :) = member_res(1:Value_Params.K);
            elseif ~isempty(member_res)
                final_Value_data.agentresources(member_id, j, 1:length(member_res)) = member_res;
            end
        end
    end
end

% 4. 添加额外信息
final_Value_data.cost_sum = cost_sum(end);
final_Value_data.net_profit_history = net_profit;
final_Value_data.cost_history = cost_sum;
final_Value_data.Rcost = Rcost;

% 5. 构建history_data
history_data = struct();
history_data.algorithm = 'Huo2025';
history_data.final_utility = net_profit(end);
history_data.net_profit_evolution = net_profit;
history_data.cost_evolution = cost_sum;
history_data.num_rounds = Value_Params.num_rounds;  % 使用传入的轮数参数
history_data.initial_coalition = initial_coalition;
history_data.total_value_history = total_value_history;
history_data.total_value_possible = total_value_possible;

% 6. 将final_Value_data作为第一个输出
Value_data_out = final_Value_data;

% 返回适配后的输出
Value_data = Value_data_out;

end





