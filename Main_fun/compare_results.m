function comparison_stats = compare_results(results)
% COMPARE_RESULTS 极简版：提取关键性能指标
%
% 核心逻辑：
%   1. 直接读取 history_data 最后一轮的数据。
%   2. 计算平均完成率 = 所有任务完成度之和 / 任务总数。
%   3. 计算联盟数 = 有智能体参与的任务数量。
%
% 输入：
%   results      - 算法结果结构体
%   agents       - 智能体数组
%   tasks        - 任务数组
%   Value_Params - 全局参数 (含 M)
%
% 输出：
%   comparison_stats - 精简后的统计结果

%% 1. 初始化
alg_names = fieldnames(results);
num_algorithms = length(alg_names);
comparison_stats = struct();

%% 2. 遍历算法提取指标
for i = 1:num_algorithms
    alg_name = alg_names{i};
    alg_result = results.(alg_name);

    % 初始化当前算法统计
    stats = struct();
    stats.name = alg_result.name;
    stats.computation_time = alg_result.computation_time;

    % 错误跳过
    if isfield(alg_result, 'error')
        stats.has_error = true;
        stats.error_message = alg_result.error.message;
        comparison_stats.(alg_name) = stats;
        continue;
    end
    stats.has_error = false;

    % --- 定位数据源：最后一轮历史记录 ---
    last_round = alg_result.history_data.rounds(end);

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
    check_count = min(M, length(SC_global));

    for j = 1:check_count
        SC_task = SC_global{j};

        % 判断条件：
        % 1. 矩阵不为空
        % 2. 矩阵元素之和 > 0 (表示确实有资源投入)
        if ~isempty(SC_task) && sum(SC_task(:)) > 1e-6
            num_active_coalitions = num_active_coalitions + 1;
        end
    end

    stats.num_coalitions = num_active_coalitions;
    % 检查每一行是否存在非零元素 (any return logic vector)
    % sum 计算为 true 的行数
    stats.num_coalitions = sum(any(coal_matrix ~= 0, 2));

    %% 6. 存入总表
    comparison_stats.(alg_name) = stats;
end
end