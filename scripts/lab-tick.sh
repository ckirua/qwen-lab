#!/usr/bin/env bash
# One autonomous lab iteration.
set -euo pipefail

LAB_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STATE="${LAB_ROOT}/.state/tick.env"
SWITCH="${INFER_SWITCH:-/home/kirua/app/infer-server/scripts/switch-context.sh}"
LAB_TSV="${LAB_ROOT}/results/lab.tsv"
LOCK="${LAB_ROOT}/locks/lab.lock"
DRY_RUN="${LAB_DRY_RUN:-0}"
PLAN_ONLY="${LAB_PLAN_ONLY:-0}"

mkdir -p "${LAB_ROOT}/locks" "${LAB_ROOT}/.state" "${LAB_ROOT}/results/campaigns" "${LAB_ROOT}/notes"

exec {LAB_LOCK_FD}>"${LOCK}"
if ! flock -n "${LAB_LOCK_FD}"; then
  echo "lab-tick: lab.lock held — concurrent tick forbidden" >&2
  exit 1
fi

restore_daily() {
  local hold
  hold="$(grep -E '^- HOLD_PROFILE:' "${LAB_ROOT}/WORKSTATE.md" 2>/dev/null | head -1 | awk '{print $3}' || echo 0)"
  if [[ "${hold}" == "1" ]]; then
    echo "lab-tick: HOLD_PROFILE=1 — skip restore" >&2
    return 0
  fi
  "${LAB_ROOT}/scripts/lab-restore-daily.sh" >/dev/null || "${LAB_ROOT}/scripts/lab-restore-daily.sh" || true
}
trap 'restore_daily' EXIT

iso_now() { date -u +%Y-%m-%dT%H:%M:%SZ; }
epoch_now() { date +%s; }

# shellcheck disable=SC1090
source "${STATE}"

MAX_ITERS="${MAX_ITERS:-12}"
MAX_WALL_H="${MAX_WALL_H:-6}"
CAMPAIGN_ID="${CAMPAIGN_ID:-cuda-graphs-101}"
ITER="${ITER:-0}"
OUTCOME="${OUTCOME:-}"
STARTED_AT="${STARTED_AT:-}"
WALL_STARTED_EPOCH="${WALL_STARTED_EPOCH:-}"

if [[ -n "${OUTCOME}" ]]; then
  echo "lab-tick: Outcome already set (${OUTCOME}) — refuse work"
  exit 0
fi

if [[ "${ITER}" -ge "${MAX_ITERS}" ]]; then
  OUTCOME="BUDGET"
  echo "OUTCOME=${OUTCOME}" >>"${STATE}.tmp" 2>/dev/null || true
  python3 - "${STATE}" <<'PY'
import re, pathlib, sys
p = pathlib.Path(sys.argv[1])
text = p.read_text()
text = re.sub(r'^OUTCOME=.*$', 'OUTCOME=BUDGET', text, flags=re.M)
if 'OUTCOME=' not in text:
    text += '\nOUTCOME=BUDGET\n'
p.write_text(text)
PY
  # update taskboard meta
  sed -i 's/^- Outcome:.*/- Outcome: BUDGET/' "${LAB_ROOT}/TASKBOARD.md" || true
  echo "lab-tick: ITER>=MAX — BUDGET"
  exit 0
fi

if [[ -z "${STARTED_AT}" ]]; then
  STARTED_AT="$(iso_now)"
  WALL_STARTED_EPOCH="$(epoch_now)"
fi

# wall budget
if [[ -n "${WALL_STARTED_EPOCH}" ]]; then
  elapsed=$(( $(epoch_now) - WALL_STARTED_EPOCH ))
  if [[ "${elapsed}" -ge $(( MAX_WALL_H * 3600 )) ]]; then
    python3 - "${STATE}" <<'PY'
import re, pathlib, sys
p = pathlib.Path(sys.argv[1])
text = p.read_text()
text = re.sub(r'^OUTCOME=.*$', 'OUTCOME=BUDGET', text, flags=re.M)
if 'OUTCOME=' not in text:
    text += '\nOUTCOME=BUDGET\n'
