# Nook

A herdr plugin that gives each workspace a persistent floating shell. Press the hotkey: a
popup opens over the current tab (default 80% x 80%) with an interactive shell. Run anything
you like in it. Press the hotkey again to hide the popup - the shell and whatever is running
in it keep going in the background - and press it once more to resume exactly where you
left off.

## Why this exists

herdr has native fixed-command popups (`[[keys.command]]` with `type = "popup"`), but a
popup's process is killed when the popup closes, so nothing persists across toggles. This
plugin keeps the shell alive between toggles by running it inside a `tmux` session - one
per workspace, on a private tmux server - and making the popup a client that attaches to
it. tmux keeps a screen buffer, so reopening shows exactly what was there.

## Features

- Hotkey opens a floating popup with an interactive shell (new session) or reattaches
  straight into the running one (existing session).
- The shell and its running programs persist in the background across popup toggles;
  contents intact.
- One persistent session per workspace - workspace 1 and workspace 2 are independent.
- Fully user-configurable dimensions (large and small popup actions).
- A real shell: type exactly what you want, with the shell's own tab completion.

## Requirements

- herdr 0.7.5 or newer.
- `tmux` on PATH (the persistence backend; retains screen contents across toggles).
  Debian/Ubuntu: `sudo apt install tmux`. Runs on a private tmux server (socket name
  `nook`), isolated from any tmux you use yourself.
- `socat` on PATH (used to call herdr's popup control).
- `jq` on PATH (used to read the workspace id and format socket requests).

## Install

Local checkout (development):

```
herdr plugin link /path/to/herdr-nook
```

From GitHub (once published):

```
herdr plugin install pasta-disaster/herdr-nook
```

No build step: the plugin is shell scripts plus herdr's popup surface and tmux.

## Keybindings

Bind the toggle actions in `~/.config/herdr/config.toml`:

```toml
[[keys.command]]
key = "ctrl+/"
type = "plugin_action"
command = "nook.toggle"

[[keys.command]]
key = "ctrl+shift+/"
type = "plugin_action"
command = "nook.toggle-small"
```

`command` is `<plugin_id>.<action_id>`; the plugin id is `nook`.

**One key for open and hide.** `ctrl+/` handles both:

- **Open**: When the popup is closed, herdr catches `ctrl+/` and runs `nook.toggle`, opening the popup and attaching to the workspace's tmux session.
- **Hide**: When the popup is focused, tmux catches `ctrl+/` via its `detach-client` root binding (`bind-key -n 'C-_' detach-client`), detaching the client and closing the popup surface while keeping the shell running in the background.
- **Fallback**: If a full-screen TUI consumes raw chords, `Ctrl+Space` then `d` (nook's tmux prefix) detaches and hides the popup.

## Custom Popup Dimensions

Popup dimensions are user-configurable. Create or edit
`~/.config/herdr/plugins/config/nook/config.toml` (or `~/.config/herdr/nook.toml`):

```toml
[toggle]
width = "80%"
height = "80%"

[toggle-small]
width = "70%"
height = "30%"
```

Dimensions accept percentages (e.g. `"80%"`) or explicit cell counts (e.g. `100`, `30`).
If omitted, dimensions fall back to default values (80% x 80% for `nook.toggle`, 70% x 30%
for `nook.toggle-small`).

## Using it

- First `ctrl+/` in a workspace: a popup opens with an interactive shell. Run any command
  (or several). Real tab completion works, and commands run exactly as typed.
- Press `ctrl+/` to hide the popup - the shell and anything running in it keep going.
- Press `ctrl+/` later: you reattach straight into the shell, resuming where you left off.
- To exit the shell, type `exit` (or Ctrl+D) inside the popup.

The shell prompt renders inside herdr's own popup frame (which already shows the "Nook"
title), so there is no second box drawn around it.

## Popup border background

The popup border is drawn by herdr using the theme's panel background, which may differ
from your terminal background. To make it match, set in `~/.config/herdr/config.toml`:

```toml
[theme.custom]
panel_bg = "reset"
```

This is a global herdr theme setting (it affects all panels, not just this popup); there
is no popup-only background token.

## Actions

| action         | effect                                                                   |
| -------------- | ------------------------------------------------------------------------ |
| `toggle`       | open the main popup (default 80% x 80%), or reattach the running one     |
| `toggle-small` | open the small popup (default 70% x 30%), or reattach the running one    |

Hiding is not an action - it happens by pressing `ctrl+/` inside the focused popup, which
tmux catches as its detach binding (fallback: `Ctrl+Space` then `d`).

To add another action (e.g. to enable another hotkey with separate dimension configuration):
1. Add the action to herdr-plugin.toml:
```toml
[[actions]]
id = "toggle-tiny"
title = "Nook: toggle (tiny)"
contexts = ["pane", "workspace"]
command = ["bash", "scripts/panel.sh", "toggle-tiny"]
```

2. Configure its dimensions in ~/.config/herdr/plugins/config/nook/config.toml:
```toml
[toggle-tiny]
width = "40%"
height = "20%"
```

3. Bind the key in ~/.config/herdr/config.toml:
```toml
[[keys.command]]
key = "ctrl+alt+/"
type = "plugin_action"
command = "nook.toggle-tiny"
```

## How it works

The popup runs `scripts/dialog.sh`. It derives the workspace id, uses a tmux session named
`ws_<workspace>` on a private tmux server (socket name `nook`), and either
attaches to the existing session or creates one running an interactive shell. Because tmux
keeps a screen buffer and owns the session, closing the popup only detaches - the shell
and its scrollback live on, and reopening repaints exactly what was there. See
`docs/design.md`.
