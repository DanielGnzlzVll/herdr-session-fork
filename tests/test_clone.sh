#!/usr/bin/env bash
set -uo pipefail
. "$(dirname "$0")/lib.sh"

CLONE="$REPO_ROOT/scripts/clone.sh"

# The stub logs argv as ARGC=<n> <arg><arg>..., so an assertion can tell
# `--cwd </home/d/my repo>` from `--cwd </home/d/my> <repo>`. Joining argv with
# spaces would make a quoting regression invisible.

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
assert_contains "$calls" "<pane><split><--pane><w1:p1><--direction><right><--cwd></home/d/repo><--no-focus>" "splits right, no focus, source cwd"
assert_contains "$calls" "<agent><start><fork-1><--kind><claude><--pane><w1:p7><--><--resume><abc-123><--fork-session>" "starts a forked claude in the new pane"
assert_contains "$calls" "<agent><focus><fork-1>" "focus moves to the fork"
stub_teardown

# --- direction: down --------------------------------------------------------
setup_happy
"$CLONE" down >/dev/null 2>&1
assert_contains "$(stub_calls)" "<--direction><down>" "a down split passes down"
stub_teardown

# --- bad direction ----------------------------------------------------------
setup_happy
"$CLONE" sideways >/dev/null 2>&1; rc=$?
assert_eq "$rc" "2" "an invalid direction exits 2"
assert_not_contains "$(stub_calls)" "<pane><split>" "an invalid direction splits nothing"
stub_teardown

setup_happy
"$CLONE" >/dev/null 2>&1; rc=$?
assert_eq "$rc" "2" "a missing direction exits 2"
stub_teardown

# --- Review Focus 1: a cwd with spaces --------------------------------------
# The bracketed log is what makes this assertion able to fail: with argv joined
# by spaces, an unquoted $cwd would satisfy it just as well.
setup_happy "/home/d/my repo" "Some title"
"$CLONE" right >/dev/null 2>&1
assert_contains "$(stub_calls)" "<--cwd></home/d/my repo><--no-focus>" "a cwd with spaces reaches herdr as one argument"
stub_teardown

# --- a title with spaces reaches pane rename as one argument ----------------
setup_happy "/home/d/repo" "A title with spaces"
"$CLONE" right >/dev/null 2>&1
assert_contains "$(stub_calls)" "<pane><rename><w1:p7><⑂ A title with spaces>" "a title with spaces is one rename argument"
stub_teardown

# --- Review Focus 2: split exits 0 with an error body -----------------------
setup_happy
stub_reply "pane split" '{"error":{"message":"cannot split further"}}'
err=$("$CLONE" right 2>&1 >/dev/null); rc=$?
assert_eq "$rc" "1" "an error body from split fails"
assert_contains "$err" "cannot split further" "herdr's split error is surfaced"
assert_not_contains "$(stub_calls)" "<agent><start>" "no agent is started after a failed split"
stub_teardown

# --- split returns no pane id -----------------------------------------------
setup_happy
stub_reply "pane split" '{"result":{}}'
"$CLONE" right >/dev/null 2>&1; rc=$?
assert_eq "$rc" "1" "a split with no pane id fails"
assert_not_contains "$(stub_calls)" "<agent><start>" "no agent is started without a pane id"
stub_teardown

# --- unsupported agent ------------------------------------------------------
setup_happy "/home/d/repo" "t" "gemini"
err=$("$CLONE" right 2>&1 >/dev/null); rc=$?
assert_eq "$rc" "1" "an unsupported agent is refused"
assert_contains "$err" "doesn't know how to fork 'gemini' yet" "the refusal names the agent"
assert_not_contains "$(stub_calls)" "<pane><split>" "an unsupported agent splits nothing"
stub_teardown

# --- rollback when the agent cannot start (non-zero exit) -------------------
setup_happy
stub_exit "agent start" 1
stub_reply "agent start" "claude: command not found"
"$CLONE" right >/dev/null 2>&1; rc=$?
assert_eq "$rc" "1" "a failed agent start fails"
assert_contains "$(stub_calls)" "<pane><close><w1:p7>" "the orphan pane is closed"
stub_teardown

# --- C1: agent start exits 0 but returns an error body ----------------------
# Exit code alone is not proof of a started agent. Trusting it leaves a pane
# holding a bare shell, renamed and focused as though it were a fork.
setup_happy
stub_exit "agent start" 0
stub_reply "agent start" '{"error":{"code":"start_failed","message":"claude exited during startup"}}'
err=$("$CLONE" right 2>&1 >/dev/null); rc=$?
calls=$(stub_calls)
assert_eq "$rc" "1" "an error body from agent start fails even on exit 0"
assert_contains "$err" "claude exited during startup" "herdr's start error is surfaced"
assert_contains "$calls" "<pane><close><w1:p7>" "the orphan pane is closed on an exit-0 error"
assert_not_contains "$calls" "<pane><rename>" "a pane holding no agent is never renamed"
assert_not_contains "$calls" "<agent><focus>" "a fork that never started is never focused"
stub_teardown

