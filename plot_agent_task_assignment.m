function plot_agent_task_assignment(Value_data, agents, tasks, Value_Params)
% PLOT_AGENT_TASK_ASSIGNMENT - 可视化智能体的任务执行列表及资源分配
%
% 输入参数：
%   Value_data - 智能体数据结构
%   agents - 智能体信息数组
%   tasks - 任务信息数组
%   Value_Params - 参数结构体

N = Value_Params.N;
M = Value_Params.M;
K = Value_Params.K;

% 提取联盟结构和资源分配
coalitionstru = Value_data(1).coalitionstru;
SC = Value_data(1).SC;

% 创建图形
figure('Position', [100, 100, 1400, 800]);

% 定义资源类型名称
resource_names = arrayfun(@(k) sprintf('R%d', k), 1:K, 'UniformOutput', false);

% 为每个智能体创建子图
for i = 1:N
    subplot(ceil(N/2), 2, i);
    
    % 找出智能体i参与的任务
    assigned_tasks = find(coalitionstru(1:M, i) ~= 0);
    
    if isempty(assigned_tasks)
        % 该智能体未分配任何任务
        text(0.5, 0.5, sprintf('智能体A%d\n未分配任务', i), ...
             'HorizontalAlignment', 'center', ...
             'FontSize', 12, 'FontWeight', 'bold');
        axis off;
        continue;
    end
    
    % 准备数据：每个任务分配的资源
    num_tasks = length(assigned_tasks);
    resource_allocation = zeros(num_tasks, K);
    
    for t = 1:num_tasks
        task_id = assigned_tasks(t);
        resource_allocation(t, :) = SC{task_id}(i, :);
    end
    
    % 绘制堆叠柱状图
    bar_handle = bar(resource_allocation, 'stacked');
    
    % 设置颜色
    colors = parula(K);
    if length(bar_handle) >= K
        for k = 1:K
            set(bar_handle(k), 'FaceColor', colors(k, :));
        end
    end
    
    % 设置标签和标题
    xlabel('任务序号', 'FontSize', 10, 'FontWeight', 'bold');
    ylabel('分配资源量', 'FontSize', 10, 'FontWeight', 'bold');
    title(sprintf('智能体A%d的任务分配 (共%d个任务)', i, num_tasks), ...
          'FontSize', 11, 'FontWeight', 'bold');
    
    % 设置X轴刻度标签为任务ID
    task_labels = arrayfun(@(tid) sprintf('T%d', tid), assigned_tasks, 'UniformOutput', false);
    set(gca, 'XTick', 1:num_tasks, 'XTickLabel', task_labels);
    
    % 添加网格
    grid on;
    set(gca, 'FontSize', 9);
    
    % 在柱子上方标注总资源量
    for t = 1:num_tasks
        total_resource = sum(resource_allocation(t, :));
        if total_resource > 0
            text(t, total_resource, sprintf('%.0f', total_resource), ...
                 'HorizontalAlignment', 'center', ...
                 'VerticalAlignment', 'bottom', ...
                 'FontSize', 8, 'FontWeight', 'bold');
        end
    end
    
    % 只在第一个子图添加图例
    if i == 1
        legend(resource_names, 'Location', 'northeast', 'FontSize', 8);
    end
end

% 总标题
sgtitle('智能体任务分配与资源使用详情', 'FontSize', 14, 'FontWeight', 'bold');

% 打印详细的资源分配表
fprintf('\n========================================\n');
fprintf('  智能体任务分配与资源明细表\n');
fprintf('========================================\n\n');

for i = 1:N
    assigned_tasks = find(coalitionstru(1:M, i) ~= 0);
    
    fprintf('【智能体 A%d】\n', i);
    fprintf('  拥有资源: [');
    fprintf('%d ', agents(i).resources);
    fprintf(']\n');
    
    if isempty(assigned_tasks)
        fprintf('  分配任务: 无\n\n');
        continue;
    end
    
    fprintf('  分配任务: %d个\n\n', length(assigned_tasks));
    
    % 打印每个任务的详细分配
    for t = 1:length(assigned_tasks)
        task_id = assigned_tasks(t);
        fprintf('  任务T%d (类型%d, 价值%d):\n', ...
                task_id, tasks(task_id).type, tasks(task_id).value);
        fprintf('    需求: [');
        fprintf('%d ', tasks(task_id).resource_demand);
        fprintf(']\n');
        fprintf('    分配: [');
        fprintf('%d ', SC{task_id}(i, :));
        fprintf(']\n');
        
        % 计算资源使用率
        for k = 1:K
            if SC{task_id}(i, k) > 0
                fprintf('      资源R%d: %d (占有资源的%.1f%%)\n', ...
                        k, SC{task_id}(i, k), ...
                        100 * SC{task_id}(i, k) / agents(i).resources(k));
            end
        end
    end
    
    % 计算总资源使用
    total_allocated = zeros(1, K);
    for t_idx = 1:length(assigned_tasks)
        task_id = assigned_tasks(t_idx);
        total_allocated = total_allocated + SC{task_id}(i, :);
    end
    
    fprintf('  总分配: [');
    fprintf('%d ', total_allocated);
    fprintf(']\n');
    fprintf('  剩余资源: [');
    fprintf('%d ', agents(i).resources' - total_allocated);
    fprintf(']\n');
    fprintf('  资源利用率: ');
    for k = 1:K
        fprintf('R%d=%.1f%% ', k, 100 * total_allocated(k) / agents(i).resources(k));
    end
    fprintf('\n\n');
end

fprintf('========================================\n\n');

end
