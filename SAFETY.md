# Qwen Lab — Safety Rules

Hard rules. Loaded into every `lab-llm.sh` system prompt. Violations are bugs.

1. **Never** edit `infer-server/scripts/switch-context.sh` profile maps, systemd units, or `best-known-config.md` without a human gate (`BLOCKED` + note in TASKBOARD).
2. **Never** leave `infer-qwen` on a non-`daily` profile after a tick unless a human set `HOLD_PROFILE=1` in `WORKSTATE.md`.
3. Max **12** ticks per campaign (`cuda-graphs-101`) or **6 wall hours**, whichever comes first. Stop on GO / NO-GO / BUDGET.
4. Destructive or live-affecting steps require `## HUMAN_GATE` in `TASKBOARD.md` with `- [x] approved: <ISO> <initials>` before `lab-run` will execute them.
5. Sandbox builds only under `qwen-lab/sandbox/**`. No `rm -rf` outside sandbox. No `git push`. No credential reads.
6. Concurrent ticks forbidden: hold `flock locks/lab.lock`.
7. GPU experiment: acquire `locks/gpu-experiment.lock`, snapshot profile, run, **always** call `lab-restore-daily.sh` via `trap EXIT`.
8. All harness writes stay under `/home/kirua/app/qwen-lab/` except allowlisted temporary profile switches that must be restored.
9. Do not edit `ninfer-2070/`, install packages, or curl anything except localhost `8080` / `8090`.
10. Inaugural campaign is **learning only** — do not ship config changes from lab findings.
