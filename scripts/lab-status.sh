#!/usr/bin/env bash
# Print board + budget + infer profile.
set -euo pipefail

LAB_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STATE="${LAB_ROOT}/.state/tick.env"
SWITCH="${INFER_SWITCH:-/home/kirua/app/infer-server/scripts/switch-context.sh}"

# shellcheck disable=SC1090
[[ -f "${STATE}" ]] && source "${STATE}" || true

echo "=== qwen-lab status ==="
echo "LAB_ROOT=${LAB_ROOT}"
echo "CAMPAIGN_ID=${CAMPAIGN_ID:-?}"
echo "ITER=${ITER:-0} / ${MAX_ITERS:-12}"
echo "OUTCOME=${OUTCOME:-}"
echo "STARTED_AT=${STARTED_AT:-}"
echo "HOLD_PROFILE=$(grep -E '^- HOLD_PROFILE:' "${LAB_ROOT}/WORKSTATE.md" 2>/dev/null | head -1 | sed 's/.*:[[:space:]]*//' || echo '?')"
echo
echo "--- WORKSTATE (head) ---"
head -n 20 "${LAB_ROOT}/WORKSTATE.md" 2>/dev/null || true
echo
echo "--- TASKBOARD Meta ---"
sed -n '/^## Meta/,/^## /p' "${LAB_ROOT}/TASKBOARD.md" | head -n 12
echo
echo "--- infer profile ---"
if [[ -x "${SWITCH}" ]]; then
  "${SWITCH}" status 2>/dev/null | head -n 20 || echo "(switch-context status failed)"
else
  echo "(switch-context missing)"
fi
echo
echo "--- last lab.tsv rows ---"
tail -n 6 "${LAB_ROOT}/results/lab.tsv" 2>/dev/null || true
