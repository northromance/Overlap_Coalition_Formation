function agentutility = Value_utility(agents, tasks, numberrow, numbercolumn, numberofcoworker, Value_data, Value_Params, SC, R_agent)
% VALUE_UTILITY 計算智能體在特定資源分配狀態下的預期淨效用
%
% 核心邏輯：
%   Utility = max(0, Revenue - Cost)
%   1. Revenue (收益): 取決於資源貢獻比、任務期望價值、任務完成度。
%   2. Cost (成本): 調用全局同步機制，計算考慮了路徑依賴和等待時間的總能耗。
%
% 輸入：
%   SC, R_agent : 提議狀態下的聯盟結構與資源分配矩陣（通常為 SC_Q, R_agent_Q）

    %% 0. 初始化參數
    tol = 1e-9;
    
    % --- 1. 特殊情況：虛任務 (Void Task) ---
    % 虛任務代表閒置狀態，無效用產生，直接返回 0
    if (numberrow == Value_Params.M + 1)
        agentutility = 0;
        return;
    end

    %% 1. 準備基礎數據
    K = Value_Params.K;
    demand = tasks(numberrow).resource_demand(:)'; % 獲取當前任務需求向量
    agent_id = numbercolumn;                       % 根據上下文，此處列索引即為智能體 ID

    % --- 2. 解析參與者 (Participants Parsing) ---
    % 注意：優先從傳入的提議狀態 SC 中解析，確保計算的是"假設移動後"的情況
    % numberofcoworker 僅作為輔助參考，SC{numberrow} 才是真實數據源
    
    participants = OCFUtils.get_participants(SC, numberrow, tol);
    SC_task = SC{numberrow}; % 獲取該任務的資源分配矩陣 (N x K)
    
    % 防衛性檢查：確保解析出的成員在矩陣範圍內
    valid_members = participants(participants <= size(SC_task, 1));
    if isempty(valid_members)
        agentutility = 0;
        return;
    end

    %% 2. 計算收益 (Revenue Calculation)
    % 公式：Revenue = 完成度(D_C) * 期望價值(V_C) * 貢獻比例(r_n)
    
    % A. 計算任務完成度 (Completion Degree, D_C)
    % 匯總所有成員投入的資源，對比需求計算滿足率
    total_resources = sum(SC_task(valid_members, :), 1);
    D_C = OCFUtils.calc_task_completion_degree(total_resources, demand, K);
    
    if D_C <= tol
        agentutility = 0; % 若無法完成任何需求，收益為 0
        return;
    end

    % B. 計算資源貢獻比例 (Contribution Ratio, r_n_C)
    % 確保 agent_row_idx 有效，計算當前智能體投入資源佔總投入的比例
    agent_row_idx = agent_id;
    if agent_row_idx < 1 || agent_row_idx > size(SC_task, 1)
        agent_row_idx = valid_members(1); % 異常回退
    end
    r_n_C = OCFUtils.calc_resource_contribution_ratio(SC_task, agent_row_idx, valid_members);

    % C. 計算期望價值 (Expected Value, V_C)
    % 結合貝葉斯信念 (initbelief) 與真實價值表，計算加權期望值
    task_types = Value_Params.task_type;
    if isempty(task_types)
        task_types = numel(tasks(numberrow).WORLD.value);
    end
    
    values = tasks(numberrow).WORLD.value;
    tlen = min([task_types, numel(values), size(Value_data.initbelief, 2)]);
    % 點乘求和：Sum(P(Type) * Value(Type))
    V_C = sum(values(1:tlen) .* Value_data.initbelief(numberrow, 1:tlen));

    % D. 總收益
    revenue = r_n_C * V_C * D_C;

    %% 3. 計算成本 (Cost Calculation - Global Sync)
    % 公式：Cost = 飛行能耗 + 等待能耗 + 執行能耗
    % 關鍵：必須基於智能體的完整任務序列進行路徑規劃
    
    % 提取能耗係數
    alpha_fly = agents(agent_id).fuel;
    alpha_wait = agents(agent_id).wait_fuel;
    beta = agents(agent_id).beta;

    % A. 構建任務序列
    % 從資源矩陣 R_agent 中找出該智能體參與的所有任務
    myOrderedTasks = find(any(R_agent > tol, 2))';
    
    % 確保當前評估的任務 (numberrow) 包含在序列中 (處理剛剛加入尚未寫入 R_agent 的情況)
    if isempty(myOrderedTasks)
        myOrderedTasks = numberrow;
    elseif ~ismember(numberrow, myOrderedTasks)
        myOrderedTasks = [numberrow, myOrderedTasks];
    end
    
    % B. 全局同步計算
    % 調用物理引擎，模擬移動、同步等待和執行過程
    % 注意：這裡 myOrderedTasks 會在內部根據優先級重新排序
    [t_fly_total, t_wait_total, t_exec_total] = calc_with_global_sync( ...
        agent_id, myOrderedTasks, agents, tasks, Value_Params, SC, R_agent, tol);

    % C. 總成本
    cost = t_fly_total * alpha_fly + t_wait_total * alpha_wait + t_exec_total * beta;

    %% 4. 計算淨效用 (Net Utility)
    % 如果成本高於收益，則效用歸零（理性代理不執行虧本任務）
    if revenue > cost
        agentutility = revenue - cost;
    else
        agentutility = 0;
    end
end