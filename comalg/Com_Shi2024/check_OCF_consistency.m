function [is_valid, error_log] = check_OCF_consistency(Value_data, agents, Value_Params)
% CHECK_OCF_CONSISTENCY 验证 OCF (重叠联盟) 场景下的数据一致性
%
% 修改说明：
%   1. [资源复用模式] Step 1 改为检查“单任务资源越界”。
%      即：任意 j, SC{j}(i,:) <= Agent(i).resources。
%      不再对所有任务的资源进行求和。
%   2. Step 2 & 3 保持不变，用于检测数据同步问题。
%
% 输入：
%   Value_data   : 1xN 结构体数组
%   agents       : 智能体数组 (用于获取 .resources 上限)
%   Value_Params : 全局参数 (M, N, K)

    is_valid = true;
    error_log = {};
    tol = 1e-5; 
    
    N = Value_Params.N;
    M = Value_Params.M;
    K = Value_Params.K;

    fprintf('==============================================\n');
    fprintf('开始 OCF 数据一致性检查 (资源复用模式)...\n');

    %% 1. 资源越界检查 (Capacity Constraints - Reusable)
    % 逻辑：智能体在任何一个单独任务中的投入，都不能超过其物理上限。
    %      (不再累加求和)
    
    fprintf('[Step 1] 检查单任务资源是否超支 (Resource Reusability)...\n');
    base_SC = Value_data(1).SC; % 以 1号智能体的视图为基准
    
    for i = 1:N
        % 获取智能体 i 的最大能力上限
        if isfield(agents(i), 'resources')
            max_cap = agents(i).resources(:)';
            if length(max_cap) < K
                max_cap = [max_cap, zeros(1, K - length(max_cap))];
            else
                max_cap = max_cap(1:K);
            end
        else
            max_cap = zeros(1, K);
        end
        
        % 遍历所有任务，逐个检查
        for j = 1:M
            if ~isempty(base_SC{j}) && i <= size(base_SC{j}, 1)
                % 获取在该任务中的投入
                current_invested = base_SC{j}(i, 1:K);
                
                % 检查是否超标
                diff_vec = current_invested - max_cap;
                
                % 如果任意一维资源投入 > 上限 + 容差
                if any(diff_vec > tol)
                    msg = sprintf('❌ 资源越界 (Agent %d, Task %d): 投入 %s > 上限 %s', ...
                        i, j, mat2str(current_invested, 2), mat2str(max_cap, 2));
                    error_log{end+1} = msg;
                    fprintf('%s\n', msg);
                    is_valid = false;
                end
            end
        end
    end

    %% 2. 结构与资源的双向映射 (Bi-directional Mapping)
    % 检查 coalitionstru 里的成员标记与 SC 里的资源分配是否对应
    
    fprintf('[Step 2] 检查 coalitionstru 与 SC 的双向对应关系...\n');
    base_stru = Value_data(1).coalitionstru;
    
    for j = 1:M
        if ~isempty(base_SC{j})
            % A. 检查 SC -> Coalitionstru
            % 找出 SC 矩阵中所有资源非零的行 (即智能体 ID)
            active_agents_in_SC = find(any(base_SC{j} > tol, 2));
            
            % 找出 coalitionstru 第 j 行中值为1的列索引（即参与的智能体ID）
            % coalitionstru(j, i) = 1 表示智能体i参与任务j
            members_in_stru = find(base_stru(j, :) > 0);

            for idx = 1:length(active_agents_in_SC)
                aid = active_agents_in_SC(idx);
                if ~ismember(aid, members_in_stru)
                    msg = sprintf('❌ 幽灵贡献: Agent %d 在 Task %d 的 SC 中投入了资源，但不在 coalitionstru 成员名单中', aid, j);
                    error_log{end+1} = msg;
                    fprintf('%s\n', msg);
                    is_valid = false;
                end
            end
        end
    end

    %% 3. 自洽性检查 (Self-Consistency)
    % 检查 Value_data(i).resources_matrix(j,:) == Value_data(i).SC{j}(i,:)
    % 即使是资源复用，你自己记录的“我参与了哪些任务”也必须和全局SC一致
    
    fprintf('[Step 3] 检查个体矩阵与全局 SC 的自洽性...\n');
    for i = 1:N
        my_R = Value_data(i).resources_matrix;
        my_SC = Value_data(i).SC; 
        
        for j = 1:M
            res_personal = my_R(j, :);
            
            if isempty(my_SC{j})
                res_global = zeros(1, K);
            else
                if i <= size(my_SC{j}, 1)
                    res_global = my_SC{j}(i, :);
                else
                    res_global = zeros(1, K);
                end
            end
            
            % 维度截断比较
            len = min(length(res_personal), length(res_global));
            if norm(res_personal(1:len) - res_global(1:len)) > tol
                msg = sprintf('❌ 视图分裂 (Agent %d, Task %d): 个体记录 %s != 全局SC记录 %s', ...
                    i, j, mat2str(res_personal(1:len), 2), mat2str(res_global(1:len), 2));
                error_log{end+1} = msg;
                fprintf('%s\n', msg);
                is_valid = false;
            end
        end
    end

    %% 总结
    if is_valid
        fprintf('✅ [OCF Check] 检查通过！资源分配逻辑正确。\n');
    else
        fprintf('🚫 [OCF Check] 检查失败！发现 %d 处错误。\n', length(error_log));
    end
    fprintf('==============================================\n');
end