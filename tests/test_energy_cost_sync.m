% test_energy_cost_sync.m - 测试energy_cost函数的固定速度+等待模型
% =========================================================================
% 扩展测试：5个智能体，6个任务，不同速度
% 验证固定速度飞行 + 先到等待的同步机制
% =========================================================================

clear; clc;
fprintf('==========================================================================\n');
fprintf('   energy_cost 固定速度+等待模型测试 - 5智能体 × 6任务\n');
fprintf('==========================================================================\n\n');

% 添加SA文件夹路径
addpath(fullfile(fileparts(pwd), 'SA'));

%% ========================================================================
% 场景配置
% ========================================================================
% 
% 新模型说明（固定速度+等待）：
%   1. 每个智能体以固定速度飞行，不调整速度
%   2. 先到达的智能体在任务点等待后到达的智能体
%   3. 所有参与者到齐后，同步开始执行任务
%   4. 执行完成后，所有参与者同时离开
%
% 能量模型：
%   总能量 = 飞行时间 × α_fly + 等待时间 × α_wait + 执行时间 × β
%   其中 α_wait = α_fly × 0.5（悬停能耗约为飞行的一半）
%
% ========================================================================

fprintf('【场景配置】\n');
fprintf('─────────────────────────────────────────────────────────────────────────\n');

%% --- 初始化智能体 ---
N = 5;
agents = struct('id', {}, 'x', {}, 'y', {}, 'vel', {}, 'fuel', {}, 'beta', {}, 'Emax', {}, 'resources', {});

agents(1).id = 1;  agents(1).x = 0;    agents(1).y = 0;    agents(1).vel = 10;
agents(2).id = 2;  agents(2).x = 0;    agents(2).y = 100;  agents(2).vel = 5;   % 最慢
agents(3).id = 3;  agents(3).x = 100;  agents(3).y = 0;    agents(3).vel = 15;  % 最快
agents(4).id = 4;  agents(4).x = 100;  agents(4).y = 100;  agents(4).vel = 8;
agents(5).id = 5;  agents(5).x = 50;   agents(5).y = 50;   agents(5).vel = 12;

for i = 1:N
    agents(i).fuel = 1.0;
    agents(i).beta = 0.5;
    agents(i).Emax = 1000;
    agents(i).resources = [5; 5];
end

fprintf('智能体配置:\n');
fprintf('  ┌─────────┬────────────┬────────┬────────────┐\n');
fprintf('  │ 智能体  │   位置     │  速度  │ α_fly/β   │\n');
fprintf('  ├─────────┼────────────┼────────┼────────────┤\n');
for i = 1:N
    fprintf('  │   %d     │ (%3d,%3d)  │  %2d    │ %.1f/%.1f   │\n', ...
        i, agents(i).x, agents(i).y, agents(i).vel, agents(i).fuel, agents(i).beta);
end
fprintf('  └─────────┴────────────┴────────┴────────────┘\n\n');

%% --- 初始化任务 ---
M = 6;
K = 2;
tasks = struct('id', {}, 'x', {}, 'y', {}, 'priority', {}, 'value', {}, 'type', {}, ...
               'resource_demand', {}, 'duration_by_resource', {}, 'duration', {});

tasks(1).id = 1;  tasks(1).x = 30;  tasks(1).y = 30;  tasks(1).priority = 1;
tasks(2).id = 2;  tasks(2).x = 70;  tasks(2).y = 30;  tasks(2).priority = 1;
tasks(3).id = 3;  tasks(3).x = 30;  tasks(3).y = 70;  tasks(3).priority = 2;
tasks(4).id = 4;  tasks(4).x = 70;  tasks(4).y = 70;  tasks(4).priority = 2;
tasks(5).id = 5;  tasks(5).x = 50;  tasks(5).y = 50;  tasks(5).priority = 3;
tasks(6).id = 6;  tasks(6).x = 50;  tasks(6).y = 20;  tasks(6).priority = 4;

