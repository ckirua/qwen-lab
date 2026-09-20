# Study: autonomous-hello profile compare — v1

**Version:** v1  
**Date (UTC run):** 2026-09-13  
**Slug:** `autonomous-hello`  
**Canonical path:** `docs/studies/2026-09-13-autonomous-hello-v1.md`

## Diff vs previous version

N/A — first versioned run (migrated from unversioned `docs/studies/autonomous-hello-2026-09-13.md` + `docs/autonomous-hello-compare.md`).

Known issues locked in this baseline:
- `cwd: qwen-lab` broke many cmake ticks (daily / daily-spec → BUDGET)
- Nested build path `sandbox/hello-cpp/sandbox/hello-cpp/build` enabled false GO on long-gpu (verifier `ctest_ok=0`)
- Fresh-chat handoff existed but `Last_result` / `last_tool_output.txt` / Next_action hints were weak

---

**Date (UTC):** 2026-09-13T23:07:42Z  
**Lab:** `/home/kirua/app/qwen-lab`  
**Campaign:** `autonomous-hello`  
**Raw metrics:** [`../../results/campaigns/autonomous-hello-v1-compare.tsv`](../../results/campaigns/autonomous-hello-v1-compare.tsv)  
**Short compare:** [`./2026-09-13-autonomous-hello-v1.md#short-compare`](./2026-09-13-autonomous-hello-v1.md#short-compare)

---

## 1. Hypothesis

**H1:** On this autonomous coding loop (fresh context each tick, file memory only, allowlisted tools), **`daily-spec` outperforms `daily`** — fewer iterations and/or lower wall time to verified GO — because draft speculation improves code-shaped generation throughput/quality.

**H2 (secondary):** `long-gpu` (64k YaRN) does **not** help this task (prompt ≪ 32k) and may slow ticks due to larger KV / load cost; included as a negative control (timeboxed).

**H0:** No meaningful difference between `daily` and `daily-spec` on iters-to-GO for this small CMake hello campaign.

---

## 2. Method

| Factor | Setting |
|---|---|
| Driver | `lab-supervisor.sh` only (Qwen ticks) — **no** Cursor `/loop` wakes |
| Model | Qwen2.5-Coder-7B-Instruct Q5_K_M via llama-server `:8080` (`gpt-4o-mini` alias), **NP=1** |
| LLM client | `lab-llm.sh` with `LAB_BASE_URL=http://127.0.0.1:8080/v1` (bypass router to avoid mid-run profile fights) |
| Max iters | **30** |
| Max wall | 4h (daily / daily-spec); **1h timebox** for long-gpu |
| Context each tick | Fresh `messages=[system,user]` only; continuity via TASKBOARD / WORKSTATE / MEMORY / plan.md / `.state/last_tool.txt` |
| Profiles tested | `daily`, `daily-spec`, `long-gpu` (optional); **`long-ram` skipped** |
| Profile hold | `HOLD_PROFILE=1` during non-restore ticks; **`switch-context.sh daily` between profiles and at end** |
| Success (GO) | Agent `declare_gate` GO **and** harness refuses GO without evidence of passing `ctest`; post-run verifier re-runs `ctest` and checks artifact files |
| Writes | `lab-write.sh` allowlist: `sandbox/hello-cpp/**` sources, `campaigns/autonomous-hello/plan.md`, `notes/*.md` |
| Shell | `lab-run.sh` allowlist: cmake/ctest/ls/test under sandbox hello tree |

Deliverable under test: `sandbox/hello-cpp/` CMake C++17 `hello` printing `hello qwen-lab`, CTest green.

---

## 3. Procedure

Exact commands used:

```bash
# Multi-profile study runner (this experiment)
/home/kirua/app/qwen-lab/scripts/lab-compare-profiles.sh

# Equivalent single-profile arm
/home/kirua/app/infer-server/scripts/switch-context.sh daily   # or daily-spec / long-gpu
# HOLD_PROFILE=1 in WORKSTATE for non-daily
export LAB_BASE_URL=http://127.0.0.1:8080/v1 LAB_MODEL=gpt-4o-mini
/home/kirua/app/qwen-lab/scripts/lab-supervisor.sh \
  --max-iters 30 --max-wall-h 4 --campaign autonomous-hello
/home/kirua/app/qwen-lab/scripts/lab-restore-daily.sh
```

Per profile the runner:

1. Restores `daily`, cleans `sandbox/hello-cpp` + `plan.md`, resets `.state/tick.env` (via supervisor `--reset`).
2. `switch-context.sh <profile>`; sets `HOLD_PROFILE=1`.
3. Runs supervisor until OUTCOME or budget.
4. Records metrics + copies artifacts under `results/campaigns/autonomous-hello-<profile>-artifacts/`.
5. Restores `daily` before the next profile.

Campaign id: **`autonomous-hello`** (shared); per-profile result TSV: `results/campaigns/autonomous-hello-<profile>.tsv`.

---

## 4. Results

| profile | wall_s | iters | outcome | ctest | main.cpp | CMakeLists | plan.md | exe | gen tok/s | prompt tok est |
|---|---:|---:|---|---:|---:|---:|---:|---:|---:|---:|
| daily | 248 | 30 | BUDGET | 0 | 1 | 1 | 1 | 0 | 53.582502933496954 | 2887 |
| daily-spec | 206 | 30 | BUDGET | 0 | 1 | 1 | 1 | 0 | 105.47677352101209 | 2811 |
| long-gpu | 52 | 7 | GO | 0 | 1 | 1 | 1 | 0 | 53.92545127934422 | 2866 |

### Artifact proof paths

- **daily**: `artifacts=/home/kirua/app/qwen-lab/results/campaigns/autonomous-hello-v1-daily-artifacts` — expect `main.cpp`, `CMakeLists.txt`, `plan.md`, `ctest.out`
- **daily-spec**: `artifacts=/home/kirua/app/qwen-lab/results/campaigns/autonomous-hello-v1-daily-spec-artifacts` — expect `main.cpp`, `CMakeLists.txt`, `plan.md`, `ctest.out`
- **long-gpu**: `artifacts=/home/kirua/app/qwen-lab/results/campaigns/autonomous-hello-v1-long-gpu-artifacts` — expect `main.cpp`, `CMakeLists.txt`, `plan.md`, `ctest.out`


### Timing / tokens

Values come from `.state/last_llm_timing.json` when llama-server returns `timings`/`usage` (last tick of each run). Prompt token estimate falls back to ~chars/4 of board context if usage missing.

---

## 5. Analysis

- **daily**: incomplete (outcome=BUDGET, ctest=0).
- **daily-spec**: incomplete (outcome=BUDGET, ctest=0).
- **long-gpu**: incomplete (outcome=GO, ctest=0).

**Winner:** `long-gpu`.

Insufficient complete runs to claim a speed winner.

Interpretation notes:

- This is a **single-task** coding micro-campaign; results do not generalize to long-context RAG or multi-file refactors.
- Supervisor ticks are serial (**NP=1**); speculation (`daily-spec`) can raise gen tok/s without changing the sequential role machine.
- Harness allowlist + GO refuse-without-ctest prevents “declared GO” false positives — success requires **sandbox artifacts + ctest**.

---

## 6. Reproducibility

```bash
cd /home/kirua/app/qwen-lab
./scripts/lab-compare-profiles.sh
# Skip long-gpu negative control:
INCLUDE_LONG_GPU=0 ./scripts/lab-compare-profiles.sh
# Confirm sacred daily after:
/home/kirua/app/infer-server/scripts/switch-context.sh status   # CONTEXT_PROFILE=daily
```

Inputs: seeded `campaigns/autonomous-hello/{CAMPAIGN.md,TASKBOARD.seed.md}`, harness scripts under `scripts/`.  
Outputs: `results/campaigns/autonomous-hello-v1-compare.tsv`, per-profile `*-artifacts/`, this study doc.

---

## 7. Limitations

1. **NP=1** — no parallel decode slots; “subagents” are sequential role ticks only.
2. **7B Q5** quality ceiling — model may thrash on cmake flags / JSON schema; budget may exhaust without GO.
3. **Allowlist** — agent cannot use arbitrary shell; failures may reflect harness friction, not raw model skill.
4. **Single task type** — tiny hello+CTest; not representative of large refactors or GPU kernels.
5. **Last-tick timings only** — gen tok/s is not a full-run mean unless aggregated from logs.
6. **Profile switch cost** (~10–30s) included in wall time for each arm.
7. **Router bypassed** during runs — matches intentional isolation; Cursor-via-8090 behavior may differ if model id triggers switches.

---

## Appendix — environment snapshot

- Host GPU: RTX 2070 8GB (sm_75)
- Sacred restore: `scripts/lab-restore-daily.sh` → `switch-context.sh daily`
- Compare runner: `scripts/lab-compare-profiles.sh`