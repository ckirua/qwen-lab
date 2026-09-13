# Memory

Durable lessons. Append-only bullets under dated headings. Cap ~80 lines; compact into `notes/` when exceeded.

## 2026-09-13
- Lab root is `/home/kirua/app/qwen-lab/` (sibling of infer-server); never nest under daily-driver ops.
- Prefer router `http://127.0.0.1:8090/v1` model `gpt-4o-mini-spec`; fallback `8080` `gpt-4o-mini`.
- CUDA toolkit for toys: `/home/kirua/app/deps/usr/local/cuda-13.1` (sm_75 / RTX 2070).
- Product verdict for llama.cpp graphs is already SKIP ship (P2); cuda-graphs-101 is learning only.
- Planned T1: Next task is to probe nvcc, sm_75, and free VRAM; write notes/snippet.
- T1 probe: nvcc 13.1 at deps/usr/local/cuda-13.1; RTX 2070 sm_75; notes/2026-09-13-toolchain-probe.md
- T2/T3: cuda-graphs-toy built; 3 trials N=1M ×1000 launches ≈1.01× graph vs eager (body-dominated).
- H1 refuted at N=1M; H2 supported — graphs matter when launch overhead dominates (see notes/2026-09-13-cuda-graphs-learning.md).
- Phase B (llama graphs remeasure) left behind HUMAN_GATE / LAB_CONFIRM_LLAMA_GRAPHS=1.
- Planned T5: Next task is to write the campaign summary in campaigns/cuda-graphs-101/CAMPAIGN.md.
- Planned T5: Next task is to write the campaign summary in campaigns/cuda-graphs-101/CAMPAIGN.md.
- dry-run tick: no tools
- Planned T6: Next task is to measure llama.cpp graphs with CUDA graphs for Turing test.
