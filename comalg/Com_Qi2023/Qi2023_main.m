function [Value_data, history_data] = Qi2023_main(agents, tasks, AddPara, Value_Params)
% Qi2023_main - 实现偏好引力引导的禁忌搜索算法 (PGG-TS)
% 
% 参考文献: Qi et al. 2023 (TII or similar venue)
%
% 算法流程概览:
%   1. 初始化: 利用引力场生成高质量初始解 (而非完全随机)
%   2. 主循环:
%      a. 离开 (Leave): 随机释放部分资源，制造扰动
%      b. 引力计算 (Gravity): 基于剩余需求和距离计算吸引力
%      c. 交换 (Exchange): 基于 Boltzmann 概率选择新任务
%      d. 禁忌检查 (Tabu): 防止搜索陷入循环
%      e. 效用评估 (Utility): 贪婪策略接受更优解
%      f. 降温 (Cooling): 降低随机性，从探索转向利用
%
% 输入:
%   agents       - 智能体结构体数组 (包含位置、资源等)
%   tasks        - 任务结构体数组 (包含位置、需求、价值等)
%   AddPara      - (预留) 附加参数
%   Value_Params - 全局算法参数 (迭代次数、种群大小等)
%
% 输出:
%   Value_data    - 最终的智能体状态和分配方案
%   history_data  - 迭代过程中的历史数据(用于绘图)

%% 0. 参数设置与初始化
% 设置随机种子以保证结果可复现
if isfield(Value_Params, 'seed')
    rng(Value_Params.seed);
end

% 基础参数
eps_val = 1e-9;         % 浮点数比较的误差容限
N = Value_Params.N;     % 智能体数量 (Agents)
M = Value_Params.M;     % 任务数量 (Tasks)
K = Value_Params.K;     % 资源类型数量 (Resource Types)

% --- PGG-TS 核心算法参数 ---
% L_tabu: 禁忌表长度。记录最近访问过的解，禁止短时间内重复访问，防止死循环。
L_tabu = 10;                

% K_len: 稳定/收敛阈值。如果连续 K_len 代效用没有提升，则认为收敛，提前退出。
K_len = 20;                 

% K_max: 最大迭代次数。算法运行的硬性终止条件。
K_max = Value_Params.num_rounds; 

% TabuList: 禁忌表。使用 Cell 数组存储已访问状态的 Hash 值。
TabuList = {};              

% Gamma (Γ): Boltzmann 温度系数。
%   - 高温 (初期): 概率分布平缓，允许更多随机探索 (Exploration)。
%   - 低温 (后期): 概率分布尖锐，倾向于选择引力最大的任务 (Exploitation)。
Gamma = 100;                

% alpha: 降温系数。每轮迭代后 Gamma = Gamma * alpha。
alpha = 0.98;               

% --- 数据结构初始化 ---
history_data = struct();
Value_data = init_value_data(agents, tasks, Value_Params);

% SC_global: 全局联盟结构 (Structure of Coalition)
% 存储格式: Cell数组 (M x 1)，每个 Cell 是一个 (N x K) 的矩阵。
% SC_global{m}(n, k) 表示第 n 个智能体在第 m 个任务上投入的第 k 种资源量。
SC_global = cell(M, 1);
for m = 1:M, SC_global{m} = zeros(N, K); end

k_iter = 1;     % 当前迭代计数器
k_stable = 0;   % 连续未改进计数器

% 初始化历史记录容器
history_data = struct('rounds', struct());

%% 1. 初始化联盟结构阶段 (Initialization)
% 很多传统算法随机初始化，PGG-TS 使用初始引力场进行启发式分配，起点更高。
fprintf('[Qi2023] Generating Initial Coalition Structure based on P(1)...\n');

