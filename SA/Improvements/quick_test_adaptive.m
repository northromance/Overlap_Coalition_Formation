% quick_test_adaptive.m - 快速测试 SA_AdaptiveAlpha
%
% 使用 Compare_Algorithms.m 的完整初始化来测试自适应算法

clear; clc;

fprintf('========================================\n');
fprintf('  快速测试 SA_AdaptiveAlpha\n');
fprintf('========================================\n\n');

% 设置要对比的算法
algorithms_to_run_ids = [1, 8];  % SA_Value vs SA_AdaptiveAlpha

% 运行对比
fprintf('运行算法对比...\n');
fprintf('算法: [1] SA_Value, [8] SA_AdaptiveAlpha\n\n');

Compare_Algorithms;

fprintf('\n========================================\n');
fprintf('  测试完成！\n');
fprintf('========================================\n');
fprintf('查看 results/ 文件夹获取详细结果\n');
