function display_task_resource_match_details(tasks, task_demand, task_allocated, K, M)
% 显示表7：每个任务的资源匹配详情（需求/已分配/缺口/状态）
% 输入：tasks，task_demand (M×K)，task_allocated (M×K)，K资源类型数，M任务数

resNames = arrayfun(@(k) sprintf('Res%d', k), 1:K, 'UniformOutput', false);

fprintf('\n【表7：任务资源匹配详情 (需求/已分配/缺口)】\n');
for m = 1:M
    fprintf('\n--- 任务 T%d (优先级=%d, 类型=%d) ---\n', m, tasks(m).priority, tasks(m).type);
    match_table = table();
    match_table.ResourceType = resNames';
    match_table.Demand = task_demand(m, :)';
    match_table.Allocated = task_allocated(m, :)';
    match_table.Gap = task_demand(m, :)' - task_allocated(m, :)';
    match_table.Status = cell(K, 1);
    for r = 1:K
        gap = match_table.Gap(r);
        if gap < 0
            match_table.Status{r} = '过量';
        elseif gap > 0
            match_table.Status{r} = '不足';
        else
            match_table.Status{r} = '满足';
        end
    end
    disp(match_table);
end
end