for i = 1:N
    % 1.1 计算初始偏好引力 F 和 选择概率 P
    % 智能体 i 观察环境，计算每个任务对它的吸引力
    [F_vec, P_vec] = calculate_gravity_and_prob(i, agents, tasks, SC_global, Gamma, Value_Params);
    
    % 1.2 基于 P 进行初始资源分配 (Initial Allocation)
    % 智能体根据概率选择任务并投入资源
    SC_global = execute_exchange_operation(i, agents, SC_global, P_vec, tasks, Value_Params);
end

% 评估初始状态的全局效用 (Utility)
% 注意: UtilityEvaluator 需要是一个存在的类或函数
current_utility = UtilityEvaluator.evaluate_coalition_metrics(SC_global, agents, tasks, Value_Params, eps_val);
fprintf('[Qi2023] Initial utility: %.4f\n', current_utility);

%% 2. 主循环 (Loop until Stable or Max Iteration)
% 只要未达到最大迭代次数且算法未收敛(稳定)，就继续循环
while k_iter <= K_max && k_stable <= K_len
    
    SC_old_global = SC_global;   % (备份) 虽然本代码主要通过比较效用决定是否更新 SC_global
    improved_this_round = false; % 标记：本轮是否有任何智能体优化了全局效用
    
    % 遍历每一个智能体 (单体序贯优化)
    for i = 1:N
        % -----------------------------------------------------------
        % A. 离开操作 (Leave Operation)
        % 目的: 仅仅依赖贪婪交换容易陷入局部最优。
        % "离开"操作强制智能体随机撤出部分资源，为系统引入扰动。
        % -----------------------------------------------------------
        SC_temp = SC_global; % 创建临时候选解，在 temp 上操作
        
        p_leave = 0.3; % 离开概率 (参数可调)
        
        for m = 1:M
            for k = 1:K
                % 如果当前有资源投入，且随机数命中概率，则撤出资源(置0)
                if SC_temp{m}(i, k) > eps_val && rand < p_leave
                    SC_temp{m}(i, k) = 0;
                end
            end
        end
        
        % -----------------------------------------------------------
        % B. 计算偏好引力 F 和 选择概率 P (Gravity Calculation)
        % 此时智能体处于"部分自由"状态，重新评估当前环境的引力。
        % 引力通常与 (任务价值 * 剩余需求) 成正比，与 (距离平方) 成反比。
        % -----------------------------------------------------------
        [F_vec, P_vec] = calculate_gravity_and_prob(i, agents, tasks, SC_temp, Gamma, Value_Params);
        
        % -----------------------------------------------------------
        % C. 执行交换操作 (Exchange Operation)
        % 基于计算出的概率 P (轮盘赌)，将手中的资源投入到新的任务中。
        % -----------------------------------------------------------
        SC_new_candidate = execute_exchange_operation(i, agents, SC_temp, P_vec, tasks, Value_Params);
        
        % -----------------------------------------------------------
        % D. 禁忌表检查 (Tabu Check)
        % 检查新生成的解是否在"黑名单"中。
        % -----------------------------------------------------------
        SC_hash = get_SC_hash(SC_new_candidate); % 生成解的指纹(Hash)
        is_tabu = is_in_tabu(SC_hash, TabuList); % 查表
        
        accepted = false;
        if ~is_tabu
            % -------------------------------------------------------
            % E. 效用判断 (Utility Check)
            % 如果解不在禁忌表中，计算其效用。
            % -------------------------------------------------------
            new_utility = UtilityEvaluator.evaluate_coalition_metrics(SC_new_candidate, agents, tasks, Value_Params, eps_val);
            
            % 计算效用增量 (Delta U)
            delta_u = new_utility - current_utility;
            
            % 贪婪准则: 只有当新解比当前全局最优解更好时才接受
            if delta_u > 0
                SC_global = SC_new_candidate; % 更新全局状态
                current_utility = new_utility; % 更新当前效用
                k_stable = 0;                 % 重置稳定计数器(因为找到了更好的解)
                accepted = true;
                improved_this_round = true;
            else
                % 拒绝: 保持 SC_global 不变 (即隐式回滚)
                % k_stable 稍后在循环外统一处理
            end
        else
             % 如果被禁忌，直接拒绝。
             % (注: 高级实现可加入"特赦准则 Aspiration Criterion"，即若解极好，即使禁忌也接受)
        end
        
        % 如果接受了新解，将其加入禁忌表，防止马上变回旧解
        if accepted
            TabuList = update_tabu_list(TabuList, SC_hash, L_tabu);
        end
        
    end % End Agent Loop
    
    % 如果一整轮下来没有任何智能体能改进结果，稳定计数器 +1
    if ~improved_this_round
        k_stable = k_stable + 1;
    end
    
    % -----------------------------------------------------------
    % F. 更新温度和 Tabu (Update Boltzmann & Tabu logic)
    % -----------------------------------------------------------
    Gamma = Gamma * alpha; % 降温: 随着时间推移，降低探索概率，增加确定性
    
    % 记录本轮历史数据
    history_data = record_history(history_data, k_iter, SC_global, current_utility, agents, tasks, Value_Params);
    
    % 打印进度
    fprintf('[Qi2023] Round %d: Utility = %.4f, Stability = %d, Temp = %.4f\n', k_iter, current_utility, k_stable, Gamma);
    
    k_iter = k_iter + 1;
