# CUDA graphs capture/replay on Turing (sm_75)

## What we measured

Toy: `sandbox/cuda-graphs-toy` — vectorAdd N=1 048 576, 1000 eager launches vs 1000 `cudaGraphLaunch` replays of a single captured launch. Three trials on RTX 2070 (sm_75).

| Trial | eager_ms | graph_ms | speedup |
|---|---:|---:|---:|
| 1 | 33.12 | 32.64 | 1.015 |
| 2 | 33.09 | 32.69 | 1.012 |
| 3 | 33.10 | 32.72 | 1.012 |

TSV: `results/campaigns/cuda-graphs-101.tsv`

## Capture / replay (concepts)

1. **Eager:** each `kernel<<<>>>` pays CPU launch overhead + GPU work.
2. **Capture:** `cudaStreamBeginCapture` → record work into a `cudaGraph_t` → `cudaGraphInstantiate` → `cudaGraphLaunch` replays without re-doing host launch packaging.
3. Graphs help when **launch overhead ≫ kernel body**. They do little when the kernel already does substantial work (as here with N=1M).

## When graphs help vs not on Turing

- **Help:** tiny kernels, many launches, dependency graphs that amortize setup (e.g. many small ops).
- **Flat / not worth it:** large vector bodies, already-fused ops, or frameworks where graphs are already internalized — matches prior llama.cpp graphs SKIP ship (~flat ~0.3% on daily).
- This toy is **learning only**; it does not reopen the product graphs decision.
