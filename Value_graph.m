% 函数功能：
% 使用 Prim 算法计算一个图的最小生成树 (Minimum Spanning Tree, MST)
% 输入：
%   agents      - 一个结构体数组，包含每个智能体/节点的信息
%                 每个结构体必须有 .x 和 .y 字段，表示其二维坐标
%   Value_Params - 一个结构体，包含算法所需的参数
%                 必须有 .N 字段，表示智能体/节点的总数
%
% 输出：
%   p           - 一个行向量，记录了最小生成树构建过程中节点被加入的顺序
%                 p(1) 是起始节点，p(end) 是最后一个被加入的节点
%   result      - 一个 3xM 的矩阵，其中 M = N-1 (树的边数)
%                 每一列代表一条边:
%                 result(1, i) - 边的起点
%                 result(2, i) - 边的终点
%                 result(3, i) - 边的权重 (即两点间的欧氏距离)

function [p, result] = Value_graph(agents, Value_Params)
    
    % 1. 初始化距离矩阵
    % a(i, j) 将存储节点 i 和节点 j 之间的欧氏距离
    a = zeros(Value_Params.N); 
    
    % 2. 计算所有节点对之间的欧氏距离
    % 由于距离矩阵是对称的 (a(i,j) = a(j,i))，为了提高效率，我们只计算上三角部分
    for i = 1:Value_Params.N
         for j = i+1:Value_Params.N
            % 计算节点 i 和节点 j 在二维平面上的直线距离
            a(i,j) = sqrt( (agents(i).x - agents(j).x)^2 + (agents(i).y - agents(j).y)^2 );
         end
    end
    
    % 将上三角矩阵复制到下三角，形成完整的对称距离矩阵
    a = a + a';
    
    % 将对角线元素 (i == j) 设置为无穷大 (inf)
    % 因为一个节点到自身的距离在 MST 算法中是没有意义的，我们不希望选择这样的边
    a(a == 0) = inf; 
    
    % 3. 初始化 Prim 算法所需的变量
    result = [];         % 用于存储最终找到的 MST 的边
    p = 1;               % 记录已加入 MST 的节点集合，初始时从第一个节点开始
    tb = 2:length(a);    % 记录待加入 MST 的节点集合，初始时为除起点外的所有节点
    
    % 4. Prim 算法主循环
    % MST 有 N 个节点，因此需要 N-1 条边。循环直到找到所有 N-1 条边
    while size(result, 2) ~= length(a) - 1 
        
        % 从已有的 MST 节点集合 (p) 到所有待选节点集合 (tb) 的距离
        temp = a(p, tb);
        
        % 将距离矩阵展平成一个列向量，方便寻找最小值
        temp = temp(:);
        
        % 找到最小的距离 d
        d = min(temp);
        
        % 在距离矩阵 a(p, tb) 中找到第一个出现最小值 d 的位置 [jb, kb]
        % jb 是在 p 索引中的位置, kb 是在 tb 索引中的位置
        [jb, kb] = find(a(p, tb) == d, 1);
        
        % 将索引转换为实际的节点编号
        j = p(jb);  % 已在 MST 中的节点
        k = tb(kb); % 将要加入 MST 的新节点
        
        % 将找到的这条边 [j, k, d] 添加到结果中
        result = [result, [j; k; d]]; 
        
        % 将新节点 k 加入到已有的 MST 节点集合 p 中
        p = [p, k]; 
        
        % 将节点 k 从待选节点集合 tb 中移除
        tb(find(tb == k)) = []; 
    end
    
end