# Qwen Lab — Allowlist

`lab-run.sh` accepts only commands matching these patterns (prefix / path checks). Denied commands exit nonzero.

| Pattern | Purpose |
|---|---|
| `scripts/lab-status.sh` | status |
| `scripts/lab-restore-daily.sh` | restore daily |
| `cmake -B build …` / `cmake --build` under `sandbox/**` | toy builds |
| `sandbox/**/bench.sh` | toy benches |
| `nvidia-smi` / `nvidia-smi -q -d MEMORY` | VRAM check |
| `curl -sS http://127.0.0.1:8080/v1/models` | readiness |
| `curl -sS http://127.0.0.1:8090/v1/models` | router |
| `/home/kirua/app/infer-server/scripts/switch-context.sh status\|daily\|daily-spec` | status / restore / coding profile |
| `/home/kirua/app/infer-server/scripts/bench-final-pass.sh` **only** with env `LAB_CONFIRM_LLAMA_GRAPHS=1` | optional phase B |
| `rg` / `sed -n` / `head` / `cat` on paths under `qwen-lab/` and `infer-server/docs/**` | read-only research |
| `nvcc --version` | toolchain probe |

## Denied (non-exhaustive)

- Any write under `infer-server/` except via allowlisted switch/bench scripts
- `systemctl` except as called inside those scripts
- Network except localhost 8080/8090
- Edits to `ninfer-2070/`
- Package install (`apt`, `pip install`, etc.)
- Pipelines that escape the allowlist (`bash -c`, `eval`, `sudo`, …)
