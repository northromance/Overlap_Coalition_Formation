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

    % 新联盟结构矩阵
    Value_data(i).SC = cell(Value_Params.M, 1);      % 资源联盟结构cell
    for m = 1:Value_Params.M
        Value_data(i).SC{m} = zeros(Value_Params.N, Value_Params.K);  % 任务m的N×K资源分配矩阵
        % 记录了i一共N个智能体 每个智能体存储M个任务的 资源分配矩阵 记录着N个智能体 分别给每个任务分配了多少资源
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
            % resource_gap 为智能体根据信念计算的缺口

            [allocated_resources, resource_gap] = compute_allocated_and_gap(Value_data(ii), agents, tasks, Value_Params);


            [inc_ii, ~, Value_data_ii] = Overlap_Coalition_Formation(agents, tasks, Value_data(ii), Value_Params,counter,AddPara, allocated_resources, resource_gap);  % 联盟形成
            incremental(ii) = inc_ii;  % 记录效用增量

            % 更新关键字段
            Value_data(ii).coalitionstru = Value_data_ii.coalitionstru;  % 联盟结构
            Value_data(ii).SC = Value_data_ii.SC;                        % 资源分配
            if isfield(Value_data_ii, 'resources_matrix')
                Value_data(ii).resources_matrix = Value_data_ii.resources_matrix;  % 资源矩阵
            end
            if isfield(Value_data_ii, 'selectProb')
                Value_data(ii).selectProb = Value_data_ii.selectProb;    % 选择概率
            end
            if isfield(Value_data_ii, 'iteration')
                Value_data(ii).iteration = Value_data_ii.iteration;      % 迭代次数
            end
            if isfield(Value_data_ii, 'unif')
                Value_data(ii).unif = Value_data_ii.unif;                % 随机数
            end

            % 传递联盟结构给下一智能体
            if ii < Value_Params.N
                Value_data(ii + 1).coalitionstru = Value_data(ii).coalitionstru;  % 传递成员结构
                Value_data(ii + 1).SC = Value_data(ii).SC;                        % 传递资源分配
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


    %% 提取各智能体当前任务
    curnumberrow = zeros(1, Value_Params.N);  % 各智能体当前任务编号
    for i = 1:Value_Params.N
        [curRow, ~] = find(final_coalitionstru(:, i) == i);
        if ~isempty(curRow)
            curnumberrow(i) = curRow(1);           % 取第一个任务
        else
            curnumberrow(i) = Value_Params.M + 1;  % void任务
        end
    end

    %% 记录观测（20次采样）
    for i=1:Value_Params.N
        if  curnumberrow(i)~=Value_Params.M+1            % 非void任务
            for m=1:20
                taskindex=find(tasks(curnumberrow(i)).value== tasks(curnumberrow(i)).WORLD.value);      % 真实价值索引
                nontaskindex=find(tasks(curnumberrow(i)).value~= tasks(curnumberrow(i)).WORLD.value);  % 非真实价值索引
                if rand<=agents(i).detprob                                      % 正确检测
                    Value_data(i).observe(curnumberrow(i),  taskindex)= Value_data(i).observe(curnumberrow(i),taskindex)+1;
                    m=m+1;
                elseif (agents(i).detprob<rand)&&(rand<=(1-1/2*agents(i).detprob))  % 误检1
                    Value_data(i).observe(curnumberrow(i),  nontaskindex(1))= Value_data(i).observe(curnumberrow(i),nontaskindex(1))+1;
                    m=m+1;
                else                                                            % 误检2
                    Value_data(i).observe(curnumberrow(i),  nontaskindex(2))= Value_data(i).observe(curnumberrow(i),nontaskindex(2))+1;
                    m=m+1;
                end
            end
        end
    end

    % 聚合所有智能体观测
    for j=1:Value_Params.M
        for k=1:3
            for i=1:Value_Params.N
                summatrix(j,k)=summatrix(j,k)+ Value_data(i).observe(j,  k)-Value_data(i).preobserve(j,  k);  % 累计新观测
            end
        end
    end

    % 同步观测给所有智能体
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
