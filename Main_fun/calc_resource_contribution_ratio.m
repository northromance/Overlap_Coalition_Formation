function r_n = calc_resource_contribution_ratio(SC_m, agent_idx, member_indices)
% CALC_RESOURCE_CONTRIBUTION_RATIO 计算智能体在联盟中的资源贡献比例 r_n(C)
%
% 计算公式：r_n(C) = ||A_n|| / Σ||A_i||
%   其中 A_n 是智能体n分配的资源向量，||·|| 是欧几里得范数
%
% 输入:
%   SC_m - 任务m的资源分配矩阵 (N×K)，每行表示一个智能体的资源分配
%   agent_idx - 要计算贡献比例的智能体索引
%   member_indices - 参与该任务的所有智能体索引向量
%
% 输出:
%   r_n - 智能体的资源贡献比例 (0~1)
%
% 示例:
%   SC_m = [2, 3, 0; 1, 2, 1; 0, 0, 0];  % 3个智能体的资源分配
%   members = [1, 2];  % 智能体1和2参与
%   r_1 = calc_resource_contribution_ratio(SC_m, 1, members);

    % 计算当前智能体的资源范数
    A_n = norm(SC_m(agent_idx, :));
    
    % 计算所有参与成员的资源范数之和
    total_norm = 0;
    for i = 1:length(member_indices)
        member_id = member_indices(i);
        total_norm = total_norm + norm(SC_m(member_id, :));
    end
    
    % 计算贡献比例
    if total_norm > 1e-9
        r_n = A_n / total_norm;
    else
        % 如果总资源为0，平均分配
        r_n = 1 / max(length(member_indices), 1);
    end
end
