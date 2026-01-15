# Qin2025 PSO scaffold overview

## Algorithm entry
- Path: `Com_Qin2025/Qin2025_main.m`
- Behavior: PSO-based placeholder optimizing total utility. Encoding = membership (M×N) + resource allocation (M×N×K); fitness = sum(task.value × completion) − λ·resource_gap. Outputs `coalitionstru`, `SC`, `agentresources`, `totalvalue`, tagged `algorithm = "Qin2025_PSO"`.
- TODOs: add finer energy/wait/path cost modeling and richer scheduling (start times, waiting rules) if needed.

## Test
- Path: `test/test_qin2025.m`
- Content: builds a small scenario, calls `Qin2025_main` for a smoke test, and asserts that `Value_data` includes the coalition matrix.
- Run (MATLAB): `matlab -batch "run('test/test_qin2025.m')"`

## Next steps
- Refine fitness with realistic costs/penalties; expand encoding if you need explicit timing/wait decisions.
- Keep inputs/outputs (`Value_data`, `history_data`) stable for `Compare_Algorithms` and plotting helpers.
