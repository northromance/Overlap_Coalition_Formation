% test_utf8_output.m
% 测试 MATLAB 终端中文输出是否正常（无乱码）
% 预期：所有 fprintf 输出的中文字符应可读，不出现 ���� 乱码

feature('DefaultCharacterSet', 'UTF-8');

fprintf('=== UTF-8 输出测试 ===\n');
fprintf('  [-] [离开] Agent #5  离开 任务 M=7  释放 资源 k=3  | 数量: 4.00\n');
fprintf('  [x] [拒绝] Agent #5  尝试加入 任务 M=9  投入 资源 k=3  失败 | 原因: energy_insufficient\n');
fprintf('  [+] [加入] Agent #6  加入 任务 M=5  投入 资源 k=3  | 数量: 2.00\n');
fprintf('=== 测试完成，若以上中文可读则修复成功 ===\n');