p.write_text(text)
PY
    sed -i 's/^- Outcome:.*/- Outcome: BUDGET/' "${LAB_ROOT}/TASKBOARD.md" || true
    echo "lab-tick: wall budget exhausted"
    exit 0
  fi
fi

profile_now="$("${SWITCH}" status 2>/dev/null | grep -E '^CONTEXT_PROFILE=' | head -1 | cut -d= -f2- || echo unknown)"
hold="$(grep -E '^- HOLD_PROFILE:' "${LAB_ROOT}/WORKSTATE.md" 2>/dev/null | head -1 | awk '{print $3}' || echo 0)"
profile_before="${profile_now}"
if [[ "${hold}" != "1" && "${profile_now}" != "daily" ]]; then
  echo "lab-tick: profile=${profile_now} — auto-restoring daily (ERROR_RESTORED)" >&2
  restore_daily
  profile_now="$("${SWITCH}" status 2>/dev/null | grep -E '^CONTEXT_PROFILE=' | head -1 | cut -d= -f2- || echo unknown)"
  echo "$(iso_now)	${CAMPAIGN_ID}	${ITER}	-	lab-restore-daily.sh	profile	${profile_now}	name	ERROR_RESTORED	" >>"${LAB_TSV}"
fi

# Assemble context
CONTEXT="$(python3 - "${LAB_ROOT}" <<'PY'
from pathlib import Path
root = Path(__file__) if False else Path(__import__('sys').argv[1])
parts = []
for name in ["SAFETY.md", "ALLOWLIST.md", "TASKBOARD.md", "WORKSTATE.md", "HYPOTHESES.md"]:
    p = root / name
    parts.append(f"===== {name} =====\n" + p.read_text()[:8000])
mem = (root / "MEMORY.md").read_text().splitlines()
parts.append("===== MEMORY.md (last 40) =====\n" + "\n".join(mem[-40:]))
tsv = (root / "results" / "lab.tsv").read_text().splitlines()
parts.append("===== lab.tsv (last 5) =====\n" + "\n".join(tsv[-5:]))
camp = root / "results" / "campaigns" / "cuda-graphs-101.tsv"
if camp.exists():
    lines = camp.read_text().splitlines()
    parts.append("===== campaign TSV (last 5) =====\n" + "\n".join(lines[-5:]))
print("\n\n".join(parts))
PY
)"

USER_PROMPT="$(cat <<EOF
Campaign: ${CAMPAIGN_ID}
Iter about to run: $((ITER + 1)) / ${MAX_ITERS}
Current profile: ${profile_now}
HOLD_PROFILE: ${hold}
PLAN_ONLY: ${PLAN_ONLY}

Propose the single next action for this tick. Prefer advancing the next TODO.
If PLAN_ONLY=1, return advance_task with command empty (propose task_id + rationale only).

${CONTEXT}
EOF
)"

ACTION_JSON=""
if [[ "${DRY_RUN}" == "1" && "${PLAN_ONLY}" != "1" ]]; then
  ACTION_JSON='{"action":"update_memory","task_id":"","command":"","cwd":"","memory_bullets":["dry-run tick: no tools"],"gate":"","rationale":"dry-run","hypothesis_updates":[]}'
else
  set +e
  ACTION_JSON="$("${LAB_ROOT}/scripts/lab-llm.sh" "${USER_PROMPT}")"
  llm_rc=$?
  set -e
  if [[ ${llm_rc} -ne 0 || -z "${ACTION_JSON}" ]]; then
    echo "lab-tick: LLM failed — recording ERROR, restoring daily" >&2
    echo "$(iso_now)	${CAMPAIGN_ID}	${ITER}	-	lab-llm.sh	error	1	count	llm_failed	ERROR" >>"${LAB_TSV}"
    exit 1
  fi
fi

echo "lab-tick: action=${ACTION_JSON}"

# Apply action via python helper
export LAB_ROOT ACTION_JSON CAMPAIGN_ID ITER LAB_TSV PLAN_ONLY profile_before profile_now
python3 <<'PY'
import json, os, re, subprocess, pathlib, datetime
from pathlib import Path

