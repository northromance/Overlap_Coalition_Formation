function [Value_data, incremental_join] = join_operation(Value_data, agents, tasks, Value_Params, probs)
% join_operation: 基于选择概率矩阵 probs(KxM) 选择任务并尝试加入联盟（重叠联盟允许同时加入多个任务）
% 逻辑：对每种资源类型 r，按 probs(r,:) 抽样一个任务 -> 尝试加入；
%      若加入后的联盟满足偏好关系（delta>0）则加入；否则按模拟退火概率 exp(delta/T) 可能接受差解。
%
% 输入:
%   Value_data: 单个 agent 的数据结构，需包含 .agentID, .coalitionstru；可选 .selectProb
%   probs: K x M，每种资源类型下对各任务的选择概率
% 输出:
%   Value_data: 更新后的联盟结构
%   incremental_join: 若本次加入导致结构变化则为 1，否则 0

incremental_join = 0;
agentID = Value_data.agentID;
Value_data.resources_matrix = zeros(Value_Params.M, Value_Params.K); % Assuming 6 resource types and M tasks

% 逐资源类型抽样候选任务
for r = 1:Value_Params.K

    % 根据之前的计算每个机器人对于该类型 选择某个任务的概率
    row = probs(r, :); % prob 6行 4列
    row_sum = sum(row); % 计算是否有该类型的选择概率
    if row_sum <= 0
        continue;
    end

    % 依照顺序选择一种任务
    % cumulative sampling（避免依赖 randsample）
    edges = cumsum(row);
    x = rand() * edges(end);

    % 选择出了target应该将r类型资源加入到target任务中
    target = find(edges >= x, 1, 'first');
    if isempty(target)
        continue;
    end

    % 只允许加入真实任务 1..M
    if target < 1 || target > Value_Params.M
        error('超出边界');
    end


    % 这块应该加一个资源向量列表 记录 该智能体分配给 该任务哪种类型的资源了
    % 将资源矩阵中赋值

    % 更新之前的个体资源分配矩阵
    back_resources_matrix = Value_data.resources_matrix;
    % 更新之后的个体资源分配矩阵
    Value_data.resources_matrix(target, r) = Value_data.resources(r,1);
    after_resources_matrix =  Value_data.resources_matrix;


    initial_coal = Value_data.coalitionstru;
    after_coal = initial_coal;
    after_coal(target, agentID) = agentID;


    % 计算效用（可以用函数名替代这里的值）
    % 计算执行加入之前的联盟结构的效用
    utility_before = overlap_coalition_utility(tasks, agents, Intial_coalitionstru, After_coalitionstru, agentID, Value_Params, Value_data);  % 计算加入联盟之前的效用

    utility_after = overlap_coalition_utility(tasks, agents, Intial_coalitionstru, After_coalitionstru, agentID, Value_Params, Value_data); 

    % 计算效用差（ΔU）
    delta_U = utility_after - utility_before;

    % 决策过程
    if delta_U > 0
        % 如果效用差大于0，直接加入联盟
        disp('加入联盟，效用差大于0。');

    else
        % 如果效用差不大于0，使用模拟退火概率判断是否加入联盟
        P_join = exp(delta_U / T);  % 计算加入联盟的概率

        % 根据随机数判断是否加入联盟
        if rand() < P_join
            disp('加入联盟，基于模拟退火的小概率。');
        else
            disp('不加入联盟，概率太低。');
        end
    end


end

