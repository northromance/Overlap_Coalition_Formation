function [Value_data, incremental_leave] = leave_operation(Value_data, agents, tasks, Value_Params, probs)
% leave_operation: 基于当前联盟与选择概率，尝试退出一个已加入的任务
% 逻辑：从当前已加入的任务集合中选一个 src，计算退出后的偏好变化 delta；
%      若 delta>0 则退出，否则按模拟退火概率 exp(delta/T) 可能接受差解。
%
% 输入:
%   Value_data: 单个 agent 的数据结构，需包含 .agentID, .coalitionstru；可选 .selectProb
%   probs: K x M，每种资源类型下对各任务的选择概率（用于加权选择要退出的任务）
% 输出:
%   Value_data: 更新后的联盟结构
%   incremental_leave: 若本次退出导致结构变化则为 1，否则 0

    incremental_leave = 0;
    agentID = Value_data.agentID;

    if nargin < 5 || isempty(probs)
        if isfield(Value_data, 'selectProb') && ~isempty(Value_data.selectProb)
            probs = Value_data.selectProb;
        else
            probs = [];
        end
    end

    % 当前所属真实任务集合（1..M），不包含空任务行
    currentRows = find(Value_data.coalitionstru(1:Value_Params.M, agentID) == agentID);
    if isempty(currentRows)
        return;
    end

    % 温度
    if isfield(Value_Params, 'Temperature') && ~isempty(Value_Params.Temperature)
        T = Value_Params.Temperature;
        if abs(T) < 1e-9, T = 1; end
    else
        T = 1;
    end

    % 选择要退出的任务 src：若 probs 合法则用其对任务加权，否则均匀
    if ~isempty(probs) && ~isvector(probs) && size(probs, 2) == Value_Params.M
        task_weights = sum(probs(:, currentRows), 1);
        if sum(task_weights) > 0
            edges = cumsum(task_weights);
            x = rand() * edges(end);
            k = find(edges >= x, 1, 'first');
            if isempty(k), k = 1; end
            src = currentRows(k);
        else
            src = currentRows(randi(length(currentRows)));
        end
    else
        src = currentRows(randi(length(currentRows)));
    end

    initial_coal = Value_data.coalitionstru;
    after_coal = initial_coal;
    after_coal(src, agentID) = 0;

    % 偏好/效用增量
    delta_remove = -inf;
    if isfield(Value_Params, 'preferenceFcn') && ~isempty(Value_Params.preferenceFcn)
        try
            delta_remove = Value_Params.preferenceFcn(tasks, agents, initial_coal, after_coal, agentID, Value_Params, Value_data, src);
        catch
            delta_remove = -inf;
        end
    else
        try
            delta_remove = SA_altruistic_utility(tasks, agents, initial_coal, after_coal, agentID, Value_Params, Value_data);
        catch
            delta_remove = -inf;
        end
    end

    accept = false;
    if delta_remove > 0
        accept = true;
    else
        acceptProb = exp(delta_remove / T);
        if rand() < acceptProb
            accept = true;
        end
    end

    if accept
        Value_data.coalitionstru = after_coal;
        incremental_leave = 1;
    end

end
