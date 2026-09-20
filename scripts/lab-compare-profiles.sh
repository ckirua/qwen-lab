#!/usr/bin/env bash
# Compare autonomous-hello across context profiles (supervisor-only, sequential GPU).
# Versioned outputs — never overwrite prior studies:
#   docs/studies/YYYY-MM-DD-autonomous-hello-vN.md
#   results/campaigns/autonomous-hello-vN-*.tsv (+ *-artifacts/)
#   campaigns/autonomous-hello-vN/ board snapshot
# Always restores CONTEXT_PROFILE=daily between profiles and on exit.
set -euo pipefail

LAB_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SWITCH="${INFER_SWITCH:-/home/kirua/app/infer-server/scripts/switch-context.sh}"
MAX_ITERS="${MAX_ITERS:-30}"
MAX_WALL_H="${MAX_WALL_H:-4}"
SLEEP_S="${SLEEP_S:-2}"
INCLUDE_LONG_GPU="${INCLUDE_LONG_GPU:-1}"
LONG_GPU_WALL_H="${LONG_GPU_WALL_H:-1}"
LONG_GPU_TIMEOUT_S="${LONG_GPU_TIMEOUT_S:-3600}"
SLUG="${STUDY_SLUG:-autonomous-hello}"
DATE_UTC="$(date -u +%Y-%m-%d)"
STUDIES_DIR="${LAB_ROOT}/docs/studies"
INDEX_MD="${STUDIES_DIR}/INDEX.md"
LOG_DIR="${LAB_ROOT}/results/campaigns/compare-logs"
mkdir -p "${LAB_ROOT}/results/campaigns" "${STUDIES_DIR}" "${LOG_DIR}"

# Next version = max existing vN for slug + 1 (never overwrite)
VER_NUM="$(
  python3 - "${LAB_ROOT}" "${SLUG}" <<'PY'
import re, sys
from pathlib import Path
root, slug = Path(sys.argv[1]), sys.argv[2]
n = 0
# studies
for p in (root / "docs" / "studies").glob(f"*-{slug}-v*.md"):
    m = re.search(rf"-{re.escape(slug)}-v(\d+)\.md$", p.name)
    if m:
        n = max(n, int(m.group(1)))
# results
for p in (root / "results" / "campaigns").glob(f"{slug}-v*-compare.tsv"):
    m = re.search(rf"{re.escape(slug)}-v(\d+)-compare\.tsv$", p.name)
    if m:
        n = max(n, int(m.group(1)))
# campaigns snapshots
for p in (root / "campaigns").glob(f"{slug}-v*"):
    m = re.search(rf"^{re.escape(slug)}-v(\d+)$", p.name)
    if m and p.is_dir():
        n = max(n, int(m.group(1)))
print(n + 1)
PY
)"
VER="v${VER_NUM}"
PREV_NUM=$((VER_NUM - 1))
PREV_VER="v${PREV_NUM}"

COMPARE_TSV="${LAB_ROOT}/results/campaigns/${SLUG}-${VER}-compare.tsv"
STUDY_MD="${STUDIES_DIR}/${DATE_UTC}-${SLUG}-${VER}.md"
CAMP_SNAP="${LAB_ROOT}/campaigns/${SLUG}-${VER}"
RUN_TAG="${SLUG}-${VER}"

PROFILES=(daily daily-spec)
if [[ "${INCLUDE_LONG_GPU}" == "1" ]]; then
  PROFILES+=(long-gpu)
fi

echo "compare: slug=${SLUG} version=${VER} date=${DATE_UTC} study=${STUDY_MD}"

restore_daily() {
  echo "compare: restoring daily…"
  "${LAB_ROOT}/scripts/lab-restore-daily.sh" || "${SWITCH}" daily || true
  if [[ -f "${LAB_ROOT}/WORKSTATE.md" ]]; then
    sed -i 's/^- HOLD_PROFILE:.*/- HOLD_PROFILE: 0/' "${LAB_ROOT}/WORKSTATE.md" || true
  fi
}

