#!/usr/bin/env bash
# Manage this plugin's keybinding block in the herdr config.
# Usage: keys.sh <setup|remove>
#
# This edits a file the user owns, so every write goes through write_cfg (which
# preserves the inode, so a symlinked dotfile stays linked and the mode is not
# widened) and is preceded by backup_once.
set -euo pipefail

mode="${1:-}"
case "$mode" in setup|remove) ;; *) echo "usage: keys.sh <setup|remove>" >&2; exit 2 ;; esac

cfg="${SESSION_FORK_CONFIG:-$HOME/.config/herdr/config.toml}"
BEGIN="# >>> danielgnzlzvll.session-fork keys"
END="# <<< danielgnzlzvll.session-fork keys"

mkdir -p "$(dirname "$cfg")"
[ -f "$cfg" ] || : >"$cfg"

# An unbalanced pair means someone lost a marker by hand. Stripping from BEGIN
# to EOF would then delete everything after it -- the user's other sections and
# their own keybindings -- so refuse and let them repair it.
begins=$(grep -cF "$BEGIN" "$cfg" || true)
ends=$(grep -cF "$END" "$cfg" || true)
if [ "$begins" != "$ends" ]; then
  echo "$cfg has $begins session-fork start marker(s) and $ends end marker(s)." >&2
  echo "Repair that block by hand first; refusing to touch the file." >&2
  exit 1
fi

strip_block() {
  awk -v b="$BEGIN" -v e="$END" '
    index($0, b) == 1 { skip = 1 }
    !skip { print }
    index($0, e) == 1 { skip = 0 }
  ' "$1"
}

# Write stdin over $cfg in place. Buffering into a temp first means a failure
# mid-render cannot truncate the config; redirecting onto $cfg (rather than
# mv-ing over it) keeps the inode, so a symlink into a dotfiles repo stays a
# symlink and the file's mode is untouched.
write_cfg() {
  local tmp
  tmp=$(mktemp "$(dirname "$cfg")/.session-fork.XXXXXX")
  cat >"$tmp"
  cat "$tmp" >"$cfg"
  rm -f "$tmp"
}

# The backup is the file as it was before this plugin first touched it. A later
# run must not overwrite it with a copy that already contains our block.
backup_once() {
  [ -e "$cfg.session-fork-backup" ] || cp "$cfg" "$cfg.session-fork-backup"
}

if [ "$mode" = "remove" ]; then
  backup_once
  strip_block "$cfg" | write_cfg
  echo "Removed the session-fork keybindings. Run: herdr server reload-config"
  exit 0
fi

# An active binding on either key, outside our own block, is the user's --
# leave it alone and say so. Commented-out lines do not count: zoetrope ships
# a commented prefix+shift+v, and that is not a conflict.
without_ours=$(strip_block "$cfg")
for key in "prefix+shift+v" "prefix+shift+minus"; do
  # `+` is an ERE metacharacter, so the key has to be escaped to match
  # literally. TOML accepts both quote styles for the value.
  key_re=${key//+/\\+}
  if printf '%s\n' "$without_ours" \
    | grep -qE "^[[:space:]]*key[[:space:]]*=[[:space:]]*[\"']${key_re}[\"']"; then
    echo "$cfg already binds $key to something else. Remove or change that binding, then run setup-keys again." >&2
    exit 1
  fi
done

backup_once

{
  printf '%s\n' "$without_ours"
  cat <<BLOCK
$BEGIN (managed: \`setup-keys\` writes this block, \`remove-keys\` deletes it)
[[keys.command]]
key = "prefix+shift+v"
type = "plugin_action"
command = "danielgnzlzvll.session-fork.clone-vertical"
description = "session-fork: fork this session into a pane on the right"

[[keys.command]]
key = "prefix+shift+minus"
type = "plugin_action"
command = "danielgnzlzvll.session-fork.clone-horizontal"
description = "session-fork: fork this session into a pane below"
$END
BLOCK
} | write_cfg

echo "Wrote the session-fork keybindings to $cfg (backup: $cfg.session-fork-backup)."
echo "Run: herdr server reload-config"
