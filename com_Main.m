clear;
clc;
close all;
% for iteration=1
%     iteration
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
    tasks(j).x=round(rand(1)*(WORLD.XMAX-WORLD.XMIN)+WORLD.XMIN);
    tasks(j).y=round(rand(1)*(WORLD.YMAX-WORLD.YMIN)+WORLD.YMIN);
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
 for iteration=1:50
[Value_data,Rcost,cost_sum,net_profit, initial_coalition]=Value_main(agents,tasks,Graph);
sta_netprofit(iteration)=net_profit(end);
init_netprofit(iteration)=net_profit(1);
iteration
 end

for j=1:Value_Params.M
    lianmengchengyuan(j).member=find(Value_data(1).coalitionstru(j,:)~=0);
end
%
 
figure()
PlotValue(agents,tasks,lianmengchengyuan)
xlabel('Position in x(m) ','FontSize', 14)
ylabel('Position in y(m) ','FontSize', 14)
grid on

figure()
VlineAssignments(agents,tasks,G)
xlabel('Position in x(m) ','FontSize', 14)
ylabel('Position in y(m) ','FontSize', 14)
grid on
axis([0,100,0,100])




for i=1:N
    for j=1:20
    sumprob1(i,j)=Value_data(i).prob1(j,1)*300+Value_data(i).prob1(j,2)*500+Value_data(i).prob1(j,3)*1000;
    sumprob2(i,j)=Value_data(i).prob2(j,1)*300+Value_data(i).prob2(j,2)*500+Value_data(i).prob2(j,3)*1000;
    sumprob3(i,j)=Value_data(i).prob3(j,1)*300+Value_data(i).prob3(j,2)*500+Value_data(i).prob3(j,3)*1000;
    sumprob4(i,j)=Value_data(i).prob4(j,1)*300+Value_data(i).prob4(j,2)*500+Value_data(i).prob4(j,3)*1000;
    sumprob5(i,j)=Value_data(i).prob5(j,1)*300+Value_data(i).prob5(j,2)*500+Value_data(i).prob5(j,3)*1000;
    sumprob6(i,j)=Value_data(i).prob6(j,1)*300+Value_data(i).prob6(j,2)*500+Value_data(i).prob6(j,3)*1000;
    end
end
figure()
plot(1:20,sumprob1(1,1:20),'-.',1:20,sumprob1(2,1:20),'-o',1:20,sumprob1(3,1:20),'-d',1:20,sumprob1(4,1:20),'-x',1:20,sumprob1(5,1:20),'-+'...
    ,1:20,sumprob1(6,1:20),'-p',1:20,sumprob1(7,1:20),'-h',1:20,sumprob1(8,1:20),'-s',1:20,sumprob1(9,1:20),'-*',1:20,sumprob1(10,1:20),'--')
legend('Agent 1','Agent 2','Agent 3','Agent 4','Agent 5','Agent 6','Agent 7','Agent 8','Agent 9','Agent 10')
xlabel('Number of iterations ','FontSize', 14)
ylabel('Expected value of task 1 ','FontSize', 14)
set(gca, 'FontSize', 12)

figure()
plot(1:20,sumprob2(1,1:20),'-.',1:20,sumprob2(2,1:20),'-o',1:20,sumprob2(3,1:20),'-d',1:20,sumprob2(4,1:20),'-x',1:20,sumprob2(5,1:20),'-+'...
       ,1:20,sumprob2(6,1:20),'-p',1:20,sumprob2(7,1:20),'-h',1:20,sumprob2(8,1:20),'-s',1:20,sumprob2(9,1:20),'-*',1:20,sumprob2(10,1:20),'--')
legend('Agent 1','Agent 2','Agent 3','Agent 4','Agent 5','Agent 6','Agent 7','Agent 8','Agent 9','Agent 10')
xlabel('Number of iterations ','FontSize', 14)
ylabel('Expected value of task 2 ','FontSize', 14)
set(gca, 'FontSize', 12)

figure()
plot(1:20,sumprob3(1,1:20),'-.',1:20,sumprob3(2,1:20),'-o',1:20,sumprob3(3,1:20),'-d',1:20,sumprob3(4,1:20),'-x',1:20,sumprob3(5,1:20),'-+'...
    ,1:20,sumprob3(6,1:20),'-p',1:20,sumprob3(7,1:20),'-h',1:20,sumprob3(8,1:20),'-s',1:20,sumprob3(9,1:20),'-*',1:20,sumprob3(10,1:20),'--')
