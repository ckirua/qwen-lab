#!/usr/bin/env bash
# One autonomous lab iteration (fresh LLM context; file memory only).
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

MAX_ITERS="${MAX_ITERS:-30}"
MAX_WALL_H="${MAX_WALL_H:-4}"
CAMPAIGN_ID="${CAMPAIGN_ID:-autonomous-hello}"
ITER="${ITER:-0}"
OUTCOME="${OUTCOME:-}"
STARTED_AT="${STARTED_AT:-}"
WALL_STARTED_EPOCH="${WALL_STARTED_EPOCH:-}"
CAMPAIGN_TSV="${LAB_CAMPAIGN_TSV:-${LAB_ROOT}/results/campaigns/${CAMPAIGN_ID}.tsv}"

if [[ -n "${OUTCOME}" ]]; then
  echo "lab-tick: Outcome already set (${OUTCOME}) — refuse work"
  exit 0
fi

set_outcome() {
  local oc="$1"
  python3 - "${STATE}" "${oc}" <<'PY'
import re, pathlib, sys
p = pathlib.Path(sys.argv[1])
oc = sys.argv[2]
text = p.read_text()
text = re.sub(r'^OUTCOME=.*$', f'OUTCOME={oc}', text, flags=re.M)
if 'OUTCOME=' not in text:
    text += f'\nOUTCOME={oc}\n'
p.write_text(text)
PY
  sed -i "s/^- Outcome:.*/- Outcome: ${oc}/" "${LAB_ROOT}/TASKBOARD.md" || true
}

if [[ "${ITER}" -ge "${MAX_ITERS}" ]]; then
  set_outcome "BUDGET"
  echo "lab-tick: ITER>=MAX — BUDGET"
  exit 0
fi

if [[ -z "${STARTED_AT}" ]]; then
  STARTED_AT="$(iso_now)"
  WALL_STARTED_EPOCH="$(epoch_now)"
fi

if [[ -n "${WALL_STARTED_EPOCH}" ]]; then
  elapsed=$(( $(epoch_now) - WALL_STARTED_EPOCH ))
  if [[ "${elapsed}" -ge $(( MAX_WALL_H * 3600 )) ]]; then
    set_outcome "BUDGET"
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

# Assemble fresh prompt with hard budget (no chat history)
CONTEXT="$(
  CAMPAIGN_ID="${CAMPAIGN_ID}" CAMPAIGN_TSV="${CAMPAIGN_TSV}" python3 - "${LAB_ROOT}" <<'PY'
from pathlib import Path
import os
root = Path(__import__("sys").argv[1])
campaign = os.environ.get("CAMPAIGN_ID", "autonomous-hello")
camp_tsv = Path(os.environ.get("CAMPAIGN_TSV", str(root / "results" / "campaigns" / f"{campaign}.tsv")))
parts = []

def head_lines(path: Path, n: int) -> str:
    if not path.exists():
        return f"(missing {path.name})"
    lines = path.read_text(errors="replace").splitlines()
    return "\n".join(lines[:n])

def board_compact(text: str) -> str:
    # Prefer Meta+TODO+DOING+DONE+BLOCKED+Gates if short; else Meta+DOING+TODO+Gates
    if len(text) <= 4500:
        return text
    keep = []
    section = None
    wanted = {"Meta", "TODO", "DOING", "Gates", "BLOCKED"}
    for line in text.splitlines():
        if line.startswith("## "):
            section = line[3:].strip()
        if section is None or section in wanted or line.startswith("# "):
            keep.append(line)
    return "\n".join(keep)[:4500]

parts.append("===== SAFETY.md =====\n" + head_lines(root / "SAFETY.md", 60))
parts.append("===== ALLOWLIST.md =====\n" + head_lines(root / "ALLOWLIST.md", 50))
board = (root / "TASKBOARD.md").read_text(errors="replace") if (root / "TASKBOARD.md").exists() else ""
parts.append("===== TASKBOARD.md =====\n" + board_compact(board))
parts.append("===== WORKSTATE.md =====\n" + head_lines(root / "WORKSTATE.md", 40))

plan = root / "campaigns" / campaign / "plan.md"
if plan.exists():
    parts.append("===== plan.md (≤80 lines) =====\n" + head_lines(plan, 80))
