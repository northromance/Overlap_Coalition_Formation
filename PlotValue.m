function fig=PlotValue(agents,tasks,C,G)

%max_text1={'task1'};
% line([tasks.x],[tasks.y]);
% plot(tasks.x(1),tasks.y(1),'d','MarkerSize',10)

plot([tasks(1).x],[tasks(1).y],'p','MarkerSize',10,'MarkerFaceColor','k','Color','k')
hold on
plot([agents(C(1).member).x],[agents(C(1).member).y],'o','MarkerSize',8,'MarkerFaceColor','k')
hold on
plot([tasks(2).x],[tasks(2).y],'p','MarkerSize',10,'MarkerFaceColor','r','Color','r')
hold on
plot([agents(C(2).member).x],[agents(C(2).member).y],'o','MarkerSize',8,'MarkerFaceColor','r')
hold on
plot([tasks(3).x],[tasks(3).y],'p','MarkerSize',10,'MarkerFaceColor','m','Color','m')
hold on
plot([agents(C(3).member).x],[agents(C(3).member).y],'o','MarkerSize',8,'MarkerFaceColor','m')
hold on
plot([tasks(4).x],[tasks(4).y],'p','MarkerSize',10,'MarkerFaceColor','y')
hold on
plot([agents(C(4).member).x],[agents(C(4).member).y],'o','MarkerSize',8,'MarkerFaceColor','y')
hold on
plot([tasks(5).x],[tasks(5).y],'p','MarkerSize',10,'MarkerFaceColor','c','Color','c')
hold on
plot([agents(C(5).member).x],[agents(C(5).member).y],'o','MarkerSize',8,'MarkerFaceColor','c')
hold on
plot([tasks(6).x],[tasks(6).y],'p','MarkerSize',10,'MarkerFaceColor','g','Color','g')
hold on
plot([agents(C(6).member).x],[agents(C(6).member).y],'o','MarkerSize',8,'MarkerFaceColor','g')
max_text1={'$t_1$','$t_2$','$t_3$','$t_4$','$t_5$','$t_6$'};
h1=text([tasks.x]+1.5,[tasks.y]+2.5,max_text1)%text()函数用来给图加上说明性文字text(x,y,'txt')
set(h1,'Interpreter','latex','FontName','Times New Roman','FontSize',12,'FontWeight','normal');
hold on
max_text={'$r_1$','$r_2$','$r_3$','$r_4$','$r_5$'...
                  '$r_6$','$r_7$','$r_8$','$r_9$','$r_{10}$'};
              h2=text([agents.x]+1.50,[agents.y]+2.5,max_text)
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