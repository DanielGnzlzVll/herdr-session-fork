#!/usr/bin/env bash
set -uo pipefail
. "$(dirname "$0")/lib.sh"
. "$REPO_ROOT/scripts/agents.sh"

out=$(fork_args claude 1234-abcd); rc=$?
assert_eq "$rc" "0" "claude is supported"
assert_eq "$out" "$(printf -- '--resume\n1234-abcd\n--fork-session')" "claude fork args, one per line"

out=$(fork_args gemini 1234-abcd); rc=$?
assert_eq "$rc" "1" "gemini is refused"
assert_eq "$out" "" "a refused agent prints nothing"

out=$(fork_args codex 1234-abcd); rc=$?
assert_eq "$rc" "1" "codex stays out until its fork flag is verified"

finish