else:
    parts.append("===== plan.md =====\n(missing — create via write_file on T1)")

mem_lines = (root / "MEMORY.md").read_text(errors="replace").splitlines() if (root / "MEMORY.md").exists() else []
parts.append("===== MEMORY.md (last 25) =====\n" + "\n".join(mem_lines[-25:]))

last_out = root / ".state" / "last_tool_output.txt"
last_tool = root / ".state" / "last_tool.txt"
handoff = last_out if last_out.exists() else last_tool
if handoff.exists():
    parts.append("===== last_tool_output.txt (handoff) =====\n" + handoff.read_text(errors="replace")[:1500])
else:
    parts.append("===== last_tool_output.txt =====\n(none — first tick or cleared)")

parts.append(
    "===== HANDOFF RULE =====\n"
    "Chat history is EMPTY. Continue ONLY from TASKBOARD/WORKSTATE/MEMORY/plan/last_tool_output.\n"
    "Follow WORKSTATE Next_action when present."
)

tsv = (root / "results" / "lab.tsv").read_text(errors="replace").splitlines() if (root / "results" / "lab.tsv").exists() else []
parts.append("===== lab.tsv (last 3) =====\n" + "\n".join(tsv[-3:]))
if camp_tsv.exists():
    lines = camp_tsv.read_text(errors="replace").splitlines()
    parts.append(f"===== campaign TSV {camp_tsv.name} (last 3) =====\n" + "\n".join(lines[-3:]))

text = "\n\n".join(parts)
# Soft ceiling ~8k tokens ≈ 32k chars; prefer ~4–6k tok ≈ 16–24k chars
if len(text) > 28000:
    text = text[:28000] + "\n\n[truncated for context budget]\n"
print(text)
PY
)"

ROLE="$(grep -E '^- ROLE:' "${LAB_ROOT}/WORKSTATE.md" 2>/dev/null | head -1 | awk '{print $3}' || echo plan)"

USER_PROMPT="$(cat <<EOF
Campaign: ${CAMPAIGN_ID}
Iter about to run: $((ITER + 1)) / ${MAX_ITERS}
ROLE: ${ROLE}
Current profile: ${profile_now}
HOLD_PROFILE: ${hold}
PLAN_ONLY: ${PLAN_ONLY}

FRESH CHAT — no prior messages. State is files only.
Propose ONE next action from TASKBOARD + WORKSTATE.Next_action + last_tool_output.
- Prefer write_file for plan.md / CMakeLists.txt / main.cpp; advance_task for cmake/ctest.
- For T4 use: `cmake -B sandbox/hello-cpp/build -S sandbox/hello-cpp` then `cmake --build sandbox/hello-cpp/build`
- For T5 use exact: `ctest --test-dir sandbox/hello-cpp/build --output-on-failure`
- cwd: omit/empty (lab root). Never cwd=qwen-lab.
- Do not declare_gate GO unless canonical sandbox/hello-cpp/build/hello exists and ctest green.

${CONTEXT}
EOF
)"

ACTION_JSON=""
if [[ "${DRY_RUN}" == "1" && "${PLAN_ONLY}" != "1" ]]; then
  ACTION_JSON='{"action":"update_memory","task_id":"","command":"","cwd":"","path":"","content":"","memory_bullets":["dry-run tick: no tools"],"gate":"","rationale":"dry-run","hypothesis_updates":[]}'
else
  set +e
  ACTION_JSON="$(CAMPAIGN_ID="${CAMPAIGN_ID}" "${LAB_ROOT}/scripts/lab-llm.sh" "${USER_PROMPT}")"
  llm_rc=$?
  set -e
  if [[ ${llm_rc} -ne 0 || -z "${ACTION_JSON}" ]]; then
    echo "lab-tick: LLM failed — recording ERROR, restoring daily" >&2
    echo "$(iso_now)	${CAMPAIGN_ID}	${ITER}	-	lab-llm.sh	error	1	count	llm_failed	ERROR" >>"${LAB_TSV}"
    exit 1
  fi
fi

echo "lab-tick: action=${ACTION_JSON}"

export LAB_ROOT ACTION_JSON CAMPAIGN_ID ITER LAB_TSV PLAN_ONLY profile_before profile_now CAMPAIGN_TSV MAX_ITERS ROLE
python3 <<'PY'
import json, os, re, subprocess, pathlib, datetime, shlex, time
from pathlib import Path

