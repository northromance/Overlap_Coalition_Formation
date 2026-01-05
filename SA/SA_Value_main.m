function [Value_data,Rcost,cost_sum,net_profit, initial_coalition]= SA_Value_main(agents,tasks,AddPara,Value_Params)
% SA_Value_main - 基于模拟退火的重叠联盟形成主函数

%% 初始化智能体数据结构
for i=1:Value_Params.N
    Value_data(i).agentID=agents(i).id;
    Value_data(i).agentIndex=i;
    Value_data(i).iteration=0;%联盟改变次数
    Value_data(i).unif=0;%均匀随机变量
    Value_data(i).coalitionstru=zeros(Value_Params.M+1,Value_Params.N);
    Value_data(i).initbelief=zeros(Value_Params.M+1,3);

    % 初始化资源分配矩阵 (M×K)
    Value_data(i).resources_matrix = zeros(Value_Params.M, Value_Params.K);
    
    % 新联盟结构矩阵
    Value_data(i).SC = cell(Value_Params.M, 1);      % 资源联盟结构cell
    for m = 1:Value_Params.M
        Value_data(i).SC{m} = zeros(Value_Params.N, Value_Params.K);  % 任务m的N×K资源分配矩阵
        % 将当前智能体的资源分配到SC对应行
        Value_data(i).SC{m}(i, :) = Value_data(i).resources_matrix(m, :);
    end
    Value_data(i).other = cell(Value_Params.N, 1);   % 存储其他智能体信念
end

%% 初始化void任务（所有智能体初始未分配）
for k=1: Value_Params.N
    for j=1:Value_Params.M+1
        if j==Value_Params.M+1                       % void任务（第M+1行）
            for i=1:Value_Params.N
                Value_data(k).coalitionstru(j,i)=agents(i).id;  % 所有智能体放入void
            end
        end
    end
end

%% 初始化信念分布（均匀分布）
for i=1:Value_Params.N
    for j=1:Value_Params.M
        Value_data(i).initbelief(j,1:end)=[1/3,1/3,1/3]';  % 均匀先验信念
    end
end
% 初始化认为其他机器人的信念值
for i=1:Value_Params.N
    for j = 1:Value_Params.N
        Value_data(i).other{j}.initbelief = Value_data(j).initbelief;  % 智能体j的信念分布
    end
end

%% 初始化观测矩阵
for i=1:Value_Params.N
    for j=1:Value_Params.M
        for k=1:3
            Value_data(i).observe(j,k)=0;        % 当前观测计数
            Value_data(i).preobserve(j,k)=0;     % 前次观测计数
            summatrix(j,k)=0;                    % 全局观测累计
        end
    end
end


for i=1:Value_Params.N
    Value_data(i).resources = agents(i).resources;  % 赋予智能体资源
end

