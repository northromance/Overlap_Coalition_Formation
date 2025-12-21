function [incremental,curnumberrow,Value_data]=SA_Value_order(agents, tasks, Value_data, Value_Params,counter)
%用于判断联盟结构是否改变的标志位
incremental=0;%%用于判断联盟结构是否改变的标志位
AValue_data.initcoalitionstru= Value_data.coalitionstru;%将联盟结构先存起来，后面涉及联盟结构调整
AValue_data.inititeration= Value_data.iteration;
AValue_data.initunif= Value_data.unif;

[curnumberrow,curnumbercolumn]=find(Value_data.coalitionstru== Value_data.agentID);% curnumber为agent当前任务索引
curnumberofcoworker =find(Value_data.coalitionstru(curnumberrow,:)~=0);% agent所在联盟的全部成员
curagentutility=Value_utility(agents, tasks,curnumberrow,curnumbercolumn, curnumberofcoworker,Value_data,Value_Params);%计算agent当前效用

%找到效用最大的任务索引
for j=1:Value_Params.M+1
    Value_data.coalitionstru= AValue_data.initcoalitionstru;  %保证每个任务的联盟结构一致
    Value_data.coalitionstru(curnumberrow,curnumbercolumn)=0;
    Value_data.coalitionstru(j,Value_data.agentID)=Value_data.agentID; 
    candidatenumberofcoworker =find(Value_data.coalitionstru(j,:)~=0);% 提取agent所在新任务联盟的全部成员
    
    
    candidateagentutility(j)=SA_altruistic_utility(agents, tasks, j, Value_data.agentID, candidatenumberofcoworker,Value_data,Value_Params);%调用utility函数
    Value_data.agentID;
end


[value,taskindex]=max(candidateagentutility);%找到对应最大效用值的任务索引
% [value,taskindex]=sort(candidateagentutility,'descend');%降序排列

if value==0
      Value_data.coalitionstru= AValue_data.initcoalitionstru;
      Value_data.coalitionstru(curnumberrow,curnumbercolumn)=0;
      Value_data.coalitionstru(Value_Params.M+1,curnumbercolumn)=Value_data.agentID;
else
    
    if  value>curagentutility
             incremental=1;
             value;
             Value_data.agentID;
             Value_data.iteration= Value_data.iteration+1;%联盟改变次数
             Value_data.unif=rand(1);%均匀随机变量
    end
end
    
    if incremental==0;
       Value_data.coalitionstru= AValue_data.initcoalitionstru;
    else
      Value_data.coalitionstru= AValue_data.initcoalitionstru;
      Value_data.coalitionstru(curnumberrow,curnumbercolumn)=0;
      Value_data.coalitionstru(taskindex,curnumbercolumn)=Value_data.agentID;
    end
    

end
