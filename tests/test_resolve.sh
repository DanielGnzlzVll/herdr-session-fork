#!/usr/bin/env bash
set -uo pipefail
. "$(dirname "$0")/lib.sh"

RESOLVE="$REPO_ROOT/scripts/resolve.sh"

pane_json() {
  cat <<JSON
{"result":{"type":"pane_info","pane":{
  "pane_id":"w1:p1",
  "cwd":"${1:-/home/d/git/repo}",
  "terminal_title_stripped":"${2:-Fixing the parser}",
  "agent_session":{"agent":"claude","kind":"id","value":"abc-123","source":"herdr:claude"}
}}}
JSON
}

# --- happy path -------------------------------------------------------------
stub_setup
stub_reply "pane get" "$(pane_json)"
export HERDR_PLUGIN_CONTEXT_JSON='{"focused_pane_id":"w1:p1"}'
out=$("$RESOLVE"); rc=$?
assert_eq "$rc" "0" "resolves a claude pane"
assert_eq "$out" "$(printf 'w1:p1\tclaude\tabc-123\t/home/d/git/repo\tFixing the parser')" "tab-separated fields"
assert_contains "$(stub_calls)" "<pane><get><w1:p1>" "asks herdr about the focused pane"
stub_teardown

# --- Review Focus 1: spaces in cwd and title --------------------------------
stub_setup
stub_reply "pane get" "$(pane_json "/home/d/my repo" "A title with spaces")"
export HERDR_PLUGIN_CONTEXT_JSON='{"focused_pane_id":"w1:p1"}'
out=$("$RESOLVE")
IFS=$'\t' read -r _ _ _ cwd title <<<"$out"
assert_eq "$cwd" "/home/d/my repo" "a cwd with spaces survives intact"
assert_eq "$title" "A title with spaces" "a title with spaces survives intact"
stub_teardown

# --- Review Focus 3: missing / malformed context ----------------------------
stub_setup
unset HERDR_PLUGIN_CONTEXT_JSON
err=$("$RESOLVE" 2>&1 >/dev/null); rc=$?
assert_eq "$rc" "1" "unset context fails"
assert_contains "$err" "no focused pane" "unset context is explained"
assert_not_contains "$err" "parse error" "jq never leaks a parse error"
stub_teardown

stub_setup
export HERDR_PLUGIN_CONTEXT_JSON='not json at all'
err=$("$RESOLVE" 2>&1 >/dev/null); rc=$?
assert_eq "$rc" "1" "malformed context fails"
assert_contains "$err" "no focused pane" "malformed context is explained"
assert_not_contains "$err" "parse error" "jq never leaks a parse error on bad JSON"
stub_teardown

# --- Review Focus 2: exit 0 with an error body ------------------------------
stub_setup
stub_reply "pane get" '{"error":{"message":"pane not found"}}'
export HERDR_PLUGIN_CONTEXT_JSON='{"focused_pane_id":"w9:p9"}'
err=$("$RESOLVE" 2>&1 >/dev/null); rc=$?
assert_eq "$rc" "1" "an error body fails even when herdr exits 0"
assert_contains "$err" "pane not found" "herdr's message is surfaced"
stub_teardown

# --- Review Focus 4: kind=id with an empty value ----------------------------
stub_setup
stub_reply "pane get" '{"result":{"pane":{"pane_id":"w1:p1","cwd":"/tmp","terminal_title_stripped":"t","agent_session":{"agent":"claude","kind":"id","value":""}}}}'
export HERDR_PLUGIN_CONTEXT_JSON='{"focused_pane_id":"w1:p1"}'
err=$("$RESOLVE" 2>&1 >/dev/null); rc=$?
assert_eq "$rc" "1" "an empty session id is rejected"
assert_contains "$err" "empty session id" "the empty id is named"
stub_teardown

# --- no agent ---------------------------------------------------------------
stub_setup
stub_reply "pane get" '{"result":{"pane":{"pane_id":"w1:p1","cwd":"/tmp","terminal_title_stripped":"bash"}}}'
export HERDR_PLUGIN_CONTEXT_JSON='{"focused_pane_id":"w1:p1"}'
err=$("$RESOLVE" 2>&1 >/dev/null); rc=$?
assert_eq "$rc" "1" "a pane with no agent fails"
assert_contains "$err" "has no agent" "the empty pane is explained"
stub_teardown

# --- kind empty: the integration is missing or predates the session ---------
stub_setup
stub_reply "pane get" '{"result":{"pane":{"pane_id":"w1:p1","cwd":"/tmp","terminal_title_stripped":"t","agent_session":{"agent":"claude","kind":"","value":""}}}}'
export HERDR_PLUGIN_CONTEXT_JSON='{"focused_pane_id":"w1:p1"}'
err=$("$RESOLVE" 2>&1 >/dev/null); rc=$?
assert_eq "$rc" "1" "a pane with no reported id fails"
assert_contains "$err" "herdr integration install claude" "the fix is spelled out"
stub_teardown

# --- kind present but not an id ---------------------------------------------
stub_setup
stub_reply "pane get" '{"result":{"pane":{"pane_id":"w1:p1","cwd":"/tmp","terminal_title_stripped":"t","agent_session":{"agent":"claude","kind":"path","value":"/x"}}}}'
export HERDR_PLUGIN_CONTEXT_JSON='{"focused_pane_id":"w1:p1"}'
err=$("$RESOLVE" 2>&1 >/dev/null); rc=$?
assert_eq "$rc" "1" "a non-id kind fails"
assert_contains "$err" "expects an id" "the wrong kind is explained"
stub_teardown

# --- herdr itself fails -----------------------------------------------------
stub_setup
stub_exit "pane get" 3
stub_reply "pane get" "boom"
export HERDR_PLUGIN_CONTEXT_JSON='{"focused_pane_id":"w1:p1"}'
err=$("$RESOLVE" 2>&1 >/dev/null); rc=$?
assert_eq "$rc" "1" "a non-zero herdr exit fails"
assert_contains "$err" "pane get failed" "the herdr failure is named"
stub_teardown

finish
