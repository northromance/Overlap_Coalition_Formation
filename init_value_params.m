function Value_Params = init_value_params(N, M, K, num_task_types, task_type_demands, SA_Temperature, SA_alpha, SA_Tmin, SA_max_stable_iterations, obs_times, num_rounds)
% INIT_VALUE_PARAMS 初始化算法参数结构
%
% 输入参数:
%   N                          - 智能体数量
%   M                          - 任务数量
%   K                          - 资源类型数量
%   num_task_types             - 任务价值类型数量
%   task_type_demands          - 任务类型资源需求矩阵
%   SA_Temperature             - 模拟退火初始温度
%   SA_alpha                   - 模拟退火温度衰减率
%   SA_Tmin                    - 模拟退火最小温度
%   SA_max_stable_iterations   - 模拟退火最大稳定迭代次数
%   obs_times                  - 每个任务的观测次数
%   num_rounds                 - 游戏总轮数
%
% 输出参数:
%   Value_Params               - 算法参数结构体
%
% 示例:
%   Value_Params = init_value_params(8, 5, 6, 3, task_type_demands, 100.0, 0.95, 0.01, 5, 20, 100);

    % 基本参数
    Value_Params.N = N;
    Value_Params.M = M;
    Value_Params.K = K;
    Value_Params.task_type = num_task_types;  % 任务价值类型数量（低、中、高）
    Value_Params.task_type_demands = task_type_demands;
    
    % 模拟退火算法参数
    Value_Params.Temperature = SA_Temperature;
    Value_Params.alpha = SA_alpha;
    Value_Params.Tmin = SA_Tmin;
    Value_Params.max_stable_iterations = SA_max_stable_iterations;
    
    % 观测参数
    Value_Params.obs_times = obs_times;
    
    % 游戏参数
    Value_Params.num_rounds = num_rounds;
    
end