root = Path(os.environ["LAB_ROOT"])
action = json.loads(os.environ["ACTION_JSON"])
campaign = os.environ["CAMPAIGN_ID"]
iter_n = int(os.environ["ITER"])
tsv = Path(os.environ["LAB_TSV"])
plan_only = os.environ.get("PLAN_ONLY", "0") == "1"
iso = datetime.datetime.utcnow().strftime("%Y-%m-%dT%H:%M:%SZ")
new_iter = iter_n + 1

def read(p):
    return Path(p).read_text()

def write(p, text):
    Path(p).write_text(text)

board_path = root / "TASKBOARD.md"
board = read(board_path)
ws_path = root / "WORKSTATE.md"
mem_path = root / "MEMORY.md"
hyp_path = root / "HYPOTHESES.md"

act = action.get("action", "")
task_id = action.get("task_id") or ""
command = (action.get("command") or "").strip()
cwd = (action.get("cwd") or str(root)).strip()
rationale = action.get("rationale") or ""
gate = (action.get("gate") or "").strip()
bullets = action.get("memory_bullets") or []
hyp_updates = action.get("hypothesis_updates") or []

outcome = ""
tool = ""
metric = "ok"
value = "1"
unit = "count"
notes = rationale.replace("\t", " ")[:200]
tool_rc = 0

def move_task(board_text, tid, to_section):
    # Extract checkbox line for tid from any section and place under to_section
    lines = board_text.splitlines()
    item = None
    new_lines = []
    for line in lines:
        if re.search(rf"\b{re.escape(tid)}:", line) and line.strip().startswith("- ["):
            item = line
            # drop from current
            continue
        new_lines.append(line)
    if item is None:
        return "\n".join(new_lines), False
    # normalize checkbox
    if to_section == "DONE":
        item = re.sub(r"^- \[[ xX]\]", "- [x]", item)
    else:
        item = re.sub(r"^- \[[ xX]\]", "- [ ]", item)
    # insert under heading
    out = []
    inserted = False
    i = 0
    while i < len(new_lines):
        out.append(new_lines[i])
        if new_lines[i].strip() == f"## {to_section}" and not inserted:
            # skip blank then insert
            out.append(item)
            inserted = True
        i += 1
    if not inserted:
        out.append(f"## {to_section}")
        out.append(item)
    return "\n".join(out) + "\n", True

def set_meta_outcome(board_text, outcome):
    return re.sub(r"^- Outcome:.*$", f"- Outcome: {outcome}", board_text, count=1, flags=re.M)

def set_meta_budget(board_text, it, max_it, started):
    text = re.sub(
        r"^- Budget:.*$",
        f"- Budget: iters {it}/{max_it}, wall started {started}",
        board_text,
        count=1,
        flags=re.M,
    )
    return text

def append_memory(bullets):
    if not bullets:
        return
    text = read(mem_path)
    day = datetime.datetime.utcnow().strftime("%Y-%m-%d")
    heading = f"## {day}"
    if heading not in text:
        text = text.rstrip() + f"\n\n{heading}\n"
    for b in bullets[:5]:
        text = text.rstrip() + f"\n- {b}"
    lines = text.splitlines()
    if len(lines) > 80:
        # compact note
        notes = root / "notes" / f"{day}-memory-compact.md"
        notes.write_text("# Memory compact\n\n" + "\n".join(lines) + "\n")
        # keep header + last ~20 content lines
        keep = lines[:8] + [f"## {day}", f"- Compacted older memory → notes/{notes.name}"] + lines[-12:]
        text = "\n".join(keep) + "\n"
    write(mem_path, text if text.endswith("\n") else text + "\n")

def update_hypotheses(updates):
    if not updates:
        return
    text = read(hyp_path)
    for u in updates:
        hid = u.get("id")
        status = u.get("status")
        evidence = u.get("evidence") or ""
        if not hid or not status:
            continue
        # replace status cell in row starting with | Hid |
        def repl(m):
            cells = [c.strip() for c in m.group(0).strip("|").split("|")]
            # ID Claim Status Evidence
            if len(cells) >= 4:
                cells[2] = status
                if evidence:
                    cells[3] = evidence
            return "| " + " | ".join(cells) + " |"
        text = re.sub(rf"^\|\s*{re.escape(hid)}\s*\|.*$", repl, text, count=1, flags=re.M)
    write(hyp_path, text)

