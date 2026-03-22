function [SC_global, moved, TabuList] = Value_order(agents, tasks, SC_global, agent_idx, Value_data_i, Value_Params, AddPara, TabuList)
% VALUE_ORDER 顺序决策版：为单个智能体执行一次"最优任务选择"决策（含禁忌机制）
%
% 非重叠联盟约束：每个智能体只能加入一个任务，全部资源投入该任务。
% 决策标准：受影响智能体效用增量之和（cur_task + 目标任务的成员），逻辑等价于全局增量。
% 禁忌机制：候选 SC 若在禁忌表中则跳过，接受移动后将新 SC 加入禁忌表。
%
% 输入：
%   agents       - 所有智能体结构体数组
%   tasks        - 所有任务结构体数组
%   SC_global    - 当前全局联盟结构（M×1 cell，每格 N×K 矩阵）
%   agent_idx    - 当前决策智能体的索引（= agentID）
%   Value_data_i - 该智能体的状态（含信念 initbelief）
%   Value_Params - 全局参数（Qi_L_tabu 控制禁忌表长度）
%   AddPara      - 附加参数
%   TabuList     - 当前禁忌表（cell array of hash strings）
%
% 输出：
%   SC_global    - 更新后的全局联盟结构（若未移动则与输入相同）
%   moved        - true=发生移动，false=保持不动
%   TabuList     - 更新后的禁忌表

M   = Value_Params.M;
tol = 1e-9;
moved  = false;
L_tabu = Value_Params.Qi_L_tabu;

%% 1. 找当前任务
cur_task = M + 1;
for m = 1:M
    if any(SC_global{m}(agent_idx, :) > tol)
        cur_task = m;
        break;
    end
end

%% 2. 构造 tmp_vd（StateTran 需要）
tmp_vd.agentID = agent_idx;
tmp_vd.SC      = SC_global;
tmp_vd.resources_matrix = zeros(M, Value_Params.K);
for m = 1:M
    tmp_vd.resources_matrix(m, :) = SC_global{m}(agent_idx, :);
end

%% 3. 当前任务的受影响成员（cur_task 的所有参与者）
if cur_task <= M
    affected_cur = OCFUtils.get_participants(SC_global, cur_task, tol);
else
    affected_cur = [];
end

%% 4. What-If 遍历所有候选任务
best_task  = cur_task;
best_delta = 0;          % 只接受严格正增量
best_SC    = SC_global;

for j = 1:M
    if j == cur_task, continue; end

    % 构造候选 SC
    tmp_vd.SC = SC_global;
    tmp_vd.resources_matrix = zeros(M, Value_Params.K);
    for m = 1:M
        tmp_vd.resources_matrix(m, :) = SC_global{m}(agent_idx, :);
    end
    [~, SC_cand, ~, ~] = StateTran.calc_move_changes(tmp_vd, agents, Value_Params, cur_task, j, agent_idx);

    % 禁忌检查
    if huo_is_in_tabu(huo_get_SC_hash(SC_cand), TabuList)
        if isfield(AddPara, 'verbose') && AddPara.verbose >= 3
            fprintf('  [Value_order] Agent %d 候选任务%d 被禁忌跳过\n', agent_idx, j);
        end
        continue;
    end

    % 受影响成员 = cur_task 原成员 ∪ 目标任务 j 原成员（非重叠联盟，其余任务不受影响）
    affected_j   = OCFUtils.get_participants(SC_global, j, tol);
    affected_all = unique([affected_cur(:); affected_j(:); agent_idx])';

    % 只计算受影响成员的效用差（逻辑等价于全局增量，但只算少数人）
    delta = 0;
    for n = affected_all
        proxy.agentID    = n;
        proxy.initbelief = Value_data_i.initbelief;
        u_new = UtilityEvaluator.calc_agent_total_utility(SC_cand,   agents, tasks, Value_Params, proxy, AddPara);
        u_old = UtilityEvaluator.calc_agent_total_utility(SC_global, agents, tasks, Value_Params, proxy, AddPara);
        delta = delta + (u_new - u_old);
    end

    if delta > best_delta
        best_delta = delta;
        best_task  = j;
        best_SC    = SC_cand;
    end
end

%% 5. 决策
if best_task ~= cur_task
    SC_global = best_SC;
    moved     = true;
    TabuList  = huo_update_tabu(TabuList, huo_get_SC_hash(SC_global), L_tabu);
    if isfield(AddPara, 'verbose') && AddPara.verbose >= 3
        fprintf('  [Value_order] Agent %d 迁移 任务%d -> 任务%d，效用增量=%.4f\n', ...
            agent_idx, cur_task, best_task, best_delta);
    end
else
    if isfield(AddPara, 'verbose') && AddPara.verbose >= 3
        fprintf('  [Value_order] Agent %d 保持任务%d不变（无正增量）\n', agent_idx, cur_task);
    end
end

end

%% ===== 禁忌辅助函数 =====

function hash = huo_get_SC_hash(SC)
vec = [];
for m = 1:length(SC)
    vec = [vec; SC{m}(:)]; %#ok<AGROW>
end
hash = mat2str(vec);
end

function result = huo_is_in_tabu(hash, TabuList)
result = false;
for i = 1:length(TabuList)
    if strcmp(hash, TabuList{i})
        result = true;
        return;
    end
end
end

function TabuList = huo_update_tabu(TabuList, hash, L_tabu)
TabuList{end+1} = hash;
if length(TabuList) > L_tabu
    TabuList(1) = [];
end
end