root = Path(os.environ["LAB_ROOT"])
action = json.loads(os.environ["ACTION_JSON"])
campaign = os.environ["CAMPAIGN_ID"]
iter_n = int(os.environ["ITER"])
tsv = Path(os.environ["LAB_TSV"])
camp_tsv = Path(os.environ["CAMPAIGN_TSV"])
plan_only = os.environ.get("PLAN_ONLY", "0") == "1"
max_it = int(os.environ.get("MAX_ITERS", "30"))
role = os.environ.get("ROLE", "plan")
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
last_tool_path = root / ".state" / "last_tool.txt"
last_tool_path.parent.mkdir(parents=True, exist_ok=True)

act = action.get("action", "")
task_id = action.get("task_id") or ""
command = (action.get("command") or "").strip()
cwd = (action.get("cwd") or "").strip()
# Normalize cwd: model often emits "qwen-lab" or other non-paths
_aliases = {"", ".", "qwen-lab", "lab", str(root)}
if cwd in _aliases or cwd.rstrip("/") in ("qwen-lab", "lab"):
    cwd = str(root)
else:
    p = Path(cwd)
    if not p.is_absolute():
        p = root / p
    try:
        resolved = p.resolve()
    except Exception:
        resolved = root
    if str(resolved) == str(root) or str(resolved).startswith(str(root) + os.sep):
        cwd = str(resolved)
    else:
        cwd = str(root)
rationale = action.get("rationale") or ""
gate = (action.get("gate") or "").strip()
bullets = action.get("memory_bullets") or []
hyp_updates = action.get("hypothesis_updates") or []
wpath = (action.get("path") or "").strip()
wcontent = action.get("content")
if wcontent is None:
    wcontent = ""

# If command uses lab-root-relative sandbox/… paths, force cwd=lab root
# (avoids nested sandbox/hello-cpp/sandbox/hello-cpp/build when cwd was hello-cpp)
if command and "sandbox/" in command:
    cwd = str(root)
# Auto-add -S for hello configure if missing
if command.startswith("cmake ") and "-B sandbox/hello-cpp/build" in command and "-S" not in command:
    command = command.replace(
        "-B sandbox/hello-cpp/build",
        "-B sandbox/hello-cpp/build -S sandbox/hello-cpp",
        1,
    )

outcome = ""
tool = ""
metric = "ok"
value = "1"
unit = "count"
notes = rationale.replace("\t", " ")[:200]
tool_rc = 0
last_result_snip = ""

def move_task(board_text, tid, to_section):
    lines = board_text.splitlines()
    item = None
    new_lines = []
    for line in lines:
        if re.search(rf"\b{re.escape(tid)}:", line) and line.strip().startswith("- ["):
            item = line
            continue
        new_lines.append(line)
    if item is None:
        return "\n".join(new_lines), False
    if to_section == "DONE":
        item = re.sub(r"^- \[[ xX]\]", "- [x]", item)
    else:
        item = re.sub(r"^- \[[ xX]\]", "- [ ]", item)
    out = []
    inserted = False
    for line in new_lines:
        out.append(line)
        if line.strip() == f"## {to_section}" and not inserted:
            out.append(item)
            inserted = True
    if not inserted:
        out.append(f"## {to_section}")
        out.append(item)
    return "\n".join(out) + "\n", True

def set_meta_outcome(board_text, outcome):
    return re.sub(r"^- Outcome:.*$", f"- Outcome: {outcome}", board_text, count=1, flags=re.M)

def set_meta_budget(board_text, it, max_it, started):
    return re.sub(
        r"^- Budget:.*$",
        f"- Budget: iters {it}/{max_it}, wall started {started}",
        board_text,
        count=1,
        flags=re.M,
    )

def append_memory(bullets):
    if not bullets:
        return
    text = read(mem_path) if mem_path.exists() else "# Memory\n"
    day = datetime.datetime.utcnow().strftime("%Y-%m-%d")
    heading = f"## {day}"
    if heading not in text:
        text = text.rstrip() + f"\n\n{heading}\n"
    for b in bullets[:5]:
        text = text.rstrip() + f"\n- {b}"
    lines = text.splitlines()
    if len(lines) > 80:
        notes = root / "notes" / f"{day}-memory-compact.md"
        notes.write_text("# Memory compact\n\n" + "\n".join(lines) + "\n")
        keep = lines[:8] + [f"## {day}", f"- Compacted older memory → notes/{notes.name}"] + lines[-12:]
        text = "\n".join(keep) + "\n"
    write(mem_path, text if text.endswith("\n") else text + "\n")