legend('Agent 1','Agent 2','Agent 3','Agent 4','Agent 5','Agent 6','Agent 7','Agent 8','Agent 9','Agent 10')
xlabel('Number of iterations ','FontSize', 14)
ylabel('Expected value of task 3 ','FontSize', 14)
set(gca, 'FontSize', 12)

figure()
plot(1:20,sumprob4(1,1:20),'-.',1:20,sumprob4(2,1:20),'-o',1:20,sumprob4(3,1:20),'-d',1:20,sumprob4(4,1:20),'-x',1:20,sumprob4(5,1:20),'-+'...
      ,1:20,sumprob4(6,1:20),'-p',1:20,sumprob4(7,1:20),'-h',1:20,sumprob4(8,1:20),'-s',1:20,sumprob4(9,1:20),'-*',1:20,sumprob4(10,1:20),'--')
legend('Agent 1','Agent 2','Agent 3','Agent 4','Agent 5','Agent 6','Agent 7','Agent 8','Agent 9','Agent 10')
xlabel('Number of iterations ','FontSize', 14)
ylabel('Expected value of task 4','FontSize', 14)
set(gca, 'FontSize', 12)

figure()
plot(1:20,sumprob5(1,1:20),'-.',1:20,sumprob5(2,1:20),'-o',1:20,sumprob5(3,1:20),'-d',1:20,sumprob5(4,1:20),'-x',1:20,sumprob5(5,1:20),'-+'...
       ,1:20,sumprob5(6,1:20),'-p',1:20,sumprob5(7,1:20),'-h',1:20,sumprob5(8,1:20),'-s',1:20,sumprob5(9,1:20),'-*',1:20,sumprob5(10,1:20),'--')
legend('Agent 1','Agent 2','Agent 3','Agent 4','Agent 5','Agent 6','Agent 7','Agent 8','Agent 9','Agent 10')
xlabel('Number of iterations ','FontSize', 14)
ylabel('Expected value of task 5 ','FontSize', 14)
set(gca, 'FontSize', 12)

figure()
plot(1:20,sumprob6(1,1:20),'-.',1:20,sumprob6(2,1:20),'-o',1:20,sumprob6(3,1:20),'-d',1:20,sumprob6(4,1:20),'-x',1:20,sumprob6(5,1:20),'-+'...
       ,1:20,sumprob6(6,1:20),'-p',1:20,sumprob6(7,1:20),'-h',1:20,sumprob6(8,1:20),'-s',1:20,sumprob6(9,1:20),'-*',1:20,sumprob6(10,1:20),'--')
legend('Agent 1','Agent 2','Agent 3','Agent 4','Agent 5','Agent 6','Agent 7','Agent 8','Agent 9','Agent 10')
xlabel('Number of iterations ','FontSize', 14)
ylabel('Expected value of task 6 ','FontSize', 14)
set(gca, 'FontSize', 12)


for i=1:N
    for j=1:50
    sumprob1(i,j)=Value_data(i).prob1(j,1)*300+Value_data(i).prob1(j,2)*500+Value_data(i).prob1(j,3)*1000;
    sumprob2(i,j)=Value_data(i).prob2(j,1)*300+Value_data(i).prob2(j,2)*500+Value_data(i).prob2(j,3)*1000;
    sumprob3(i,j)=Value_data(i).prob3(j,1)*300+Value_data(i).prob3(j,2)*500+Value_data(i).prob3(j,3)*1000;
    sumprob4(i,j)=Value_data(i).prob4(j,1)*300+Value_data(i).prob4(j,2)*500+Value_data(i).prob4(j,3)*1000;
    sumprob5(i,j)=Value_data(i).prob5(j,1)*300+Value_data(i).prob5(j,2)*500+Value_data(i).prob5(j,3)*1000;
    sumprob6(i,j)=Value_data(i).prob6(j,1)*300+Value_data(i).prob6(j,2)*500+Value_data(i).prob6(j,3)*1000;
    end
end
time=1:4:50;
figure()
plot(time,sumprob1(1,1:4:50),'-.',time,sumprob1(2,1:4:50),'-o',time,sumprob1(3,1:4:50),'-d',time,sumprob1(4,1:4:50),'-x',time,sumprob1(5,1:4:50),'-+'...
    ,time,sumprob1(6,1:4:50),'-p',time,sumprob1(7,1:4:50),'-h',time,sumprob1(8,1:4:50),'-s',time,sumprob1(9,1:4:50),'-*',time,sumprob1(10,1:4:50),'--')
legend('Agent 1','Agent 2','Agent 3','Agent 4','Agent 5','Agent 6','Agent 7','Agent 8','Agent 9','Agent 10')
xlabel('Number of iterations ','FontSize', 14)
ylabel('Expected value of task 1 ','FontSize', 14)
set(gca, 'FontSize', 12)



