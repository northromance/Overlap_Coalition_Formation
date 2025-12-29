function fig=PlotValue(agents,tasks,C,G)

% 动态颜色数组
colors = {'k', 'r', 'm', 'y', 'c', 'g', 'b', [0.5 0.5 0.5], [0.8 0.4 0], [0.6 0.2 0.8]};

% 绘制任务和对应的联盟成员
for i = 1:length(tasks)
    color_idx = mod(i-1, length(colors)) + 1;
    if isnumeric(colors{color_idx})
        plot([tasks(i).x],[tasks(i).y],'p','MarkerSize',10,'MarkerFaceColor',colors{color_idx},'Color',colors{color_idx})
    else
        plot([tasks(i).x],[tasks(i).y],'p','MarkerSize',10,'MarkerFaceColor',colors{color_idx},'Color',colors{color_idx})
    end
    hold on
    if ~isempty(C(i).member)
        if isnumeric(colors{color_idx})
            plot([agents(C(i).member).x],[agents(C(i).member).y],'o','MarkerSize',8,'MarkerFaceColor',colors{color_idx})
        else
            plot([agents(C(i).member).x],[agents(C(i).member).y],'o','MarkerSize',8,'MarkerFaceColor',colors{color_idx})
        end
        hold on
    end
end

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
% hold on
% for i=1:length(G)
%     for j=1:length(G)
%         if G(i,j)~=0
%             line([agents(i).x,agents(j).x],[agents(i).y,agents(j).y],'color','b','LineWidth',1.2);
%         end
%     end
% end
return