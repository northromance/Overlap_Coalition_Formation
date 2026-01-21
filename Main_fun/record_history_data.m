function history_data = record_history_data(history_data, round_idx, Value_data, Value_Params, ...
                                            final_SC, final_coalitionstru, ...
                                            coalition_utility, total_global_cost, ...
                                            total_completed_value, task_completion_degrees, ...
                                            summatrix)
% RECORD_HISTORY_DATA 记录每一轮算法的详细状态
%
% 输入:
%   history_data            - 历史结构体
%   round_idx               - 当前轮数 (对应主程序的 counter)
%   Value_data              - 智能体状态 (用于记录信念)
%   Value_Params            - 全局参数
%   final_SC                - 最终资源分配 (Cell)
%   final_coalitionstru     - 最终成员矩阵
%   coalition_utility       - 全局净效用 (标量)
%   total_global_cost       - 全局总成本 (标量，所有智能体消耗之和)
%   total_completed_value   - 任务总完成价值 (标量)
%   task_completion_degrees - 任务完成度 (Mx1)
%   summatrix               - 全局观测矩阵
%
% 输出:
%   history_data            - 更新后的历史结构体

    %% 1. 基础信息
    history_data.rounds(round_idx).round_num = round_idx;
    
    %% 2. 结构快照
    history_data.rounds(round_idx).coalitionstru = final_coalitionstru;
    history_data.rounds(round_idx).SC = final_SC;
    
    %% 3. 性能指标 (扁平化存储)
    % 记录全局净效用 (标量)
    history_data.rounds(round_idx).coalition_utility = coalition_utility;
    
    % 记录全局总成本 (标量)
    history_data.rounds(round_idx).total_global_cost = total_global_cost;
    
    % 记录完成价值与完成度
    history_data.rounds(round_idx).total_completed_value = total_completed_value;
    history_data.rounds(round_idx).task_completion_degrees = task_completion_degrees;
    
    %% 4. 信念与观测
    history_data.rounds(round_idx).summatrix = summatrix;
    
    % 记录信念快照 (N x M x TaskTypes)
    % 提取前 M 个任务的信念
    belief_snapshot = zeros(Value_Params.N, Value_Params.M, Value_Params.task_type);
    for i = 1:Value_Params.N
        belief_snapshot(i, :, :) = Value_data(i).initbelief(1:Value_Params.M, :);
    end
    history_data.rounds(round_idx).beliefs = belief_snapshot;

end