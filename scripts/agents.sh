#!/usr/bin/env bash
# Maps an agent kind to the CLI arguments that FORK its session.
#
# A row belongs here only once its fork flag has been verified on real
# hardware. A plain resume reattaches the original session instead of
# branching from it: both processes would then append to one history and the
# fork would cannibalise its source. That failure is silent and destroys the
# user's work, so documentation alone is never enough to add a row.
#
# Verified:
#   claude  --resume <id> --fork-session   (Claude Code 2.1.280; forks a live,
#           currently-generating session into a new id, source left untouched)
#
# Candidate, NOT verified:
#   codex   `codex resume <id>` may branch, because Codex writes a new rollout
#           file per run. Untested. Do not add without testing.

fork_args() {
  case "$1" in
    claude) printf '%s\n' "--resume" "$2" "--fork-session" ;;
    *) return 1 ;;
  esac
}
