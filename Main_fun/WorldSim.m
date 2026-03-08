classdef WorldSim

    methods (Static)
        function t_exec = calc_exec_time(task, R_row, Value_Params, tol)
            if ~isempty(R_row)
                used = R_row > tol;
            else
                used = true(1, Value_Params.K);
            end

            if isfield(task, 'duration_by_resource')
                dur = task.duration_by_resource(:)';
                if isscalar(dur)
                    t_exec = dur;
                else
                    dur = dur(1:min(numel(dur), Value_Params.K));
                    used = used(1:numel(dur));
                    t_exec = max([dur(used), 0]);
                end
            elseif isfield(task, 'duration')
                t_exec = task.duration;
            else
                t_exec = 1.0;
            end
        end

        function t_exec = calc_coalition_exec_time(SC, task_idx, task, Value_Params, tol)
            alloc = SC{task_idx};
            exec_times = [];

            for i = 1:Value_Params.N
                if any(alloc(i, :) > tol)
                    exec_times = [exec_times, WorldSim.calc_exec_time(task, alloc(i, :), Value_Params, tol)]; %#ok<AGROW>
                end
            end

            t_exec = max([exec_times, 0]);
        end


        function D_C = calc_task_completion_degree(allocated_resources, task_demand, K)
            if size(allocated_resources, 1) > 1
                allocated = sum(allocated_resources, 1);
            else
                allocated = allocated_resources;
            end

            if numel(allocated) < K
                allocated = [allocated, zeros(1, K - numel(allocated))];
            end
            if numel(task_demand) < K
                task_demand = [task_demand, zeros(1, K - numel(task_demand))];
            end

            Z_c = nnz(task_demand > 1e-9);
            if Z_c == 0
                D_C = 1; return;
            end

            D_C = 0;
            for k = 1:K
                if task_demand(k) > 1e-9
                    ratio = min(allocated(k) / task_demand(k), 1.0);
                    D_C = D_C + ratio;
                end
            end

            D_C = D_C / Z_c;
        end


        function all_agents_results = calc_all_agents_with_global_sync(agents, tasks, Value_Params, SC, tol)
            %CALC_ALL_AGENTS_WITH_GLOBAL_SYNC 鍦�"鍏ㄥ眬鍚屾鎵ц"鍋囪涓嬩竴娆℃€ц绠楁墍鏈夋櫤鑳戒綋鐨勯琛�/绛夊緟/鎵ц鏃堕棿
            %
            % 鏍稿績鎬濇兂锛�
            % 1) 鍏堟寜鍏ㄥ眬浠诲姟浼樺厛绾�(global_order)鎺ㄨ繘"绯荤粺鏃堕挓"锛屽姣忎釜浠诲姟璁＄畻锛�
            %    - 璇ヤ换鍔＄殑鍚屾寮€濮嬫椂鍒� task_sync_start(task_id)
            %    - 璇ヤ换鍔＄殑鑱旂洘鎵ц鏃堕暱 task_coalition_dur(task_id)
            % 2) 鐒跺悗瀵规墍鏈夋櫤鑳戒綋骞惰璁＄畻鍏跺悇鑷殑鏃堕棿鎸囨爣
            %
            % Inputs:
            %   agents, tasks   - 鏅鸿兘浣�/浠诲姟缁撴瀯浣撴暟缁�
            %   Value_Params    - 鍙傛暟缁撴瀯浣�(鍖呭惈 N,M,K)
            %   SC              - 璧勬簮鍒嗛厤/鑱旂洘缁撴瀯
            %   tol             - 鏁板€煎宸�
            %
            % Outputs:
            %   all_agents_results - 缁撴瀯浣撴暟缁�(1xN)锛屽寘鍚瘡涓櫤鑳戒綋鐨勶細
            %       .t_fly_total     - 鎬婚琛屾椂闂�(鍚繑鑸�)
            %       .t_wait_total    - 鎬荤瓑寰呮椂闂�
            %       .t_exec_total    - 鎬绘墽琛屾椂闂�
            %       .start_times     - 姣忎釜浠诲姟鐨勫悓姝ュ紑濮嬫椂鍒�
            %       .execution_times - 姣忎釜浠诲姟鐨勮嚜韬墽琛屾椂闀�
            %       .completion_times- 姣忎釜浠诲姟瀹屾垚鏃跺埢
            %       .mission_end_time- 浠诲姟搴忓垪瀹屾垚骞惰繑鑸悗鐨勭粨鏉熸椂鍒�
            %       .task_sequence   - 浠诲姟搴忓垪(鎸変紭鍏堢骇鎺掑簭鍚�)

            N = Value_Params.N;
            M = Value_Params.M;

            %% 闃舵1锛氬叏灞€鍚屾妯℃嫙锛岃绠楁墍鏈変换鍔＄殑鍚屾寮€濮嬫椂鍒诲拰鑱旂洘鎵ц鏃堕暱
            agent_state = struct('pos', {}, 'ready_time', {});
            for i = 1:N
                agent_state(i).pos = [agents(i).x, agents(i).y];
                agent_state(i).ready_time = 0;
            end

            all_tasks = 1:M;
            global_order = OCFUtils.sort_tasks_by_priority(all_tasks, tasks);

            task_sync_start = zeros(M, 1);
            task_coalition_dur = zeros(M, 1);

            for order_idx = 1:M
                task_id = global_order(order_idx);
                task_pos = [tasks(task_id).x, tasks(task_id).y];

                participants = OCFUtils.get_participants(SC, task_id, tol);
                if isempty(participants), continue; end

                arrival_times = zeros(numel(participants), 1);
                for k = 1:numel(participants)
                    p_id = participants(k);
                    v = agents(p_id).vel;
                    dist = norm(task_pos - agent_state(p_id).pos);
                    fly_time = dist / max(v, tol);
                    arrival_times(k) = agent_state(p_id).ready_time + fly_time;
                end

                sync_start = max(arrival_times);
                task_sync_start(task_id) = sync_start;

                t_coalition = WorldSim.calc_coalition_exec_time(SC, task_id, tasks(task_id), Value_Params, tol);
                task_coalition_dur(task_id) = t_coalition;

                for k = 1:numel(participants)
                    p_id = participants(k);
                    agent_state(p_id).pos = task_pos;
                    agent_state(p_id).ready_time = sync_start + t_coalition;
                end
            end

            %% 闃舵2锛氫负姣忎釜鏅鸿兘浣撹绠楄缁嗙殑鏃堕棿鎸囨爣
            all_agents_results = struct('t_fly_total', {}, 't_wait_total', {}, 't_exec_total', {}, ...
                'start_times', {}, 'execution_times', {}, 'completion_times', {}, ...
                'mission_end_time', {}, 'task_sequence', {});

            for agentIdx = 1:N
                % 鑾峰彇璇ユ櫤鑳戒綋鐨勪换鍔″垪琛ㄥ苟鎺掑簭
                task_list = OCFUtils.get_agent_tasks_fast(SC, agentIdx, tol);
                task_list = task_list(task_list <= M);

                if isempty(task_list)
                    % 璇ユ櫤鑳戒綋娌℃湁浠诲姟
                    all_agents_results(agentIdx).t_fly_total = 0;
                    all_agents_results(agentIdx).t_wait_total = 0;
                    all_agents_results(agentIdx).t_exec_total = 0;
                    all_agents_results(agentIdx).start_times = [];
                    all_agents_results(agentIdx).execution_times = [];
                    all_agents_results(agentIdx).completion_times = [];
                    all_agents_results(agentIdx).mission_end_time = 0;
                    all_agents_results(agentIdx).task_sequence = [];
                    continue;
                end

                myOrderedTasks = OCFUtils.sort_tasks_by_priority(task_list, tasks);
                R_agent = OCFUtils.get_agent_resource_matrix(SC, agentIdx, Value_Params);

                t_fly_total = 0;
                t_wait_total = 0;
                t_exec_total = 0;

                num_my_tasks = numel(myOrderedTasks);
                start_times = zeros(num_my_tasks, 1);
                execution_times = zeros(num_my_tasks, 1);
                completion_times = zeros(num_my_tasks, 1);

                curr_pos = [agents(agentIdx).x, agents(agentIdx).y];
                curr_clock = 0;
                v = agents(agentIdx).vel;

                for ii = 1:num_my_tasks
                    task_id = myOrderedTasks(ii);
                    task_pos = [tasks(task_id).x, tasks(task_id).y];

                    % (1) 椋炶
                    dist = norm(task_pos - curr_pos);
                    fly_time = dist / max(v, tol);
                    t_fly_total = t_fly_total + fly_time;

                    my_arrival = curr_clock + fly_time;

                    sync_start = task_sync_start(task_id);
                    coalition_dur = task_coalition_dur(task_id);

                    % (2) 鍚屾鍓嶇瓑寰�
                    wait_pre_start = max(0, sync_start - my_arrival);

                    if ~isempty(SC) && task_id <= numel(SC) && ~isempty(SC{task_id})
                        R_row = SC{task_id}(agentIdx, :);
                    else
                        R_row = R_agent(task_id, :);
                    end

                    % (3) 鑷韩鎵ц鏃堕暱
                    my_exec_time = WorldSim.calc_exec_time(tasks(task_id), R_row, Value_Params, tol);
                    t_exec_total = t_exec_total + my_exec_time;

                    % (4) 鍚屾鍚庣瓑寰�
                    wait_post_exec = max(0, coalition_dur - my_exec_time);

                    t_wait_total = t_wait_total + wait_pre_start + wait_post_exec;

                    curr_clock = sync_start + coalition_dur;
                    curr_pos = task_pos;

                    start_times(ii) = sync_start;
                    execution_times(ii) = my_exec_time;
                    completion_times(ii) = curr_clock;
                end

                % 杩旇埅
                return_dist = norm([agents(agentIdx).x, agents(agentIdx).y] - curr_pos);
                return_time = return_dist / max(v, tol);
                t_fly_total = t_fly_total + return_time;
                mission_end_time = curr_clock + return_time;

                % 淇濆瓨缁撴灉
                all_agents_results(agentIdx).t_fly_total = t_fly_total;
                all_agents_results(agentIdx).t_wait_total = t_wait_total;
                all_agents_results(agentIdx).t_exec_total = t_exec_total;
                all_agents_results(agentIdx).start_times = start_times;
                all_agents_results(agentIdx).execution_times = execution_times;
                all_agents_results(agentIdx).completion_times = completion_times;
                all_agents_results(agentIdx).mission_end_time = mission_end_time;
                all_agents_results(agentIdx).task_sequence = myOrderedTasks;
            end
        end


        function [t_fly_total, t_wait_total, t_exec_total, start_times, execution_times, completion_times,mission_end_time] = calc_with_global_sync(...
                agentIdx, myOrderedTasks, agents, tasks, Value_Params, SC, tol)
            %CALC_WITH_GLOBAL_SYNC 锟节★拷全锟斤拷同锟斤拷执锟叫★拷锟斤拷锟斤拷锟铰硷拷锟姐单锟斤拷锟斤拷锟斤拷锟斤拷姆锟斤拷锟�/锟饺达拷/执锟斤拷时锟戒。
            %
            % 锟斤拷锟斤拷思锟诫：
            % 1) 锟饺帮拷全锟斤拷锟斤拷锟斤拷锟斤拷锟饺硷拷(global_order)锟狡斤拷锟斤拷系统时锟接★拷锟斤拷锟斤拷每锟斤拷锟斤拷锟斤拷锟斤拷悖�
            %    - 锟斤拷锟斤拷锟斤拷锟酵拷锟斤拷锟绞际憋拷锟� task_sync_start(task_id)锟斤拷锟斤拷锟斤拷锟斤拷锟斤拷锟斤拷锟斤拷锟斤拷锟斤拷锟斤拷锟藉都锟斤拷锟斤拷锟斤拷时锟斤拷
            %    - 锟斤拷锟斤拷锟斤拷锟斤拷锟斤拷锟街达拷锟绞憋拷锟� task_coalition_dur(task_id)锟斤拷锟斤拷锟斤拷锟斤拷锟斤拷锟斤拷锟斤拷员锟斤拷执锟斤拷时锟斤拷(取 max)
            %    锟斤拷锟捷此革拷锟斤拷锟斤拷锟叫诧拷锟斤拷锟竭的碉拷前位锟斤拷锟斤拷锟斤拷锟绞憋拷锟�(ready_time)锟斤拷
            % 2) 锟劫讹拷指锟斤拷锟斤拷锟斤拷锟斤拷(agentIdx)锟斤拷锟斤拷锟斤拷锟斤拷锟斤拷锟斤拷锟斤拷锟�(myOrderedTasks)锟斤拷锟姐：
            %    - 锟斤拷锟斤拷时锟戒：锟斤拷锟斤拷一锟斤拷位锟矫飞碉拷锟斤拷前锟斤拷锟斤拷锟斤拷时锟斤拷
            %    - 锟饺达拷时锟戒：锟斤拷锟斤拷锟饺碉拷同锟斤拷锟斤拷始 + 执锟叫猴拷鹊锟斤拷锟斤拷锟斤拷锟斤拷锟斤拷锟斤拷
            %    - 执锟斤拷时锟戒：锟斤拷锟斤拷锟斤拷锟斤拷锟节革拷锟斤拷锟斤拷锟较碉拷锟斤拷锟斤拷执锟斤拷时锟斤拷
            % 3) 锟斤拷锟斤拷锟较凤拷锟斤拷(锟截碉拷锟斤拷始位锟斤拷)时锟戒，锟矫碉拷 mission_end_time锟斤拷
            %
            % Inputs:
            %   agentIdx        - 锟斤拷前要锟斤拷锟斤拷锟斤拷锟斤拷锟斤拷锟斤拷锟斤拷锟斤拷(1..N)
            %   myOrderedTasks  - 锟斤拷前锟斤拷锟斤拷锟斤拷执锟叫碉拷锟斤拷锟斤拷锟斤拷锟斤拷(锟斤拷锟斤拷锟斤拷锟斤拷锟斤拷)
            %   agents, tasks   - 锟斤拷锟斤拷锟斤拷/锟斤拷锟斤拷峁癸拷锟斤拷锟斤拷锟�(锟斤拷锟斤拷锟� x,y,vel 锟斤拷锟街讹拷)
            %   Value_Params    - 锟斤拷锟斤拷锟结构锟斤拷(锟斤拷锟劫帮拷锟斤拷 N,M,K)
            %   SC              - 锟斤拷源锟斤拷锟斤拷/锟斤拷锟剿结构锟斤拷SC{m} 为 N锟斤拷K 锟斤拷锟斤拷(锟斤拷 m 锟斤拷锟斤拷锟斤拷姆锟斤拷锟�)
            %   tol             - 锟斤拷值锟捷诧拷(锟斤拷锟斤拷锟斤拷锟�/锟叫讹拷锟斤拷源锟角凤拷使锟斤拷)
            %
            % Outputs:
            %   t_fly_total     - 锟杰凤拷锟斤拷时锟斤拷(锟斤拷锟斤拷锟斤拷)
            %   t_wait_total    - 锟杰等达拷时锟斤拷(同锟斤拷前锟饺达拷 + 同锟斤拷锟襟“诧拷锟诫到锟斤拷锟剿斤拷锟斤拷锟斤拷锟侥等达拷)
            %   t_exec_total    - 锟斤拷执锟斤拷时锟斤拷(锟斤拷锟斤拷锟斤拷锟斤拷锟斤拷锟斤拷执锟斤拷时锟斤拷锟桔硷拷)
            %   start_times     - 锟斤拷锟斤拷锟斤拷锟斤拷每锟斤拷锟斤拷锟斤拷锟酵拷锟斤拷锟绞际憋拷锟�
            %   execution_times - 锟斤拷锟斤拷锟斤拷锟斤拷每锟斤拷锟斤拷锟斤拷锟斤拷锟斤拷锟街达拷锟绞憋拷锟�
            %   completion_times- 锟斤拷锟斤拷锟斤拷锟斤拷每锟斤拷锟斤拷锟斤拷锟斤拷锟绞憋拷锟�(同锟斤拷锟斤拷始 + 锟斤拷锟斤拷时锟斤拷)
            %   mission_end_time- 锟斤拷锟斤拷锟斤拷锟斤拷锟斤拷刹锟斤拷锟斤拷锟斤拷锟侥斤拷锟斤拷时锟斤拷
            N = Value_Params.N;
            M = Value_Params.M;
            R_agent = OCFUtils.get_agent_resource_matrix(SC, agentIdx, Value_Params);

            agent_state = struct('pos', {}, 'ready_time', {});
            for i = 1:N
                % 锟斤拷录每锟斤拷锟斤拷锟斤拷锟斤拷摹锟斤拷锟角拔伙拷锟� pos锟斤拷锟酵★拷锟斤拷一锟轿可筹拷锟斤拷时锟斤拷 ready_time锟斤拷
                agent_state(i).pos = [agents(i).x, agents(i).y];
                agent_state(i).ready_time = 0;
            end

            all_tasks = 1:M;
            % 全锟斤拷锟斤拷锟斤拷顺锟斤拷锟斤拷锟斤拷模锟斤拷系统锟斤拷锟斤拷摹锟斤拷锟酵伙拷锟斤拷燃锟斤拷锟斤拷锟酵拷锟斤拷平锟斤拷锟�
            global_order = OCFUtils.sort_tasks_by_priority(all_tasks, tasks);

            task_sync_start = zeros(M, 1);
            task_coalition_dur = zeros(M, 1);

            for order_idx = 1:M
                task_id = global_order(order_idx);
                task_pos = [tasks(task_id).x, tasks(task_id).y];

                % 锟揭筹拷锟斤拷锟斤拷锟斤拷牟锟斤拷锟斤拷锟�(锟斤拷 SC{task_id} 锟叫凤拷锟斤拷锟斤拷锟斤拷源锟斤拷锟斤拷锟斤拷锟斤拷)
                participants = OCFUtils.get_participants(SC, task_id, tol);
                if isempty(participants), continue; end

                arrival_times = zeros(numel(participants), 1);
                for k = 1:numel(participants)
                    p_id = participants(k);
                    v = agents(p_id).vel;

                    % 锟斤拷锟斤拷锟竭达拷锟戒当前 pos 锟缴碉拷锟斤拷锟斤拷锟侥碉拷锟斤拷时锟斤拷 = ready_time + 锟斤拷锟斤拷时锟斤拷
                    dist = norm(task_pos - agent_state(p_id).pos);
                    fly_time = dist / max(v, tol);

                    arrival_times(k) = agent_state(p_id).ready_time + fly_time;
                end

                % 同锟斤拷锟斤拷始锟斤拷锟斤拷锟斤拷锟斤拷锟斤拷胁锟斤拷锟斤拷叨锟斤拷锟斤拷耄拷锟斤拷取锟斤拷锟斤拷时锟教碉拷锟斤拷锟街�
                sync_start = max(arrival_times);
                task_sync_start(task_id) = sync_start;

                % 锟斤拷锟斤拷执锟斤拷时锟斤拷锟斤拷锟斤拷锟斤拷锟斤拷执锟斤拷锟斤拷锟斤拷锟侥筹拷员锟斤拷锟斤拷锟斤拷锟斤拷锟斤拷锟斤拷锟斤拷锟绞憋拷锟�
                t_coalition = WorldSim.calc_coalition_exec_time(SC, task_id, tasks(task_id), Value_Params, tol);
                task_coalition_dur(task_id) = t_coalition;

                for k = 1:numel(participants)
                    p_id = participants(k);
                    % 锟斤拷锟斤拷锟斤拷锟斤拷螅翰锟斤拷锟斤拷锟轿伙拷帽锟轿拷锟斤拷锟姐，锟斤拷锟斤拷时锟斤拷锟斤拷锟轿� sync_start + t_coalition
                    agent_state(p_id).pos = task_pos;
                    agent_state(p_id).ready_time = sync_start + t_coalition;
                end
            end

            t_fly_total = 0;
            t_wait_total = 0;
            t_exec_total = 0;

            num_my_tasks = numel(myOrderedTasks);
            start_times = zeros(num_my_tasks, 1);
            execution_times = zeros(num_my_tasks, 1);
            completion_times = zeros(num_my_tasks, 1);

            curr_pos = [agents(agentIdx).x, agents(agentIdx).y];
            curr_clock = 0;
            v = agents(agentIdx).vel;

            for ii = 1:num_my_tasks
                task_id = myOrderedTasks(ii);
                task_pos = [tasks(task_id).x, tasks(task_id).y];

                % (1) 锟斤拷锟叫ｏ拷锟接碉拷前锟姐到锟斤拷锟斤拷锟�
                dist = norm(task_pos - curr_pos);
                fly_time = dist / max(v, tol);
                t_fly_total = t_fly_total + fly_time;

                my_arrival = curr_clock + fly_time;

                sync_start = task_sync_start(task_id);
                coalition_dur = task_coalition_dur(task_id);

                % (2) 同锟斤拷前锟饺达拷锟斤拷锟斤拷锟斤拷业锟斤拷锟斤拷耍锟斤拷锟揭拷鹊锟酵拷锟斤拷锟绞�
                wait_pre_start = max(0, sync_start - my_arrival);

                if ~isempty(SC) && task_id <= numel(SC) && ~isempty(SC{task_id})
                    R_row = SC{task_id}(agentIdx, :);
                else
                    R_row = R_agent(task_id, :);
                end
                % (3) 锟斤拷锟斤拷执锟斤拷时锟斤拷锟斤拷锟斤拷锟斤拷锟斤拷锟斤拷锟绞憋拷锟斤拷锟斤拷曳锟斤拷涞斤拷锟斤拷锟皆达拷锟斤拷锟�
                my_exec_time = WorldSim.calc_exec_time(tasks(task_id), R_row, Value_Params, tol);
                t_exec_total = t_exec_total + my_exec_time;

                % (4) 同锟斤拷锟斤拷却锟斤拷锟斤拷锟斤拷锟斤拷锟斤拷锟斤拷锟斤拷锟斤拷 coalition_dur 锟斤拷锟斤拷锟斤拷锟斤拷锟斤拷执锟叫革拷锟斤拷锟斤拷锟斤拷要锟饺达拷锟斤拷锟斤拷
                wait_post_exec = max(0, coalition_dur - my_exec_time);

                % 锟杰等达拷时锟斤拷 = 同锟斤拷前锟饺达拷 + 同锟斤拷锟斤拷锟斤拷却锟�
                t_wait_total = t_wait_total + wait_pre_start + wait_post_exec;

                % 锟斤拷锟斤拷时锟斤拷锟狡斤拷锟斤拷锟斤拷锟斤拷锟斤拷锟斤拷锟斤拷锟斤拷锟绞憋拷獭锟�(锟斤拷全锟斤拷同锟斤拷锟斤拷锟斤拷一锟斤拷)
                curr_clock = sync_start + coalition_dur;
                curr_pos = task_pos;

                start_times(ii) = sync_start;
                execution_times(ii) = my_exec_time;
                completion_times(ii) = curr_clock;
            end

            % 锟斤拷锟斤拷锟斤拷锟截碉拷锟斤拷锟斤拷锟斤拷锟斤拷锟绞嘉伙拷锟�
            return_dist = norm([agents(agentIdx).x, agents(agentIdx).y] - curr_pos);
            return_time = return_dist / max(v, tol);

            t_fly_total = t_fly_total + return_time;

            % 锟斤拷锟斤拷锟斤拷锟叫斤拷锟斤拷锟斤拷锟斤拷锟斤拷锟斤拷锟斤拷锟斤拷锟斤拷时锟斤拷
            mission_end_time = curr_clock + return_time;
        end


        function demand = calculate_demand_quantile(belief, task_type_demands, confidence)
            if nargin < 3
                error('calculate_demand_quantile:NotEnoughInputs', 'Need: belief, task_type_demands, confidence');
            end

            [num_types, K] = size(task_type_demands);

            belief = belief(:).';

            demand = zeros(1, K);

            if max(belief) >= confidence
                [~, most_likely_type] = max(belief);
                demand = ceil(task_type_demands(most_likely_type, :));
                return;
            end

            for r = 1:K
                demands_r = task_type_demands(:, r);

                [sorted_demands, idx] = sort(demands_r);

                sorted_belief = belief(idx);

                cumulative_prob = cumsum(sorted_belief);

                threshold_idx = find(cumulative_prob >= confidence, 1);

                if isempty(threshold_idx)
                    threshold_idx = num_types;
                end

                demand(r) = sorted_demands(threshold_idx);
            end

            demand = ceil(demand);
        end


        function Value_data = init_value_data(agents, tasks, Value_Params)
            N = Value_Params.N;
            M = Value_Params.M;
            K = Value_Params.K;

            for i = 1:N
                Value_data(i).agentID = agents(i).id;
                Value_data(i).agentIndex = i;
                Value_data(i).iteration = 0;
                Value_data(i).unif = 0;
                Value_data(i).coalitionstru = zeros(M+1, N);
                Value_data(i).initbelief = zeros(M+1, Value_Params.task_type);
                Value_data(i).cost_data = [];

                Value_data(i).resources_matrix = zeros(M, K);

                Value_data(i).SC = cell(M, 1);
                for m = 1:M
                    Value_data(i).SC{m} = zeros(N, K);
                end

                Value_data(i).other = cell(N, 1);

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

                Value_data(i).observe = zeros(M, Value_Params.task_type);
                Value_data(i).preobserve = zeros(M, Value_Params.task_type);

                Value_data(i).resources = agents(i).resources;
            end

            for k = 1:N
                for j = 1:M+1
                    if j == M+1
                        for i = 1:N
                            Value_data(k).coalitionstru(j, i) = agents(i).id;
                        end
                    end
                end
            end

            for i = 1:N
                for j = 1:M
                    Value_data(i).initbelief(j, 1:end) = ones(Value_Params.task_type, 1) / Value_Params.task_type;
                end
            end

            for i = 1:N
                for j = 1:N
                    Value_data(i).other{j}.initbelief = Value_data(j).initbelief;
                end
            end
        end


        function [Value_data, summatrix] = init_observe_belief_neighbor(Value_data, N, M, Value_Params)
            T = Value_Params.task_type;

            for i = 1:N
                Value_data(i).observe    = zeros(M, T);
                Value_data(i).preobserve = zeros(M, T);
            end

            summatrix = zeros(M, T);

            uniform_prior_row = ones(1, T) / T;
            for i = 1:N
                Value_data(i).initbelief(1:M, :) = repmat(uniform_prior_row, M, 1);
            end

            for i = 1:N
                for j = 1:N
                    Value_data(i).other{j}.initbelief = Value_data(j).initbelief;
                end
            end
        end


    end

end