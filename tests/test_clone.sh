#!/usr/bin/env bash
set -uo pipefail
. "$(dirname "$0")/lib.sh"

CLONE="$REPO_ROOT/scripts/clone.sh"

setup_happy() {
  stub_setup
  stub_reply "pane get" '{"result":{"pane":{"pane_id":"w1:p1","cwd":"'"${1:-/home/d/repo}"'","terminal_title_stripped":"'"${2:-Parser work}"'","agent_session":{"agent":"'"${3:-claude}"'","kind":"id","value":"abc-123"}}}}'
  stub_reply "pane split" '{"result":{"pane":{"pane_id":"w1:p7"}}}'
  stub_exit  "agent get" 1          # every probed name is free
  export HERDR_PLUGIN_CONTEXT_JSON='{"focused_pane_id":"w1:p1"}'
}

# --- direction: right -------------------------------------------------------
setup_happy
out=$("$CLONE" right 2>&1); rc=$?
calls=$(stub_calls)
assert_eq "$rc" "0" "a right split succeeds"
assert_contains "$calls" "pane split --pane w1:p1 --direction right --cwd /home/d/repo --no-focus" "splits right, no focus, source cwd"
assert_contains "$calls" "agent start fork-1 --kind claude --pane w1:p7 -- --resume abc-123 --fork-session" "starts a forked claude in the new pane"
assert_contains "$calls" "agent focus fork-1" "focus moves to the fork"
stub_teardown

# --- direction: down --------------------------------------------------------
setup_happy
"$CLONE" down >/dev/null 2>&1
assert_contains "$(stub_calls)" "--direction down" "a down split passes down"
stub_teardown

# --- bad direction ----------------------------------------------------------
setup_happy
err=$("$CLONE" sideways 2>&1 >/dev/null); rc=$?
assert_eq "$rc" "2" "an invalid direction exits 2"
assert_not_contains "$(stub_calls)" "pane split" "an invalid direction splits nothing"
stub_teardown

setup_happy
"$CLONE" >/dev/null 2>&1; rc=$?
assert_eq "$rc" "2" "a missing direction exits 2"
stub_teardown

# --- Review Focus 1: a cwd with spaces --------------------------------------
setup_happy "/home/d/my repo" "Some title"
"$CLONE" right >/dev/null 2>&1
assert_contains "$(stub_calls)" "--cwd /home/d/my repo --no-focus" "a cwd with spaces reaches herdr as one argument"
stub_teardown

# --- Review Focus 2: split exits 0 with an error body -----------------------
setup_happy
stub_reply "pane split" '{"error":{"message":"cannot split further"}}'
err=$("$CLONE" right 2>&1 >/dev/null); rc=$?
assert_eq "$rc" "1" "an error body from split fails"
assert_contains "$err" "cannot split further" "herdr's split error is surfaced"
assert_not_contains "$(stub_calls)" "agent start" "no agent is started after a failed split"
stub_teardown

# --- split returns no pane id -----------------------------------------------
setup_happy
stub_reply "pane split" '{"result":{}}'
err=$("$CLONE" right 2>&1 >/dev/null); rc=$?
assert_eq "$rc" "1" "a split with no pane id fails"
assert_not_contains "$(stub_calls)" "agent start" "no agent is started without a pane id"
stub_teardown

# --- unsupported agent ------------------------------------------------------
setup_happy "/home/d/repo" "t" "gemini"
err=$("$CLONE" right 2>&1 >/dev/null); rc=$?
assert_eq "$rc" "1" "an unsupported agent is refused"
assert_contains "$err" "doesn't know how to fork 'gemini' yet" "the refusal names the agent"
assert_not_contains "$(stub_calls)" "pane split" "an unsupported agent splits nothing"
stub_teardown

# --- rollback when the agent cannot start -----------------------------------
setup_happy
stub_exit "agent start" 1
stub_reply "agent start" "claude: command not found"
err=$("$CLONE" right 2>&1 >/dev/null); rc=$?
assert_eq "$rc" "1" "a failed agent start fails"
assert_contains "$(stub_calls)" "pane close w1:p7" "the orphan pane is closed"
stub_teardown

# --- agent_not_ready is success, not an orphan ------------------------------
setup_happy
stub_exit "agent start" 1
stub_reply "agent start" '{"error":{"code":"agent_not_ready"}}'
out=$("$CLONE" right 2>&1); rc=$?
assert_eq "$rc" "0" "agent_not_ready is a live fork, not a failure"
assert_not_contains "$(stub_calls)" "pane close" "agent_not_ready never closes the pane"
assert_contains "$out" "waiting" "the user is told the fork needs attention"
stub_teardown

# --- Review Focus 5: name allocation skips live names -----------------------
setup_happy
stub_exit "agent get" 0           # every probed name is TAKEN
stub_reply "agent get" '{"result":{"agent":{"name":"fork-1"}}}'
"$CLONE" right >/dev/null 2>&1; rc=$?
assert_eq "$rc" "1" "exhausting every name fails rather than reusing one"
assert_not_contains "$(stub_calls)" "agent start" "no agent is started without a free name"
stub_teardown

# A taken fork-1 (error body, exit 0) must roll over to fork-2.
stub_setup
stub_reply "pane get" '{"result":{"pane":{"pane_id":"w1:p1","cwd":"/r","terminal_title_stripped":"t","agent_session":{"agent":"claude","kind":"id","value":"abc-123"}}}}'
stub_reply "pane split" '{"result":{"pane":{"pane_id":"w1:p7"}}}'
cat >"$STUB_DIR/bin/herdr" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$STUB_LOG"
if [ "${1:-} ${2:-}" = "agent get" ]; then
  if [ "${3:-}" = "fork-1" ]; then echo '{"result":{"agent":{"name":"fork-1"}}}'; exit 0; fi
  echo '{"error":{"message":"no such agent"}}'; exit 0
fi
key="${1:-} ${2:-}"; f="$STUB_DIR/reply_${key// /_}"
[ -f "$f" ] && cat "$f"
exit 0
STUB
chmod +x "$STUB_DIR/bin/herdr"
export HERDR_PLUGIN_CONTEXT_JSON='{"focused_pane_id":"w1:p1"}'
"$CLONE" right >/dev/null 2>&1
assert_contains "$(stub_calls)" "agent start fork-2 " "a taken fork-1 rolls over to fork-2"
stub_teardown

# --- rename and focus are best effort ---------------------------------------
setup_happy
stub_exit "pane rename" 1
stub_exit "agent focus" 1
out=$("$CLONE" right 2>&1); rc=$?
assert_eq "$rc" "0" "a failed rename or focus still leaves a usable fork"
assert_contains "$out" "focus did not move" "the user is told focus stayed put"
stub_teardown

# --- the fork's pane is renamed ---------------------------------------------
setup_happy
"$CLONE" right >/dev/null 2>&1
assert_contains "$(stub_calls)" "pane rename w1:p7 ⑂ Parser work" "the fork pane is labelled"
stub_teardown

finish
