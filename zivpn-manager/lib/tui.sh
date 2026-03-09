#!/usr/bin/env bash
# =============================================================================
# tui.sh — Pure-bash TUI engine: arrow-key menus, styled confirm dialogs
# Uses alternate screen buffer for flicker-free rendering.
# All visual output goes to /dev/tty so command substitution works correctly.
# No external dependencies (no dialog/whiptail/fzf needed)
# =============================================================================

# --- State -------------------------------------------------------------------
_TUI_ALT_SCREEN=0  # Track if alternate screen buffer is active

# --- Terminal control helpers ------------------------------------------------
_cursor_hide()    { printf '\e[?25l' >/dev/tty 2>/dev/null; }
_cursor_show()    { printf '\e[?25h' >/dev/tty 2>/dev/null; }
_save_cursor()    { printf '\e7'     >/dev/tty 2>/dev/null; }
_restore_cursor() { printf '\e8'     >/dev/tty 2>/dev/null; }

_alt_screen_on() {
    printf '\e[?1049h' >/dev/tty 2>/dev/null
    _TUI_ALT_SCREEN=1
}

_alt_screen_off() {
    if (( _TUI_ALT_SCREEN )); then
        printf '\e[?1049l' >/dev/tty 2>/dev/null
        _TUI_ALT_SCREEN=0
    fi
}

# Ensure terminal is restored on exit/interrupt
_tui_cleanup() {
    _cursor_show
    _alt_screen_off
    stty echo 2>/dev/null
}
trap _tui_cleanup EXIT INT TERM

# ---------------------------------------------------------------------------
# read_key — Read a single keypress, return a normalized key name
# Output (via echo): "UP" "DOWN" "LEFT" "RIGHT" "ENTER" "ESC" "TAB"
#                     "BACKSPACE" or the literal character
# ---------------------------------------------------------------------------
read_key() {
    local key
    IFS= read -rsn1 key 2>/dev/null

    case "$key" in
        $'\x1b')  # Escape sequence
            local seq seq2
            IFS= read -rsn1 -t 0.05 seq 2>/dev/null
            if [[ -z "$seq" ]]; then
                echo "ESC"; return
            fi
            IFS= read -rsn1 -t 0.05 seq2 2>/dev/null
            case "${seq}${seq2}" in
                '[A') echo "UP"    ;;
                '[B') echo "DOWN"  ;;
                '[C') echo "RIGHT" ;;
                '[D') echo "LEFT"  ;;
                '[H') echo "HOME"  ;;
                '[F') echo "END"   ;;
                *)    echo "ESC"   ;;
            esac
            # Flush any remaining escape sequence bytes
            while IFS= read -rsn1 -t 0.01 _ 2>/dev/null; do :; done
            ;;
        '')       echo "ENTER"     ;;
        $'\t')    echo "TAB"       ;;
        $'\x7f')  echo "BACKSPACE" ;;
        $'\x08')  echo "BACKSPACE" ;;
        *)        echo "$key"      ;;
    esac
}

