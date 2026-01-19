function test_select_probs_calc_gaps()
% test_select_probs_calc_gaps 快速单元测试 select_probs / calc_gaps / calculate_demand_quantile
% 运行方式：在项目根目录进入 MATLAB，执行 tests/test_select_probs_calc_gaps
%
% 覆盖场景：
%   1) calculate_demand_quantile 高置信度分支（直接取最可能类型需求）
%   2) calculate_demand_quantile 低置信度分支（分位数计算）
%   3) calc_gaps 结合 SC 累加与分位数需求计算出的 resource_gap
%   4) select_probs 归一化、优先级权重作用是否正确

    %% 路径设置（相对 tests 目录向上两级到项目根）
    project_root = fileparts(fileparts(mfilename('fullpath')));
    addpath(project_root);
    addpath(fullfile(project_root, 'SA'));

    fprintf('Running select_probs / calc_gaps / calculate_demand_quantile tests...\n');

    test_calculate_demand_quantile_high_confidence();
    test_calculate_demand_quantile_low_confidence();
    test_calc_gaps_quantile_and_allocation();
    test_select_probs_priority_and_normalization();

    fprintf('All tests passed.\n');
end

%% ========== 子测试：calculate_demand_quantile ==========
function test_calculate_demand_quantile_high_confidence()
    belief = [0.9, 0.1];
    demands = [2, 5;
               10, 1];
    conf = 0.8;

    got = OCFUtils.calculate_demand_quantile(belief, demands, conf);
    expect = [2, 5];
    assert(isequal(got, expect), 'High-confidence branch should pick most likely type demands.');
end

function test_calculate_demand_quantile_low_confidence()
    belief = [0.4, 0.6];
    demands = [2, 5;
               10, 1];
    conf = 0.9;

    got = OCFUtils.calculate_demand_quantile(belief, demands, conf);
    expect = [10, 5];  % 分位数：r1 走到 0.9 累积 -> 10；r2 -> 5
    assert(isequal(got, expect), 'Low-confidence branch should return quantile-based demand.');
end

%% ========== 子测试：calc_gaps ==========
function test_calc_gaps_quantile_and_allocation()
    % 构造最小化参数
    Value_Params.N = 2;
    Value_Params.M = 2;
    Value_Params.K = 2;
    Value_Params.task_type_demands = [2, 4;   % 类型1
                                      6, 8];  % 类型2
    Value_Params.resource_confidence = 0.8;

    % belief: 任务1高置信度 -> 取类型1需求；任务2低置信度 -> 用分位数
    Value_data.initbelief = [0.9, 0.1;
                             0.4, 0.6];

    % SC：每个任务的资源分配 (N x K)
    Value_data.SC = cell(Value_Params.M, 1);
    Value_data.SC{1} = [1, 2;
                        0, 1];  % 任务1 分配 r1=1,r2=3
    Value_data.SC{2} = [0, 0;
                        1, 1];  % 任务2 分配 r1=1,r2=1

    % 其余字段当前函数不使用，用占位即可
    agents = struct([]);
    tasks = struct([]);

    [allocated_resources, resource_gap] = calc_gaps(Value_data, Value_Params);

    % allocated_resources：按 agent 汇总所有任务
    assert(isequal(allocated_resources, [1, 2; 1, 2]), 'Allocated resources per agent mismatch.');

    % 预期缺口：
    %  任务1: 需求[2,4] - 已获[1,3] = [1,1]
    %  任务2: 分位数需求[6,8] - 已获[1,1] = [5,7]
    expect_gap = [1, 1;
                  5, 7];
    assert(isequal(resource_gap, expect_gap), 'Resource gaps do not match expected quantile-based values.');
end

%% ========== 子测试：select_probs ==========
function test_select_probs_priority_and_normalization()
    % 基础参数
    Value_Params.K = 2;
    Value_Params.M = 2;

    % agent 在原点，两任务等距，优先级不同
    agents(1).x = 0; agents(1).y = 0;

    tasks(1).priority = 1; tasks(1).x = 1;  tasks(1).y = 0;
    tasks(2).priority = 3; tasks(2).x = -1; tasks(2).y = 0;

    Value_data.agentID = 1;
    Value_data.resources = [5; 5];  % 每种资源可用量

    resource_gap = ones(Value_Params.M, Value_Params.K);  % 两个任务的需求对称

    probs = select_probs(Value_data, agents, tasks, Value_Params, resource_gap);

    % 理论权重：任务1 => 1^2 * 1 * 5 / 1 = 5，任务2 => 3^2 * 1 * 5 / 1 = 45
    % 归一化后：0.1 和 0.9
    assert(all(abs(sum(probs, 2) - 1) < 1e-12), 'Each resource row should sum to 1 after normalization.');
    assert(all(abs(probs(:, 1) - 0.1) < 1e-12), 'Lower priority task should get ~0.1 probability.');
    assert(all(abs(probs(:, 2) - 0.9) < 1e-12), 'Higher priority task should dominate (~0.9).');
end
