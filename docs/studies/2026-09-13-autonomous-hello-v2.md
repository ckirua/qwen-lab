# Study: autonomous-hello profile compare — v2

**Version:** v2  
**Date (UTC):** 2026-09-13T23:22:45Z (2026-09-13)  
**Slug:** `autonomous-hello`  
**Lab:** `/home/kirua/app/qwen-lab`  
**Raw metrics:** [`../../results/campaigns/autonomous-hello-v2-compare.tsv`](../../results/campaigns/autonomous-hello-v2-compare.tsv)  
**Board snapshot:** [`../../campaigns/autonomous-hello-v2/`](../../campaigns/autonomous-hello-v2/)  
**INDEX:** [`INDEX.md`](./INDEX.md)

## Diff vs previous version

Previous: [`2026-09-13-autonomous-hello-v1.md`](./2026-09-13-autonomous-hello-v1.md)
- **daily**: BUDGET/0 @ 30iters/248s → GO/1 @ 9iters/66s
- **daily-spec**: BUDGET/0 @ 30iters/206s → GO/1 @ 12iters/78s
- **long-gpu**: GO/0 @ 7iters/52s → GO/1 @ 8iters/58s
- Harness deltas expected in this version: cwd normalize + force lab-root for sandbox paths; cmake auto `-S`; GO requires canonical `build/hello`; handoff via WORKSTATE Next_action + `.state/last_tool_output.txt` (fresh chat each tick).

---

## 1. Hypothesis

**H1:** On this autonomous coding loop (fresh context each tick, file memory only, allowlisted tools), **`daily-spec` outperforms `daily`** — fewer iterations and/or lower wall time to verified GO — because draft speculation improves code-shaped generation throughput/quality.

**H2 (secondary):** `long-gpu` does **not** help this small-prompt task; timeboxed negative control.

**H0:** No meaningful difference between `daily` and `daily-spec` on iters-to-GO.

---

## 2. Method

| Factor | Setting |
|---|---|
| Driver | `lab-supervisor.sh` only (Qwen ticks) — **no** Cursor `/loop` wakes |
| Model | Qwen2.5-Coder-7B Q5_K_M via `:8080` (`gpt-4o-mini`), **NP=1** |
| Max iters | **30** |
| Context each tick | Fresh `messages=[system,user]` only |
| Handoff files | TASKBOARD, WORKSTATE (Next_action/Last_result/Handoff), MEMORY, plan.md, `.state/last_tool_output.txt` |
| Profiles | `daily`, `daily-spec`, `long-gpu` (optional); **long-ram skipped** |
| Success | `declare_gate` GO **and** verifier `ctest` + canonical `sandbox/hello-cpp/build/hello` |

---

## 3. Procedure

```bash
/home/kirua/app/qwen-lab/scripts/lab-compare-profiles.sh
# bumps to next vN automatically; never overwrites prior versioned paths
```

Per profile: restore daily → clean sandbox → switch profile + HOLD_PROFILE=1 → supervisor → metrics → restore daily.

---

## 4. Results

| profile | wall_s | iters | outcome | ctest | main.cpp | CMakeLists | plan.md | exe | gen tok/s | prompt tok est |
|---|---:|---:|---|---:|---:|---:|---:|---:|---:|---:|
| daily | 66 | 9 | GO | 1 | 1 | 1 | 1 | 1 | 54.00852296037333 | 2900 |
| daily-spec | 78 | 12 | GO | 1 | 1 | 1 | 1 | 1 | 86.46142219432684 | 3175 |
| long-gpu | 58 | 8 | GO | 1 | 1 | 1 | 1 | 1 | 53.58003086996274 | 3032 |

### Artifact proof paths

- **daily**: `artifacts=/home/kirua/app/qwen-lab/results/campaigns/autonomous-hello-v2-daily-artifacts`
- **daily-spec**: `artifacts=/home/kirua/app/qwen-lab/results/campaigns/autonomous-hello-v2-daily-spec-artifacts`
- **long-gpu**: `artifacts=/home/kirua/app/qwen-lab/results/campaigns/autonomous-hello-v2-long-gpu-artifacts`


---

## 5. Analysis

- **daily**: verified GO in 9 iters / 66s (ctest pass + `build/hello` prints `hello qwen-lab`).
- **daily-spec**: verified GO in 12 iters / 78s; higher last-tick gen tok/s (~86 vs ~54) but **more** iters and wall than daily.
- **long-gpu**: verified GO in 8 iters / 58s; fastest wall/iters on this single run, but prompt ≪ 32k so YaRN-64k is not a causal advantage — noise / switch timing likely dominates.

**Winner (verified GO, harness score = GO∧ctest then min iters/wall):** `long-gpu`.

**Hypothesis verdicts (this run):**
- **H1 unsupported / leaning H0:** `daily-spec` did **not** beat `daily` on iters or wall to verified GO (12/78s vs 9/66s). Speculation raised gen tok/s without shortening the sequential role loop.
- **H2 mixed:** `long-gpu` was not harmful and edged the scoreboard, but this micro-task cannot credit long context; treat as negative-control noise, not a reason to prefer long-gpu for hello+CTest.
- vs **v1:** harness fixes eliminated false GO / BUDGET thrash — all three arms now produce real `exe_ok=1` + `ctest_ok=1`.

---

## 6. Reproducibility

```bash
cd /home/kirua/app/qwen-lab
./scripts/lab-compare-profiles.sh          # creates next vN
INCLUDE_LONG_GPU=0 ./scripts/lab-compare-profiles.sh
/home/kirua/app/infer-server/scripts/switch-context.sh status  # expect daily
```

Outputs for this version:
- `docs/studies/2026-09-13-autonomous-hello-v2.md`
- `results/campaigns/autonomous-hello-v2-compare.tsv`
- `results/campaigns/autonomous-hello-v2-<profile>.tsv` + `-artifacts/`
- `campaigns/autonomous-hello-v2/`

---

## 7. Limitations

1. NP=1 sequential role ticks only.
2. 7B Q5 quality ceiling.
3. Allowlist friction ≠ raw model skill.
4. Single micro-task (hello+CTest).
5. Last-tick timings only.
6. Profile switch cost in wall time.
