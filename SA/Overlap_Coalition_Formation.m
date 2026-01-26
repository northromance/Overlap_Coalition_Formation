function [Value_data] = Overlap_Coalition_Formation(agents, tasks, Value_data, Value_Params,AddPara)
% OVERLAP_COALITION_FORMATION 单个智能体的联盟更新函数（允许重叠联盟）
%
% 核心逻辑：
%   这是一个两阶段的决策过程：
%   1. 尝试“加入”某个任务：利用空闲资源去贡献新任务或增加对现有任务的投入。
%   2. 如果加入失败（没有发生变动），则尝试“离开”某个任务：释放资源，为后续轮次创造机会。
%   整个过程包含状态备份与回滚机制，确保状态更新的原子性。
%
% 输入:
%   agents       - 智能体结构体数组 (只读，用于获取位置、最大资源上限等)
%   tasks        - 任务结构体数组 (只读，用于获取任务位置、需求等)
%   Value_data   - 当前智能体的状态结构体 (包含当前的联盟结构、资源分配、信念等)
%   Value_Params - 全局参数结构体 (包含任务数 M, 资源维数 K 等)
%
% 输出:
%   Value_data   - 更新后的智能体状态
%   (注：代码内部计算了 incremental 变量，但函数签名未将其作为输出返回，如果外部需要判断是否收敛，建议修改函数签名为 [Value_data, incremental])

    %% ==================== 1. 状态备份 (Backup Current State) ====================
    % 在进行任何尝试性操作前，先保存当前状态。
    % 目的：
    %   1. 用于后续检测状态是否发生了实质性变化 (Change Detection)。
    %   2. 如果操作无效或需要取消，可以方便地回滚数据 (Rollback)。
    
    backup.coalition = Value_data.coalitionstru;  % 备份联盟成员结构
    backup.iteration = Value_data.iteration;      % 备份迭代次数
    backup.unif = Value_data.unif;                % 备份随机变量
    backup.SC = Value_data.SC;                    % 备份全局资源分配表 (Schedule)
    
    % 提取并备份当前智能体的资源矩阵 (从全局 SC 视图转换为个体的 M x K 矩阵)
    backup.resources_matrix = OCFUtils.get_agent_resource_matrix(backup.SC , Value_data.agentID, Value_Params);

    %% ==================== 2. 计算资源缺口 (Compute Resource Gaps) ====================
    % 动态计算当前状态下，各个任务还缺多少资源，以及智能体还剩多少资源。
    % resource_gap 通常包含两部分信息：
    %   1. 任务的剩余需求 (Task Demand - Current Allocation)
    %   2. 智能体的剩余能力 (Agent Capacity - Current Usage)
    [~, resource_gap] = calc_gaps(Value_data, Value_Params,AddPara);
    % 注：calc_gaps 的第一个返回值可能是 gap_cost 或其他指标，此处被忽略

    %% ==================== 3. 计算任务选择概率 (Task Selection Probabilities) ====================
    % 基于资源缺口、任务优先级、距离成本等因素，计算智能体对每个任务及其每种资源的倾向程度。
    % probs 维度通常为 (K x M) 或 (1 x M)，取决于 select_probs 的具体实现。
    % 高概率意味着该任务更值得投入资源。
    probs = Select_probs(Value_data, agents, tasks, Value_Params, resource_gap);
    
    % 将计算出的概率存入状态结构体，供后续 Join/Leave 操作使用
    Value_data.selectProb = probs;

    %% ==================== 4. 联盟操作：尝试加入，否则尝试离开 ====================
    % 策略逻辑：
    %   优先尝试“做加法” (Join)：如果能利用现有资源产生价值，就加入。
    %   如果做不了加法，尝试“做减法” (Leave)：释放低效占用的资源，打破局部最优，让资源流动起来。
    
    % --- Step 4.1: 尝试加入 (Join Operation) ---
    [Value_data, incremental_join] = join_operation(Value_data, agents, tasks, Value_Params, probs,AddPara);
    
    % --- Step 4.2: 尝试离开 (Leave Operation) ---
    % 只有在 Join 操作没有产生任何改变 (incremental_join == 0) 时，才考虑 Leave。
    if ~incremental_join
        [Value_data, ~] = leave_operation(Value_data, agents, tasks, Value_Params, probs,AddPara);
    end

    %% ==================== 5. 变化检测 (Detect Changes in SC) ====================
    % 检查经过 Join/Leave 操作后的全局资源分配表 (SC) 是否与备份的一致。
    
    SC_changed = false;
    for m = 1:Value_Params.M
        % 逐个任务检查资源分配矩阵是否发生变化
        if ~isequal(backup.SC{m}, Value_data.SC{m})
            SC_changed = true;
            break; % 只要有一个任务变了，就标记为已改变并退出循环
        end
    end

    %% ==================== 6. 应用更新或回滚 (Apply or Rollback) ====================
    if SC_changed
        % 情况 A: 状态发生了改变
        incremental = 1; % 标记有增量变化 (虽然此变量未被输出，但在调试或逻辑判断中有用)
        % Value_data 保持更新后的状态，无需操作
    else
        % 情况 B: 状态未改变 (Join 和 Leave 都没有成功，或者操作被拒绝)
        incremental = 0;
        
        % 执行回滚：将状态恢复到操作前的备份
        Value_data.coalitionstru = backup.coalition;
        Value_data.SC = backup.SC;
        Value_data.resources_matrix = backup.resources_matrix;
    end
    
end