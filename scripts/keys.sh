#!/usr/bin/env bash
# Manage this plugin's keybinding block in the herdr config.
# Usage: keys.sh <setup|remove>
set -euo pipefail

mode="${1:-}"
case "$mode" in setup|remove) ;; *) echo "usage: keys.sh <setup|remove>" >&2; exit 2 ;; esac

cfg="${SESSION_FORK_CONFIG:-$HOME/.config/herdr/config.toml}"
BEGIN="# >>> danielgnzlzvll.session-fork keys"
END="# <<< danielgnzlzvll.session-fork keys"

mkdir -p "$(dirname "$cfg")"
[ -f "$cfg" ] || : >"$cfg"

strip_block() {
  awk -v b="$BEGIN" -v e="$END" '
    index($0, b) == 1 { skip = 1 }
    !skip { print }
    index($0, e) == 1 { skip = 0 }
  ' "$1"
}

if [ "$mode" = "remove" ]; then
  strip_block "$cfg" >"$cfg.tmp" && mv "$cfg.tmp" "$cfg"
  echo "Removed the session-fork keybindings. Run: herdr server reload-config"
  exit 0
fi

# An active binding on either key, outside our own block, is the user's --
# leave it alone and say so. Commented-out lines do not count: zoetrope ships
# a commented prefix+shift+v, and that is not a conflict.
without_ours=$(strip_block "$cfg")
for key in "prefix+shift+v" "prefix+shift+minus"; do
  # `+` is an ERE metacharacter, so the key has to be escaped to match literally.
  key_re=${key//+/\\+}
  if printf '%s\n' "$without_ours" | grep -qE "^[[:space:]]*key[[:space:]]*=[[:space:]]*\"$key_re\""; then
    echo "$cfg already binds $key to something else. Remove or change that binding, then run setup-keys again." >&2
    exit 1
  fi
done

cp "$cfg" "$cfg.session-fork-backup"

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
} >"$cfg.tmp" && mv "$cfg.tmp" "$cfg"

echo "Wrote the session-fork keybindings to $cfg (backup: $cfg.session-fork-backup)."
echo "Run: herdr server reload-config"
