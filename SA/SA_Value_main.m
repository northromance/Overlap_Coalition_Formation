function [Value_data,Rcost,cost_sum,net_profit, initial_coalition]= SA_Value_main(agents,tasks,Graph)
% =========================================================================
%  函数名称：Value_main
%
%  算法主要功能：
%  ------------------------------------------------------------------------
%  本算法基于多智能体联盟形成（Coalition Formation）与任务值估计机制，
%  完成以下核心流程：
%    1. 初始化 agent 的 belief、联盟结构和观测矩阵。
%    2. 通过迭代过程：每个 agent 根据 belief 选择任务并形成联盟。
%    3. 按通信拓扑 Graph 执行邻居信息共享，更新任务估计。
%    4. 每轮联盟形成后，agent 通过模拟观测更新 Dirichlet belief。
%    5. 计算每轮联盟结构下的成本、收益与净收益。
%    6. 重复多次（counter=1:50），用于统计不同联盟的收益表现。
%
%  输入参数：
%  ------------------------------------------------------------------------
%  agents：结构体数组，包含：
%       - id：agent ID
%       - x, y：空间坐标
%       - fuel：燃料单价（决定行动成本）
%       - detprob：观测正确概率
%
%  tasks：结构体数组，包含：
%       - x, y：任务位置
%       - value：任务当前可能值（一个 3 维向量）
%       - WORLD.value：任务真实值（环境设定）
%
%  Graph：通信邻接矩阵（N×N），Graph(i,j)=1 表示 agent i 和 j 可通信
%
%
%  输出参数：
%  ------------------------------------------------------------------------
%  Value_data：包含每个 agent 在各轮迭代中的 belief、观测、联盟结构等信息
%
%  Rcost：联盟中 agent 的行动成本（距离 × fuel）
%
%  cost_sum：50 次联盟形成中，每次的总成本
%
%  net_profit：50 次联盟形成中，每次的（收益 - 成本）
%
%  initial_coalition：第一次联盟形成的联盟成员结构
%
%  注：算法内部会运行多轮 belief 更新、联盟优化和通信，最终输出每轮的成本与收益。
%
% =========================================================================

Value_Params=Value_init(length(agents),length(tasks));

for i=1:Value_Params.N %包括agent标号，索引以及初始联盟结构
    Value_data(i).agentID=agents(i).id;
    Value_data(i).agentIndex=i;
    Value_data(i).iteration=0;%联盟改变次数
    Value_data(i).unif=0;%均匀随机变量
    Value_data(i).coalitionstru=zeros(Value_Params.M+1,Value_Params.N);
    Value_data(i).initbelief=zeros(Value_Params.M+1,3);
end

for k=1: Value_Params.N   %所有agents放在void 任务中
    for j=1:Value_Params.M+1
        if j==Value_Params.M+1
            for i=1:Value_Params.N
                Value_data(k).coalitionstru(j,i)=agents(i).id;
            end
        end
    end
end

for i=1:Value_Params.N %每一个agent对所有任务的任务值持有一个初始belief
    for j=1:Value_Params.M
        %Value_data(i).initbelief(j,1:end)=drchrnd([1,1,1],1)';
        Value_data(i).initbelief(j,1:end)=[1/3,1/3,1/3]';
    end
end

for i=1:Value_Params.N
    for j=1:Value_Params.M
        for k=1:3
            Value_data(i).observe(j,k)=0;%创建每个agent对当前所在任务联盟的观测矩阵
            Value_data(i).preobserve(j,k)=0;
            summatrix(j,k)=0;
        end
    end
end

%此处应该有个for/which循环

