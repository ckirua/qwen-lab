#!/usr/bin/env bash
# OpenAI-compatible chat client for qwen-lab.
# Prefers 8090 gpt-4o-mini-spec (Cursor catalog on the router).
# Falls back to 8080 using the live llama-server alias (real GGUF name).
# Compare runners may override LAB_BASE_URL / LAB_MODEL to hit :8080 directly.
set -euo pipefail

LAB_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BASE_URL="${LAB_BASE_URL:-http://127.0.0.1:8090/v1}"
MODEL="${LAB_MODEL:-gpt-4o-mini-spec}"
FALLBACK_URL="${LAB_FALLBACK_URL:-http://127.0.0.1:8080/v1}"

resolve_8080_model() {
  curl -sS --max-time 3 "http://127.0.0.1:8080/v1/models" | python3 -c \
    'import json,sys; print(json.load(sys.stdin)["data"][0]["id"])' 2>/dev/null \
    || echo "Qwen2.5-Coder-7B-Instruct"
}

FALLBACK_MODEL="${LAB_FALLBACK_MODEL:-$(resolve_8080_model)}"
TIMEOUT_S="${LAB_LLM_TIMEOUT:-120}"
USER_MSG="${1:-}"
SYSTEM_EXTRA="${2:-}"
CAMPAIGN_HINT="${CAMPAIGN_ID:-autonomous-hello}"

if [[ -z "${USER_MSG}" ]]; then
  USER_MSG="$(cat)"
fi

SYSTEM_PROMPT="$(cat <<EOF
You are the qwen-lab autonomous agent finishing campaign ${CAMPAIGN_HINT}.
Propose exactly ONE action per tick as JSON.
Context was RESET this tick — trust TASKBOARD / WORKSTATE / plan.md / MEMORY / last_tool only (no prior chat).
Follow SAFETY.md and ALLOWLIST.md strictly. Never edit infer-server profiles or leave non-daily without HOLD.
Daily driver is sacred. File memory is source of truth.

Return ONLY a JSON object (no markdown fences) with this shape:
{
  "action": "advance_task" | "write_file" | "update_memory" | "declare_gate" | "block_human",
  "task_id": "T1",
  "command": "allowlisted shell command string or empty",
  "cwd": "optional cwd under lab root",
  "path": "relative path for write_file",
  "content": "full file contents for write_file",
  "memory_bullets": ["optional", "≤5 bullets"],
  "gate": "GO" | "NO-GO" | "",
  "rationale": "one short sentence",
  "hypothesis_updates": [{"id":"H1","status":"supported|refuted|open","evidence":"path"}]
}

Rules:
- Prefer the single next TODO; at most one DOING.
- Prefer write_file for new sources / plan.md; advance_task for cmake/ctest/ls/test.
- command must match ALLOWLIST (no pipelines, no sudo, no bash -c).
- write_file: one file per tick; path MUST be lab-root relative, e.g. `sandbox/hello-cpp/CMakeLists.txt`, `sandbox/hello-cpp/main.cpp`, `campaigns/autonomous-hello/plan.md`, or `notes/*.md` (never bare `CMakeLists.txt`); content ≤32KiB.
- If last_tool shows DENIED path, fix the path next tick — do not repeat the same bare filename.
- CRITICAL: For T4/T5 never leave command empty and never use plan_only. T4 command example: `cmake -B sandbox/hello-cpp/build -S sandbox/hello-cpp` (next tick: `cmake --build sandbox/hello-cpp/build`). T5: `ctest --test-dir sandbox/hello-cpp/build --output-on-failure`.
- If sources already exist under sandbox/hello-cpp and T4 is TODO/DOING, you MUST advance_task with a real cmake command now.
- cwd: leave empty or omit (defaults to lab root). NEVER set cwd to `qwen-lab`.
- For update_memory: no tools, ≤5 bullets.
- For declare_gate: set gate GO or NO-GO only when criteria met. REFUSE GO unless a successful ctest for this campaign is evident in context.
- For block_human: explain what human must do.
- NEVER advance a task whose text contains [HUMAN_GATE] unless TASKBOARD ## HUMAN_GATE has '- [x] approved:'.
- autonomous-hello has no human gates — drive T1→T6 to green ctest + GO.
${SYSTEM_EXTRA}
EOF
)"

SAFETY_SNIP="$(head -n 60 "${LAB_ROOT}/SAFETY.md")"
ALLOW_SNIP="$(head -n 50 "${LAB_ROOT}/ALLOWLIST.md")"
SYSTEM_PROMPT="${SYSTEM_PROMPT}

--- SAFETY.md ---
${SAFETY_SNIP}

--- ALLOWLIST.md ---
${ALLOW_SNIP}
"

payload_for() {
  local base="$1" model="$2"
  python3 - "$base" "$model" <<'PY'
import json, sys, os
base, model = sys.argv[1], sys.argv[2]
system = os.environ["LAB_SYSTEM"]
user = os.environ["LAB_USER"]
print(json.dumps({
  "model": model,
  "temperature": 0.2,
  "max_tokens": 1200,
  "messages": [
    {"role": "system", "content": system},
    {"role": "user", "content": user},
  ],
}))
PY
}

call_once() {
  local base="$1" model="$2"
  local payload tmp http_code
  export LAB_SYSTEM="${SYSTEM_PROMPT}"
  export LAB_USER="${USER_MSG}"
  payload="$(payload_for "${base}" "${model}")"
  tmp="$(mktemp)"
  set +e
  http_code="$(curl -sS -m "${TIMEOUT_S}" \
    -o "${tmp}" -w '%{http_code}' \
    -H 'Content-Type: application/json' \
    -d "${payload}" \
    "${base}/chat/completions")"
  local rc=$?
  set -e
  if [[ ${rc} -ne 0 || "${http_code}" != 2* ]]; then
    echo "lab-llm: ${base} model=${model} failed http=${http_code} rc=${rc}" >&2
    head -c 400 "${tmp}" >&2 || true
    echo >&2
    rm -f "${tmp}"
    return 1
  fi
  python3 - "${tmp}" "${LAB_ROOT}/.state/last_llm_timing.json" <<'PY'
import json, sys, re, pathlib
path = sys.argv[1]
timing_path = pathlib.Path(sys.argv[2])
with open(path) as f:
    data = json.load(f)
content = data["choices"][0]["message"]["content"]
content = content.strip()
if content.startswith("```"):
    content = re.sub(r"^```(?:json)?\s*", "", content)
    content = re.sub(r"\s*```$", "", content)
obj = json.loads(content)
# Persist timings / usage for compare metrics
timing = {
    "usage": data.get("usage") or {},
    "timings": data.get("timings") or {},
}
# llama.cpp sometimes nests timings differently
if not timing["timings"] and isinstance(data.get("timings"), dict):
    timing["timings"] = data["timings"]
timing_path.parent.mkdir(parents=True, exist_ok=True)
timing_path.write_text(json.dumps(timing, indent=2) + "\n")
print(json.dumps(obj, ensure_ascii=False))
PY
  rm -f "${tmp}"
}

mkdir -p "${LAB_ROOT}/.state"
if ! call_once "${BASE_URL}" "${MODEL}"; then
  echo "lab-llm: falling back to ${FALLBACK_URL} ${FALLBACK_MODEL}" >&2
  call_once "${FALLBACK_URL}" "${FALLBACK_MODEL}"
fi
