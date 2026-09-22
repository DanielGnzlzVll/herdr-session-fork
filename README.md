# herdr-session-fork

One keystroke forks the focused agent session into a sibling pane. Both copies
carry the full conversation up to that moment, both stay live, and both share
the working directory.

Fork at a decision point and drive each copy down a different path, or leave
the fork grinding on the current task while you steer the original elsewhere.

## Install

```bash
herdr plugin install DanielGnzlzVll/herdr-session-fork
herdr plugin action invoke setup-keys --plugin danielgnzlzvll.session-fork
herdr server reload-config
```

`setup-keys` writes one delimited block into `~/.config/herdr/config.toml` and
backs the file up first. It refuses rather than overwrite a key you already
bind. `remove-keys` deletes exactly that block.

## Keys

| Key | What happens |
|---|---|
| `prefix+shift+v` | Fork opens in a pane to the **right** |
| `prefix+_` | Fork opens in a pane **below** |

These mirror herdr's own `split_vertical` (`prefix+v`) and `split_horizontal`
(`prefix+minus`): hold shift while you press the split key, and you get a split
with a fork of this session in it.

`prefix+_` rather than `prefix+shift+minus` because that keystroke reaches the
terminal as the character `_`. herdr accepts `shift+minus` and registers it as
shift plus the `-` keycode — a chord the terminal never sends — so it would
parse without complaint and then never fire.

To bind your own keys instead, point a `[[keys.command]]` at the action:

```toml
[[keys.command]]
key = "prefix+alt+f"
type = "plugin_action"
command = "danielgnzlzvll.session-fork.clone-vertical"
```

The two action ids are `clone-vertical` and `clone-horizontal`.

## Requirements

- herdr 0.9.0 or newer
- `jq`
- Linux or macOS
- The agent's herdr integration installed **before the session started**:

```bash
herdr integration install claude
```

That hook is what reports the session id, and it only fires when a session
begins. **A session that was already running when the integration was installed
cannot be forked** — restart the agent in that pane and the next session will
report an id.

## ⚠️ Both copies share a working directory

The fork opens in the same `cwd` as its source. Two live agents can edit the
same files, and nothing stops them from overwriting each other.

This is deliberate: isolating the fork in a git worktree would put it in a
separate herdr workspace rather than a pane beside you, and the forked context
is full of absolute paths that would still point at the original checkout.

So the plugin is at its best when at least one of the two copies is thinking
rather than writing — comparing two plans, reviewing a diff, exploring an
approach. If both are going to edit, give one of them a worktree yourself.

## A turn in flight is not in the fork

Forking reads the session's transcript from disk. Fork while the agent is
working and the copy carries everything up to the last **completed** turn; the
turn being generated at that instant is not in it. The original is unaffected
and finishes normally.

## Supported agents

**Claude Code only.**

Forking needs a CLI flag that mints a *new* session id. Claude Code has one
(`--resume <id> --fork-session`). A plain "resume" is not a substitute — it
reattaches the original session, so both processes would append to one history
and the fork would cannibalise its source. That failure is silent and costs the
user their work.

Codex is the obvious next candidate, since it writes a new rollout file per run,
but that has not been tested. Issues and PRs for other agents are welcome; each
one needs its fork verified on real hardware before it goes in the table, never
from documentation alone. The table is `scripts/agents.sh` — adding a verified
agent is one line.

## Development

```bash
bash tests/run.sh
```

Tests drive a stub `herdr` placed first on `PATH`, so they need neither a
running herdr server nor a real agent. `shellcheck` runs as part of the suite
when it is installed.

## Licence

MIT