end

fprintf('[Qi2023] Algorithm converged after %d iterations.\n', k_iter-1);

% --- 输出最终稳定结构 ---
% 将全局 SC 分配到每个智能体的输出结构中
for i = 1:N
    Value_data(i).SC = SC_global;
end

end

%% ================= 辅助函数 (Helper Functions) =================

function [F, P] = calculate_gravity_and_prob(agent_idx, agents, tasks, SC, Gamma, Value_Params)
    % 计算偏好引力(F)和选择概率(P)
    % 核心公式: (26) 引力场, (27) Boltzmann分布
    
    M = Value_Params.M;
    K = Value_Params.K;
    F = zeros(M, K); % 偏好引力矩阵
    agent_pos = [agents(agent_idx).x, agents(agent_idx).y];
    
    % 1. 计算偏好引力 F
    for m = 1:M
        task_pos = [tasks(m).x, tasks(m).y];
        % 距离平方 (加微小量防止除以0)
        dist_sq = sum((agent_pos - task_pos).^2) + 1e-6;
        
        for k = 1:K
            % 计算该任务当前已获得的资源量
            current_allocated = sum(SC{m}(:, k));
            % 获取任务总需求
            demand = tasks(m).resource_demand(k);
            % 计算剩余需求 (Remaining Demand) - 越缺资源，引力越大
            rem_demand = max(0, demand - current_allocated);
            
            % 任务期望价值
            task_val = tasks(m).value;
            
            % 引力公式: F = (价值 * 剩余需求) / 距离^2
            F(m, k) = (task_val * rem_demand) / dist_sq;
        end
    end
    
    % 2. 计算概率 P (Softmax)
    P = zeros(M, K);
    for k = 1:K
        vec = F(:, k);
        % 数值稳定性处理: 减去最大值防止 exp 溢出
        vec = vec - max(vec);
        exp_vec = exp(vec / Gamma);
        sum_exp = sum(exp_vec);
        
        if sum_exp > 1e-12
            P(:, k) = exp_vec / sum_exp;
        else
            % 如果所有引力都极小(例如任务都满了)，则概率均分
            P(:, k) = ones(M, 1) / M;
        end
    end
end

