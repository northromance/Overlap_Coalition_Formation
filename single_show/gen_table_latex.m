% gen_table_latex.m
% 从 SS_Single_Viz 最新结果生成 LaTeX 智能体-任务调度表
% 输出: single_show/agent_task_schedule_table.tex
%
% 表格 preamble 所需宏（粘贴到论文 preamble）:
%   \usepackage{booktabs,multirow,makecell,array}
%   \newlength{\SEw}\setlength{\SEw}{2.4em}
%   \newcolumntype{C}[1]{>{\centering\arraybackslash}m{#1}}
%   \newcommand{\AllocCell}[1]{{\scriptsize #1}}

clear; clc;
feature('DefaultCharacterSet', 'UTF-8');

script_dir  = fileparts(mfilename('fullpath'));
results_dir = fullfile(script_dir, 'results');

%% 1. 找最新 .mat 文件
mat_files = dir(fullfile(results_dir, 'N*_M*_K*_seed*.mat'));
if isempty(mat_files)
    error('未在 %s 找到结果文件', results_dir);
end
[~, idx] = sort([mat_files.datenum], 'descend');
mat_path  = fullfile(results_dir, mat_files(idx(1)).name);
fprintf('加载: %s\n', mat_path);

%% 2. 加载数据
s  = load(mat_path, 'viz_data');
vd = s.viz_data;

N      = vd.N;
M      = vd.M;
K      = vd.K;
agents = vd.agents;
tasks  = vd.tasks;
SC     = vd.final_SC;
timing = vd.timing;
tdeg   = vd.task_completion_degrees;
EPS    = 1e-9;

%% 3. 任务按优先级降序排列
prios = arrayfun(@(t) t.priority, tasks);
[~, task_order] = sort(prios, 'descend');

%% 4. 辅助函数
fmt_vec  = @(v) ['[' strjoin(arrayfun(@(x) sprintf('%d', round(x)), ...
                     v(:)', 'UniformOutput', false), ',') ']'];
fmt_time = @(t) sprintf('%.1f', t);

%% 5. 建立最终轮 agent×task 时间查找表
t_start = nan(N, M);
t_end   = nan(N, M);
for i = 1:N
    seq = timing(i).task_sequence;
    if isempty(seq), continue; end
    st = timing(i).start_times;
    ct = timing(i).completion_times;
    for pos = 1:length(seq)
        j = seq(pos);
        t_start(i, j) = st(pos);
        t_end(i, j)   = ct(pos);
    end
end

%% 6. 验证：打印关键数值与论文表格对照
fprintf('\n===== 验证：与论文表格对照 =====\n');
fprintf('能力向量（各智能体）:\n');
for i = 1:N
    fprintf('  A%d: %s\n', i, fmt_vec(agents(i).resources(:).'));
end
fprintf('\n任务（按优先级降序）:\n');
fprintf('  %-4s | %-4s | %-4s | %-5s | %-20s | %s\n', ...
    'Col', 'Task', 'Prio', 'Val', 'Demand', 'Compl');
for col = 1:M
    j = task_order(col);
    fprintf('  %-4d | T%-3d | %-4d | %-5d | %-20s | %.1f%%\n', ...
        col, j, tasks(j).priority, tasks(j).value, ...
        fmt_vec(tasks(j).resource_demand(:).'), tdeg(j)*100);
end
fprintf('\n分配向量与时序（最终轮）:\n');
for i = 1:N
    for col = 1:M
        j = task_order(col);
        a = SC{j}(i,:);
        if any(a > EPS)
            fprintf('  A%d → T%d: alloc=%s  start=%.1f  end=%.1f\n', ...
                i, j, fmt_vec(a), t_start(i,j), t_end(i,j));
        end
    end
end
fprintf('=================================\n\n');

%% 7. 检查多轮次数据是否存在
if ~isfield(vd, 'all_rounds_SC') || ~isfield(vd, 'all_rounds_tdeg')
    error(['缺少 all_rounds_SC / all_rounds_tdeg 字段。\n' ...
           '请先重新运行 SS_Single_Viz.m 以生成含新字段的 .mat 文件。']);
end
num_r = size(vd.all_rounds_tdeg, 1);
target_rounds = unique([1, min(20, num_r), min(40, num_r), num_r]);

%% 8. 生成多轮次表格
L = {};

% preamble 注释
L{end+1} = '% 以下宏定义请粘贴至论文 preamble：';
L{end+1} = '% \usepackage{booktabs,multirow,makecell,array}';
L{end+1} = '% \newlength{\SEw}\setlength{\SEw}{2.4em}';
L{end+1} = '% \newcolumntype{C}[1]{>{\centering\arraybackslash}m{#1}}';
L{end+1} = '% \newcommand{\AllocCell}[1]{{\scriptsize #1}}';
L{end+1} = '';

for ti = 1:length(target_rounds)
    r = target_rounds(ti);

    SC_r    = vd.all_rounds_SC{r};
    tim_r   = vd.all_rounds_timing{r};
    tdeg_r  = vd.all_rounds_tdeg(r, :);

    % 建立该轮 t_start / t_end 查找表
    ts_r = nan(N, M);
    te_r = nan(N, M);
    for i = 1:N
        seq = tim_r(i).task_sequence;
        if isempty(seq), continue; end
        st = tim_r(i).start_times;
        ct = tim_r(i).completion_times;
        for pos = 1:length(seq)
            jj = seq(pos);
            ts_r(i, jj) = st(pos);
            te_r(i, jj) = ct(pos);
        end
    end

    if r == num_r
        cap_suffix   = sprintf('Round %d (Final)', r);
        label_suffix = 'final';
    else
        cap_suffix   = sprintf('Round %d', r);
        label_suffix = sprintf('r%d', r);
    end

    L = append_one_table(L, cap_suffix, label_suffix, ...
        SC_r, tim_r, tdeg_r, ts_r, te_r, ...
        N, M, K, agents, tasks, task_order, fmt_vec, fmt_time, EPS);
    L{end+1} = '';
end

%% 9. 写入文件
out_path = fullfile(script_dir, 'agent_task_schedule_table.tex');
fid = fopen(out_path, 'w', 'n', 'UTF-8');
if fid == -1
    error('无法创建文件: %s', out_path);
end
for k = 1:length(L)
    fprintf(fid, '%s\n', L{k});
end
fclose(fid);
fprintf('已保存: %s\n', out_path);
fprintf('包含 %d 张表（轮次 %s），每张含 %d 个任务、%d 个智能体。\n', ...
    length(target_rounds), mat2str(target_rounds), M, N);


%% ===== 本地函数 =====

function L = append_one_table(L, cap_suffix, label_suffix, ...
    SC_r, tim_r, tdeg_r, ts_r, te_r, ...
    N, M, K, agents, tasks, task_order, fmt_vec, fmt_time, EPS) %#ok<INUSD>

% 列定义：1列 robot + 2列/任务
col_spec = ['c' repmat(' C{\SEw} C{\SEw}', 1, M)];

L{end+1} = '\begin{table*}[t]';
L{end+1} = ['\caption{Agent--task schedule with resource allocations, ' ...
            'carrying capacities, task demands, and completion degrees ' ...
            '(\textit{' cap_suffix '}). ' ...
            'Tasks are ordered by priority in descending order.}'];
L{end+1} = ['\label{tab:agent_task_schedule_' label_suffix '}'];
L{end+1} = '\centering';
L{end+1} = '\scriptsize';
L{end+1} = '\setlength{\tabcolsep}{1.9pt}';
L{end+1} = '\renewcommand{\arraystretch}{1.10}';
L{end+1} = '';
L{end+1} = ['\begin{tabular}{' col_spec '}'];
L{end+1} = '\toprule';

% 第1标题行：任务列头
hdr1 = '\multirow{2}{*}{Robot}';
for col = 1:M
    j = task_order(col);
    hdr1 = [hdr1, sprintf(' & \\multicolumn{2}{c}{T%d (P%d, V%d)}', ...
            j, tasks(j).priority, tasks(j).value)]; %#ok<AGROW>
end
L{end+1} = [hdr1, ' \\'];

% cmidrule
cmid = '';
for col = 1:M
    c1 = 2 + (col-1)*2;
    cmid = [cmid, sprintf('\\cmidrule(lr){%d-%d}', c1, c1+1)]; %#ok<AGROW>
end
L{end+1} = cmid;

% 第2标题行：Start / End
hdr2 = '';
for col = 1:M
    hdr2 = [hdr2, ' & Start & End']; %#ok<AGROW>
end
L{end+1} = [hdr2(2:end), ' \\'];   % strip leading space, keep &
L{end+1} = '\midrule';

% 各智能体行
for i = 1:N
    cap_vec = agents(i).resources(:)';
    cap_str = fmt_vec(cap_vec);

    % 行1：分配向量（跨 Start+End 两列）
    alloc_parts = {};
    for col = 1:M
        j = task_order(col);
        alloc = SC_r{j}(i, :);
        if any(alloc > EPS)
            alloc_parts{end+1} = ['\multicolumn{2}{c}{\scriptsize $', fmt_vec(alloc), '$}']; %#ok<AGROW>
        else
            alloc_parts{end+1} = '\multicolumn{2}{c}{\scriptsize --}'; %#ok<AGROW>
        end
    end
    row1 = [sprintf('\\multirow{2}{*}{\\makecell[c]{A%d\\\\$%s$}}', i, cap_str), ...
            ' & ', strjoin(alloc_parts, ' & ')];
    L{end+1} = [row1, ' \\'];

    % 行2：时间 start / end
    time_parts = {};
    for col = 1:M
        j = task_order(col);
        if ~isnan(ts_r(i, j))
            time_parts{end+1} = [fmt_time(ts_r(i,j)), ' & ', fmt_time(te_r(i,j))]; %#ok<AGROW>
        else
            time_parts{end+1} = '-- & --'; %#ok<AGROW>
        end
    end
    L{end+1} = ['& ', strjoin(time_parts, ' & '), ' \\'];
    L{end+1} = '\midrule';
end

% Demand 行
row_d = '\textbf{Demand}';
for col = 1:M
    j = task_order(col);
    d = fmt_vec(tasks(j).resource_demand(:)');
    row_d = [row_d, ' & \multicolumn{2}{c}{\scriptsize $', d, '$}']; %#ok<AGROW>
end
L{end+1} = [row_d, ' \\'];
L{end+1} = '\midrule';

% Allocated 行
row_a = '\textbf{Allocated}';
for col = 1:M
    j = task_order(col);
    alloc_tot = sum(SC_r{j}, 1);
    a = fmt_vec(alloc_tot);
    row_a = [row_a, ' & \multicolumn{2}{c}{\scriptsize $', a, '$}']; %#ok<AGROW>
end
L{end+1} = [row_a, ' \\'];
L{end+1} = '\midrule';

% Completion 行
row_c = '\textbf{Completion}';
for col = 1:M
    j = task_order(col);
    pct = sprintf('%.1f\\%%', tdeg_r(j) * 100);
    row_c = [row_c, ' & \multicolumn{2}{c}{\scriptsize ', pct, '}']; %#ok<AGROW>
end
L{end+1} = [row_c, ' \\'];
L{end+1} = '\bottomrule';
L{end+1} = '\end{tabular}';
L{end+1} = '\end{table*}';

end
