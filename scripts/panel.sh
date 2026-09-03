#!/usr/bin/env bash
# Nook launcher: open, dismiss, or toggle the floating popup.
#
#   panel.sh [action_id] [width] [height]
#
# Dynamically resolves popup dimensions from ~/.config/herdr/plugins/config/nook/config.toml
# (or ~/.config/herdr/nook.toml) under [<action_id>] (e.g. [toggle], [toggle-small], [toggle-tiny]).
#
# herdr's popup is a single global surface, opened with a plugin pane at popup placement
# and closed with the socket popup.close (not on the CLI). The popup runs the session
# manager (scripts/dialog.sh), which owns the per-workspace tmux session.
#
# Hiding is handled by tmux, not here: pressing Ctrl+/ inside the focused popup is caught
# by tmux as its detach binding (dialog.sh binds C-_ to detach-client), which closes the
# popup while the session keeps running. herdr never sees that key because a focused popup
# consumes it. So when the toggle action DOES run (no popup focused), it essentially always
# opens. The dismiss branch below is a harmless fallback for the rare case a popup is open
# but not consuming the key.
set -uo pipefail

export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:${PATH:-}"

MODE="${1:-toggle}"
H="${HERDR_BIN_PATH:-herdr}"

refuse() {
    printf 'nook: %s\n' "$1" >&2
    exit 1
}

HERDR_SOCK="${HERDR_SOCKET_PATH:-$HOME/.config/herdr/herdr.sock}"

# Close the popup surface via herdr's socket (popup.close is not on the CLI). Prints the
# outcome: "closed" if a popup was open and dismissed, "none" if nothing was open,
# "error" if the call failed. This is the only popup-state signal herdr exposes.
close_popup_surface() {
    command -v socat >/dev/null 2>&1 || { printf 'error'; return; }
    local resp
    resp=$(printf '{"id":"fp","method":"popup.close","params":{}}\n' \
        | timeout 5 socat - "UNIX-CONNECT:$HERDR_SOCK" 2>/dev/null)
    case "$resp" in
        *popup_not_open*) printf 'none' ;;
        *'"type":"ok"'*)  printf 'closed' ;;
        *)                printf 'error' ;;
    esac
}

# Open the popup via herdr socket API with custom width/height dimensions.
open_popup_socket() {
    local entrypoint="$1" cwd="$2" width="$3" height="$4"
    command -v socat >/dev/null 2>&1 || return 1
    command -v jq >/dev/null 2>&1 || return 1

    local req resp
    req=$(jq -n \
        --arg plugin_id "nook" \
        --arg entrypoint "$entrypoint" \
        --arg placement "popup" \
        --arg cwd "$cwd" \
        --arg width "$width" \
        --arg height "$height" \
        '{
            id: "nook_open",
            method: "plugin.pane.open",
            params: ({
                plugin_id: $plugin_id,
                entrypoint: $entrypoint,
                placement: $placement,
                focus: true
            }
            + (if $cwd != "" then {cwd: $cwd} else {} end)
            + (if $width != "" then {width: (if ($width | test("^[0-9]+$")) then ($width | tonumber) else $width end)} else {} end)
            + (if $height != "" then {height: (if ($height | test("^[0-9]+$")) then ($height | tonumber) else $height end)} else {} end))
        }' -c 2>/dev/null) || return 1

    resp=$(printf '%s\n' "$req" | timeout 5 socat - "UNIX-CONNECT:$HERDR_SOCK" 2>/dev/null)
    case "$resp" in
        *'"type":"ok"'*|*'"plugin_pane"'*) return 0 ;;
        *) return 1 ;;
    esac
}

