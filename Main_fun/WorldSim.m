classdef WorldSim
    % AgentOps ��������֪����Ϊ������
    % ְ�𣺴����۲����ݵ��ռ���ȫ����Ϣ���ں���ͬ�����Լ�����ı�Ҷ˹���¡�

    methods (Static)
        function t_exec = calc_exec_time(task, R_row, Value_Params, tol)
            % calc_exec_time ���㵥�������壨����Դ��ϣ�������������ִ��ʱ�䡣
            % ���裺��ά��Դ���д�����ִ��ʱ��ȡ����"�̰�"����ʱ�����һ����Դ����
            % ���룺
            %   task: (Struct) ������󣬰��� duration_by_resource �� duration �ֶΡ�
            %   R_row: (Vector) ��ǰͶ�����Դ������
            %   Value_Params: (Struct) ȫ�ֲ�����������Դά�� K��
            %   tol: (Float) ��ֵ�ж���ֵ��

            % ȷ����Щ��Դά�ȱ�ʹ���ˣ�Ͷ�� > 0��
            if ~isempty(R_row)
                used = R_row > tol;
            else
                used = true(1, Value_Params.K); % ��δָ��������ȫά�Ȳ���
            end

            if isfield(task, 'duration_by_resource')
                % ���������˷���Դ�ľ����ʱ
                dur = task.duration_by_resource(:)';
                if isscalar(dur)
                    t_exec = dur; % ��Ϊ������ͳһʱ��
                else
                    % �ضϻ������Դά��
                    dur = dur(1:min(numel(dur), Value_Params.K));
                    used = used(1:numel(dur));
                    % �����߼���ȡ��ʹ����Դ�е�����ʱ
                    t_exec = max([dur(used), 0]);
                end
            elseif isfield(task, 'duration')
                t_exec = task.duration; % ʹ�ù̶�ʱ��
            else
                t_exec = 1.0; % Ĭ�϶���ֵ
            end
        end

        function t_exec = calc_coalition_exec_time(SC, task_idx, task, Value_Params, tol)
            % calc_coalition_exec_time ���������������ĳ���������ʱ�䡣
            % �߼������˳�Ա���й������������ʱ���������ĳ�Ա������ľͰЧӦ����
            % ���룺
            %   SC: (Cell) ���˽ṹ��
            %   task_idx: (Int) ����ID��
            %   task: (Struct) �������顣
            %   Value_Params: (Struct) ȫ�ֲ�����

            alloc = SC{task_idx}; % ��ȡ������ķ������ (N x K)
            exec_times = [];

            % �������������壬��������ߵĸ���ʱ��
            for i = 1:Value_Params.N
                if any(alloc(i, :) > tol) % ��������� i ����������
                    % ����ó�Ա��ִ��ʱ�䲢�����б�
                    exec_times = [exec_times, WorldSim.calc_exec_time(task, alloc(i, :), Value_Params, tol)]; %#ok<AGROW>
                end
            end

            % �������˵ĺ�ʱ = ���в������е�����ʱ
            t_exec = max([exec_times, 0]);
        end


        function D_C = calc_task_completion_degree(allocated_resources, task_demand, K)
            % calc_task_completion_degree ����������ɶ� D_C (��Χ 0.0 ~ 1.0)��
            % ����ָ�꣺������ǰ�������Դ�ڶ��̶�����������������
            % ���룺
            %   allocated_resources: (Matrix/Vector) �ѷ������Դ�����Ǿ���������͡�
            %   task_demand: (Vector) ����ʵ������������
            %   K: (Int) ��Դά������

            % �������Ƕ��о��󣨶�������壩���Ȱ�����͵õ�����Դ
            if size(allocated_resources, 1) > 1
                allocated = sum(allocated_resources, 1);
            else
                allocated = allocated_resources;
            end

            % ά�ȶ��룺���� K ά����
            if numel(allocated) < K
                allocated = [allocated, zeros(1, K - numel(allocated))];
            end
            if numel(task_demand) < K
                task_demand = [task_demand, zeros(1, K - numel(task_demand))];
            end

            % ͳ����ʵ�����󣨷��㣩����Դά������
            Z_c = nnz(task_demand > 1e-9);
            if Z_c == 0
                D_C = 1; return; % ��������������Ϊֱ�����
            end

            D_C = 0;
            for k = 1:K
                if task_demand(k) > 1e-9
                    % ����� k ά�ȵ������ʣ��ⶥΪ 1.0 (��Դ�����������ɶ�)
                    ratio = min(allocated(k) / task_demand(k), 1.0);
                    D_C = D_C + ratio;
                end
            end

            % ȡ������Чά�ȵ�ƽ��������
            D_C = D_C / Z_c;
        end


        function [t_fly_total, t_wait_total, t_exec_total, start_times, execution_times, completion_times,mission_end_time] = calc_with_global_sync(...
                agentIdx, myOrderedTasks, agents, tasks, Value_Params, SC, tol)
            % CALC_WITH_GLOBAL_SYNC �������ȫ��ͬ�����Ƶ�ʱ�����ܺģ���������ϸʱ���
            % myOrderedTasks ��Ҫ��֮ǰ������������ȼ������
            % ���룺
            %   agentIdx       - ��ǰ�����������ID
            %   myOrderedTasks - ����������������У��Ѱ����ȼ�����
            %   ... (������׼����)
            %
            % �����
            %   t_fly_total     - �ܷ���ʱ��
            %   t_wait_total    - �ܵȴ�ʱ�䣨�����ȵ��롱�͡����깤����
            %   t_exec_total    - ����Чִ��ʱ��
            %   start_times     - [����] ÿ�������ͳһ��ʼʱ��
            %   execution_times - [����] ÿ������ĸ�����Чִ��ʱ��
            %   completion_times- [����] ÿ�������ͳһ����/�뿪ʱ��

            %% ========== ������ȡ ==========
            N = Value_Params.N;
            M = Value_Params.M;
            R_agent = OCFUtils.get_agent_resource_matrix(SC, agentIdx, Value_Params);

            %% ========== �׶�һ��ȫ��״̬ģ�� (God View) ==========
            % Ŀ�ģ�����ȫ���������ʱ�����ȷ��ÿ������ġ�������ʼʱ�䡱�͡���������ʱ�䡱��

            % 1. ��ʼ������״̬
            agent_state = struct('pos', {}, 'ready_time', {});
            for i = 1:N
                agent_state(i).pos = [agents(i).x, agents(i).y];
                agent_state(i).ready_time = 0;
            end

            % 2. ȫ������
            all_tasks = 1:M;
            global_order = OCFUtils.sort_tasks_by_priority(all_tasks, tasks);

            % 3. ��¼ȫ��ʱ��ê��
            task_sync_start = zeros(M, 1);    % ���� m ��ͳһ��ʼʱ��
            task_coalition_dur = zeros(M, 1); % ���� m �������ܺ�ʱ������ִ��ʱ����

            % 4. ģ������
            for order_idx = 1:M
                task_id = global_order(order_idx);
                task_pos = [tasks(task_id).x, tasks(task_id).y];

                participants = OCFUtils.get_participants(SC, task_id, tol);
                if isempty(participants), continue; end

                % --- ����ÿ�������ߵĵ���ʱ�� ---
                arrival_times = zeros(numel(participants), 1);
                for k = 1:numel(participants)
                    p_id = participants(k);
                    v = agents(p_id).vel;

                    dist = norm(task_pos - agent_state(p_id).pos);
                    fly_time = dist / max(v, tol);

                    arrival_times(k) = agent_state(p_id).ready_time + fly_time;
                end

                % --- ȷ��ͬ����ʼʱ�� (ľͰЧӦ) ---
                sync_start = max(arrival_times);
                task_sync_start(task_id) = sync_start;

                % --- ���������ܺ�ʱ ---
                t_coalition = WorldSim.calc_coalition_exec_time(SC, task_id, tasks(task_id), Value_Params, tol);
                task_coalition_dur(task_id) = t_coalition;

                % --- ���²�����״̬ (ǿ��ͬ���뿪) ---
                for k = 1:numel(participants)
                    p_id = participants(k);
                    agent_state(p_id).pos = task_pos;
                    agent_state(p_id).ready_time = sync_start + t_coalition;
                end
            end

            %% ========== �׶ζ�������Ŀ�����������ϸָ�� (Agent View) ==========

            t_fly_total = 0;
            t_wait_total = 0;
            t_exec_total = 0;

            % ��ʼ����ϸ��¼����
            num_my_tasks = numel(myOrderedTasks);
            start_times = zeros(num_my_tasks, 1);      % ��¼��ʼʱ��
            execution_times = zeros(num_my_tasks, 1);  % ��¼��Чִ��ʱ��
            completion_times = zeros(num_my_tasks, 1); % ��¼����/�뿪ʱ��

            % ����״̬��ר����һ�� agentIdx ��·��
            curr_pos = [agents(agentIdx).x, agents(agentIdx).y];
            curr_clock = 0;
            v = agents(agentIdx).vel;

            for ii = 1:num_my_tasks
                task_id = myOrderedTasks(ii);
                task_pos = [tasks(task_id).x, tasks(task_id).y];

                % --- 1. ���н׶� ---
                dist = norm(task_pos - curr_pos);
                fly_time = dist / max(v, tol);
                t_fly_total = t_fly_total + fly_time;

                my_arrival = curr_clock + fly_time;

                % --- 2. ��ȡȫ��ʱ��ê�� ---
                sync_start = task_sync_start(task_id);
                coalition_dur = task_coalition_dur(task_id);

                % --- 3. ���㡰����ȴ��� ---
                wait_pre_start = max(0, sync_start - my_arrival);

                % --- 4. ���㡰ִ��ʱ�䡱 ---
                if ~isempty(SC) && task_id <= numel(SC) && ~isempty(SC{task_id})
                    R_row = SC{task_id}(agentIdx, :);
                else
                    R_row = R_agent(task_id, :);
                end
                my_exec_time = WorldSim.calc_exec_time(tasks(task_id), R_row, Value_Params, tol);
                t_exec_total = t_exec_total + my_exec_time;

                % --- 5. ���㡰�깤�ȴ��� ---
                wait_post_exec = max(0, coalition_dur - my_exec_time);

                % --- 6. �ۼ��ܵȴ� ---
                t_wait_total = t_wait_total + wait_pre_start + wait_post_exec;

                % --- 7. ����״̬ǰ����һվ ---
                % �뿪ʱ�� = ��ʼʱ�� + �����ܺ�ʱ
                curr_clock = sync_start + coalition_dur;
                curr_pos = task_pos;

                % ========== [����] ��ϸʱ���¼ ==========
                start_times(ii) = sync_start;           % ����ͳһ��ʼ��ʱ��
                execution_times(ii) = my_exec_time;     % ��ʵ�ʸɻ��ʱ��
                completion_times(ii) = curr_clock;      % ���뿪�����ʱ�� (���깤�ȴ�)
            end

            % --- 8. ���ػ��صķ��� ---
            return_dist = norm([agents(agentIdx).x, agents(agentIdx).y] - curr_pos);
            return_time = return_dist / max(v, tol); % ���㷵����ʱ

            t_fly_total = t_fly_total + return_time; % �����ܳɱ�

            % [����] �����������ʱ��
            mission_end_time = curr_clock + return_time;
        end


        function demand = calculate_demand_quantile(belief, task_type_demands, confidence)
            % CALCULATE_DEMAND_QUANTILE ��������ֲ������������Դ��
            %
            % �����߼���
            %   �����岻֪�������ȷ�����ͣ�ֻ֪�����ڸ����͵ĸ��� (belief)��
            %   Ϊ�˱�֤����ɹ��ʣ���������Ҫ׼���㹻����Դ��ʹ����Դ�����á��ĸ������ٴﵽ confidence��
            %
            % �����߼���
            %   1. ����ȷ���Խݾ��������������ǳ�ȷ��������ĳһ�����ͣ����� > confidence����
            %      ��ֱ�Ӱ��ո����͵ı�׼����Я����Դ�����⸴�ӵļ��㡣
            %   2. ����ȷ���Զ��ס��������������ԥ���������ʷ�ɢ�����򹹽�������ۻ��ֲ����� (CDF)��
            %      �ҵ����� confidence �����������С��Դ��������λ�������
            %
            % ���룺
            %   belief            : (1xN double) �������ڸ����͵ĸ��ʷֲ����� [p1, p2, ..., pN]����ӦΪ1��
            %   task_type_demands : (NxK double) N���������Ͷ�K����Դ��������󡣵�i���ǵ�i�����������
            %   confidence        : (double)     ���Ŷ���ֵ (0~1)������ 0.95 ��ʾҪ��95%�İ�����Դ���á�
            %
            % �����
            %   demand            : (1xK double) ���վ����ĸ�����ԴЯ������

            % --- 1. ����У�� ---
            if nargin < 3
                error('calculate_demand_quantile:NotEnoughInputs', '���󣺱����ṩ belief, task_type_demands �� confidence ��������');
            end

            % --- 2. ����Ԥ���� ---
            % num_types: Ǳ�ڵ������������� (N)
            % K: ��Դ��������� (���磺ȼ�͡���ҩ��������)
            [num_types, K] = size(task_type_demands);

            % ȷ�� belief �������� (1xN)����������������
            belief = belief(:).';

            % ��ʼ�������������
            demand = zeros(1, K);

            % --- 3. ����һ��ȷ�������� (High Confidence Strategy) ---
            % Ŀ�ģ�������١�����Ѿ�������ȷ������ĳ�����񣬾�û��Ҫ�����ӵ�ͳ��ѧ���㡣
            % �߼������ĳ���͵ĸ��� >= ���Ŷȣ���ֻ׼�������͵���Դ�������������Ŷ�Ҫ��
            if max(belief) >= confidence
                % �ҵ����������Ǹ���������
                [~, most_likely_type] = max(belief);

                % ֱ�Ӷ�ȡ�����͵�������Ϊ��������
                % ceil: ����ȡ������ֹ������Դ����С������0.5�������ˣ�
                demand = ceil(task_type_demands(most_likely_type, :));
                return; % ֱ�ӽ�������
            end

            % --- 4. ���Զ������չ�� (Quantile/CDF Strategy) ---
            % Ŀ�ģ�����ȷ���Խϸ�ʱ�����������A���������0.4��B��0.6������Ҫ�ۺϿ������п��ܡ�
            % �߼�������ÿһ����Դ k������Ҫ�ҵ�һ����ֵ d��ʹ�� P(ʵ������ <= d) >= confidence��

            % ����ÿһ����Դ���� (��)
            for r = 1:K
                % 4.1 ��ȡ��ǰ��Դ r �����п������������µ�������
                demands_r = task_type_demands(:, r);

                % 4.2 ���򣺽������С��������
                % sorted_demands: ����������ֵ
                % idx: ����������������ͬ�����Ŷ�Ӧ�ĸ���
                [sorted_demands, idx] = sort(demands_r);

                % 4.3 ���Ÿ��ʣ��ø����������������Ӧ
                % ���磺����Ϊ [10, 5, 20]������Ϊ [0.2, 0.3, 0.5]
                % ���������: [5, 10, 20]����Ӧ����: [0.3, 0.2, 0.5]
                sorted_belief = belief(idx);

                % 4.4 �����ۻ����� (CDF - Cumulative Distribution Function)
                % ����������cumulative_prob = [0.3, 0.5, 1.0]
                % ���壺���� <= 5 �ĸ����� 0.3������ <= 10 �ĸ����� 0.5������ <= 20 �ĸ����� 1.0
                cumulative_prob = cumsum(sorted_belief);

                % 4.5 Ѱ����ֵ�ضϵ�
                % �ҵ���һ���ۻ����ʳ��� confidence ��λ��
                % ���� confidence = 0.4������ index=2 (��Ӧ����10) �����ۻ����ʴﵽ 0.5 >= 0.4
                % ����ζ�Ŵ� 10 ����λ��Դ���� 50% �ĸ��ʹ��ã����� >40% ��Ҫ��
                threshold_idx = find(cumulative_prob >= confidence, 1);

                % 4.6 �쳣����
                % ��� confidence ����Ϊ 1.0 ���߸���������û�ҵ���Ĭ��ȡ���������ز��ԣ�
                if isempty(threshold_idx)
                    threshold_idx = num_types;
                end

                % 4.7 ��ֵ
                demand(r) = sorted_demands(threshold_idx);
            end

            % --- 5. ����ȡ�� ---
            % ȷ��������Դ��Ϊ�����������˻���������ذ�������ͨ��Ϊ��ɢֵ��
            demand = ceil(demand);
        end


        function Value_data = init_value_data(agents, tasks, Value_Params)
            % INIT_VALUE_DATA 初始化智能体数据结构
            % 统一的初始化函数，供所有算法使用
            %
            % 输入:
            %   agents       - 智能体结构体数组
            %   tasks        - 任务结构体数组
            %   Value_Params - 全局参数
            %
            % 输出:
            %   Value_data   - 初始化后的智能体数据结构数组

            N = Value_Params.N;
            M = Value_Params.M;
            K = Value_Params.K;

            % 初始化智能体数据结构
            for i = 1:N
                Value_data(i).agentID = agents(i).id;
                Value_data(i).agentIndex = i;
                Value_data(i).iteration = 0;
                Value_data(i).unif = 0;
                Value_data(i).coalitionstru = zeros(M+1, N);
                Value_data(i).initbelief = zeros(M+1, Value_Params.task_type);
                Value_data(i).cost_data = [];

                % 初始化资源分配矩阵
                Value_data(i).resources_matrix = zeros(M, K);

                % 初始化联盟结构 SC
                Value_data(i).SC = cell(M, 1);
                for m = 1:M
                    Value_data(i).SC{m} = zeros(N, K);
                end

                Value_data(i).other = cell(N, 1);

                % 任务执行序列与时间跟踪
                Value_data(i).task_schedule = struct();
                Value_data(i).task_schedule.task_sequence = [];
                Value_data(i).task_schedule.arrival_times = [];
                Value_data(i).task_schedule.start_times = [];
                Value_data(i).task_schedule.mission_end_time = [];
                Value_data(i).task_schedule.execution_times = [];
                Value_data(i).task_schedule.completion_times = [];
                Value_data(i).task_schedule.total_flight_time = 0;
                Value_data(i).task_schedule.total_execution_time = 0;
                Value_data(i).task_schedule.total_energy = 0;
                Value_data(i).selectProb = zeros(K, M);

                % 初始化观测矩阵
                Value_data(i).observe = zeros(M, Value_Params.task_type);
                Value_data(i).preobserve = zeros(M, Value_Params.task_type);

                % 赋予智能体初始物理资源
                Value_data(i).resources = agents(i).resources;
            end

            % 初始化 void 任务（第 M+1 个任务）
            for k = 1:N
                for j = 1:M+1
                    if j == M+1
                        for i = 1:N
                            Value_data(k).coalitionstru(j, i) = agents(i).id;
                        end
                    end
                end
            end

            % 初始化信念分布（均匀先验）
            for i = 1:N
                for j = 1:M
                    Value_data(i).initbelief(j, 1:end) = ones(Value_Params.task_type, 1) / Value_Params.task_type;
                end
            end

            % 初始化邻居信念
            for i = 1:N
                for j = 1:N
                    Value_data(i).other{j}.initbelief = Value_data(j).initbelief;
                end
            end
        end


        function [Value_data, summatrix] = init_observe_belief_neighbor(Value_data, N, M, Value_Params)
            %INIT_OBSERVE_BELIEF_NEIGHBOR 初始化观测矩阵、全局汇总矩阵、信念分布与邻居信念
            %
            % 输入:
            %   Value_data    - 结构体数组（至少已创建 Value_data(i).other 为 cell）
            %   N, M          - 智能体数与任务数
            %   Value_Params  - 参数结构体（需包含 task_type）
            %
            % 输出:
            %   Value_data    - 更新后的结构体数组
            %   summatrix     - 全局观测汇总矩阵 (M x task_type)

            T = Value_Params.task_type;

            % 初始化观测矩阵
            for i = 1:N
                Value_data(i).observe    = zeros(M, T);
                Value_data(i).preobserve = zeros(M, T);
            end

            % 初始化全局观测汇总矩阵
            summatrix = zeros(M, T);

            % 初始化信念分布（均匀先验）
            uniform_prior_row = ones(1, T) / T;   % 1 x T（避免行列维度问题）
            for i = 1:N
                Value_data(i).initbelief(1:M, :) = repmat(uniform_prior_row, M, 1);
            end

            % 初始化邻居信念（用于信息共享）
            for i = 1:N
                for j = 1:N
                    Value_data(i).other{j}.initbelief = Value_data(j).initbelief;
                end
            end
        end


    end

end