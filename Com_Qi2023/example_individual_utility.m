%% 个体效用按比例分配示例
% 
% 公式: u_n = (|A_m^(n)| / sum(|A_m^(n')|)) * U_m(A_m)
%
% 其中:
%   u_n - UAV n的个体效用
%   |A_m^(n)| - UAV n对任务m贡献的资源总量
%   sum(|A_m^(n')|) - 联盟成员对任务m贡献的总资源量
%   U_m(A_m) - 任务m的总效用

%% 示例场景
% 任务1: 价值100, 需求[10, 20]
% UAV1贡献[5, 10], UAV2贡献[5, 10]
% 任务总效用: 100 * 1.0 - 距离成本 = 95

% 计算个体贡献比例
A_1_uav1 = norm([5, 10]);    % UAV1贡献量: sqrt(25+100) = 11.18
A_1_uav2 = norm([5, 10]);    % UAV2贡献量: sqrt(25+100) = 11.18
total_contribution = A_1_uav1 + A_1_uav2;  % 总贡献: 22.36

% 按比例分配
u_uav1 = (A_1_uav1 / total_contribution) * 95;  % 47.5
u_uav2 = (A_1_uav2 / total_contribution) * 95;  % 47.5

fprintf('任务总效用: %.2f\n', 95);
fprintf('UAV1个体效用: %.2f (贡献比例: %.1f%%)\n', u_uav1, A_1_uav1/total_contribution*100);
fprintf('UAV2个体效用: %.2f (贡献比例: %.1f%%)\n', u_uav2, A_1_uav2/total_contribution*100);
fprintf('效用总和: %.2f (应等于任务总效用)\n', u_uav1 + u_uav2);

%% 正确的个体效用计算函数
function individual_utilities = calc_individual_utility(SC, agent_resources, tasks, dist_matrix, N, M, K)
    % 返回N×M矩阵，每个元素是UAV n从任务m获得的个体效用
    individual_utilities = zeros(N, M);
    
    for m = 1:M
        % 找到参与任务m的UAV
        members = [];
        allocated = zeros(1, K);
        contributions = zeros(N, 1);  % 每个UAV的贡献量
        
        for n = 1:N
            if any(SC(m, n, :) > 0)
                members = [members, n];
                agent_alloc = zeros(1, K);
                for z = 1:K
                    if SC(m, n, z) > 0
                        agent_alloc(z) = agent_resources(n, z);
                        allocated(z) = allocated(z) + agent_resources(n, z);
                    end
                end
                % 计算该UAV的贡献量 |A_m^(n)|
                contributions(n) = norm(agent_alloc);
            end
        end
        
        if ~isempty(members)
            % 计算任务m的总效用
            demand = tasks(m).resource_demand(:)';
            if length(demand) < K
                demand = [demand, zeros(1, K - length(demand))];
            end
            D_C = calc_task_completion_degree(allocated, demand, K);
            
            total_dist = 0;
            for n = members
                total_dist = total_dist + dist_matrix(n, m);
            end
            U_m = tasks(m).value * D_C - total_dist * 0.1;
            
            % 按比例分配给每个成员
            total_contribution = sum(contributions);
            if total_contribution > 0
                for n = members
                    individual_utilities(n, m) = (contributions(n) / total_contribution) * U_m;
                end
            end
        end
    end
end
