%% 对比：互斥联盟 vs 重叠联盟 在贪婪算法中的差异

fprintf('========================================\n');
fprintf('  互斥联盟 vs 重叠联盟 对比\n');
fprintf('========================================\n\n');

%% 模拟场景
fprintf('场景设置:\n');
fprintf('  智能体1: 资源[5, 3], 能量100, 位置(10, 10)\n');
fprintf('  任务A: 需求[3, 2], 价值100, 位置(20, 10)\n');
fprintf('  任务B: 需求[2, 1], 价值80,  位置(35, 10)\n');
fprintf('  任务C: 需求[4, 2], 价值120, 位置(50, 10)\n\n');

agent1_resources = [5, 3];
agent1_energy = 100;
agent1_pos = [10, 10];

tasks = struct('demand', {[3,2], [2,1], [4,2]}, ...
               'value', {100, 80, 120}, ...
               'pos', {[20,10], [35,10], [50,10]}, ...
               'name', {'A', 'B', 'C'});

%% 方法1：互斥联盟（当前贪婪算法）
fprintf('========================================\n');
fprintf('方法1: 互斥联盟（资源互斥分配）\n');
fprintf('========================================\n\n');

remaining_res = agent1_resources;
total_utility_exclusive = 0;

fprintf('处理过程:\n');
for j = 1:3
    dist = norm(tasks(j).pos - agent1_pos);
    
    fprintf('  任务%s:\n', tasks(j).name);
    fprintf('    - 需求: [%d, %d]\n', tasks(j).demand);
    fprintf('    - 剩余资源: [%d, %d]\n', remaining_res);
    
    % 尝试分配
    can_allocate = all(remaining_res >= tasks(j).demand);
    
    if can_allocate
        allocated = tasks(j).demand;
        remaining_res = remaining_res - allocated;
        
        % 计算完成度
        D_C = mean(min(allocated ./ tasks(j).demand, 1.0));
        distance_cost = dist * 0.1;
        utility = tasks(j).value * D_C - distance_cost;
        
        fprintf('    - 分配: [%d, %d]\n', allocated);
        fprintf('    - 完成度: %.1f%%\n', D_C*100);
        fprintf('    - 效用: %.2f\n', utility);
        total_utility_exclusive = total_utility_exclusive + utility;
    else
        fprintf('    - 分配: 失败（资源不足）\n');
    end
    fprintf('\n');
end

fprintf('结果:\n');
fprintf('  - 完成任务数: 1/3\n');
fprintf('  - 总效用: %.2f\n', total_utility_exclusive);
fprintf('  - 智能体1参与: 1个任务\n\n');

%% 方法2：重叠联盟（能量约束）
fprintf('========================================\n');
fprintf('方法2: 重叠联盟（资源可复用，能量约束）\n');
fprintf('========================================\n\n');

remaining_energy = agent1_energy;
total_utility_overlap = 0;
tasks_completed = 0;

fprintf('处理过程:\n');
for j = 1:3
    dist = norm(tasks(j).pos - agent1_pos);
    
    fprintf('  任务%s:\n', tasks(j).name);
    fprintf('    - 需求: [%d, %d]\n', tasks(j).demand);
    fprintf('    - 可用资源: [%d, %d] (完整资源)\n', agent1_resources);
    
    % 计算能量消耗
    fly_energy = dist * 0.5;  % 假设燃料系数0.5
    exec_energy = 10;  % 假设执行能量10
    total_energy_cost = fly_energy + exec_energy;
    
    fprintf('    - 所需能量: %.1f (飞行%.1f + 执行%.1f)\n', ...
            total_energy_cost, fly_energy, exec_energy);
    fprintf('    - 剩余能量: %.1f\n', remaining_energy);
    
    % 检查能量是否足够
    if remaining_energy >= total_energy_cost
        % 使用完整资源
        allocated = min(agent1_resources, tasks(j).demand);
        remaining_energy = remaining_energy - total_energy_cost;
        
        % 计算完成度
        D_C = mean(min(allocated ./ tasks(j).demand, 1.0));
        distance_cost = dist * 0.1;
        utility = tasks(j).value * D_C - distance_cost;
        
        fprintf('    - 分配: [%d, %d] (资源复用)\n', allocated);
        fprintf('    - 完成度: %.1f%%\n', D_C*100);
        fprintf('    - 效用: %.2f\n', utility);
        fprintf('    - 扣除能量后剩余: %.1f\n', remaining_energy);
        
        total_utility_overlap = total_utility_overlap + utility;
        tasks_completed = tasks_completed + 1;
    else
        fprintf('    - 分配: 失败（能量不足）\n');
    end
    fprintf('\n');
end

fprintf('结果:\n');
fprintf('  - 完成任务数: %d/3\n', tasks_completed);
fprintf('  - 总效用: %.2f\n', total_utility_overlap);
fprintf('  - 智能体1参与: %d个任务\n\n', tasks_completed);

%% 总结对比
fprintf('========================================\n');
fprintf('  对比总结\n');
fprintf('========================================\n\n');

fprintf('+-----------------+----------+----------+\n');
fprintf('|     指标        | 互斥联盟 | 重叠联盟 |\n');
fprintf('+-----------------+----------+----------+\n');
fprintf('| 完成任务数      |   1/3    |   %d/3   |\n', tasks_completed);
fprintf('| 总效用          | %.2f   | %.2f  |\n', total_utility_exclusive, total_utility_overlap);
fprintf('| 智能体利用率    |   低     |   高     |\n');
fprintf('| 资源利用方式    | 互斥消耗 | 时间复用 |\n');
fprintf('| 约束条件        | 资源量   | 能量预算 |\n');
fprintf('+-----------------+----------+----------+\n\n');

fprintf('关键差异:\n');
fprintf('  1. 互斥联盟：资源用完就没了，后续任务无法完成\n');
fprintf('  2. 重叠联盟：资源可复用，受能量约束限制参与数量\n');
fprintf('  3. 重叠联盟更符合实际：同一智能体可以先后完成多个任务\n');
fprintf('  4. 重叠联盟总效用更高：充分利用智能体能力\n\n');

fprintf('========================================\n');
