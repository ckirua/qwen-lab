#!/usr/bin/env bash
# Allowlisted file writer for qwen-lab (sandbox / campaign plan / notes).
# Usage: lab-write.sh <rel-or-abs-path>   # content on stdin
#    or: lab-write.sh --file <path> --from <content-file>
set -euo pipefail

LAB_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MAX_BYTES=32768
PATH_ARG=""
FROM_FILE=""

usage() {
  cat <<EOF
Usage: $(basename "$0") <path>                 # content via stdin
       $(basename "$0") --file <path> --from <content-file>
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --file) PATH_ARG="$2"; shift 2 ;;
    --from) FROM_FILE="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *)
      if [[ -z "${PATH_ARG}" ]]; then
        PATH_ARG="$1"; shift
      else
        echo "lab-write: unexpected arg: $1" >&2
        exit 2
      fi
      ;;
  esac
done

if [[ -z "${PATH_ARG}" ]]; then
  usage >&2
  exit 2
fi

deny() {
  echo "lab-write: DENIED: $*" >&2
  exit 4
}

# Reject path traversal tokens early
case "${PATH_ARG}" in
  *'..'* ) deny "path contains .." ;;
esac

if [[ "${PATH_ARG}" = /* ]]; then
  ABS="${PATH_ARG}"
else
  ABS="$(cd "${LAB_ROOT}" && realpath -m "${PATH_ARG}")"
fi

# Must resolve under LAB_ROOT
case "${ABS}" in
  "${LAB_ROOT}"|"${LAB_ROOT}"/*) ;;
  *) deny "path outside lab root: ${ABS}" ;;
esac

REL="${ABS#"${LAB_ROOT}"/}"

allowed=0
case "${REL}" in
  sandbox/hello-cpp/*)
    # sources / cmake / readme only
    base="$(basename "${REL}")"
    case "${base}" in
      *.cpp|*.h|*.hpp|*.cc|*.cxx|CMakeLists.txt|README.md|*.txt|*.cmake)
        allowed=1
        ;;
      *)
        deny "disallowed filename under hello-cpp: ${base}"
        ;;
    esac
    # still deny build tree writes via this tool
    case "${REL}" in
      sandbox/hello-cpp/build|sandbox/hello-cpp/build/*) deny "no write_file into build/" ;;
    esac
    ;;
  campaigns/autonomous-hello/plan.md)
    allowed=1
    ;;
  notes/*)
    case "${REL}" in
      notes/*.md) allowed=1 ;;
      *) deny "notes only *.md" ;;
    esac
    ;;
  *)
    deny "path not on write allowlist: ${REL}"
    ;;
esac

[[ "${allowed}" -eq 1 ]] || deny "not allowlisted: ${REL}"

# Deny sensitive / harness paths even if somehow matched
case "${REL}" in
  scripts/*|SAFETY.md|ALLOWLIST.md|.git/*|infer-server/*|.state/*)
    deny "protected path: ${REL}"
    ;;
esac

tmpdir="$(mktemp -d)"
trap 'rm -rf "${tmpdir}"' EXIT
content_file="${tmpdir}/content"
if [[ -n "${FROM_FILE}" ]]; then
  cp -- "${FROM_FILE}" "${content_file}"
else
  cat >"${content_file}"
fi

bytes="$(wc -c <"${content_file}" | tr -d ' ')"
if [[ "${bytes}" -gt "${MAX_BYTES}" ]]; then
  deny "content ${bytes} bytes exceeds ${MAX_BYTES}"
fi

mkdir -p "$(dirname "${ABS}")"
cp -- "${content_file}" "${ABS}"
echo "lab-write: wrote ${REL} (${bytes} bytes)" >&2
exit 0
