function [Value_data,Rcost,cost_sum,net_profit, initial_coalition]= SA_Value_main(agents,tasks,Graph)
% =========================================================================
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
    previous_coalitionstru = Value_data(1).coalitionstru;
    
    while(doneflag == 0)
        % 初始化增量数组，用来存储每个机器人的增量
        incremental = zeros(1, Value_Params.N);
        
        % 依次进行联盟结构计算
        for ii = 1:Value_Params.N
            % 调用SA_Value_order()进行联盟优化
            [incremental(ii), Value_data(ii)] = Overlap_Coalition_Formation(agents, tasks, Value_data(ii), Value_Params,counter,AddPara);
            
            % 传递联盟结构给下一个智能体
            if ii < Value_Params.N 
                Value_data(ii + 1).coalitionstru = Value_data(ii).coalitionstru;
            end
        end
        
        % SA温度更新
        Value_Params.Temperature = Value_Params.alpha * Value_Params.Temperature;
        
        % 获取最终联盟结构
        final_coalitionstru = Value_data(Value_Params.N).coalitionstru;
        T = T + 1;
        
        % 收敛性检测
        if isequal(previous_coalitionstru, final_coalitionstru)
            k_stable = k_stable + 1;
        else
            k_stable = 0;
        end
        
        % 收敛判断：稳定迭代次数或温度达到阈值
        if k_stable >= Value_Params.max_stable_iterations || Value_Params.Temperature < Value_Params.Tmin
            disp('Convergence detected: Coalition structure has stabilized for multiple iterations.');
            doneflag = 1;
        end
        
        % 更新前次联盟结构
        previous_coalitionstru = final_coalitionstru;
        
        % 传递给其他机器人的联盟结构
        for ii = 1:Value_Params.N
            Value_data(ii).coalitionstru = final_coalitionstru;
        end
    end
    
    
    curnumberrow = zeros(1, Value_Params.N);
    for i = 1:Value_Params.N
        [curRow, ~] = find(final_coalitionstru(:, i) == i);
        if ~isempty(curRow)
            curnumberrow(i) = curRow;
        else
            curnumberrow(i) = Value_Params.M + 1;  % 未分配任务
        end
    end
    
    %% 记录一次联盟形成后观测次数
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
    %% 联盟形成后根据观测更新belief
    for i=1:Value_Params.N
        for j=1:Value_Params.M
            Value_data(i).initbelief(j,1:end)=drchrnd([1+Value_data(i).observe(j,1),1+Value_data(i).observe(j,2),1+Value_data(i).observe(j,3)],1)';
            %  Value_data(i).initbelief(j,1:end)=[1/3,1/3,1/3];
        end
    end
    
    initial_coalition=final_coalitionstru;
    
end
end
