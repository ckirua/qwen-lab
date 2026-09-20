#!/usr/bin/env bash
# Allowlisted command runner for qwen-lab.
# Usage: lab-run.sh [--human-gate] [--cwd DIR] -- <command...>
set -euo pipefail

LAB_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REQUIRE_HUMAN_GATE=0
RUN_CWD="${LAB_ROOT}"
GPU_LOCK=0

usage() {
  cat <<EOF
Usage: $(basename "$0") [--human-gate] [--gpu-lock] [--cwd DIR] -- <command...>

Executes one allowlisted command. Rejects anything outside ALLOWLIST.md rules.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --human-gate) REQUIRE_HUMAN_GATE=1; shift ;;
    --gpu-lock) GPU_LOCK=1; shift ;;
    --cwd) RUN_CWD="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    --) shift; break ;;
    *) break ;;
  esac
done

if [[ $# -lt 1 ]]; then
  usage >&2
  exit 2
fi

human_gate_ok() {
  grep -Eq '^- \[x\] approved:' "${LAB_ROOT}/TASKBOARD.md" 2>/dev/null
}

if [[ "${REQUIRE_HUMAN_GATE}" -eq 1 ]] || [[ "${LAB_CONFIRM_LLAMA_GRAPHS:-0}" == "1" && "$*" == *bench-final-pass* ]]; then
  if ! human_gate_ok && [[ "${LAB_CONFIRM_LLAMA_GRAPHS:-0}" != "1" ]]; then
    echo "lab-run: HUMAN_GATE required (checkbox not approved)" >&2
    exit 3
  fi
  if [[ "$*" == *bench-final-pass* && "${LAB_CONFIRM_LLAMA_GRAPHS:-0}" != "1" ]]; then
    echo "lab-run: bench-final-pass requires LAB_CONFIRM_LLAMA_GRAPHS=1" >&2
    exit 3
  fi
fi

# Resolve relative script paths against LAB_ROOT
CMD0="$1"
shift
ARGS=("$@")

abs_under() {
  local base="$1" path="$2"
  local abs
  if [[ "${path}" = /* ]]; then
    abs="${path}"
  else
    abs="$(cd "${base}" && realpath -m "${path}")"
  fi
  case "${abs}" in
    "${base}"|"${base}"/*) echo "${abs}"; return 0 ;;
    *) return 1 ;;
  esac
}

deny() {
  echo "lab-run: DENIED: $*" >&2
  exit 4
}

# Forbidden argv tokens
for a in "${CMD0}" "${ARGS[@]+"${ARGS[@]}"}"; do
  case "${a}" in
    *'..'*|*';'|sudo|eval|systemctl|apt|apt-get|pip|git|rm)
      # allow rm only if later checks pass for sandbox — still deny bare rm here if CMD0
      ;;
  esac
done
case "${CMD0}" in
  sudo|eval|bash|sh|zsh|systemctl|apt|apt-get|pip|pip3|git|rm|chmod|chown|curl)
    # curl handled specially below
    if [[ "${CMD0}" != "curl" ]]; then
      deny "forbidden argv0=${CMD0}"
    fi
    ;;
esac

# Expand PATH for nvcc
export PATH="/home/kirua/app/deps/usr/local/cuda-13.1/bin:${PATH:-}"
export CUDA_HOME="${CUDA_HOME:-/home/kirua/app/deps/usr/local/cuda-13.1}"

allowed=0
full_cmd=("${CMD0}" "${ARGS[@]+"${ARGS[@]}"}")

# --- allowlist matchers ---
if [[ "${CMD0}" == "scripts/lab-status.sh" || "${CMD0}" == "${LAB_ROOT}/scripts/lab-status.sh" ]]; then
  CMD0="${LAB_ROOT}/scripts/lab-status.sh"
  allowed=1
elif [[ "${CMD0}" == "scripts/lab-restore-daily.sh" || "${CMD0}" == "${LAB_ROOT}/scripts/lab-restore-daily.sh" ]]; then
  CMD0="${LAB_ROOT}/scripts/lab-restore-daily.sh"
  allowed=1
elif [[ "${CMD0}" == "nvcc" && ${#ARGS[@]} -ge 1 && "${ARGS[0]}" == "--version" && ${#ARGS[@]} -eq 1 ]]; then
  allowed=1
elif [[ "${CMD0}" == "nvidia-smi" ]]; then
  # nvidia-smi or nvidia-smi -q -d MEMORY or query forms
  allowed=1
elif [[ "${CMD0}" == "curl" ]]; then
  # Exact readiness probes only
  joined="${full_cmd[*]}"
  if [[ "${joined}" == "curl -sS http://127.0.0.1:8080/v1/models" \
     || "${joined}" == "curl -sS http://127.0.0.1:8090/v1/models" ]]; then
    allowed=1
  else
    deny "curl not allowlisted: ${joined}"
  fi
elif [[ "${CMD0}" == "/home/kirua/app/infer-server/scripts/switch-context.sh" \
     || "${CMD0}" == "switch-context.sh" ]]; then
  CMD0="/home/kirua/app/infer-server/scripts/switch-context.sh"
  if [[ ${#ARGS[@]} -eq 1 && ( "${ARGS[0]}" == "status" || "${ARGS[0]}" == "daily" || "${ARGS[0]}" == "daily-spec" ) ]]; then
    allowed=1
  else
    deny "switch-context only status|daily|daily-spec"
  fi
elif [[ "${CMD0}" == "/home/kirua/app/infer-server/scripts/bench-final-pass.sh" ]]; then
  if [[ "${LAB_CONFIRM_LLAMA_GRAPHS:-0}" != "1" ]]; then
    deny "bench-final-pass needs LAB_CONFIRM_LLAMA_GRAPHS=1"
  fi
  if ! human_gate_ok; then
    deny "bench-final-pass needs HUMAN_GATE approved"
  fi
  allowed=1
elif [[ "${CMD0}" == "cmake" ]]; then
  # Must operate under sandbox/**
  joined="${full_cmd[*]}"
  if [[ "${joined}" == *"sandbox/"* ]] || [[ "${RUN_CWD}" == *"sandbox/"* ]]; then
    # Require -B build or --build
    if [[ "${joined}" == *"-B"* || "${joined}" == *"--build"* ]]; then
      allowed=1
    fi
  fi
  [[ "${allowed}" -eq 1 ]] || deny "cmake only under sandbox with -B/--build"
elif [[ "${CMD0}" == "ctest" ]]; then
  joined="${full_cmd[*]}"
  # Prefer exact hello success probe; also allow --test-dir under sandbox/**
  if [[ "${joined}" == "ctest --test-dir sandbox/hello-cpp/build --output-on-failure" ]]; then
    allowed=1
  elif [[ "${joined}" == *"--test-dir"*sandbox/* && "${joined}" == *"--output-on-failure"* ]]; then
    # resolve --test-dir argument
    td=""
    prev=""
    for a in "${full_cmd[@]}"; do
      if [[ "${prev}" == "--test-dir" ]]; then
        td="${a}"
        break
      fi
      prev="${a}"
    done
    [[ -n "${td}" ]] || deny "ctest missing --test-dir"
    if [[ "${td}" != /* ]]; then
      td="$(cd "${RUN_CWD}" && realpath -m "${td}")"
    fi
    case "${td}" in
      "${LAB_ROOT}/sandbox/"*) allowed=1 ;;
      *) deny "ctest --test-dir must be under sandbox/: ${td}" ;;
    esac
  else
    deny "ctest not allowlisted: ${joined}"
  fi
elif [[ "${CMD0}" == "ls" || "${CMD0}" == "test" ]]; then
  # Inspect only under sandbox/hello-cpp/**
  if [[ ${#ARGS[@]} -lt 1 ]]; then
    deny "${CMD0} needs path args under sandbox/hello-cpp"
  fi
  for a in "${ARGS[@]}"; do
    [[ "${a}" == -* ]] && continue
    target="${a}"
    [[ "${target}" = /* ]] || target="$(cd "${RUN_CWD}" && realpath -m "${target}")"
    case "${target}" in
      "${LAB_ROOT}/sandbox/hello-cpp"|"${LAB_ROOT}/sandbox/hello-cpp"/*) ;;
      *) deny "${CMD0} path outside sandbox/hello-cpp: ${target}" ;;
    esac
  done
  if [[ "${CMD0}" == "test" ]]; then
    # only test -f / -d / -e
    [[ ${#ARGS[@]} -ge 2 && ( "${ARGS[0]}" == "-f" || "${ARGS[0]}" == "-d" || "${ARGS[0]}" == "-e" ) ]] \
      || deny "test only -f/-d/-e under hello-cpp"
  fi
  allowed=1
elif [[ "${CMD0}" == *"/bench.sh" || "${CMD0}" == "sandbox/"*"/bench.sh" || "${CMD0}" == bench.sh ]]; then
  bench_path="${CMD0}"
  if [[ "${bench_path}" != /* ]]; then
    bench_path="$(cd "${RUN_CWD}" && realpath -m "${bench_path}")"
  fi
  case "${bench_path}" in
    "${LAB_ROOT}/sandbox/"*/bench.sh) allowed=1; CMD0="${bench_path}" ;;
    *) deny "bench.sh must live under sandbox/**" ;;
  esac
elif [[ "${CMD0}" == "rg" || "${CMD0}" == "sed" || "${CMD0}" == "head" || "${CMD0}" == "cat" ]]; then
  # Read-only: every path-like arg must be under qwen-lab or infer-server/docs
  for a in "${ARGS[@]+"${ARGS[@]}"}"; do
    [[ "${a}" == -* ]] && continue
    [[ "${a}" == *"/"* || -e "${a}" || -e "${RUN_CWD}/${a}" ]] || continue
    target="${a}"
    [[ "${target}" = /* ]] || target="$(cd "${RUN_CWD}" && realpath -m "${target}")"
    case "${target}" in
      "${LAB_ROOT}"|"${LAB_ROOT}"/*) ;;
      /home/kirua/app/infer-server/docs|/home/kirua/app/infer-server/docs/*) ;;
      *) deny "read path outside lab/docs: ${target}" ;;
    esac
  done
  if [[ "${CMD0}" == "sed" ]]; then
    [[ ${#ARGS[@]} -ge 1 && "${ARGS[0]}" == "-n" ]] || deny "sed only with -n"
  fi
  allowed=1
fi

[[ "${allowed}" -eq 1 ]] || deny "no allowlist match for: ${full_cmd[*]}"

# cwd must stay under lab (or be LAB_ROOT) unless running infer-server scripts
case "${CMD0}" in
  /home/kirua/app/infer-server/scripts/*) ;;
  *)
    RUN_CWD="$(cd "${RUN_CWD}" && pwd)"
    case "${RUN_CWD}" in
      "${LAB_ROOT}"|"${LAB_ROOT}"/*) ;;
      *) deny "cwd outside lab: ${RUN_CWD}" ;;
    esac
    ;;
esac

restore_daily() {
  "${LAB_ROOT}/scripts/lab-restore-daily.sh" || true
}

GPU_LOCK_FD=
if [[ "${GPU_LOCK}" -eq 1 ]]; then
  exec {GPU_LOCK_FD}>"${LAB_ROOT}/locks/gpu-experiment.lock"
  if ! flock -n "${GPU_LOCK_FD}"; then
    echo "lab-run: gpu-experiment.lock held" >&2
    exit 5
  fi
  trap 'restore_daily; flock -u "${GPU_LOCK_FD}" 2>/dev/null || true' EXIT
fi

cd "${RUN_CWD}"
echo "lab-run: + ${CMD0} ${ARGS[*]+${ARGS[*]}}" >&2
set +e
"${CMD0}" ${ARGS[@]+"${ARGS[@]}"}
rc=$?
set -e
exit "${rc}"
