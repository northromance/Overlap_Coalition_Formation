% quick_compare_configs.m - 快速对比配置示例
%
% 使用方法：
%   1. 在 Compare_Algorithms.m 中复制下面的配置到 algorithms_to_run_ids
%   2. 或者直接在命令行中设置：
%      algorithms_to_run_ids = [1, 7, 8];
%      Compare_Algorithms;

%% 配置1：原始 SA vs 所有改进版本
% 用途：全面评估所有改进算法的性能
config_all_improvements = [1, 7, 8, 9, 10, 11, 12];

%% 配置2：原始 SA vs 温度相关改进
% 用途：对比不同温度策略的效果
config_temperature_variants = [1, 8, 9, 11];  % SA_Value, AdaptiveAlpha, ImprovedTemp, HybridGreedy

%% 配置3：原始 SA vs 搜索策略改进
% 用途：对比不同搜索策略的效果
config_search_variants = [1, 7, 10, 12];  % SA_Value, TabuEnhanced, MultiStart, EnhancedNeighbor

%% 配置4：SA vs 对比算法 vs 最佳改进
% 用途：与其他算法对比时，展示 SA 的最佳改进版本
config_best_comparison = [1, 3, 4, 7];  % SA_Value, Huo2025, Qi2023, TabuEnhanced

%% 配置5：只测试改进算法（不包括原始 SA）
% 用途：快速筛选最有潜力的改进方向
config_improvements_only = [7, 8, 9, 10, 11, 12];

%% 配置6：原始 SA vs 单个改进（用于详细分析）
% 用途：深入分析某个改进算法的行为
config_single_improvement_tabu = [1, 7];        % vs TabuEnhanced
config_single_improvement_alpha = [1, 8];       % vs AdaptiveAlpha
config_single_improvement_temp = [1, 9];        % vs ImprovedTemp
config_single_improvement_multistart = [1, 10]; % vs MultiStart
config_single_improvement_greedy = [1, 11];     % vs HybridGreedy
config_single_improvement_neighbor = [1, 12];   % vs EnhancedNeighbor

%% 配置7：完整对比（所有算法）
% 用途：生成完整的性能对比报告
config_full_comparison = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12];

%% 使用示例
% 在 MATLAB 命令行中：
%
% % 示例1：运行配置1（所有改进）
% algorithms_to_run_ids = config_all_improvements;
% Compare_Algorithms;
%
% % 示例2：运行配置4（与对比算法比较）
% algorithms_to_run_ids = config_best_comparison;
% Compare_Algorithms;
%
% % 示例3：自定义配置
% algorithms_to_run_ids = [1, 7, 9, 4];  % SA + TabuEnhanced + ImprovedTemp + Qi2023
% Compare_Algorithms;

%% 算法 ID 参考
% 1  = SA_Value (原始算法)
% 2  = Greedy baseline
% 3  = Huo2025
% 4  = Qi2023
% 5  = Shi2024
% 6  = PSO
% 7  = SA_TabuEnhanced (禁忌搜索增强)
% 8  = SA_AdaptiveAlpha (自适应降温系数)
% 9  = SA_ImprovedTemp (改进温度策略)
% 10 = SA_MultiStart (多起点重启)
% 11 = SA_HybridGreedy (混合贪心策略)
% 12 = SA_EnhancedNeighbor (增强邻域搜索)
