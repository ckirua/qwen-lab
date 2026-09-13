#!/usr/bin/env bash
# Build (if needed) and run cuda-graphs-toy; append campaign TSV rows.
set -euo pipefail

TOY_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LAB_ROOT="$(cd "${TOY_DIR}/../.." && pwd)"
TSV="${LAB_ROOT}/results/campaigns/cuda-graphs-101.tsv"
BUILD="${TOY_DIR}/build"
export PATH="/home/kirua/app/deps/usr/local/cuda-13.1/bin:${PATH:-}"
export CUDA_HOME="${CUDA_HOME:-/home/kirua/app/deps/usr/local/cuda-13.1}"
export LD_LIBRARY_PATH="${CUDA_HOME}/lib64:${LD_LIBRARY_PATH:-}"

TRIALS="${TRIALS:-3}"
N="${N:-1048576}"
LAUNCHES="${LAUNCHES:-1000}"
ITER="${LAB_ITER:-0}"
TASK_ID="${LAB_TASK_ID:-T3}"

mkdir -p "${BUILD}"
if [[ ! -f "${BUILD}/vector_add_graphs" ]]; then
  cmake -B "${BUILD}" -S "${TOY_DIR}" -DCMAKE_CUDA_ARCHITECTURES=75
  cmake --build "${BUILD}" -j"$(nproc)"
fi

iso="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
out="$("${BUILD}/vector_add_graphs" --n "${N}" --launches "${LAUNCHES}" --trials "${TRIALS}")"
echo "${out}"

while IFS=$'\t' read -r tag trial m1 v1 m2 v2 m3 v3; do
  [[ "${tag}" == "TRIAL" ]] || continue
  # eager
  echo -e "${iso}\tcuda-graphs-101\t${ITER}\t${TASK_ID}\tsandbox/cuda-graphs-toy/bench.sh\t${m1}\t${v1}\tms\ttrial=${trial} launches=${LAUNCHES} n=${N}\t" >>"${TSV}"
  echo -e "${iso}\tcuda-graphs-101\t${ITER}\t${TASK_ID}\tsandbox/cuda-graphs-toy/bench.sh\t${m2}\t${v2}\tms\ttrial=${trial} launches=${LAUNCHES} n=${N}\t" >>"${TSV}"
  echo -e "${iso}\tcuda-graphs-101\t${ITER}\t${TASK_ID}\tsandbox/cuda-graphs-toy/bench.sh\t${m3}\t${v3}\tratio\ttrial=${trial} launches=${LAUNCHES} n=${N}\t" >>"${TSV}"
done <<<"$(echo "${out}" | grep $'^TRIAL\t')"

echo "bench: wrote trials to ${TSV}"