figure()
plot(time,sumprob2(1,1:4:50),'-.',time,sumprob2(2,1:4:50),'-o',time,sumprob2(3,1:4:50),'-d',time,sumprob2(4,1:4:50),'-x',time,sumprob2(5,1:4:50),'-+'...
    ,time,sumprob2(6,1:4:50),'-p',time,sumprob2(7,1:4:50),'-h',time,sumprob2(8,1:4:50),'-s',time,sumprob2(9,1:4:50),'-*',time,sumprob2(10,1:4:50),'--')
legend('Agent 1','Agent 2','Agent 3','Agent 4','Agent 5','Agent 6','Agent 7','Agent 8','Agent 9','Agent 10')
xlabel('Number of iterations ','FontSize', 14)
ylabel('Expected value of task 2 ','FontSize', 14)
set(gca, 'FontSize', 12)

figure()
plot(time,sumprob3(1,1:4:50),'-.',time,sumprob3(2,1:4:50),'-o',time,sumprob3(3,1:4:50),'-d',time,sumprob3(4,1:4:50),'-x',time,sumprob3(5,1:4:50),'-+'...
    ,time,sumprob3(6,1:4:50),'-p',time,sumprob3(7,1:4:50),'-h',time,sumprob3(8,1:4:50),'-s',time,sumprob3(9,1:4:50),'-*',time,sumprob3(10,1:4:50),'--')
legend('Agent 1','Agent 2','Agent 3','Agent 4','Agent 5','Agent 6','Agent 7','Agent 8','Agent 9','Agent 10')
xlabel('Number of iterations ','FontSize', 14)
ylabel('Expected value of task 3 ','FontSize', 14)
set(gca, 'FontSize', 12)

figure()
plot(time,sumprob4(1,1:4:50),'-.',time,sumprob4(2,1:4:50),'-o',time,sumprob4(3,1:4:50),'-d',time,sumprob4(4,1:4:50),'-x',time,sumprob4(5,1:4:50),'-+'...
    ,time,sumprob4(6,1:4:50),'-p',time,sumprob4(7,1:4:50),'-h',time,sumprob4(8,1:4:50),'-s',time,sumprob4(9,1:4:50),'-*',time,sumprob4(10,1:4:50),'--')
legend('Agent 1','Agent 2','Agent 3','Agent 4','Agent 5','Agent 6','Agent 7','Agent 8','Agent 9','Agent 10')
xlabel('Number of iterations ','FontSize', 14)
ylabel('Expected value of task 4','FontSize', 14)
set(gca, 'FontSize', 12)

figure()
plot(time,sumprob5(1,1:4:50),'-.',time,sumprob5(2,1:4:50),'-o',time,sumprob5(3,1:4:50),'-d',time,sumprob5(4,1:4:50),'-x',time,sumprob5(5,1:4:50),'-+'...
    ,time,sumprob5(6,1:4:50),'-p',time,sumprob5(7,1:4:50),'-h',time,sumprob5(8,1:4:50),'-s',time,sumprob5(9,1:4:50),'-*',time,sumprob5(10,1:4:50),'--')
legend('Agent 1','Agent 2','Agent 3','Agent 4','Agent 5','Agent 6','Agent 7','Agent 8','Agent 9','Agent 10')
xlabel('Number of iterations ','FontSize', 14)
ylabel('Expected value of task 5 ','FontSize', 14)
set(gca, 'FontSize', 12)

figure()
plot(time,sumprob6(1,1:4:50),'-.',time,sumprob6(2,1:4:50),'-o',time,sumprob6(3,1:4:50),'-d',time,sumprob6(4,1:4:50),'-x',time,sumprob6(5,1:4:50),'-+'...
    ,time,sumprob6(6,1:4:50),'-p',time,sumprob6(7,1:4:50),'-h',time,sumprob6(8,1:4:50),'-s',time,sumprob6(9,1:4:50),'-*',time,sumprob6(10,1:4:50),'--')
legend('Agent 1','Agent 2','Agent 3','Agent 4','Agent 5','Agent 6','Agent 7','Agent 8','Agent 9','Agent 10')
xlabel('Number of iterations ','FontSize', 14)
ylabel('Expected value of task 6 ','FontSize', 14)
set(gca, 'FontSize', 12)

% figure()
% plot(1:20,net_profit,'*-')
% xlabel('Number of iterations ','FontSize', 14)
% ylabel('Global utility ','FontSize', 14)
% set(gca, 'FontSize', 12)