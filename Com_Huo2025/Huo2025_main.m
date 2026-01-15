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
%       - value：任务当前可能值（一个 3 维向量）
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

% 使用传入的Value_Params，如果没有则初始化
if nargin < 4 || isempty(Value_Params)
    Value_Params = Value_init(length(agents), length(tasks));
else
    % 确保Value_Params包含必需字段
    if ~isfield(Value_Params, 'N')
        Value_Params.N = length(agents);
    end
    if ~isfield(Value_Params, 'M')
        Value_Params.M = length(tasks);
    end
    % 获取迭代轮数，如果没有则默认50
    if ~isfield(Value_Params, 'num_rounds')
        Value_Params.num_rounds = 50;
    end
    % 获取观测次数，如果没有则默认50
    if ~isfield(Value_Params, 'obs_times')
        Value_Params.obs_times = 50;
    end
end

% 生成全连通的通信图（所有智能体可以相互通信）
Graph = ones(Value_Params.N, Value_Params.N);

for i=1:Value_Params.N %包括agent标号，索引以及初始联盟结构
    Value_data(i).agentID=agents(i).id;
    Value_data(i).agentIndex=i;
    Value_data(i).iteration=0;%联盟改变次数
    Value_data(i).unif=0;%均匀随机变量
    Value_data(i).coalitionstru=zeros(Value_Params.M+1,Value_Params.N);
    Value_data(i).initbelief=zeros(Value_Params.M+1,3);
end

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
        %Value_data(i).initbelief(j,1:end)=drchrnd([1,1,1],1)';
        Value_data(i).initbelief(j,1:end)=[1/3,1/3,1/3]';
    end
end

for i=1:Value_Params.N
    for j=1:Value_Params.M
        for k=1:3
            Value_data(i).observe(j,k)=0;%创建每个agent对当前所在任务联盟的观测矩阵
            Value_data(i).preobserve(j,k)=0;
            summatrix(j,k)=0;
        end
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
    
    %记录一次联盟形成后观测次数
    for i=1:Value_Params.N
        if  curnumberrow(i)~=Value_Params.M+1
            for m=1:Value_Params.obs_times 
                taskindex=find(tasks(curnumberrow(i)).value== tasks(curnumberrow(i)).WORLD.value);
                nontaskindex=find(tasks(curnumberrow(i)).value~= tasks(curnumberrow(i)).WORLD.value);
                if rand<=agents(i).detprob
                    Value_data(i).observe(curnumberrow(i),  taskindex)= Value_data(i).observe(curnumberrow(i),taskindex)+1;%更新观测矩阵
                    m=m+1;
                elseif (agents(i).detprob<rand)&&(rand<=(1-1/2*agents(i).detprob))
                    Value_data(i).observe(curnumberrow(i),  nontaskindex(1))= Value_data(i).observe(curnumberrow(i),nontaskindex(1))+1;%更新观测矩阵
                    m=m+1;
                else
                    Value_data(i).observe(curnumberrow(i),  nontaskindex(2))= Value_data(i).observe(curnumberrow(i),nontaskindex(2))+1;%更新观测矩阵
                    m=m+1;
                end
            end
        end
    end
    
    for j=1:Value_Params.M
        for k=1:3
            for i=1:Value_Params.N
                summatrix(j,k)=summatrix(j,k)+ Value_data(i).observe(j,  k)-Value_data(i).preobserve(j,  k);
            end
        end
    end
    
    for i=1:Value_Params.N
        for j=1:Value_Params.M
            for k=1:3
                Value_data(i).preobserve(j,k)= summatrix(j,k);
                Value_data(i).observe(j,  k)= summatrix(j,k);
            end
        end
    end
    
    %
    %一次联盟形成后根据观测更新belief
    for i=1:Value_Params.N
        for j=1:Value_Params.M
            Value_data(i).initbelief(j,1:end)=drchrnd([1+Value_data(i).observe(j,1),1+Value_data(i).observe(j,2),1+Value_data(i).observe(j,3)],1)';
            %  Value_data(i).initbelief(j,1:end)=[1/3,1/3,1/3];
        end
    end
    
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
        D_C = calc_task_completion_degree(total_resources, demand, K);
        
        % 计算期望价值 V_C
        V_C = tasks(j).WORLD.value(1)*Value_data(1).initbelief(j,1)...
            + tasks(j).WORLD.value(2)*Value_data(1).initbelief(j,2)...
            + tasks(j).WORLD.value(3)*Value_data(1).initbelief(j,3);
        
        % 计算联盟收益 = V_C × D_C
        coalition_revenue = V_C * D_C;
        
        % 计算每个成员的移动代价
        coalition_cost = 0;
        for i = 1:length(member_ids)
            member_id = member_ids(i);
            dist = sqrt((agents(member_id).x - tasks(j).x)^2 ...
                      + (agents(member_id).y - tasks(j).y)^2);
            Rcost(j, i) = dist * agents(member_id).fuel;
            coalition_cost = coalition_cost + Rcost(j, i);
        end
        
        % 联盟效用 = 收益 - 代价
        coalition_utility(j) = max(coalition_revenue - coalition_cost, 0);
    end
    
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

% 6. 将final_Value_data作为第一个输出
Value_data_out = final_Value_data;

% 返回适配后的输出
Value_data = Value_data_out;

end
