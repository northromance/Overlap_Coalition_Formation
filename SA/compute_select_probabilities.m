function probs = compute_select_probabilities(Value_data, agents, tasks, Value_Params)
% compute_select_probabilities: 计算当前 agent 针对所有任务的选择概率
% 简单占位实现：如果存在 compute_select_score.m 则调用之，
% 否则使用基于距离的负距离打分并 softmax 归一化。

M = Value_Params.M;
scores = zeros(1, M+1);
for j = 1:(M+1)
    try
        if exist('compute_select_score','file') == 2
            scores(j) = compute_select_score(j, agents, tasks, Value_data, Value_Params);
        else
            if j == M+1
                scores(j) = 0;
            else
                aidx = Value_data.agentIndex;
                dx = agents(aidx).x - tasks(j).x;
                dy = agents(aidx).y - tasks(j).y;
                scores(j) = -sqrt(dx*dx + dy*dy);
            end
        end
    catch
        scores(j) = 0;
    end
end

exp_s = exp(scores);
if sum(exp_s) == 0
    probs = ones(size(exp_s)) / numel(exp_s);
else
    probs = exp_s / sum(exp_s);
end

end
