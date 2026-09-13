# Hypotheses

| ID | Claim | Status | Evidence |
|---|---|---|---|
| H1 | CUDA graph replay cuts launch overhead vs eager launches for tiny kernels (vectorAdd N=1M) on sm_75 | refuted | results/campaigns/cuda-graphs-101.tsv (~1.01×; body dominates) |
| H2 | Graphs help most when kernel bodies are short and launch count is high; less when work per launch dominates | supported | notes/2026-09-13-cuda-graphs-learning.md |
| H3 | Remeasuring llama.cpp graphs on daily remains ~flat (~0.3%); does not change SKIP ship | open | docs/speculative-gates.md P2 (phase B optional) |
