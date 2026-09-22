#!/usr/bin/env bash
# Fork the focused agent session into a sibling pane.
# Usage: clone.sh <right|down>
set -euo pipefail

dir="${1:-}"
case "$dir" in
  right|down) ;;
  *) echo "session-fork: direction must be 'right' or 'down', got '${dir:-<none>}'" >&2; exit 2 ;;
esac

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=agents.sh
. "$here/agents.sh"

herdr="${HERDR_BIN_PATH:-herdr}"

# resolve.sh writes its own diagnosis to stderr; pass it straight through.
resolved=$("$here/resolve.sh") || exit 1
IFS=$'\t' read -r src_pane agent session cwd title <<<"$resolved"

if ! fork_out=$(fork_args "$agent" "$session"); then
  echo "session-fork doesn't know how to fork '$agent' yet." >&2
  exit 1
fi
mapfile -t fork_argv <<<"$fork_out"

# herdr reports a `name` only for agents it started, so live names cannot be
# listed. Probe instead: a non-zero exit or an .error body means free.
next_free_name() {
  local n="$1" candidate probe
  while [ "$n" -le 99 ]; do
    candidate="fork-$n"
    if probe=$("$herdr" agent get "$candidate" 2>/dev/null); then
      if [ -z "$(printf '%s' "$probe" | jq -r '.error // empty' 2>/dev/null || true)" ]; then
        n=$((n + 1))
        continue   # the name is taken
      fi
    fi
    printf '%s\n' "$candidate"
    return 0
  done
  return 1
}

name=$(next_free_name 1) \
  || { echo "session-fork: fork-1 through fork-99 are all live" >&2; exit 1; }

split=$("$herdr" pane split --pane "$src_pane" --direction "$dir" --cwd "$cwd" --no-focus 2>&1) || {
  echo "session-fork: pane split failed: $split" >&2; exit 1; }
err=$(printf '%s' "$split" | jq -r '.error.message // empty' 2>/dev/null || true)
[ -z "$err" ] || { echo "session-fork: pane split failed: $err" >&2; exit 1; }

new_pane=$(printf '%s' "$split" | jq -r '.result.pane.pane_id // empty' 2>/dev/null || true)
[ -n "$new_pane" ] || { echo "session-fork: herdr returned no pane id for the new pane" >&2; exit 1; }

# herdr can report a failure either by exiting non-zero or by answering an
# error body on exit 0, so the exit code alone is never proof that the agent
# started. Trusting it would leave a pane holding a bare shell, renamed and
# focused as though it were a fork.
attempt=1
while :; do
  start_rc=0
  start=$("$herdr" agent start "$name" --kind "$agent" --pane "$new_pane" -- "${fork_argv[@]}" 2>&1) \
    || start_rc=$?
  err_code=$(printf '%s' "$start" | jq -r '.error.code // empty' 2>/dev/null || true)
  err_msg=$(printf  '%s' "$start" | jq -r '.error.message // empty' 2>/dev/null || true)

  # agent_not_ready means the fork IS running, just sitting on a dialog. The
  # pane is real and the name is valid, so closing it would throw away a live
  # session. Matched on the error code, never on the text: a genuine failure
  # that merely mentions the token must not be read as success.
  if [ "$err_code" = "agent_not_ready" ]; then
    echo "session-fork: the fork is live in $new_pane but is waiting on a prompt, so focus stayed here."
    exit 0
  fi

  if [ "$start_rc" -eq 0 ] && [ -z "$err_code" ] && [ -z "$err_msg" ]; then
    break
  fi

  # A name claimed between the probe and the start is a lost race, not a
  # failure: two forks fired in quick succession both probe before either
  # registers. Take the next free name and reuse the pane we already made.
  if [ "$attempt" -eq 1 ]; then
    case "$err_code $err_msg" in
      *name_in_use*|*"already in use"*|*"already exists"*)
        attempt=2
        if retry_name=$(next_free_name "$(( ${name#fork-} + 1 ))"); then
          name="$retry_name"
          continue
        fi
        ;;
    esac
  fi

  "$herdr" pane close "$new_pane" >/dev/null 2>&1 || true
  echo "session-fork: could not start $agent in the new pane, so it was closed: ${err_msg:-$start}" >&2
  exit 1
done

# Cosmetic and navigational; neither is worth discarding a live fork over.
if [ -n "$title" ]; then
  "$herdr" pane rename "$new_pane" "⑂ $title" >/dev/null 2>&1 \
    || echo "session-fork: the fork is live, but its pane could not be renamed." >&2
fi
"$herdr" agent focus "$name" >/dev/null 2>&1 \
  || echo "session-fork: the fork is live in $new_pane, but focus did not move to it." >&2