for counter=1:50
    for i=1:Value_Params.N   %一会要改回来
        for j=1:Value_Params.M
            Value_data(i).tasks(j).prob(counter,:)=Value_data(i).initbelief(j,1:end);
        end
    end
    
    T=1;   %迭代次数
    lastTime=T-1;
    doneflag=0;   %初始标志位0，收敛标志位为1
    
    while( doneflag==0)
        
        %communication
        
        %所有agents选择自主任务
        for ii=1:Value_Params.N
            [incremental(ii),curnumberrow(ii),Value_data(ii)]=SA_Value_order(agents, tasks, Value_data(ii), Value_Params,counter);
            incremental(ii);
        end
        
        if (length(find(incremental==0))==Value_Params.N)
            lastTime= lastTime;
        else
            lastTime=T;
        end
        % length(find(incremental==0))
        Value_data= Value_communication(agents, tasks, Value_data, Value_Params,Graph); %邻居agent间彼此通信
        
        %convergence check
        
        if (T-lastTime>2)
            %     if (T==100)
            doneflag=1;
        else
            T=T+1;
        end
    end
    
    if counter==1
        for j=1:Value_Params.M
            initial_coalition(j).member=find(Value_data(1).coalitionstru(j,:)~=0);
        end
    end
    
    %记录一次联盟形成后观测次数
    for i=1:Value_Params.N
        if  curnumberrow(i)~=Value_Params.M+1
            for m=1:20
                taskindex=find(tasks(curnumberrow(i)).value== tasks(curnumberrow(i)).WORLD.value);
                nontaskindex=find(tasks(curnumberrow(i)).value~= tasks(curnumberrow(i)).WORLD.value);
                if rand<=agents(i).detprob
                    Value_data(i).observe(curnumberrow(i),  taskindex)= Value_data(i).observe(curnumberrow(i),taskindex)+1;%更新观测矩阵
                    m=m+1;
                elseif (agents(i).detprob<rand)&&(rand<=(1-1/2*agents(i).detprob))
                    Value_data(i).observe(curnumberrow(i),  nontaskindex(1))= Value_data(i).observe(curnumberrow(i),nontaskindex(1))+1;%更新观测矩阵
                    m=m+1;
                else
                    Value_data(i).observe(curnumberrow(i),  nontaskindex(2))= Value_data(i).observe(curnumberrow(i),nontaskindex(2))+1;%更新观测矩阵
                    m=m+1;
                end
            end
        end
    end
    
    for j=1:Value_Params.M
        for k=1:3
            for i=1:Value_Params.N
                summatrix(j,k)=summatrix(j,k)+ Value_data(i).observe(j,  k)-Value_data(i).preobserve(j,  k);
            end
        end
    end
    
    for i=1:Value_Params.N
        for j=1:Value_Params.M
            for k=1:3
                Value_data(i).preobserve(j,k)= summatrix(j,k);
                Value_data(i).observe(j,  k)= summatrix(j,k);
            end
        end
    end
    
    %
    %一次联盟形成后根据观测更新belief
    for i=1:Value_Params.N
        for j=1:Value_Params.M
            Value_data(i).initbelief(j,1:end)=drchrnd([1+Value_data(i).observe(j,1),1+Value_data(i).observe(j,2),1+Value_data(i).observe(j,3)],1)';
            %  Value_data(i).initbelief(j,1:end)=[1/3,1/3,1/3];
        end
    end
    
    Rcost=zeros(Value_Params.M,Value_Params.N);
    for j=1:Value_Params.M
        lianmeng(j).member=find(Value_data(1).coalitionstru(j,:)~=0);
        for i=1:length(lianmeng(j).member)
            Rcost(j,i)=sqrt((agents(lianmeng(j).member(i)).x-tasks(j).x)^2 ...
                +(agents(lianmeng(j).member(i)).y-tasks(j).y)^2)*agents(lianmeng(j).member(i)).fuel;
        end
    end
    
    cost_sum(counter)=0;
    for j=1:size(Rcost,1)
        for i=1:size(Rcost,2)
            cost_sum(counter)=cost_sum(counter)+Rcost(j,i);
        end
    end
    
    revenue_sum(counter)=0;
    for j=1:Value_Params.M
        revenue_sum(counter)=revenue_sum(counter)+tasks(j).value;
    end
    
    net_profit(counter)= revenue_sum(counter)- cost_sum(counter);
    
    counter=counter+1;
    
end
end
