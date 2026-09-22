#!/usr/bin/env bash
# Test harness: a fake `herdr` on PATH that records argv and replies from
# canned files. Every test sources this.

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
export REPO_ROOT

FAILURES=0

stub_setup() {
  STUB_DIR=$(mktemp -d "${TMPDIR:-/tmp}/session-fork-stub.XXXXXX")
  export STUB_DIR
  export STUB_LOG="$STUB_DIR/calls.log"
  : >"$STUB_LOG"
  mkdir -p "$STUB_DIR/bin"

  cat >"$STUB_DIR/bin/herdr" <<'STUB'
#!/usr/bin/env bash
{ printf 'ARGC=%d ' "$#"; printf '<%s>' "$@"; printf '\n'; } >>"$STUB_LOG"
key="${1:-} ${2:-}"
safe=${key// /_}
exit_file="$STUB_DIR/exit_$safe"
reply_file="$STUB_DIR/reply_$safe"
[ -f "$reply_file" ] && cat "$reply_file"
if [ -f "$exit_file" ]; then exit "$(cat "$exit_file")"; fi
exit 0
STUB
  chmod +x "$STUB_DIR/bin/herdr"
  PATH="$STUB_DIR/bin:$PATH"
  export PATH
  unset HERDR_BIN_PATH
}

stub_teardown() { [ -n "${STUB_DIR:-}" ] && rm -rf "$STUB_DIR"; }

stub_reply() { printf '%s' "$2" >"$STUB_DIR/reply_${1// /_}"; }
stub_exit()  { printf '%s' "$2" >"$STUB_DIR/exit_${1// /_}"; }
stub_calls() { cat "$STUB_LOG"; }

assert_eq() {
  if [ "$1" = "$2" ]; then printf '  ok   %s\n' "$3"
  else printf '  FAIL %s\n       want: %s\n       got:  %s\n' "$3" "$2" "$1"; FAILURES=$((FAILURES+1)); fi
}

assert_contains() {
  case "$1" in
    *"$2"*) printf '  ok   %s\n' "$3" ;;
    *) printf '  FAIL %s\n       missing: %s\n       in:      %s\n' "$3" "$2" "$1"; FAILURES=$((FAILURES+1)) ;;
  esac
}

assert_not_contains() {
  case "$1" in
    *"$2"*) printf '  FAIL %s\n       unexpected: %s\n' "$3" "$2"; FAILURES=$((FAILURES+1)) ;;
    *) printf '  ok   %s\n' "$3" ;;
  esac
}

finish() { [ "$FAILURES" -eq 0 ] || exit 1; }
