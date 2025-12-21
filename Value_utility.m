function agentutility=Value_utility(agents, tasks, numberrow, numbercolumn, numberofcoworker,Value_data,Value_Params)
 
if (numberrow==Value_Params.M+1)%如果当前不在空任务集中

         revenue=0;
else
%revenue=tasks(numberrow).value;
 revenue=tasks(numberrow).WORLD.value(1)*Value_data.initbelief(numberrow,1)...
             +tasks(numberrow).WORLD.value(2)*Value_data.initbelief(numberrow,2)...
             +tasks(numberrow).WORLD.value(3)*Value_data.initbelief(numberrow,3);
        
end

individualrevenue=revenue/length(numberofcoworker);

%任务代价
if (numberrow==Value_Params.M+1)
    cost=0;
else
cost=sqrt((agents(numbercolumn).x-tasks(numberrow).x)^2 ...
    +(agents(numbercolumn).y-tasks(numberrow).y)^2)*agents(numbercolumn).fuel;

numbercolumn;
numberrow;
% cost=0;
end

if (individualrevenue-cost)>0
    agentutility=individualrevenue-cost;
else
     agentutility=0;
end

end
