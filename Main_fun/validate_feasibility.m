function [isFeasible, info, cost_data] = validate_feasibility(Value_data, agents, tasks, Value_Params, agentID, SC, check_teammates, AddPara) %#ok<INUSL>
% VALIDATE_FEASIBILITY 可行性检测：携带量约束 + 能量可达性 + 队友检查
%
% 输入:
%   Value_data      - 智能体数据（保留接口兼容，实际仅用 agents）
%   agents          - 智能体数组
%   tasks           - 任务数组
%   Value_Params    - 全局参数
%   agentID         - 目标智能体 ID
%   SC              - 待检查的联盟结构
%   check_teammates - 是否检查队友可行性（默认 true）
%   AddPara         - 附加参数（.verbose 控制日志输出）
%
% 输出:
%   isFeasible - 是否可行
%   info       - 不可行原因（info.reason 字符串）
%   cost_data  - 能量/时间成本数据（可选，供调用方复用）

if nargin < 7, check_teammates = true; end
if nargin < 8, AddPara = struct('verbose', false); end

tol = 1e-9;

%% 1. 自身可行性检查
[isFeasible, info, cost_data] = check_single_agent(agentID, SC, agents, tasks, Value_Params, tol);
if ~isFeasible, return; end

%% 2. 队友可行性检查（可选）
if ~check_teammates, return; end

teammates = get_teammates(agentID, SC, Value_Params, tol);
for k = 1:numel(teammates)
    [ok, info_t] = check_single_agent(teammates(k), SC, agents, tasks, Value_Params, tol);
    if ~ok
        isFeasible = false;
        info.reason = 'teammates_would_become_infeasible';
        info.affected_agents = teammates(k);
        if AddPara.verbose
            fprintf('      [队友检查] Agent %d 不可行: %s\n', teammates(k), info_t.reason);
        end
        return;
    end
end

end

%% ===== 内部函数 =====

function [isFeasible, info, cost_data] = check_single_agent(agentIdx, SC, agents, tasks, Value_Params, tol)
% 检查单个智能体的自身可行性（不递归检查队友）
isFeasible = true;
info       = struct('reason', '');
cost_data  = struct();

% 非负约束 + 携带量约束
R_agent = OCFUtils.get_agent_resource_matrix(SC, agentIdx, Value_Params);
if min(R_agent(:)) < -tol
    isFeasible = false; info.reason = 'negative_allocation'; return;
end

cap = agents(agentIdx).resources(:);
if any(max(R_agent, [], 1)' - cap > tol)
    isFeasible = false; info.reason = 'capacity_exceeded'; return;
end

% 能量约束
assignedTasks = find(any(R_agent > tol, 2))';
if isempty(assignedTasks), return; end

[t_fly, t_exec, totalDist, energy, ~, ~, t_wait] = ...
    energy_cost(agentIdx, assignedTasks, agents, tasks, Value_Params, SC);

if energy > agents(agentIdx).Emax + tol
    isFeasible = false; info.reason = 'energy_insufficient'; return;
end

cost_data.requiredEnergy = energy;
cost_data.t_fly_total    = t_fly;
cost_data.t_wait_total   = t_wait;
cost_data.t_exec_total   = t_exec;
cost_data.totalDistance  = totalDist;
cost_data.assignedTasks  = assignedTasks;
end


function teammates = get_teammates(agentID, SC, Value_Params, tol)
% 找出与 agentID 共同参与任意任务的所有其他智能体（去重）
teammates = [];
for m = 1:Value_Params.M
    if size(SC{m}, 1) >= agentID && any(SC{m}(agentID, :) > tol)
        participants = find(any(SC{m} > tol, 2));
        teammates = [teammates; participants(participants ~= agentID)]; %#ok<AGROW>
    end
end
teammates = unique(teammates)';
end