tasks(1).duration_by_resource = [4, 3];  tasks(1).duration = 4;
tasks(2).duration_by_resource = [5, 4];  tasks(2).duration = 5;
tasks(3).duration_by_resource = [3, 6];  tasks(3).duration = 6;
tasks(4).duration_by_resource = [4, 5];  tasks(4).duration = 5;
tasks(5).duration_by_resource = [6, 4];  tasks(5).duration = 6;
tasks(6).duration_by_resource = [8, 7];  tasks(6).duration = 8;

for m = 1:M
    tasks(m).value = 1000;
    tasks(m).type = 1;
    tasks(m).resource_demand = [3, 3];
end

fprintf('任务配置:\n');
fprintf('  ┌───────┬────────────┬──────────┬─────────────────────┐\n');
fprintf('  │ 任务  │   位置     │ 优先级   │ duration_by_resource│\n');
fprintf('  ├───────┼────────────┼──────────┼─────────────────────┤\n');
for m = 1:M
    fprintf('  │  %d    │ (%3d,%3d)  │    %d     │      [%d, %d]         │\n', ...
        m, tasks(m).x, tasks(m).y, tasks(m).priority, ...
        tasks(m).duration_by_resource(1), tasks(m).duration_by_resource(2));
end
fprintf('  └───────┴────────────┴──────────┴─────────────────────┘\n\n');

%% --- 初始化参数 ---
Value_Params.N = N;
Value_Params.M = M;
Value_Params.K = K;

%% --- 初始化联盟结构 SC ---
SC = cell(1, M);
for m = 1:M
    SC{m} = zeros(N, K);
end

% 任务1: 智能体1+2协同
SC{1}(1, :) = [1, 0];
SC{1}(2, :) = [0, 1];

% 任务2: 智能体3单独
SC{2}(3, :) = [1, 1];

% 任务3: 智能体4+5协同
SC{3}(4, :) = [1, 0];
SC{3}(5, :) = [0, 1];

% 任务4: 智能体1+3协同
SC{4}(1, :) = [0, 1];
SC{4}(3, :) = [1, 0];

% 任务5: 智能体2+4+5协同
SC{5}(2, :) = [1, 0];
SC{5}(4, :) = [0, 1];
SC{5}(5, :) = [0.5, 0.5];

% 任务6: 全员协同
SC{6}(1, :) = [0.5, 0];
SC{6}(2, :) = [0, 0.5];
SC{6}(3, :) = [0.5, 0];
SC{6}(4, :) = [0, 0.5];
SC{6}(5, :) = [0.5, 0.5];

fprintf('联盟结构 (任务分配):\n');
task_participants = cell(M, 1);
for m = 1:M
    participants = find(any(SC{m} > 1e-9, 2))';
    task_participants{m} = participants;
    fprintf('  任务%d: 智能体 [%s]\n', m, num2str(participants));
end
fprintf('\n');

%% --- 构建各智能体的资源分配矩阵 ---
R_agents = cell(N, 1);
agent_tasks = cell(N, 1);

for i = 1:N
    R_agents{i} = zeros(M, K);
    agent_tasks{i} = [];
    for m = 1:M
        if any(SC{m}(i, :) > 1e-9)
            R_agents{i}(m, :) = SC{m}(i, :);
            agent_tasks{i} = [agent_tasks{i}, m];
        end
    end
end

fprintf('智能体任务分配:\n');
for i = 1:N
    fprintf('  智能体%d: 任务 [%s]\n', i, num2str(agent_tasks{i}));
end
fprintf('\n');

%% ========================================================================
% 执行测试
% ========================================================================
fprintf('==========================================================================\n');
fprintf('【固定速度+等待模型执行结果】\n');
fprintf('==========================================================================\n\n');

% 存储所有结果
results = struct('agent', {}, 't_fly', {}, 't_wait', {}, 't_exec', {}, 'energy', {}, ...
                 'ordered', {}, 'arrivals', {});

