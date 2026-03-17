function agentutility = Value_utility(agents, tasks, numberrow, numbercolumn, ~, Value_data, Value_Params, SC)
% VALUE_UTILITY 计算智能体在特定资源分配状态下的预期净效用
%
% 输入：
%   agents        - 所有智能体结构体数组
%   tasks         - 所有任务结构体数组
%   numberrow     - 任务索引（行号），M+1 表示 Void 任务
%   numbercolumn  - 智能体在联盟结构中的列索引（即 agent_id）
%   ~             - 占位参数（历史兼容，未使用）
%   Value_data    - 当前智能体的状态数据（含信念、SC、联盟结构等）
%   Value_Params  - 全局参数（N/M/K/信念/温度等）
%   SC            - 提议状态下的联盟资源结构（M×1 cell，每格 N×K 矩阵）
%
% 输出：
%   agentutility  - 净效用 = 收益 - 成本（可为负值，不截断）

%% 0. 初始化与快速剪枝
tol = 1e-9;
verbose = isfield(Value_Params, 'verbose') && Value_Params.verbose;

% 若为 Void 任务 (M+1)，无收益，直接返回 0
if numberrow > Value_Params.M
    agentutility = 0;
    if verbose
        fprintf('    [Value_utility] Agent %d -> Void任务(M+1)，效用=0\n', numbercolumn);
    end
    return;
end

agent_id = numbercolumn; % 列索引即为 Agent ID

%% 1. 准备基础数据（基于信念的需求估算）
K = Value_Params.K;
num_types = Value_Params.task_type;

% 提取该智能体对任务 numberrow 的类型信念分布（1×num_types 向量）
belief = Value_data.initbelief(numberrow, :);

% 各类型任务的资源需求模板（num_types×K 矩阵）
task_type_demands = Value_Params.task_type_demands;

% 用分位数法将信念分布折算为估计需求向量（1×K）
% resource_confidence 越高，估计需求越保守（偏大）
resource_confidence = Value_Params.resource_confidence;
demand = WorldSim.calculate_demand_quantile(belief, task_type_demands, resource_confidence);

%% 2. 计算收益（Revenue）
% 公式：revenue = r_n * V_C * D_C
%   r_n  = 该智能体的资源贡献比例
%   V_C  = 基于信念的期望任务价值
%   D_C  = 任务完成度（已投入资源 / 估计需求，上限 1）

% A. 解析当前任务的参与者列表（资源非零的行）
participants = OCFUtils.get_participants(SC, numberrow, tol);
SC_task = SC{numberrow}; % 该任务的 N×K 资源矩阵

% B. 计算任务完成度 D_C
% total_resources(k) = 所有参与者在第 k 种资源上的总投入
total_resources = sum(SC_task(participants, :), 1);
D_C = WorldSim.calc_task_completion_degree(total_resources, demand, K);

% 若完成度为 0（无任何资源满足需求），收益为 0，直接返回
if D_C <= tol
    agentutility = 0;
    if verbose
        fprintf('    [Value_utility] Agent %d -> 任务%d，D_C≈0，效用=0\n', agent_id, numberrow);
    end
    return;
end

% C. 计算该智能体的资源贡献比例 r_n（标量，∈[0,1]）
r_n_C = OCFUtils.calc_resource_contribution_ratio(SC_task, agent_id, participants);

% D. 计算期望任务价值 V_C = Σ(类型价值 × 信念概率)
task_types = Value_Params.task_type;
values = tasks(numberrow).WORLD.value; % 各类型对应的价值向量

% 维度对齐：取三者最小长度，防止越界
tlen = min([task_types, numel(values), size(belief, 2)]);
V_C = sum(values(1:tlen) .* belief(1:tlen));

% E. 总收益
revenue = r_n_C * V_C * D_C;

%% 3. 计算成本（Cost）
% 公式：cost = t_fly * alpha_fly + t_wait * alpha_wait + t_exec * beta
%   t_fly  = 飞行时间（移动到任务地点）
%   t_wait = 等待时间（等待最晚到达的队友 + 等待执行结束）
%   t_exec = 执行时间（个体在该任务上的执行时长）

% 提取该智能体的能耗系数
alpha_fly  = agents(agent_id).fuel;       % 飞行能耗系数 varpi
alpha_wait = agents(agent_id).wait_fuel;  % 等待能耗系数 gamma
beta       = agents(agent_id).beta;       % 执行能耗系数 beta

% 调用全局同步物理引擎（一次性计算所有智能体的时间分量）
% 注意：此处每次调用开销较大，外层应尽量缓存结果
all_results = WorldSim.calc_all_agents_with_global_sync(agents, tasks, Value_Params, SC, tol);
t_fly  = all_results(agent_id).t_fly_total;   % 总飞行时间
t_wait = all_results(agent_id).t_wait_total;  % 总等待时间
t_exec = all_results(agent_id).t_exec_total;  % 总执行时间

% 聚合总成本
cost = t_fly * alpha_fly + t_wait * alpha_wait + t_exec * beta;

%% 4. 计算净效用（可为负值，不截断）
agentutility = revenue - cost;

%% 5. 调试输出
if verbose
    fprintf('    [Value_utility] Agent %2d -> 任务%2d | 参与者=%s | D_C=%.3f r_n=%.3f V_C=%.3f\n', ...
        agent_id, numberrow, mat2str(participants), D_C, r_n_C, V_C);
    fprintf('                              revenue=%.4f | fly=%.3f wait=%.3f exec=%.3f cost=%.4f\n', ...
        revenue, t_fly, t_wait, t_exec, cost);
    fprintf('                              => 净效用=%.4f\n', agentutility);
end

end