cleanup() {
  restore_daily
  echo "compare: final profile:"
  "${SWITCH}" status 2>/dev/null | grep -E '^CONTEXT_PROFILE=' || true
}
trap cleanup EXIT

set_hold() {
  local v="$1"
  if [[ -f "${LAB_ROOT}/WORKSTATE.md" ]]; then
    if grep -qE '^- HOLD_PROFILE:' "${LAB_ROOT}/WORKSTATE.md"; then
      sed -i "s/^- HOLD_PROFILE:.*/- HOLD_PROFILE: ${v}/" "${LAB_ROOT}/WORKSTATE.md"
    else
      echo "- HOLD_PROFILE: ${v}" >>"${LAB_ROOT}/WORKSTATE.md"
    fi
  else
    printf '# Workstate\n- HOLD_PROFILE: %s\n' "${v}" >"${LAB_ROOT}/WORKSTATE.md"
  fi
}

clean_sandbox() {
  rm -rf "${LAB_ROOT}/sandbox/hello-cpp"
  rm -f "${LAB_ROOT}/campaigns/autonomous-hello/plan.md"
}

profile_status() {
  "${SWITCH}" status 2>/dev/null | grep -E '^CONTEXT_PROFILE=' | head -1 | cut -d= -f2- || echo unknown
}

collect_metrics() {
  local profile="$1" wall_s="$2" logf="$3"
  local campaign_tsv="${LAB_ROOT}/results/campaigns/${RUN_TAG}-${profile}.tsv"
  local art_dir="${LAB_ROOT}/results/campaigns/${RUN_TAG}-${profile}-artifacts"
  mkdir -p "${art_dir}"

  # shellcheck disable=SC1090
  source "${LAB_ROOT}/.state/tick.env"
  local outcome="${OUTCOME:-}"
  local iters="${ITER:-0}"

  if [[ -f "${LAB_ROOT}/results/campaigns/autonomous-hello.tsv" ]]; then
    cp "${LAB_ROOT}/results/campaigns/autonomous-hello.tsv" "${campaign_tsv}"
  else
    {
      echo -e "iso\tcampaign\titer\ttask\ttool\tmetric\tvalue\tunit\tnotes\toutcome"
      awk -F'\t' -v c="autonomous-hello" '$2==c {print}' "${LAB_ROOT}/results/lab.tsv" 2>/dev/null | tail -n 80 || true
    } >"${campaign_tsv}"
  fi

  local main_ok=0 cmake_ok=0 plan_ok=0 ctest_ok=0 exe_ok=0
  [[ -f "${LAB_ROOT}/sandbox/hello-cpp/main.cpp" ]] && main_ok=1 && cp "${LAB_ROOT}/sandbox/hello-cpp/main.cpp" "${art_dir}/main.cpp" || true
  [[ -f "${LAB_ROOT}/sandbox/hello-cpp/CMakeLists.txt" ]] && cmake_ok=1 && cp "${LAB_ROOT}/sandbox/hello-cpp/CMakeLists.txt" "${art_dir}/CMakeLists.txt" || true
  [[ -f "${LAB_ROOT}/campaigns/autonomous-hello/plan.md" ]] && plan_ok=1 && cp "${LAB_ROOT}/campaigns/autonomous-hello/plan.md" "${art_dir}/plan.md" || true
  if [[ -x "${LAB_ROOT}/sandbox/hello-cpp/build/hello" ]]; then
    exe_ok=1
    cp "${LAB_ROOT}/sandbox/hello-cpp/build/hello" "${art_dir}/hello.bin" 2>/dev/null || true
  fi

  set +e
  if [[ -d "${LAB_ROOT}/sandbox/hello-cpp/build" ]]; then
    ctest --test-dir "${LAB_ROOT}/sandbox/hello-cpp/build" --output-on-failure >"${art_dir}/ctest.out" 2>&1
    ctest_rc=$?
    [[ ${ctest_rc} -eq 0 ]] && ctest_ok=1
  else
    echo "no build dir" >"${art_dir}/ctest.out"
    ctest_rc=2
  fi
  set -e

  local gen_tps="" prompt_n="" pred_n=""
  if [[ -f "${LAB_ROOT}/.state/last_llm_timing.json" ]]; then
    cp "${LAB_ROOT}/.state/last_llm_timing.json" "${art_dir}/last_llm_timing.json"
    eval "$(python3 - "${LAB_ROOT}/.state/last_llm_timing.json" <<'PY'
import json, sys
p = sys.argv[1]
try:
    d = json.load(open(p))
except Exception:
    d = {}
u = d.get("usage") or {}
t = d.get("timings") or {}
def g(*keys, default=""):
    for k in keys:
        if k in t and t[k] is not None:
            return t[k]
        if k in u and u[k] is not None:
            return u[k]
    return default
print(f'gen_tps={g("predicted_per_second", "pred_per_second")!r}')
print(f'prompt_n={g("prompt_n", "prompt_tokens")!r}')
print(f'pred_n={g("predicted_n", "completion_tokens")!r}')
PY
)"
  fi

  local prompt_est=""
  if [[ -z "${prompt_n}" || "${prompt_n}" == "None" ]]; then
    prompt_est="$(python3 - <<'PY'