def update_hypotheses(updates):
    if not updates or not hyp_path.exists():
        return
    text = read(hyp_path)
    for u in updates:
        hid = u.get("id")
        status = u.get("status")
        evidence = u.get("evidence") or ""
        if not hid or not status:
            continue
        def repl(m):
            cells = [c.strip() for c in m.group(0).strip("|").split("|")]
            if len(cells) >= 4:
                cells[2] = status
                if evidence:
                    cells[3] = evidence
            return "| " + " | ".join(cells) + " |"
        text = re.sub(rf"^\|\s*{re.escape(hid)}\s*\|.*$", repl, text, count=1, flags=re.M)
    write(hyp_path, text)

def persist_last_tool(label, rc, body):
    global last_result_snip
    snippet = (body or "")[-1500:]
    last_result_snip = snippet.replace("\n", " ")[:240]
    text = f"tool={label}\nrc={rc}\n{snippet}\n"
    last_tool_path.write_text(text)
    # Explicit handoff alias for next tick (same truncated output)
    (root / ".state" / "last_tool_output.txt").write_text(text)

def hello_artifacts_ok() -> bool:
    plan = root / "campaigns" / campaign / "plan.md"
    main = root / "sandbox" / "hello-cpp" / "main.cpp"
    cmake = root / "sandbox" / "hello-cpp" / "CMakeLists.txt"
    exe = root / "sandbox" / "hello-cpp" / "build" / "hello"
    return plan.exists() and main.exists() and cmake.exists() and exe.is_file()

def ctest_passed_for_campaign() -> bool:
    """Require evidence of ctest rc=0 on the canonical build dir (not nested)."""
    canon = "sandbox/hello-cpp/build"
    nested_bad = "sandbox/hello-cpp/sandbox/"
    if last_tool_path.exists():
        t = last_tool_path.read_text(errors="replace")
        if "ctest" in t and re.search(r"^rc=0\s*$", t, re.M):
            if nested_bad in t:
                return False
            if canon in t or (root / "sandbox" / "hello-cpp" / "build").exists():
                # Prefer live verify when build exists
                build = root / "sandbox" / "hello-cpp" / "build"
                if build.exists():
                    proc = subprocess.run(
                        ["ctest", "--test-dir", str(build), "--output-on-failure"],
                        cwd=str(root),
                        capture_output=True,
                        text=True,
                    )
                    return proc.returncode == 0
                return canon in t
    for path in (tsv, camp_tsv):
        if not path.exists():
            continue
        for line in path.read_text(errors="replace").splitlines()[-40:]:
            cols = line.split("\t")
            if len(cols) < 7:
                continue
            if cols[1] != campaign:
                continue
            toolname = cols[4]
            val = cols[6]
            if "ctest" in toolname and val == "0" and nested_bad not in line:
                if hello_artifacts_ok():
                    return True
    return False

def suggest_role(board_text: str, act: str, task_id: str) -> str:
    # Heuristic cadence
    if act == "write_file" and task_id == "T1":
        return "implement"
    if act == "write_file":
        return "implement"
    if act == "advance_task" and command and "ctest" in command:
        return "gate" if tool_rc == 0 else "test"
    if act == "advance_task" and command and "cmake" in command:
        return "test"
    if act == "declare_gate":
        return "gate"
    # board-driven
    for line in board_text.splitlines():
        if line.strip().startswith("- [") and "##" not in line:
            pass
    todo = []
    section = None
    for line in board_text.splitlines():
        if line.startswith("## "):
            section = line[3:].strip()
            continue
        if section == "TODO" and line.strip().startswith("- ["):
            todo.append(line)
    if not todo:
        return "gate"
    head = todo[0]
    if "T1:" in head:
        return "plan"
    if "T2:" in head or "T3:" in head:
        return "implement"
    if "T4:" in head or "T5:" in head:
        return "test"
    return "gate"

