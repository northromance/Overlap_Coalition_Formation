function initial=initialValue(agents,tasks)

max_text1={'task1','task2','task3','task4','task5','task6'};
% line([tasks.x],[tasks.y]);
% plot(tasks.x(1),tasks.y(1),'d','MarkerSize',10)

plot([tasks.x],[tasks.y],'p','MarkerSize',10,'MarkerFaceColor','k')%'d'是菱形，'s'是正方形
text([tasks.x]-0.3,[tasks.y]+1,max_text1)%text()函数用来给图加上说明性文字text(x,y,'txt')
% axis([-15,15,-15,15])%axis主要是用来对坐标轴进行一定的缩放操作axis([xmin xmax ymin ymax])
hold on

max_text={'robot1','robot2','robot3','robot4','robot5'...
                  'robot6','robot7','robot8','robot9','robot10'};
% line([agents.x],[agents.y]);
plot([agents.x],[agents.y],'o','MarkerSize',10,'MarkerFaceColor','g')
text([agents.x]-0.8,[agents.y]+1,max_text)

hold off
xlabel('Position in x (m)','FontSize',14)
ylabel('Position in y (m)','FontSize',14)
set(gca, 'FontSize', 12)

% title('联盟形成任务分配')
return