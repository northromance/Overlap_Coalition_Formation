
## Shi2024 Transfer/Join 阶段去除 Preference_gain（2026-03-22）

- `comalg/alg4_Shi2024/Shi2024_main.m` — Transfer（C段）和 Join（D段）不再调用 Preference_gain，改为可行性通过即直接接受到工作副本；Preference_gain 仅在最终门控（E段）调用一次，与 Qi2023 结构对齐。预期每 agent 每迭代调用次数从 ~67 次降至 1 次（约 67 倍加速）。
