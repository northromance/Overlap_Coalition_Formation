

clear;
% 注释
clc;
close all;
%for t_iteration=1:50
tic
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

%% 初始化agents和tasks
for j=1:M
    tasks(j).id=j;
    tasks(j).x=round(rand(1)*(WORLD.XMAX-WORLD.XMIN)+WORLD.XMIN);
    tasks(j).y=round(rand(1)*(WORLD.YMAX-WORLD.YMIN)+WORLD.YMIN);
    %     tasks(j).z=rand(1)*(WORLD.ZMAX-WORLD.ZMIN)+WORLD.ZMIN;
    tasks(j).value=WORLD.value(randi(length(WORLD.value),1,1));
    %随机选择一个UAV进行更新;%randi是matlab中能产生均匀分布的伪随机整数的新函数
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
    %agents(i).detprob=0.9+0.1*rand(1);
end

Value_Params=Value_init(N,M);

%% 生成一个连接图
% 生成一个最小生成树形成的矩阵
[p, result] = Value_graph(agents, Value_Params);


S = result(1, :);


E = result(2, :);


G = zeros(N);

for j=1:size(result,2)
    G(result(1,j),result(2,j))=1;
end
Graph=G+G';


[Value_data,Rcost,cost_sum,net_profit, initial_coalition]=SA_Value_main(agents,tasks,Graph);

toc

%% 联盟成员

% 联盟成员
for j=1:Value_Params.M
    lianmengchengyuan(j).member=find(Value_data(1).coalitionstru(j,:)~=0);
end

%% 绘图
figure()
PlotValue(agents,tasks,lianmengchengyuan,G)
axis([0,100,0,100])
% hold on
% initialValue2(TUAVs(RUAV_data(2).accept),RUAVs(2))
% hold on
% initialValue3(TUAVs(RUAV_data(3).accept),RUAVs(3))
xlabel('x-axis (m)','FontName','Times New Roman','FontSize',14)
ylabel('y-axis (m)','FontName','Times New Roman','FontSize',14)
%set(gca, 'FontSize', 12)
grid on

% figure()
% PlotValue(agents,tasks,lianmengchengyuan)
% xlabel('Position in x(m) ','FontSize', 14)
% ylabel('Position in y(m) ','FontSize', 14)
% grid on


%% 绘制分布图
% figure()
% VlineAssignments(agents,tasks,G)
% xlabel('x-axis (m)','FontName','Times New Roman','FontSize',14)
% ylabel('y-axis (m)','FontName','Times New Roman','FontSize',14)
% %set(gca, 'FontSize', 12)
% grid on
% axis([0,100,0,100])



% 计算最终形成的价值
for i=1:N %精确监测能力
    for j=1:M
        for k=1:50
            sumprob(i,j).value(k)=Value_data(i).tasks(j).prob(k,1)*300+Value_data(i).tasks(j).prob(k,2)*500+Value_data(i).tasks(j).prob(k,3)*1000;
        end
    end
end


time=1:4:50;
for j=1:M
    figure()
    plot(time,sumprob(1,j).value(1:4:50),'-+',time,sumprob(2,j).value(1:4:50),'-o',time,sumprob(3,j).value(1:4:50),'-x',time,sumprob(4,j).value(1:4:50),'-*',time,sumprob(5,j).value(1:4:50),'-v'...
        ,time,sumprob(6,j).value(1:4:50),'-^',time,sumprob(7,j).value(1:4:50),'-s',time,sumprob(8,j).value(1:4:50),'-d',time,sumprob(9,j).value(1:4:50),'-p',time,sumprob(10,j).value(1:4:50),'-h')
    h=legend('$r_1$','$r_2$','$r_3$','$r_4$','$r_5$','$r_6$','$r_7$','$r_8$','$r_9$','$r_{10}$');
    set(h,'Interpreter','latex','FontName','Times New Roman','FontSize',12,'FontWeight','normal');
    xlabel('Index of game','FontName','Times New Roman','FontSize',14);
    ylabel('Expected task revenue','FontName','Times New Roman','FontSize',14);
    grid on
end
% figure()
% plot(1:20,net_profit,'o-')
% xlabel('Number of iterations ','FontSize', 14)
% ylabel('Global utility ','FontSize', 14)
% set(gca, 'FontSize', 12)
% grid on