# Resolve custom width and height configured for this action.
# Checks:
#   1. $NOOK_CONFIG_PATH
#   2. $HERDR_PLUGIN_CONFIG_DIR/config.toml (standard plugin config path)
#   3. $HOME/.config/herdr/nook.toml
# Reads [<mode>] section or falls back to sensible defaults based on name.
resolve_config_dimensions() {
    local mode="$1"
    local cfg_path=""

    if [ -n "${NOOK_CONFIG_PATH:-}" ] && [ -f "$NOOK_CONFIG_PATH" ]; then
        cfg_path="$NOOK_CONFIG_PATH"
    elif [ -n "${HERDR_PLUGIN_CONFIG_DIR:-}" ] && [ -f "$HERDR_PLUGIN_CONFIG_DIR/config.toml" ]; then
        cfg_path="$HERDR_PLUGIN_CONFIG_DIR/config.toml"
    elif [ -f "$HOME/.config/herdr/plugins/config/nook/config.toml" ]; then
        cfg_path="$HOME/.config/herdr/plugins/config/nook/config.toml"
    elif [ -f "$HOME/.config/herdr/nook.toml" ]; then
        cfg_path="$HOME/.config/herdr/nook.toml"
    fi

    if command -v python3 >/dev/null 2>&1; then
        python3 - "$cfg_path" "$mode" << 'EOF' 2>/dev/null || :
import sys, os, re

cfg_path = sys.argv[1] if len(sys.argv) > 1 else ""
mode = sys.argv[2] if len(sys.argv) > 2 else "toggle"

width, height = "", ""
if cfg_path and os.path.isfile(cfg_path):
    try:
        try:
            import tomllib
            with open(cfg_path, "rb") as f:
                d = tomllib.load(f)
            candidates = [
                mode,
                mode.replace("-", "_"),
                mode.replace("toggle-", ""),
                mode.replace("toggle_", ""),
                "default",
                "toggle"
            ]
            for c in candidates:
                if c in d and isinstance(d[c], dict):
                    w = d[c].get("width")
                    h = d[c].get("height")
                    if w and not width: width = str(w)
                    if h and not height: height = str(h)
                    if width and height: break

            if not width:
                width = str(d.get(f"{mode}_width") or d.get(f"{mode.replace('toggle-', '')}_width") or d.get("width") or "")
            if not height:
                height = str(d.get(f"{mode}_height") or d.get(f"{mode.replace('toggle-', '')}_height") or d.get("height") or "")
        except Exception:
            with open(cfg_path, "r", encoding="utf-8", errors="ignore") as f:
                content = f.read()
            sec_patterns = [
                re.escape(mode),
                re.escape(mode.replace("-", "_")),
                re.escape(mode.replace("toggle-", "")),
                re.escape(mode.replace("toggle_", "")),
                "default",
                "toggle"
            ]
            sec_match = re.search(r'\[(?:' + '|'.join(sec_patterns) + r')\](.*?)(?=\n\[|\Z)', content, re.DOTALL)
            if sec_match:
                block = sec_match.group(1)
                w = re.search(r"""width\s*=\s*(?:["\x27]([^"\x27]+)["\x27]|(\d+))""", block)
                h = re.search(r"""height\s*=\s*(?:["\x27]([^"\x27]+)["\x27]|(\d+))""", block)
                if w and not width: width = w.group(1) or w.group(2)
                if h and not height: height = h.group(1) or h.group(2)
            if not width:
                w = re.search(r"""(?m)^(?:""" + re.escape(mode) + r"""_)?width\s*=\s*(?:["\x27]([^"\x27]+)["\x27]|(\d+))""", content)
                if w: width = w.group(1) or w.group(2)
            if not height:
                h = re.search(r"""(?m)^(?:""" + re.escape(mode) + r"""_)?height\s*=\s*(?:["\x27]([^"\x27]+)["\x27]|(\d+))""", content)
                if h: height = h.group(1) or h.group(2)
    except Exception:
        pass

if not width:
    if "tiny" in mode: width = "50%"
    elif "small" in mode: width = "70%"
    else: width = "80%"

if not height:
    if "tiny" in mode: height = "20%"
    elif "small" in mode: height = "30%"
    else: height = "80%"

print(f"{width}\t{height}")
EOF
    else
        if [[ "$mode" == *"tiny"* ]]; then
            printf '50%%\t20%%\n'
        elif [[ "$mode" == *"small"* ]]; then
            printf '70%%\t30%%\n'
        else
            printf '80%%\t80%%\n'
        fi
    fi
}

# Open the popup (herdr focuses it). $1 = entrypoint id (default "panel"); $2 = width;
# $3 = height. Dimensions come from user config, CLI args, or fallback defaults.
# cwd is the focused pane's dir so relative commands run where the user is working.
open_popup() {
    local entrypoint="${1:-panel}" width="${2:-80%}" height="${3:-80%}"
    local cwd_args=() cwd="" out
    if [ -n "${HERDR_PLUGIN_CONTEXT_JSON:-}" ] && command -v jq >/dev/null 2>&1; then
        cwd=$(printf '%s' "$HERDR_PLUGIN_CONTEXT_JSON" \
            | jq -r '.focused_pane_cwd // .workspace_cwd // empty' 2>/dev/null)
        [ -n "${cwd:-}" ] && cwd_args+=(--cwd "$cwd")
    fi

    # Open via socket API with resolved width and height
    if open_popup_socket "$entrypoint" "$cwd" "$width" "$height"; then
        return 0
    fi

    out=$("$H" plugin pane open \
        --plugin nook --entrypoint "$entrypoint" \
        --placement popup \
        "${cwd_args[@]}" --focus 2>&1) \
        || refuse "failed to open popup: $(printf '%s' "$out" | head -c 200)"
}

# One key: dismiss the popup if it is showing, otherwise open it.
# Dismissing only detaches the popup surface; the tmux session keeps running so contents
# persist and the next toggle reattaches. Racelessly driven by popup.close's own report:
# if a popup was open it is now dismissed; if none was open, open ours.
toggle_popup() {
    local entrypoint="${1:-panel}" width="${2:-80%}" height="${3:-80%}"
    case "$(close_popup_surface)" in
        closed)
            printf 'nook: dismissed popup (session still running)\n'
            ;;
        none)
            open_popup "$entrypoint" "$width" "$height"
            printf 'nook: opened popup\n'
            ;;
        *)
            refuse "could not reach herdr popup control (is socat installed?)"
            ;;
    esac
}

WIDTH="${2:-${NOOK_WIDTH:-}}"
HEIGHT="${3:-${NOOK_HEIGHT:-}}"

if [ -z "$WIDTH" ] || [ -z "$HEIGHT" ]; then
    dims=$(resolve_config_dimensions "$MODE")
    if [ -n "$dims" ]; then
        [ -z "$WIDTH" ] && WIDTH=$(printf '%s' "$dims" | cut -f1)
        [ -z "$HEIGHT" ] && HEIGHT=$(printf '%s' "$dims" | cut -f2)
    fi
fi

toggle_popup panel "$WIDTH" "$HEIGHT"
