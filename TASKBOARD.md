# Taskboard — cuda-graphs-101

## Meta
- Campaign: cuda-graphs-101
- Budget: iters 5/12, wall started 2026-09-13T21:25:57Z
- Outcome: GO (learning)

## TODO
- [ ] T6: [HUMAN_GATE] Optional llama graphs remeasure via allowlisted bench → MEMORY only

## DOING

## DONE
- [x] T1: Probe nvcc, sm_75, free VRAM; write notes/ snippet
- [x] T2: Scaffold sandbox/cuda-graphs-toy (CMake CUDA 75, vectorAdd graph vs eager)
- [x] T3: Run bench ≥3 trials → results/campaigns/cuda-graphs-101.tsv
- [x] T4: Update HYPOTHESES.md (H1 graph replay overhead) + MEMORY
- [x] T5: Write campaign summary in campaigns/cuda-graphs-101/CAMPAIGN.md → declare GO (learning)

## BLOCKED

## Gates
- GO when: Toy bench TSV complete (graphs vs no-graphs ≥3 runs) + notes/ writeup of capture/replay + when graphs help vs not on Turing
- NO-GO when: Toolchain missing / cannot build toy after 3 attempts → document blocker; still restore daily

## HUMAN_GATE
- [ ] approved: (empty — flip to `- [x] approved: <ISO> <initials>` before T6 / live llama graphs measure)
