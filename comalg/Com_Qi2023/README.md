# Qi2023 Algorithm - PGG-TS Implementation

## Overview

This folder contains the implementation of the **Preference Gravity-Guided Tabu Search (PGG-TS)** algorithm for distributed overlapping coalition formation, as described in Qi et al. (2023).

## Files

- **Qi2023_main.m** - Main algorithm implementation (345 lines)
- **alg_structure** - Algorithm pseudocode in LaTeX format
- **ALGORITHM_STRUCTURE.md** - Detailed algorithm explanation (Chinese)
- **MODIFICATIONS.md** - Modification log and changelog (Chinese)
- **SUMMARY.md** - Quick summary of changes (Chinese)
- **README.md** - This file

## Quick Start

### Running the Algorithm

```matlab
% Add paths
addpath('Main_fun/');
addpath('SA/');
addpath('comalg/Com_Qi2023/');

% Run comparison platform
Compare_Algorithms  % Set algorithms_to_run_ids = [4]

% Or run standalone test
cd tests
test_Qi2023
```

### Algorithm Interface

```matlab
function [Value_data, history_data] = Qi2023_main(agents, tasks, AddPara, Value_Params)
```

**Inputs:**
- `agents` - Agent struct array (position, resources, capabilities)
- `tasks` - Task struct array (position, value, resource demands)
- `AddPara` - Additional parameters
- `Value_Params` - Global algorithm parameters

**Outputs:**
- `Value_data` - Final agent states with coalition structure
- `history_data` - Historical data for each iteration

## Algorithm Structure

```
Initialization
    ↓
Main Loop (while k ≤ K_max AND k_stable ≤ K_len)
    ↓
    For each agent n:
        1. Leave: Randomly leave partial resources
        2. Gravity: Calculate preference gravity F and probability P
        3. Exchange: Reallocate resources based on P
        4. Tabu: Check if new structure is in tabu list
        5. Utility: Accept if utility improves and not tabu
        6. Update: Update temperature and tabu list
    ↓
Output: Stable coalition structure SC*
```

## Key Features

### 1. Preference Gravity Field
- Guides agents to select high-value, nearby, under-allocated tasks
- Formula: `F[m,k] = (Value × Remaining_Demand) / Distance²`

### 2. Tabu Search
- Maintains a tabu list of recently visited structures
- Prevents cycling and improves search diversity

### 3. Boltzmann Temperature
- Controls exploration vs exploitation balance
- High temperature → more exploration
- Low temperature → more exploitation
- Cooling schedule: `Γ(k+1) = α × Γ(k)`

## Parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| L_tabu | 10 | Tabu list length |
| K_len | 20 | Stability threshold |
| K_max | 100 | Maximum iterations |
| Gamma | 100 | Initial temperature |
| alpha | 0.98 | Cooling rate |
| p_leave | 0.3 | Leave probability |

## Performance

**Time Complexity:** O(K_max × N × M × K × L_tabu)

**Typical Runtime:** 1-5 seconds for N=6, M=10, K=6, K_max=100

## Testing

Run the test suite:
```matlab
cd tests
test_Qi2023
```

**Test Coverage:**
- ✅ Basic functionality
- ✅ Output format validation
- ✅ Convergence verification
- ✅ Utility improvement
- ✅ Resource constraint satisfaction

## Comparison with Other Algorithms

| Algorithm | Search Strategy | Speed | Quality | Complexity |
|-----------|----------------|-------|---------|------------|
| **Qi2023** | Tabu + Gravity | Medium | High | O(K×N×M×K×L) |
| SA_Value | Simulated Annealing | Slow | High | O(K×N×M×K) |
| Huo2025 | Greedy + Belief | Fast | Medium | O(K×N×M) |
| Greedy | Pure Greedy | Very Fast | Low | O(N×M) |

## Known Issues

1. **Simple leave strategy** - Uses random leaving (can be improved)
2. **Hash function** - Uses `mat2str` (consider DataHash for large-scale)
3. **No aspiration criterion** - Cannot accept tabu solutions even if excellent

## Future Improvements

- [ ] Adaptive parameter tuning
- [ ] Implement aspiration criterion
- [ ] Multi-objective optimization support
- [ ] Parallelization (parfor)
- [ ] GPU acceleration

## References

1. Qi et al. (2023). "Preference Gravity-Guided Tabu Search for Distributed Overlapping Coalition Formation"
2. Glover, F. (1989). "Tabu Search - Part I". ORSA Journal on Computing.
3. Kirkpatrick, S. (1983). "Optimization by Simulated Annealing". Science.

## Citation

If you use this implementation, please cite:

```bibtex
@article{qi2023preference,
  title={Preference Gravity-Guided Tabu Search for Distributed Overlapping Coalition Formation},
  author={Qi, et al.},
  journal={Journal Name},
  year={2023}
}
```

## License

This implementation is part of the Overlap Coalition Formation project.

## Contact

For questions or issues, please refer to the main project repository.

---

**Last Updated:** 2026-01-27
**Version:** 1.0
**Status:** ✅ Ready for use
