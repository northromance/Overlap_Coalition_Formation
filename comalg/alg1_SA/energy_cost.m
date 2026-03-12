function [t_fly_total, t_exec_total, totalDistance, requiredEnergy, orderedTasks, task_start_times, t_wait_total, start_times, execution_times, completion_times, mission_end_time] = ...
    energy_cost(agentIdx, assignedTasks, agents, tasks, Value_Params, SC)
% ENERGY_COST 计算智能体执行任务序列的能量成本
%
% 输出：
%   t_fly_total  - 总飞行时间
%   t_exec_total - 总执行时间（注意：小写t，与内部变量一致）
%   totalDistance - 总飞行距离
%   requiredEnergy - 总能量需求
%   其他输出 - 详细的时间信息


tol = 1e-9;


% ========================
% 1) 按优先级排序当前智能体的任务
% =========================
% orderedTasks：将 assignedTasks 按 tasks 中的 priority 字段（或你的排序规则）排序
orderedTasks = OCFUtils.sort_tasks_by_priority(assignedTasks, tasks);

% =========================
% 2) 计算路径距离（闭环）
% =========================
% 智能体初始坐标
startXY = [agents(agentIdx).x, agents(agentIdx).y];

% totalDistance：根据起点 startXY 和 orderedTasks，计算走完任务的总路线长度
% “闭环”通常表示最后还要回到 startXY（具体依赖 compute_route_distance 的实现）
totalDistance = OCFUtils.compute_route_distance(startXY, orderedTasks, tasks);

% =========================
% 3) 能量模型参数
% =========================
% alpha_fly  : 单位飞行时间耗能系数（或单位距离/时间的燃料系数，你这里用的是“乘时间”）
% alpha_wait : 单位等待时间耗能系数（悬停/待机耗电）
% beta       : 单位执行时间耗能系数（做任务动作耗电）
alpha_fly  = agents(agentIdx).fuel;
alpha_wait = agents(agentIdx).wait_fuel;
beta       = agents(agentIdx).beta;



% 为每个任务建立时间数组（列向量），先全置0

% 下面这几行是你原来可能用于“非同步模式自行累积时间”的草稿（当前被注释掉）
% curr_pos = startXY;           % 当前坐标
% curr_time = 0;                % 当前时间
% v = agents(agentIdx).vel;     % 速度（若固定速度，飞行时间=距离/速度）


% 同步模式：直接调用全局调度器/仿真器去算
% calc_with_global_sync 应该会：
%   - 依据 orderedTasks 路线、速度、任务持续时间、以及 SC 的同步/资源约束
%   - 输出总飞行/等待/执行时间，以及每个任务的开始/执行/完成时刻
[t_fly_total, t_wait_total, t_exec_total, start_times, execution_times, completion_times,mission_end_time] = ...
    WorldSim.calc_with_global_sync(agentIdx, orderedTasks, agents, tasks, Value_Params, SC, tol);

% =========================
% 6) 输出整理与能耗计算
% =========================
% 兼容接口：task_start_times 与 start_times 相同
task_start_times = start_times;

% 总能耗：飞行能耗 + 等待能耗 + 执行能耗
requiredEnergy = t_fly_total * alpha_fly + ...
    t_wait_total * alpha_wait + ...
    t_exec_total * beta;
end