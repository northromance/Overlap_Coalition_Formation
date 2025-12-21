a1=sta_netprofit';
a2=init_netprofit';


edgecolor1=[0,0,0]; % black color
edgecolor2=[0,0,0]; % black color
% fillcolor1=[200, 211, 30]/255; % fillcolors = rand(24, 3);
% fillcolor2=[180, 68, 108]/255;
% fillcolors=[repmat(fillcolor1,5,1);repmat(fillcolor2,5,1)];

bh=boxplot([a1 a2],'colors',edgecolor1,'width',0.3,'notch','on','symbol','o','outliersize',5)
set(bh,'LineWidth',1.2)
set(gca,'XTickLabel',{'Belief updating', 'Fixed belief'},'Fontsize',10)
mycolor = [
    0.705882352941177,0.266666666666667,0.423529411764706;...
    0.949019607843137,0.650980392156863,0.121568627450980;...
    0.956862745098039,0.572549019607843,0.474509803921569;...
    0.231372549019608,0.490196078431373,0.717647058823529];



boxobj = findobj(gca,'Tag','Box');
for j=1:length(boxobj)
    patch(get(boxobj(j),'XData'),get(boxobj(j),'YData'),mycolor(j),'FaceAlpha',0.5)
end
set(gca, 'TickDir', 'in', 'TickLength', [.008 .008]);
% legend('Ultristic order', 'Selfish order')
%% 设置坐标区域的参数
xlabel('Belief settings','Fontsize',14);
ylabel('Global utility','Fontsize',14);
% title('单组别多色箱式图','Fontsize',10,'FontWeight','bold','FontName','楷体');
set(gca,'Linewidth',1.2); %设置坐标区的线宽
set(gca,'Fontsize',14); % 设置坐标区字体大小
% 对X轴刻度与显示范围调整
% set(gca,'Xlim',[0.5 5.5], 'Xtick', [0:1:5.5],'Xticklabel',X);
% % 对Y轴刻度与显示范围调整
% set(gca,'YTick', 2:0.5:7.5,'Ylim',[2 7.5]);
% 对刻度长度与刻度显示位置调整
set(gca, 'TickDir', 'in', 'TickLength', [.008 .008]);
% legend('Ultristic order', 'Selfish order')