# ---------------------------------------------------------------------------
# tui_menu — Interactive arrow-key menu selector
#
# Usage:
#   local items=("label1|action1" "label2|action2" "-" "label3|action3")
#   result=$(tui_menu "Title" items_array_name [initial_index])
#
# Items format: "Display Label|action_id"
# Use "-" for a separator line (non-selectable)
# Returns (via echo to stdout): the action_id of the selected item
# All visual rendering goes to /dev/tty (not captured by $())
# Returns 1 if no selectable items
#
# Rendering strategy:
#   - Uses alternate screen buffer (clean entry/exit, no leftover on terminal)
#   - Header is rendered once (no network calls per keypress)
#   - Menu items are redrawn via cursor save/restore (no full-screen clear)
#   - Output is buffered for atomic/flicker-free writes
# ---------------------------------------------------------------------------
tui_menu() {
    local title="$1"
    local -n _items=$2
    local current=${3:-0}
    local total=${#_items[@]}

    # Build selectable indices (skip separators)
    local selectable=()
    local i
    for ((i = 0; i < total; i++)); do
        [[ "${_items[$i]}" != "-" ]] && selectable+=("$i")
    done

    local sel_total=${#selectable[@]}
    if ((sel_total == 0)); then echo ""; return 1; fi

    # Find initial position in selectable array
    local sel_idx=0
    for ((i = 0; i < sel_total; i++)); do
        if ((selectable[i] == current)); then
            sel_idx=$i
            break
        fi
    done
    current=${selectable[$sel_idx]}

    # Pre-compute separator strings
    local sep_subtle sep_bottom
    sep_subtle=$(printf '┄%.0s' {1..50})
    sep_bottom=$(printf '─%.0s' {1..56})

    # --- Enter TUI mode ---
    _alt_screen_on
    _cursor_hide
    stty -echo 2>/dev/null

    # --- Render header once ---
    printf '\e[H\e[2J' >/dev/tty

    local host domain host_label total_acc active expired
    domain=$(get_custom_domain)
    if [[ -n "$domain" ]]; then
        host="$domain"
        host_label="Domain   "
    else
        host=$(get_public_ipv4)
        host_label="IP Server"
    fi
    total_acc=$(jq '.accounts | length' "$ACCOUNTS_FILE" 2>/dev/null || echo 0)
    active=$(jq '[.accounts[] | select(.status == "active")] | length' "$ACCOUNTS_FILE" 2>/dev/null || echo 0)
    expired=$(jq '[.accounts[] | select(.status == "expired")] | length' "$ACCOUNTS_FILE" 2>/dev/null || echo 0)

    local ver="v${ZIVPN_MANAGER_VERSION:-1.0}"
    local h_line
    h_line=$(printf '─%.0s' {1..56})

    {
        echo ""
        printf '%b  %b%b%b%b\n' "${RESET}" "\033[38;5;75m" "╭" "$h_line" "╮"
        printf '%b  %b│%56s│%b\n' "${RESET}" "\033[38;5;75m" "" "${RESET}"
        printf '  \033[38;5;75m│\033[0m  \033[1m\033[38;5;117m         ⚡  ZiVPN Account Manager  %-17s\033[0m  \033[38;5;75m│\033[0m\n' "$ver"
        printf '%b  %b│%56s│%b\n' "${RESET}" "\033[38;5;75m" "" "${RESET}"
        printf '%b  %b%b%b%b%b\n' "${RESET}" "\033[38;5;75m" "╰" "$h_line" "╯" "${RESET}"
        echo ""
        printf '%b    %b%b :%b  %b%b%b\n' "${RESET}" "\033[38;5;243m" "$host_label" "${RESET}" "\033[1;37m" "$host" "${RESET}"
        printf '%b    %b%b :%b  %b%b%b  %b│%b  %b●%b %bAktif: %b%b  %b│%b  %b●%b %bExpired: %b%b\n' \
            "${RESET}" "\033[38;5;243m" "Total Akun" "${RESET}" "\033[1;37m" "$total_acc" "${RESET}" \
            "\033[38;5;240m" "${RESET}" "\033[0;32m" "${RESET}" "\033[0;32m" "$active" "${RESET}" \
            "\033[38;5;240m" "${RESET}" "\033[0;31m" "${RESET}" "\033[0;31m" "$expired" "${RESET}"
        echo ""

        # Section title for menu
        local title_len=${#title}
        local title_line_len=$(( 54 - title_len ))
        printf '  \033[38;5;75m──\033[0m \033[1m\033[38;5;75m%s\033[0m \033[38;5;75m%s\033[0m\n' \
            "$title" "$(printf '─%.0s' $(seq 1 $title_line_len))"
        echo ""
        printf '%b    %b↑↓ Pilih  ·  Enter Konfirmasi  ·  Esc Keluar%b\n' "${RESET}" "\033[38;5;240m" "${RESET}"
        echo ""
    } >/dev/tty

    # Save cursor position — menu items start here
    _save_cursor

    while true; do
        _restore_cursor

        # Build entire menu in a buffer for atomic write
        local buf=""
        for ((i = 0; i < total; i++)); do
            local item="${_items[$i]}"
            if [[ "$item" == "-" ]]; then
                buf+="\e[2K    \e[38;5;240m${sep_subtle}\e[0m\n"
            else
                local label="${item%%|*}"
                if ((i == current)); then
                    buf+="\e[2K"
                    buf+=$(printf '    \e[1m\e[48;5;24m\e[38;5;255m  ▸ %-48s\e[0m\n' "$label")
                else
                    buf+="\e[2K\e[38;5;252m      ${label}\e[0m\n"
                fi
            fi
        done
        buf+="\e[2K\n"
        buf+="\e[2K  \e[38;5;243m${sep_bottom}\e[0m\n"
        buf+="\e[J"

        printf '%b' "$buf" >/dev/tty

        local key
        key=$(read_key)

        case "$key" in
            UP)
                ((sel_idx > 0)) && { ((sel_idx--)); current=${selectable[$sel_idx]}; }
                ;;
            DOWN)
                ((sel_idx < sel_total - 1)) && { ((sel_idx++)); current=${selectable[$sel_idx]}; }
                ;;
            HOME)
                sel_idx=0
                current=${selectable[$sel_idx]}
                ;;
            END)
                sel_idx=$((sel_total - 1))
                current=${selectable[$sel_idx]}
                ;;
            TAB)
                sel_idx=$(( (sel_idx + 1) % sel_total ))
                current=${selectable[$sel_idx]}
                ;;
            ENTER)
                _alt_screen_off
                _cursor_show
                stty echo 2>/dev/null
                local selected="${_items[$current]}"
                echo "${selected#*|}"
                return 0
                ;;
            ESC)
                _alt_screen_off
                _cursor_show
                stty echo 2>/dev/null
                echo "__exit__"
                return 0
                ;;
        esac
    done
}