for i = 1:N
    if isempty(agent_tasks{i})
        continue;
    end
    
    % 新接口: [t_fly, T_exec, dist, energy, ordered, arrivals, t_wait]
    [t_fly, t_exec, dist, energy, ordered, arrivals, t_wait] = ...
        energy_cost(i, agent_tasks{i}, agents, tasks, Value_Params, R_agents{i}, SC);
    
    results(i).agent = i;
    results(i).t_fly = t_fly;
    results(i).t_wait = t_wait;
    results(i).t_exec = t_exec;
    results(i).dist = dist;
    results(i).energy = energy;
    results(i).ordered = ordered;
    results(i).arrivals = arrivals;
end

%% --- 打印每个智能体的详细执行信息 ---
fprintf('─────────────────────────────────────────────────────────────────────────\n');
fprintf('各智能体执行详情:\n');
fprintf('─────────────────────────────────────────────────────────────────────────\n\n');

for i = 1:N
    if isempty(agent_tasks{i})
        fprintf('智能体%d: 无任务分配\n\n', i);
        continue;
    end
    
    fprintf('【智能体%d】速度=%d, 起点=(%d,%d)\n', i, agents(i).vel, agents(i).x, agents(i).y);
    fprintf('  任务序列: [%s] (按优先级排序)\n', num2str(results(i).ordered));
    fprintf('  ┌─────────┬──────────────┬──────────────┬──────────────┬──────────────┐\n');
    fprintf('  │  任务   │  我的到达    │  同步开始    │   等待时间   │   执行时间   │\n');
    fprintf('  ├─────────┼──────────────┼──────────────┼──────────────┼──────────────┤\n');
    
    current_pos = [agents(i).x, agents(i).y];
    current_ready_time = 0;
    v = agents(i).vel;
    
    for idx = 1:numel(results(i).ordered)
        task_id = results(i).ordered(idx);
        task_pos = [tasks(task_id).x, tasks(task_id).y];
        
        % 飞行时间
        dist_to_task = norm(task_pos - current_pos);
        fly_time = dist_to_task / v;
        my_arrival = current_ready_time + fly_time;
        
        % 同步开始时间
        sync_start = results(i).arrivals(idx);
        
        % 等待时间
        wait_time = max(0, sync_start - my_arrival);
        
        % 执行时间
        R_row = R_agents{i}(task_id, :);
        used = R_row > 1e-9;
        dur = tasks(task_id).duration_by_resource;
        my_exec = max([dur(used), 0]);
        
        fprintf('  │   T%d    │    %7.2f   │    %7.2f   │    %7.2f   │    %7.2f   │\n', ...
            task_id, my_arrival, sync_start, wait_time, my_exec);
        
        % 更新状态
        coalition_exec = max([dur, 0]);  % 联盟执行时间
        current_ready_time = sync_start + coalition_exec;
        current_pos = task_pos;
    end
    fprintf('  └─────────┴──────────────┴──────────────┴──────────────┴──────────────┘\n');
    
    % 计算能量分解
    alpha_fly = agents(i).fuel;
    alpha_wait = alpha_fly * 0.5;
    beta = agents(i).beta;
    
    fprintf('  时间统计: 飞行=%.2f, 等待=%.2f, 执行=%.2f\n', ...
        results(i).t_fly, results(i).t_wait, results(i).t_exec);
    fprintf('  能量分解: 飞行能量=%.2f, 等待能量=%.2f, 执行能量=%.2f, 总计=%.2f\n\n', ...
        results(i).t_fly * alpha_fly, ...
        results(i).t_wait * alpha_wait, ...
        results(i).t_exec * beta, ...
        results(i).energy);
end

%% --- 打印任务同步验证 ---
fprintf('==========================================================================\n');
fprintf('【任务同步验证】\n');
fprintf('==========================================================================\n\n');

priorities = arrayfun(@(t) t.priority, tasks);
[~, task_order] = sort(priorities);