from pathlib import Path
root = Path("/home/kirua/app/qwen-lab")
n = 0
for rel in ["SAFETY.md","ALLOWLIST.md","TASKBOARD.md","WORKSTATE.md","MEMORY.md"]:
    p = root/rel
    if p.exists():
        n += len(p.read_text(errors="replace"))
print(max(1, n // 4))
PY
)"
  else
    prompt_est="${prompt_n}"
  fi

  if [[ ${main_ok} -eq 1 && ${exe_ok} -eq 1 ]]; then
    "${LAB_ROOT}/sandbox/hello-cpp/build/hello" >"${art_dir}/hello_stdout.txt" 2>&1 || true
  fi

  cp "${LAB_ROOT}/TASKBOARD.md" "${art_dir}/TASKBOARD.md" 2>/dev/null || true
  cp "${LAB_ROOT}/.state/tick.env" "${art_dir}/tick.env" 2>/dev/null || true
  cp "${logf}" "${art_dir}/supervisor.log" 2>/dev/null || true

  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
    "${profile}" "${wall_s}" "${iters}" "${outcome:-BUDGET}" \
    "${ctest_ok}" "${main_ok}" "${cmake_ok}" "${plan_ok}" "${exe_ok}" \
    "${gen_tps:-}" "${prompt_est:-}" "${prompt_n:-}" "${pred_n:-}" \
    "artifacts=${art_dir}" >>"${COMPARE_TSV}"

  echo "compare: ${profile} wall=${wall_s}s iters=${iters} outcome=${outcome:-} ctest=${ctest_ok} main=${main_ok} cmake=${cmake_ok} plan=${plan_ok}"
}

printf 'profile\twall_s\titers\toutcome\tctest_ok\tmain_ok\tcmake_ok\tplan_ok\texe_ok\tgen_tps\tprompt_tok_est\tprompt_n\tpred_n\tnotes\n' >"${COMPARE_TSV}"

echo "compare: profiles=${PROFILES[*]} max_iters=${MAX_ITERS} ${RUN_TAG}"

