#!/usr/bin/env bash
# Print "<pane_id>\t<agent>\t<session_id>\t<cwd>\t<title>" for the pane this
# plugin was invoked from, or exit 1 with the reason on stderr.
#
# The pane id comes from `focused_pane_id` in HERDR_PLUGIN_CONTEXT_JSON, never
# from HERDR_PANE_ID: in a pane command HERDR_PANE_ID is the plugin's own new
# pane, which has no agent. The context names the pane that was focused when
# the plugin fired, and it is the same field for an action and a pane command.
set -euo pipefail

herdr="${HERDR_BIN_PATH:-herdr}"
ctx="${HERDR_PLUGIN_CONTEXT_JSON:-}"

command -v jq >/dev/null 2>&1 || {
  echo "jq is not on PATH, and the plugin reads herdr's JSON with it" >&2; exit 1; }

# A malformed context is treated as an absent one: the user gets the same
# actionable line either way, and jq's parse error never reaches them.
pane_id=$(printf '%s' "$ctx" | jq -r '.focused_pane_id // empty' 2>/dev/null || true)
[ -n "$pane_id" ] || { echo "no focused pane in the invocation context" >&2; exit 1; }

resp=$("$herdr" pane get "$pane_id" 2>&1) || {
  echo "herdr pane get failed: $resp" >&2; exit 1; }

err=$(printf '%s' "$resp" | jq -r '.error.message // empty' 2>/dev/null || true)
[ -z "$err" ] || { echo "herdr: $err" >&2; exit 1; }

# `pane.get` answers {"result": {"pane": {...}}}: the record is under
# .result.pane, not .result itself.
pane=$(printf '%s' "$resp" | jq '.result.pane // .result' 2>/dev/null || true)
agent=$(printf '%s' "$pane" | jq -r '.agent_session.agent // .agent // empty')
kind=$(printf  '%s' "$pane" | jq -r '.agent_session.kind  // empty')
value=$(printf '%s' "$pane" | jq -r '.agent_session.value // empty')
cwd=$(printf   '%s' "$pane" | jq -r '.cwd // empty')
title=$(printf '%s' "$pane" | jq -r '.terminal_title_stripped // .terminal_title // empty')

[ -n "$agent" ] || { echo "pane $pane_id has no agent: focus an agent pane" >&2; exit 1; }

case "$kind" in
  id) ;;
  "") cat >&2 <<MSG
herdr has no session id for this $agent pane.

  The id comes from the agent's SessionStart hook, which fires only when a
  session begins. Install the integration if it is missing, then start the
  agent in that pane again. A session already running when the integration
  was installed never reports one.

    herdr integration install $agent    (herdr integration status lists them)
MSG
      exit 1 ;;
  *)  echo "herdr reports a $kind for this $agent pane, and the plugin expects an id" >&2; exit 1 ;;
esac

# A reported id that is blank would become `--resume --fork-session`, which
# resumes something other than what the user is looking at.
[ -n "$value" ] || { echo "herdr reports an empty session id for pane $pane_id" >&2; exit 1; }
[ -n "$cwd" ]   || { echo "herdr reports no cwd for pane $pane_id" >&2; exit 1; }

printf '%s\t%s\t%s\t%s\t%s\n' "$pane_id" "$agent" "$value" "$cwd" "$title"
