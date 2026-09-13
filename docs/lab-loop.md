# Qwen Lab `/loop` (local monitored shell)

Stop-when-GO/NO-GO-or-budget loop for `scripts/lab-tick.sh`. Uses the Cursor **loop** skill’s **monitored shell output** path (local IDE — not cloud subscription timers).

## Goal

Run the active campaign (default `cuda-graphs-101`) one tick at a time with durable file memory. Max **12** iterations or **6h**. Always end on **`daily`**.

## Arm once

1. Check terminals for an existing `AGENT_LOOP_TICK_qwenlab` / `AGENT_LOOP_WAKE_qwenlab` loop — do not duplicate.
2. Prefer **dynamic wake** (GPU ticks vary):

```bash
# After each tick completes, the agent re-arms:
sleep 5
echo 'AGENT_LOOP_WAKE_qwenlab {"prompt":"Run /home/kirua/app/qwen-lab/scripts/lab-tick.sh; if Outcome set or budget exhausted, stop this loop and confirm daily profile."}'
```

Fixed 15m alternative (unsupervised overnight — still stop on Outcome):

```bash
while true; do
  sleep 900
  echo 'AGENT_LOOP_TICK_qwenlab {"prompt":"Run /home/kirua/app/qwen-lab/scripts/lab-tick.sh; if Outcome set or budget exhausted, stop this loop and confirm daily profile."}'
done
```

3. Start the background shell with `notify_on_output` pattern `^AGENT_LOOP_WAKE_qwenlab` or `^AGENT_LOOP_TICK_qwenlab`.
4. **Run one tick immediately** (`/home/kirua/app/qwen-lab/scripts/lab-tick.sh`) before the first sleep.
5. Each wake: exactly one `lab-tick.sh`; on Outcome or budget → kill sleeper PID, run `scripts/lab-restore-daily.sh`, confirm `switch-context.sh status` → `daily`. Do not re-arm.

## Manual / headless

```bash
cd /home/kirua/app/qwen-lab
./scripts/lab-status.sh
./scripts/lab-tick.sh
./scripts/lab-supervisor.sh --max-iters 12 --campaign cuda-graphs-101
./scripts/lab-restore-daily.sh
```

## Stop

Kill the tracked sleeper/loop PID; do not re-arm. Run `./scripts/lab-restore-daily.sh` if profile is not `daily`. Confirm Outcome in `TASKBOARD.md` / `.state/tick.env`.

## Sentinels

| Sentinel | Mode |
|---|---|
| `AGENT_LOOP_WAKE_qwenlab` | Dynamic re-arm after each tick |
| `AGENT_LOOP_TICK_qwenlab` | Fixed interval (e.g. 900s) |
