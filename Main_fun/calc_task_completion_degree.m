function D_C = calc_task_completion_degree(allocated_resources, task_demand, K)
% CALC_TASK_COMPLETION_DEGREE 计算任务的资源完成度 D_C
%
% 计算公式：D_C = (1/Z_c) × Σ min(allocated_k / demand_k, 1.0)
% 
% 输入:
%   allocated_resources - 分配给任务的资源向量 (1×K) 或矩阵 (N×K)
%                        如果是矩阵，会自动求和每列
%   task_demand - 任务的资源需求向量 (1×K)
%   K - 资源类型数量
%
% 输出:
%   D_C - 任务完成度 (0~1)，表示资源满足程度
%
% 示例:
%   SC_m = [2, 3, 0; 1, 2, 1];  % 2个智能体的资源分配 (2×3)
%   demand = [3, 4, 2];          % 任务需求
%   D_C = calc_task_completion_degree(SC_m, demand, 3);

    % 如果allocated_resources是矩阵，求和每列
    if size(allocated_resources, 1) > 1
        allocated = sum(allocated_resources, 1);
    else
        allocated = allocated_resources;
    end
    
    % 确保维度正确
    if length(allocated) < K
        allocated = [allocated, zeros(1, K - length(allocated))];
    end
    if length(task_demand) < K
        task_demand = [task_demand, zeros(1, K - length(task_demand))];
    end
    
    % 计算有需求的资源类型数量
    Z_c = nnz(task_demand > 1e-9);
    
    if Z_c == 0
        D_C = 1;  % 如果没有需求，认为完成度为1
        return;
    end
    
    % 计算资源完成度
    D_C = 0;
    for k = 1:K
        if task_demand(k) > 1e-9
            ratio = min(allocated(k) / task_demand(k), 1.0);
            D_C = D_C + ratio;
        end
    end
    D_C = D_C / Z_c;
end
