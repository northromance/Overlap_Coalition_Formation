function deltaU = overlap_coalition_utility(tasks, agents, SC_P, SC_Q, agentID, Value_Params, Value_data)
% OVERLAP_COALITION_UTILITY 偏好函数：计算智能体在两个联盟结构间的效用差值
%
% 输入:
%   SC_P: Current Structure (当前/旧的状态)
%   SC_Q: Proposed Structure (提议/新的状态)
%
% 核心更新:
%   全面调用 `calc_agent_total_utility`。
%   这确保了无论是算自己还是算队友，都是基于“总收益 - 一次性总路径成本”的正确逻辑。

    N = Value_Params.N;
    
    %% ==================== 1. 识别任务集合 ====================
    % 这一步是为了弄清楚：“我在旧状态下干什么？我在新状态下干什么？”
    
    % 获取智能体 n 在 Q (新) 和 P (旧) 中参与的任务列表
    % [引用注意] 这里使用了 OCFUtils 或 WorldSim 的快速查询函数
    rows_n_Q = OCFUtils.get_agent_tasks_fast(SC_Q, agentID);
    rows_n_P = OCFUtils.get_agent_tasks_fast(SC_P, agentID);
    
    %% ==================== 2. 第一项：智能体自身的效用 (Self Utility) ====================
    % 这是最直接的动力：我换个干法，我自己能多赚吗？
    
    % 计算在新状态 Q 下，我自己的总净效用 (收益 - 成本)
    u_n_Q = calc_agent_total_utility(SC_Q, agents, tasks, Value_Params, Value_data);
    
    % 计算在旧状态 P 下，我自己的总净效用
    u_n_P = calc_agent_total_utility(SC_P, agents, tasks, Value_Params, Value_data);
    
    %% ==================== 3. 第二项：对"新加入"任务中其他成员的影响 ====================
    % 逻辑：如果我加入了一个新任务，原来的成员是高兴还是不高兴？
    % (例如：我带资进组，大家分得更多了？还是我拖慢了大家？)
    
    % 找出我新加入的任务 (在 Q 中有，在 P 中没有)
    new_tasks = setdiff(rows_n_Q, rows_n_P);
   fprintf('新任务个数为 %d 个', length(new_tasks)); % 检查新任务个数是否为1个
    sum_new_delta = 0;
    
    for idx = 1:length(new_tasks)
        A_j = new_tasks(idx);
        % 获取该任务在 Q 中的所有成员
        members = OCFUtils.get_participants(SC_Q, A_j, 1e-6);
        members(members == agentID) = []; % 排除我自己，只算队友
        
        for k = 1:length(members)
            g = members(k); % 队友 g
            
            % [关键点] 获取我对 g 的信念 (Theory of Mind)
            % 我无法知道 g 真实的快乐程度，我只能基于“我认为 g 的信念”来估算他的效用
            if isfield(Value_data, 'other') && length(Value_data.other) >= g
                belief_g = Value_data.other{g}.initbelief;
            else
                % 兜底逻辑：如果我们不了解 g，就假设他和我想的一样
                belief_g = Value_data.initbelief; 
            end
            
            % 计算队友 g 在新旧状态下的总效用，并求差值
            % 注意：这里使用了 get_agent_util_proxy 辅助函数来适配数据格式
            u_g_Q = get_agent_util_proxy(g, belief_g, SC_Q, agents, tasks, Value_Params);
            u_g_P = get_agent_util_proxy(g, belief_g, SC_P, agents, tasks, Value_Params);
            
            % 累加变化量 (如果我加入让 g 变好了，这里是正数)
            sum_new_delta = sum_new_delta + (u_g_Q - u_g_P);
        end
    end
    
    %% ==================== 4. 第三项：对"离开"任务中剩余成员的影响 ====================
    % 逻辑：如果我甩手不干了，原来的队友会被坑吗？
    % 这一项通常放在 RHS (右值) 中，表示“维持现状的价值”或“离开的代价”。
    
    % 找出我离开的任务 (在 P 中有，在 Q 中没有)
    source_tasks = setdiff(rows_n_P, rows_n_Q);
    sum_source_delta = 0;
    
    for idx = 1:length(source_tasks)
        A_i = source_tasks(idx);
        % 获取该任务在 P 中的成员 (也就是即将被我抛弃的队友)
        members = WorldSim.get_participants(SC_P, A_i, 1e-6);
        members(members == agentID) = [];
        
        for k = 1:length(members)
            h = members(k); % 队友 h
            
            % 获取信念
            if isfield(Value_data, 'other') && length(Value_data.other) >= h
                belief_h = Value_data.other{h}.initbelief;
            else
                belief_h = Value_data.initbelief;
            end
            
            % 计算队友 h 在旧状态 P (有我) 和 新状态 Q (没我) 的效用差
            u_h_P = get_agent_util_proxy(h, belief_h, SC_P, agents, tasks, Value_Params);
            u_h_Q = get_agent_util_proxy(h, belief_h, SC_Q, agents, tasks, Value_Params);
            
            % 累加变化量 (如果我在 P 中对 h 很重要，u_h_P > u_h_Q，这里是正数)
            sum_source_delta = sum_source_delta + (u_h_P - u_h_Q);
        end
    end
    
    %% ==================== 5. 第四项：合作伙伴的总效用 (稳定性项) ====================
    % 逻辑：不仅看被我改变的任务，还要看我所有合作伙伴的整体幸福度。
    % 这通常用于享乐博弈 (Hedonic Games) 中，确保联盟的整体稳定性。
    
    % 构造 "朋友圈"：在新结构 Q 下，所有与我有合作关系的智能体
    all_members_An = [];
    for idx = 1:length(rows_n_Q)
        task_id = rows_n_Q(idx);
        mems = OCFUtils.get_participants(SC_Q, task_id, 1e-6);
        all_members_An = union(all_members_An, mems); % 取并集
    end
    all_members_An(all_members_An == agentID) = []; % 排除自己
    
    sum_An_Q = 0;
    sum_An_P = 0;
    
    for k = 1:length(all_members_An)
        o = all_members_An(k); % 合作伙伴 o
        
        % 获取信念
        if isfield(Value_data, 'other') && length(Value_data.other) >= o
            belief_o = Value_data.other{o}.initbelief;
        else
            belief_o = Value_data.initbelief;
        end
        
        % 计算合作伙伴 o 在 Q 和 P 下的总效用
        % 这里比较的是：在我的新朋友圈眼里，是新世界(Q)好，还是旧世界(P)好？
        sum_An_Q = sum_An_Q + get_agent_util_proxy(o, belief_o, SC_Q, agents, tasks, Value_Params);
        sum_An_P = sum_An_P + get_agent_util_proxy(o, belief_o, SC_P, agents, tasks, Value_Params);
    end
    
    %% ==================== 6. 汇总与差值计算 ====================
    
    % LHS (Left Hand Side): 变革的动力
    % = 我在Q的爽度 + 我加入带给别人的好处 + 我新朋友圈在Q的总爽度
    lhs = u_n_Q + sum_new_delta + sum_An_Q;
    
    % RHS (Right Hand Side): 保守的阻力
    % = 我在P的爽度 + 我离开带给别人的损失 + 我新朋友圈在P的总爽度
    rhs = u_n_P + sum_source_delta + sum_An_P;
    
    % 计算净偏好
    deltaU = lhs - rhs;
end

%% ==================== 内部辅助函数 ====================
function u = get_agent_util_proxy(target_id, target_belief, SC, agents, tasks, params)
    % 作用：伪造一个 Value_data 结构体。
    % 原因：主计算函数 calc_agent_total_utility 需要传入一个结构体来读取 agentID 和 belief。
    %       但对于队友，我们没有现成的结构体，所以这里临时拼凑一个。
    
    temp_data.agentID = target_id;
    temp_data.initbelief = target_belief;
    
    % 调用通用的效用计算函数
    u = calc_agent_total_utility(SC, agents, tasks, params, temp_data);
end