% 检查结果文件结构
clear; clc;

% 加载最近的比较结果
result_files = dir('results/comparison_N6_M10_SA+Qi+SA*.mat');
if isempty(result_files)
    error('未找到比较结果文件');
end

% 按时间排序，选择最新的
[~, idx] = max([result_files.datenum]);
latest_file = fullfile(result_files(idx).folder, result_files(idx).name);

fprintf('正在检查文件结构: %s\n\n', result_files(idx).name);

% 加载数据
data = load(latest_file);

% 显示所有字段
fprintf('文件包含的字段:\n');
fprintf('================\n');
field_names = fieldnames(data);
for i = 1:length(field_names)
    field_name = field_names{i};
    field_value = data.(field_name);
    field_class = class(field_value);
    field_size = size(field_value);

    fprintf('%s: %s, size: [', field_name, field_class);
    fprintf('%d ', field_size);
    fprintf(']\n');

    % 如果是struct，显示其字段
    if isstruct(field_value) && numel(field_value) == 1
        sub_fields = fieldnames(field_value);
        fprintf('  子字段: ');
        for j = 1:min(5, length(sub_fields))
            fprintf('%s, ', sub_fields{j});
        end
        if length(sub_fields) > 5
            fprintf('...');
        end
        fprintf('\n');
    end

    % 如果是cell array，显示内容
    if iscell(field_value) && numel(field_value) <= 5
        fprintf('  内容: ');
        for j = 1:numel(field_value)
            if ischar(field_value{j})
                fprintf('%s, ', field_value{j});
            elseif isstruct(field_value{j})
                fprintf('[struct], ');
            end
        end
        fprintf('\n');
    end

    fprintf('\n');
end
