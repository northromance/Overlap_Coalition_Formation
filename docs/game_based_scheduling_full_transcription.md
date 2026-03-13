# Game-based scheduling of mobile charging robots for electric vehicle charging: A relay-like scheme

> 基于用户上传 PDF 的完整 Markdown 转写稿。正文保留按页原始提取内容，另附公式 LaTeX 规范化版本、算法伪代码与表格重排版本。

## Source
- Journal: Applied Energy 402 (2026) 126956
- DOI: 10.1016/j.apenergy.2025.126956
- Authors: Qiuyang Fang, Chunyan Zhang, Chen Wang, Guangming Xie, Jianlei Zhang

## Figure Captions
- Fig. 1. An example of a parking facility where MCRs deliver charging services for EVs. Green-marked vehicles are either being charged or fully charged, while black-marked vehicles are new arrivals or unassigned, awaiting charging or parking allocation.
- Fig. 2. An example of a group of three MCRs working together to increase an EV’s SOC from 0 % to 100 %. ① MCR 1 arrives first and initiates the charging process. ② MCR 2 arrives after MCR 1 and must wait for $WT_{2j}$ hours until MCR1 departs before it can begin its own charging session. ③ Upon completion of the charging task, MCR 3 enters an idle state and remains inactive until its scheduled departure time $DT_{3j}$.
- Fig. 3. Example of an STN for three tasks assigned to one MCR, showing arrival/departure times, duration, and travel constraints.
- Fig. 4. Simulation environment. The simulation environment is conducted on a real-world parking-lot map measuring 66.0m × 47.6m with 106 parking spaces. MCRs dynamically form multiple coalitions, depicted as dashed colored ellipses, to collaboratively serve EVs. MCR paths are shown as colored straight lines with arrows.
- Fig. 5. Social welfare curves with increasing iterations.
- Fig. 6. Comparison of the average social welfare and computation time of four game-based algorithms under different charging strategy sets. (a) Non-overlapping CF, (b) Unguided OCF, (c) PGG-TS OCF, and (d) SA-OCF.
- Fig. 7. Performance comparison of five scheduling algorithms (mGA, non-overlapping CF, unguided OCF, PGG-TS OCF, and SA-OCF) under varying fleet size and battery capacity. Columns indicate MCR battery capacity $C = 60, 80, 100, 120, 140$ kWh. Rows report: (a) social welfare (CNY) versus number of MCRs; (b) total energy delivered (kWh) versus number of MCRs; (c) total travel cost (CNY) versus number of MCRs; (d) total idle cost (CNY) versus number of MCRs.

## Equations (LaTeX normalized)
**(1)**

$$
D_j = (SOC_j^t - SOC_j^0)\,BC_j
$$

**(2)**

$$
R_j(N_j) = \mu_s D_j \cdot \frac{\log(1+\lambda_j r_j)}{\log(1+\lambda_j)}
$$

**(3)**

$$
a_{ij} = \pi_{ij}\,BC_j,\quad \pi_{ij}\in\Pi
$$

**(4)**

$$
N_j = \{\, i\in N \mid a_{ij}\neq 0 \,\}
$$

**(5)**

$$
M_i = \{\, j\in M \mid a_{ij}\neq 0 \,\}
$$

**(6)**

$$
\begin{cases} DT_{ij} \ge AT_{ij} + DUR_{ij}, \\ DUR_{ij} = \eta_{tot}^{-1} P_d^{-1} a_{ij}, \end{cases}
$$

**(7)**

$$
\eta_{tot} = \eta_c^{ev}\,\eta_d^{mcr}
$$

**(8)**

$$
ST_{ij} = \begin{cases} \max\{AT_{ij},\Phi_{ij}\}, & \text{if } DT_{ij} > \max\{AT_{ij},\Phi_{ij}\}, \\ DT_{ij}, & \text{otherwise}, \end{cases}
$$

**(9)**

$$
\Phi_{ij} = \max_{k\in N_j\setminus\{i\}} \{ z_{ki}^{j} DT_{kj} \}
$$

**(10)**

$$
FT_{ij} = \min\{ DT_{ij},\, ST_{ij} + \eta_{tot}^{-1} P_d^{-1}\Delta D_{ij} \}
$$

**(11)**

$$
\Delta D_{ij} = D_j - \sum_{k\in N_j\setminus\{i\}} z_{ki}^{j}\eta_{tot}P_d(FT_{kj}-ST_{kj})
$$

**(12)**

$$
\bar a_{ij} = \eta_{tot}P_d(FT_{ij}-ST_{ij})
$$

**(13)**

$$
r_j = \sum_{i\in N_j} \bar a_{ij}\,D_j^{-1}
$$

**(14)**

$$
u_{ij}(N_j) = \frac{\bar a_{ij}}{\sum_{i\in N_j}\bar a_{ij}}\,R_j(N_j) - \left(C_{ij}^{idle}+C_{ij}^{chg}\right)
$$

**(15)**

$$
C_{ij}^{idle} = \gamma\left[(ST_{ij}-AT_{ij}) + (DT_{ij}-FT_{ij})\right],\quad i\in N_j
$$

**(16)**

