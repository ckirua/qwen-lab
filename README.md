# Qwen Lab Autoresearch Harness

Autonomous **experiment loop** for learning/probes under `/home/kirua/app/qwen-lab/`.
Sibling of `infer-server` — never nests under the daily driver ops tree.

## Safety summary

- Daily profile is sacred; every tick restores `CONTEXT_PROFILE=daily` unless `HOLD_PROFILE=1`.
- Allowlisted tools only (`ALLOWLIST.md` + `scripts/lab-run.sh`).
- Stop on GO / NO-GO / budget (12 iters or 6h for `cuda-graphs-101`).
- No silent edits to shipped `infer-server` profile maps.

## Arm / stop (Cursor `/loop`)

See [`docs/lab-loop.md`](docs/lab-loop.md).

```bash
# Dynamic wake (preferred)
sleep 5
echo 'AGENT_LOOP_WAKE_qwenlab {"prompt":"Run /home/kirua/app/qwen-lab/scripts/lab-tick.sh; if Outcome set or budget exhausted, stop this loop and confirm daily profile."}'
```

`notify_on_output` pattern: `^AGENT_LOOP_WAKE_qwenlab`

## Headless supervisor

```bash
/home/kirua/app/qwen-lab/scripts/lab-supervisor.sh --max-iters 12 --campaign cuda-graphs-101
```

## One tick

```bash
/home/kirua/app/qwen-lab/scripts/lab-tick.sh
/home/kirua/app/qwen-lab/scripts/lab-status.sh
```

## LLM

Prefer `http://127.0.0.1:8090/v1` model `gpt-4o-mini-spec`; fallback `8080` `gpt-4o-mini`.

## Inaugural campaign

`campaigns/cuda-graphs-101` — CUDA graphs learning on sm_75 (toy microbench). Not a ship path.
