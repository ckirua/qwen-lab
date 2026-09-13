# Campaign: cuda-graphs-101

## Goal

Learn CUDA graphs on sm_75 (RTX 2070) via a toy microbench; optionally remeasure llama.cpp graphs for pedagogy; document lessons in `MEMORY.md`. **Not** a product change path (P2 already SKIP ship).

## Gates

| Outcome | Condition |
|---|---|
| **GO (learning)** | Toy bench TSV complete (graphs vs no-graphs ≥3 runs) + `notes/` writeup of capture/replay + when graphs help vs not on Turing |
| **NO-GO** | Toolchain missing / cannot build toy after 3 attempts → document blocker; still restore daily |
| Phase B optional | If human sets `LAB_CONFIRM_LLAMA_GRAPHS=1` and HUMAN_GATE approved: remeasure daily graphs on/off; expect ~flat (~0.3%); MEMORY only — **does not** change shipped config |

## Phases

- **A** — Probe toolchain, scaffold toy, bench ≥3 trials, update hypotheses/memory, declare GO
- **B** — Optional human-gated llama graphs remeasure (T6)

## Board

See `TASKBOARD.md` in this directory (mirrors root campaign board) and root `/home/kirua/app/qwen-lab/TASKBOARD.md`.

## Summary

Phase A complete:

- Toolchain: nvcc 13.1, sm_75, notes in `notes/2026-09-13-toolchain-probe.md`.
- Toy: `sandbox/cuda-graphs-toy` CMake CUDA 75 vectorAdd eager vs graph replay.
- Bench: 3 trials in `results/campaigns/cuda-graphs-101.tsv` — ~1.01× at N=1M (kernel body dominates launch overhead).
- Learning writeup: `notes/2026-09-13-cuda-graphs-learning.md`.
- Hypotheses: H1 refuted at this problem size; H2 supported; H3 open pending optional phase B.
- T6 not run (HUMAN_GATE unset). No shipped config changes. Daily profile restored after ticks.
