#!/usr/bin/env bash
# Nook session manager, run inside the popup.
#
# One persistent tmux session per workspace, on a private tmux server (a dedicated socket
# name) so it never clashes with a tmux you run yourself:
#   - No live session: create a fresh session and attach.
#   - Session exists: attach straight in, resuming with its full screen contents intact.
#
# tmux keeps a screen buffer, so reattaching shows exactly what was there (unlike dtach,
# which retains nothing and reopened blank). Pressing Ctrl+/ inside the popup is bound at
# the tmux level to detach-client: the popup closes but the session keeps running, so the
# next open reattaches where you left off. Ctrl+/ is also the herdr key that opens the
# popup, giving one key for open and hide.
set -uo pipefail

export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:${PATH:-}"

command -v tmux >/dev/null 2>&1 || {
    printf '\033[1;31mnook:\033[0m tmux is not installed.\n' >&2
    printf 'Install it (Debian/Ubuntu): sudo apt install tmux\n' >&2
    sleep 4
    exit 1
}

# Private tmux server for this plugin (isolated from the user's own tmux).
TMUX_SOCKET="nook"
TM=(tmux -L "$TMUX_SOCKET")

# ---------------------------------------------------------------------------
# Workspace id -> session name. The popup pane gets the id inside
# HERDR_PLUGIN_CONTEXT_JSON, not as a bare HERDR_WORKSPACE_ID.
# ---------------------------------------------------------------------------
WS=""
if [ -n "${HERDR_WORKSPACE_ID:-}" ]; then
    WS="$HERDR_WORKSPACE_ID"
elif [ -n "${HERDR_PLUGIN_CONTEXT_JSON:-}" ] && command -v jq >/dev/null 2>&1; then
    WS=$(printf '%s' "$HERDR_PLUGIN_CONTEXT_JSON" | jq -r '.workspace_id // empty' 2>/dev/null)
fi
[ -n "$WS" ] || WS="default"
# tmux session names cannot contain '.' or ':'; sanitize to a safe set.
SESSION=$(printf 'ws_%s' "$WS" | tr -c 'A-Za-z0-9_-' '_')

# Working directory for a fresh session: the focused pane's cwd when herdr provides it.
START_DIR="$HOME"
if [ -n "${HERDR_PLUGIN_CONTEXT_JSON:-}" ] && command -v jq >/dev/null 2>&1; then
    d=$(printf '%s' "$HERDR_PLUGIN_CONTEXT_JSON" | jq -r '.focused_pane_cwd // .workspace_cwd // empty' 2>/dev/null)
    [ -n "$d" ] && [ -d "$d" ] && START_DIR="$d"
fi

# ---------------------------------------------------------------------------
# Server-wide options applied once (idempotent). These shape the popup session:
#   - No status bar (herdr already frames the popup with a title).
#   - Large scrollback.
#   - Detach (hide) keys. Ctrl+/ is the primary, matching the herdr open key. Some TUIs
#     use an enhanced keyboard protocol (kitty/CSI-u) that re-encodes Ctrl+/, so a
#     fallback prefix is provided too: the tmux prefix is set to Ctrl+Space (distinct
#     from herdr's Ctrl+b), and prefix then d always detaches regardless of app keyboard
#     mode. extended-keys off asks tmux not to negotiate the CSI-u protocol, which keeps
#     Ctrl+/ arriving as a plain key more often.
# ---------------------------------------------------------------------------
configure_server() {
    "${TM[@]}" set-option -g  status off          \; \
               set-option -g  history-limit 50000 \; \
               set-option -g  mouse on            \; \
               set-option -g  extended-keys off   \; \
               set-option -g  prefix C-Space      \; \
               bind-key   -n  'C-_'   detach-client \; \
               bind-key   -n  'M-C-_' detach-client \; \
               bind-key   -n  'C-?'   detach-client \; \
               bind-key   -n  'M-C-?' detach-client \; \
               bind-key       d       detach-client 2>/dev/null || :
}

session_exists() {
    "${TM[@]}" has-session -t "$SESSION" 2>/dev/null
}

# ---------------------------------------------------------------------------
# Create the session if needed, then attach. Attaching a tmux client repaints the full
# retained screen, so a reopen shows exactly what was there.
# ---------------------------------------------------------------------------
if ! session_exists; then
    "${TM[@]}" new-session -d -s "$SESSION" -c "$START_DIR" 2>/dev/null || {
        printf 'nook: failed to create session\n' >&2
        sleep 3
        exit 1
    }
fi
configure_server

# Attach. tmux sizes the session to this client and repaints the buffer. On Ctrl+/ the
# root binding detaches, closing the popup while the session lives on.
exec "${TM[@]}" attach-session -t "$SESSION"
