#!/usr/bin/env bash
# Headless supervisor: loop lab-tick until Outcome or budget.
set -euo pipefail

LAB_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MAX_ITERS=12
CAMPAIGN="cuda-graphs-101"
SLEEP_S=2

usage() {
  cat <<EOF
Usage: $(basename "$0") [--max-iters N] [--campaign ID] [--sleep S]

Loops lab-tick.sh until OUTCOME set or ITER>=max. Always restores daily on exit.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --max-iters) MAX_ITERS="$2"; shift 2 ;;
    --campaign) CAMPAIGN="$2"; shift 2 ;;
    --sleep) SLEEP_S="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "unknown arg: $1" >&2; usage >&2; exit 2 ;;
  esac
done

STATE="${LAB_ROOT}/.state/tick.env"
# seed campaign / max
python3 - "${STATE}" "${CAMPAIGN}" "${MAX_ITERS}" <<'PY'
import pathlib, re, sys
p, camp, mx = pathlib.Path(sys.argv[1]), sys.argv[2], sys.argv[3]
text = p.read_text()
text = re.sub(r'^CAMPAIGN_ID=.*$', f'CAMPAIGN_ID={camp}', text, flags=re.M)
text = re.sub(r'^MAX_ITERS=.*$', f'MAX_ITERS={mx}', text, flags=re.M)
p.write_text(text)
PY

cleanup() {
  "${LAB_ROOT}/scripts/lab-restore-daily.sh" || true
  echo "lab-supervisor: exit restore daily"
}
trap cleanup EXIT

echo "lab-supervisor: campaign=${CAMPAIGN} max_iters=${MAX_ITERS}"

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
    echo "lab-supervisor: tick failed rc=$? — continue after restore" >&2
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