for profile in "${PROFILES[@]}"; do
  echo "========== PROFILE ${profile} (${RUN_TAG}) =========="
  restore_daily
  clean_sandbox
  rm -f "${LAB_ROOT}/results/campaigns/autonomous-hello.tsv"
  echo -e "iso\tcampaign\titer\ttask\ttool\trc\tnotes" >"${LAB_ROOT}/results/campaigns/autonomous-hello.tsv"

  echo "compare: switching to ${profile}"
  if ! "${SWITCH}" "${profile}"; then
    echo "compare: switch to ${profile} FAILED — skip" >&2
    printf '%s\t%s\t%s\t%s\t0\t0\t0\t0\t0\t\t\t\t\t%s\n' \
      "${profile}" "0" "0" "SWITCH_FAIL" "switch failed" >>"${COMPARE_TSV}"
    restore_daily
    continue
  fi
  got="$(profile_status)"
  if [[ "${got}" != "${profile}" ]]; then
    echo "compare: expected ${profile} got ${got} — skip" >&2
    printf '%s\t%s\t%s\t%s\t0\t0\t0\t0\t0\t\t\t\t\t%s\n' \
      "${profile}" "0" "0" "SWITCH_MISMATCH" "got=${got}" >>"${COMPARE_TSV}"
    restore_daily
    continue
  fi

  set_hold 1
  export LAB_BASE_URL="http://127.0.0.1:8080/v1"
  live_8080="$(curl -sS --max-time 3 http://127.0.0.1:8080/v1/models | python3 -c \
    'import json,sys; print(json.load(sys.stdin)["data"][0]["id"])' 2>/dev/null \
    || echo "Qwen2.5-Coder-7B-Instruct")"
  export LAB_MODEL="${live_8080}"
  export LAB_FALLBACK_URL="http://127.0.0.1:8080/v1"
  export LAB_FALLBACK_MODEL="${live_8080}"
  export LAB_CAMPAIGN_TSV="${LAB_ROOT}/results/campaigns/autonomous-hello.tsv"
  export CAMPAIGN_ID="autonomous-hello"

  wall_h="${MAX_WALL_H}"
  timeout_s=0
  if [[ "${profile}" == "long-gpu" ]]; then
    wall_h="${LONG_GPU_WALL_H}"
    timeout_s="${LONG_GPU_TIMEOUT_S}"
  fi

  logf="${LOG_DIR}/${RUN_TAG}-${profile}.log"
  t0="$(date +%s)"
  set +e
  if [[ "${timeout_s}" -gt 0 ]]; then
    timeout --signal=INT --kill-after=30 "${timeout_s}" \
      "${LAB_ROOT}/scripts/lab-supervisor.sh" \
        --max-iters "${MAX_ITERS}" \
        --max-wall-h "${wall_h}" \
        --campaign autonomous-hello \
        --sleep "${SLEEP_S}" \
      >"${logf}" 2>&1
    rc=$?
  else
    "${LAB_ROOT}/scripts/lab-supervisor.sh" \
      --max-iters "${MAX_ITERS}" \
      --max-wall-h "${wall_h}" \
      --campaign autonomous-hello \
      --sleep "${SLEEP_S}" \
      >"${logf}" 2>&1
    rc=$?
  fi
  set -e
  t1="$(date +%s)"
  wall_s=$((t1 - t0))
  echo "compare: ${profile} supervisor rc=${rc} wall=${wall_s}s (log ${logf})"

  collect_metrics "${profile}" "${wall_s}" "${logf}"
  restore_daily
done

# Snapshot campaign board (never overwrite prior versions — CAMP_SNAP is new)
mkdir -p "${CAMP_SNAP}"
cp -a "${LAB_ROOT}/campaigns/autonomous-hello/." "${CAMP_SNAP}/" 2>/dev/null || true
cp "${LAB_ROOT}/TASKBOARD.md" "${CAMP_SNAP}/TASKBOARD.final.md" 2>/dev/null || true
cp "${LAB_ROOT}/WORKSTATE.md" "${CAMP_SNAP}/WORKSTATE.final.md" 2>/dev/null || true
printf 'version=%s\ndate=%s\nslug=%s\nstudy=%s\ncompare_tsv=%s\n' \
  "${VER}" "${DATE_UTC}" "${SLUG}" "${STUDY_MD}" "${COMPARE_TSV}" >"${CAMP_SNAP}/VERSION.txt"

