function individual_utility = overlap_coalition_self_utility(m, curRow, coalitionstru, agents, tasks, Value_Params, Value_data)
% =========================================================================
% SA_self_utility: 计算个体在联盟中的效用
% 输入: m-智能体ID, curRow-任务行号, coalitionstru-联盟结构, agents-智能体信息,
%       tasks-任务信息, Value_Params-参数, Value_data-数据
% 输出: individual_utility-个体效用值
% =========================================================================

current_task = curRow;
% 计算该任务的联盟完成率：找到参与该任务的智能体，组合完成率为 1 - prod(1 - r_i)

%% 空任务检查
if current_task == Value_Params.M + 1
    individual_utility = 0;
    return;
else

    member_idx = find(coalitionstru(current_task,:) ~= 0);
    if isempty(member_idx)
        coalition_completion = 0;
    else
        cr = arrayfun(@(i) agents(i).completionRate(current_task), member_idx);
        coalition_completion = 1 - prod(1 - cr);
    end
    
    %% 收入计算
    b = Value_data.initbelief(current_task, :);
    v = tasks(current_task).WORLD.value;
    revenue = (v(1) * b(1) + v(2) * b(2) + v(3) * b(3)) * coalition_completion;
    
    %% 成本计算
    % 距离成本
    cost_distance = sqrt((agents(m).x - tasks(current_task).x)^2 + (agents(m).y - tasks(current_task).y)^2) * agents(m).fuel;
    
    % 风险成本
    risk = tasks(current_task).WORLD.risk;
    cost_risk = risk(1) * b(1) + risk(2) * b(2) + risk(3) * b(3);
    
    total_cost = cost_distance + cost_risk;
    
    %% 个体效用计算
    coalition_member_num = length(find(coalitionstru(current_task,:) ~= 0));
    individual_utility = revenue / coalition_member_num - total_cost;
    
end


end
