function [incremental, current_task_idx, Value_data] = Value_order(agents, tasks, Value_data, Value_Params,AddPara)
% VALUE_ORDER 为单个智能体执行一次"最优任务选择"决策
%
% 流程：
%   1. 获取当前任务与基准效用
%   2. 遍历所有任务（含 Void），计算假设效用
%   3. 选出最优任务，决定是否迁移
%   4. 回滚状态，执行最终移动
%
% 输入：
%   agents      - 所有智能体结构体数组
%   tasks       - 所有任务结构体数组
%   Value_data  - 当前智能体状态（含 SC、coalitionstru、信念等）
%   Value_Params- 全局参数
%
% 输出：
%   incremental      - 1=发生有效迁移，0=保持不动或移至 Void
%   current_task_idx - 决策前所在任务索引
%   Value_data       - 更新后的智能体状态

verbose = isfield(AddPara, 'verbose') ;

%% 1. 初始化与状态备份
incremental = 0;
agentID = Value_data.agentID;
M = Value_Params.M;

% 备份原始状态，用于后续回滚（深拷贝）
AValue_data = Value_data;

%% 2. 获取当前状态与基准效用
% 在联盟成员结构中找到该智能体当前所在任务（行）和列位置
[current_task_idx, agent_col_idx] = find(Value_data.coalitionstru == agentID);

% 计算当前任务下的基准效用（用于后续比较）
cur_teammates = find(Value_data.coalitionstru(current_task_idx, :) ~= 0);
curagentutility = Value_utility(agents, tasks, current_task_idx, agent_col_idx, ...
    cur_teammates, Value_data, Value_Params, Value_data.SC);

if verbose
    fprintf('[Value_order] Agent %d 当前任务=%d，基准效用=%.4f\n', ...
        agentID, current_task_idx, curagentutility);
end

%% 3. 试探所有可能的任务（What-If Analysis）
% candidateagentutility(j) = 假设移动到任务 j 后的效用
% j = M+1 表示 Void（休息）任务
candidateagentutility = zeros(1, M + 1);

for j = 1 : M + 1
    % A. 每次试探前重置到初始状态，避免试探间相互污染
    Value_data.coalitionstru    = AValue_data.coalitionstru;
    Value_data.SC               = AValue_data.SC;
    Value_data.resources_matrix = AValue_data.resources_matrix;

    % B. 模拟移动：将智能体从当前任务移到任务 j
    % 更新成员结构：从原任务退出，加入任务 j
    Value_data.coalitionstru(current_task_idx, agent_col_idx) = 0;
    Value_data.coalitionstru(j, agent_col_idx) = agentID;

    % 计算移动引起的资源变化（SC 和 resources_matrix）
    [~, SC_Q, ~, R_agent_Q] = StateTran.calc_move_changes(...
        Value_data, agents, Value_Params, current_task_idx, j, agent_col_idx);

    % 同步资源数据到假设状态
    Value_data.SC               = SC_Q;
    Value_data.resources_matrix = R_agent_Q;

    % C. 计算假设效用
    sim_teammates = find(Value_data.coalitionstru(j, :) ~= 0);
    candidateagentutility(j) = Value_utility(...
        agents, tasks, j, agent_col_idx, sim_teammates, ...
        Value_data, Value_Params, SC_Q);

    if verbose
        if j <= M
            fprintf('  [Value_order] Agent %d 试探任务%2d -> 假设效用=%.4f\n', ...
                agentID, j, candidateagentutility(j));
        else
            fprintf('  [Value_order] Agent %d 试探Void(M+1) -> 假设效用=%.4f\n', ...
                agentID, candidateagentutility(j));
        end
    end
end

%% 4. 决策逻辑
[max_utility, best_task_idx] = max(candidateagentutility);

% 默认：保持现状
target_task_idx = current_task_idx;

if max_utility == 0
    % 情况 A：所有任务效用均为 0 -> 强制进入 Void（休息）
    target_task_idx = M + 1;
    if verbose
        fprintf('[Value_order] Agent %d 决策: 所有效用=0，移至Void\n', agentID);
    end

elseif max_utility > curagentutility
    % 情况 B：找到更优任务 -> 迁移
    target_task_idx = best_task_idx;
    incremental = 1;
    if verbose
        if best_task_idx <= M
            fprintf('[Value_order] Agent %d 决策: 迁移 任务%d->任务%d，效用 %.4f->%.4f (增量=1)\n', ...
                agentID, current_task_idx, best_task_idx, curagentutility, max_utility);
        else
            fprintf('[Value_order] Agent %d 决策: 迁移 任务%d->Void，效用 %.4f->%.4f (增量=1)\n', ...
                agentID, current_task_idx, curagentutility, max_utility);
        end
    end

else
    % 情况 C：当前任务已是最优 -> 保持不动
    if verbose
        fprintf('[Value_order] Agent %d 决策: 保持任务%d不变（当前效用%.4f >= 最优%.4f）\n', ...
            agentID, current_task_idx, curagentutility, max_utility);
    end
end

%% 5. 执行最终更新
% 先回滚到干净的初始状态（SC、Resources、Stats 全部恢复）
Value_data = AValue_data;

% 若目标就是当前任务，无需任何操作，直接返回
if target_task_idx == current_task_idx
    return;
end

% --- 统一执行移动操作 ---
% 1. 重新计算目标任务的资源变化
[~, SC_Q, ~, R_agent_Q] = StateTran.calc_move_changes(...
    Value_data, agents, Value_Params, current_task_idx, target_task_idx, agent_col_idx);

% 2. 应用资源变化
Value_data.SC               = SC_Q;
Value_data.resources_matrix = R_agent_Q;

% 3. 应用成员结构变化
Value_data.coalitionstru(current_task_idx, agent_col_idx) = 0;
Value_data.coalitionstru(target_task_idx, agent_col_idx)  = agentID;

% 4. 仅在有效进化（incremental=1）时更新迭代计数和随机数
if incremental == 1
    Value_data.iteration = Value_data.iteration + 1;
    Value_data.unif = rand(1);
end

if verbose
    if target_task_idx <= M
        fprintf('[Value_order] Agent %d 已移动至任务%d，iteration=%d\n', ...
            agentID, target_task_idx, Value_data.iteration);
    else
        fprintf('[Value_order] Agent %d 已移动至Void，iteration=%d\n', ...
            agentID, Value_data.iteration);
    end
end

end