%% 主循环：50轮游戏迭代
for counter=1:50
    for i=1:Value_Params.N
        for j=1:Value_Params.M
            Value_data(i).tasks(j).prob(counter,:)=Value_data(i).initbelief(j,1:end);  % 记录信念概率
        end
    end

    % SA迭代初始化
    T=1;                                  % 迭代计数
    lastTime=T-1;                         % 上次时间
    previous_SC = Value_data(1).SC;       % 前次资源联盟结构
    k_stable = 0;                         % 稳定计数
    doneflag = 0;                         % 收敛标志


    %% SA主循环
    while(doneflag == 0)
        incremental = zeros(1, Value_Params.N);  % 各智能体效用增量

        % 计算已分配资源和缺口

        % 顺序遍历各智能体进行联盟优化
        for ii = 1:Value_Params.N
            % 计算已分配资源和缺口
           
            % 计算已经分配的资源和剩余资源的缺口
            [allocated_resources, resource_gap] = compute_allocated_and_gap(Value_data(ii), agents, tasks, Value_Params);

            % 重叠联盟形成
            [inc_ii, Value_data_ii] = Overlap_Coalition_Formation(agents, tasks, Value_data(ii), Value_Params,counter,AddPara, allocated_resources, resource_gap);  % 联盟形成
            incremental(ii) = inc_ii;  % 记录效用增量


            % 传递联盟结构给下一智能体
            if ii < Value_Params.N
                Value_data(ii + 1).coalitionstru = Value_data_ii.coalitionstru;  % 传递成员结构
                Value_data(ii + 1).SC = Value_data_ii.SC;                        % 传递资源分配
            end
        end

        % SA温度衰减
        Value_Params.Temperature = Value_Params.alpha * Value_Params.Temperature;  % 温度退火

        % 获取最终联盟结构
        final_SC = Value_data(Value_Params.N).SC;                      % 最终资源分配
        final_coalitionstru = Value_data(Value_Params.N).coalitionstru;  % 最终成员结构
        T = T + 1;                                                      % 迭代计数+1

        % 收敛性检测
        if isequal(previous_SC, final_SC)
            k_stable = k_stable + 1;  % 结构未变，稳定计数+1
        else
            k_stable = 0;             % 结构改变，重置计数
        end

        % 判断收敛条件
        if k_stable >= Value_Params.max_stable_iterations || Value_Params.Temperature < Value_Params.Tmin
            disp('Convergence detected: Coalition structure has stabilized for multiple iterations.');
            doneflag = 1;  % 设置收敛标志
        end

        previous_SC = final_SC;  % 保存当前SC用于下轮对比

        % 同步全局联盟结构
        for ii = 1:Value_Params.N
            Value_data(ii).coalitionstru = final_coalitionstru;  % 同步成员结构
            Value_data(ii).SC = final_SC;                        % 同步资源分配
        end
    end


    %% 提取各智能体参与的任务集合（重叠联盟）
    % 说明：在“重叠联盟”下，一个智能体可以同时参与多个任务。
    % - final_coalitionstru 的每一列对应一个智能体
    % - 第 j 行(1..M)表示任务 Tj 的成员关系；第 M+1 行是 void(未分配)占位
    % - 任务成员通常用非零表示(常见为写入 agentID)，所以这里用 ~=0 判断参与
    % 输出：curTaskList{i} 是智能体 i 参与的任务ID向量（范围 1..M）
    curTaskList = cell(1, Value_Params.N);
    for i = 1:Value_Params.N
        curTaskList{i} = find(final_coalitionstru(1:Value_Params.M, i) ~= 0);
    end

    %% 记录观测（每个参与任务各采样20次）
    % 观测建模：每个智能体对“自己参与的每个任务”的真实价值进行多次观测采样。
    % - tasks(j).WORLD.value 是所有候选价值集合(长度=3)，例如 [300,500,1000]
    % - tasks(j).value 是该任务的真实价值(必然属于候选集)
    % - Value_data(i).observe(j,k) 统计智能体 i 对任务 j 观测为第 k 个价值的次数
    % - detprob 为正确检测概率；否则发生误检，将观测计入非真实价值的某个类别
    for i = 1:Value_Params.N
        taskIds = curTaskList{i};
        if isempty(taskIds)
            continue; % 该智能体本轮未参与任何真实任务(只在void)，不产生观测
        end

        for tIdx = 1:numel(taskIds)
            taskId = taskIds(tIdx);

            % 真实价值在候选集中的索引(1..3)
            taskindex = find(tasks(taskId).value == tasks(taskId).WORLD.value);
            % 非真实价值的索引(长度=2)
            nontaskindex = find(tasks(taskId).value ~= tasks(taskId).WORLD.value);

            for m = 1:20
                % 采样一次随机数，决定本次观测结果落在哪个类别
                % - 概率 detprob：观测为真实价值
                % - 剩余概率：误检到两个非真实价值类别(按原代码阈值划分)
                r = rand;
                if r <= agents(i).detprob                                       % 正确检测
                    Value_data(i).observe(taskId, taskindex) = Value_data(i).observe(taskId, taskindex) + 1;
                elseif (agents(i).detprob < r) && (r <= (1 - 1/2*agents(i).detprob))  % 误检1
                    Value_data(i).observe(taskId, nontaskindex(1)) = Value_data(i).observe(taskId, nontaskindex(1)) + 1;
                else                                                             % 误检2
                    Value_data(i).observe(taskId, nontaskindex(2)) = Value_data(i).observe(taskId, nontaskindex(2)) + 1;
                end
            end
        end
    end

    % 聚合所有智能体观测
    % summatrix(j,k) 维护“全体智能体对任务 j 的新观测增量”的累计结果。
    % 这里用 observe - preobserve 来提取“本轮新增观测”，避免重复累计。
    for j=1:Value_Params.M
        for k=1:3
            for i=1:Value_Params.N
                summatrix(j,k)=summatrix(j,k)+ Value_data(i).observe(j,  k)-Value_data(i).preobserve(j,  k);  % 累计新观测
            end
        end
    end

    % 同步观测给所有智能体
    % 将全局聚合后的观测结果广播给每个智能体，使所有智能体拥有一致的观测统计。
    % - preobserve：记录“上一次同步后的观测”(用于下轮求增量)
    % - observe：记录“当前同步后的观测”(后续用于更新 Dirichlet 后验)
    for i=1:Value_Params.N
        for j=1:Value_Params.M
            for k=1:3
                Value_data(i).preobserve(j,k)= summatrix(j,k);  % 更新前次观测
                Value_data(i).observe(j,  k)= summatrix(j,k);   % 更新当前观测
            end
        end
    end

    %% 根据观测更新信念（Dirichlet后验）
    for i=1:Value_Params.N
        for j=1:Value_Params.M
            Value_data(i).initbelief(j,1:end)=drchrnd([1+Value_data(i).observe(j,1),1+Value_data(i).observe(j,2),1+Value_data(i).observe(j,3)],1)';  % Dirichlet采样
        end
    end

    %% 信念广播：同步各智能体的信念到other中
    for i = 1:Value_Params.N
        for j = 1:Value_Params.N
            Value_data(i).other{j}.initbelief = Value_data(j).initbelief;  % 智能体i更新其对智能体j信念的认知
        end
    end


    % 设置未使用输出参数
    Rcost = [];       % 路径成本（保留接口）
    cost_sum = [];    % 总成本（保留接口）
    net_profit = [];  % 净收益（保留接口）

end
end