# Write versioned study + INDEX
python3 - "${COMPARE_TSV}" "${STUDY_MD}" "${INDEX_MD}" "${MAX_ITERS}" \
  "${SLUG}" "${VER}" "${DATE_UTC}" "${PREV_VER}" "${CAMP_SNAP}" <<'PY'
import csv, pathlib, sys, datetime, re
tsv_path = pathlib.Path(sys.argv[1])
study_path = pathlib.Path(sys.argv[2])
index_path = pathlib.Path(sys.argv[3])
max_iters, slug, ver, date_utc, prev_ver = sys.argv[4:9]
camp_snap = pathlib.Path(sys.argv[9])
rows = list(csv.DictReader(tsv_path.open(), delimiter="\t"))
lab = pathlib.Path("/home/kirua/app/qwen-lab")

def winner(rows):
    scored = []
    for r in rows:
        go = 1 if (r.get("outcome") == "GO" and r.get("ctest_ok") == "1") else 0
        try:
            iters = int(float(r.get("iters") or 999))
        except Exception:
            iters = 999
        try:
            wall = float(r.get("wall_s") or 1e9)
        except Exception:
            wall = 1e9
        scored.append((go, -iters, -wall, r.get("profile"), r))
    scored.sort(reverse=True)
    if not scored:
        return None, None
    return scored[0][3], scored[0][4]

win_name, win_row = winner(rows)
iso = datetime.datetime.utcnow().strftime("%Y-%m-%dT%H:%M:%SZ")

def table(rows):
    lines = [
        "| profile | wall_s | iters | outcome | ctest | main.cpp | CMakeLists | plan.md | exe | gen tok/s | prompt tok est |",
        "|---|---:|---:|---|---:|---:|---:|---:|---:|---:|---:|",
    ]
    for r in rows:
        lines.append(
            f"| {r.get('profile','')} | {r.get('wall_s','')} | {r.get('iters','')} | {r.get('outcome','')} | "
            f"{r.get('ctest_ok','')} | {r.get('main_ok','')} | {r.get('cmake_ok','')} | {r.get('plan_ok','')} | "
            f"{r.get('exe_ok','')} | {r.get('gen_tps','') or '—'} | {r.get('prompt_tok_est','') or '—'} |"
        )
    return "\n".join(lines)

# Diff vs previous
prev_study = None
prev_rows = []
if prev_ver != "v0":
    cands = sorted((lab / "docs" / "studies").glob(f"*-{slug}-{prev_ver}.md"))
    if cands:
        prev_study = cands[-1]
    prev_tsv = lab / "results" / "campaigns" / f"{slug}-{prev_ver}-compare.tsv"
    if prev_tsv.exists():
        prev_rows = list(csv.DictReader(prev_tsv.open(), delimiter="\t"))

diff_lines = []
if prev_ver == "v0" or not prev_study:
    diff_lines.append("N/A — no previous version.")
else:
    diff_lines.append(f"Previous: [`{prev_study.name}`](./{prev_study.name})")
    prev_map = {r["profile"]: r for r in prev_rows if r.get("profile")}
    cur_map = {r["profile"]: r for r in rows if r.get("profile")}
    for p in sorted(set(prev_map) | set(cur_map)):
        a, b = prev_map.get(p, {}), cur_map.get(p, {})
        diff_lines.append(
            f"- **{p}**: {a.get('outcome','—')}/{a.get('ctest_ok','—')} @ {a.get('iters','—')}iters/{a.get('wall_s','—')}s"
            f" → {b.get('outcome','—')}/{b.get('ctest_ok','—')} @ {b.get('iters','—')}iters/{b.get('wall_s','—')}s"
        )
    diff_lines.append(
        "- Harness deltas expected in this version: cwd normalize + force lab-root for sandbox paths; "
        "cmake auto `-S`; GO requires canonical `build/hello`; "
        "handoff via WORKSTATE Next_action + `.state/last_tool_output.txt` (fresh chat each tick)."
    )

