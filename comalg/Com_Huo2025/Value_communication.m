function Value_data=Value_communication(agents, tasks, Value_data, Value_Params,Graph)

for k=1:Value_Params.N
    for n=1:Value_Params.N
       if Graph(k,n)==1
           if (Value_data(k).iteration>Value_data(n).iteration)...
             ||((Value_data(k).iteration==Value_data(n).iteration)&&(Value_data(k).unif>Value_data(n).unif))
%                if GAME_data(k).unif>GAME_data(n).unif
         Value_data(n).coalitionstru=Value_data(k).coalitionstru;
         Value_data(n).iteration=Value_data(k).iteration;
         Value_data(n).unif=Value_data(k).unif;
           end
       end
    end
end
             
end