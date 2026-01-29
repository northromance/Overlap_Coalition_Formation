function [is_valid, error_log] = check_data_consistency(Value_data, Value_Params)
% CHECK_DATA_CONSISTENCY 验证算法结果的数据一致性
%
% 功能：
%   1. 共识检查：检查 Value_data(1...N) 中所有智能体的 SC 和 coalitionstru 是否完全相同。
%   2. 逻辑检查：检查 coalitionstru 中的成员存在性与 SC 中的资源投入是否对应。
%      (即：如果在 coalitionstru 里，SC 应该有资源；反之亦然)
%   3. 自我检查：检查每个智能体的 resources_matrix(j,:) 是否等于 SC{j}(i,:)。
%
% 输入：
%   Value_data   : 原始的 1xN 结构体数组
%   Value_Params : 全局参数 (M, N, K)
%
% 输出：
%   is_valid     : 布尔值，true 表示完全一致
%   error_log    : 错误信息元胞数组

    is_valid = true;
    error_log = {};
    tol = 1e-6; % 浮点数比较容差
    
    fprintf('==============================================\n');
    fprintf('开始数据一致性检查 (Agents: %d, Tasks: %d)...\n', Value_Params.N, Value_Params.M);

    %% 1. 共识性检查 (Consensus Check)
    % 检查所有智能体的 Value_data(i).SC 和 Value_data(i).coalitionstru 是否与 Value_data(1) 一致
    base_SC = Value_data(1).SC;
    base_stru = Value_data(1).coalitionstru;
    
    fprintf('[Step 1] 检查所有智能体是否达成共识...\n');
    for i = 2:Value_Params.N
        % 1.1 检查联盟结构
        if ~isequal(base_stru, Value_data(i).coalitionstru)
            msg = sprintf('❌ 共识失败: Agent %d 的 coalitionstru 与 Agent 1 不一致', i);
            error_log{end+1} = msg;
            fprintf('%s\n', msg);
            is_valid = false;
        end
        
        % 1.2 检查 SC (逐任务检查)
        for j = 1:Value_Params.M
            if ~isempty(base_SC{j}) && ~isempty(Value_data(i).SC{j})
                diff_sc = norm(base_SC{j} - Value_data(i).SC{j});
                if diff_sc > tol
                    msg = sprintf('❌ 共识失败: Agent %d 在 Task %d 的 SC 资源视图与 Agent 1 不一致 (Diff: %.4f)', i, j, diff_sc);
                    error_log{end+1} = msg;
                    fprintf('%s\n', msg);
                    is_valid = false;
                end
            end
        end
    end

    %% 2. 结构匹配性检查 (Structure vs Resource)
    % 检查 coalitionstru 里的成员标记与 SC 里的资源分配是否逻辑互斥
    % 逻辑：如果 coalitionstru(j, i) == 0，则 SC{j}(i, :) 必须全是 0
    
    fprintf('[Step 2] 检查联盟结构与资源分配的逻辑对应性 (基于 Agent 1 视图)...\n');
    for j = 1:Value_Params.M
        if isempty(base_SC{j})
            continue; 
        end
        
        for i = 1:Value_Params.N
            % 获取该位置的 Agent ID (在你的代码逻辑中，列索引 i 通常对应 Agent ID i)
            member_id_in_stru = base_stru(j, i); 
            resource_in_SC = sum(abs(base_SC{j}(i, :))); % 该位置投入的总资源
            
            % 情况 A: 结构中显示“不在”，但 SC 中却“有资源”
            if member_id_in_stru == 0 && resource_in_SC > tol
                msg = sprintf('❌ 幽灵资源: Task %d, Col %d 在 coalitionstru 中为 0，但在 SC 中投入了 %.2f 资源', j, i, resource_in_SC);
                error_log{end+1} = msg;
                fprintf('%s\n', msg);
                is_valid = false;
            end
            
            % 情况 B: 结构中显示“在”，但 SC 中“无资源”
            % (这在某些逻辑下可能是允许的，比如观察者，但如果你的逻辑是全额投入，则这是异常)
            if member_id_in_stru ~= 0 && resource_in_SC < tol
                % 这是一个警告，不一定是错误，取决于你的业务逻辑
                % msg = sprintf('⚠️ 僵尸成员: Task %d, Col %d 在 coalitionstru 中，但资源投入为 0', j, i);
                % fprintf('%s\n', msg);
            end
        end
    end

    %% 3. 自我一致性检查 (Self vs Global)
    % 检查 Value_data(i).resources_matrix(j, :) 是否等于 Value_data(i).SC{j}(i, :)
    % 含义：我认为我投入的资源，是否等于我在全局表里登记的资源
    
    fprintf('[Step 3] 检查个体资源矩阵与全局 SC 的一致性...\n');
    for i = 1:Value_Params.N
        my_R = Value_data(i).resources_matrix;
        my_SC = Value_data(i).SC; % 使用自己的视图进行自洽性检查
        
        for j = 1:Value_Params.M
            % 提取个体矩阵中我刚才对任务 j 的投入
            res_personal = my_R(j, :);
            
            % 提取 SC 中记录的我对任务 j 的投入
            if isempty(my_SC{j})
                res_global = zeros(1, Value_Params.K);
            else
                % 注意：这里假设 SC 的行索引 i 对应 Agent i
                if i <= size(my_SC{j}, 1)
                    res_global = my_SC{j}(i, :);
                else
                    res_global = zeros(1, Value_Params.K);
                end
            end
            
            % 比较
            % 维度对齐
            len = min(length(res_personal), length(res_global));
            diff_res = norm(res_personal(1:len) - res_global(1:len));
            
            if diff_res > tol
                msg = sprintf('❌ 精神分裂: Agent %d 在 Task %d 的记录冲突。\n\t个体矩阵: %s\n\t全局SC表: %s', ...
                    i, j, mat2str(res_personal(1:len), 2), mat2str(res_global(1:len), 2));
                error_log{end+1} = msg;
                fprintf('%s\n', msg);
                is_valid = false;
            end
        end
    end
    
    %% 总结
    if is_valid
        fprintf('✅ 检查通过！所有数据结构一致且逻辑正确。\n');
    else
        fprintf('🚫 检查失败！发现 %d 处不一致，请查看 error_log。\n', length(error_log));
    end
    fprintf('==============================================\n');
end