function [Value_data, history_data] = SA_Value_MultiStart_main(agents, tasks, AddPara, Value_Params)
% SA_Value_MultiStart_main - 多起点重启的 SA 算法
%
% 改进点：
%   1. 运行多次 SA（例如 3-5 次），每次使用不同的初始解
%   2. 每次运行使用较少的轮数（num_rounds / num_restarts）
%   3. 返回所有运行中的最优解
%   4. 目标：通过多起点搜索降低对初始解的依赖，提高全局搜索能力
%
% 输入/输出：与 SA_Value_main 相同

%% TODO: 实现多起点重启策略
% 提示：
% - 设置 num_restarts = 3
% - 每次重启使用不同的随机种子
% - 调整 Value_Params.num_rounds = original_rounds / num_restarts
% - 跟踪全局最优解

% 暂时调用原始算法（占位符）
warning('SA_Value_MultiStart_main: 尚未实现，调用原始 SA_Value_main');
[Value_data, history_data] = SA_Value_main(agents, tasks, AddPara, Value_Params);

end
