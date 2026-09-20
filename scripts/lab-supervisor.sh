#!/usr/bin/env bash
# Headless supervisor: loop lab-tick until Outcome or budget.
# Qwen-only ticks (no Cursor /loop). Always restores daily on exit unless HOLD stays set
# by an outer compare runner (cleanup still calls restore).
set -euo pipefail

LAB_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MAX_ITERS=30
CAMPAIGN="autonomous-hello"
SLEEP_S=2
MAX_WALL_H=4
RESET=1

usage() {
  cat <<EOF
Usage: $(basename "$0") [--max-iters N] [--campaign ID] [--sleep S] [--max-wall-h H] [--no-reset]

Loops lab-tick.sh until OUTCOME set or ITER>=max. Restores daily on exit.
With default --reset behavior: clears OUTCOME, ITER=0, seeds campaign board.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --max-iters) MAX_ITERS="$2"; shift 2 ;;
    --campaign) CAMPAIGN="$2"; shift 2 ;;
    --sleep) SLEEP_S="$2"; shift 2 ;;
    --max-wall-h) MAX_WALL_H="$2"; shift 2 ;;
    --no-reset) RESET=0; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "unknown arg: $1" >&2; usage >&2; exit 2 ;;
  esac
done

STATE="${LAB_ROOT}/.state/tick.env"
SEED_BOARD="${LAB_ROOT}/campaigns/${CAMPAIGN}/TASKBOARD.md"

mkdir -p "${LAB_ROOT}/.state" "${LAB_ROOT}/results/campaigns"

if [[ "${RESET}" -eq 1 ]]; then
  cat >"${STATE}" <<EOF
ITER=0
MAX_ITERS=${MAX_ITERS}
MAX_WALL_H=${MAX_WALL_H}
CAMPAIGN_ID=${CAMPAIGN}
STARTED_AT=
OUTCOME=
WALL_STARTED_EPOCH=
EOF
  if [[ -f "${SEED_BOARD}" ]]; then
    # Fresh board from campaign seed template (re-read CAMPAIGN.md sibling seed if present)
    # Prefer canonical seed: rewrite from campaigns/${CAMPAIGN}/TASKBOARD.md if it looks like a template
    # Always install seed copy for autonomous-hello from the campaign file we maintain as template.
    if [[ "${CAMPAIGN}" == autonomous-hello* ]]; then
      TEMPLATE="${LAB_ROOT}/campaigns/autonomous-hello/TASKBOARD.md"
      # Re-seed from embedded baseline if campaign board already mutated — use .seed if present
      if [[ -f "${LAB_ROOT}/campaigns/autonomous-hello/TASKBOARD.seed.md" ]]; then
        TEMPLATE="${LAB_ROOT}/campaigns/autonomous-hello/TASKBOARD.seed.md"
      fi
      cp "${TEMPLATE}" "${LAB_ROOT}/TASKBOARD.md"
      # Rewrite budget line for this max iters
      sed -i "s/^- Budget:.*/- Budget: iters 0\/${MAX_ITERS}, wall started (unset)/" "${LAB_ROOT}/TASKBOARD.md"
      sed -i "s/^- Outcome:.*/- Outcome:/" "${LAB_ROOT}/TASKBOARD.md"
      sed -i "s/^- Campaign:.*/- Campaign: ${CAMPAIGN}/" "${LAB_ROOT}/TASKBOARD.md"
      mkdir -p "${LAB_ROOT}/campaigns/${CAMPAIGN}"
      cp "${LAB_ROOT}/TASKBOARD.md" "${LAB_ROOT}/campaigns/${CAMPAIGN}/TASKBOARD.md"
    else
      cp "${SEED_BOARD}" "${LAB_ROOT}/TASKBOARD.md"
    fi
  fi
  # Preserve HOLD_PROFILE from existing workstate if set
  hold="$(grep -E '^- HOLD_PROFILE:' "${LAB_ROOT}/WORKSTATE.md" 2>/dev/null | head -1 | awk '{print $3}' || echo 0)"
  cat >"${LAB_ROOT}/WORKSTATE.md" <<EOF
# Workstate
- Updated: $(date -u +%Y-%m-%dT%H:%M:%SZ)
- Campaign: ${CAMPAIGN}
- Iter: 0 / ${MAX_ITERS}
- ROLE: plan
- Profile_before_tick:
- Profile_now:
- HOLD_PROFILE: ${hold}
- Last_tool:
- Last_result_row: results/lab.tsv
- Next_action: arm campaign
- Stop_reason:
EOF
  : >"${LAB_ROOT}/.state/last_tool.txt"
  echo "lab-supervisor: reset campaign=${CAMPAIGN} ITER=0 OUTCOME= empty"
else
  python3 - "${STATE}" "${CAMPAIGN}" "${MAX_ITERS}" "${MAX_WALL_H}" <<'PY'
import pathlib, re, sys
p, camp, mx, wall = pathlib.Path(sys.argv[1]), sys.argv[2], sys.argv[3], sys.argv[4]
text = p.read_text() if p.exists() else ""
def setk(text, k, v):
    if re.search(rf'^{k}=', text, re.M):
        return re.sub(rf'^{k}=.*$', f'{k}={v}', text, flags=re.M)
    return text.rstrip() + f'\n{k}={v}\n'
text = setk(text, 'CAMPAIGN_ID', camp)
text = setk(text, 'MAX_ITERS', mx)
text = setk(text, 'MAX_WALL_H', wall)
p.write_text(text)
PY
fi

cleanup() {
  "${LAB_ROOT}/scripts/lab-restore-daily.sh" || true
  echo "lab-supervisor: exit restore daily"
}
trap cleanup EXIT

echo "lab-supervisor: campaign=${CAMPAIGN} max_iters=${MAX_ITERS} max_wall_h=${MAX_WALL_H}"

while true; do
  # shellcheck disable=SC1090
  source "${STATE}"
  if [[ -n "${OUTCOME:-}" ]]; then
    echo "lab-supervisor: stop Outcome=${OUTCOME}"
    break
  fi
  if [[ "${ITER:-0}" -ge "${MAX_ITERS}" ]]; then
    echo "lab-supervisor: stop budget ITER=${ITER}"
    break
  fi
  "${LAB_ROOT}/scripts/lab-tick.sh" || {
    echo "lab-supervisor: tick failed rc=$? — continue after pause" >&2
    sleep "${SLEEP_S}"
    continue
  }
  # shellcheck disable=SC1090
  source "${STATE}"
  if [[ -n "${OUTCOME:-}" ]]; then
    echo "lab-supervisor: stop Outcome=${OUTCOME}"
    break
  fi
  sleep "${SLEEP_S}"
done

"${LAB_ROOT}/scripts/lab-status.sh" || true