# Enforce ≤1 DOING: clear existing DOING into TODO if advancing different task
if act == "advance_task" and task_id:
    board, _ = move_task(board, task_id, "DOING")
    # remove any other DOING items back to TODO
    doing_section = False
    lines = board.splitlines()
    rebuilt = []
    extras = []
    for line in lines:
        if line.startswith("## "):
            doing_section = line.strip() == "## DOING"
            rebuilt.append(line)
            continue
        if doing_section and line.strip().startswith("- [") and task_id not in line:
            extras.append(line)
            continue
        rebuilt.append(line)
    if extras:
        # put extras back under TODO
        out = []
        for line in rebuilt:
            out.append(line)
            if line.strip() == "## TODO":
                out.extend(extras)
        board = "\n".join(out) + "\n"

if act == "update_memory":
    append_memory(bullets)
    tool = "update_memory"
elif act == "block_human":
    if task_id:
        board, _ = move_task(board, task_id, "BLOCKED")
    append_memory([f"BLOCKED {task_id}: {rationale}"][:1] and [f"BLOCKED {task_id}: {rationale}"])
    tool = "block_human"
elif act == "declare_gate":
    if gate in ("GO", "NO-GO"):
        outcome = gate
        board = set_meta_outcome(board, gate if gate == "NO-GO" else "GO (learning)" if gate == "GO" else gate)
        tool = "declare_gate"
    else:
        tool = "declare_gate"
        notes = "invalid gate"
elif act == "advance_task":
    tool = command or "plan_only"
    # Refuse HUMAN_GATE tasks without approval
    board_l = board.lower()
    task_line = ""
    for line in board.splitlines():
        if task_id and re.search(rf"\b{re.escape(task_id)}:", line):
            task_line = line
            break
    human_approved = bool(re.search(r"^- \[x\] approved:", board, re.M))
    if "[HUMAN_GATE]" in task_line and not human_approved:
        board, _ = move_task(board, task_id, "TODO")
        append_memory([f"Refused {task_id}: HUMAN_GATE not approved"])
        tool = "human_gate_refuse"
        notes = f"HUMAN_GATE blocked {task_id}"
        command = ""
        plan_only = True
    if plan_only or not command:
        append_memory([f"Planned {task_id}: {rationale}"] if task_id else [f"Planned: {rationale}"])
        notes = f"plan_only {task_id}: {rationale}".replace("\t", " ")[:200]
    else:
        # run via lab-run
        import shlex
        try:
            argv = shlex.split(command)
        except ValueError as e:
            tool_rc = 4
            notes = f"bad command: {e}"
            argv = []
        if argv:
            run = [str(root / "scripts" / "lab-run.sh"), "--cwd", cwd or str(root), "--", *argv]
            # human-gate tools
            if "bench-final-pass" in command or "daily-spec" in command:
                run.insert(1, "--human-gate")
            if "bench-final-pass" in command or "switch-context" in command and "daily" not in argv[-1:]:
                if "bench-final-pass" in command:
                    run.insert(1, "--gpu-lock")
            proc = subprocess.run(run, cwd=str(root), capture_output=True, text=True)
            tool_rc = proc.returncode
            out_snip = (proc.stdout or "")[-1500:] + (proc.stderr or "")[-800:]
            notes = (rationale + " | " + out_snip.replace("\n", " ").replace("\t", " "))[:240]
            # On success move to DONE
            if tool_rc == 0 and task_id:
                board, _ = move_task(board, task_id, "DONE")
                append_memory([f"Done {task_id}: {rationale}"])
            elif tool_rc != 0 and task_id:
                # leave in DOING / optionally BLOCKED on hard deny
                if tool_rc in (3, 4):
                    board, _ = move_task(board, task_id, "BLOCKED")
            value = str(tool_rc)
            metric = "exit"
