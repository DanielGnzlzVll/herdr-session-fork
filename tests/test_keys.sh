#!/usr/bin/env bash
set -uo pipefail
. "$(dirname "$0")/lib.sh"

KEYS="$REPO_ROOT/scripts/keys.sh"

new_cfg() {
  WORK=$(mktemp -d "${TMPDIR:-/tmp}/session-fork-cfg.XXXXXX")
  export SESSION_FORK_CONFIG="$WORK/config.toml"
  printf '%s\n' "$1" >"$SESSION_FORK_CONFIG"
}
drop_cfg() { rm -rf "$WORK"; }

# --- setup writes the block and backs the file up ---------------------------
new_cfg 'onboarding = false'
"$KEYS" setup >/dev/null; rc=$?
cfg=$(cat "$SESSION_FORK_CONFIG")
assert_eq "$rc" "0" "setup succeeds on a clean config"
assert_contains "$cfg" 'key = "prefix+shift+v"' "the vertical binding is written"
assert_contains "$cfg" 'key = "prefix+shift+minus"' "the horizontal binding is written"
assert_contains "$cfg" 'command = "danielgnzlzvll.session-fork.clone-vertical"' "the vertical action is targeted"
assert_contains "$cfg" 'onboarding = false' "existing config is preserved"
assert_eq "$(cat "$SESSION_FORK_CONFIG.session-fork-backup")" "onboarding = false" "the original is backed up"
drop_cfg

# --- setup is idempotent ----------------------------------------------------
new_cfg 'onboarding = false'
"$KEYS" setup >/dev/null
"$KEYS" setup >/dev/null
count=$(grep -c 'prefix+shift+v' "$SESSION_FORK_CONFIG")
assert_eq "$count" "1" "running setup twice leaves one binding"
drop_cfg

# --- setup refuses to fight an existing ACTIVE binding ----------------------
new_cfg 'onboarding = false
[[keys.command]]
key = "prefix+shift+v"
type = "shell"
command = "something else"'
err=$("$KEYS" setup 2>&1 >/dev/null); rc=$?
assert_eq "$rc" "1" "an existing active binding blocks setup"
assert_contains "$err" "prefix+shift+v" "the conflicting key is named"
assert_not_contains "$(cat "$SESSION_FORK_CONFIG")" "session-fork" "nothing was written on refusal"
drop_cfg

# --- a COMMENTED binding is not a conflict (zoetrope ships one) -------------
new_cfg 'onboarding = false
# [[keys.command]]
# key = "prefix+shift+v"
# type = "plugin_action"
# command = "furkankly.zoetrope.open-split"'
"$KEYS" setup >/dev/null; rc=$?
assert_eq "$rc" "0" "a commented-out binding does not block setup"
drop_cfg

# --- remove deletes exactly the block ---------------------------------------
new_cfg 'onboarding = false'
"$KEYS" setup >/dev/null
"$KEYS" remove >/dev/null; rc=$?
cfg=$(cat "$SESSION_FORK_CONFIG")
assert_eq "$rc" "0" "remove succeeds"
assert_not_contains "$cfg" "session-fork" "the block is gone"
assert_contains "$cfg" "onboarding = false" "the rest of the config survives"
drop_cfg

# --- remove on a config without the block is a no-op ------------------------
new_cfg 'onboarding = false'
"$KEYS" remove >/dev/null; rc=$?
assert_eq "$rc" "0" "remove with no block still succeeds"
assert_eq "$(cat "$SESSION_FORK_CONFIG")" "onboarding = false" "remove changed nothing"
drop_cfg

# --- a missing config file ---------------------------------------------------
WORK=$(mktemp -d); export SESSION_FORK_CONFIG="$WORK/config.toml"
"$KEYS" setup >/dev/null; rc=$?
assert_eq "$rc" "0" "setup creates a config that does not exist yet"
assert_contains "$(cat "$SESSION_FORK_CONFIG")" "prefix+shift+v" "the binding lands in the new file"
rm -rf "$WORK"

finish
