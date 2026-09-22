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

# --- I1: an unterminated managed block must never eat the rest of the file --
# If the END marker is lost (hand edit, truncation), a naive strip deletes
# everything from BEGIN to EOF -- silently, with no backup to recover from.
new_cfg 'onboarding = false
# >>> danielgnzlzvll.session-fork keys
[[keys.command]]
key = "prefix+shift+v"
type = "plugin_action"
command = "danielgnzlzvll.session-fork.clone-vertical"
[server]
port = 9999
[[keys.command]]
key = "prefix+ctrl+g"
type = "shell"
command = "lazygit"'
err=$("$KEYS" remove 2>&1 >/dev/null); rc=$?
cfg=$(cat "$SESSION_FORK_CONFIG")
assert_eq "$rc" "1" "an unterminated block makes remove refuse"
assert_contains "$err" "marker" "the refusal names the broken marker"
assert_contains "$cfg" "port = 9999" "the user's unrelated config survives"
assert_contains "$cfg" "prefix+ctrl+g" "the user's own keybinding survives"
drop_cfg

new_cfg 'onboarding = false
# >>> danielgnzlzvll.session-fork keys
[server]
port = 9999'
err=$("$KEYS" setup 2>&1 >/dev/null); rc=$?
assert_eq "$rc" "1" "an unterminated block makes setup refuse too"
assert_contains "$(cat "$SESSION_FORK_CONFIG")" "port = 9999" "setup did not eat the tail either"
drop_cfg

# --- I1b: remove takes a backup, like setup does ----------------------------
new_cfg 'onboarding = false'
"$KEYS" setup >/dev/null
"$KEYS" remove >/dev/null
assert_eq "$([ -e "$SESSION_FORK_CONFIG.session-fork-backup" ] && echo yes || echo no)" "yes" "remove leaves a backup behind"
drop_cfg

# --- M5: the backup is the pristine original, not the last write ------------
new_cfg 'onboarding = false'
"$KEYS" setup >/dev/null
"$KEYS" setup >/dev/null
assert_eq "$(cat "$SESSION_FORK_CONFIG.session-fork-backup")" "onboarding = false" "a second setup does not overwrite the pristine backup"
drop_cfg

# --- I2: a single-quoted TOML key is still an active binding ----------------
new_cfg "onboarding = false
[[keys.command]]
key = 'prefix+shift+v'
type = \"shell\"
command = \"something else\""
err=$("$KEYS" setup 2>&1 >/dev/null); rc=$?
assert_eq "$rc" "1" "a single-quoted conflicting binding blocks setup"
assert_eq "$(grep -c 'prefix+shift+v' "$SESSION_FORK_CONFIG")" "1" "no duplicate binding was written"
drop_cfg

# --- I3: writing must not detach a symlinked config -------------------------
WORK=$(mktemp -d "${TMPDIR:-/tmp}/session-fork-link.XXXXXX")
mkdir -p "$WORK/dotfiles"
printf 'onboarding = false\n' >"$WORK/dotfiles/config.toml"
ln -s "$WORK/dotfiles/config.toml" "$WORK/config.toml"
export SESSION_FORK_CONFIG="$WORK/config.toml"
"$KEYS" setup >/dev/null
assert_eq "$([ -L "$WORK/config.toml" ] && echo yes || echo no)" "yes" "the config path is still a symlink"
assert_contains "$(cat "$WORK/dotfiles/config.toml")" "prefix+shift+v" "the symlink target received the block"
rm -rf "$WORK"

# --- I3b: writing must not widen the config's mode --------------------------
file_mode() { stat -c '%a' "$1" 2>/dev/null || stat -f '%OLp' "$1"; }
new_cfg 'onboarding = false'
chmod 600 "$SESSION_FORK_CONFIG"
"$KEYS" setup >/dev/null
assert_eq "$(file_mode "$SESSION_FORK_CONFIG")" "600" "the config keeps its mode"
drop_cfg

finish
