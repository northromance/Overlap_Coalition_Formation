classdef ResultProcessor
    % ResultProcessor 用于记录、整理和对比不同算法的运行结果
    % 负责提取关键性能指标、生成统计信息，并保存历史状态变化
    
    methods(Static)
        function comparison_stats = compare_results(results, Value_Params)
            % COMPARE_RESULTS 比较多种算法的最终结果指标
            %
            % 功能说明：
            %   1. 直接从 history_data 中提取最终轮次的数据；
            %   2. 计算平均任务完成度 = 所有任务完成度之和 / 任务总数；
            %   3. 统计形成的联盟数量 = 实际发生资源分配的任务数。
            %
            % 输入：
            %   results      - 算法运行结果结构体（每个字段包含 Value_data, history_data）
            %   Value_Params - 全局参数（其中 M 表示任务数量）
            %
            % 输出：
            %   comparison_stats - 各算法的统计结果结构体
            
            %% 1. 初始化
            alg_names = fieldnames(results);
            num_algorithms = length(alg_names);
            comparison_stats = struct();
            
            %% 2. 遍历各算法并提取指标
            for i = 1:num_algorithms
                alg_name = alg_names{i};
                alg_result = results.(alg_name);
                num_active_coalitions = 0;
                
                % 初始化当前算法统计结构
                stats = struct();
                stats.name = alg_result.name;
                
                % 记录算法运行时间（如果结果中有 computation_time 字段）
                if isfield(alg_result, 'computation_time')
                    stats.computation_time = alg_result.computation_time;
                else
                    stats.computation_time = NaN;
                end
                
                % 如果算法执行出错，则跳过正常统计并记录错误信息
                if isfield(alg_result, 'error')
                    stats.has_error = true;
                    stats.error_message = alg_result.error.message;
                    
                    % 设置默认空值，防止后续访问报错
                    stats.total_utility = NaN;
                    stats.total_cost = NaN;
                    stats.total_completion_score = NaN;
                    stats.avg_task_completion = NaN;
                    stats.num_coalitions = NaN;
                    
                    comparison_stats.(alg_name) = stats;
                    continue;
                end
                stats.has_error = false;
                
                % --- 定位最终历史记录 ---
                % 确保 history_data 中存在 rounds 字段
                if isfield(alg_result, 'history_data') && isfield(alg_result.history_data, 'rounds') && ~isempty(alg_result.history_data.rounds)
                    last_round = alg_result.history_data.rounds(end);
                else
                    warning('ResultProcessor:NoHistory', '算法 %s 缺少历史记录，无法比较。', alg_name);
                    continue;
                end
                
                %% 3. 提取核心指标 (Utility, Cost, Value)
                % [总效用] 全局联盟效用
                stats.total_utility = last_round.coalition_utility;
                
                % [总成本] 全局执行成本
                stats.total_cost = last_round.total_global_cost;
                
                % [总完成价值] Sum(Value * Degree)
                stats.total_completion_score = last_round.total_completed_value;
                
                %% 4. 计算平均任务完成度 (Average Completion Rate)
                % task_completion_degrees 为 Mx1 向量，每个元素表示一个任务的完成度（0~1）
                degrees = last_round.task_completion_degrees;
                
                stats.task_completion_degrees = degrees;      % 保存原始完成度向量
                stats.avg_task_completion = mean(degrees);    % 平均完成度
                
                %% 5. 统计形成的联盟数 (Number of Coalitions Formed)
                % 统计哪些任务上实际发生了资源分配：
                % 如果某个任务的资源分配矩阵非空，且元素和大于阈值，则视为形成了联盟
                SC_global = last_round.SC;
                check_count = min(Value_Params.M, length(SC_global));
                
                for j = 1:check_count
                    SC_task = SC_global{j};
                    
                    % 判断一个任务是否被激活：
                    % 1. 不为空
                    % 2. 所有元素之和 > 1e-6（表示确实发生了资源投入）
                    if ~isempty(SC_task) && sum(SC_task(:)) > 1e-6
                        num_active_coalitions = num_active_coalitions + 1;
                    end
                end
                
                stats.num_coalitions = num_active_coalitions;
                
                %% 6. 保存结果
                comparison_stats.(alg_name) = stats;
            end
        end


        function history_data = record_history_data(history_data, round_idx, Value_data, Value_Params, ...
                final_SC, final_coalitionstru, ...
                coalition_utility, total_global_cost, ...
                total_completed_value, task_completion_degrees, ...
                summatrix)
            % RECORD_HISTORY_DATA 记录每一轮算法执行后的详细状态
            %
            % 输入：
            %   history_data            - 历史数据结构体
            %   round_idx               - 当前轮次（对应外层循环 counter）
            %   Value_data              - 所有智能体状态（用于记录 belief）
            %   Value_Params            - 全局参数
            %   final_SC                - 最终资源分配结构（Cell）
            %   final_coalitionstru     - 最终联盟成员结构
            %   coalition_utility       - 全局联盟效用（总收益）
            %   total_global_cost       - 全局总成本（所有智能体执行代价总和）
            %   total_completed_value   - 总完成价值（总收益）
            %   task_completion_degrees - 各任务完成度（Mx1）
            %   summatrix               - 全局观测统计矩阵
            %
            % 输出：
            %   history_data            - 更新后的历史数据结构体
            
            %% 1. 记录轮次信息
            history_data.rounds(round_idx).round_num = round_idx;
            
            %% 2. 记录结构信息
            history_data.rounds(round_idx).coalitionstru = final_coalitionstru;
            history_data.rounds(round_idx).SC = final_SC;
            
            %% 3. 记录性能指标
            % 记录全局联盟效用（总收益）
            history_data.rounds(round_idx).coalition_utility = coalition_utility;
            
            % 记录全局总成本
            history_data.rounds(round_idx).total_global_cost = total_global_cost;
            
            % 记录总完成价值与各任务完成度
            history_data.rounds(round_idx).total_completed_value = total_completed_value;
            history_data.rounds(round_idx).task_completion_degrees = task_completion_degrees;
            
            %% 4. 记录观测与信念
            history_data.rounds(round_idx).summatrix = summatrix;
            
            % 记录每个智能体的 belief 快照 (N x M x TaskTypes)
            % 只截取前 M 个任务的 belief
            belief_snapshot = zeros(Value_Params.N, Value_Params.M, Value_Params.task_type);
            for i = 1:Value_Params.N
                belief_snapshot(i, :, :) = Value_data(i).initbelief(1:Value_Params.M, :);
            end
            history_data.rounds(round_idx).beliefs = belief_snapshot;

        end

        function inner_loop_history = record_inner_loop_iteration(inner_loop_history, iteration, temperature, current_utility, best_utility, SC_current, Value_Params)
            % RECORD_INNER_LOOP_ITERATION 记录内循环每次迭代的详细数据
            %
            % 功能：
            %   记录 SA / Qi 等算法在内循环中的每次迭代状态，用于后续可视化分析
            %
            % 输入：
            %   inner_loop_history  - 内循环历史结构体
            %   iteration           - 当前迭代次数
            %   temperature         - 当前温度（SA）或 Gamma 系数（Qi）
            %   current_utility     - 当前解的效用
            %   best_utility        - 本轮最优效用
            %   SC_current          - 当前联盟结构（Cell 数组）
            %   Value_Params        - 全局参数
            %
            % 输出：
            %   inner_loop_history  - 更新后的内循环历史结构体
            %
            % 示例：
            %   inner_loop_history = ResultProcessor.record_inner_loop_iteration(...
            %       inner_loop_history, k_iter, Temperature, current_utility, best_utility, SC, Value_Params);

            %% 记录基础数据
            inner_loop_history.iteration(end+1) = iteration;
            inner_loop_history.temperature(end+1) = temperature;
            inner_loop_history.current_utility(end+1) = current_utility;
            inner_loop_history.best_utility(end+1) = best_utility;

            %% 计算并记录联盟数量
            num_coalitions = 0;
            for m = 1:Value_Params.M
                if any(SC_current{m}(:) > 1e-9)
                    num_coalitions = num_coalitions + 1;
                end
            end
            inner_loop_history.num_coalitions(end+1) = num_coalitions;

        end

        function inner_loop_history = init_inner_loop_history()
            % INIT_INNER_LOOP_HISTORY 初始化内循环历史记录结构体
            %
            % 功能：
            %   创建一个空的内循环历史记录结构体，用于存储迭代过程数据
            %
            % 输出：
            %   inner_loop_history - 初始化后的内循环历史结构体
            %
            % 示例：
            %   inner_loop_history = ResultProcessor.init_inner_loop_history();

            inner_loop_history = struct();
            inner_loop_history.iteration = [];
            inner_loop_history.temperature = [];
            inner_loop_history.current_utility = [];
            inner_loop_history.best_utility = [];
            inner_loop_history.num_coalitions = [];
        end
    end
end