$$
C_{ij}^{chg} = \frac{\mu_g}{\eta_c^{mcr}}\left[\rho\,l_{j',j}+P_d(FT_{ij}-ST_{ij})\right]
$$

**(17)**

$$
\rho\,l_{p_i^k,0} \le C_i^{p_i^k} \le C
$$

**(18)**

$$
EST_{p_i^k} \le AT_{i,p_i^k} \le LFT_{p_i^k} - DUR_{i,p_i^k}
$$

**(19)**

$$
EST_{p_i^k} + DUR_{i,p_i^k} \le DT_{i,p_i^k} \le LFT_{p_i^k}
$$

**(20)**

$$
DT_{i,p_i^k} - AT_{i,p_i^k} \ge DUR_{i,p_i^k}
$$

**(21)**

$$
AT_{i,p_i^{k+1}} - DT_{i,p_i^k} \ge TT_{p_i^k,p_i^{k+1}}
$$

**(22)**

$$
TT_{p_i^k,p_i^{k+1}} = \begin{cases} v^{-1} l_{p_i^k,p_i^{k+1}}, & \text{if Condition 1}, \\ v^{-1}(l_{p_i^k,0}+l_{p_i^{k+1},0}) + P_c^{-1}(C-C_i^{p_i^k}-\rho l_{p_i^k,0})/\eta_c^{mcr}, & \text{if Condition 2}, \\ \infty, & \text{otherwise}, \end{cases}
$$

**(23)**

$$
C_i^{p_i^k} \ge \eta_{tot}^{-1} a_{i,p_i^{k+1}} + \rho\left(l_{p_i^k,p_i^{k+1}} + l_{p_i^{k+1},0}\right)
$$

**(24)**

$$
\begin{cases} C_i^{p_i^k} \ge \rho\,l_{p_i^k,0}, \\ C_i^{p_i^k} < \eta_{tot}^{-1} a_{i,p_i^{k+1}} + \rho\left(l_{p_i^k,p_i^{k+1}} + l_{p_i^{k+1},0}\right), \\ C \ge \eta_{tot}^{-1} a_{i,p_i^{k+1}} + \rho\left(l_{p_i^{k+1},0} + l_{0,p_i^{k+1}}\right), \end{cases}
$$

**(25)**

$$
\max_{A,\{p_i\}_{i\in N}} U = \sum_{j\in M}\sum_{i\in N_j} u_{ij}(N_j)
$$

**(26)**

$$
G = (N,M,CS,R,\Pi,A,\{p_i\}_{i\in N},P)
$$

**(27)**

$$
CS = \{CS_1,CS_2,\ldots,CS_M\}
$$

**(28)**

$$
CS_2 \succ_i CS_1 \iff \begin{cases} u_i(CS_2) > u_i(CS_1), \\ u_i(CS_2)-u_i(CS_1) > \sum_{o\in N\setminus\{i\}}\left(u_o(CS_1)-u_o(CS_2)\right), \end{cases}
$$

**(29)**

$$
\begin{cases} u_i(CS_1)=\sum_{j\in M_i} u_{ij}(N_j^{(1)}), \\ u_i(CS_2)=\sum_{j\in M_i} u_{ij}(N_j^{(2)}), \end{cases}
$$

**(30)**

$$
\sum_{i\in N}u_i(CS_2) \ge \sum_{i\in N}u_i(CS_1)
$$

**(31)**

$$
\sum_{i\in N}u_i(CS^*) \ge \sum_{i\in N}u_i(CS_k)
$$

**(32)**

$$
T \leftarrow \alpha\cdot T
$$

**(33)**

$$
p_i' = p_i \oplus_n \{(j,\pi)\}
$$

**(34)**

$$
\begin{cases} \Delta U_1 = u_i(CS_k') - u_i(CS_k^*), \\ \Delta U_2 = \sum_{i\in N}u_i(CS_k') - \sum_{i\in N}u_i(CS_k^*), \end{cases}
$$

**(35)**

$$
P_a(T,CS_k^*,CS_k') = \begin{cases} 1, & \Delta U_1>0 \ \text{and}\ \Delta U_2>0, \\ e^{\Delta U_1/T}, & \Delta U_1\le 0 \ \text{and}\ \Delta U_2>0, \\ e^{\Delta U_2/T}, & \Delta U_1>0 \ \text{and}\ \Delta U_2\le 0, \\ e^{(\Delta U_1+\Delta U_2)/T}, & \Delta U_1\le 0 \ \text{and}\ \Delta U_2\le 0, \end{cases}
$$

**(36)**

$$
\operatorname{rand}(0,1) < P_a(T,CS_k^*,CS_k')
$$

## Algorithms (normalized pseudocode)

```text
Algorithm 1 SA-OCF algorithm procedure.
1: Input: N, M, α, Tmin, Tmax, Kmax;
2: Initialization: k = 1, k_stable = 0, T = Tmax, CS0 = {∅, ∅, ..., ∅}, p_i = ∅ (i ∈ N);
3: Loop
4:   CS_k = CS_{k-1};
5:   for i ∈ N do
6:       MCR i performs a joining operation using Algorithm 2:
         CS_k = JoiningOperation(p_i, T, CS_k);
7:       MCR i performs a leaving operation using Algorithm 3:
         CS_k = LeavingOperation(p_i, T, CS_k);
8:   end for
9:   if CS_k = CS_{k-1} then
10:      k_stable = k_stable + 1;
11:   else
12:      k_stable = 0;
13:   end if
14:   Update temperature T using Eq. (32);
15:   k = k + 1;
16: End loop if k_stable > Kmax or T < Tmin.
17: Output: stable coalition structure CS*;
```

```text
Algorithm 2 Joining operation for MCR i at k-th iteration.
1: Input: Π, p_i, M, T, CS_k;
2: Initialization: p_i' = p_i, CS_k^* = CS_k;
3: Randomly select a task j ∈ M;
4: for (n, π) ∈ enumerate(|p_i| + 1, Π) do
5:     p_i' = p_i ⊕_n {(j, π)};
6:     Check the feasibility of path p_i' via Algorithm 4;
7:     if feasible then
8:         Derive a new coalition structure CS_k' from p_i' and its schedule;
9:         if rand(0,1) < P_a(T, CS_k^*, CS_k') then
10:            CS_k^* ← CS_k';
11:        end if
12:    end if
13: end for
14: Output: coalition structure CS_k = CS_k^* and p_i';
```

```text
Algorithm 3 Leaving operation for MCR i at k-th iteration.
1: Input: p_i, T, CS_k;
2: Initialization: p_temp_i = p_i, CS_k^* = CS_k;
3: for (j, π_ij) ∈ p_temp_i do
4:     p_i' = p_i \ (j, π_ij);
5:     Check the feasibility of path p_i' via Algorithm 4;
6:     if feasible then
7:         Derive a new coalition structure CS_k' from p_i' and its schedule;
8:         if rand(0,1) < P_a(T, CS_k^*, CS_k') then
9:             CS_k^* ← CS_k';
10:            p_i ← p_i';
11:        end if
12:    end if
13: end for
14: Output: coalition structure CS_k = CS_k^* and p_i.
```

```text
Algorithm 4 Task scheduling algorithm.
1: Input: p_i, S = (Q, ε) for MCR i;
2: Initialization: feasibility = False, S = ∅, T = ∅;
3: Encode all task-related time points and temporal constraints into the STN S;
4: Propagate the STN using Floyd-Warshall algorithm.
5: if STN is consistent then
6:     feasibility = True;
7:     Compute feasible time schedule T along path p_i that minimizes the makespan;
8: end if
9: Output: feasibility, T.
```

## Tables (normalized)

### Table 1. Simulation parameters

| EV Parameters                     | Values         |
|:----------------------------------|:---------------|
| Battery capacity $BC$ (kWh)       | {40,60,80,100} |
| Charging efficiency $\eta_c^{ev}$ | 0.90           |

| MCR Parameters                                      |   Values |
|:----------------------------------------------------|---------:|
| Average velocity $v$ (km/h)                         |      5   |
| Charging power $P_c$ (kW)                           |    100   |
| Discharging power $P_d$ (kW)                        |    100   |
| Charging efficiency $\eta_c^{mcr}$                  |      0.9 |
| Discharging efficiency $\eta_d^{mcr}$               |      0.9 |
| Energy consumption per kilometer $\rho$ (kWh/km)    |      1   |
| Unit grid electricity price $\mu_g$ (CNY/kWh)       |      0.7 |
| Unit service price $\mu_s$ (CNY/kWh)                |      1.4 |
| Unit idle-time penalty coefficient $\gamma$ (CNY/h) |     70   |

| Algorithm Parameters                 |   Values |
|:-------------------------------------|---------:|
| Maximum temperature $T_{\max}$       |  100     |
| Minimum temperature $T_{\min}$       |    0.001 |
| Cooling factor $\alpha$              |    0.96  |
| Maximum stable iterations $K_{\max}$ |   50     |

### Table 2. Benchmark methods comparison

| Method             | MCR → Multi-tasks   | Task → Multi-MCRs   |
|:-------------------|:--------------------|:--------------------|
| mGA                | ✓                   | ✗                   |
| Non-overlapping CF | ✗                   | ✓                   |
| Unguided OCF       | ✓                   | ✓                   |
| PGG-TS OCF         | ✓                   | ✓                   |
| SA-OCF             | ✓                   | ✓                   |

### Table 3. Three different charging strategy sets

| Strategy sets   | Value                                                         |
|:----------------|:--------------------------------------------------------------|
| $\Pi_1$         | {50 %, 100 %}                                                 |
| $\Pi_2$         | {20 %, 40 %, 60 %, 80 %, 100 %}                               |
| $\Pi_3$         | {10 %, 20 %, 30 %, 40 %, 50 %, 60 %, 70 %, 80 %, 90 %, 100 %} |

### Table 4. Simulation results on office parking scenario

<table border="1" class="dataframe">
  <thead>
    <tr style="text-align: right;">
      <th>Capacity_kWh</th>
      <th>MCRs</th>
      <th>SW_mGA</th>
      <th>SW_NCF</th>
      <th>SW_UngOCF</th>
      <th>SW_PGGTS</th>
      <th>SW_SAOCF</th>
      <th>OC_mGA</th>
      <th>OC_NCF</th>
      <th>OC_UngOCF</th>
      <th>OC_PGGTS</th>
      <th>OC_SAOCF</th>
      <th>TC_mGA</th>
      <th>TC_NCF</th>
      <th>TC_UngOCF</th>
      <th>TC_PGGTS</th>
      <th>TC_SAOCF</th>
      <th>CR_mGA</th>
      <th>CR_NCF</th>
      <th>CR_UngOCF</th>
      <th>CR_PGGTS</th>
      <th>CR_SAOCF</th>
    </tr>
  </thead>
  <tbody>
    <tr>
      <td>60</td>
      <td>12</td>
      <td>991.45</td>
      <td>419.84</td>
      <td>1164.80</td>
      <td>1183.98</td>
      <td>1186.69</td>
      <td>1.57</td>
      <td>1.33</td>
      <td>29.53</td>
      <td>11.79</td>
      <td>8.20</td>
      <td>0.850</td>
      <td>0.350</td>
      <td>1</td>
      <td>1</td>
      <td>1</td>
      <td>0.830</td>
      <td>0.341</td>
      <td>0.999</td>
      <td>1.000</td>
      <td>0.999</td>
    </tr>
    <tr>
      <td>60</td>
      <td>16</td>
      <td>1194.41</td>
      <td>570.22</td>
      <td>1156.96</td>
      <td>1182.51</td>
      <td>1172.22</td>
      <td>1.36</td>
      <td>10.21</td>
      <td>37.80</td>
      <td>13.26</td>
      <td>23.55</td>
      <td>1.000</td>
      <td>0.450</td>
      <td>1</td>
      <td>1</td>
      <td>1</td>
      <td>1.000</td>
      <td>0.477</td>
      <td>0.999</td>
      <td>1.000</td>
      <td>1.000</td>
    </tr>
    <tr>
      <td>60</td>
      <td>20</td>
      <td>1194.46</td>
      <td>666.31</td>
      <td>1160.74</td>
      <td>1182.58</td>
      <td>1161.95</td>
      <td>1.31</td>
      <td>13.94</td>
      <td>34.03</td>
      <td>12.32</td>
      <td>33.27</td>
      <td>1.000</td>
      <td>0.550</td>
      <td>1</td>
      <td>1</td>
      <td>1</td>
      <td>1.000</td>
      <td>0.557</td>
      <td>0.999</td>
      <td>0.999</td>
      <td>0.999</td>
    </tr>
    <tr>
      <td>60</td>
      <td>24</td>
      <td>1194.50</td>
      <td>769.17</td>
      <td>1159.15</td>
      <td>1177.81</td>
      <td>1165.23</td>
      <td>1.27</td>
      <td>10.78</td>
      <td>35.19</td>
      <td>17.08</td>
      <td>29.73</td>
      <td>1.000</td>
      <td>0.617</td>
      <td>1</td>
      <td>1</td>
      <td>1</td>
      <td>1.000</td>
      <td>0.641</td>
      <td>0.998</td>
      <td>0.999</td>
      <td>0.999</td>
    </tr>
    <tr>
      <td>80</td>
      <td>12</td>
      <td>993.41</td>
      <td>462.99</td>
      <td>1547.69</td>
      <td>1573.22</td>
      <td>1576.35</td>
      <td>1.68</td>
      <td>1.27</td>
      <td>37.97</td>
      <td>13.87</td>
      <td>12.01</td>
      <td>0.650</td>
      <td>0.263</td>
      <td>1</td>
      <td>1</td>
      <td>1</td>
      <td>0.626</td>
      <td>0.286</td>
      <td>0.998</td>
      <td>0.999</td>
      <td>1.000</td>
    </tr>
    <tr>
      <td>80</td>
      <td>16</td>
      <td>1316.18</td>
      <td>643.40</td>
      <td>1560.73</td>
      <td>1576.11</td>
      <td>1569.53</td>
      <td>2.25</td>
      <td>1.90</td>
      <td>25.32</td>
      <td>11.68</td>
      <td>18.02</td>
      <td>0.838</td>
      <td>0.400</td>
      <td>1</td>
      <td>1</td>
      <td>1</td>
      <td>0.830</td>
      <td>0.394</td>
      <td>0.998</td>
      <td>0.999</td>
      <td>0.999</td>
    </tr>
    <tr>
      <td>80</td>
      <td>20</td>
      <td>1586.44</td>
      <td>718.11</td>
      <td>1547.94</td>
      <td>1571.37</td>
      <td>1573.96</td>
      <td>1.93</td>
      <td>1.89</td>
      <td>37.11</td>
      <td>15.56</td>
      <td>12.09</td>
      <td>1.000</td>
      <td>0.400</td>
      <td>1</td>
      <td>1</td>
      <td>1</td>
      <td>1.000</td>
      <td>0.445</td>
      <td>0.997</td>
      <td>0.999</td>
      <td>0.998</td>
    </tr>
    <tr>
      <td>80</td>
      <td>24</td>
      <td>1586.62</td>
      <td>774.93</td>
      <td>1503.70</td>
      <td>1574.91</td>
      <td>1567.56</td>
      <td>1.75</td>
      <td>2.32</td>
      <td>80.28</td>
      <td>13.45</td>
      <td>20.77</td>
      <td>1.000</td>
      <td>0.475</td>
      <td>1</td>
      <td>1</td>
      <td>1</td>
      <td>1.000</td>
      <td>0.477</td>
      <td>0.996</td>
      <td>1.000</td>
      <td>1.000</td>
    </tr>
    <tr>
      <td>100</td>
      <td>12</td>
      <td>994.15</td>
      <td>436.63</td>
      <td>1934.81</td>
      <td>1969.96</td>
      <td>1964.50</td>
      <td>1.93</td>
      <td>1.15</td>
      <td>42.26</td>
      <td>12.28</td>
      <td>16.17</td>
      <td>0.530</td>
      <td>0.180</td>
      <td>1</td>
      <td>1</td>
      <td>1</td>
      <td>0.502</td>
      <td>0.216</td>
      <td>0.997</td>
      <td>1.000</td>
      <td>0.999</td>
    </tr>
    <tr>
      <td>100</td>
      <td>16</td>
      <td>1322.02</td>
      <td>559.95</td>
      <td>1936.21</td>
      <td>1973.49</td>
      <td>1962.14</td>
      <td>2.11</td>
      <td>1.55</td>
      <td>43.04</td>
      <td>8.75</td>
      <td>20.10</td>
      <td>0.710</td>
      <td>0.240</td>
      <td>1</td>
      <td>1</td>
      <td>1</td>
      <td>0.668</td>
      <td>0.280</td>
      <td>0.998</td>
      <td>1.000</td>
      <td>1.000</td>
    </tr>
    <tr>
      <td>100</td>
      <td>20</td>
      <td>1647.72</td>
      <td>719.33</td>
      <td>1918.04</td>
      <td>1965.74</td>
      <td>1960.58</td>
      <td>2.58</td>
      <td>2.11</td>
      <td>58.32</td>
      <td>16.50</td>
      <td>20.22</td>
      <td>0.850</td>
      <td>0.330</td>
      <td>1</td>
      <td>1</td>
      <td>1</td>
      <td>0.833</td>
      <td>0.357</td>
      <td>0.996</td>
      <td>1.000</td>
      <td>0.999</td>
    </tr>
    <tr>
      <td>100</td>
      <td>24</td>
      <td>1954.24</td>
      <td>859.11</td>
      <td>1923.38</td>
      <td>1959.95</td>
      <td>1916.59</td>
      <td>2.95</td>
      <td>2.37</td>
      <td>55.27</td>
      <td>20.06</td>
      <td>65.34</td>
      <td>0.990</td>
      <td>0.410</td>
      <td>1</td>
      <td>1</td>
      <td>1</td>
      <td>0.987</td>
      <td>0.426</td>
      <td>0.997</td>
      <td>0.999</td>
      <td>1.000</td>
    </tr>
  </tbody>
</table>

### Table 5. Simulation results on shopping mall scenario

<table border="1" class="dataframe">
  <thead>
    <tr style="text-align: right;">
      <th>Capacity_kWh</th>
      <th>MCRs</th>
      <th>SW_mGA</th>
      <th>SW_NCF</th>
      <th>SW_UngOCF</th>
      <th>SW_PGGTS</th>
      <th>SW_SAOCF</th>
      <th>OC_mGA</th>
      <th>OC_NCF</th>
      <th>OC_UngOCF</th>
      <th>OC_PGGTS</th>
      <th>OC_SAOCF</th>
      <th>TC_mGA</th>
      <th>TC_NCF</th>
      <th>TC_UngOCF</th>
      <th>TC_PGGTS</th>
      <th>TC_SAOCF</th>
      <th>CR_mGA</th>
      <th>CR_NCF</th>
      <th>CR_UngOCF</th>
      <th>CR_PGGTS</th>
      <th>CR_SAOCF</th>
    </tr>
  </thead>
  <tbody>
    <tr>
      <td>60</td>
      <td>12</td>
      <td>989.94</td>
      <td>516.88</td>
      <td>1138.84</td>
      <td>1130.01</td>
      <td>1238.40</td>
      <td>1.48</td>
      <td>1.25</td>
      <td>10.16</td>
      <td>8.45</td>
      <td>3.52</td>
      <td>0.650</td>
      <td>0.317</td>
      <td>0.933</td>
      <td>0.900</td>
      <td>0.983</td>
      <td>0.660</td>
      <td>0.330</td>
      <td>0.704</td>
      <td>0.707</td>
      <td>0.761</td>
    </tr>
    <tr>
      <td>60</td>
      <td>16</td>
      <td>1310.42</td>
      <td>715.29</td>
      <td>1370.62</td>
      <td>1407.49</td>
      <td>1481.46</td>
      <td>1.68</td>
      <td>5.73</td>
      <td>27.88</td>
      <td>15.33</td>
      <td>6.32</td>
      <td>0.867</td>
      <td>0.483</td>
      <td>1.000</td>
      <td>1.000</td>
      <td>1.000</td>
      <td>0.873</td>
      <td>0.454</td>
      <td>0.898</td>
      <td>0.932</td>
      <td>0.983</td>
    </tr>
    <tr>
      <td>60</td>
      <td>20</td>
      <td>1500.82</td>
      <td>794.09</td>
      <td>1431.71</td>
      <td>1477.46</td>
      <td>1482.96</td>
      <td>1.55</td>
      <td>13.68</td>
      <td>67.49</td>
      <td>23.76</td>
      <td>17.35</td>
      <td>1.000</td>
      <td>0.467</td>
      <td>1.000</td>
      <td>1.000</td>
      <td>1.000</td>
      <td>1.000</td>
      <td>0.520</td>
      <td>0.996</td>
      <td>0.999</td>
      <td>0.998</td>
    </tr>
    <tr>
      <td>60</td>
      <td>24</td>
      <td>1500.83</td>
      <td>960.16</td>
      <td>1464.45</td>
      <td>1479.18</td>
      <td>1477.34</td>
      <td>1.54</td>
      <td>34.09</td>
      <td>34.33</td>
      <td>18.76</td>
      <td>22.43</td>
      <td>1.000</td>
      <td>0.650</td>
      <td>1.000</td>
      <td>1.000</td>
      <td>1.000</td>
      <td>1.000</td>
      <td>0.634</td>
      <td>0.996</td>
      <td>0.995</td>
      <td>0.997</td>
    </tr>
    <tr>
      <td>80</td>
      <td>12</td>
      <td>991.68</td>
      <td>589.65</td>
      <td>1175.51</td>
      <td>1124.16</td>
      <td>1189.54</td>
      <td>1.76</td>
      <td>15.24</td>
      <td>5.52</td>
      <td>8.30</td>
      <td>3.39</td>
      <td>0.525</td>
      <td>0.263</td>
      <td>0.800</td>
      <td>0.700</td>
      <td>0.713</td>
      <td>0.498</td>
      <td>0.287</td>
      <td>0.528</td>
      <td>0.534</td>
      <td>0.551</td>
    </tr>
    <tr>
      <td>80</td>
      <td>16</td>
      <td>1320.04</td>
      <td>706.79</td>
      <td>1528.49</td>
      <td>1501.42</td>
      <td>1637.22</td>
      <td>1.65</td>
      <td>1.64</td>
      <td>19.90</td>
      <td>11.94</td>
      <td>5.99</td>
      <td>0.675</td>
      <td>0.325</td>
      <td>0.938</td>
      <td>0.887</td>
      <td>1.000</td>
      <td>0.663</td>
      <td>0.342</td>
      <td>0.715</td>
      <td>0.725</td>
      <td>0.749</td>
    </tr>
    <tr>
      <td>80</td>
      <td>20</td>
      <td>1634.48</td>
      <td>850.16</td>
      <td>1768.47</td>
      <td>1778.96</td>
      <td>1889.38</td>
      <td>2.39</td>
      <td>2.53</td>
      <td>34.38</td>
      <td>17.28</td>
      <td>7.68</td>
      <td>0.825</td>
      <td>0.438</td>
      <td>0.988</td>
      <td>0.975</td>
      <td>1.000</td>
      <td>0.821</td>
      <td>0.393</td>
      <td>0.860</td>
      <td>0.881</td>
      <td>0.923</td>
    </tr>
    <tr>
      <td>80</td>
      <td>24</td>
      <td>1945.24</td>
      <td>1030.11</td>
      <td>1929.15</td>
      <td>1953.63</td>
      <td>1972.03</td>
      <td>2.59</td>
      <td>2.64</td>
      <td>50.73</td>
      <td>39.46</td>
      <td>21.93</td>
      <td>0.975</td>
      <td>0.500</td>
      <td>1.000</td>
      <td>1.000</td>
      <td>1.000</td>
      <td>0.977</td>
      <td>0.493</td>
      <td>0.987</td>
      <td>0.999</td>
      <td>1.000</td>
    </tr>
    <tr>
      <td>100</td>
      <td>12</td>
      <td>991.65</td>
      <td>612.07</td>
      <td>1245.57</td>
      <td>1164.81</td>
      <td>1250.60</td>
      <td>1.63</td>
      <td>1.60</td>
      <td>5.56</td>
      <td>6.73</td>
      <td>3.40</td>
      <td>0.420</td>
      <td>0.220</td>
      <td>0.700</td>
      <td>0.590</td>
      <td>0.580</td>
      <td>0.398</td>
      <td>0.234</td>
      <td>0.443</td>
      <td>0.435</td>
      <td>0.454</td>
    </tr>
    <tr>
      <td>100</td>
      <td>16</td>
      <td>1325.01</td>
      <td>717.23</td>
      <td>1574.73</td>
      <td>1475.20</td>
      <td>1625.57</td>
      <td>1.99</td>
      <td>2.55</td>
      <td>9.48</td>
      <td>22.35</td>
      <td>4.97</td>
      <td>0.520</td>
      <td>0.230</td>
      <td>0.820</td>
      <td>0.760</td>
      <td>0.790</td>
      <td>0.531</td>
      <td>0.278</td>
      <td>0.570</td>
      <td>0.565</td>
      <td>0.607</td>
    </tr>
    <tr>
      <td>100</td>
      <td>20</td>
      <td>1643.01</td>
      <td>892.06</td>
      <td>1882.45</td>
      <td>1894.43</td>
      <td>2024.16</td>
      <td>2.26</td>
      <td>8.10</td>
      <td>13.97</td>
      <td>6.55</td>
      <td>7.32</td>
      <td>0.680</td>
      <td>0.340</td>
      <td>0.950</td>
      <td>0.910</td>
      <td>0.970</td>
      <td>0.659</td>
      <td>0.341</td>
      <td>0.702</td>
      <td>0.717</td>
      <td>0.748</td>
    </tr>
    <tr>
      <td>100</td>
      <td>24</td>
      <td>1952.82</td>
      <td>1051.27</td>
      <td>2099.34</td>
      <td>2116.41</td>
      <td>2291.81</td>
      <td>2.68</td>
      <td>2.68</td>
      <td>34.65</td>
      <td>30.99</td>
      <td>6.22</td>
      <td>0.790</td>
      <td>0.410</td>
      <td>0.970</td>
      <td>0.950</td>
      <td>1.000</td>
      <td>0.783</td>
      <td>0.394</td>
      <td>0.813</td>
      <td>0.830</td>
      <td>0.879</td>
    </tr>
  </tbody>
</table>

### Table 6. Simulation results on highway scenario

<table border="1" class="dataframe">
  <thead>
    <tr style="text-align: right;">
      <th>Capacity_kWh</th>
      <th>MCRs</th>
      <th>SW_mGA</th>
      <th>SW_NCF</th>
      <th>SW_UngOCF</th>
      <th>SW_PGGTS</th>
      <th>SW_SAOCF</th>
      <th>OC_mGA</th>
      <th>OC_NCF</th>
      <th>OC_UngOCF</th>
      <th>OC_PGGTS</th>
      <th>OC_SAOCF</th>
      <th>TC_mGA</th>
      <th>TC_NCF</th>
      <th>TC_UngOCF</th>
      <th>TC_PGGTS</th>
      <th>TC_SAOCF</th>
      <th>CR_mGA</th>
      <th>CR_NCF</th>
      <th>CR_UngOCF</th>
      <th>CR_PGGTS</th>
      <th>CR_SAOCF</th>
    </tr>
  </thead>
  <tbody>
    <tr>
      <td>60</td>
      <td>12</td>
      <td>934.10</td>
      <td>695.38</td>
      <td>1033.43</td>
      <td>1035.02</td>
      <td>1190.31</td>
      <td>1.02</td>
      <td>0.83</td>
      <td>6.41</td>
      <td>10.59</td>
      <td>2.19</td>
      <td>0.433</td>
      <td>0.267</td>
      <td>0.650</td>
      <td>0.633</td>
      <td>0.733</td>
      <td>0.407</td>
      <td>0.284</td>
      <td>0.375</td>
      <td>0.395</td>
      <td>0.410</td>
    </tr>
    <tr>
      <td>60</td>
      <td>16</td>
      <td>1218.47</td>
      <td>916.51</td>
      <td>1186.18</td>
      <td>1354.20</td>
      <td>1517.68</td>
      <td>1.25</td>
      <td>1.44</td>
      <td>22.48</td>
      <td>6.63</td>
      <td>2.87</td>
      <td>0.567</td>
      <td>0.383</td>
      <td>0.733</td>
      <td>0.783</td>
      <td>0.933</td>
      <td>0.531</td>
      <td>0.361</td>
      <td>0.445</td>
      <td>0.513</td>
      <td>0.526</td>
    </tr>
    <tr>
      <td>60</td>
      <td>20</td>
      <td>1475.12</td>
      <td>1152.98</td>
      <td>1564.99</td>
      <td>1532.80</td>
      <td>1774.06</td>
      <td>1.43</td>
      <td>1.52</td>
      <td>21.72</td>
      <td>6.75</td>
      <td>3.06</td>
      <td>0.683</td>
      <td>0.467</td>
      <td>0.900</td>
      <td>0.817</td>
      <td>0.983</td>
      <td>0.642</td>
      <td>0.467</td>
      <td>0.599</td>
      <td>0.612</td>
      <td>0.641</td>
    </tr>
    <tr>
      <td>60</td>
      <td>24</td>
      <td>1719.68</td>
      <td>1276.53</td>
      <td>1679.52</td>
      <td>1795.59</td>
      <td>1991.36</td>
      <td>1.78</td>
      <td>2.03</td>
      <td>51.06</td>
      <td>17.36</td>
      <td>4.94</td>
      <td>0.783</td>
      <td>0.533</td>
      <td>0.900</td>
      <td>0.950</td>
      <td>1.000</td>
      <td>0.749</td>
      <td>0.514</td>
      <td>0.673</td>
      <td>0.708</td>
      <td>0.765</td>
    </tr>
    <tr>
      <td>80</td>
      <td>12</td>
      <td>953.35</td>
      <td>741.84</td>
      <td>1116.47</td>
      <td>1087.03</td>
      <td>1169.82</td>
      <td>1.16</td>
      <td>0.99</td>
      <td>2.95</td>
      <td>6.08</td>
      <td>2.19</td>
      <td>0.325</td>
      <td>0.212</td>
      <td>0.562</td>
      <td>0.500</td>
      <td>0.487</td>
      <td>0.302</td>
      <td>0.220</td>
      <td>0.282</td>
      <td>0.293</td>
      <td>0.300</td>
    </tr>
    <tr>
      <td>80</td>
      <td>16</td>
      <td>1252.06</td>
      <td>926.29</td>
      <td>1311.68</td>
      <td>1440.03</td>
      <td>1530.58</td>
      <td>1.53</td>
      <td>1.01</td>
      <td>23.82</td>
      <td>4.00</td>
      <td>2.70</td>
      <td>0.450</td>
      <td>0.237</td>
      <td>0.662</td>
      <td>0.613</td>
      <td>0.662</td>
      <td>0.397</td>
      <td>0.278</td>
      <td>0.348</td>
      <td>0.389</td>
      <td>0.388</td>
    </tr>
    <tr>
      <td>80</td>
      <td>20</td>
      <td>1525.44</td>
      <td>1203.00</td>
      <td>1665.23</td>
      <td>1693.98</td>
      <td>1811.43</td>
      <td>1.61</td>
      <td>1.62</td>
      <td>11.86</td>
      <td>10.50</td>
      <td>3.01</td>
      <td>0.550</td>
      <td>0.362</td>
      <td>0.738</td>
      <td>0.725</td>
      <td>0.750</td>
      <td>0.484</td>
      <td>0.353</td>
      <td>0.448</td>
      <td>0.467</td>
      <td>0.478</td>
    </tr>
    <tr>
      <td>80</td>
      <td>24</td>
      <td>1808.62</td>
      <td>1343.90</td>
      <td>1916.45</td>
      <td>2017.40</td>
      <td>2162.87</td>
      <td>1.74</td>
      <td>1.81</td>
      <td>15.60</td>
      <td>10.35</td>
      <td>4.57</td>
      <td>0.625</td>
      <td>0.375</td>
      <td>0.812</td>
      <td>0.850</td>
      <td>0.963</td>
      <td>0.573</td>
      <td>0.400</td>
      <td>0.524</td>
      <td>0.556</td>
      <td>0.566</td>
    </tr>
    <tr>
      <td>100</td>
      <td>12</td>
      <td>967.83</td>
      <td>774.75</td>
      <td>1113.62</td>
      <td>1146.30</td>
      <td>1165.28</td>
      <td>1.07</td>
      <td>1.02</td>
      <td>4.21</td>
      <td>4.52</td>
      <td>2.24</td>
      <td>0.270</td>
      <td>0.190</td>
      <td>0.440</td>
      <td>0.480</td>
      <td>0.430</td>
      <td>0.244</td>
      <td>0.181</td>
      <td>0.227</td>
      <td>0.238</td>
      <td>0.242</td>
    </tr>
    <tr>
      <td>100</td>
      <td>16</td>
      <td>1247.13</td>
      <td>1004.85</td>
      <td>1415.44</td>
      <td>1483.68</td>
      <td>1618.09</td>
      <td>1.57</td>
      <td>6.49</td>
      <td>5.05</td>
      <td>4.39</td>
      <td>2.99</td>
      <td>0.340</td>
      <td>0.240</td>
      <td>0.540</td>
      <td>0.610</td>
      <td>0.620</td>
      <td>0.315</td>
      <td>0.233</td>
      <td>0.287</td>
      <td>0.307</td>
      <td>0.316</td>
    </tr>
    <tr>
      <td>100</td>
      <td>20</td>
      <td>1549.83</td>
      <td>1192.46</td>
      <td>1733.06</td>
      <td>1766.25</td>
      <td>1909.50</td>
      <td>1.96</td>
      <td>8.45</td>
      <td>9.74</td>
      <td>14.27</td>
      <td>3.47</td>
      <td>0.460</td>
      <td>0.250</td>
      <td>0.670</td>
      <td>0.630</td>
      <td>0.680</td>
      <td>0.391</td>
      <td>0.291</td>
      <td>0.352</td>
      <td>0.382</td>
      <td>0.394</td>
    </tr>
    <tr>
      <td>100</td>
      <td>24</td>
      <td>1838.98</td>
      <td>1364.65</td>
      <td>2066.51</td>
      <td>2020.22</td>
      <td>2252.57</td>
      <td>2.03</td>
      <td>1.93</td>
      <td>11.11</td>
      <td>6.97</td>
      <td>4.60</td>
      <td>0.510</td>
      <td>0.300</td>
      <td>0.780</td>
      <td>0.710</td>
      <td>0.800</td>
      <td>0.464</td>
      <td>0.325</td>
      <td>0.432</td>
      <td>0.445</td>
      <td>0.462</td>
    </tr>
  </tbody>
</table>

## Full transcription (page-by-page)

### Page 1

```text
Contents lists available at ScienceDirect

Applied Energy
journal homepage: www.elsevier.com/locate/apen

Game-based scheduling of mobile charging robots for electric vehicle
charging: A relay-like scheme
Qiuyang Fang a ID, Chunyan Zhang a ID, Chen Wang b, c ID, Guangming Xie c, d ID, Jianlei Zhang a,* ID
a College of Artificial Intelligence, Nankai University, Tianjin, 300071, Tianjin, China
b

National Engineering Research Center of Software Engineering, Peking University, Beijing, 100871, Beijing, China

c State Key Laboratory for Turbulence and Complex Systems, Intelligent Biomimetic Design Lab, College of Engineering, Peking University, Beijing, 100871, Beijing, China
d

Institute of Ocean Research, Peking University, Beijing, 100871, Beijing, China

HIGH LIGHTS
• Relay-like EV charging via Mobile Charging Robots (MCRs) enables task splitting.
• MCR tasking is modeled as an Overlapping Coalition Formation (OCF) game.
• SA-OCF algorithm enables decentralized, energy-aware task allocation.
• Enhanced MCR scheduling achieves better energy usage and higher social welfare.

ARTICLE INFO

ABS TRACT

Keywords:
EV charging
Mobile charging robot
Multi-robot system
Overlapping coalition formation
Game theory
Resource allocation

The growing demand for electric-vehicle (EV) charging poses substantial challenges for power grids. In response,
mobile charging robots (MCRs) have emerged as a promising solution for flexible, on-demand energy delivery.
This paper proposes a novel relay-like EV-charging scheme for public parking facilities, in which long-duration
charging tasks are decomposed into sequential time slots and collaboratively managed by multiple MCRs. The
coordination problem is cast as an overlapping coalition formation (OCF) game with a holistic-altruistic preference order, enabling MCRs to autonomously allocate energy and cooperatively fulfill charging tasks while
balancing self-interest and social welfare. Based on this framework, we develop a simulated annealing–inspired,
decentralized OCF (SA-OCF) algorithm that effectively explores the solution space under stringent energy and
time-window constraints and converges to a stable overlapping coalition structure. Simulation results show that
the proposed approach outperforms baseline methods in social welfare and energy delivered. Furthermore, the
algorithm exhibits strong scalability across scenarios with heterogeneous EV-charging behaviors.

1. Introduction
Electric vehicles (EVs) are anticipated to achieve widespread deployment in the foreseeable future is likely due to their compatibility with
renewable energy sources and their superior energy efficiency [1–4].
However, the aggregated and intermittent charging demands of large
EV fleets can impose significant supply capacity constraints on power
distribution networks and pose considerable challenges to grid stability
[1,2]. Moreover, limited charging infrastructure remains a critical bottleneck to rapid EV deployment [3,4]; for example, delays often arise
when chargers are occupied for longer than necessary.

To address the aforementioned challenges, numerous charging
schemes have been proposed in the literature to enhance the EV charging experience. These approaches can be primarily categorized into
two directions. The first direction involves upgrading charging infrastructure, such as deploying more fixed charging stations (FCSs) [5,6],
implementing fast chargers [7], and developing contactless charging
as well as battery swapping technologies [8,9]. Although these solutions can effectively enhance the service capacity of both individual
charging units and entire networks, they typically require significant capital investments in the early stages [10]. The other direction

*

Corresponding author.
Email addresses: qiuyangfang@mail.nankai.edu.cn (Q. Fang), zhcy@mail.nankai.edu.cn (C. Zhang), wangchen@pku.edu.cn (C. Wang),
xiegming@pku.edu.cn (G. Xie), jianleizhang@nankai.edu.cn (J. Zhang).

https://doi.org/10.1016/j.apenergy.2025.126956
Received 3 August 2025; Received in revised form 30 September 2025; Accepted 18 October 2025
Available online 5 November 2025
0306-2619/© 2025 Elsevier Ltd. All rights are reserved, including those for text and data mining, AI training, and similar technologies.
```


### Page 2

```text
Nomenclature
Abbreviations
CF
Coalition Formation
EV
Electric Vehicle
FCS
Fixed Charging Station
ISO
Independent System Operator
MCR
Mobile Charging Robot
MCS
Mobile Charging Station
MES
Mobile Energy Storage
OCF
Overlapping Coalition Formation
QoE
Quality of Experience
SoC
State of Charge
VANET Vehicular Ad Hoc Network
Symbols
a-ij
ηcev
ηcmcr
ηdmcr
ηtot
λj
pi
pki
CS
M
Mi
N

Set of MCRs assigned to task j
Unit grid price
Unit service price
Discrete strategy set of each MCR
Charging strategy of MCR i at task j
Unit-distance energy consumption of MCR
Energy allocated by MCR i to EVj
Arrival time of MCR i at task j
Battery capacity of EVj
Battery capacity of MCR

Nj
μg
μs
π
πij
ρ
aij
ATij
BCj
C
pk

Actual energy delivered by MCR i to EVj
EV-side charging efficiency
Charging efficiency of MCR
Discharging efficiency of MCR
End-to-end charging efficiency
Sensitivity coefficient of task j
Task execution sequence of MCR i
k-th task in pi
Overlapping coalition structure
Set of EVs
Task bundle of MCR i
Set of MCRs

Ci i
Dj
DTij
DU Rij
Eij
ESTj
EVj
F Tij
LF Tj
Pc
Pd
rj
SOCj0
SOCjt
STij
T Tpk ,pk+1

Residual energy of MCR i after the k-th task
Charging demand of task j
Departure time of MCR i at task j
Assigned charging duration of MCR i at task j
Travel energy cost of MCR i at task j
Earliest start time of task j
Electric vehicle submitting the j-th charging task
Charging finish time of MCR i at task j
Latest finish time of task j
Recharging power of MCR
Discharging power of MCR
Completion ratio of task j
Initial state of charge of EVj
Target state of charge of EVj
Charging start time of MCR i at task j
Travel time of MCR i between pki and pik+1

T Wj

Charging time window of task j

i

focuses on improving the scheduling and optimization of EV charging operations. Efforts in this area include optimizing charging station deployment [11,12], implementing robust power management in
vehicle-to-grid networks [2,13], and designing pricing models to mitigate EV overstay behavior in charging stations [14]. Such approaches
can effectively enhance resource utilization, lower operating costs, and
improve overall charging service quality. Nevertheless, non-cooperative
behavior among EV users may negatively impact operational efficiency [15].
Recently, mobile charging robots (MCRs) have emerged as a promising alternative for providing flexible charging services to EVs. Unlike
FCS, an MCR integrates battery energy storage, navigation and dynamic
control systems, and communication devices, enabling autonomous
operation in parking facilities, coordination with other units, and localized on-demand charging [16]. These capabilities support deployment
across varied scenarios. First, the mobility and service flexibility of
MCRs can directly solve the EV overstay problem often observed in
FCSs. A typical scenario is office buildings, where vehicles are generally parked for the entire workday and system utilization is low
[10,17]. By decoupling charging from parking, MCR deployment in
such settings can improve utilization of existing infrastructure. Second,
as off-grid supply units, MCRs can buffer EV charging from the distribution network, reducing stress from large-scale uncoordinated charging, particularly during peak-load periods. This feature makes them
well-suited for deployment in scenarios with high-density charging
demands such as highway service areas and shopping malls, to alleviate range anxiety and enhance charging reliability in areas where
fixed stations are sparse or overloaded, thus stabilizing the distribution
networks [18,19]. Consequently, this novel charging paradigm demonstrates broad applicability and motivates further investigation in this
paper.

i

1.1. Related works
This literature review categorizes existing studies on MCRs and
similar mobile charging schemes, such as mobile energy storage (MES)
and mobile charging stations (MCSs), into two primary groups based on
the scheduling methodologies.
The first group comprises centralized approaches [10,17,20–27]. For
example, a pricing mechanism is designed in [20] for a hybrid business
model integrating fixed stations and MCS; [21] proposes a two-stage
framework to improve photovoltaic utilization along expressways by
coordinating EV charging and MES truck dispatch; and [22] employs a
rolling-horizon approach to route MESs in coupled transportation-power
networks. Optimization-based methods, including heuristic [23] and
mixed-integer linear programming (MILP) techniques [24,25], have also
been widely explored in MCS-related research. Recent MCS works, such
as [28], introduce two-stage models for truck MCS (TMCS) coordinating
charging and energy arbitrage with robust handling of demand uncertainty via the lookahead rolling horizon-value function approximation
(LRH-VFA) and the distributionally robust optimization (DRO), while
[29] employs multi-scenario stochastic optimization for MCS routing
with auction-based allocation. Although these schemes explore various
optimization methods for deploying and scheduling MES or MCSs, they
are less adaptable and flexible than MCRs due to limited autonomous
mobility. Recently, MCR-specific scheduling has attracted growing attention. A Markov-based MCR deployment scheme is proposed in [10]
and further extended in [26] with demand-responsive adaptations. A
two-stage optimization framework is introduced in [17] and solved using a Gurobi solver to jointly optimize hybrid MCR and fixed-charger
scheduling. In [27], a multi-objective mixed-integer nonlinear programming (MINLP) model is developed to leverage MCRs for enhancing
voltage resilience in distribution systems. Despite their optimization
power, these centralized models often rely on a central authority’s access
```


### Page 3

```text
to full data from MCR system and customers, which introduces single
points of failure, scalability bottlenecks, and potential privacy concerns
when applied in large-scale, real-world deployments [18]. In contrast
to these centralized MCS-focused methods, which often target larger
truck-based units for energy arbitrage or uncertainty management, our
work emphasizes decentralized coordination for agile robot-based MCRs
in parking scenarios, enabling relay-like overlapping coalitions among
agents.
The second group focuses on decentralized or distributed solutions
[18,19,30,31]. For example, Zhang et al. [18] introduce a gametheoretic framework that enables distributed interaction between MCRs
and EVs, while [19] explores voltage restoration strategies in distributed
networks. A consensus-based approach is proposed in [30] to improve
coordination among MCRs. In our previous work [31], the MCR scheduling problem is modeled as a coalition formation (CF) game and solved
using a decentralized auction-based algorithm. Compared to centralized
approaches, decentralized or distributed methods offload computational
burdens to individual MCRs, enabling them to make decisions based on
local information. This not only improves system scalability but also
enhances fault tolerance and responsiveness in dynamic environments.
However, these schemes rely on simplified assumptions, such as modeling each EV’s charging request as an indivisible task served by a single
MCR. These assumptions limit cooperation among MCRs and may degrade service quality, especially when MCRs have constrained capacities
and EVs require service within strict time windows. This limitation highlights the need for a more flexible scheduling paradigm, in which each
EV charging request can be jointly served by multiple MCRs. In such a
scheme, each MCR is able to fully utilize its limited energy and temporal resources to cooperate with others, thereby enhancing task coverage
and improving overall service quality.

The remainder of this paper is organized as follows. Section 2 details
the problem formulation. Section 3 models the MCR scheduling problem
as an OCF game and provides a thorough analysis. Section 4 presents
the SA-OCF algorithmic framework. Simulation settings and results are
discussed in Section 5, followed by concluding remarks in Section 6.
2. System model and problem formulation
In this study, we consider an EV charging scenario where MCRs are
deployed to deliver on-demand charging services. As illustrated in Fig. 1,
EVs arrive stochastically and submit time-constrained charging requests
through cellular or vehicular ad hoc networks (VANETs). These requests
are periodically collected and broadcast to MCRs by an independent system operator (ISO), which functions solely as an information collector
and signaling relay, without participating in MCR scheduling or control
[32]. For modeling simplicity, we assume that all MCRs have identical
configurations and independent computing capabilities. Each MCR has
a designated charging base, typically located at the edge of the service
area or near an energy hub, where it can return for battery recharging.
To improve system scalability and flexibility, each MCR is allowed
to handle multiple charging requests and cooperate with others on individual tasks, enabling task-specific overlapping coalitions to emerge
naturally. Our objective is to develop a multi-robot task-allocation
and scheduling framework that enables MCRs to collaboratively fulfill
EV charging requests within their time windows and maximize social
welfare, defined as total net operational profit.
2.1. EV modeling
Let M = {1, 2, ... , M} denote the set of M EV charging tasks. Each task j Є M is characterized by the tuple
(EVj , BCj , ESTj , LF Tj , SOCj0 , SOCjt ), where EVj denotes the target EV
to be charged, BCj is the battery capacity of EVj (in kWh), ESTj and
LF Tj represent the earliest start time and latest finish time of the charging task, respectively, and SOCj0 and SOCjt denote the initial and target
SoC, expressed as percentages of the battery capacity. The charging
time window for task j is defined as T Wj = {ESTj , LF Tj }, and the
corresponding energy demand Dj is computed as

1.2. Contribution
Building on the above observations, this article introduces a relaylike decentralized scheduling framework that coordinates multiple
MCRs to deliver charging services in public parking facilities. Within this
framework, each MCR can independently determine its collaboration
strategy, including which EVs to serve, which other MCRs to cooperate
with, and how much energy to deliver, based on its own task schedule
and resource availability. From the EV’s perspective, the charging process is carried out sequentially by multiple MCRs, resembling a relay
race, where the EV’s charging demand is fulfilled in segments over time.
A summary of contributions is listed as follows:

Dj = (SOCjt - SOCj0 ) . BCj .

• We formulate EV charging task allocation and scheduling as an
overlapping coalition formation (OCF) game. Under this framework,
MCRs can autonomously determine their resource allocation and
form overlapping coalitions to jointly serve EVs, offering enhanced
flexibility in assigning tasks and managing schedules.
• We introduce a holistic altruistic preference order designed to promote cooperative behavior among MCRs and maximize social welfare, which is defined as total operating profit. Under this preference
order, we rigorously prove the existence of a stable coalition structure, in which no MCR possesses an incentive to unilaterally alter its
coalition membership.
• We propose a simulated annealing-inspired OCF (SA-OCF) algorithm
that performs decentralized coalition formation and systematically
explores high-quality schedules subject to task time-window and
MCR energy constraints. Unlike combinations of standard algorithms, SA-OCF is tailored to the OCF game with a holistic-altruistic
preference order, enabling efficient search over feasible coalition
structures in constrained multi-robot settings.
• We empirically evaluate SA-OCF against multiple baselines and
observe consistent gains in social welfare and energy delivered.
Extensive simulations across varied application scenarios further
demonstrate its adaptability and scalability.

(1)

Fig. 1. An example of a parking facility where MCRs deliver charging services
for EVs. Green-marked vehicles are either being charged or fully charged, while
black-marked vehicles are new arrivals or unassigned, awaiting charging or
parking allocation.
```


### Page 4

```text
To encapsulate the diminishing marginal utility characteristic of EV
charging behavior [33], we define the QoE for an EV as follows:
Rj (Nj ) = μs Dj .

log(1 + λj rj )
log(1 + λj )

,

(2)

where Nj is the set of MCRs assigned to charging task j, μs denotes
the unit service price for EV charging, and rj Є [0, 1] represents the
completion ratio of the requested demand Dj delivered before departure. The parameter λj > 0 is a sensitivity coefficient that characterizes
an EV user’s tolerance toward incomplete charging. It is noteworthy
that this logarithmic formulation exhibits monotonic increasing and concave properties with respect to rj , effectively capturing the diminishing
marginal willingness-to-pay of EV users as the completion ratio increases
[33]. Additionally, the formulation characterizes the economic revenue
obtained by the assigned MCRs while embedding user-perceived QoE.

Fig. 2. An example of a group of three MCRs working together to increase an
1 MCR 1 arrives first and initiates the charging
EV’s SOC from 0 % to 100 %. ○
2 MCR 2 arrives after MCR 1 and must wait for W T2j hours until MCR1
process. ○
3 Upon completion of the
departs before it can begin its own charging session. ○
charging task, MCR 3 enters an idle state and remains inactive until its scheduled
departure time DT3j .

2.2. MCR modeling
Let N = {1, 2, ... , N} denote the set of MCRs, each of which is initially fully charged and equipped with a lithium-ion battery of capacity
C (kWh). In this study, MCRs are allowed to collaborate to fulfill individual EV charging tasks. Such cooperative behavior enables more flexible
scheduling strategies and contributes to improved QoE for EV users. It is
assumed that each MCR can serve an EV according to a charging strategy π Є π, where π denotes the discrete set of available SoC increment
levels. For instance, π = {0 %, 20 %, 40 %, 60 %} specifies possible contributions to the SoC increase of the target EV, depending on resource
availability and task assignment.
Consequently, we define the resource allocation matrix AN×M =
[aij ]N×M , where aij denotes the energy allocated by MCR i to EVj ,
calculated as:

whether MCR k arrives earlier than MCR i at task j. The charging start
time STij of MCR i at task j is then defined as
{
STij =

πij Є π.

(3)

(4)

and the task bundle of MCR i can be denoted as:
Mi = {j Є M | aij ≠ 0}.

DTij ≥ ATij + DU Rij ,
-1 P -1 a ,
DU Rij = ηtot
ij
d

(5)

(10)

where the residual demand ΔDij is computed as
ΔDij = Dj -

∑

zjki ηtot Pd (F Tkj - STkj ).

(11)

kЄNj \{i}

Furthermore, the actual energy provided by MCR i to EVj depends
on the duration of its charging service and is calculated as

(6)

(12)

a-ij = ηtot Pd (F Tij - STij ).
Accordingly, the completion ratio rj is defined as

where DU Rij is the assigned charging duration, Pd is the discharge
power of the MCR, and the end-to-end efficiency from the MCR battery
to the EV battery is
ηtot = ηcev ηdmcr

(9)

-1 -1
F Tij = min{DTij , STij + ηtot
Pd ΔDij },

Finally, let pi denote the ordered path (task execution sequence) assigned to MCR i, i.e., a permutation of the tasks in Mi together with
their associated charging strategies. Let ATij and DTij be the scheduled
arrival and departure times of MCR i (i Є Nj ) at task j along pi . Then
{

max {zjki DTkj }

kЄNj \{i}

denotes the latest departure time among all MCRs that arrived before
MCR i at task j. The charging finish time F Tij of MCR i at task j is then
determined by the minimum of its scheduled departure time and the
time required to complete the remaining charging demand:

Accordingly, the set of MCRs Nj assigned to EVj is defined as
Nj = {i Є N | aij ≠ 0},

(8)

DTij , Otherwise,

where
Φij =

aij = πij . BCj ,

max{ATij , Φij }, If DTij > max{ATij , Φij },

rj =

∑
iЄNj

a-ij . Dj-1 .

(13)

In this work, we adopt a proportional-fairness rule [34] to distribute
task revenue among MCRs. The net profit of MCR i serving EV j is

(7)

with ηcev , ηdmcr Є (0, 1) respectively denoting the EV-side charging efficiency and MCR-side discharging efficiency.
Given the empirical fact that mainstream EVs typically have a single
charging port, we reasonably assume that an EV cannot be serviced by
multiple MCRs simultaneously. When multiple MCRs are assigned to the
same EV, the “first-come, first-served” principle determines their service
order. Consequently, any MCR arriving later must wait until the earlier
one has completed its service before it can begin charging, as illustrated
in Fig. 2. Let the binary variable zjki Є {0, 1} (k, i Є Nj and k ≠ i) indicate

uij (Nj ) = ∑

a-ij

iЄNj a-ij

(
)
chg
. Rj (Nj ) - Cijidle + Cij ,

(14)

where the first term is the revenue allocated to MCR i; Cijidle is the opportunity cost of MCR i’s idle time at task j, including both the waiting
time before charging and the loitering time after completion, given by
[
]
Cijidle = γ (STij - ATij ) + (DTij - F Tij ) ,

i Є Nj ,

(15)
```


### Page 5

```text
pk
which covers the case where Ci i

is insufficient to complete the next
task directly but sufficient to return to base, fully recharge, and then
complete the next task.
The detailed method for constructing a path that satisfies both the
energy and temporal constraints is presented in Section 4.2. Note that
this paper concentrates on the scheduling layer for MCRs. For each robot
and its path pi , we build a simple temporal network (STN) that encodes
energy and temporal constraints (see Eqs. (17)–(22)). From the STN we
then extract a certified arrival–departure timeline (ATij , DTij ) for execution, under the simplifying assumption that the platform’s low-level
motion module can accurately track waypoints and timing. In practical deployments, this motion layer can be realized with well-established
path/trajectory planning and tracking techniques [35,36].

where γ > 0 is the unit idle-time penalty (e.g., monetary cost per unit
chg
time). Cij represents charging-related energy cost incurred by MCR i
when serving task j, formulated as
μg [
(
)]
chg
(16)
Cij = mcr ρ lj ' ,j + Pd F Tij - STij ,
ηc
where μg denotes the unit grid electricity price, ηcmcr Є (0, 1) is the MCR
charging efficiency, and ρ denotes the MCR’s propulsion energy consumption per unit distance. lj ' ,j denotes the shortest collision-free travel
distance from the location of the preceding task j ' to that of task j, com(
)
puted by the A* path planner. Pd F Tij -STij gives the energy delivered
during the charging session at rated power Pd , where STij and F Tij are
the start and finish times, respectively.
Given the above model, the central problem is to compute a feasible
path pi for each MCR i Є N , which in turn fixes the task-specific service
start and finish times. For uninterrupted operation, each path must satisfy the energy and time-window constraints to ensure successful task
execution.
(1) Energy constraints: To ensure that an MCR can safely return
to base for recharging, it must retain sufficient energy after completing
each task on pi . This requirement is enforced by
pk

ρ lpk ,0 ≤ Ci i ≤ C,

2.3. Problem formulation
In this study, the objective is to optimize the cooperative grouping
and scheduling strategy of MCRs to maximize social welfare. Here, social welfare is defined as the total net profit achieved by all MCRs across
their assigned charging tasks. Specifically, the MCR scheduling problem is formulated as a joint optimization over the resource allocation
matrix AN×M and the corresponding execution paths {pi }iЄN , with the
objective of maximizing the total net profit of MCRs, as given by:

(17)

i

max

where k Є {0, 1, ... , |pi | - 1}, pki denotes the k-th task, and lpk ,0 denotes

A,{pi }iЄN

i

the shortest collision-free travel distance from location of pki to the base
station.
(2) Temporal constraints: First, because multiple MCRs cannot
charge the same EV simultaneously, the charging start and finish times
of MCR i at the k-th task on pi are given by Eqs. (8) and (10). Second,
the charging session of MCR i at the k-th task (k Є {0, 1, ... , |pi | - 1})
must lie within the user-specified time window, which requires
ESTpk ≤ ATi,pk ≤ LF Tpk - DU Ri,pk ,

(18)

ESTpk + DU Ri,pk ≤ DTi,pk ≤ LF Tpk ,

(19)

DTi,pk - ATi,pk ≥ DU Ri,pk .

(20)

i

i

i

i

i

i

i

i

i

i

i

i

i

i

uij (Nj ),

(25)

iЄNj jЄM

3. Game-based overlapping coalition formation
The optimization problem in (25) is NP-hard due to the presence of
integer variables for task assignment, nonlinear utility functions, and
tightly coupled time-energy constraints. These factors cause the solution space to expand exponentially with the number of MCRs and tasks,
making exact solutions computationally expensive in a centralized approach. To address this, we reformulate the problem as an OCF game,
where each MCR independently makes decisions through interaction,
aiming to maximize social welfare in a cooperative manner. This approach allows us to solve the MCR scheduling problem in a distributed
or decentralized manner, thereby distributing the computational burden
among MCRs.

(21)

i

3.1. OCF game model

where T Tpk ,pk+1 denotes the travel time required for MCR i to move from
i

∑ ∑

subject to (8), (10), (17), (18), (19), (20), and (22).

Finally, the interval between consecutive tasks on pi must allow MCR i
to travel from the previous task to the next; thus,
ATi,pk+1 - DTi,pk ≥ T Tpk ,pk+1 ,

U=

i

task pki to task pki +1 and is computed as
{v-1 . l
,
pki ,pk+1
|
i
|
|v-1 . (lpk ,0 + lpk+1 ,0 )+
T Tpk ,pk+1 = {
i
i
k
i i
|P -1 . (C - C pi - ρl k )/η mcr ,
pi ,0
c
c
i
|
|∞
}

Given that each MCR has independent computing capabilities, the
proposed scheduling problem can be naturally framed as a distributed or
decentralized multi-robot decision process, where MCRs independently
make decisions based on information exchange to maximize the objective function. In this context, the OCF game can provide a framework for
guiding MCR decision-making. The OCF game is a type of cooperative
game where players can simultaneously participate in multiple coalitions according to their preferences, rather than being restricted to a
single coalition as in traditional cooperative games. This framework allows players to allocate their resources across different tasks and earn
revenue from the coalitions they join, resulting in an overlapping coalition structure [34,37]. This structure aligns with the problem defined
in Section 2. Furthermore, the distributed nature of OCF games enables
us to model our problem as a decentralized decision-making process.
Based on this, we reformulate the MCR scheduling problem within the
OCF game framework, where MCRs, acting as players, independently
decide which other MCRs to collaborate with to complete tasks, based
on their preferences, with the goal of maximizing social welfare as defined in (24). Consequently, the OCF game model can be represented by
the tuple:

If Condition 1;

If Condition 2;

(22)

Otherwise;

where v denotes the travel speed of MCR i and Pc is the charging power.
Condition 1 is
(
)
pk
-1
Ci i ≥ ηtot
. ai,pk+1 + ρ . lpk ,pk+1 + lpk+1 ,0 ,
i

i

i

(23)

i

pk

which means that the residual energy Ci i of MCR i is sufficient to complete the next task and return directly to base from the subsequent task.
Condition 2 is
{ pki
|Ci ≥ ρ lpk ,0 ,
i
| pk
(
)
-1 a
{Ci i < ηtot
+ ρ lpk ,pk+1 + lpk+1 ,0 ,
i,pk+1
i
i i
i)
(
|
-1 a
+ ρ lpk+1 ,0 + l0,pk+1 ,
|C ≥ ηtot
i,pk+1
i
i
i
}

(24)

G = (N , M, CS, R, π, A, {pi }iЄN , P),

(26)
```


### Page 6

```text
where N denotes the set of players, which specifically refers to the MCRs
in this work, M represents the set of charging tasks, CS is the overlapping coalition structure formed by MCRs, R is the task revenue defined
in Eq. (2), π denotes the set of feasible discrete charging strategies, A is
the resource allocation matrix across MCR-task pairs, {pi }iЄN captures
the planned execution routes of MCRs, and P represents the preference
profiles that guide individual coalition participation decisions. We next
introduce key concepts from OCF game theory that support the design
of stable and efficient coalition structures.

its own utility through joining or leaving operations only when the improvement outweighs the total utility loss experienced by other players.
Intuitively, this ensures that each individual decision not only benefits
the player itself but also leads to a net gain in global social welfare.
Such order aligns with considered scenario with objective of maximizing overall social welfare defined in Eq. (25). The holistic altruistic order
is formally defined as follows.
Definition 5 (Holistic altruistic order). For any MCR i Є N and
two overlapping coalition structures CS 1 = {CSj(1) }
and C S 2 =
jЄM

Definition 1 (Overlapping coalition structure). An Overlapping coalition structure CS specifies how multiple coalitions are organized, including details of resource allocation and temporal scheduling information.
In this work, we formally define CS as

{CSj(2) }

altruistic order satisfies:
CS 2 >i CS 1 ↔
{u (CS ) > u (CS );
i
| i
{u (CS ) - u (CS ) > ∑ (u (CS ) - u (CS )),
i
o
o
| i
oЄN \{i}
}

(27)

CS = {CS1 , CS2 , ... , CSM },

where each element CSj = (Nj , Aj , Tj ), with j Є M, denotes the
coalition associated with charging task j and comprises Nj , the set of
MCRs assigned to task j; Aj = {aij }iЄN , the resource allocation vector,

j

{ui (CS 1 ) = ∑ uij (N (1) );
j
|
jЄMi
∑
{
(2)
u
(CS
)
=
u
(N
ij
| i
j ).
jЄMi
}

and departure times of MCR i at task j along its execution path pi .
Since each coalition corresponds to a distinct EV charging task, the
total number of coalitions satisfies |CS| = M . Some coalitions may remain empty if their associated tasks are not assigned to any MCRs. The
revenue of each coalition and the individual utilities allocated to MCRs
are defined in Eqs. (2) and (14), respectively.

(29)

where Nj(1) is the member set of coalition CSj(1) , and Nj(2) is the member
set of coalition CSj(2) .

Definition 2 (Preference relation). For each MCR i Є N , a preference
profile Pi Є P defines a complete, reflexive, and transitive binary relation over the set of possible overlapping coalition structures. Given two
coalition structures CS 1 and CS 2 , the relation CS 1 >i CS 2 denotes that
MCR i strictly prefers CS 1 to CS 2 .

3.2. Stability analysis
Stability is a fundamental concept in OCF games, essential for ensuring the existence and sustainability of feasible coalition structures.
In this subsection, we examine the existence of a Nash-stable coalition
structure under the proposed holistic altruistic order. Specifically, we focus on the notion of o-profitable stability, which defines a state in which
no MCR has an incentive to unilaterally improve its utility by joining or
leaving a coalition [38]. The formal definition is given below:

Definition 3 (Joining Operation). Given a coalition structure CS 1 =
{CSj(1) }
, a joining operation occurs when an MCR i decides to join
j ЄM

an existing coalition associated with task j. In doing so, MCR i selects
a charging strategy πij Є π, and collaborates with the current members
of coalition CSj(1) Є CS 1 to jointly serve EVj . This operation results in
jЄM

(28)

where ui (CS 1 ) and ui (CS 2 ) denote the total net profits of MCR i under
structures CS 1 and CS 2 , respectively, given by

j

where aij is the amount of energy that MCR i allocates to task j; and
Tj = (ATij , DTij )iЄN , the task timeline specifying the scheduled arrival

a new coalition structure CS 2 = {CSj(2) }

j ЄM

resulting from joining or leaving operations, the holistic

Definition 6 (o-profitable deviation). Given an overlapping coalition
structure CS 1 = {CSj(1) }
, an MCR i’s deviation (joining or leaving

, in which MCR i becomes

j ЄM

part of coalition CSj(2) .

coalition CSj(1) ) is termed o-profitable if the total system utility does not
decrease:

Definition 4 (Leaving Operation). Given a coalition structure CS 1 =
{CSj(1) }
, a leaving operation occurs when an MCR i decides to with-

∑

draw from a coalition associated with task j. Specifically, MCR i removes
task j from its path and terminates its collaboration with the current
members of coalition CSj(1) Є CS 1 responsible for serving EVj . This

iЄN

jЄM

ui (CS 2 ) ≥

∑

ui (CS 1 ).

(30)

iЄN

As defined in Definition 6, any o-profitable deviation results in a
non-decreasing total system utility. An OCF game reaches an o-stable
state when no MCR can perform such a deviation, and the corresponding
coalition structure CS * is said to belong to the o-core [38]. Based on this
notion of stability, we present the following theorem:

operation yields a new coalition structure CS 2 = {CSj(2) }
, where
jЄM
(2)
i Ɇ Nj .
In OCF games, the decision-making process (i.e., joining or leaving
operations) of players regarding coalition formation is governed by preference relations [34,37]. Two commonly adopted preference relations
are the selfish order and the Pareto order [34]. The selfish order prioritizes the player’s own utility improvement, regardless of the impact
on others, which may lead to suboptimal outcomes in terms of social
welfare. In contrast, the Pareto order requires that no player’s utility is
diminished in the transition, thereby promoting fairness and cooperation. However this strict constraint makes it difficult to find an optimal
coalition structure.
To better balance self-interest and system-level efficiency, especially
in a resource-constrained and partially cooperative scenario such as
multi-tasking MCR scheduling, we introduce a novel preference relation
termed the holistic altruistic order. This order allows an MCR to improve

Theorem 1. In the proposed OCF game, there exists at least one stable
coalition structure CS * under the proposed holistic altruistic order.
Proof (Proof of Theorem 1). Let the initial coalition structure of the
proposed OCF game be CS 0 , and denote the coalition structure at iteration k as CS k . Define F = {CS 0 , CS 1 , ... , CS K } as the set of coalition
structures after K iterations, where each iteration corresponds to an
MCR performing a joining or leaving operation. Under the holistic altruistic order, an MCR may modify its coalition membership only if the
operation increases its own utility and the individual utility gain exceeds
the total utility losses of others, as defined in Definition 5. Thus, each
allowed operation preserves or improves the total system utility. Since
the numbers of MCRs, tasks, and feasible charging strategies are finite,
```


### Page 7

```text
the set F is finite, ensuring that the iterative process cannot continue
indefinitely and must converge to a stable coalition structure CS * .
Once a stable coalition structure CS * is reached, this means the
condition
∑
∑
ui (CS k )
(31)
ui (CS * ) ≥
iЄN

Algorithm 1 SA-OCF algorithm procedure.
1: Input: N , M, α, Tmin , Tmax , Kmax ;
2: Initialization: k = 1, kstable = 0, T = Tmax , CS 0 = {ꬾ, ꬾ, ... , ꬾ}, pi = ꬾ

(i Є N );
3: Loop
4: CS k = CS k-1 ;
5: for i Є N do
6:
MCR i performs a joining operation using Algorithm 2, that is,

iЄN

holds for all possible coalition structures CS k Є F and no MCR can
achieve an o-profitable deviation through any further joining or leaving
operations. Therefore, CS * is stable, confirming the existence of at least
one stable solution.

CS k = JoiningOperation(pi , T , CS k );
MCR i performs a leaving operation using Algorithm 3, that is,
CS k = LeavingOperation(pi , T , CS k );
8: end for
9: if CS k = CS k-1 then
10:
kstable = kstable + 1;
11: else
12:
kstable = 0;
13: end if
14: Update temperature T using Eq. (22);
15: k = k + 1;
16: End loop if kstable > Kmax or T < Tmin .
17: Output: stable coalition structure CS * ;
7:

4. Proposed algorithm for MCR scheduling
Building on the OCF game model established in the previous section,
we now present a decentralized coalition formation algorithm that enables MCRs to autonomously allocate resources and form Nash-stable
coalition structures CS * , as characterized in Eq. (31). A scheduling management mechanism is designed for each MCR to evaluate the feasibility
of its assigned task sequence and generate the corresponding time schedule while respecting energy and temporal constraints. Furthermore,
convergence analysis is provided to demonstrate the reliability of the
proposed approach.
4.1. Decentralized overlapping coalition formation algorithm

or when the coalition structure remains unchanged for more than Kmax
consecutive iterations (Line 16). The detailed procedures for the joining
and leaving operations are provided below.
Joining operation: In the proposed framework, each MCR i executes its
assigned tasks sequentially along its current path pi in cooperation with
other coalition members. During the joining operation, MCR i considers
inserting a new task-strategy pair (j, π) into its path pi , thereby joining
the coalition associated with task j, as defined in Definition 3. Because
the insertion position and charging strategy jointly affect both the feasibility of the resulting path and the overall system utility, an exhaustive
search is conducted to evaluate all candidate positions and strategies.
The detailed procedure is provided in Algorithm 2.
As outlined in Algorithm 2, let CS *k denote the best overlapping coalition structure found for MCR i at iteration k. Initially, CS *k is set to the
current structure CS k (Line 2), and a candidate task j Є M is randomly
selected (Line 3). The task is then tentatively inserted into all possible
positions in the current path pi under every available charging strategy, i.e., for each (n, π) Є enumerate(|pi | + 1, π) (Line 4). This operation
generates a temporary path:

The OCF problem studied here is NP-hard and tightly constrained.
It couples the combinatorial nature of task allocation with strict EVcharging time windows and MCR energy feasibility. Most existing
studies use unguided best-response algorithms for coalition formation
[39]. These methods guarantee stepwise, myopic improvement but often
converge slowly and become trapped in local optima. A guided alternative, preference-gravity-guided tabu search (PGG-TS), augments tabu
search with a “preference gravity” mechanism to steer coalition formation and escape local traps [34]. However, its effectiveness depends on
neighborhood diversity. Under tight temporal and energy constraints,
feasible neighborhoods shrink, limiting exploration and yielding suboptimal solutions. A method that sustains exploration while respecting
constraints is therefore needed.
We address this gap by integrating simulated annealing (SA) into
a decentralized coalition-formation process. SA is a stochastic metaheuristic inspired by metallurgical annealing. It can solve difficult
combinatorial or nonconvex optimization problems by alternating local perturbations with a temperature-controlled acceptance rule: at high
temperature, the search occasionally accepts uphill moves to escape local minima; as the temperature cools, acceptance becomes conservative
and the search shifts to exploitation. Building on this mechanism, we
propose a simulated-annealing-inspired OCF algorithm (SA-OCF), summarized in Algorithm 1. Early iterations accept suboptimal moves with
a controlled probability to fully explore the solution space. As the temperature decreases, the algorithm focuses on exploitation and converges
to a stable, high-quality overlapping coalition structure.
As outlined in Algorithm 1, the SA-OCF algorithm adopts a simulated
annealing framework. Initially, no resource allocation is performed, and
the coalition structure is initialized as a set of empty coalitions, i.e.,
CS 0 = {ꬾ, ꬾ, ... , ꬾ}. Meanwhile, the task execution path pi for each
MCR i is initialized as an empty list. The algorithm starts with a temperature T set to the initial maximum value Tmax . The iterative search
process proceeds while the temperature gradually decreases according
to a predefined annealing schedule, which updates T as
T ← α . T,

p'i = pi 0n {(j, π)},

(33)

where 0n denotes the insertion of (j, π) after the n-th element of pi . Next,
the feasibility of p'i is evaluated (Line 6) with respect to both temporal
Algorithm 2 Joining operation for MCR i at k-th iteration.
1: Input: π, pi , M, T , CS k ;
2: Initialization: p'i = pi , CS *k = CS k ;
3: Randomly select a task j Є M;
4: for (n, π) Є enumerate(|pi | + 1, π) do
5:
p'i = pi 0n {(j, π)};
6:
Check the feasibility of the path p'i via Algorithm 4;
7:
if feasible then
8:
A new coalition structure CS 'k is delivered based on the p'i and
its time schedule;
9:
if rand (0, 1) < Pa (T , CS *k , CS k' ) then
10:
CS *k ← CS 'k ;
11:
end if
12:
end if
13: end for
14: Output: coalition structure CS k = CS *k and p'i .

(32)

where α Є (0, 1) is the cooling factor controlling the rate of temperature
decay. In each iteration, every MCR performs both joining and leaving
operations (as defined in Definitions 3 and 4) to iteratively construct
a stable coalition structure (Lines 5–8). The algorithm terminates either when the temperature T falls below the minimum threshold Tmin
```


### Page 8

```text
and energy constraints, ensuring that (i) a valid time schedule exists
such that all assigned EVs are served within their time windows, and
(ii) the MCR retains sufficient energy to avoid operational failure. The
feasibility-checking and schedule-generation procedures are described
in detail in the next subsection.
If the temporary path pi' is deemed feasible, a new coalition structure
CS 'k is generated from the corresponding time schedule (Line 8). The
current best structure CS *k is then updated according to a Metropolisinspired stochastic acceptance rule (Lines 9–10), where the individual
and global utility gaps are defined as
{ΔU = u (CS ' ) - u (CS * );
i
i
k
k
| 1
{ΔU = ∑ u (CS ' ) - ∑ u (CS * ) .
i
i
k
k
|
iЄN
iЄN
}

criterion is satisfied:
rand(0, 1) < Pa (T , CS *k , CS 'k ),

where rand(0, 1) generates a uniform random number in [0, 1], and
Pa (T , CS *k , CS 'k ) is the Metropolis-inspired acceptance probability defined in Eq. (35).
4.2. Managing schedule
To determine path feasibility and generate a corresponding task
schedule, we adopt a simple temporal network (STN) representation for
each MCR [40]. As shown in Fig. 3, an STN is a directed graph S = (Q, ε),
where Q contains time points corresponding to arrival and departure
times for each task, and ε encodes temporal constraints, including task
durations and inter-task travel times. Self-loops indicate absolute timing
requirements for task execution.
For a task j assigned to MCR i, let ATij and DTij denote its arrival and
departure times. The duration constraint is directly given by Eqs. (18),
(19) and (20), ensuring that the allocated charging duration DU Rij
is respected and the charging session can be completed in the specified time window [ESTj , LF Tj ]. The inter-task travel time must satisfy
Eqs. (21) and (22), which also implicitly guarantee energy feasibility by
accounting for the MCR’s residual capacity and, if necessary, the option
to return to the base for recharging before executing the next task.
The procedure for checking the feasibility of a path and computing
the associated time schedule is outlined in Algorithm 4. Specifically,
whenever an MCR executes a joining or leaving operation, its corresponding STN S = (Q, ε) is reconstructed based on the updated task
execution path pi and its associated constraints (Line 3). To determine whether a valid time schedule exists, the STN is propagated using
the Floyd–Warshall algorithm [41] to identify potential inconsistencies
(Line 4). If no negative cycles are detected during propagation, the STN
is considered consistent, indicating that all temporal and energy constraints can be simultaneously satisfied. In this case, the path is deemed
feasible (Line 6), and a feasible task schedule T is generated by solving
the STN to minimize the makespan, defined as the total time required
to complete all assigned tasks (Line 7).

(34)

where ΔU1 and ΔU2 quantify the changes in MCR i’ utility and total
system utility (i.e., the global social welfare difference) after performing the joining operation, respectively. The acceptance probability
Pa (T , CS *k , CS 'k ) is given by
{
|1,
|eΔU1 /T ,
Pa (T , CS *k , CS 'k ) = { ΔU /T
,
|e
(ΔU1 +ΔU2 )/T ,
e
|
}

if ΔU1 > 0 and ΔU2 > 0;
if ΔU1 ≤ 0 and ΔU2 > 0;
if ΔU1 > 0 and ΔU2 ≤ 0;
if ΔU1 ≤ 0 and ΔU2 ≤ 0.

(36)

(35)

where T > 0 is the current temperature that controls the exploration–
exploitation trade-off. This Metropolis-inspired mechanism ensures that:
(i) Strictly improving moves (ΔU1 > 0 and ΔU2 > 0) are always accepted;
(ii) Partially worsening moves are accepted probabilistically, with the
probability decreasing as utility loss increases or temperature decreases.
This stochastic mechanism enhances the algorithm’s ability to escape local optima by allowing controlled acceptance of suboptimal solutions.
At higher temperatures, exploration is favored through more frequent
acceptance of worse outcomes; as the temperature decreases, the algorithm gradually shifts toward exploitation, leading to convergence to a
high-quality and stable coalition structure.
Leaving operation: In the leaving operation, MCR i systematically
examines the coalitions it currently participates in by removing the corresponding tasks and charging strategies from its path pi . As shown in
Algorithm 3 (Lines 1–2), the process begins by initializing the temporary
path p_tempi with pi and setting CS *k to the current coalition structure
CS k . For each task-strategy pair in p_tempi , a modified path p'i is generated by removing that entry. If p'i is feasible (Line 6), a new coalition
structure CS 'k is derived based on the updated path and its corresponding
time schedule (Line 7). The current best structure CS *k is then updated
with CS 'k , and pi is replaced by p'i if the following stochastic acceptance

Algorithm 3 Leaving operation for MCR i at k-th iteration.
1: Input: pi , T , CS k ;
2: Initialization: p_tempi = pi , CS *k = C S k ;
3: for (j, πij ) Є p_tempi do
4:
p'i = pi \(j, πij );
5:
Check the feasibility of the path p'i via Algorithm 4;
6:
if feasible then
7:
A new coalition structure CS 'k is derived based on the p'i and its
time schedule;
8:
if rand(0, 1) < Pa (T , CS *k , CS 'k ) then
9:
CS *k ← CS k' ;
10:
pi ← p'i ;
11:
end if
12:
end if
13: end for
14: Output: coalition structure CS k = CS *k and pi .

Fig. 3. Example of an STN for three tasks assigned to one MCR, showing
arrival/departure times, duration, and travel constraints.

Algorithm 4 Task scheduling algorithm.
1: Input: pi , S = (Q, ε) for MCR i;
2: Initialization: f easibility = F lase, S = ꬾ, T = ꬾ;
3: Encode all task-related time points and temporal constraints into the

STN S;
4: Propagate the STN using Floyd-Warshall algorithm.
5: if STN is consistent then
6:
f easibility = T rue;
7:
Compute feasible time schedule T along path pi that minimizes

the makespan;
8: end if
9: Output: f easibility, T ;
```


### Page 9

```text
4.3. Convergence and complexity analysis

Table 1
Simulation parameters.

Convergence analysis. We now provide a theoretical analysis
showing that Algorithm 1 converges to a stable coalition structure, as
stated below.

EV Parameters

Theorem 2. Starting from any initial coalition structure CS 0 , the proposed
OCF algorithm is guaranteed to converge to a stable coalition structure CS * .

Parameters

Values

Battery capacity BC (kWh)
Charging efficiency ηcev

{40,60,80,100}
0.90

MCR Parameters

Proof (Proof of Theorem 2). In each joining or leaving operation of
Algorithm 1, an MCR either moves to a strictly better configuration under the holistic altruistic (HA) order or, under the simulated-annealing
acceptance rule, may temporarily accept a worse configuration. As
iterations proceed, the temperature decreases and the probability of accepting a worse move tends to zero. Moreover, Theorem 1 ensures the
existence of at least one HA-stable coalition structure. Because the numbers of MCRs, tasks, and charging strategies are finite, the state space is
finite. Therefore, Algorithm 1 reaches a stable coalition structure CS * in
finitely many iterations.

Parameters

Values

Average velocity v (km/h)
Charging power Pc (kW)
Discharging power Pd (kW)
Charging efficiency ηcmcr
Discharging efficiency ηdmcr
Energy consumption per kilometer ρ (kWh/km)
Unit grid electricity price μg (CNY/kWh)
Unit service price μs (CNY/kWh)
Unit idle-time penalty coefficient γ (CNY/h)

0.90
0.90
0.7
1.4

Algorithm Parameters

Complexity analysis. We next analyze the computational complexity of Algorithm 1. Assume convergence occurs within at most K iterations. In each iteration, every MCR performs both joining and leaving
operations. In a joining operation, an MCR tries all insertion positions for
a new task while enumerating J charging strategies and verifying path
feasibility. In the worst case, if the path already contains M - 1 tasks,
there are M insertion positions. With J charging strategies and feasibility checked via the Floyd–Warshall algorithm (worst-case O((2 M)3 )),
(
)
the joining cost per MCR is O M . J . (2 M)3 = O(M 4 J ). In a leaving
operation, an MCR considers removing each of the at most M tasks from
its path; for each removal, feasibility is verified via the Floyd–Warshall
algorithm with worst-case complexity O((2(M -1))3 ). Thus, the leaving
(
)
cost per MCR is O M(2(M -1))3 = O(M 4 ). Aggregating over N MCRs
and K iterations yields an upper bound of O(KNM 4 (J +1)) for the total
complexity, equivalently O(KNM 4 J ) when J dominates. This bound
is polynomial in (N, M, J ) for any fixed or polynomially bounded K,
supporting practical deployment.

Parameters

Values

Maximum temperature Tmax
Minimum temperature Tmin
Cooling factor α
Maximum stable iterations Kmax

0.001
0.96

measures 66.0 m × 47.6 m, provides 106 parking spaces, and includes
a dedicated MCR recharging area. EVs arrive stochastically, occupy
spaces, and submit charging requests with time-window constraints.
Key simulation parameters are summarized in Table 1. Following
[42], we consider four EV types with lithium-ion battery capacities of
40, 60, 80, and 100 kWh, representing mainstream models such as the
Hyundai Nexo, BYD Atto 3, BMW i3, and Tesla Model S. The EV charging
efficiency is set to ηcev = 0.9 [42]. To reflect typical parking-lot speed limits and safety considerations, the MCR travel speed is set to v = 5 km/h.
MCRs are modeled with lithium-ion batteries, with charging and discharging efficiencies both set to 0.90. Their charge/discharge power is
set to 100 kW, consistent with Level-III fast charging [43]. The grid electricity price is set to μg = 0.7 CNY/km based on the Chinese electricity
market analysis in [44], and the service price is μg = 1.4 CNY/kWh to
cover operating costs. The idle-time penalty coefficient is γ = 70 CNY/h,
calibrated to approximate the foregone gross margin from one hour of
service and thereby discourage unnecessary waiting. Algorithm parameters, including the maximum temperature Tmax , minimum temperature
Tmin , and cooling factor α, are selected following [45]. The maximum
number of stable iterations Kmax is set as 50 to ensure convergence.
All simulations are conducted on a workstation running Ubuntu
20.04 with an Intel Core i7-12700F CPU (4.90 GHz) and 48 GB RAM.
The algorithms are implemented in Python 3.8 and executed within the
ROS Noetic framework. Interactions among MCRs and the ISO are implemented through the ROS publish–subscribe mechanism. To ensure
operational safety, MCRs are prohibited from traversing parking spaces.
The shortest collision-free travel distances between any two locations in
the parking lot are computed using the A* algorithm.

5. Simulation
5.1. Setup
In this section, we evaluate the SA-OCF algorithm using simulations
on a real parking-lot map from our previous work (Fig. 4) [31]. The site

5.2. Performance evaluation
To demonstrate the effectiveness of the proposed SA-OCF algorithm,
we conduct a comparative study against four benchmark methods: (i) the
non-overlapping coalition formation (non-overlapping CF) algorithm
[46], (ii) the unguided OCF algorithm [39], (iii) the PGG-TS OCF algorithm [34], and (iv) the modified genetic algorithm (mGA) [23]. It
should be noted that the non-overlapping CF and mGA methods adopt
fundamentally different scheduling paradigms. Non-overlapping CF restricts each MCR to a single coalition, collaborating with others to
complete one task. By contrast, mGA formulates the MCR scheduling
problem as a capacitated vehicle routing and scheduling problem with

Fig. 4. Simulation environment. The simulation environment is conducted on a
real-world parking-lot map measuring 66.0m × 47.6m with 106 parking spaces.
MCRs dynamically form multiple coalitions, depicted as dashed colored ellipses,
to collaboratively serve EVs. MCR paths are shown as colored straight lines with
arrows.
```


### Page 10

```text
time windows (CVRSPTW): each task is assigned to exactly one MCR,
and the mGA method is proposed to solve a route for each MCR along
which the MCR can sequentially serve multiple tasks while respecting
time-window and capacity constraints to maximize system utility. These
paradigms differ along two dimensions: whether an MCR may serve multiple tasks and whether a task may be served by multiple MCRs. The
comparison is summarized in Table 2.
We first examine the convergence behavior in a randomized scenario
with 10 MCRs. Each MCR carries a 100 kWh battery, starts fully charged,
and is placed randomly in the lot. Over a 1 h horizon, we generate 30
charging requests. Each EV arrives with an initial SOC in [0, 0.5], targets
a full SOC of 1, and stays for 1–3 h. The sensitivity coefficient is uniformly sampled from [0.1, 1]. Fig. 5 plots social welfare versus iteration
for the five algorithms. It can be observed that all methods converge as
iterations increase. SA-OCF achieves the highest steady-state welfare. In
early iterations, its curve fluctuates because the algorithm probabilistically accepts suboptimal moves to enhance exploration. As iterations
proceed, the welfare stabilizes, indicating convergence to a high-quality
solution. This behavior shows that SA-OCF can effectively balance exploration and exploitation and facilitate a superior overlapping coalition
structure. In contrast, PGG-TS converges faster but to a lower final welfare, reflecting limited neighborhood diversity. Unguided OCF and mGA
converge more slowly, and the non-overlapping CF baseline yields the
lowest welfare.
Under the above randomized setting, we examine how chargingpolicy granularity affects performance and computation time for four
game-based methods: non-overlapping CF, unguided OCF, PGG-TS OCF,
and SA-OCF. Here, we exclude the mGA algorithm because it assigns

Fig. 6. Comparison of the average social welfare and computation time of
four game-based algorithms under different charging strategy sets. (a) Nonoverlapping CF, (b) Unguided OCF, (c) PGG-TS OCF, and (d) SA-OCF.

an MCR only when its capacity fully meets an EV’s demand, which
precludes partial allocations and makes granularity irrelevant. We test
three charging strategy sets (as listed in Table 3) with 20 independent
replications each. Fig. 6 reports the average social welfare and computation time for each combination of method and policy. It is observed that
finer charging strategy sets generally yield more efficient MCR scheduling, which raises social welfare but also increases computation time. For
non-overlapping CF, welfare and runtime change little across policies
because resource sharing is disallowed: each MCR serves at most one
EV at a time, so with a limited fleet the feasible schedule set is nearly
fixed and policy granularity does not expand the action space. Moreover,
relative to unguided OCF, SA-OCF raises welfare by 106.1–118.8 CNY
(10.1–11.7 %) with an extra 0.8–1.2s; relative to PGG-TS OCF, the gains
are 84.6–95.2 CNY (8.5–9.3 %) with 0.9–1.4s additional time. The added
overhead, on the order of seconds, is justified by the welfare gains and
the improved quality of experience for EV owners.
Under the randomized setting, we further evaluate performance for
MCR battery capacities of 60, 80, 100, 120, and 140 kWh and fleet
sizes of 4, 6, 8, 10, 12, 14, and 16. At the start of each run, all MCRs
are randomly placed in the parking lot and begin fully charged. Over
a 1 h horizon, 30 charging requests arrive. Each EV arrives with an
initial SOC in [0, 0.5], targets a full SOC of 1, and stays for 1–3 h.
The sensitivity coefficient is uniformly sampled from [0.1, 2]. For the
four game-based methods, each MCR uses the charging strategy set
π2 listed in Table 2. Fig. 7 reports social welfare, total energy delivered, travel cost, and idle cost across fleet–capacity combinations.
Fig. 7(a) and (b) show that larger fleets and higher capacities increase social welfare and energy delivery for all methods. Compared
with non-overlapping CF and mGA, the three OCF variants (unguided,
PGG-TS, and SA-OCF) achieve higher welfare and deliver more energy,
with the largest gains for small fleets or low capacities. This indicates
that overlapping cooperation methods enable more efficient scheduling under limited resources and tight temporal constraints. Among
OCF methods, SA-OCF performs best: it raises social welfare by 6.2 %
over PGG-TS and 7.8 % over the unguided variant, and increases energy delivery by 4.95 % and 9.07 % on average, respectively. These

Table 2
Benchmark methods comparison.
Method

MCR → Multi-tasks

Task → Multi-MCRs

mGA
Non-overlapping CF
Unguided OCF
PGG-TS OCF
SA-OCF

√
×
√
√
√

×
√
√
√
√

MCR → Multi-tasks: indicates whether each MCR can serve multiple
tasks. Task → Multi-MCRs: indicates whether each task can be served
by multiple MCRs. √ signifies that the feature is supported, while ×
signifies that it is not supported.

Fig. 5. Social welfare curves with increasing iterations.

Table 3
Three different charging strategy sets.
Strategy sets

Value

π1
π2
π3

{50 %, 100 %}
{20 %, 40 %, 60 %, 80 %, 100 %}
{10 %, 20 %, 30 %, 40 %, 50 %, 60 %, 70 %, 80 %, 90 %, 100 %}
```


### Page 11

```text
Fig. 7. Performance comparison of five scheduling algorithms (mGA, non-overlapping CF, unguided OCF, PGG-TS OCF, and SA-OCF) under varying fleet size and
battery capacity. Columns indicate MCR battery capacity C = 60, 80, 100, 120, 140 kWh. Rows report: (a) social welfare (CNY) versus number of MCRs; (b) total energy
delivered (kWh) versus number of MCRs; (c) total travel cost (CNY) versus number of MCRs; (d) total idle cost (CNY) versus number of MCRs.

results demonstrate the effectiveness of SA-OCF in searching for overlapping coalition structures. In particular, mGA is capacity-dependent; at
60–100 kWh it yields the lowest welfare and energy because it disallows
partial service, dispatching an MCR only when its battery fully covers
an EV’s demand.
Nevertheless, OCF methods incur higher operating costs. It should be
noted that our accounting excludes the fixed cost of grid electricity used
by MCRs to charge EVs and merely considers scheduling-induced costs:
total MCR travel cost and idle-time cost. As shown in Fig. 7(c) and (d),
both costs generally rise with MCR fleet size. By contrast, travel costs
under OCF methods decline as MCR battery capacity increases because
larger batteries extend on-site service and reduce return trips to charging
stations. Compared with mGA and non-overlapping CF, OCF methods
typically exhibit higher travel and idle costs, reflecting the added operational complexity of overlapping coordination. Even so, this additional
operating cost is a reasonable trade-off for the gains in social welfare and
energy delivered (Fig. 7(a) and (b)). Moreover, among the OCF variants,

the proposed SA-OCF generally incurs the lowest travel and idle costs,
underscoring its scheduling efficiency.
5.3. Scalable analysis
This section evaluates algorithm scalability across three
representative charging scenarios: office parking, shopping malls,
and highway service areas. EV users in these scenarios exhibit distinct charging behaviors in initial SOC, target SOC, dwell time, and
willingness to pay.
• Office parking: Users typically arrive in the morning and depart in
the evening, resulting in long dwell times [10]. Because many drivers
may charge the night before, vehicles often arrive with a relatively
high SOC; immediate charging demand and willingness-to-pay are
low. To capture this behavior, we model the initial SOC as uniformly
distributed over [0.4, 0.6] and the target SOC over [0.7, 0.9]. Dwell
time follows a truncated normal distribution on [6, 9] h with mean of
```


### Page 12

```text
994.15
1322.02
1647.72
1954.24

993.41
1316.18
1586.44
1586.62

991.45
1194.41
1194.46
1194.5

mGA

436.63
559.95
719.33
859.11

462.99
643.4
718.11
774.93

419.84
570.22
666.31
769.17

No. of
MCRs

No. of
Tasks

shopping mall 60

Scenario

991.65
1325.01
1643.01
1952.82

991.68
1320.04
1634.48
1945.24

989.94
1310.42
1500.82
1500.83

mGA

1964.5 1.93
1962.14 2.11
1960.58 2.58
1916.59 2.95

1969.96
1973.49
1965.74
1959.95

612.07
717.23
892.06
1051.27

589.65
706.79
850.16
1030.11

516.88
715.29
794.09
960.16

1245.57
1574.73
1882.45
2099.34

1175.51
1528.49
1768.47
1929.15

1138.84
1370.62
1431.71
1464.45

1164.81
1475.2
1894.43
2116.41

1124.16
1501.42
1778.96
1953.63

1130.01
1407.49
1477.46
1479.18
15.24
1.64
2.53
2.64
1.6
2.55
8.1
2.68

1250.6 1.63
1625.57 1.99
2024.16 2.26
2291.81 2.68

5.56
9.48
13.97
34.65

5.52
19.9
34.38
50.73

6.73
22.35
6.55
30.99

8.3
11.94
17.28
39.46

8.45
15.33
23.76
18.76

1189.54 1.76
1637.22 1.65
1889.38 2.39
1972.03 2.59

10.16
27.88
67.49
34.33

1.25
5.73
13.68
34.09

1238.4 1.48
1481.46 1.68
1482.96 1.55
1477.34 1.54

12.28
8.75
16.5
20.06

13.87
11.68
15.56
13.45

Unguided PGG-TS
Nonoverlapping OCF
OCF
CF

42.26
43.04
58.32
55.27

37.97
25.32
37.11
80.28

SA-OCF mGA

Operating cost (CNY)

1.15
1.55
2.11
2.37

1.27
1.9
1.89
2.32

1576.35 1.68
1569.53 2.25
1573.96 1.93
1567.56 1.75

1573.22
1576.11
1571.37
1574.91

11.79
13.26
12.32
17.08

1.33
10.21
13.94
10.78

1186.69 1.57
1172.22 1.36
1161.95 1.31
1165.23 1.27

1183.98
1182.51
1182.58
1177.81

Unguided PGG-TS
Nonoverlapping OCF
OCF
CF

Social welfare (CNY)

1934.81
1936.21
1918.04
1923.38

1547.69
1560.73
1547.94
1503.7

1164.8
1156.96
1160.74
1159.15

29.53
37.8
34.03
35.19

NonUnguided PGG-TS
overlapping OCF
OCF
CF

Operating cost (CNY)
SA-OCF mGA

NonUnguided PGG-TS
overlapping OCF
OCF
CF

Social welfare (CNY)

Table 5
Simulation results on shopping mall scenario.

No. of
MCRs

No. of
Tasks

Office parking 60

Scenario

Table 4
Simulation results on office parking scenario.

3.4
4.97
7.32
6.22

3.39
5.99
7.68
21.93

3.52
6.32
17.35
22.43

SAOCF

16.17
20.1
20.22
65.34

12.01
18.02
12.09
20.77

8.2
23.55
33.27
29.73

SAOCF

0.18
0.24
0.33
0.41

0.263
0.4
0.4
0.475

0.35
0.45
0.55
0.617

0.42
0.52
0.68
0.79

0.525
0.675
0.825
0.975

0.65
0.867

mGA

0.22
0.23
0.34
0.41

0.263
0.325
0.438
0.5

0.317
0.483
0.467
0.65

0.7
0.82
0.95
0.97

0.8
0.938
0.988

0.933

0.59
0.76
0.91
0.95

0.7
0.887
0.975

0.9

NonUnguided PGG-TS
OCF
overlapping OCF
CF

NonUnguided PGG-TS
overlapping OCF
OCF
CF

Task coverage ratio

0.53
0.71
0.85
0.99

0.65
0.838

0.85

mGA

Task coverage ratio

0.58
0.79
0.97

0.713

0.983

SAOCF

SAOCF

0.216
0.28
0.357
0.426

0.286
0.394
0.445
0.477

0.341
0.477
0.557
0.641

0.398
0.531
0.659
0.783

0.498
0.663
0.821
0.977

0.66
0.873

mGA

0.999

0.999
0.999
0.999

0.999
0.999

0.234
0.278
0.341
0.394

0.287
0.342
0.393
0.493

0.33
0.454
0.52
0.634

0.443
0.57
0.702
0.813

0.528
0.715
0.86
0.987

0.704
0.898
0.996
0.996

0.435
0.565
0.717
0.83

0.534
0.725
0.881
0.999

0.707
0.932
0.999
0.995

NonUnguided PGG-TS
overlapping OCF
OCF
CF

0.997
0.998
0.996
0.997

0.998
0.998
0.997
0.996

0.999
0.999
0.999
0.998

NonUnguided PGG-TS
overlapping OCF
OCF
CF

Completion ratio

0.502
0.668
0.833
0.987

0.626
0.83

0.83

mGA

Completion ratio

0.454
0.607
0.748
0.879

0.551
0.749
0.923

0.761
0.983
0.998
0.997

SAOCF

0.999
0.999

0.999
0.998

0.999
0.999
0.999

SAOCF
```


### Page 13

```text
0.227
0.287
0.352
0.432

0.238
0.307
0.382
0.445

0.242
0.316
0.394
0.462

8 h workday and standard deviation of 0.5 h. A small price-sensitivity
coefficient in Eq. (2) is drawn uniformly from [0.1, 0.2].
• Shopping mall: Compared with office parking, EVs at shopping
malls usually have shorter dwell times. Visits are non-commuting
and opportunistic; charging occurs during shopping or dining, and
willingness to pay is moderate. We set the initial SOC uniformly on
[0.3, 0.5] and the target SOC on [0.7, 1]. A shorter dwell time follows
a truncated normal distribution on [1, 3] h with mean of 2 h and standard deviation of 0.5 h. We draw a moderate sensitivity coefficient
uniformly from [0.2, 0.4].
• Highway service area: Because EV users typically follow tight travel
schedules in highway service areas, EVs tend to arrive with a low
initial SOC, plan brief dwell times, and exhibit a strong willingness
to pay for fast charging. To capture this behavior, we set a lower
initial SOC uniformly on [0.1, 0.3] and the target SOC on [0.8, 1.0].
Dwell time follows a truncated normal distribution on [0.5, 1.5] h
with mean of 1 h and standard deviation of 0.2 h. A larger sensitivity
coefficient is uniformly sampled from [0.5, 1].

0.244
0.315
0.391
0.464
0.43
0.62
0.68
0.8
0.48
0.61
0.63
0.71

0.181
0.233
0.291
0.325

0.3
0.388
0.478
0.566
0.293
0.389
0.467
0.556
0.22
0.278
0.353
0.4
0.302
0.397
0.484
0.573
0.487
0.662
0.75
0.963

1146.3
1483.68
1766.25
2020.22

4.21
5.05
9.74
11.11

4.52
4.39
14.27
6.97
1.02
6.49
8.45
1.93
1165.28 1.07
1618.09 1.57
1909.5 1.96
2252.57 2.03
1113.62
1415.44
1733.06
2066.51
774.75
1004.85
1192.46
1364.65

2.24
2.99
3.47
4.6

0.27
0.34
0.46
0.51

0.19
0.24
0.25
0.3

0.44
0.54
0.67
0.78

To evaluate scalability, we test fleets of 12, 16, 20, and 24 MCRs,
each with a 120 kWh battery. Over a 1-h scheduling horizon, we generate 60, 80, and 100 charging requests under the three scenarios defined
above. At the start of each run, MCRs are fully charged and placed uniformly at random in the parking lot. For each configuration and scenario,
we conduct 20 independent trials and report the average social welfare,
operating cost, task coverage ratio, and completion ratio in Tables 4–6.
Boldface indicates the best value in each row. Operating cost is the
sum of idle time and travel costs. The task coverage ratio is the fraction of requests receiving any positive service before departure, and the
completion ratio is the ratio of total energy delivered to total energy
requested.
Across the three scenarios, the OCF methods (Unguided OCF, PGGTS OCF, and SA-OCF) outperform the two non-overlapping baselines
(mGA and Non-overlapping CF) on average social welfare and, under
tight time windows (shopping malls and highway service areas), on completion, while keeping operating costs comparable. In office parking,
where dwell times are long and urgency is low, all methods approach
saturation; OCF remains well above Non-overlapping CF and competitive with mGA, achieving near-unity coverage and completion even at
high loads with small fleets (e.g., 100 tasks and 12 MCRs). Among OCF
variants, SA-OCF attains the best average welfare and the lowest operating cost in the tighter scenarios. Averaged over all fleet sizes and loads,
SA-OCF improves social welfare by 5.71 % versus PGG-TS and 5.11 %
versus Unguided OCF in shopping malls, and by 9.37 % and 12.87 % in
highway service areas; it also reduces operating cost by 47.35 % (versus
PGG-TS) and 64.81 % (versus Unguided OCF) in shopping malls, and
by 62.08 % and 79.12 % in highway service areas. These gains stem
from overlap-aware, relay-like coordination combined with simulated
annealing search, which preserves feasibility under tight windows and
converts it into higher realized welfare. Overall, SA-OCF is well suited to
time-constrained, high-sensitivity deployments (malls and highway service areas) and remains stable and effective in looser office conditions,
demonstrating strong scalability.
6. Conclusion
This paper investigates the cooperative task assignment and resource scheduling problem for mobile charging robots (MCRs) in EV
charging services. The problem is formulated as an overlapping coalition formation (OCF) game, enabling MCRs to autonomously allocate
resources and collaboratively complete charging tasks. To promote cooperation and enhance social welfare, a holistic altruistic preference
order is introduced. A decentralized simulated annealing-inspired OCF
(SA-OCF) algorithm is further developed to efficiently explore coalition structures while satisfying both energy and temporal constraints.
Simulation results demonstrate that, in a randomly generated scenario,
SA-OCF improves social welfare by 6.2 %–7.8 % and energy delivered by

967.83
1247.13
1549.83
1838.98

953.35
1252.06
1525.44
1808.62

1087.03
1440.03
1693.98
2017.4

2.95
23.82
11.86
15.6

6.08
10.5
10.35
0.99
1.01
1.62
1.81
1169.82 1.16
1530.58 1.53
1811.43 1.61
2162.87 1.74
1116.47
1311.68
1665.23
1916.45
741.84
926.29
1343.9

2.19
2.7
3.01
4.57

0.325
0.45
0.55
0.625

0.212
0.237
0.362
0.375

0.562
0.662
0.738
0.812

0.5
0.613
0.725
0.85

0.282
0.348
0.448
0.524

0.41
0.526
0.641
0.765
0.395
0.513
0.612
0.708
0.375
0.445
0.599
0.673
0.284
0.361
0.467
0.514
0.407
0.531
0.642
0.749
0.733
0.933
0.983
Highway 60

934.1
1218.47
1475.12
1719.68

1035.02
1354.2
1532.8
1795.59

6.41
22.48
21.72
51.06

10.59
6.63
6.75
17.36
0.83
1.44
1.52
2.03
1190.31 1.02
1517.68 1.25
1774.06 1.43
1991.36 1.78
1033.43
1186.18
1564.99
1679.52
695.38
916.51
1152.98
1276.53

2.19
2.87
3.06
4.94

0.433
0.567
0.683
0.783

0.267
0.383
0.467
0.533

0.65
0.733
0.9
0.9

0.633
0.783
0.817
0.95

NonUnguided PGG-TS
overlapping OCF
OCF
CF
mGA
SAOCF
NonUnguided PGG-TS
overlapping OCF
OCF
CF
mGA
NonUnguided PGG-TS
overlapping OCF
OCF
CF

Operating cost (CNY)

SA-OCF mGA
mGA

Social welfare (CNY)

No. of
MCRs
Scenario No. of
Tasks

Table 6
Simulation results on highway scenario.

NonUnguided PGG-TS
overlapping OCF
OCF
CF

SAOCF

Task coverage ratio

Completion ratio

SAOCF
```


### Page 14

```text
4.95 %–9.07 % relative to the two OCF variants. Across scenarios with
heterogeneous user charging behaviors, SA-OCF exhibits strong scalability and stability, particularly in time-constrained, high-load regimes,
underscoring its superior performance.
Although the proposed framework assumes deterministic task parameters for computational efficiency, it offers inherent robustness
to uncertainties through its decentralized and adaptive nature. For
example, periodic reruns of SA-OCF can accommodate variations in arrival/departure times or demands by reallocating MCRs dynamically.
In cases of early EV departure, partial charging via the relay scheme
ensures utility gains, with remaining MCRs redirecting to other tasks.
However, more advanced handling of stochasticity—such as probabilistic arrival times [47], uncertain demands and deadlines [48], or online
commitment mechanisms [49]—represents a promising direction for
future work. Extensions could incorporate chance-constrained OCF or
distribution-free robust optimization to further enhance reliability under
real-world variability.

[10] Kong PY. Autonomous robot-like mobile chargers for electric vehicles at public parking facilities. IEEE Trans Smart Grid 2019;10(6):5952–63. https://doi.org/10.1109/
TSG.2019.2893962
[11] Zhao Z, Lee CK, Huo J. EV charging station deployment on coupled transportation and power distribution networks via reinforcement learning. Energy
2023;267:126555.
[12] Zhang Y, Wang Y, Li F, Wu B, Chiang YY, Zhang X. Efficient deployment of
electric vehicle charging infrastructure: simultaneous optimization of charging
station placement and charging pile assignment. IEEE Trans Intell Transp Syst
2020;22(10):6654–9. https://doi.org/10.1109/TITS.2020.2990694
[13] Sarkhosh M, Fattahi A. Network-aware electric vehicle charging/discharging
scheduling for grid load management in a hierarchical framework. Comput Electr
Eng 2025;121:109903.
[14] Zeng T, Bae S, Travacca B, Moura S. Inducing human behavior to maximize operation
performance at PEV charging station. IEEE Trans Smart Grid 2021;12(4):3353–63.
https://doi.org/10.1109/TSG.2021.3066998
[15] Cao Y, Tang S, Li C, Zhang P, Tan Y, Zhang Z, Li J. An optimized EV charging
model considering tou price and soc curve. IEEE Trans Smart Grid 2011;3(1):388–93.
https://doi.org/10.1109/TSG.2011.2159630
[16] IEEE guide for terminology and classification of electric vehicle charging
robots. IEEE Std 3345-2024, 2025:1–22. https://doi.org/10.1109/IEEESTD.2024.
[17] Ju Y, Zeng T, Allybokus Z, Moura S. Robo-chargers: optimal operation and planning of a robotic charging system to alleviate overstay. IEEE Trans Smart Grid
2023;15(1):770–82. https://doi.org/10.1109/TSG.2023.3286434
[18] Zhang Z, Dong ZY, Yip C. When mobile energy meets active distribution networks: a security–economic coordination perspective. IEEE Trans Smart Grid
2023;15(3):3126–40. https://doi.org/10.1109/TSG.2023.3339617
[19] Zhang Z, Dong ZY, Yip C, Luo F. Security-economic driven coordinated operation of
the mobile charging robots cluster and active distribution networks. IEEE Trans Ind
Appl 2024;60(6):8306–18. https://doi.org/10.1109/TIA.2024.3447637
[20] Cui J, Jiang W, Wu C. Pricing mechanism design for future EV charging station
with hybrid fixed and mobile charging modes. Appl Energy 2025;380:125033. https:
//doi.org/10.1016/j.apenergy.2024.125033
[21] Wang D, Guo J, Zhang Y, Zhong Q, Xu H. Optimizing expressway battery electric
vehicle charging and mobile storage energy truck scheduling: a two-stage approach
to improve photovoltaic generation utilization. Energy 2025;320:135145. https://
doi.org/10.1016/j.energy.2025.135145
[22] Saboori H, Mehrjerdi H, Jadid S. Mobile battery storage modeling and normalemergency operation in coupled distribution-transportation networks. IEEE Trans
Sustain Energy 2022;13(4):2226–38. https://doi.org/10.1109/TSTE.2022.3189838
[23] Qureshi U, Ghosh A, Panigrahi BK. Scheduling and routing of mobile charging stations with stochastic travel times to service heterogeneous spatiotemporal electric vehicle charging requests with time windows. IEEE Trans Ind Appl
2022;58(5):6546–56. https://doi.org/10.1109/TIA.2022.3182323
[24] Afshar S, Pecenak ZK, Barati M, Disfani V. Mobile charging stations for EV
charging management in urban areas: a case study in chattanooga. Appl Energy
2022;325:119901. https://doi.org/10.1016/j.apenergy.2022.119901
[25] Afshar S, Pecenak ZK, Disfani V. Mobile charging station: a complementary charging
technology for electric vehicles, In: 2022 IEEE transportation electrification conference & expo (ITEC); IEEE; 2022. p. 953–7. https://doi.org/10.1109/ITEC53557.
2022.9814039
[26] Kong PY. Extending energy storage lifetime of autonomous robot-like mobile
charger for electric vehicles. IEEE Access 2020;8:106811–21. https://doi.org/10.
1109/ACCESS.2020.3000820
[27] An S, Qiu J, Lin J, Yao Z, Liang Q, Lu X. Planning of a multi-agent mobile
robot-based adaptive charging network for enhancing power system resilience under extreme conditions. Appl Energy 2025;395:126252. https://doi.org/10.1016/j.
apenergy.2025.126252
[28] He K, Jia H, Mu Y, Yu X, Zhou Y, Gan W, Wu J. Coordinated scheduling of EV
charging service and energy arbitrage for truck mobile charging stations. IEEE Trans
Smart Grid 2025.
[29] Liu L, Zheng Y, Tang Y, Xu J. Multi-scenario robust stochastic optimization based
approach for scheduling of mobile charging stations. IEEE Trans Mobile Comput
2025:1–18.
[30] Zhang Z, Dong ZY, Yip C. A new charging scheme based on mobile charging
robots cluster: a three-level coordinated perspective. IEEE Trans Ind Informatics
2024;20(4):6900–12. https://doi.org/10.1109/TII.2024.3352182
[31] Fang Q, Zhang J, Wang C, Xie G, Zhang C. Decentralized game-based auction algorithm for scheduling robotic chargers to service evs with uncertain demands. IEEE
Trans Intell Veh 2025;10(2):886–99. https://doi.org/10.1109/TIV.2024.3419183
[32] Zeng M, Leng S, Zhang Y, He J. QoE-aware power management in vehicle-to-grid networks: a matching-theoretic approach. IEEE Trans Smart Grid 2016;9(4):2468–77.
https://doi.org/10.1109/TSG.2016.2613546
[33] Limmer S. Dynamic pricing for electric vehicle charging—a literature review.
Energies 2019;12(18):3574.
[34] Qi N, Huang Z, Zhou F, Shi Q, Wu Q, Xiao M. A task-driven sequential overlapping
coalition formation game for resource allocation in heterogeneous UAV networks.
IEEE Trans Mobile Comput 2022;22(8):4439–55. https://doi.org/10.1109/TMC.
2022.3165965
[35] Li JT, Chen CK, Ren H. Time-optimal trajectory planning and tracking for autonomous vehicles. Sensors 2024;24(11):3281.
[36] Gao Y, Li D, Sui Z, Tian Y. Trajectory planning and tracking control of autonomous
vehicles based on improved artificial potential field. IEEE Trans Veh Technol
2024;73(9):12468–83.

CRediT authorship contribution statement
Qiuyang Fang: Writing – original draft, Visualization,
Validation, Software, Methodology, Investigation, Formal analysis,
Conceptualization. Chunyan Zhang: Writing – review & editing,
Validation, Formal analysis. Chen Wang: Writing – review & editing,
Validation, Formal analysis. Guangming Xie: Writing – review &
editing, Validation, Formal analysis. Jianlei Zhang: Writing – review
& editing, Validation, Supervision, Formal analysis.
Declaration of competing interest
The authors declare that they have no known competing financial
interests or personal relationships that could have appeared to influence
the work reported in this paper.
Acknowledgement
This work was supported by the National Natural Science Foundation
of China under Grants 62473211 and 62573239.
Data availability
No data was used for the research described in the article.
References
[1] Park K, Moon I. Multi-agent deep reinforcement learning approach for EV charging
scheduling in a smart grid. Appl Energy 2022;328:120111. https://doi.org/10.1016/
j.apenergy.2022.120111
[2] Secchi M, Barchi G, Macii D, Petri D. Smart electric vehicles charging with
centralised vehicle-to-grid capability for net-load variance minimisation under increasing EV and PV penetration levels. Sustain Energy Grids Netw 2023;35:101120.
https://doi.org/10.1016/j.segan.2023.101120
[3] Zhang Y, You P, Cai L. Optimal charging scheduling by pricing for EV charging station with dual charging modes. IEEE Trans Intell Transp Syst 2018;20(9):3386–96.
https://doi.org/10.1109/TITS.2018.2876287
[4] He X, Jiang S, Yu Y, Su S. Impact of novel infrastructure investments on productivity: evidence from public procurement of EV charging facilities in China. Energy
2025;334:137699. https://doi.org/10.1016/j.energy.2025.137699
[5] Graber G, Calderaro V, Mancarella P, Galdi V. Two-stage stochastic sizing and packetized energy scheduling of bev charging stations with quality of service constraints.
Appl Energy 2020;260:114262. https://doi.org/10.1016/j.apenergy.2019.114262
[6] Ameer H, Wang Y, Fan X, Chen Z. Hybrid optimization of EV charging station placement and pricing using bender’s decomposition and NSGA-II algorithm. Appl Energy
2025;397:126385. https://doi.org/10.1016/j.apenergy.2025.126385
[7] Zhu Z, Zhang H. Real-time coordinated operation of electric vehicle fast charging
stations with energy storage: an efficient spatiotemporal decomposition approach.
IEEE Trans Smart Grid 2025;16(3):2464–77. https://doi.org/10.1109/TSG.2025.
[8] Ouyang K, Wang DZ. Optimal operation strategies for freight transport with electric
vehicles considering wireless charging lanes. Transp Res Part E Logist Transp Rev
2025;193:103852. https://doi.org/10.1016/j.tre.2024.103852
[9] Simwaba D, Qutieshat A. The potential of EV battery-swapping in developing countries: China’s use case as a baseline for sub-saharan africa. Transp Res Interdiscip
Perspect 2025;32:101505.
```


### Page 15

```text
[37] Mahdiraji HA, Razghandi E, Hatami-Marbini A. Overlapping coalition formation in
game theory: a state-of-the-art review. Expert Syst Appl 2021;174:114752. https:
//doi.org/10.1016/j.eswa.2021.114752
[38] Wang T, Song L, Han Z, Saad W. Overlapping coalition formation games for emerging communication networks. IEEE Network 2016;30(5):46–53. https://doi.org/10.
1109/MNET.2016.7579026
[39] Luan H, Xu Y, Liu D, Du Z, Qian H, Liu X, Tong X. Energy efficient task cooperation for multi-UAV networks: a coalition formation game
approach. IEEE Access 2020;8:149372–84. https://doi.org/10.1109/ACCESS.2020.
[40] Suslova E, Fazli P. Multi-robot task allocation with time window and ordering
constraints, In: 2020 IEEE/RSJ international conference on intelligent robots and
systems (IROS); IEEE; 2020. p. 6909–16. https://doi.org/10.1109/IROS45743.2020.
[41] Hougardy S. The floyd–warshall algorithm on graphs with negative cycles. Inf
Process Lett 2010;110(8–9):279–81. https://doi.org/10.1016/j.ipl.2010.02.001
[42] Acharige SS, Haque ME, Arif MT, Hosseinzadeh N, Hasan KN, Oo AMT. Review
of electric vehicle charging technologies, standards, architectures, and converter
configurations. IEEE Access 2023;11:41218–55.

[43] Tan L, Wu B, Rivera S, Yaramasu V. Comprehensive DC power balance management
in high-power three-level DC–DC converter for electric vehicle fast charging. IEEE
Trans Power Electron 2015;31(1):89–100.
[44] Yan J, Yang Y, Elia Campana P, He J. City-level analysis of subsidy-free solar photovoltaic electricity price, profits and grid parity in China. Nat Energy
2019;4(8):709–17.
[45] Park MW, Kim YD. A systematic procedure for setting parameters in simulated
annealing algorithms. Comput Oper Res 1998;25(3):207–17.
[46] Chen J, Wu Q, Xu Y, Qi N, Guan X, Zhang Y, Xue Z. Joint task assignment and
spectrum allocation in heterogeneous UAV communication networks: a coalition formation game-theoretic approach. IEEE Trans Wireless Commun 2020;20(1):440–52.
https://doi.org/10.1109/TWC.2020.3025316
[47] Wang Z, Zheng F, Liu M. Charging scheduling of electric vehicles considering
uncertain arrival times and time-of-use price. Sustainability 2025;17(3):1100.
[48] Sone SP, Lehtomäki JJ, Khan Z, Umebayashi K, Kim KS. Robust EV scheduling in
charging stations under uncertain demands and deadlines. IEEE Trans Intell Transp
Syst 2024;25(12):21484–99.
[49] Alinia B, Hajiesmaili MH, Crespi N. Online EV charging scheduling with on-arrival
commitment. IEEE Trans Intell Transp Syst 2019;20(12):4524–37.
```
