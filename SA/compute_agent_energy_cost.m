function [t_wait_total, T_exec_total, totalDistance, requiredEnergy, orderedTasks] = ...
    compute_agent_energy_cost(agentIdx, assignedTasks, agents, tasks, Value_Params, R_agent)
% compute_agent_energy_cost: 计算智能体执行任务序列的时间和能量消耗
%
% 输入参数:
%   agentIdx       - 智能体索引
%   assignedTasks  - 智能体分配到的任务列表（向量）
%   agents         - 智能体信息数组
%   tasks          - 任务信息数组
%   Value_Params   - 参数结构体（包含 M, K 等）
%   R_agent        - (可选) 资源分配矩阵 M×K，用于确定使用的资源类型
%
% 输出参数:
%   t_wait_total   - 移动时间（路径距离/速度）
%   T_exec_total   - 执行时间（基于duration_by_resource和实际使用的资源类型）
%   totalDistance  - 总路径距离
%   requiredEnergy - 总能量消耗 = t_wait_total*fuel + T_exec_total*beta
%   orderedTasks   - 按priority排序后的任务列表

    tol = 1e-9;
    % 首先将已分配的任务 按照优先级进行排序
    %% 1. 按priority排序任务
    if ~isempty(assignedTasks) && isfield(tasks, 'priority')
        pr = zeros(size(assignedTasks));
        for ii = 1:numel(assignedTasks)
            pr(ii) = tasks(assignedTasks(ii)).priority;
        end
        [~, orderIdx] = sort(pr, 'ascend');
        orderedTasks = assignedTasks(orderIdx);
    else
        orderedTasks = sort(assignedTasks(:));
    end
    
    %% 2. 计算路径：起点 -> 任务序列 -> 起点
    startXY = [agents(agentIdx).x, agents(agentIdx).y];
    pts = zeros(numel(orderedTasks) + 2, 2);
    pts(1, :) = startXY;
    for ii = 1:numel(orderedTasks)
        t = orderedTasks(ii);
        pts(ii + 1, :) = [tasks(t).x, tasks(t).y];
    end
    pts(end, :) = startXY;  % 回到起点
    
    seg = diff(pts, 1, 1);
    distEach = sqrt(sum(seg.^2, 2));
    totalDistance = sum(distEach);
    
    %% 3. 获取能量模型参数
    alpha = agents(agentIdx).fuel;  % 移动能耗系数
    beta = agents(agentIdx).beta;   % 执行能耗系数
    speed = agents(agentIdx).vel;   % 速度
    
    %% 4. 计算移动时间
    t_wait_total = totalDistance / max(speed, tol);
    
    %% 5. 计算执行时间（基于duration_by_resource和实际分配的资源类型）
    T_exec_total = 0;
    for ii = 1:numel(orderedTasks)
        m = orderedTasks(ii);
        
        % 确定使用了哪些资源类型
        if nargin >= 6 && ~isempty(R_agent)
            % 使用提供的资源分配矩阵
            allocRow = R_agent(m, :);
            usedTypes = (allocRow > tol);
        else
            % 假设使用所有资源类型（兼容模式）
            usedTypes = true(1, Value_Params.K);
        end
        
        % 获取任务执行时间
        if isfield(tasks, 'duration_by_resource')
            dur = tasks(m).duration_by_resource;
            if isscalar(dur)
                T_exec_total = T_exec_total + dur * nnz(usedTypes);
            else
                dur = dur(:)';
                if numel(dur) ~= Value_Params.K
                    dur = dur(1:min(numel(dur), Value_Params.K));
                    usedTypes = usedTypes(1:numel(dur));
                end
                T_exec_total = T_exec_total + sum(dur(usedTypes));
            end
        else
            % 兼容：无duration_by_resource则使用duration
            if isfield(tasks, 'duration')
                T_exec_total = T_exec_total + tasks(m).duration;
            else
                T_exec_total = T_exec_total + 1.0;  % 默认值
            end
        end
    end
    
    %% 6. 计算总能量消耗
    requiredEnergy = t_wait_total * alpha + T_exec_total * beta;
end
