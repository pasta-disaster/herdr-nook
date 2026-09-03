# Changelog

- Changed: updated design.md to reflect socket method name, generic action resolution, and Meta/Alt detach bindings (Mike Thomas, 2026-09-03)
- Added: Alt/Meta and question-mark root detach keybindings (M-C-_, C-?, M-C-?) in tmux dialog server to support chords like Ctrl+Alt+/ (Mike Thomas, 2026-09-03)
- Changed: made action dimension resolution completely generic so any action name (e.g. toggle-tiny) works automatically via manifest and plugin config without script code changes (Mike Thomas, 2026-09-03)
- Changed: streamlined README to concisely explain hotkey interception (herdr on open vs tmux detach on hide) (Mike Thomas, 2026-09-03)
- Changed: moved user-configurable popup dimensions to plugin config (~/.config/herdr/plugins/config/nook/config.toml) to prevent herdr keybinding warnings, keeping clean toggle and toggle-small actions (Mike Thomas, 2026-09-03)
- Removed: redundant close, toggle-small, and prompt actions along with panel-small entrypoint; single toggle action with keybinding dimensions now handles all popup invocations (Mike Thomas, 2026-09-03)
- Added: dynamic popup dimension support via keybinding configuration in config.toml (width and height on [[keys.command]]) with socket-driven plugin.pane.open sizing and manifest fallback (Mike Thomas, 2026-09-03)

- Added: a second, smaller popup - entrypoint panel-small (70% x 30%) and action nook.toggle-small, bound to Ctrl+Shift+/; both sizes share the same per-workspace tmux session so switching size keeps the shell; panel.sh open/toggle logic parametrized by entrypoint (Mike Thomas, 2026-08-20)

- Changed: renamed the plugin from Floating Panel to Nook - plugin id floating-panel to nook, action commands nook.toggle/nook.prompt/nook.close, tmux server socket to nook, and updated the live keybindings and all docs; project directory renamed to herdr-nook (Mike Thomas, 2026-08-20)

- Removed: the sidebar indicator - herdr 0.7.5 has no plugin surface to render a per-workspace status marker (workspace metadata tokens are stored but not displayed, and sidebar tokens are limited to agent-row templates), so the non-functional code was removed (Mike Thomas, 2026-08-20)

- Added: sidebar indicator - a metadata token next to the workspace name marks any workspace with a live session (showing or hidden); set on open, cleared on close, per workspace. A right-edge tab-bar indicator was investigated but herdr exposes no tab-bar token surface, so the sidebar is used (Mike Thomas, 2026-08-20)
- Changed: documented the popup border background fix - set [theme.custom] panel_bg = "reset" in the herdr config so the border background matches the terminal; applied to the live config (Mike Thomas, 2026-08-20)