# Enforce ≤1 DOING
if act in ("advance_task", "write_file") and task_id:
    board, _ = move_task(board, task_id, "DOING")
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
        out = []
        for line in rebuilt:
            out.append(line)
            if line.strip() == "## TODO":
                out.extend(extras)
        board = "\n".join(out) + "\n"
    else:
        board = "\n".join(rebuilt) + "\n"

if act == "update_memory":
    append_memory(bullets)
    tool = "update_memory"
    persist_last_tool(tool, 0, "memory updated")
elif act == "block_human":
    if task_id:
        board, _ = move_task(board, task_id, "BLOCKED")
    append_memory([f"BLOCKED {task_id}: {rationale}"])
    tool = "block_human"
    persist_last_tool(tool, 0, rationale)
elif act == "declare_gate":
    tool = "declare_gate"
    if gate == "GO":
        plan_ok = (root / "campaigns" / campaign / "plan.md").exists()
        ctest_ok = ctest_passed_for_campaign()
        arts_ok = hello_artifacts_ok() if campaign.startswith("autonomous-hello") else True
        if campaign.startswith("autonomous-hello") and (not ctest_ok or not plan_ok or not arts_ok):
            tool_rc = 1
            notes = (
                f"refused GO: plan={plan_ok} ctest={ctest_ok} artifacts={arts_ok} "
                "(need plan.md + sandbox/hello-cpp/{{main.cpp,CMakeLists.txt,build/hello}} + green ctest)"
            )
            persist_last_tool(tool, tool_rc, notes)
            append_memory([notes])
        else:
            outcome = "GO"
            board = set_meta_outcome(board, "GO")
            persist_last_tool(tool, 0, f"gate=GO {rationale}")
            append_memory(bullets or [f"Gate GO: {rationale}"])
    elif gate == "NO-GO":
        outcome = "NO-GO"
        board = set_meta_outcome(board, "NO-GO")
        persist_last_tool(tool, 0, f"gate=NO-GO {rationale}")
        append_memory(bullets or [f"Gate NO-GO: {rationale}"])
    else:
        notes = "invalid gate"
        tool_rc = 1
        persist_last_tool(tool, tool_rc, notes)
elif act == "write_file":
    # Normalize common bare filenames / cwd-relative paths to lab-root relatives
    def normalize_write_path(p: str, cwd_hint: str) -> str:
        p = (p or "").strip().lstrip("./")
        if not p:
            return p
        if p.startswith("sandbox/") or p.startswith("campaigns/") or p.startswith("notes/"):
            return p
        base = Path(p).name
        hello_names = {
            "CMakeLists.txt", "main.cpp", "main.cc", "main.cxx",
            "hello.cpp", "README.md",
        }
        if base in hello_names or p.startswith("hello-cpp/"):
            if p.startswith("hello-cpp/"):
                return "sandbox/" + p
            return f"sandbox/hello-cpp/{base}"
        # cwd hint: sandbox/hello-cpp → join
        ch = (cwd_hint or "").strip().rstrip("/")
        if ch.endswith("sandbox/hello-cpp") or ch.endswith("hello-cpp"):
            return f"sandbox/hello-cpp/{base}"
        if "autonomous-hello" in ch and base == "plan.md":
            return "campaigns/autonomous-hello/plan.md"
        if base == "plan.md":
            return "campaigns/autonomous-hello/plan.md"
        return p

    wpath = normalize_write_path(wpath, cwd)
    tool = f"write_file:{wpath}"
    if not wpath:
        tool_rc = 4
        notes = "write_file missing path"
        persist_last_tool(tool, tool_rc, notes)
    else:
        # content via temp file to avoid argv limits
        import tempfile
        with tempfile.NamedTemporaryFile("w", delete=False, encoding="utf-8") as tf:
            tf.write(wcontent if isinstance(wcontent, str) else str(wcontent))
            tmp_name = tf.name
        try:
            proc = subprocess.run(
                [str(root / "scripts" / "lab-write.sh"), "--file", wpath, "--from", tmp_name],
                cwd=str(root),
                capture_output=True,
                text=True,
            )
            tool_rc = proc.returncode
            out_snip = (proc.stdout or "") + (proc.stderr or "")
            persist_last_tool(tool, tool_rc, out_snip)
            notes = (rationale + " | " + out_snip.replace("\n", " ").replace("\t", " "))[:240]
            if tool_rc == 0 and task_id:
                board, _ = move_task(board, task_id, "DONE")
                append_memory([f"Wrote {wpath} ({task_id}): {rationale}"] + list(bullets[:2]))
            elif tool_rc != 0 and task_id:
                # leave on TODO for retry (do not BLOCK on path mistakes)
                board, _ = move_task(board, task_id, "TODO")
                append_memory([f"write_file failed rc={tool_rc} path={wpath}: use sandbox/hello-cpp/…"])
            value = str(tool_rc)
            metric = "exit"
        finally:
            Path(tmp_name).unlink(missing_ok=True)
