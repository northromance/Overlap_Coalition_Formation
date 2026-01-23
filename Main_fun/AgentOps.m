classdef AgentOps
    % AgentOps 智能体认知与行为操作类
    % 职责：处理观测数据的收集、全局信息的融合与同步，以及信念的贝叶斯更新。
    
    methods (Static)
        function [Value_data, summatrix] = collect_observations(Value_data, agents, tasks, Value_Params, summatrix, SC)
            % collect_observations 模拟智能体对任务类型的观测过程与信息共享。
            % 过程：
            %   1. 智能体根据探测概率(detprob)对任务类型进行观测（可能出错）。
            %   2. 将观测结果汇总到全局矩阵(summatrix)，实现通信共享。
            
            if nargin < 6 || isempty(summatrix)
                summatrix = zeros(Value_Params.M, Value_Params.task_type);
            end

            SC_global = SC;

            % --- 阶段1：各智能体独立观测 ---
            for i = 1:Value_Params.N
                % [修正] 在新架构中，任务查询逻辑已移至 WorldSim 类
                taskIds = WorldSim.get_agent_tasks_fast(SC_global, i);
                
                if isempty(taskIds), continue; end

                for tIdx = 1:numel(taskIds)
                    taskId = taskIds(tIdx);

                    % 确定任务的真实类型索引与错误类型索引集合
                    taskindex = find(tasks(taskId).value == tasks(taskId).WORLD.value, 1);
                    nontaskindex = find(tasks(taskId).value ~= tasks(taskId).WORLD.value);

                    if isempty(taskindex), continue; end

                    % 根据 obs_times 执行多次观测采样
                    for m = 1:Value_Params.obs_times
                        r = rand;
                        % 逻辑：随机数 < 探测概率 -> 观测正确；否则 -> 随机产生一个错误观测
                        if r <= agents(i).detprob || isempty(nontaskindex)
                            Value_data(i).observe(taskId, taskindex) = Value_data(i).observe(taskId, taskindex) + 1;
                        else
                            % 随机选择一个错误的类型进行累加
                            chosen_idx = nontaskindex(randi(numel(nontaskindex)));
                            Value_data(i).observe(taskId, chosen_idx) = Value_data(i).observe(taskId, chosen_idx) + 1;
                        end
                    end
                end
            end

            % --- 阶段2：信息融合与同步 ---
            % 更新全局观测矩阵：加上各智能体自上次同步以来的新增观测
            for j = 1:Value_Params.M
                for k = 1:Value_Params.task_type
                    for i = 1:Value_Params.N
                        % 新增量 = 当前累计观测 - 上次同步时的快照
                        summatrix(j, k) = summatrix(j, k) + Value_data(i).observe(j, k) - Value_data(i).preobserve(j, k);
                    end
                end
            end

            % 将全局信息回写给每个智能体，完成信息共享
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
            % update_belief_from_observations 利用贝叶斯公式更新智能体的信念 (Belief)。
            % 方法：Dirichlet 分布作为 Multinomial 分布的共轭先验。
            
            for i = 1:Value_Params.N
                for j = 1:Value_Params.M
                    % 计算 Dirichlet 分布的参数 alpha (加1代表均匀先验)
                    alpha_params = 1 + Value_data(i).observe(j, 1:Value_Params.task_type);

                    % 从更新后的 Dirichlet 分布中采样，得到新的信念概率分布
                    % [注] drchrnd 属于基础数学工具，保留在 OCFUtils 中
                    Value_data(i).initbelief(j, 1:end) = OCFUtils.drchrnd(alpha_params, 1)';
                end
            end
        end
    end
end