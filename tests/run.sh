#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")" || exit 1
status=0
for t in test_*.sh; do
  printf '\n== %s\n' "$t"
  bash "$t" || status=1
done
if command -v shellcheck >/dev/null 2>&1; then
  printf '\n== shellcheck\n'
  shellcheck -x --source-path=SCRIPTDIR ../scripts/*.sh lib.sh run.sh test_*.sh || status=1
else
  printf '\n== shellcheck (not installed, skipped)\n'
fi
exit $status