elif act == "advance_task":
    tool = command or "plan_only"
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
        persist_last_tool(tool, 0, notes)
    if plan_only or not command:
        append_memory([f"Planned {task_id}: {rationale}"] if task_id else [f"Planned: {rationale}"])
        notes = f"plan_only {task_id}: {rationale}".replace("\t", " ")[:200]
        persist_last_tool(tool, 0, notes)
    else:
        # Allow "cmake -B ... && cmake --build ..." only as two separate advances —
        # reject shell metacharacters / pipelines.
        if any(x in command for x in ("&&", "|", ";", "`", "$(", "\n")):
            # Special-case documented T4 double cmake: run sequentially if both halves allowlisted
            if "&&" in command and all(p not in command for p in ("|", ";", "`", "$(")):
                parts = [p.strip() for p in command.split("&&")]
            else:
                parts = []
                tool_rc = 4
                notes = "denied shell metacharacters in command"
                persist_last_tool(tool, tool_rc, notes)
                parts = None
        else:
            parts = [command]

        if parts is not None:
            combined_out = []
            tool_rc = 0
            for part in parts:
                try:
                    argv = shlex.split(part)
                except ValueError as e:
                    tool_rc = 4
                    notes = f"bad command: {e}"
                    argv = []
                if not argv:
                    break
                run = [str(root / "scripts" / "lab-run.sh"), "--cwd", cwd or str(root), "--", *argv]
                if "bench-final-pass" in part or "daily-spec" in part:
                    run.insert(1, "--human-gate")
                if "bench-final-pass" in part:
                    run.insert(1, "--gpu-lock")
                proc = subprocess.run(run, cwd=str(root), capture_output=True, text=True)
                combined_out.append(f"$ {part}\nrc={proc.returncode}\n{(proc.stdout or '')}\n{(proc.stderr or '')}")
                if proc.returncode != 0:
                    tool_rc = proc.returncode
                    break
            out_snip = "\n".join(combined_out)
            persist_last_tool(command, tool_rc, out_snip)
            notes = (rationale + " | " + out_snip.replace("\n", " ").replace("\t", " "))[:240]
            if tool_rc == 0 and task_id:
                board, _ = move_task(board, task_id, "DONE")
                append_memory([f"Done {task_id}: {rationale}"])
            elif tool_rc != 0 and task_id:
                if tool_rc in (3, 4):
                    board, _ = move_task(board, task_id, "BLOCKED")
            value = str(tool_rc)
            metric = "exit"
            # campaign TSV row for cmake/ctest
            if "cmake" in command or "ctest" in command:
                camp_tsv.parent.mkdir(parents=True, exist_ok=True)
                if not camp_tsv.exists():
                    camp_tsv.write_text("iso\tcampaign\titer\ttask\ttool\trc\tnotes\n")
                with camp_tsv.open("a") as cf:
                    cf.write(f"{iso}\t{campaign}\t{new_iter}\t{task_id}\t{command}\t{tool_rc}\t{notes[:120]}\n")
else:
    tool = "unknown_action"
    tool_rc = 1
    notes = f"unknown action {act}"
    persist_last_tool(tool, tool_rc, notes)

update_hypotheses(hyp_updates)

# sync campaign board copy
camp_dir = root / "campaigns" / campaign
camp_dir.mkdir(parents=True, exist_ok=True)
camp_board = camp_dir / "TASKBOARD.md"

state_text = read(root / ".state" / "tick.env")
m = re.search(r"^STARTED_AT=(.*)$", state_text, re.M)
started = (m.group(1) if m and m.group(1) else iso)
mm = re.search(r"^MAX_ITERS=(.*)$", state_text, re.M)
if mm and mm.group(1).strip():
    max_it = int(mm.group(1).strip())
