function deltaU = Preference_gain(tasks, agents, SC_P, SC_Q, agentID, Value_Params, Value_data, AddPara)
% AddPara 为可选参数，用于透传给 calc_agent_total_utility（如 verbose 等标志）
if nargin < 8
    AddPara.verbose = false;
end
% OVERLAP_COALITION_UTILITY [BMBT偏好计算核心]
% 计算智能体在两个联盟结构(SC_P vs SC_Q)间的效用差值。
% 
% 对应论文公式 (Eq. 19):
%   Delta U = (Self_Q - Self_P) + Sum(Gain_g) - Sum(Loss_h) + Sum(Diff_o)
%
% 输入:
%   SC_P: Current Structure (当前/旧的状态)
%   SC_Q: Proposed Structure (提议/新的状态)
%   Value_data: 包含信念(belief)等信息，用于估算队友效用

    %% ==================== 0. 基础准备 ====================
    % 获取智能体 n 在 Q (新) 和 P (旧) 中参与的任务列表
    % 假设 get_agent_tasks_fast 返回的是任务ID的数组
    rows_n_Q = OCFUtils.get_agent_tasks_fast(SC_Q, agentID);
    rows_n_P = OCFUtils.get_agent_tasks_fast(SC_P, agentID);
    
    %% ==================== 1. 关键集合划分 (Set Definition) ====================
    % 根据 BMBT 逻辑，将任务分为三类，互不重叠：
    
    % [集合 g] 新增任务 (Gainers): 仅在 Q 中存在
    % 对应公式项 ①: \sum [u_g(SC_Q) - u_g(SC_P)]
    new_tasks = setdiff(rows_n_Q, rows_n_P);
    
    % [集合 h] 退出任务 (Hurters): 仅在 P 中存在
    % 对应公式项 ③: \sum [u_h(SC_P) - u_h(SC_Q)]
    source_tasks = setdiff(rows_n_P, rows_n_Q);
    
    % [集合 o] 维持任务 (Others/Stable): 在 P 和 Q 中都存在
    % 对应公式项 ② vs ④: \sum u_o(SC_Q) vs \sum u_o(SC_P)
    % *这是之前逻辑出错的地方，必须用 intersect 锁定交集*
    stable_tasks = intersect(rows_n_P, rows_n_Q);
    
    %% ==================== 2. 计算自身效用差 (Self Utility) ====================
    % u_n(SC_Q) - u_n(SC_P)
    
    u_n_Q = UtilityEvaluator.calc_agent_total_utility(SC_Q, agents, tasks, Value_Params, Value_data, AddPara);
    u_n_P = UtilityEvaluator.calc_agent_total_utility(SC_P, agents, tasks, Value_Params, Value_data, AddPara);
    
    delta_self = u_n_Q - u_n_P;
    
    %% ==================== 3. 计算新任务队友的增益 (Delta g) ====================
    % 逻辑：我加入了这些任务，队友通常会受益 (Gain)
    
    sum_gain_new = 0;
    
    for idx = 1:length(new_tasks)
        task_id = new_tasks(idx);
        % 获取该任务在新状态 Q 中的队友 (g)
        members = OCFUtils.get_participants(SC_Q, task_id, 1e-6);
        members(members == agentID) = []; % 排除我自己
        
        for k = 1:length(members)
            g_id = members(k);
            % 获取信念 (估算 g 的效用)
            belief_g = get_belief(Value_data, g_id);
            
            % 计算 g 的效用变化
            u_g_Q = get_agent_util_proxy(g_id, belief_g, SC_Q, agents, tasks, Value_Params, AddPara);
            u_g_P = get_agent_util_proxy(g_id, belief_g, SC_P, agents, tasks, Value_Params, AddPara);
            
            sum_gain_new = sum_gain_new + (u_g_Q - u_g_P);
        end
    end
    
    %% ==================== 4. 计算旧任务队友的损失 (Delta h) ====================
    % 逻辑：我退出了这些任务，队友通常会受损 (Hurt)
    % 注意：公式项 ③ 写的是 [u_h(P) - u_h(Q)]，这是一个正值的"损失量"
    
    sum_loss_old = 0;
    
    for idx = 1:length(source_tasks)
        task_id = source_tasks(idx);
        % 获取该任务在旧状态 P 中的队友 (h) -> 即将被抛弃的人
        members = OCFUtils.get_participants(SC_P, task_id, 1e-6);
        members(members == agentID) = []; 
        
        for k = 1:length(members)
            h_id = members(k);
            belief_h = get_belief(Value_data, h_id);
            
            u_h_P = get_agent_util_proxy(h_id, belief_h, SC_P, agents, tasks, Value_Params, AddPara);
            u_h_Q = get_agent_util_proxy(h_id, belief_h, SC_Q, agents, tasks, Value_Params, AddPara);
            
            % 计算损失量 (P - Q)
            sum_loss_old = sum_loss_old + (u_h_P - u_h_Q);
        end
    end
    
    %% ==================== 5. 计算旁观任务队友的影响 (Delta o) ====================
    % 逻辑：这些任务我还在做，但因为时间表变了(蝴蝶效应)，队友可能会被延误
    % 这是之前代码容易重复计算的地方，现在只遍历 stable_tasks
    
    sum_diff_other = 0;
    
    for idx = 1:length(stable_tasks)
        task_id = stable_tasks(idx);
        % 获取队友 (在稳定任务中，P和Q的成员集合通常是一样的，取Q即可)
        members = OCFUtils.get_participants(SC_Q, task_id, 1e-6);
        members(members == agentID) = [];
        
        for k = 1:length(members)
            o_id = members(k);
            belief_o = get_belief(Value_data, o_id);
            
            u_o_Q = get_agent_util_proxy(o_id, belief_o, SC_Q, agents, tasks, Value_Params, AddPara);
            u_o_P = get_agent_util_proxy(o_id, belief_o, SC_P, agents, tasks, Value_Params, AddPara);
            
            % 计算变化量 (Q - P)
            % 如果延误了，Q < P，这里会累加负值
            sum_diff_other = sum_diff_other + (u_o_Q - u_o_P);
        end
    end
    
    %% ==================== 6. 最终汇总 (Aggregation) ====================
    % BMBT 判定标准: LHS > RHS
    % 移项后: (LHS - RHS) > 0
    % Delta = (Self_Q - Self_P) + Sum(g_diff) - Sum(h_loss) + Sum(o_diff)
    
    % 注意：sum_loss_old 计算的是 (P - Q)，我们在总公式里要减去这个"损失"
    % 或者理解为：总效用 = Q的总效用 - P的总效用
    % u_h_Q - u_h_P = -(u_h_P - u_h_Q) = -sum_loss_old
    
    deltaU = delta_self + sum_gain_new - sum_loss_old + sum_diff_other;
    
    % 调试打印 (可选)
    % fprintf('Self: %.2f | New(g): %.2f | Old(h): -%.2f | Other(o): %.2f | Total: %.2f\n', ...
    %     delta_self, sum_gain_new, sum_loss_old, sum_diff_other, deltaU);

end

%% ==================== 辅助函数 (Helper Functions) ====================

function belief = get_belief(Value_data, target_id)
    % 封装信念获取逻辑，防止主代码冗余
    if isfield(Value_data, 'other') && length(Value_data.other) >= target_id && ~isempty(Value_data.other{target_id})
        belief = Value_data.other{target_id}.initbelief;
    else
        % 兜底：如果没有特定队友的信念，就假设他和我一样 (Theory of Mind level 0)
        belief = Value_data.initbelief; 
    end
end

function u = get_agent_util_proxy(target_id, target_belief, SC, agents, tasks, params, AddPara)
    temp_data.agentID = target_id;
    temp_data.initbelief = target_belief;
    u = UtilityEvaluator.calc_agent_total_utility(SC, agents, tasks, params, temp_data, AddPara);
end