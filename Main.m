

clear;
clc;
close all;
tic

%% 初始化参数
SEED=24375;
rand('seed',SEED);
addpath("SA\")

% 世界空间设置
WORLD.XMIN=0;
WORLD.XMAX=100;
WORLD.YMIN=0;
WORLD.YMAX=100;
WORLD.ZMIN=0;
WORLD.ZMAX=0;
WORLD.value=[300,500,1000]; % 任务价值集合

% 配置参数
N = 6; % agent数目
M = 4;  % 任务数目
K = 6; %总资源类型的数目

num_resources = 6; % 总资源类型数
num_task_types = 3; % 任务的类型数

max_resource_value = 8; % 最大资源值
min_resource_value = 0; % 最小资源值（允许为0）

task_type_demands_range = [0, 5]; % 任务资源需求的范围 [0,5]
task_type_duration = [100, 150, 200]; % 各类型任务的执行时间

AddPara.control = 1;

%% 初始化任务类型的资源需求
% 随机生成任务类型的资源需求
task_type_demands = randi(task_type_demands_range, num_task_types, num_resources);  % 3种任务类型，每种任务类型有6种资源需求（可以为0）

%% 初始化agents和tasks
% 初始化任务
% 为 M 个任务生成不重复的优先级（数值越小表示优先级越高）
task_priorities = randperm(M);
for j = 1:M
    tasks(j).id = j;
    tasks(j).priority = task_priorities(j);
    tasks(j).x = round(rand(1) * (WORLD.XMAX - WORLD.XMIN) + WORLD.XMIN);
    tasks(j).y = round(rand(1) * (WORLD.YMAX - WORLD.YMIN) + WORLD.YMIN);
    tasks(j).value = WORLD.value(randi(length(WORLD.value), 1, 1));
    tasks(j).type = randi(num_task_types, 1, 1);  % 任务类型：1, 2, 3（可以根据任务类型选择对应的资源需求）
    tasks(j).resource_demand = task_type_demands(tasks(j).type, :);  % 根据任务类型分配资源需求
    tasks(j).duration = task_type_duration(tasks(j).type);  % 根据任务类型分配执行时间
end

% 初始化agents
for i = 1:N
    agents(i).id = i;
    agents(i).vel = 2;   % 巡航速度
    agents(i).fuel = 1;  % 油耗/m
    agents(i).x = round(rand(1) * (WORLD.XMAX - WORLD.XMIN) + WORLD.XMIN);
    agents(i).y = round(rand(1) * (WORLD.YMAX - WORLD.YMIN) + WORLD.YMIN);
    agents(i).detprob = 1; % 检测概率
    agents(i).resources = randi([min_resource_value, max_resource_value], num_resources, 1);  % 每个agent有6种资源，数量在[min_resource_value, max_resource_value]之间（允许为0）
end



Value_Params=Value_init(N,M,K);
% 将任务类型的资源需求保存到参数结构中，供后续根据 belief 计算期望需求使用
Value_Params.task_type_demands = task_type_demands;

%% 生成连接图
[p, result] = Value_graph(agents, Value_Params);

S = result(1, :);
E = result(2, :);

% 构建邻接矩阵
G = zeros(N);
for j=1:size(result,2)
    G(result(1,j),result(2,j))=1;
end
Graph=G+G'; % 对称化

%% 运行联盟形成算法
[Value_data,Rcost,cost_sum,net_profit, initial_coalition]= SA_Value_main(agents,tasks,Graph,AddPara,Value_Params);

toc

%% 提取联盟成员
for j=1:Value_Params.M
    lianmengchengyuan(j).member=find(Value_data(1).coalitionstru(j,:)~=0);
end

%% 绘制联盟结构图
figure()
PlotValue(agents,tasks,lianmengchengyuan,G)
axis([0,100,0,100])
xlabel('x-axis (m)','FontName','Times New Roman','FontSize',14)
ylabel('y-axis (m)','FontName','Times New Roman','FontSize',14)
grid on

%% 计算期望任务收益
for i=1:N
    for j=1:M
        for k=1:50
            sumprob(i,j).value(k)=Value_data(i).tasks(j).prob(k,1)*300+Value_data(i).tasks(j).prob(k,2)*500+Value_data(i).tasks(j).prob(k,3)*1000;
        end
    end
end

%% 绘制期望收益演化曲线
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
