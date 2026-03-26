function algs = get_all_algorithms()
% get_all_algorithms  统一算法注册表
%
% 返回包含所有算法定义的 cell array，每项包含：
%   .id     算法 ID（整数）
%   .name   算法名称（用作结构体字段名、打印等）
%   .func   主函数句柄
%   .folder 相对于项目根目录的文件夹路径（Compare_Algorithms 使用）
%   .color  绘图颜色 RGB（Compare_Algorithms 使用）
%
% 用法示例：
%   all_algorithms = get_all_algorithms();
%   % 批量脚本：按 ID 过滤
%   enabled = all_algorithms(cellfun(@(a) ismember(a.id, ids), all_algorithms));
%   % Compare_Algorithms：额外使用 folder / color 字段

algs = {
    struct('id', 2, 'name', 'Huo2025',    'func', @Huo2025_main,          'folder', 'comalg/alg2_Huo2025',    'color', [0.8, 0.2, 0.2]);
    struct('id', 3, 'name', 'Qi2023',     'func', @Qi2023_main,           'folder', 'comalg/alg3_Qi2023',     'color', [0.2, 0.8, 0.2]);
    struct('id', 4, 'name', 'Shi2024',    'func', @Shi2024_main,          'folder', 'comalg/alg4_Shi2024',    'color', [0.8, 0.4, 0.2]);
    struct('id', 7, 'name', 'OCF_SAtabu', 'func', @OCF_SAtabu_global_main,'folder', 'comalg/alg7_OCF_SAtabu', 'color', [0.2, 0.8, 0.6]);
};