else:
    tool = "unknown_action"
    tool_rc = 1
    notes = f"unknown action {act}"

update_hypotheses(hyp_updates)

# sync campaign board copy
camp_board = root / "campaigns" / "cuda-graphs-101" / "TASKBOARD.md"
# budget meta
state_text = read(root / ".state" / "tick.env")
m = re.search(r"^STARTED_AT=(.*)$", state_text, re.M)
started = (m.group(1) if m and m.group(1) else iso)
max_it = 12
mm = re.search(r"^MAX_ITERS=(.*)$", state_text, re.M)
if mm and mm.group(1).strip():
    max_it = int(mm.group(1).strip())
board = set_meta_budget(board, new_iter, max_it, started)
write(board_path, board)
write(camp_board, board)

# workstate
hold_m = re.search(r"^- HOLD_PROFILE:\s*(\S+)", read(ws_path), re.M)
hold_v = hold_m.group(1) if hold_m else "0"
ws = f"""# Workstate
- Updated: {iso}
- Campaign: {campaign}
- Iter: {new_iter} / {max_it}
- Profile_before_tick: {os.environ.get('profile_before','')}
- Profile_now: {os.environ.get('profile_now','')}
- HOLD_PROFILE: {hold_v}
- Last_tool: {tool}
- Last_result_row: results/lab.tsv
- Next_action: {rationale}
- Stop_reason: {outcome}
"""
write(ws_path, ws)

# TSV row
with tsv.open("a") as f:
    f.write(f"{iso}\t{campaign}\t{new_iter}\t{task_id}\t{tool}\t{metric}\t{value}\t{unit}\t{notes}\t{outcome}\n")

# state
st = read(root / ".state" / "tick.env")
st = re.sub(r"^ITER=.*$", f"ITER={new_iter}", st, flags=re.M)
if not re.search(r"^STARTED_AT=.", st, re.M):
    st = re.sub(r"^STARTED_AT=.*$", f"STARTED_AT={iso}", st, flags=re.M)
if "WALL_STARTED_EPOCH=" in st and re.search(r"^WALL_STARTED_EPOCH=\s*$", st, re.M):
    import time
    st = re.sub(r"^WALL_STARTED_EPOCH=.*$", f"WALL_STARTED_EPOCH={int(time.time())}", st, flags=re.M)
elif re.search(r"^WALL_STARTED_EPOCH=$", st, re.M):
    import time
    st = re.sub(r"^WALL_STARTED_EPOCH=.*$", f"WALL_STARTED_EPOCH={int(time.time())}", st, flags=re.M)
if outcome:
    st = re.sub(r"^OUTCOME=.*$", f"OUTCOME={outcome}", st, flags=re.M)
write(root / ".state" / "tick.env", st)

# expose outcome to shell
Path("/tmp/qwen-lab-last-outcome").write_text(outcome)
Path("/tmp/qwen-lab-last-rc").write_text(str(tool_rc))
print(json.dumps({"iter": new_iter, "action": act, "task_id": task_id, "outcome": outcome, "tool_rc": tool_rc}))
PY

# Ensure STARTED_AT / WALL set if empty
python3 - "${STATE}" "$(iso_now)" "$(epoch_now)" <<'PY'
import pathlib, re, sys
p = pathlib.Path(sys.argv[1])
iso, epoch = sys.argv[2], sys.argv[3]
text = p.read_text()
if re.search(r'^STARTED_AT=\s*$', text, re.M):
    text = re.sub(r'^STARTED_AT=.*$', f'STARTED_AT={iso}', text, flags=re.M)
if re.search(r'^WALL_STARTED_EPOCH=\s*$', text, re.M):
    text = re.sub(r'^WALL_STARTED_EPOCH=.*$', f'WALL_STARTED_EPOCH={epoch}', text, flags=re.M)
p.write_text(text)
PY

# shellcheck disable=SC1090
source "${STATE}"
echo "lab-tick: done ITER=${ITER} OUTCOME=${OUTCOME:-}"
# trap restores daily
exit 0