- Fixed: reopened popup was blank with no retained content - switched the persistence backend from dtach to tmux, which keeps a screen buffer, so reattaching repaints exactly what was there (Mike Thomas, 2026-08-20)
- Changed: sessions now run on a private tmux server (socket name nook), one session per workspace (ws_<id>), isolated from the user's own tmux; close kills the tmux session (Mike Thomas, 2026-08-20)
- Fixed: Ctrl+/ failing to hide the popup under some full-screen apps - hide is now a tmux detach binding (more robust than dtach's single-byte scan), with extended-keys off and a Ctrl+Space then d fallback for apps using an enhanced keyboard protocol (Mike Thomas, 2026-08-20)

- Changed: the popup now runs a persistent interactive shell instead of a custom command prompt; you type exactly what you want with the shell's own tab completion, and it runs literally that (Mike Thomas, 2026-08-20)
- Removed: fzf-based command box and scripts/prompt.sh - fzf fuzzy-matched and would run a list item instead of the typed text (e.g. "ls -al" launching "update-fonts-alias"), and drew a redundant second border inside herdr's existing popup frame (Mike Thomas, 2026-08-20)
- Fixed: blank popup after a session ended - session liveness now removes a stale socket so a reopen starts a fresh shell instead of attaching to a dead session (Mike Thomas, 2026-08-20)

- Changed: command prompt rebuilt with fzf - input sits inside a rounded box with live command/path suggestions below, and the box can no longer be corrupted by ambiguous tab-completion output (the previous readline-in-a-box approach could not contain the completion list); falls back to a plain prompt if fzf is absent (Mike Thomas, 2026-08-20)
- Changed: hide is now handled by dtach's detach character (Ctrl+/, 0x1f) pressed inside the focused popup, which closes the popup while the session persists; this replaces the unworkable keybinding-to-hide approach (a focused popup consumes keys and prefix mode dismisses the popup) (Mike Thomas, 2026-08-20)
- Changed: single key Ctrl+/ now both opens the popup (via herdr when no popup is focused) and hides it (via dtach when the popup is focused); live keybinding updated (Mike Thomas, 2026-08-20)

- Fixed: toggle could open the popup but not hide it, because a focused popup captures the keyboard and herdr only intercepts prefix keys over it; documented the constraint and switched the recommended and live keybindings to prefix-based (prefix+f toggle, prefix+shift+f close) (Mike Thomas, 2026-08-20)

- Added: toggle action and single-key toggle - one keybinding dismisses the popup if showing or opens it if not, using popup.close's own open/not-open report as a raceless state signal; dismissing only detaches so the persistent session survives toggling (Mike Thomas, 2026-08-20)
- Changed: panel.sh refactored to share popup open/close/end-session helpers across toggle, prompt, and close actions; default action is now toggle (Mike Thomas, 2026-08-20)

- Added: Persistence across popup toggles via a per-workspace dtach session - the popup is now a thin client that attaches to a detached session, so the program keeps running when the popup closes and resumes on reopen (Mike Thomas, 2026-08-20)
- Added: scripts/prompt.sh - a centered rounded-box command prompt (pure bash and ANSI, no extra dependencies) drawn to the tty with the command emitted cleanly on stdout (Mike Thomas, 2026-08-20)
- Changed: scripts/dialog.sh reworked into a session manager - resolves the workspace id, reattaches straight into a live session, or prompts and starts a new one when none exists (Mike Thomas, 2026-08-20)
- Changed: close action now ends the workspace's dtach session (kills its process group and removes the socket) in addition to closing the popup (Mike Thomas, 2026-08-20)
- Added: dtach dependency for session persistence; socat also used to probe session liveness without disturbing the session (Mike Thomas, 2026-08-20)

- Changed: Reworked to an input-dialog popup (Option B) - one hotkey opens an 80% floating popup that prompts for any command and runs it, replacing the fixed single-command design; herdr already has native fixed-command popups via keys.command type popup, so this plugin now fills the arbitrary-command gap (Mike Thomas, 2026-08-17)
- Added: scripts/dialog.sh - readline command prompt with persistent history, run-another loop, and shell-operator support (Mike Thomas, 2026-08-17)
- Changed: Actions reduced to prompt and close; removed the per-workspace popup-toggle state machine and the workspace indicator, which are unnecessary for an ephemeral prompt (Mike Thomas, 2026-08-17)
- Fixed: Manifest invokes the dialog by absolute path under HERDR_PLUGIN_ROOT because the popup cwd is the user's focused directory, not the plugin root, so a relative path was not found and the popup exited immediately (Mike Thomas, 2026-08-17)
- Fixed: Read the command into a variable instead of via command substitution, so the readline prompt renders and line editing works and only one foreground process runs (Mike Thomas, 2026-08-17)

- Changed: Reworked to Option A - a true floating popup (placement popup, 80% width/height) that pops up over the current tab, per workspace; toggling off now closes the popup because herdr's popup surface is global and cannot be hidden while alive (Mike Thomas, 2026-08-17)
- Changed: Indicator moved from a right-edge tab-bar element (not supported by the API) to a workspace-list token shown next to the workspace name (Mike Thomas, 2026-08-17)
- Added: Direct socket call to herdr popup.close (not exposed on the CLI); socat is now a dependency (Mike Thomas, 2026-08-17)
- Fixed: socket_call default-parameter brace bug (${2:-{}}) that appended a stray brace and made popup.close fail, leaving TUI popups like top running after close (Mike Thomas, 2026-08-17)
- Added: Per-workspace popup ownership state tracked by process PID for reliable liveness across command self-exit and herdr restarts (Mike Thomas, 2026-08-17)

- Added: Nook herdr plugin - per-workspace toggleable floating pane that runs a configured command or TUI, persists in a background tab when hidden, and terminates only on close (Mike Thomas, 2026-08-17)
- Added: Plugin manifest herdr-plugin.toml with panel entrypoint (split placement) and toggle, close, refresh-indicator actions (Mike Thomas, 2026-08-17)
- Added: scripts/panel.sh state machine implementing open, hide, show, close, and indicator logic using live herdr topology for panel identity (Mike Thomas, 2026-08-17)
- Added: Tab-bar indicator via workspace metadata tokens with TTL, set while a panel is active and cleared on close (Mike Thomas, 2026-08-17)
- Added: config.example.toml, README.md, docs/design.md, and docs/overview.md (Mike Thomas, 2026-08-17)
