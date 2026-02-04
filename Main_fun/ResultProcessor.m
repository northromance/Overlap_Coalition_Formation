classdef ResultProcessor
    % ResultProcessor ���ڴ����������ͶԱȲ�ͬ�㷨�����н��
    % ������ȡ�ؼ�����ָ�ꡢ����ͳ�Ʊ����Ⱦ�̬������
    
    methods(Static)
        function comparison_stats = compare_results(results, Value_Params)
            % COMPARE_RESULTS ����棺��ȡ�ؼ�����ָ��
            %
            % �����߼���
            %   1. ֱ�Ӷ�ȡ history_data ���һ�ֵ����ݡ�
            %   2. ����ƽ������� = ����������ɶ�֮�� / ����������
            %   3. ���������� = ����������������������
            %
            % ���룺
            %   results      - �㷨����ṹ�� (��������㷨�� Value_data, history_data)
            %   Value_Params - ȫ�ֲ��� (������� M: ��������)
            %
            % �����
            %   comparison_stats - ������ͳ�ƽ���ṹ��
            
            %% 1. ��ʼ��
            alg_names = fieldnames(results);
            num_algorithms = length(alg_names);
            comparison_stats = struct();
            
            %% 2. �����㷨��ȡָ��
            for i = 1:num_algorithms
                alg_name = alg_names{i};
                alg_result = results.(alg_name);
                num_active_coalitions = 0;
                
                % ��ʼ����ǰ�㷨ͳ��
                stats = struct();
                stats.name = alg_result.name;
                
                % �����Դ���������Ƿ���� computation_time �ֶ�
                if isfield(alg_result, 'computation_time')
                    stats.computation_time = alg_result.computation_time;
                else
                    stats.computation_time = NaN;
                end
                
                % ������������㷨����ʧ�ܣ���¼��������
                if isfield(alg_result, 'error')
                    stats.has_error = true;
                    stats.error_message = alg_result.error.message;
                    
                    % ����Ĭ�Ͽ�ֵ��ֹ��������
                    stats.total_utility = NaN;
                    stats.total_cost = NaN;
                    stats.total_completion_score = NaN;
                    stats.avg_task_completion = NaN;
                    stats.num_coalitions = NaN;
                    
                    comparison_stats.(alg_name) = stats;
                    continue;
                end
                stats.has_error = false;
                
                % --- ��λ����Դ�����һ����ʷ��¼ ---
                % ȷ�� history_data �� rounds ����
                if isfield(alg_result, 'history_data') && isfield(alg_result.history_data, 'rounds') && ~isempty(alg_result.history_data.rounds)
                    last_round = alg_result.history_data.rounds(end);
                else
                    warning('ResultProcessor:NoHistory', '�㷨 %s ȱ����ʷ��¼����', alg_name);
                    continue;
                end
                
                %% 3. ��������ָ�� (Utility, Cost, Value)
                % [��Ч��] ȫ�־�����
                stats.total_utility = last_round.coalition_utility;
                
                % [�ܳɱ�] ȫ������
                stats.total_cost = last_round.total_global_cost;
                
                % [����ɼ�ֵ] Sum(Value * Degree)
                stats.total_completion_score = last_round.total_completed_value;
                
                %% 4. ��������� (Average Completion Rate)
                % �߼�����������������ɶȵ�ƽ��ֵ (Sum / M)
                % task_completion_degrees �� Mx1 ����������0ֵ
                degrees = last_round.task_completion_degrees;
                
                stats.task_completion_degrees = degrees; % ����ԭʼ����
                stats.avg_task_completion = mean(degrees); % ƽ��ֵ (0~1)
                
                %% 5. �������� (Number of Coalitions Formed)
                % �߼���ͳ���ж��ٸ�����ִ���� (��������һ�����������)
                % coalitionstru �� MxN ����
                % ����ǰ M ������ (��ֹ SC ���ȳ��� M)
                SC_global = last_round.SC;
                check_count = min(Value_Params.M, length(SC_global));
                
                for j = 1:check_count
                    SC_task = SC_global{j};
                    
                    % �ж�������
                    % 1. ����Ϊ��
                    % 2. ����Ԫ��֮�� > 1e-6 (��ʾȷʵ����ԴͶ�룬���Ը������)
                    if ~isempty(SC_task) && sum(SC_task(:)) > 1e-6
                        num_active_coalitions = num_active_coalitions + 1;
                    end
                end
                
                stats.num_coalitions = num_active_coalitions;
                
                %% 6. �����ܱ�
                comparison_stats.(alg_name) = stats;
            end
        end


        function history_data = record_history_data(history_data, round_idx, Value_data, Value_Params, ...
                final_SC, final_coalitionstru, ...
                coalition_utility, total_global_cost, ...
                total_completed_value, task_completion_degrees, ...
                summatrix)
            % RECORD_HISTORY_DATA ��¼ÿһ���㷨����ϸ״̬
            %
            % ����:
            %   history_data            - ��ʷ�ṹ��
            %   round_idx               - ��ǰ���� (��Ӧ������� counter)
            %   Value_data              - ������״̬ (���ڼ�¼����)
            %   Value_Params            - ȫ�ֲ���
            %   final_SC                - ������Դ���� (Cell)
            %   final_coalitionstru     - ���ճ�Ա����
            %   coalition_utility       - ȫ�־�Ч�� (����)
            %   total_global_cost       - ȫ���ܳɱ� (��������������������֮��)
            %   total_completed_value   - ��������ɼ�ֵ (����)
            %   task_completion_degrees - ������ɶ� (Mx1)
            %   summatrix               - ȫ�ֹ۲����
            %
            % ���:
            %   history_data            - ���º����ʷ�ṹ��
            
            %% 1. ������Ϣ
            history_data.rounds(round_idx).round_num = round_idx;
            
            %% 2. �ṹ����
            history_data.rounds(round_idx).coalitionstru = final_coalitionstru;
            history_data.rounds(round_idx).SC = final_SC;
            
            %% 3. ����ָ�� (��ƽ���洢)
            % ��¼ȫ�־�Ч�� (����)
            history_data.rounds(round_idx).coalition_utility = coalition_utility;
            
            % ��¼ȫ���ܳɱ� (����)
            history_data.rounds(round_idx).total_global_cost = total_global_cost;
            
            % ��¼��ɼ�ֵ����ɶ�
            history_data.rounds(round_idx).total_completed_value = total_completed_value;
            history_data.rounds(round_idx).task_completion_degrees = task_completion_degrees;
            
            %% 4. ������۲�
            history_data.rounds(round_idx).summatrix = summatrix;
            
            % ��¼������� (N x M x TaskTypes)
            % ��ȡǰ M �����������
            belief_snapshot = zeros(Value_Params.N, Value_Params.M, Value_Params.task_type);
            for i = 1:Value_Params.N
                belief_snapshot(i, :, :) = Value_data(i).initbelief(1:Value_Params.M, :);
            end
            history_data.rounds(round_idx).beliefs = belief_snapshot;

        end

        function inner_loop_history = record_inner_loop_iteration(inner_loop_history, iteration, temperature, current_utility, best_utility, SC_current, Value_Params)
            % RECORD_INNER_LOOP_ITERATION 记录内循环每次迭代的详细数据
            %
            % 功能：
            %   记录SA/Qi等算法在内循环中每次迭代的状态，用于后续可视化分析
            %
            % 输入：
            %   inner_loop_history  - 内循环历史结构体
            %   iteration           - 当前迭代次数（从0开始）
            %   temperature         - 当前温度（SA算法）或Gamma系数（Qi算法）
            %   current_utility     - 当前解的效用
            %   best_utility        - 本轮最优效用
            %   SC_current          - 当前联盟结构（Cell数组）
            %   Value_Params        - 全局参数
            %
            % 输出：
            %   inner_loop_history  - 更新后的内循环历史结构体
            %
            % 示例：
            %   inner_loop_history = ResultProcessor.record_inner_loop_iteration(...
            %       inner_loop_history, k_iter, Temperature, current_utility, best_utility, SC, Value_Params);

            %% 记录基本数据
            inner_loop_history.iteration(end+1) = iteration;
            inner_loop_history.temperature(end+1) = temperature;
            inner_loop_history.current_utility(end+1) = current_utility;
            inner_loop_history.best_utility(end+1) = best_utility;

            %% 计算并记录联盟数量
            num_coalitions = 0;
            for m = 1:Value_Params.M
                if any(SC_current{m}(:) > 1e-9)
                    num_coalitions = num_coalitions + 1;
                end
            end
            inner_loop_history.num_coalitions(end+1) = num_coalitions;

        end

        function inner_loop_history = init_inner_loop_history()
            % INIT_INNER_LOOP_HISTORY 初始化内循环历史记录结构体
            %
            % 功能：
            %   创建一个空的内循环历史记录结构体，用于存储迭代过程数据
            %
            % 输出：
            %   inner_loop_history - 初始化的内循环历史结构体
            %
            % 示例：
            %   inner_loop_history = ResultProcessor.init_inner_loop_history();

            inner_loop_history = struct();
            inner_loop_history.iteration = [];
            inner_loop_history.temperature = [];
            inner_loop_history.current_utility = [];
            inner_loop_history.best_utility = [];
            inner_loop_history.num_coalitions = [];
        end
    end
end