function SC_new = execute_exchange_operation(agent_idx, agents, SC_current, P_prob, tasks, Value_Params)
    % 基于概率矩阵 P 执行资源交换
    
    SC_new = SC_current;
    M = Value_Params.M;
    K = Value_Params.K;
    
    for k = 1:K
        % 获取智能体拥有的该类资源总量
        resource_amt = agents(agent_idx).resources(k);
        if resource_amt <= 0, continue; end
        
        % --- 轮盘赌选择 (Roulette Wheel Selection) ---
        cum_prob = cumsum(P_prob(:, k));
        r = rand;
        % 找到第一个累积概率大于随机数的任务索引
        selected_task = find(cum_prob >= r, 1, 'first');
        if isempty(selected_task), selected_task = randi(M); end % 保底逻辑
        
        % --- 资源重新分配 ---
        % 1. 先清空该智能体在该资源类型上的所有旧分配 (撤回)
        for m = 1:M
            SC_new{m}(agent_idx, k) = 0;
        end
        
        % 2. 投入到新选中的任务中
        % 检查新任务还缺多少资源，不能超额供给
        curr_alloc = sum(SC_new{selected_task}(:, k));
        demand = tasks(selected_task).resource_demand(k);
        can_add = max(0, demand - curr_alloc);
        
        % 实际投入量 = min(拥有量, 需求空缺量)
        act_add = min(resource_amt, can_add);
        SC_new{selected_task}(agent_idx, k) = act_add;
    end
end

function hash_str = get_SC_hash(SC)
    % 生成联盟结构的唯一字符串标识 (Hash)
    % 用于在 TabuList 中快速查找和比对
    
    % 将 Cell 矩阵扁平化为向量
    temp_vec = [];
    for m = 1:length(SC)
        temp_vec = [temp_vec; SC{m}(:)];
    end
    % 转为字符串。对于超大规模问题，建议替换为 DataHash 等更高效算法。
    hash_str = mat2str(temp_vec); 
end

function is_in = is_in_tabu(sc_hash, tabu_list)
    % 检查当前 Hash 是否存在于禁忌表中
    is_in = false;
    for i = 1:length(tabu_list)
        if strcmp(sc_hash, tabu_list{i})
            is_in = true;
            return;
        end
    end
end

function tabu_list = update_tabu_list(tabu_list, sc_hash, L_tabu)
    % 更新禁忌表 (FIFO 队列)
    % 加入最新状态
    tabu_list{end+1} = sc_hash;
    % 如果超出长度限制，移除最早的一个
    if length(tabu_list) > L_tabu
        tabu_list(1) = []; 
    end
end

function Value_data = init_value_data(agents, tasks, Value_Params)
   % 初始化输出数据结构
   N = Value_Params.N;
   for i=1:N
       Value_data(i).agentID = agents(i).id;
       Value_data(i).agentIndex = i;
       Value_data(i).SC = cell(Value_Params.M, 1);
       % 预分配内存
       for m = 1:Value_Params.M
           Value_data(i).SC{m} = zeros(N, Value_Params.K);
       end
   end
end

function history_data = record_history(hist, k, SC, util, agents, tasks, Value_Params)
    % 记录每一代的详细数据，便于后续分析和绘图
    eps_val = 1e-9;
    
    % 调用评估器获取详细指标 (成本、完成度等)
    [coalition_utility, total_cost, total_completed_value, task_completion_degrees] = ...
        UtilityEvaluator.evaluate_coalition_metrics(SC, agents, tasks, Value_Params, eps_val);
    
    % 简化联盟结构表示，只记录参与者索引
    M = Value_Params.M;
    coalitionstru = cell(M, 1);
    for m = 1:M
        participants = find(any(SC{m} > eps_val, 2));
        coalitionstru{m} = participants';
    end
    
    % 存入结构体
    hist.rounds(k).round_num = k;
    hist.rounds(k).SC = SC;
    hist.rounds(k).coalitionstru = coalitionstru;
    hist.rounds(k).coalition_utility = coalition_utility;
    hist.rounds(k).total_global_cost = total_cost;
    hist.rounds(k).total_completed_value = total_completed_value;
    hist.rounds(k).task_completion_degrees = task_completion_degrees;
    
    history_data = hist;
end