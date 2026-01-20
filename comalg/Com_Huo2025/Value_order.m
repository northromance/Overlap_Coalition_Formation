function [incremental, curnumberrow, Value_data] = Value_order(agents, tasks, Value_data, Value_Params)
% VALUE_ORDER 智能体自主任务选择函数
% 
% 功能：
%   智能体遍历所有可选任务（包括空闲 Void 任务），计算“如果我加入该任务”能获得的预期效用。
%   如果发现有比当前任务效用更高的选项，则执行转移操作（更新联盟结构）。
%
% 输入：
%   agents       - 智能体列表
%   tasks        - 任务列表
%   Value_data   - 包含当前联盟结构(coalitionstru)和智能体ID的数据
%   Value_Params - 全局参数（M, N等）
%
% 输出：
%   incremental  - 变化标志位 (1=发生了变动, 0=未变动)
%   curnumberrow - 智能体在变动前的任务ID
%   Value_data   - 更新后的智能体状态数据

    %% 1. 初始化与状态备份
    incremental = 0; % 初始化标志位，0 表示结构未改变
    agentID = Value_data.agentID;
    
    % 确保资源/联盟结构存在
    if ~isfield(Value_data, 'resources_matrix') || isempty(Value_data.resources_matrix)
        Value_data.resources_matrix = zeros(Value_Params.M, Value_Params.K);
    end
    if ~isfield(Value_data, 'SC') || isempty(Value_data.SC)
        Value_data.SC = cell(Value_Params.M, 1);
        for m = 1:Value_Params.M
            Value_data.SC{m} = zeros(Value_Params.N, Value_Params.K);
        end
    end
    
    % 记录当前智能体的完整资源向量
    agent_resource_profile = zeros(1, Value_Params.K);
    if agentID <= numel(agents) && isfield(agents(agentID), 'resources') && ~isempty(agents(agentID).resources)
        res_tmp = agents(agentID).resources(:)';
        len_res = min(length(res_tmp), Value_Params.K);
        agent_resource_profile(1:len_res) = res_tmp(1:len_res);
    end
    
    % 备份当前的联盟结构和其他状态，用于“试探”后的回滚
    % 因为后面会在循环里反复修改 coalitionstru 来计算假设效用
    AValue_data.initcoalitionstru = Value_data.coalitionstru; 
    AValue_data.inititeration = Value_data.iteration;
    AValue_data.initunif = Value_data.unif;
    AValue_data.initSC = Value_data.SC;
    AValue_data.initresources_matrix = Value_data.resources_matrix;
    
    %% 2. 获取当前状态
    % 找到当前智能体所在的行（任务ID）和列（Agent索引）
    % coalitionstru 是 (M+1) x N 的矩阵
    [curnumberrow, curnumbercolumn] = find(Value_data.coalitionstru == Value_data.agentID);
    
    % 找到当前任务的所有队友（列索引）
    curnumberofcoworker = find(Value_data.coalitionstru(curnumberrow, :) ~= 0);


    % 计算当前的结构
    SC = Value_data.SC;
    R_agent = Value_data.resources_matrix; 
    
    % 计算【当前】效用
    curagentutility = Value_utility(agents, tasks, curnumberrow, curnumbercolumn, curnumberofcoworker, Value_data, Value_Params, SC, R_agent);
    
    %% 3. 试探所有可能的任务 (What-If Analysis)
    % 遍历任务 1 到 M，以及 M+1 (Void任务)
    candidateagentutility = zeros(1, Value_Params.M + 1); % 预分配数组
    
    for j = 1 : Value_Params.M + 1
        % --- 3.1 构造假设场景 ---
        % 每次循环前，先恢复到初始的联盟结构，保证环境纯净
        Value_data.coalitionstru = AValue_data.initcoalitionstru; 
        Value_data.SC = AValue_data.initSC;
        Value_data.resources_matrix = AValue_data.initresources_matrix;
        
        % 模拟操作1：从当前任务中移除自己
        Value_data.coalitionstru(curnumberrow, curnumbercolumn) = 0;
        % 模拟操作2：将自己加入到候选任务 j 中
        Value_data.coalitionstru(j, Value_data.agentID) = Value_data.agentID; 

        [~, SC_Q, ~, R_agent_Q] = OCFUtils.calc_move_changes(Value_data, agents, Value_Params, curnumberrow, j, curnumbercolumn);
        % --- 3.2 计算假设效用 ---
        % 获取假设任务 j 中的所有队友
        candidatenumberofcoworker = find(Value_data.coalitionstru(j, :) ~= 0);
        Value_data.SC = SC_Q;
        Value_data.resources_matrix = R_agent_Q;
        
        % 调用 Utility 函数计算在新环境下的效用
        candidateagentutility(j) = Value_utility(agents, tasks, j, Value_data.agentID, candidatenumberofcoworker, Value_data, Value_Params,SC_Q,R_agent_Q);
    end
    
    %% 4. 决策逻辑
    % 找到所有候选中效用最大的那个
    [value, taskindex] = max(candidateagentutility);
    % [value, taskindex] = sort(candidateagentutility, 'descend'); % (已注释) 备用的排序逻辑
    
    if value == 0
        % --- 情况 A: 最大效用为 0 ---
        % 说明去哪里都没收益，或者所有任务都无法产生正效用。
        % 策略：强制移动到 Void 任务 (第 M+1 行)，即选择“休息/空闲”。
        
        % 恢复原始结构
        Value_data.coalitionstru = AValue_data.initcoalitionstru;
        % 从当前任务移除
        Value_data.coalitionstru(curnumberrow, curnumbercolumn) = 0;
        % 移动到 Void 任务 (M+1)
        Value_data.coalitionstru(Value_Params.M + 1, curnumbercolumn) = Value_data.agentID;
        
        % 注意：这里虽然改变了结构，但 incremental 没有置 1，
        % 这可能意味着“去休息”不被视为一次有效的“联盟进化步骤”，或者仅仅是重置。
        
    else
        % --- 情况 B: 存在正效用 ---
        if value > curagentutility
            % 只有当【新任务效用 > 当前效用】时，才决定转移 (Greedy)
            incremental = 1; % 标记结构发生了改变
            
            % 更新统计信息
            Value_data.iteration = Value_data.iteration + 1; % 迭代次数+1
            Value_data.unif = rand(1); % 更新随机变量（可能用于后续记录或随机扰动）
        end
    end
    
    %% 5. 执行最终更新
    if incremental == 0
        % 如果没有找到更好的任务（或者最大效用为0且去休息了），
        % 这里的逻辑稍显复杂：
        % 如果上面 value==0 执行了移动，这里又把 initcoalitionstru 覆盖回去了？
        % **潜在逻辑问题**：如果 value==0，上面的修改会被这行覆盖，导致 agent 没有去 Void。
        % 建议检查：除非 value==0 的分支原本就是想回滚，或者 incremental 应在 value==0 时也置1。
        Value_data.coalitionstru = AValue_data.initcoalitionstru;
        Value_data.SC = AValue_data.initSC;
        Value_data.resources_matrix = AValue_data.initresources_matrix;
    else
        % 确认转移：执行真正的结构更新
        Value_data.coalitionstru = AValue_data.initcoalitionstru; % 先拿到底板
        Value_data.coalitionstru(curnumberrow, curnumbercolumn) = 0; % 退出旧任务
        Value_data.coalitionstru(taskindex, curnumbercolumn) = Value_data.agentID; % 加入新优选任务
        
        % 同步更新资源/SC 结构
        Value_data.SC = AValue_data.initSC;
        Value_data.resources_matrix = AValue_data.initresources_matrix;
        if curnumberrow <= Value_Params.M
            Value_data.resources_matrix(curnumberrow, :) = 0;
            if curnumberrow <= numel(Value_data.SC) && ~isempty(Value_data.SC{curnumberrow}) ...
                    && curnumbercolumn <= size(Value_data.SC{curnumberrow}, 1)
                Value_data.SC{curnumberrow}(curnumbercolumn, :) = 0;
            end
        end
        
        if taskindex <= Value_Params.M
            Value_data.resources_matrix(taskindex, :) = agent_resource_profile;
            if taskindex <= numel(Value_data.SC) && ~isempty(Value_data.SC{taskindex}) && curnumbercolumn <= size(Value_data.SC{taskindex}, 1)
                klen = min(Value_Params.K, size(Value_data.SC{taskindex}, 2));
                Value_data.SC{taskindex}(curnumbercolumn, 1:klen) = agent_resource_profile(1:klen);
                if klen < size(Value_data.SC{taskindex}, 2)
                    Value_data.SC{taskindex}(curnumbercolumn, klen+1:end) = 0;
                end
            end
        else
            Value_data.resources_matrix(:,:) = 0;
            for m = 1:min(numel(Value_data.SC), Value_Params.M)
                if ~isempty(Value_data.SC{m}) && curnumbercolumn <= size(Value_data.SC{m}, 1)
                    Value_data.SC{m}(curnumbercolumn, :) = 0;
                end
            end
        end
    end
    
end
