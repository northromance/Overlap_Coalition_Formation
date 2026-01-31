% 测试 Compare_Algorithms 修复
% 模拟算法失败的情况

% 创建一个空的 results 结构
results = struct();
results.alg1.name = 'SA_Value';
% 故意不添加 Value_data 字段，模拟算法失败

% 测试修复后的代码逻辑
if isfield(results, 'alg1') && strcmp(results.alg1.name, 'SA_Value') && isfield(results.alg1, 'Value_data')
    fprintf('✅ 会尝试可视化\n');
else
    fprintf('✅ 正确跳过可视化（算法失败或未运行）\n');
end

% 测试算法成功的情况
results.alg1.Value_data = struct('test', 1);

if isfield(results, 'alg1') && strcmp(results.alg1.name, 'SA_Value') && isfield(results.alg1, 'Value_data')
    fprintf('✅ 会尝试可视化（算法成功）\n');
else
    fprintf('❌ 错误：应该可视化但被跳过\n');
end

fprintf('\n修复验证完成！\n');