# --- agent_not_ready is success, not an orphan (non-zero exit) --------------
setup_happy
stub_exit "agent start" 1
stub_reply "agent start" '{"error":{"code":"agent_not_ready"}}'
out=$("$CLONE" right 2>&1); rc=$?
assert_eq "$rc" "0" "agent_not_ready is a live fork, not a failure"
assert_not_contains "$(stub_calls)" "<pane><close>" "agent_not_ready never closes the pane"
assert_contains "$out" "waiting" "the user is told the fork needs attention"
stub_teardown

# --- agent_not_ready delivered with exit 0 ----------------------------------
setup_happy
stub_exit "agent start" 0
stub_reply "agent start" '{"error":{"code":"agent_not_ready"}}'
out=$("$CLONE" right 2>&1); rc=$?
assert_eq "$rc" "0" "agent_not_ready on exit 0 is still a live fork"
assert_not_contains "$(stub_calls)" "<pane><close>" "agent_not_ready on exit 0 never closes the pane"
stub_teardown

# --- I4: a real failure that merely mentions the token is NOT not-ready -----
setup_happy
stub_exit "agent start" 1
stub_reply "agent start" "error: unknown state; expected one of: running, agent_not_ready, exited"
out=$("$CLONE" right 2>&1); rc=$?
assert_eq "$rc" "1" "an error merely naming agent_not_ready is still a failure"
assert_contains "$(stub_calls)" "<pane><close><w1:p7>" "that failure still closes the orphan pane"
assert_not_contains "$out" "waiting on a prompt" "the user is not told the fork is live"
stub_teardown

# --- Review Focus 5: name allocation skips live names -----------------------
setup_happy
stub_exit "agent get" 0           # every probed name is TAKEN
stub_reply "agent get" '{"result":{"agent":{"name":"fork-1"}}}'
"$CLONE" right >/dev/null 2>&1; rc=$?
assert_eq "$rc" "1" "exhausting every name fails rather than reusing one"
assert_not_contains "$(stub_calls)" "<agent><start>" "no agent is started without a free name"
stub_teardown

# A taken fork-1 (error body, exit 0) must roll over to fork-2.
stub_setup
stub_reply "pane split" '{"result":{"pane":{"pane_id":"w1:p7"}}}'
cat >"$STUB_DIR/bin/herdr" <<'STUB'
#!/usr/bin/env bash
{ printf 'ARGC=%d ' "$#"; printf '<%s>' "$@"; printf '\n'; } >>"$STUB_LOG"
if [ "${1:-} ${2:-}" = "pane get" ]; then
  echo '{"result":{"pane":{"pane_id":"w1:p1","cwd":"/r","terminal_title_stripped":"t","agent_session":{"agent":"claude","kind":"id","value":"abc-123"}}}}'
  exit 0
fi
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
assert_contains "$(stub_calls)" "<agent><start><fork-2>" "a taken fork-1 rolls over to fork-2"
stub_teardown

# --- I6: a name taken between the probe and the start is retried ------------
# Two forks fired in quick succession both probe before either registers, so
# both pick fork-1. The loser must take the next name, not give up.
stub_setup
cat >"$STUB_DIR/bin/herdr" <<'STUB'
#!/usr/bin/env bash
{ printf 'ARGC=%d ' "$#"; printf '<%s>' "$@"; printf '\n'; } >>"$STUB_LOG"
case "${1:-} ${2:-}" in
  "pane get")
    echo '{"result":{"pane":{"pane_id":"w1:p1","cwd":"/r","terminal_title_stripped":"t","agent_session":{"agent":"claude","kind":"id","value":"abc-123"}}}}' ;;
  "pane split") echo '{"result":{"pane":{"pane_id":"w1:p7"}}}' ;;
  "agent get")  echo '{"error":{"message":"no such agent"}}' ;;   # every name probes free
  "agent start")
    # fork-1 was claimed by the other fork in the gap; fork-2 is fine.
    if [ "${3:-}" = "fork-1" ]; then
      echo '{"error":{"code":"name_in_use","message":"agent name '"'"'fork-1'"'"' is already in use"}}'
      exit 1
    fi ;;
esac
exit 0
STUB
chmod +x "$STUB_DIR/bin/herdr"
export HERDR_PLUGIN_CONTEXT_JSON='{"focused_pane_id":"w1:p1"}'
out=$("$CLONE" right 2>&1); rc=$?
calls=$(stub_calls)
assert_eq "$rc" "0" "losing the name race still produces a fork"
assert_contains "$calls" "<agent><start><fork-1>" "the first attempt used fork-1"
assert_contains "$calls" "<agent><start><fork-2>" "the retry used the next free name"
assert_not_contains "$calls" "<pane><close>" "the pane is reused for the retry, not discarded"
assert_contains "$calls" "<agent><focus><fork-2>" "focus goes to the name that actually started"
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
assert_contains "$(stub_calls)" "<pane><rename><w1:p7><⑂ Parser work>" "the fork pane is labelled"
stub_teardown

finish