analysis = []
for r in rows:
    p = r.get("profile")
    if r.get("outcome") == "GO" and r.get("ctest_ok") == "1":
        analysis.append(f"- **{p}**: verified GO in {r.get('iters')} iters / {r.get('wall_s')}s.")
    elif r.get("ctest_ok") == "1":
        analysis.append(f"- **{p}**: ctest green but outcome={r.get('outcome')}.")
    else:
        analysis.append(f"- **{p}**: incomplete (outcome={r.get('outcome')}, ctest={r.get('ctest_ok')}).")

why = "Insufficient verified GO runs to claim a speed winner."
if win_row and win_row.get("ctest_ok") == "1":
    why = (
        f"`{win_name}` won on verified GO with best (iters, wall) among successful profiles."
    )

overall = "mixed"
if any(r.get("outcome") == "GO" and r.get("ctest_ok") == "1" for r in rows):
    overall = f"GO:{win_name}"
elif all(r.get("outcome") == "BUDGET" for r in rows):
    overall = "BUDGET"
else:
    outs = ",".join(f"{r.get('profile')}={r.get('outcome')}" for r in rows)
    overall = outs[:80]

hyp = "H1: daily-spec beats daily on autonomous coding ticks (iters/wall to verified GO)"

study = f"""# Study: {slug} profile compare — {ver}

**Version:** {ver}  
**Date (UTC):** {iso} ({date_utc})  
**Slug:** `{slug}`  
**Lab:** `/home/kirua/app/qwen-lab`  
**Raw metrics:** [`../../results/campaigns/{slug}-{ver}-compare.tsv`](../../results/campaigns/{slug}-{ver}-compare.tsv)  
**Board snapshot:** [`../../campaigns/{slug}-{ver}/`](../../campaigns/{slug}-{ver}/)  
**INDEX:** [`INDEX.md`](./INDEX.md)

## Diff vs previous version

{chr(10).join(diff_lines)}

---

## 1. Hypothesis

**H1:** On this autonomous coding loop (fresh context each tick, file memory only, allowlisted tools), **`daily-spec` outperforms `daily`** — fewer iterations and/or lower wall time to verified GO — because draft speculation improves code-shaped generation throughput/quality.

**H2 (secondary):** `long-gpu` does **not** help this small-prompt task; timeboxed negative control.

**H0:** No meaningful difference between `daily` and `daily-spec` on iters-to-GO.

---

## 2. Method

| Factor | Setting |
|---|---|
| Driver | `lab-supervisor.sh` only (Qwen ticks) — **no** Cursor `/loop` wakes |
| Model | Qwen2.5-Coder-7B Q5_K_M via `:8080` (live `/v1/models` id), **NP=1** |
| Max iters | **{max_iters}** |
| Context each tick | Fresh `messages=[system,user]` only |
| Handoff files | TASKBOARD, WORKSTATE (Next_action/Last_result/Handoff), MEMORY, plan.md, `.state/last_tool_output.txt` |
| Profiles | `daily`, `daily-spec`, `long-gpu` (optional); **long-ram skipped** |
| Success | `declare_gate` GO **and** verifier `ctest` + canonical `sandbox/hello-cpp/build/hello` |

---

## 3. Procedure

```bash
/home/kirua/app/qwen-lab/scripts/lab-compare-profiles.sh
# bumps to next vN automatically; never overwrites prior versioned paths
```

Per profile: restore daily → clean sandbox → switch profile + HOLD_PROFILE=1 → supervisor → metrics → restore daily.

---

## 4. Results

{table(rows)}

### Artifact proof paths

"""
for r in rows:
    study += f"- **{r.get('profile')}**: `{r.get('notes','')}`\n"

