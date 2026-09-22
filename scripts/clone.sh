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
name=""
for n in $(seq 1 99); do
  candidate="fork-$n"
  if probe=$("$herdr" agent get "$candidate" 2>/dev/null); then
    if [ -z "$(printf '%s' "$probe" | jq -r '.error // empty' 2>/dev/null || true)" ]; then
      continue   # the name is taken
    fi
  fi
  name="$candidate"
  break
done
[ -n "$name" ] || { echo "session-fork: fork-1 through fork-99 are all live" >&2; exit 1; }

split=$("$herdr" pane split --pane "$src_pane" --direction "$dir" --cwd "$cwd" --no-focus 2>&1) || {
  echo "session-fork: pane split failed: $split" >&2; exit 1; }
err=$(printf '%s' "$split" | jq -r '.error.message // empty' 2>/dev/null || true)
[ -z "$err" ] || { echo "session-fork: pane split failed: $err" >&2; exit 1; }

new_pane=$(printf '%s' "$split" | jq -r '.result.pane.pane_id // empty' 2>/dev/null || true)
[ -n "$new_pane" ] || { echo "session-fork: herdr returned no pane id for the new pane" >&2; exit 1; }

if ! start=$("$herdr" agent start "$name" --kind "$agent" --pane "$new_pane" -- "${fork_argv[@]}" 2>&1); then
  # agent_not_ready means the fork IS running, just sitting on a dialog. The
  # pane is real and the name is valid, so closing it would throw away a live
  # session.
  if printf '%s' "$start" | grep -q 'agent_not_ready'; then
    echo "session-fork: the fork is live in $new_pane but is waiting on a prompt, so focus stayed here."
    exit 0
  fi
  "$herdr" pane close "$new_pane" >/dev/null 2>&1 || true
  echo "session-fork: could not start $agent in the new pane, so it was closed: $start" >&2
  exit 1
fi

# Cosmetic and navigational; neither is worth discarding a live fork over.
if [ -n "$title" ]; then
  "$herdr" pane rename "$new_pane" "⑂ $title" >/dev/null 2>&1 \
    || echo "session-fork: the fork is live, but its pane could not be renamed." >&2
fi
"$herdr" agent focus "$name" >/dev/null 2>&1 \
  || echo "session-fork: the fork is live in $new_pane, but focus did not move to it." >&2
