$path = "comalg/Com_Huo2025/Huo2025_main.m"
$content = Get-Content -Raw -Encoding UTF8 $path
$pattern = '% 5\. 构建history_data.*?% 6\. 将final_Value_data作为第一个输出'
$replacement = "% 5. 构建history_data`n" + \
"history_data = struct();`n" + \
"history_data.algorithm = 'Huo2025';`n" + \
"history_data.final_utility = net_profit(end);`n" + \
"history_data.net_profit_evolution = net_profit;`n" + \
"history_data.cost_evolution = cost_sum;`n" + \
"history_data.num_rounds = Value_Params.num_rounds;  % 使用传入的轮数参数`n" + \
"history_data.initial_coalition = initial_coalition;`n" + \
"history_data.total_value_history = total_value_history;`n" + \
"history_data.total_value_possible = total_value_possible;`n`n" + \
"% 6. 将final_Value_data作为第一个输出"
$new = [regex]::Replace($content, $pattern, $replacement, 'Singleline')
Set-Content -Path $path -Value $new -Encoding UTF8
