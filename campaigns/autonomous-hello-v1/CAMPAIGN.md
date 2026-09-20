# Campaign: autonomous-hello

## Goal

Finish a minimal CMake C++ hello project under `sandbox/hello-cpp/` fully via Qwen lab ticks (file memory only; fresh LLM context each tick). Success = green `ctest` + `declare_gate` GO.

## Gates

| Outcome | Condition |
|---|---|
| **GO** | `ctest --test-dir sandbox/hello-cpp/build --output-on-failure` exit 0 **and** `campaigns/autonomous-hello/plan.md` exists; agent `declare_gate` GO |
| **NO-GO** | Cannot produce green `ctest` after budget, or repeated allowlist denies / path escapes |
| **BUDGET** | ITER≥MAX_ITERS (default 30) or wall≥4h |

## Deliverable

- `sandbox/hello-cpp/main.cpp` prints `hello qwen-lab` and returns 0
- `sandbox/hello-cpp/CMakeLists.txt` — C++17, `add_executable(hello …)`, `enable_testing()` + `add_test`
- Build + test under `sandbox/hello-cpp/build`

## Non-goals

- No GPU profile required for the hello work itself (compare runner may hold non-daily profiles for study)
- No edits under `infer-server/`, harness `scripts/`, or outside sandbox allowlist

## Board

See `TASKBOARD.md` in this directory (mirrors root board while this campaign is active).
