function Value_Params=Value_init(N,M,K)
Value_Params.N=N;
Value_Params.M=M;
Value_Params.K=K;

% 添加模拟退火相关参数
Value_Params.Temperature = 100.0;      % 初始温度
Value_Params.alpha = 0.95;              % 温度衰减率
Value_Params.Tmin = 0.01;              % 最小温度
Value_Params.max_stable_iterations = 5; % 最大稳定迭代次数
end