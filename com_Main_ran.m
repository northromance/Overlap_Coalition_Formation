clear;
clc;
close all;
%ttt=1:20;
SEED=24375;
rand('seed',SEED);%设置随机数，后面可能用得到

WORLD.XMIN=0;
WORLD.XMAX=100;
WORLD.YMIN=0;
WORLD.YMAX=100;
WORLD.ZMIN=0;
WORLD.ZMAX=0;%2维空间
WORLD.value=[300,500,1000];%任务值为离散型随机变量，在50-200取离散值

N=10;%agent数目
M=6;%任务数目


for j=1:M
    tasks(j).id=j;
% %     tasks(j).req=randint(1,1,[0,3]);
% %     tasks(j).req=round(rand(1,1))*(-1)+1;
%     tasks(j).req=randperm(3,1);%最小数量要求,[0,2]中取随机数
%     tasks(j).req=2;%最小数量要求,[0,2]中取随机数
%     tasks(j).lamuda=0.1;   %折现系数
    tasks(j).x=round(rand(1)*(WORLD.XMAX-WORLD.XMIN)+WORLD.XMIN);
    tasks(j).y=round(rand(1)*(WORLD.YMAX-WORLD.YMIN)+WORLD.YMIN);
%     tasks(j).z=rand(1)*(WORLD.ZMAX-WORLD.ZMIN)+WORLD.ZMIN;
    tasks(j).value=WORLD.value(randi(length(WORLD.value),1,1)); %随机选择一个UAV进行更新;%randi是matlab中能产生均匀分布的伪随机整数的新函数
    tasks(j).WORLD.value=[300,500,1000];%任务值为离散型随机变量，在50-200取离散值
end

for i=1:N
    agents(i).id=i;
    agents(i).vel=2;%巡航速度，用于判断后面任务奖励折现
    agents(i).fuel=1;%油耗/m
    agents(i).x=round(rand(1)*(WORLD.XMAX-WORLD.XMIN)+WORLD.XMIN);
    agents(i).y=round(rand(1)*(WORLD.YMAX-WORLD.YMIN)+WORLD.YMIN);
   % agents(i).detprob=0.9+randn(1);
end
for i=1:N
    agents(i).detprob=1;
end

Value_Params=Value_init(N,M);


[p,result]=Value_graph(agents,Value_Params);
S=result(1,:);
E=result(2,:);
G=zeros(N);
for j=1:size(result,2)
G(result(1,j),result(2,j))=1;
end
Graph=G+G';


for time=1:50
[Value_data,Rcost,cost_sum,net_profit, initial_coalition]=Value_main(agents,tasks,Graph);
X1(time)=net_profit(end);
time
end



for count=1:50
coalition_structure=zeros(M,N);
    for i=1:N
        agents(i).position=randi(6,1,1);
         coalition_structure(agents(i).position,i)=agents(i).id
    end
       
     ran_Rcost=zeros(M,N);
     for j=1:Value_Params.M  %计算随机分配下每个任务的联盟成员
     ran_lianmeng(j).member=find(coalition_structure(j,:)~=0);
     for i=1:length( ran_lianmeng(j).member)
        ran_Rcost(j,i)=sqrt((agents(ran_lianmeng(j).member(i)).x-tasks(j).x)^2 ...
                 +(agents(ran_lianmeng(j).member(i)).y-tasks(j).y)^2)*agents(ran_lianmeng(j).member(i)).fuel;
     end
     end

    ran_cost_sum(count)=0;
 for j=1:size(ran_Rcost,1)
    for i=1:size(ran_Rcost,2)
      ran_cost_sum(count)=ran_cost_sum(count)+ran_Rcost(j,i);
     
    end
 end
 
 ran_revenue_sum(count)=0;
 
for j=1:Value_Params.M
    if  length(find(coalition_structure(j,:)~=0))
  ran_revenue_sum(count)=ran_revenue_sum(count)+tasks(j).value;
 
    end
end

ran_net_profit(count)= ran_revenue_sum(count)- ran_cost_sum(count);

count

end
for near_count=1:50
  near_coalition_structure=zeros(M,N);  
  for i=1:N
      for j=1:M
          near_Rcost(j,i)=sqrt((agents(i).x-tasks(j).x)^2 ...
                  +(agents(i).y-tasks(j).y)^2)*agents(i).fuel;
      end
     [near_value(i),near_taskindex(i)]=min(near_Rcost(:,i));%找到对应最大效用值的任务索引
     near_coalition_structure(near_taskindex(i),i)=agents(i).id
  end
  
     near_Rcost=zeros(M,N);
     for j=1:Value_Params.M  %计算随机分配下每个任务的联盟成员
     near_lianmeng(j).member=find(near_coalition_structure(j,:)~=0);
     for i=1:length( near_lianmeng(j).member)
        near_Rcost(j,i)=sqrt((agents(near_lianmeng(j).member(i)).x-tasks(j).x)^2 ...
                 +(agents(near_lianmeng(j).member(i)).y-tasks(j).y)^2)*agents(near_lianmeng(j).member(i)).fuel;
     end
     end

      near_cost_sum(near_count)=0;
 for j=1:size(near_Rcost,1)
    for i=1:size(near_Rcost,2)
      near_cost_sum(near_count)=near_cost_sum(near_count)+near_Rcost(j,i);
     
    end
 end
 
 
 near_revenue_sum(near_count)=0;
 
for j=1:Value_Params.M
    if  length(find(near_coalition_structure(j,:)~=0))
    near_revenue_sum(near_count)=near_revenue_sum(near_count)+tasks(j).value;
    end
end
near_net_profit((near_count))= near_revenue_sum(near_count)- near_cost_sum(near_count);
end

% figure()
% plot(1:50,X1,'*-')
% xlabel('Number of iterations ','FontSize', 14)
% ylabel('Global utility ','FontSize', 14)
% set(gca, 'FontSize', 12)