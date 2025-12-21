function fig=VlineAssignments(agents,tasks,G)

max_text1={'$t_1$','$t_2$','$t_3$','$t_4$','$t_5$','$t_6$'};

% line([tasks.x],[tasks.y]);
% plot(tasks.x(1),tasks.y(1),'d','MarkerSize',10)

plot([tasks(1).x],[tasks(1).y],'p','MarkerSize',10,'MarkerFaceColor','k','Color','k')
hold on
plot([tasks(2).x],[tasks(2).y],'p','MarkerSize',10,'MarkerFaceColor','r','Color','r')
hold on
plot([tasks(3).x],[tasks(3).y],'p','MarkerSize',10,'MarkerFaceColor','m','Color','m')
hold on
plot([tasks(4).x],[tasks(4).y],'p','MarkerSize',10,'MarkerFaceColor','y')
hold on
plot([tasks(5).x],[tasks(5).y],'p','MarkerSize',10,'MarkerFaceColor','c','Color','c')
hold on
plot([tasks(6).x],[tasks(6).y],'p','MarkerSize',10,'MarkerFaceColor','g','Color','g')
hold on
h1=text([tasks.x]+1.5,[tasks.y]+2.5,max_text1)%text()函数用来给图加上说明性文字text(x,y,'txt')
set(h1,'Interpreter','latex','FontName','Times New Roman','FontSize',12,'FontWeight','normal');
% axis([-15,15,-15,15])%axis主要是用来对坐标轴进行一定的缩放操作axis([xmin xmax ymin ymax])
hold on

max_text={'$r_1$','$r_2$','$r_3$','$r_4$','$r_5$'...
                  '$r_6$','$r_7$','$r_8$','$r_9$','$r_{10}$'};
% line([agents.x],[agents.y]);
plot([agents.x],[agents.y],'o','MarkerSize',8,'MarkerFaceColor',[139 139 122]/255)
h2=text([agents.x]+1.50,[agents.y]+2.5,max_text)
set(h2,'Interpreter','latex','FontName','Times New Roman','FontSize',12,'FontWeight','normal');

for i=1:length(G)
    for j=1:length(G)
        if G(i,j)~=0
            line([agents(i).x,agents(j).x],[agents(i).y,agents(j).y],'linestyle','--','color','b','LineWidth',1);
        end
    end
end
%    
%  line([agents(1).x,agents(2).x],[agents(1).y,agents(2).y]);


% hold off
% xlabel('Position in x (m)','FontSize',14)
% ylabel('Position in y (m)','FontSize',14)
%set(gca, 'FontSize', 12)

% title('联盟形成任务分配')
return