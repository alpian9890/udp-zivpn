#!/usr/bin/env bash
# =============================================================================
# tui.sh — Pure-bash TUI engine: arrow-key menus, styled confirm dialogs
# No external dependencies (no dialog/whiptail/fzf needed)
# =============================================================================

# --- Terminal control helpers ------------------------------------------------

# Hide/show cursor
_cursor_hide() { printf '\e[?25l'; }
_cursor_show() { printf '\e[?25h'; }

# Move cursor up N lines
_cursor_up() { printf '\e[%dA' "${1:-1}"; }

# Clear from cursor to end of line
_clear_line() { printf '\e[2K\r'; }

# Ensure cursor is restored on exit/interrupt
_tui_cleanup() {
    _cursor_show
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
            local seq
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
#   tui_menu "Title" items_array_name [initial_index]
#
# Items format: "Display Label|action_id"
# Use "-" for a separator line (non-selectable)
# Returns (via echo): the action_id of the selected item
# Returns 1 if user pressed ESC (cancelled)
# ---------------------------------------------------------------------------
tui_menu() {
    local title="$1"
    local -n _items=$2
    local current=${3:-0}
    local total=${#_items[@]}

    # Build selectable indices (skip separators)
    local selectable=()
    local i
    for i in $(seq 0 $((total - 1))); do
        [[ "${_items[$i]}" != "-" ]] && selectable+=("$i")
    done

    local sel_total=${#selectable[@]}
    if [[ "$sel_total" -eq 0 ]]; then
        echo ""; return 1
    fi

    # Find initial position in selectable array
    local sel_idx=0
    for i in $(seq 0 $((sel_total - 1))); do
        if [[ "${selectable[$i]}" -eq "$current" ]]; then
            sel_idx=$i
            break
        fi
    done
    current=${selectable[$sel_idx]}

    _cursor_hide

    while true; do
        # Render header
        print_header
        echo -e "${BOLD}  ${title}${RESET}"
        echo ""
        echo -e "  ${GRAY}Gunakan ↑↓ untuk memilih, Enter untuk konfirmasi, ESC untuk keluar${RESET}"
        echo ""

        # Render menu items
        for i in $(seq 0 $((total - 1))); do
            local item="${_items[$i]}"

            if [[ "$item" == "-" ]]; then
                echo -e "  ${GRAY}$(printf '─%.0s' {1..50})${RESET}"
                continue
            fi

            local label="${item%%|*}"
            local icon color prefix

            if [[ "$i" -eq "$current" ]]; then
                # Selected / highlighted item
                color="\e[0;30;46m"  # Black text on cyan background
                prefix=" ▸ "
                printf "  ${color}${prefix}%-48s\e[0m\n" "$label"
            else
                prefix="   "
                echo -e "  ${prefix}${label}"
            fi
        done

        echo ""
        divider

        # Read key
        local key
        key=$(read_key)

        case "$key" in
            UP)
                if [[ "$sel_idx" -gt 0 ]]; then
                    sel_idx=$((sel_idx - 1))
                    current=${selectable[$sel_idx]}
                fi
                ;;
            DOWN)
                if [[ "$sel_idx" -lt $((sel_total - 1)) ]]; then
                    sel_idx=$((sel_idx + 1))
                    current=${selectable[$sel_idx]}
                fi
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
                # Tab cycles forward
                sel_idx=$(( (sel_idx + 1) % sel_total ))
                current=${selectable[$sel_idx]}
                ;;
            ENTER)
                _cursor_show
                local selected="${_items[$current]}"
                local action="${selected#*|}"
                echo "$action"
                return 0
                ;;
            ESC)
                _cursor_show
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
# ---------------------------------------------------------------------------
tui_confirm() {
    local message="$1"
    local selected=1  # 0=Yes, 1=No (default No for safety)

    _cursor_hide

    while true; do
        local yes_style no_style
        if [[ "$selected" -eq 0 ]]; then
            yes_style="\e[0;30;42m"  # Black on green
            no_style="${GRAY}"
        else
            yes_style="${GRAY}"
            no_style="\e[0;30;41m"   # Black on red
        fi

        # Render on single line (overwrite previous)
        printf "\r\e[2K"
        printf "  ${YELLOW}%s${RESET}  " "$message"
        printf "${yes_style} Ya ${RESET}  "
        printf "${no_style} Tidak ${RESET} "
        printf "  ${GRAY}(←→ pilih, Enter konfirmasi)${RESET}"

        local key
        key=$(read_key)

        case "$key" in
            LEFT|RIGHT|TAB)
                selected=$(( selected ^ 1 ))
                ;;
            ENTER)
                _cursor_show
                echo ""
                return "$selected"
                ;;
            ESC|'n'|'N')
                _cursor_show
                echo ""
                return 1
                ;;
            'y'|'Y')
                _cursor_show
                echo ""
                return 0
                ;;
        esac
    done
}
