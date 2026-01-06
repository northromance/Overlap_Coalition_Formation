function demand = calculate_demand_quantile(belief, task_type_demands, confidence)
% calculate_demand_quantile - 使用分位数法计算资源需求
%
% 核心思想：
%   在不确定性下，不使用期望值（可能不足），而是基于置信水平
%   找到"有X%把握够用"的需求量
%
% 输入参数：
%   belief            - 1×T 任务类型信念分布向量
%                       例如: [0.5, 0.3, 0.2] 表示50%认为是类型1，30%类型2，20%类型3
%   task_type_demands - T×K 任务类型资源需求矩阵
%                       行: 任务类型 (1~T)
%                       列: 资源类型 (1~K)
%                       例如: task_type_demands(2, 3) = 类型2对资源3的需求
%   confidence        - 标量，置信水平 (0~1)
%                       例如: 0.9 表示要求90%把握够用（能接受10%失败风险）
%
% 输出参数：
%   demand            - 1×K 各资源类型的需求量向量
%
% 算法原理：
%   对每种资源独立应用分位数法：
%   1. 提取该资源在所有类型下的需求值
%   2. 按需求从小到大排序，信念分布跟随
%   3. 累积信念概率，直到达到置信水平
%   4. 此时对应的需求值即为结果
%
% 示例：
%   belief = [0.5, 0.3, 0.2];
%   task_type_demands = [6, 7, 6;
%                        7, 8, 7;
%                        8, 6, 8];
%   confidence = 0.9;
%   
%   对资源1: 需求[6, 7, 8], 排序后累积[0.5, 0.8, 1.0]
%            第一个 >= 0.9 的是1.0, 对应需求8
%   → demand(1) = 8
%
% 作者: [Your Name]
% 日期: 2026-01-06

    % 输入验证
    if nargin < 3
        error('calculate_demand_quantile:NotEnoughInputs', ...
              '需要3个输入参数: belief, task_type_demands, confidence');
    end
    
    if confidence < 0 || confidence > 1
        error('calculate_demand_quantile:InvalidConfidence', ...
              'confidence必须在0到1之间，当前值: %.2f', confidence);
    end
    
    % 获取维度
    [num_types, K] = size(task_type_demands);
    
    % 验证信念维度
    if length(belief) ~= num_types
        error('calculate_demand_quantile:DimensionMismatch', ...
              'belief长度(%d)必须等于task_type_demands行数(%d)', ...
              length(belief), num_types);
    end
    
    % 确保belief是行向量
    belief = belief(:).';
    
    % 初始化输出
    demand = zeros(1, K);
    
    % ========== 策略：高确定性时直接用最大信念类型 ==========
    % 原理：当信念高度确定时（如max(belief)>0.85），说明观测已充分
    % 此时直接使用最可能的类型需求，比分位数法更准确
    % 分位数法在高确定性下会因排序打乱类型对应关系而失效
    % ========================================================
    max_belief = max(belief);
    
    if max_belief >= confidence
        % 高确定性：直接使用信念最大的类型
        [~, most_likely_type] = max(belief);
        demand = task_type_demands(most_likely_type, :);
        demand = ceil(demand);
        return;
    end
    
    % 低确定性：使用分位数法
    % 对每种资源独立计算分位数需求
    for r = 1:K
        % 提取该资源在所有类型下的需求
        demands_r = task_type_demands(:, r);  % T×1 向量
        
        % 按需求从小到大排序
        [sorted_demands, idx] = sort(demands_r);
        
        % 信念分布跟随排序
        sorted_belief = belief(idx);
        
        % 计算累积概率
        cumulative_prob = cumsum(sorted_belief);
        
        % 找到第一个累积概率 >= confidence 的位置
        threshold_idx = find(cumulative_prob >= confidence, 1);
        
        % 如果没找到（理论上不会发生，因为cumsum最终=1.0）
        if isempty(threshold_idx)
            threshold_idx = num_types;  % 使用最大需求
        end
        
        % 该资源的分位数需求
        demand(r) = sorted_demands(threshold_idx);
    end
    
    % 向上取整确保整数资源
    demand = ceil(demand);
end
