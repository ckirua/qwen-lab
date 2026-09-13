#!/usr/bin/env bash
# Thin wrap → infer-server switch-context daily (sacred restore).
set -euo pipefail

SWITCH="${INFER_SWITCH:-/home/kirua/app/infer-server/scripts/switch-context.sh}"

if [[ ! -x "${SWITCH}" ]]; then
  echo "lab-restore-daily: missing ${SWITCH}" >&2
  exit 1
fi

exec "${SWITCH}" daily