board = set_meta_budget(board, new_iter, max_it, started)
# keep campaign meta name
board = re.sub(r"^- Campaign:.*$", f"- Campaign: {campaign}", board, count=1, flags=re.M)
write(board_path, board)
write(camp_board, board)

next_role = suggest_role(board, act, task_id)
hold_m = re.search(r"^- HOLD_PROFILE:\s*(\S+)", read(ws_path), re.M) if ws_path.exists() else None
hold_v = hold_m.group(1) if hold_m else "0"
# Explicit next-tick handoff (files only — chat is always fresh)
next_hint = rationale or ""
if act == "write_file" and tool_rc == 0:
    if "CMakeLists" in wpath or wpath.endswith("main.cpp"):
        next_hint = "Sources ready → advance_task T4: cmake -B sandbox/hello-cpp/build -S sandbox/hello-cpp (cwd empty)"
elif act == "advance_task" and command and "cmake -B" in command and tool_rc == 0:
    next_hint = "Configured → advance_task T4/T5: cmake --build sandbox/hello-cpp/build then ctest"
elif act == "advance_task" and command and "cmake --build" in command and tool_rc == 0:
    next_hint = "Built → advance_task T5: ctest --test-dir sandbox/hello-cpp/build --output-on-failure"
elif act == "advance_task" and command and "ctest" in command and tool_rc == 0:
    next_hint = "ctest green → declare_gate GO (T6)"
elif tool_rc != 0:
    next_hint = f"Last tool failed rc={tool_rc}; read last_tool_output.txt and retry with fixed cwd/path. {rationale}"

ws = f"""# Workstate
- Updated: {iso}
- Campaign: {campaign}
- Iter: {new_iter} / {max_it}
- ROLE: {next_role}
- Profile_before_tick: {os.environ.get('profile_before','')}
- Profile_now: {os.environ.get('profile_now','')}
- HOLD_PROFILE: {hold_v}
- Last_tool: {tool}
- Last_result: {last_result_snip or notes}
- Last_result_row: results/lab.tsv
- Next_action: {next_hint}
- Stop_reason: {outcome}

## Handoff (for next tick — chat history is empty)
- Continuity files: TASKBOARD.md, WORKSTATE.md, MEMORY.md, campaigns/{campaign}/plan.md, .state/last_tool_output.txt
- Last_tool_rc: {tool_rc}
- Prefer one action advancing the top TODO/DOING item.
"""
write(ws_path, ws)

with tsv.open("a") as f:
    f.write(f"{iso}\t{campaign}\t{new_iter}\t{task_id}\t{tool}\t{metric}\t{value}\t{unit}\t{notes}\t{outcome}\n")

st = read(root / ".state" / "tick.env")
st = re.sub(r"^ITER=.*$", f"ITER={new_iter}", st, flags=re.M)
if re.search(r"^STARTED_AT=\s*$", st, re.M):
    st = re.sub(r"^STARTED_AT=.*$", f"STARTED_AT={iso}", st, flags=re.M)
if re.search(r"^WALL_STARTED_EPOCH=\s*$", st, re.M):
    st = re.sub(r"^WALL_STARTED_EPOCH=.*$", f"WALL_STARTED_EPOCH={int(time.time())}", st, flags=re.M)
if outcome:
    st = re.sub(r"^OUTCOME=.*$", f"OUTCOME={outcome}", st, flags=re.M)
# ensure CAMPAIGN_ID persisted
if re.search(r"^CAMPAIGN_ID=", st, re.M):
    st = re.sub(r"^CAMPAIGN_ID=.*$", f"CAMPAIGN_ID={campaign}", st, flags=re.M)
else:
    st += f"\nCAMPAIGN_ID={campaign}\n"
write(root / ".state" / "tick.env", st)

Path("/tmp/qwen-lab-last-outcome").write_text(outcome)
Path("/tmp/qwen-lab-last-rc").write_text(str(tool_rc))
print(json.dumps({"iter": new_iter, "action": act, "task_id": task_id, "outcome": outcome, "tool_rc": tool_rc, "role": next_role}))
PY

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
exit 0
