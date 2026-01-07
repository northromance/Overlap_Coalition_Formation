function display_task_schedule(Value_data, agents, tasks, Value_Params)
% display_task_schedule: 显示所有智能体的任务执行调度信息
%
% 输入参数：
%   Value_data   - 智能体数据结构数组（需包含task_schedule字段）
%   agents       - 智能体结构体数组
%   tasks        - 任务结构体数组
%   Value_Params - 参数结构体
%
% 显示内容：
%   - 每个智能体的任务执行序列
%   - 各任务的时间信息（到达、开始、执行、完成时间）
%   - 甘特图（可选）

    fprintf('\n========== 任务执行调度信息 ==========\n\n');
    
    N = Value_Params.N;
    total_system_energy = 0;
    
    for i = 1:N
        schedule = Value_data(i).task_schedule;
        
        fprintf('--- 智能体 %d ---\n', i);
        
        if isempty(schedule.task_sequence)
            fprintf('  未分配任何任务\n\n');
            continue;
        end
        
        % 打印任务序列
        task_names = arrayfun(@(t) sprintf('T%d', t), schedule.task_sequence, 'UniformOutput', false);
        fprintf('  任务序列: %s\n', strjoin(task_names, ' -> '));
        
        % 打印详细时间表
        fprintf('  %-8s %-10s %-10s %-10s %-10s\n', '任务', '到达时间', '开始时间', '执行时间', '完成时间');
        fprintf('  %s\n', repmat('-', 1, 50));
        
        for ii = 1:numel(schedule.task_sequence)
            task_id = schedule.task_sequence(ii);
            arr_time = schedule.arrival_times(ii);
            start_time = schedule.start_times(ii);
            exec_time = schedule.execution_times(ii);
            comp_time = schedule.completion_times(ii);
            
            fprintf('  T%-7d %-10.2f %-10.2f %-10.2f %-10.2f\n', ...
                task_id, arr_time, start_time, exec_time, comp_time);
        end
        
        % 打印汇总信息
        fprintf('  %s\n', repmat('-', 1, 50));
        fprintf('  总飞行时间: %.2f\n', schedule.total_flight_time);
        fprintf('  总执行时间: %.2f\n', schedule.total_execution_time);
        fprintf('  总能量消耗: %.2f\n', schedule.total_energy);
        fprintf('\n');
        
        total_system_energy = total_system_energy + schedule.total_energy;
    end
    
    fprintf('========== 系统总能量消耗: %.2f ==========\n\n', total_system_energy);
end
