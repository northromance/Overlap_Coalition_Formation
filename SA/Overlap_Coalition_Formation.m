function [incremental, Value_data] = Overlap_Coalition_Formation(agents, tasks, Value_data, Value_Params, counter, AddPara, allocated_resources, resource_gap)
% Overlap_Coalition_Formation - 重叠联盟形成函数（单智能体）
%
% 输入:
%   agents              - 所有智能体结构数组
%   tasks               - 所有任务结构数组
%   Value_data          - 当前智能体的数据结构（包含联盟信息、资源分配等）
%   Value_Params        - 全局参数（N, M, K等）
%   counter             - 当前轮次计数器
%   AddPara             - 附加参数
%   allocated_resources - N×K矩阵，各智能体已分配资源量
%   resource_gap        - M×K矩阵，各任务资源缺口
%
% 输出:
%   incremental         - 联盟是否发生改变（0=未改变, 1=已改变）
%   Value_data          - 更新后的智能体数据

%% 备份当前状态
backup.coalition = Value_data.coalitionstru;
backup.iteration = Value_data.iteration;
backup.unif = Value_data.unif;
backup.SC = Value_data.SC;
backup.resources_matrix = Value_data.resources_matrix;

%% 计算任务选择概率
% probs: K×M矩阵，probs(r,j) = 用资源类型r选择任务j的概率
probs = compute_select_probabilities(Value_data, agents, tasks, Value_Params, allocated_resources, resource_gap);
Value_data.selectProb = probs;

%% 执行联盟操作（加入 或 离开）
% 先尝试加入任务，若未成功则尝试离开任务
[Value_data, incremental_join] = join_operation(Value_data, agents, tasks, Value_Params, probs);

if ~incremental_join
    [Value_data, ~] = leave_operation(Value_data, agents, tasks, Value_Params, probs);
end

%% 检测联盟结构变化
SC_changed = false;
for m = 1:Value_Params.M
    if ~isequal(backup.SC{m}, Value_data.SC{m})
        SC_changed = true;
        break;
    end
end

%% 决定是否保留变化
if SC_changed
    incremental = 1;  % 联盟结构已改变
else
    incremental = 0;  % 无变化，回退到备份状态
    Value_data.coalitionstru = backup.coalition;
    Value_data.SC = backup.SC;
    Value_data.resources_matrix = backup.resources_matrix;
end

end


