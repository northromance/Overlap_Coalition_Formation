function fig=PlotValue(agents,tasks,C)

% 动态颜色数组
colors = {'k', 'r', 'm', 'y', 'c', 'g', 'b', [0.5 0.5 0.5], [0.8 0.4 0], [0.6 0.2 0.8]};

% 1. 先绘制任务（彩色五角星）
for i = 1:length(tasks)
    color_idx = mod(i-1, length(colors)) + 1;
    task_color = colors{color_idx};
    plot([tasks(i).x],[tasks(i).y],'p','MarkerSize',14,'MarkerFaceColor',task_color,'Color',task_color,'LineWidth',1.5)
    hold on
end

% 2. 绘制智能体（灰色圆圈）
plot([agents.x],[agents.y],'o','MarkerSize',10,'MarkerFaceColor',[0.9 0.9 0.9],'MarkerEdgeColor','k','LineWidth',1.5);
hold on

% 动态生成任务标签
max_text1 = cell(1, length(tasks));
for i = 1:length(tasks)
    max_text1{i} = sprintf('$t_{%d}$', i);
end
h1=text([tasks.x]+1.5,[tasks.y]+2.5,max_text1);
set(h1,'Interpreter','latex','FontName','Times New Roman','FontSize',12,'FontWeight','normal');
hold on

% 动态生成智能体标签
max_text = cell(1, length(agents));
for i = 1:length(agents)
    max_text{i} = sprintf('$r_{%d}$', i);
end
h2=text([agents.x]+1.50,[agents.y]+2.5,max_text);
set(h2,'Interpreter','latex','FontName','Times New Roman','FontSize',12,'FontWeight','normal');

fig = gcf;  % 返回当前图形句柄
end