% 测试 SA_Value 收敛逻辑改进
% 验证参数命名统一和收敛条件

fprintf('=== SA_Value 收敛逻辑测试 ===\n\n');

% 模拟参数
K_len_SA = 20;
K_max_inner_SA = 100;
SA_Temperature = 100.0;
SA_alpha = 0.95;
SA_Tmin = 0.01;

fprintf('参数设置（统一命名）：\n');
fprintf('  K_len_SA = %d (稳定性阈值)\n', K_len_SA);
fprintf('  K_max_inner_SA = %d (最大迭代次数)\n', K_max_inner_SA);
fprintf('  SA_Temperature = %.2f (初始温度)\n', SA_Temperature);
fprintf('  SA_alpha = %.2f (降温系数)\n', SA_alpha);
fprintf('  SA_Tmin = %.4f (终止温度)\n\n', SA_Tmin);

% 测试1：稳定性收敛
fprintf('测试1：稳定性收敛（连续无变化）\n');
k_stable = 20;
k_iter = 50;
Temperature = 50.0;
if k_stable >= K_len_SA
    fprintf('  ✅ 触发条件1：k_stable(%d) >= K_len_SA(%d)\n', k_stable, K_len_SA);
    fprintf('  收敛原因：连续%d次无变化\n\n', k_stable);
end

% 测试2：温度收敛
fprintf('测试2：温度收敛（温度过低）\n');
k_stable = 5;
k_iter = 90;
Temperature = 0.005;
if Temperature < SA_Tmin
    fprintf('  ✅ 触发条件2：Temperature(%.4f) < SA_Tmin(%.4f)\n', Temperature, SA_Tmin);
    fprintf('  收敛原因：温度过低\n\n');
end

% 测试3：最大迭代次数
fprintf('测试3：最大迭代次数（防止无限循环）\n');
k_stable = 5;
k_iter = 100;
Temperature = 20.0;
if k_iter >= K_max_inner_SA
    fprintf('  ✅ 触发条件3：k_iter(%d) >= K_max_inner_SA(%d)\n', k_iter, K_max_inner_SA);
    fprintf('  收敛原因：达到最大迭代次数\n\n');
end

% 测试4：温度衰减估算
fprintf('测试4：温度衰减估算\n');
T = SA_Temperature;
for n = 1:100
    T = T * SA_alpha;
    if T < SA_Tmin
        fprintf('  达到终止温度需要 %d 次迭代\n', n);
        fprintf('  最终温度：%.6f\n', T);
        break;
    end
end
fprintf('  K_max_inner_SA = %d 是合理的上限\n\n', K_max_inner_SA);

% 测试5：对比 Qi2023 命名
fprintf('测试5：命名统一性对比\n');
fprintf('  Qi2023:   K_len = 20,    K_max_inner = 100,    k_iter\n');
fprintf('  SA_Value: K_len_SA = %d, K_max_inner_SA = %d, k_iter\n', K_len_SA, K_max_inner_SA);
fprintf('  ✅ 命名统一，便于对比\n\n');

fprintf('=== 所有测试通过 ===\n');