for order_idx = 1:M
    task_id = task_order(order_idx);
    participants = task_participants{task_id};
    task_pos = [tasks(task_id).x, tasks(task_id).y];
    
    fprintf('任务%d (优先级%d, 位置(%d,%d)):\n', ...
        task_id, tasks(task_id).priority, tasks(task_id).x, tasks(task_id).y);
    fprintf('  参与者: 智能体 [%s]\n', num2str(participants));
    
    if numel(participants) > 1
        arrival_times = zeros(numel(participants), 1);
        my_arrivals = zeros(numel(participants), 1);  % 各自的实际到达时间
        
        for k = 1:numel(participants)
            agent_id = participants(k);
            task_pos_in_agent = find(results(agent_id).ordered == task_id, 1);
            if ~isempty(task_pos_in_agent)
                arrival_times(k) = results(agent_id).arrivals(task_pos_in_agent);
            end
        end
        
        fprintf('  同步开始时间:\n');
        for k = 1:numel(participants)
            fprintf('    智能体%d: %.2f\n', participants(k), arrival_times(k));
        end
        
        if max(arrival_times) - min(arrival_times) < 1e-3
            fprintf('  ? 同步成功! 所有智能体同时开始 (时间=%.2f)\n', arrival_times(1));
        else
            fprintf('  ? 同步失败! 开始时间不一致 (差值=%.4f)\n', max(arrival_times) - min(arrival_times));
        end
    else
        agent_id = participants(1);
        task_pos_in_agent = find(results(agent_id).ordered == task_id, 1);
        arrival = results(agent_id).arrivals(task_pos_in_agent);
        fprintf('  单智能体执行, 开始时间: %.2f\n', arrival);
    end
    fprintf('\n');
end

%% --- 测试总结 ---
fprintf('==========================================================================\n');
fprintf('【测试总结】\n');
fprintf('==========================================================================\n\n');

% 验证同步
all_sync_ok = true;
for m = 1:M
    participants = task_participants{m};
    if numel(participants) > 1
        arrival_times = zeros(numel(participants), 1);
        for k = 1:numel(participants)
            agent_id = participants(k);
            task_pos_in_agent = find(results(agent_id).ordered == m, 1);
            if ~isempty(task_pos_in_agent)
                arrival_times(k) = results(agent_id).arrivals(task_pos_in_agent);
            end
        end
        if max(arrival_times) - min(arrival_times) >= 1e-3
            all_sync_ok = false;
            fprintf('? 任务%d 同步失败\n', m);
        end
    end
end

if all_sync_ok
    fprintf('? 所有协同任务同步正确!\n\n');
else
    fprintf('? 存在同步失败的任务\n\n');
end

fprintf('各智能体统计:\n');
fprintf('  ┌─────────┬──────────┬──────────┬──────────┬──────────┬──────────┐\n');
fprintf('  │ 智能体  │ 飞行时间 │ 等待时间 │ 执行时间 │ 总距离   │ 总能量   │\n');
fprintf('  ├─────────┼──────────┼──────────┼──────────┼──────────┼──────────┤\n');
for i = 1:N
    if ~isempty(agent_tasks{i})
        fprintf('  │   %d     │  %6.2f  │  %6.2f  │  %6.2f  │  %6.2f  │  %6.2f  │\n', ...
            i, results(i).t_fly, results(i).t_wait, results(i).t_exec, results(i).dist, results(i).energy);
    end
end
fprintf('  └─────────┴──────────┴──────────┴──────────┴──────────┴──────────┘\n');

fprintf('\n固定速度+等待模型验证:\n');
fprintf('  ? 固定速度飞行: 每个智能体以自己的固定速度飞行\n');
fprintf('  ? 先到等待: 先到达的智能体等待后到达的智能体\n');
fprintf('  ? 同步执行: 所有参与者到齐后一起开始执行\n');
fprintf('  ? 能量分解: 飞行能量 + 等待能量(×0.5) + 执行能量\n');
