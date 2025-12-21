clear
load('C:\Users\UGV\Desktop\TASE修稿\TASE_仿真修改\仿真\data1.mat')
coalition_structure=zeros(M,N);
for  t_iteration=1:50
  for i=1:N
      for j=1:M
          near_Rcost(j,i)=sqrt((agents(i).x-tasks(j).x)^2 ...
                  +(agents(i).y-tasks(j).y)^2)*agents(i).fuel;
      end
     [near_value(i),near_taskindex(i)]=min(near_Rcost(:,i));%找到对应最大效用值的任务索引
     coalition_structure(near_taskindex(i),i)=agents(i).id
  end
  
  
% for i=1:N
%     for j=1:M
%      coalition_structure(agents(i).position,i)=agents(i).id;
%     end
% end

Rcost=zeros(M,N);

for j=1:M
     lianmeng(j).member=find(coalition_structure(j,:)~=0);
     for i=1:length(lianmeng(j).member)
        Rcost(j,i)=sqrt((agents(lianmeng(j).member(i)).x-tasks(j).x)^2 ...
                 +(agents(lianmeng(j).member(i)).y-tasks(j).y)^2)*agents(lianmeng(j).member(i)).fuel;
     end
end

cost_sum(t_iteration)=0;
for j=1:size(Rcost,1)
    for i=1:size(Rcost,2)
        cost_sum(t_iteration)=cost_sum(t_iteration)+Rcost(j,i);
    end
end

revenue_sum(t_iteration)=0;
for j=1:M
    if length(lianmeng(j).member)~=0
       revenue_sum(t_iteration)=revenue_sum(t_iteration)+tasks(j).value;
    end
end

net_profit(t_iteration)= revenue_sum(t_iteration)- cost_sum(t_iteration);
t_iteration=t_iteration+1;
end


% plot(1:2:50,X1(1,1:2:50),'r-o',1:2:50,near_net_profit(1,1:2:50),'b',1:2:50,ran_net_profit(1,1:2:50),'k-*','LineWidth',1)
% xlabel('Monte Carlo case ID ','Fontsize',14);
% ylabel('Global utility','Fontsize',14);
% legend('The proposed scheme','Near allocation' ,'Random allocation')
% getColor(3,1,10)
% grid on