# ---------------------------------------------------------------------------
# tui_confirm — Yes/No dialog with arrow-key navigation
#
# Usage:
#   tui_confirm "Are you sure?" && echo "yes" || echo "no"
#
# Returns 0 for Yes, 1 for No
# All rendering goes to /dev/tty
# ---------------------------------------------------------------------------
tui_confirm() {
    local message="$1"
    local selected=1  # 0=Yes, 1=No (default No for safety)

    _cursor_hide

    while true; do
        local yes_style no_style
        if ((selected == 0)); then
            yes_style="\e[1m\e[48;5;22m\e[38;5;255m"  # Bold, dark green bg, white
            no_style="\e[38;5;243m"
        else
            yes_style="\e[38;5;243m"
            no_style="\e[1m\e[48;5;52m\e[38;5;255m"    # Bold, dark red bg, white
        fi

        {
            printf '\r\e[2K'
            printf '  \e[1;33m▸ %s\e[0m  ' "$message"
            printf '%b  Ya  \e[0m  ' "$yes_style"
            printf '%b  Tidak  \e[0m ' "$no_style"
            printf '  \e[38;5;240m(←→ pilih, Enter konfirmasi)\e[0m'
        } >/dev/tty

        local key
        key=$(read_key)

        case "$key" in
            LEFT|RIGHT|TAB)
                selected=$(( selected ^ 1 ))
                ;;
            ENTER)
                _cursor_show
                echo "" >/dev/tty
                return "$selected"
                ;;
            ESC|'n'|'N')
                _cursor_show
                echo "" >/dev/tty
                return 1
                ;;
            'y'|'Y')
                _cursor_show
                echo "" >/dev/tty
                return 0
                ;;
        esac
    done
}
