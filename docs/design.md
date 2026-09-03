# Nook design

How the plugin makes a floating popup persist across toggles, per workspace, on herdr.

## The core problem and the solution

herdr's popup is a single global surface with only `popup.close`, which tears down the
popup's PTY and kills its process group (verified: the process receives SIGHUP on close).
So a popup cannot be hidden while its program keeps running - not with herdr alone.

The fix is a terminal multiplexer that owns the durable PTY and keeps a screen buffer:
run the shell inside a `tmux` session, and make the popup a client that attaches to it.
Closing the popup detaches the client; tmux keeps the shell alive on its own PTY, and -
crucially - retains the screen contents. Reopening attaches a client and tmux repaints
exactly what was there.

tmux is used rather than dtach (an earlier choice) because dtach has no screen buffer: it
relays live I/O only, so a reattached shell showed blank until the next keystroke and its
scrollback was gone. Retaining content across toggles requires a multiplexer that stores
the screen, which tmux does. To avoid clashing with a tmux the user runs themselves, the
plugin uses a private tmux server (a dedicated socket name, `nook`).

## Requirements to mechanics

| Requirement                         | Mechanic                                                      |
| ----------------------------------- | ------------------------------------------------------------ |
| Floating popup over the tab         | `plugin.pane.open` `placement: popup`, `width/height`        |
| Persist across toggles, keep screen | shell runs inside a `tmux` session (screen buffer retained)  |
| One hotkey opens/resumes            | `toggle` action opens; tmux detach binding hides (see below) |
| Per workspace                       | one tmux session (`ws_<id>`) per workspace                   |
| User-configurable popup sizes       | plugin config (`~/.config/herdr/plugins/config/nook/config.toml`) |
| Run exactly what you type + tab     | an interactive shell inside the popup                        |

## Components

- `scripts/panel.sh` - generic launcher action.
  - Dynamically resolves popup dimensions for any configured action (e.g. `toggle`,
    `toggle-small`, `toggle-tiny`) from the plugin configuration (`[toggle]`, `[toggle-small]`,
    etc.), opens the popup with those dimensions, or dismisses it if showing.
- `scripts/dialog.sh` - runs inside the popup. Resolves the workspace id, then attaches to
  the workspace's tmux session (creating it with an interactive shell if needed).

A single pane entrypoint `panel` is defined in the manifest. Popup dimensions are resolved
dynamically by `panel.sh` from the plugin config and passed via the socket API
(`plugin.pane.open`), keeping Herdr's main `config.toml` clean without diagnostics.
All actions share the same per-workspace session, so you can switch sizes and keep your shell.

## Workspace identity and the session

Actions get `HERDR_WORKSPACE_ID`. The popup pane gets the id inside
`HERDR_PLUGIN_CONTEXT_JSON.workspace_id`. Both paths resolve the id and derive a tmux
session name `ws_<sanitized-workspace-id>` on the private tmux server, so each workspace
has an independent persistent session.

## Session liveness

With tmux there is no socket race to manage: `tmux has-session -t <name>` reports whether
the session exists, and `attach-session` repaints the retained buffer. A session ends only
when its shell exits, so a reopen never lands on a dead session showing blank (the failure
mode that dtach exhibited).

## The panel content: an interactive shell

The popup runs the user's login shell (`$SHELL -l`, falling back to bash then sh). This
is deliberately simple and matches the requirement of "type exactly the command I want,
with real completion, run literally that":

- The shell runs exactly what you type; nothing fuzzy-matches or rewrites it.
- Tab completion is the shell's own, rendered correctly because the shell owns the screen.
- No box is drawn by the plugin - herdr already frames the popup with a border and the
  "Nook" title, so the shell prompt sits inside that frame.

## Session launch and reattach

The dialog attaches to `ws_<id>`, creating it with an interactive shell if it does not
exist:

```
tmux -L nook new-session -d -s ws_<id> -c <cwd>   # only if missing
tmux -L nook attach-session -t ws_<id>
```

Attaching repaints tmux's retained buffer, so a reopened popup shows exactly what was
there. The shell runs until you exit it.

## Open and hide with one key (Ctrl+/)

The key challenge: herdr cannot hide a focused popup from a keybinding. A focused popup
consumes keystrokes, so a direct chord never reaches herdr to close it; and entering prefix
mode dismisses the popup outright, so a prefix binding just reopens it.

The resolution routes open and hide through two different layers, unified under one key:

- **Open**: when no popup is focused, the key reaches herdr and runs the configured toggle
  action (e.g. `nook.toggle`), which opens the popup (reattaching a live session or creating one).
- **Hide**: when the popup is focused, the key chord is consumed inside the popup, where tmux
  is bound to detach: `bind-key -n 'C-_' detach-client` along with modifier variants (`M-C-_`,
  `C-?`, `M-C-?`). tmux detaches, the popup closes, and the session keeps running.

tmux's root bindings intercept the key before the inner app, so hide works over most TUIs. But
some full-screen apps enable an enhanced keyboard protocol (kitty/CSI-u) that re-encodes
chords, so tmux may not match them directly. Two mitigations: `extended-keys off` asks tmux not to
negotiate that protocol, and the tmux prefix is set to `Ctrl+Space` (distinct from herdr's
`Ctrl+b`) so `Ctrl+Space` then `d` always detaches as a fallback. Persistence survives
any number of toggles.

## Verified behaviour

- New session: the workspace's tmux session is created with a shell; popup attaches.
- Toggle off then on: same session, contents fully retained (tmux screen buffer).
- Detach binding works while a full-screen app runs inside; the app keeps running.
- Per workspace: session names are distinct; one workspace's session is untouched by
  another.

## No in-UI indicator

An in-UI "this workspace has a live session" indicator was investigated and dropped.
herdr 0.7.5 offers no clean plugin surface for it.

## Popup border background

The popup border is herdr's, drawn with the theme's panel background token. There is no
popup-only background token, so matching it to the terminal background is a global theme
setting: `[theme.custom] panel_bg = "reset"` in the user's herdr config.

## Failure semantics

An action that cannot proceed refuses loudly (exit 1, one stderr line); a success prints
one stdout line. A missing `tmux` shows an install hint in the popup instead of failing
silently.
