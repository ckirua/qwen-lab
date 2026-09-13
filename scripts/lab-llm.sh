#!/usr/bin/env bash
# OpenAI-compatible chat client for qwen-lab.
# Prefers 8090 gpt-4o-mini-spec; falls back to 8080 gpt-4o-mini.
set -euo pipefail

LAB_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BASE_URL="${LAB_BASE_URL:-http://127.0.0.1:8090/v1}"
MODEL="${LAB_MODEL:-gpt-4o-mini-spec}"
FALLBACK_URL="${LAB_FALLBACK_URL:-http://127.0.0.1:8080/v1}"
FALLBACK_MODEL="${LAB_FALLBACK_MODEL:-gpt-4o-mini}"
TIMEOUT_S="${LAB_LLM_TIMEOUT:-120}"
USER_MSG="${1:-}"
SYSTEM_EXTRA="${2:-}"

if [[ -z "${USER_MSG}" ]]; then
  # Read user message from stdin
  USER_MSG="$(cat)"
fi

SYSTEM_PROMPT="$(cat <<EOF
You are the qwen-lab autonomous research agent. You propose exactly ONE action per tick as JSON.
Follow SAFETY.md and ALLOWLIST.md strictly. Never suggest editing infer-server profile maps or leaving non-daily profiles.
Daily driver is sacred. File memory (TASKBOARD/WORKSTATE/MEMORY/HYPOTHESES) is source of truth.

Return ONLY a JSON object (no markdown fences) with this shape:
{
  "action": "advance_task" | "update_memory" | "declare_gate" | "block_human",
  "task_id": "T1",
  "command": "allowlisted shell command string or empty",
  "cwd": "optional cwd under lab root",
  "memory_bullets": ["optional", "≤5 bullets"],
  "gate": "GO" | "NO-GO" | "",
  "rationale": "one short sentence",
  "hypothesis_updates": [{"id":"H1","status":"supported|refuted|open","evidence":"path"}]
}

Rules:
- Prefer the single next TODO task; at most one DOING.
- command must match ALLOWLIST exactly (no pipelines, no sudo, no bash -c).
- For update_memory: no tools, ≤5 bullets.
- For declare_gate: set gate GO or NO-GO when campaign criteria met.
- For block_human: explain what human must do.
- NEVER advance a task whose text contains [HUMAN_GATE] unless TASKBOARD ## HUMAN_GATE has `- [x] approved:`.
- If Phase A GO criteria are already met and only HUMAN_GATE tasks remain, declare_gate GO (do not start T6).
${SYSTEM_EXTRA}
EOF
)"

# Attach safety + allowlist (truncated) into system
SAFETY_SNIP="$(head -n 80 "${LAB_ROOT}/SAFETY.md")"
ALLOW_SNIP="$(head -n 60 "${LAB_ROOT}/ALLOWLIST.md")"
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
  "max_tokens": 800,
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
  python3 - "${tmp}" <<'PY'
import json, sys, re
path = sys.argv[1]
with open(path) as f:
    data = json.load(f)
content = data["choices"][0]["message"]["content"]
# Strip optional fences
content = content.strip()
if content.startswith("```"):
    content = re.sub(r"^```(?:json)?\s*", "", content)
    content = re.sub(r"\s*```$", "", content)
# Validate JSON
obj = json.loads(content)
print(json.dumps(obj, ensure_ascii=False))
PY
  rm -f "${tmp}"
}

if ! call_once "${BASE_URL}" "${MODEL}"; then
  echo "lab-llm: falling back to ${FALLBACK_URL} ${FALLBACK_MODEL}" >&2
  call_once "${FALLBACK_URL}" "${FALLBACK_MODEL}"
fi
