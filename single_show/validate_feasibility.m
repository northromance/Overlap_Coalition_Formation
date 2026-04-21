function [isFeasible, info, cost_data] = validate_feasibility(Value_data, agents, tasks, Value_Params, agentID, SC, check_teammates, AddPara) %#ok<INUSL>
% VALIDATE_FEASIBILITY 可行性检测：携带量约束 + 能量可达性
%
% 输入:
%   Value_data      - 智能体数据（保留接口兼容，实际仅用 agents）
%   agents          - 智能体数组
%   tasks           - 任务数组
%   Value_Params    - 全局参数
%   agentID         - 目标智能体 ID
%   SC              - 待检查的联盟结构
%   check_teammates - 是否检查全局能量约束（默认 true）
%                     true  → 调用 calc_all_agents_with_global_sync 一次，检查全部 N 个智能体
%                     false → 仅检查 agentID 自身能量（轻量快速路径）
%   AddPara         - 附加参数（.verbose 控制日志输出）
%
% 输出:
%   isFeasible - 是否可行
%   info       - 不可行原因（info.reason 字符串）
%   cost_data  - agentID 的能量/时间数据（可选，供调用方复用）

if nargin < 7, check_teammates = true; end
if nargin < 8, AddPara = struct('verbose', false); end

tol = 1e-9;

%% 1. agentID 资源约束快速检查（无需时序计算）
[isFeasible, info, cost_data] = check_resource_constraints(agentID, SC, agents, Value_Params, tol);
if ~isFeasible, return; end

%% 2. 能量可行性检查
if check_teammates
    % ---------------------------------------------------------------
    % 全局路径：调用 calc_all_agents_with_global_sync 一次
    % 得到所有 N 个智能体的时序结果，逐一校验能量约束。
    % 这样能捕获"间接受害者"：与 agentID 不共任务，但通过时间同步链
    % 被传递延迟、最终能量溢出的智能体。
    % ---------------------------------------------------------------
    all_results = SS_WorldSim.calc_all_agents_with_global_sync(agents, tasks, Value_Params, SC, tol);

    for j = 1:Value_Params.N
        r = all_results(j);
        if isempty(r.task_sequence), continue; end

        energy_j = agents(j).fuel      * r.t_fly_total  + ...
                   agents(j).wait_fuel * r.t_wait_total + ...
                   agents(j).beta      * r.t_exec_total;

        if energy_j > agents(j).Emax + tol
            isFeasible          = false;
            info.reason         = 'energy_insufficient';
            info.affected_agent = j;
            if AddPara.verbose >= 3
                fprintf('      [全局能量检查] Agent %d 能量不足: 需要 %.2f > 拥有 %.2f\n', ...
                    j, energy_j, agents(j).Emax);
            end
            return;
        end

        % 顺便填充 agentID 的 cost_data
        if j == agentID
            cost_data.requiredEnergy = energy_j;
            cost_data.t_fly_total    = r.t_fly_total;
            cost_data.t_wait_total   = r.t_wait_total;
            cost_data.t_exec_total   = r.t_exec_total;
            cost_data.assignedTasks  = r.task_sequence;
        end
    end

else
    % ---------------------------------------------------------------
    % 轻量路径：仅检查 agentID 自身能量（不检查其他人）
    % 用于对性能敏感、且已知不需要全局检查的调用场景。
    % ---------------------------------------------------------------
    assignedTasks = cost_data.assignedTasks;
    if ~isempty(assignedTasks)
        [t_fly, t_exec, ~, energy, ~, ~, t_wait] = ...
            energy_cost(agentID, assignedTasks, agents, tasks, Value_Params, SC);

        if energy > agents(agentID).Emax + tol
            isFeasible = false;
            info.reason = 'energy_insufficient';
            return;
        end

        cost_data.requiredEnergy = energy;
        cost_data.t_fly_total    = t_fly;
        cost_data.t_wait_total   = t_wait;
        cost_data.t_exec_total   = t_exec;
    end
end

end

%% ===== 内部函数 =====

function [isFeasible, info, cost_data] = check_resource_constraints(agentIdx, SC, agents, Value_Params, tol)
% 检查 agentIdx 的资源非负约束和携带量约束（纯矩阵运算，无时序开销）
isFeasible = true;
info       = struct('reason', '');
cost_data  = struct('assignedTasks', []);

R_agent = SS_OCFUtils.get_agent_resource_matrix(SC, agentIdx, Value_Params);

% 非负约束
if min(R_agent(:)) < -tol
    isFeasible = false; info.reason = 'negative_allocation'; return;
end

% 携带量约束：单任务投入不超过自身资源上限
cap = agents(agentIdx).resources(:);
if any(max(R_agent, [], 1)' - cap > tol)
    isFeasible = false; info.reason = 'capacity_exceeded'; return;
end

cost_data.assignedTasks = find(any(R_agent > tol, 2))';
end
