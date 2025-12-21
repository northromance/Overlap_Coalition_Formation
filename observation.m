%返回agent所在任务index
clc;
clear;
SEED=24377;
rand('seed',SEED);%设置随机数，后面可能用得到

WORLD.value=[50,100,200];
curnumberrow=[4,2,5,3,3,1,1,2,4,3];
for i=1:10
    agents(i).id=i;
    agents(i).vel=2;%巡航速度，用于判断后面任务奖励折现
    agents(i).fuel=1;%油耗/m
%     agents(i).x=rand(1)*(WORLD.XMAX-WORLD.XMIN)+WORLD.XMIN;
%     agents(i).y=rand(1)*(WORLD.YMAX-WORLD.YMIN)+WORLD.YMIN;
    agents(i).detprob=0.9;
end
for j=1:5
    tasks(j).id=j;
% % %     tasks(j).req=randint(1,1,[0,3]);
% %     tasks(j).req=round(rand(1,1))*(-1)+1;
%     tasks(j).req=randperm(3,1);%最小数量要求,[0,2]中取随机数
    tasks(j).req=2;%最小数量要求,[0,2]中取随机数
    tasks(j).lamuda=0.1;   %折现系数
%     tasks(j).x=rand(1)*(WORLD.XMAX-WORLD.XMIN)+WORLD.XMIN;
%     tasks(j).y=rand(1)*(WORLD.YMAX-WORLD.YMIN)+WORLD.YMIN;
%     tasks(j).z=rand(1)*(WORLD.ZMAX-WORLD.ZMIN)+WORLD.ZMIN;
    tasks(j).value=WORLD.value(randi(length(WORLD.value),1,1)); %随机选择一个UAV进行更新;%randi是matlab中能产生均匀分布的伪随机整数的新函数
    tasks(j).WORLD.value=[50,100,200];%任务值为离散型随机变量，在50-200取离散值
end

for i=1:10
    for j=1:5
    for k=1:3
    Value_data(i).observe(j,k)=0;%创建每个agent对当前所在任务联盟的观测矩阵
    Value_data(i).preobserve(j,k)=0;
     summatrix(j,k)=0;
    end
    end
end

for mmm=1:2
    for i=1:10%局部观测
                 taskindex=find(tasks(curnumberrow(i)).value== tasks(curnumberrow(i)).WORLD.value);
                 nontaskindex=find(tasks(curnumberrow(i)).value~= tasks(curnumberrow(i)).WORLD.value);
            for m=1:10
                 
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
   

    for j=1:5
        for k=1:3
           
            for i=1:10
            summatrix(j,k)=summatrix(j,k)+ Value_data(i).observe(j,  k)-Value_data(i).preobserve(j,  k);
            end
        end
    end
%     
    for i=1:10
    for j=1:5
    for k=1:3
    Value_data(i).preobserve(j,k)= summatrix(j,k);
    Value_data(i).observe(j,  k)= summatrix(j,k);
    end
    end
end
%     
%     
%     
%     for i=1:10
%     for j=1:5
%     for k=1:3
%     Value_data(i).observe(j,k)= summatrix(j,k);%创建每个agent对当前所在任务联盟的观测矩阵
%     end
%     end
% end
%     
    
    
   for i=1:10 %包括agent标号，索引以及初始联盟结构
%     Value_data(i).agentID=agents(i).id;
%     Value_data(i).agentIndex=i;
%     Value_data(i).iteration=0;%联盟改变次数
%     Value_data(i).unif=0;%均匀随机变量
%     Value_data(i).coalitionstru=zeros(Value_Params.M+1,Value_Params.N);
     Value_data(i).initbelief=zeros(6,3);
   end

   for i=1:10 %每一个agent对所有任务的任务值持有一个初始belief
    for j=1:5
        Value_data(i).initbelief(j,1:end)=drchrnd([1,1,1],1)';
    end
   end

    for i=1:10
    for j=1:5
        Value_data(i).initbelief(j,1:end)=drchrnd([1+Value_data(i).observe(j,1),1+Value_data(k).observe(j,2),1+Value_data(k).observe(j,3)],1)';
    end
    end
    mmm=mmm+1;
end
   