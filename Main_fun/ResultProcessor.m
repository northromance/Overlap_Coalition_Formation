classdef ResultProcessor
    % ResultProcessor 用于处理、分析和对比不同算法的运行结果
    % 包含提取关键性能指标、生成统计报表等静态方法。
    
    methods(Static)
        function comparison_stats = compare_results(results, Value_Params)
            % COMPARE_RESULTS 极简版：提取关键性能指标
            %
            % 核心逻辑：
            %   1. 直接读取 history_data 最后一轮的数据。
            %   2. 计算平均完成率 = 所有任务完成度之和 / 任务总数。
            %   3. 计算联盟数 = 有智能体参与的任务数量。
            %
            % 输入：
            %   results      - 算法结果结构体 (包含多个算法的 Value_data, history_data)
            %   Value_Params - 全局参数 (必须包含 M: 任务数量)
            %
            % 输出：
            %   comparison_stats - 精简后的统计结果结构体
            
            %% 1. 初始化
            alg_names = fieldnames(results);
            num_algorithms = length(alg_names);
            comparison_stats = struct();
            
            %% 2. 遍历算法提取指标
            for i = 1:num_algorithms
                alg_name = alg_names{i};
                alg_result = results.(alg_name);
                num_active_coalitions = 0;
                
                % 初始化当前算法统计
                stats = struct();
                stats.name = alg_result.name;
                
                % 兼容性处理：检查是否存在 computation_time 字段
                if isfield(alg_result, 'computation_time')
                    stats.computation_time = alg_result.computation_time;
                else
                    stats.computation_time = NaN;
                end
                
                % 错误处理：如果算法运行失败，记录错误并跳过
                if isfield(alg_result, 'error')
                    stats.has_error = true;
                    stats.error_message = alg_result.error.message;
                    
                    % 设置默认空值防止后续报错
                    stats.total_utility = NaN;
                    stats.total_cost = NaN;
                    stats.total_completion_score = NaN;
                    stats.avg_task_completion = NaN;
                    stats.num_coalitions = NaN;
                    
                    comparison_stats.(alg_name) = stats;
                    continue;
                end
                stats.has_error = false;
                
                % --- 定位数据源：最后一轮历史记录 ---
                % 确保 history_data 和 rounds 存在
                if isfield(alg_result, 'history_data') && isfield(alg_result.history_data, 'rounds') && ~isempty(alg_result.history_data.rounds)
                    last_round = alg_result.history_data.rounds(end);
                else
                    warning('ResultProcessor:NoHistory', '算法 %s 缺少历史记录数据', alg_name);
                    continue;
                end
                
                %% 3. 基础标量指标 (Utility, Cost, Value)
                % [总效用] 全局净收益
                stats.total_utility = last_round.coalition_utility;
                
                % [总成本] 全局消耗
                stats.total_cost = last_round.total_global_cost;
                
                % [总完成价值] Sum(Value * Degree)
                stats.total_completion_score = last_round.total_completed_value;
                
                %% 4. 任务完成率 (Average Completion Rate)
                % 逻辑：计算所有任务完成度的平均值 (Sum / M)
                % task_completion_degrees 是 Mx1 向量，包含0值
                degrees = last_round.task_completion_degrees;
                
                stats.task_completion_degrees = degrees; % 保留原始向量
                stats.avg_task_completion = mean(degrees); % 平均值 (0~1)
                
                %% 5. 联盟数量 (Number of Coalitions Formed)
                % 逻辑：统计有多少个任务被执行了 (即至少有一个智能体参与)
                % coalitionstru 是 MxN 矩阵
                % 遍历前 M 个任务 (防止 SC 长度超过 M)
                SC_global = last_round.SC;
                check_count = min(Value_Params.M, length(SC_global));
                
                for j = 1:check_count
                    SC_task = SC_global{j};
                    
                    % 判断条件：
                    % 1. 矩阵不为空
                    % 2. 矩阵元素之和 > 1e-6 (表示确实有资源投入，忽略浮点误差)
                    if ~isempty(SC_task) && sum(SC_task(:)) > 1e-6
                        num_active_coalitions = num_active_coalitions + 1;
                    end
                end
                
                stats.num_coalitions = num_active_coalitions;
                
                %% 6. 存入总表
                comparison_stats.(alg_name) = stats;
            end
        end


        function history_data = record_history_data(history_data, round_idx, Value_data, Value_Params, ...
                final_SC, final_coalitionstru, ...
                coalition_utility, total_global_cost, ...
                total_completed_value, task_completion_degrees, ...
                summatrix)
            % RECORD_HISTORY_DATA 记录每一轮算法的详细状态
            %
            % 输入:
            %   history_data            - 历史结构体
            %   round_idx               - 当前轮数 (对应主程序的 counter)
            %   Value_data              - 智能体状态 (用于记录信念)
            %   Value_Params            - 全局参数
            %   final_SC                - 最终资源分配 (Cell)
            %   final_coalitionstru     - 最终成员矩阵
            %   coalition_utility       - 全局净效用 (标量)
            %   total_global_cost       - 全局总成本 (标量，所有智能体消耗之和)
            %   total_completed_value   - 任务总完成价值 (标量)
            %   task_completion_degrees - 任务完成度 (Mx1)
            %   summatrix               - 全局观测矩阵
            %
            % 输出:
            %   history_data            - 更新后的历史结构体
            
            %% 1. 基础信息
            history_data.rounds(round_idx).round_num = round_idx;
            
            %% 2. 结构快照
            history_data.rounds(round_idx).coalitionstru = final_coalitionstru;
            history_data.rounds(round_idx).SC = final_SC;
            
            %% 3. 性能指标 (扁平化存储)
            % 记录全局净效用 (标量)
            history_data.rounds(round_idx).coalition_utility = coalition_utility;
            
            % 记录全局总成本 (标量)
            history_data.rounds(round_idx).total_global_cost = total_global_cost;
            
            % 记录完成价值与完成度
            history_data.rounds(round_idx).total_completed_value = total_completed_value;
            history_data.rounds(round_idx).task_completion_degrees = task_completion_degrees;
            
            %% 4. 信念与观测
            history_data.rounds(round_idx).summatrix = summatrix;
            
            % 记录信念快照 (N x M x TaskTypes)
            % 提取前 M 个任务的信念
            belief_snapshot = zeros(Value_Params.N, Value_Params.M, Value_Params.task_type);
            for i = 1:Value_Params.N
                belief_snapshot(i, :, :) = Value_data(i).initbelief(1:Value_Params.M, :);
            end
            history_data.rounds(round_idx).beliefs = belief_snapshot;
            
        end
    end
end