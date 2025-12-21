
scatter(1:50,init_netprofit,30,'filled','r')
hold on
scatter(1:50,sta_netprofit,30,'filled','b')
 
xlabel('Monte Carlo case ID ','Fontsize',14);
ylabel('Global utility','Fontsize',14);
% set(gca,'Linewidth',1.2); %设置坐标区的线宽
 legend('Fixed belief','Belief updating')
 hold off
