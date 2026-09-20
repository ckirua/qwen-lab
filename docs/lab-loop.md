# Qwen Lab `/loop` (local monitored shell) + headless supervisor

Stop-when-GO/NO-GO-or-budget for `scripts/lab-tick.sh`. Two drivers:

1. **Headless (preferred for studies):** `lab-supervisor.sh` / `lab-compare-profiles.sh` — Qwen-only ticks, no Cursor wakes.
2. **Cursor monitored shell:** dynamic wake sentinel (below).

## Autonomous-hello (inaugural coding campaign)

| Item | Value |
|---|---|
| Campaign | `autonomous-hello` |
| Sandbox | `sandbox/hello-cpp/` (agent-created) |
| Success | green `ctest` + artifacts + `declare_gate` GO |
| Budget | **MAX_ITERS=30**, MAX_WALL_H=4 |
| Continuity | Files only; **fresh LLM context each tick** |

### Arm headless (single profile)

```bash
/home/kirua/app/infer-server/scripts/switch-context.sh status   # expect daily
/home/kirua/app/qwen-lab/scripts/lab-supervisor.sh \
  --max-iters 30 --max-wall-h 4 --campaign autonomous-hello
/home/kirua/app/qwen-lab/scripts/lab-restore-daily.sh
```

### Multi-profile study compare (versioned)

```bash
/home/kirua/app/qwen-lab/scripts/lab-compare-profiles.sh
# INCLUDE_LONG_GPU=0 to skip long-gpu timebox arm
```

Each run **bumps** a new version (never overwrites):

| Artifact | Path |
|---|---|
| Study | `docs/studies/YYYY-MM-DD-autonomous-hello-vN.md` |
| INDEX | `docs/studies/INDEX.md` |
| Raw TSV | `results/campaigns/autonomous-hello-vN-compare.tsv` |
| Per-profile | `results/campaigns/autonomous-hello-vN-<profile>.tsv` + `-artifacts/` |
| Board snapshot | `campaigns/autonomous-hello-vN/` |

Always restores **`CONTEXT_PROFILE=daily`** between profiles and at end.

### Role-tick / handoff protocol

Each `lab-tick.sh` uses a **fresh chat** (`messages=[system,user]` only). Continuity is files only:

1. Assemble SAFETY + ALLOWLIST + TASKBOARD + WORKSTATE + plan excerpt + MEMORY + **`.state/last_tool_output.txt`** (≤~8k tok).
2. Call `lab-llm.sh` — no prior assistant turns.
3. One action → update boards + WORKSTATE (`Next_action`, `Last_result`, `## Handoff`) + truncate tool output for the next tick.
4. Restores daily unless `HOLD_PROFILE=1`.

Suggested cadence: T1 plan → T2–T3 implement (`write_file`) → T4–T5 cmake/ctest → T6 gate.

## Cursor `/loop` (optional)

1. Check terminals for an existing `AGENT_LOOP_WAKE_qwenlab` sleeper — do not duplicate.
2. Dynamic wake:

```bash
sleep 5
echo 'AGENT_LOOP_WAKE_qwenlab {"prompt":"Run /home/kirua/app/qwen-lab/scripts/lab-tick.sh once. Context is file-only. If .state/tick.env OUTCOME is set or ITER>=MAX, stop this loop, run lab-restore-daily.sh, confirm daily profile, and summarize GO/NO-GO/BUDGET."}'
```

`notify_on_output` pattern: `^AGENT_LOOP_WAKE_qwenlab`

3. Run one tick immediately before the first sleep. Each wake: exactly one `lab-tick.sh`.

## Stop

- Outcome `GO` | `NO-GO` | `BUDGET` in `.state/tick.env`
- Kill sleeper PID if using Cursor loop; run `scripts/lab-restore-daily.sh`
- Confirm `switch-context.sh status` → `CONTEXT_PROFILE=daily`
