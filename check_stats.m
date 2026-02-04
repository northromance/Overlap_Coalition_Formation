% 详细检查comparison_stats结构
clear; clc;

result_files = dir('results/comparison_N6_M10_SA+Qi+SA*.mat');
[~, idx] = max([result_files.datenum]);
latest_file = fullfile(result_files(idx).folder, result_files(idx).name);

data = load(latest_file);

fprintf('comparison_stats的字段:\n');
stats_fields = fieldnames(data.comparison_stats);
for i = 1:length(stats_fields)
    fprintf('\n%s:\n', stats_fields{i});
    alg_stats = data.comparison_stats.(stats_fields{i});
    if isstruct(alg_stats)
        sub_fields = fieldnames(alg_stats);
        for j = 1:length(sub_fields)
            field_value = alg_stats.(sub_fields{j});
            if isnumeric(field_value) && isscalar(field_value)
                fprintf('  %s: %.4f\n', sub_fields{j}, field_value);
            elseif isnumeric(field_value) && length(field_value) <= 10
                fprintf('  %s: [', sub_fields{j});
                fprintf('%.2f ', field_value);
                fprintf(']\n');
            else
                fprintf('  %s: %s (size: %s)\n', sub_fields{j}, class(field_value), mat2str(size(field_value)));
            end
        end
    end
end
