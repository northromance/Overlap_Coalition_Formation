classdef AgentOps
    % AgentOps 智能体观测与信念更新模块
    % 职责：处理观测数据的采集、全局信息融合与同步，以及基于观测的贝叶斯更新。
    
    methods (Static)
        function [Value_data, summatrix] = collect_observations(Value_data, agents, tasks, Value_Params, summatrix, SC)
            % collect_observations 模拟智能体对任务类型的观测，并进行信息融合
            % 过程：
            %   1. 根据智能体探测概率(detprob)对参与任务进行观测（可能产生误判）；
            %   2. 将观测结果汇总到全局统计矩阵(summatrix)，实现通信共享。
            
            if nargin < 6 || isempty(summatrix)
                summatrix = zeros(Value_Params.M, Value_Params.task_type);
            end

            SC_global = SC;

            % --- 阶段1：各智能体进行局部观测 ---
            for i = 1:Value_Params.N
                % [说明] 在新架构下，任务查询逻辑统一封装到 OCFUtils 中
                taskIds = OCFUtils.get_agent_tasks_fast(SC_global, i);
                
                if isempty(taskIds), continue; end

                for tIdx = 1:numel(taskIds)
                    taskId = taskIds(tIdx);

                    % 确定该任务真实类型对应的位置，以及其他非真实类型位置
                    taskindex = find(tasks(taskId).value == tasks(taskId).WORLD.value, 1);
                    nontaskindex = find(tasks(taskId).value ~= tasks(taskId).WORLD.value);

                    if isempty(taskindex), continue; end

                    % 根据 obs_times 执行多次观测
                    for m = 1:Value_Params.obs_times
                        r = rand;
                        % 逻辑：随机数 < 探测概率 -> 观测到正确类型；否则随机观测成一个错误类型
                        if r <= agents(i).detprob || isempty(nontaskindex)
                            Value_data(i).observe(taskId, taskindex) = Value_data(i).observe(taskId, taskindex) + 1;
                        else
                            % 随机选择一个错误类型并累加
                            chosen_idx = nontaskindex(randi(numel(nontaskindex)));
                            Value_data(i).observe(taskId, chosen_idx) = Value_data(i).observe(taskId, chosen_idx) + 1;
                        end
                    end
                end
            end

            % --- 阶段2：信息融合与同步 ---
            % 计算全局观测矩阵：汇总各智能体自上次同步以来新增的观测
            for j = 1:Value_Params.M
                for k = 1:Value_Params.task_type
                    for i = 1:Value_Params.N
                        % 新增观测 = 当前累计观测 - 上次同步时的快照
                        summatrix(j, k) = summatrix(j, k) + Value_data(i).observe(j, k) - Value_data(i).preobserve(j, k);
                    end
                end
            end

            % 将全局信息写回每个智能体，实现信息同步
            for i = 1:Value_Params.N
                for j = 1:Value_Params.M
                    for k = 1:Value_Params.task_type
                        Value_data(i).preobserve(j, k) = summatrix(j, k); % 更新快照
                        Value_data(i).observe(j, k) = summatrix(j, k);    % 更新当前认知
                    end
                end
            end
        end

        function Value_data = update_belief_from_observations(Value_data, Value_Params)
            % update_belief_from_observations 利用贝叶斯方式更新任务类型信念 (Belief)
            % 这里用 Dirichlet 分布作为 Multinomial 分布的共轭先验。
            
            for i = 1:Value_Params.N
                for j = 1:Value_Params.M
                    % 构造 Dirichlet 分布参数 alpha（加1表示单位先验）
                    alpha_params = 1 + Value_data(i).observe(j, 1:Value_Params.task_type);

                    % 从更新后的 Dirichlet 分布中采样，得到新的任务类型概率分布
                    % [注] drchrnd 属于概率统计工具函数，封装在 OCFUtils 中
                    Value_data(i).initbelief(j, 1:end) = OCFUtils.drchrnd(alpha_params, 1)';
                end
            end
        end
    end
end