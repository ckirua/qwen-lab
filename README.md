# Qwen Lab Autoresearch Harness

Autonomous **experiment loop** for learning/probes under `/home/kirua/app/qwen-lab/`.
Sibling of `infer-server` — never nests under the daily driver ops tree.

## Safety summary

- Daily profile is sacred; every tick restores `CONTEXT_PROFILE=daily` unless `HOLD_PROFILE=1`.
- Allowlisted tools only (`ALLOWLIST.md` + `scripts/lab-run.sh` / `lab-write.sh`).
- Stop on GO / NO-GO / budget.
- No silent edits to shipped `infer-server` profile maps.

## Campaigns

| Id | Goal |
|---|---|
| `cuda-graphs-101` | CUDA graphs learning toy (complete) |
| `autonomous-hello` | Autonomous CMake C++ hello + ctest (write_file + supervisor) |

## Headless supervisor (Qwen-only)

```bash
/home/kirua/app/qwen-lab/scripts/lab-supervisor.sh \
  --max-iters 30 --campaign autonomous-hello
```

## Multi-profile compare (versioned studies)

```bash
/home/kirua/app/qwen-lab/scripts/lab-compare-profiles.sh
# auto-bumps docs/studies/YYYY-MM-DD-autonomous-hello-vN.md
# + results/campaigns/autonomous-hello-vN-*.tsv
# + campaigns/autonomous-hello-vN/
```

Index: [`docs/studies/INDEX.md`](docs/studies/INDEX.md)  
Never overwrite prior `vN` — bump versions. See `MEMORY.md` for latest study link.

## Cursor `/loop` (optional)

```bash
sleep 5
echo 'AGENT_LOOP_WAKE_qwenlab {"prompt":"Run /home/kirua/app/qwen-lab/scripts/lab-tick.sh; if Outcome set or budget exhausted, stop this loop and confirm daily profile."}'
```

## One tick

```bash
/home/kirua/app/qwen-lab/scripts/lab-tick.sh
/home/kirua/app/qwen-lab/scripts/lab-status.sh
```

## LLM

Prefer direct `:8080` with the live GGUF alias during profile compares (bypass router). Default `lab-llm.sh` still prefers router `:8090` `gpt-4o-mini-spec` with `:8080` fallback to `/v1/models` id.
