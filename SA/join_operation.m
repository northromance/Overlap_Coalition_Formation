function Value_data = join_operation(Value_data, agents, tasks, Value_Params, probs)
% exchange_operation: 根据已计算的选择概率执行一次离开-加入操作（随机交换）
% 输入:
%   Value_data - 单个 agent 的数据结构，需包含 .agentID, .agentIndex, .coalitionstru, .selectProb
%   agents, tasks, Value_Params - 环境和参数（未使用的参数保留兼容性）
% 输出:
%   Value_data - 更新后的 Value_data，已在 .coalitionstru 中执行离开与加入

    agentID = Value_data.agentID;

    % 检查概率向量（接受外部传入的 probs，若为空则尝试读取 Value_data.selectProb）
    if nargin < 5 || isempty(probs)
        if isfield(Value_data,'selectProb') && ~isempty(Value_data.selectProb)
            probs = Value_data.selectProb(:)';
        else
            return;
        end
    end

    % 抽样目标任务（包含空任务 M+1）
    try
        % 使用 randsample 若存在统计工具箱，否则使用 cumulative sampling
        if exist('randsample','file') == 2
            target = randsample(length(probs),1,true,probs);
        else
            edges = [0 cumsum(probs)];
            r = rand()*edges(end);
            target = find(r>edges,1,'last');
            if target>length(probs), target=length(probs); end
        end
    catch
        % 回退：均匀随机
        target = randi(length(probs));
    end

    % 当前所属任务集合
    currentRows = find(Value_data.coalitionstru(:, agentID) == agentID);

    % 温度（用于退火概率），回退到 1
    if isfield(Value_Params,'Temperature') && ~isempty(Value_Params.Temperature)
        T = Value_Params.Temperature;
        if abs(T) < 1e-9, T = 1; end
    else
        T = 1;
    end

    %% 1) 根据概率在当前联盟中选择一个要退出的任务（若无则跳过）
    if ~isempty(currentRows)
        % 如果 probs 中包含当前任务的概率，则按该权重选择，否则均匀选择
        cur_probs = probs(currentRows);
        if sum(cur_probs) > 0
            % 归一化
            cur_probs = cur_probs / sum(cur_probs);
            % 抽样 src
            if exist('randsample','file') == 2
                src = currentRows(randsample(length(currentRows),1,true,cur_probs));
            else
                edges = [0 cumsum(cur_probs)];
                r = rand()*edges(end);
                k = find(r>edges,1,'last'); if isempty(k), k=1; end
                src = currentRows(k);
            end
        else
            src = currentRows(randi(length(currentRows)));
        end

        % 评估移除后的效用变化（使用利他效用作为默认评估函数）
        initial_coal = Value_data.coalitionstru;
        after_coal = initial_coal;
        after_coal(src, agentID) = 0;
        try
            delta_remove = SA_altruistic_utility(tasks, agents, initial_coal, after_coal, agentID, Value_Params, Value_data);
        catch
            delta_remove = -inf;
        end

        % 接受条件：delta>0 或按退火概率接受
        if delta_remove > 0
            % 执行移除
            Value_data.coalitionstru = after_coal;
        else
            acceptProb = exp(delta_remove / T);
            if rand() < acceptProb
                Value_data.coalitionstru = after_coal;
            end
        end
    end

    %% 2) 根据概率选择加入目标任务并评估
    % 抽样目标任务 index
    try
        if exist('randsample','file') == 2
            target = randsample(length(probs),1,true,probs);
        else
            edges = [0 cumsum(probs)];
            r = rand()*edges(end);
            target = find(r>edges,1,'last');
            if target>length(probs), target=length(probs); end
        end
    catch
        target = randi(length(probs));
    end

    % 如果已经属于目标任务则不作改变
    currentRows = find(Value_data.coalitionstru(:, agentID) == agentID);
    if ismember(target, currentRows)
        return;
    end

    % 构造加入后的联盟并评估
    initial_coal2 = Value_data.coalitionstru;
    after_coal2 = initial_coal2;
    after_coal2(target, agentID) = agentID;
    try
        delta_add = SA_altruistic_utility(tasks, agents, initial_coal2, after_coal2, agentID, Value_Params, Value_data);
    catch
        delta_add = -inf;
    end

    if delta_add > 0
        Value_data.coalitionstru = after_coal2;
    else
        acceptProb2 = exp(delta_add / T);
        if rand() < acceptProb2
            Value_data.coalitionstru = after_coal2;
        end
    end

end