study += f"""

---

## 5. Analysis

{chr(10).join(analysis)}

**Winner (verified GO):** `{win_name or 'none'}`.

{why}

---

## 6. Reproducibility

```bash
cd /home/kirua/app/qwen-lab
./scripts/lab-compare-profiles.sh          # creates next vN
INCLUDE_LONG_GPU=0 ./scripts/lab-compare-profiles.sh
/home/kirua/app/infer-server/scripts/switch-context.sh status  # expect daily
```

Outputs for this version:
- `{study_path.relative_to(lab)}`
- `results/campaigns/{slug}-{ver}-compare.tsv`
- `results/campaigns/{slug}-{ver}-<profile>.tsv` + `-artifacts/`
- `campaigns/{slug}-{ver}/`

---

## 7. Limitations

1. NP=1 sequential role ticks only.
2. 7B Q5 quality ceiling.
3. Allowlist friction ≠ raw model skill.
4. Single micro-task (hello+CTest).
5. Last-tick timings only.
6. Profile switch cost in wall time.
"""
study_path.write_text(study)

# INDEX.md
header = (
    "# qwen-lab studies INDEX\n\n"
    "Versioned experiment write-ups. **Never overwrite** — bump `vN`.\n\n"
    "Layout:\n"
    "- Study: `docs/studies/YYYY-MM-DD-<slug>-vN.md`\n"
    "- Raw: `results/campaigns/<slug>-vN-*.tsv`\n"
    "- Board snapshot: `campaigns/<slug>-vN/`\n\n"
    "| Version | Date | Hypothesis | Profiles | Outcome | Path |\n"
    "|---|---|---|---|---|---|\n"
)
rows_idx = []
# rebuild from all studies
for p in sorted((lab / "docs" / "studies").glob("*-v*.md")):
    m = re.match(r"^(\d{4}-\d{2}-\d{2})-(.+)-(v\d+)\.md$", p.name)
    if not m:
        continue
    d, s, v = m.group(1), m.group(2), m.group(3)
    body = p.read_text(errors="replace")
    hyp = "—"
    hm = re.search(r"\*\*H1:\*\*\s*(.+)", body)
    if hm:
        hyp = hm.group(1).strip()[:80]
    # profiles / outcome from matching tsv if present
    tsv = lab / "results" / "campaigns" / f"{s}-{v}-compare.tsv"
    profiles = "—"
    outcome = "—"
    if tsv.exists():
        rr = list(csv.DictReader(tsv.open(), delimiter="\t"))
        profiles = ",".join(r.get("profile", "") for r in rr)
        if any(r.get("outcome") == "GO" and r.get("ctest_ok") == "1" for r in rr):
            w = winner(rr)[0]
            outcome = f"GO:{w}"
        else:
            outcome = ",".join(f"{r.get('profile')}={r.get('outcome')}" for r in rr)[:60]
    rows_idx.append(f"| {v} | {d} | {hyp.replace('|','/')} | {profiles} | {outcome} | [`{p.name}`](./{p.name}) |")

index_path.write_text(header + "\n".join(rows_idx) + "\n")
print(f"wrote {study_path}")
print(f"wrote {index_path}")
print(f"winner={win_name} overall={overall}")
PY

# MEMORY link
python3 - "${LAB_ROOT}/MEMORY.md" "${STUDY_MD}" "${VER}" "${SLUG}" <<'PY'
from pathlib import Path
import datetime, sys
mem, study, ver, slug = map(Path, sys.argv[1:2]) if False else (Path(sys.argv[1]), Path(sys.argv[2]), sys.argv[3], sys.argv[4])
text = mem.read_text() if mem.exists() else "# Memory\n"
day = datetime.datetime.utcnow().strftime("%Y-%m-%d")
heading = f"## {day}"
bullet = (
    f"- Study {slug} {ver} written: docs/studies/{study.name} "
    f"(INDEX: docs/studies/INDEX.md; raw results/campaigns/{slug}-{ver}-compare.tsv)"
)
if heading not in text:
    text = text.rstrip() + f"\n\n{heading}\n"
if bullet not in text:
    text = text.rstrip() + f"\n{bullet}\n"
mem.write_text(text if text.endswith("\n") else text + "\n")
print("MEMORY updated")
PY

echo "compare: done — ${STUDY_MD}"
"${SWITCH}" status | grep CONTEXT_PROFILE || true
