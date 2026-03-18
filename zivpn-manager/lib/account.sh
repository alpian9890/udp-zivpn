#!/usr/bin/env bash
# =============================================================================
# account.sh — Account management: add, delete, list, expire, extend, trial
# =============================================================================

# Initialize accounts.json if it doesn't exist
init_accounts_file() {
    if [[ ! -f "$ACCOUNTS_FILE" ]]; then
        echo '{"accounts":[]}' > "$ACCOUNTS_FILE"
        chmod 600 "$ACCOUNTS_FILE"
        print_info "File akun baru dibuat: $ACCOUNTS_FILE"
    fi
}

# Check if username already exists
username_exists() {
    local username="$1"
    local count
    count=$(jq --arg u "$username" '[.accounts[] | select(.username == $u)] | length' "$ACCOUNTS_FILE")
    [[ "$count" -gt 0 ]]
}

# Check if password already used by another account
password_exists() {
    local password="$1"
    local count
    count=$(jq --arg p "$password" '[.accounts[] | select(.password == $p)] | length' "$ACCOUNTS_FILE")
    [[ "$count" -gt 0 ]]
}

# ---------------------------------------------------------------------------
# list_accounts — Display all accounts in a formatted table
# ---------------------------------------------------------------------------
list_accounts() {
    print_header
    echo ""
    section_title "Daftar Akun ZiVPN"
    echo ""

    local total
    total=$(jq '.accounts | length' "$ACCOUNTS_FILE")

    if [[ "$total" -eq 0 ]]; then
        print_info "Belum ada akun. Tambahkan akun baru dari menu."
        wait_for_esc
        return
    fi

    # Table header
    printf "  ${FG_DIM}┌──────┬──────────────────┬────────────────┬────────────┬────────────────────────┬──────────┐${RESET}\n"
    printf "  ${FG_DIM}│${RESET} ${BOLD}%-4s${RESET} ${FG_DIM}│${RESET} ${BOLD}%-16s${RESET} ${FG_DIM}│${RESET} ${BOLD}%-14s${RESET} ${FG_DIM}│${RESET} ${BOLD}%-10s${RESET} ${FG_DIM}│${RESET} ${BOLD}%-22s${RESET} ${FG_DIM}│${RESET} ${BOLD}%-8s${RESET} ${FG_DIM}│${RESET}\n" \
        "No" "Username" "Password" "Status" "Expired At" "Sisa"
    printf "  ${FG_DIM}├──────┼──────────────────┼────────────────┼────────────┼────────────────────────┼──────────┤${RESET}\n"

    local i=0
    while IFS= read -r acc; do
        i=$((i + 1))
        local username password status expired_at trial
        username=$(echo "$acc"  | jq -r '.username')
        password=$(echo "$acc"  | jq -r '.password')
        status=$(echo "$acc"    | jq -r '.status')
        expired_at=$(echo "$acc"| jq -r '.expired_at')
        trial=$(echo "$acc"     | jq -r '.trial')

        local sisa
        sisa=$(days_remaining "$expired_at")

        local expired_fmt
        expired_fmt=$(format_date "$expired_at")

        # Color based on status
        local color="$RESET"
        local status_label="$status"
        case "$status" in
            active)
                if [[ "$trial" == "true" ]]; then
                    color="$YELLOW"; status_label="trial"
                else
                    color="$GREEN";  status_label="aktif"
                fi
                ;;
            expired)  color="$RED";  status_label="expired" ;;
            disabled) color="$GRAY"; status_label="nonaktif" ;;
        esac

        # Sisa hari color
        local sisa_colored="$sisa hari"
        if [[ "$expired_at" == "null" || -z "$expired_at" ]]; then
            sisa_colored="${CYAN}Permanent${RESET}"
        elif [[ "$sisa" =~ ^-?[0-9]+$ ]] && (( sisa <= 0 )); then
            sisa_colored="${RED}Expired${RESET}"
        elif [[ "$sisa" =~ ^[0-9]+$ ]] && (( sisa <= 3 )); then
            sisa_colored="${YELLOW}${sisa} hari${RESET}"
        else
            sisa_colored="${GREEN}${sisa} hari${RESET}"
        fi

        printf "  ${FG_DIM}│${RESET} ${FG_DIM}%-4s${RESET} ${FG_DIM}│${RESET} %-16s ${FG_DIM}│${RESET} ${CYAN}%-14s${RESET} ${FG_DIM}│${RESET} ${color}%-10s${RESET} ${FG_DIM}│${RESET} %-22s ${FG_DIM}│${RESET} %b ${FG_DIM}│${RESET}\n" \
            "$i" "$username" "$password" "$status_label" "$expired_fmt" "$sisa_colored"

    done < <(jq -c '.accounts[]' "$ACCOUNTS_FILE")

    printf "  ${FG_DIM}└──────┴──────────────────┴────────────────┴────────────┴────────────────────────┴──────────┘${RESET}\n"

    local active trial_count expired_count
    active=$(jq '[.accounts[] | select(.status == "active" and .trial == false)] | length' "$ACCOUNTS_FILE")
    trial_count=$(jq '[.accounts[] | select(.status == "active" and .trial == true)] | length' "$ACCOUNTS_FILE")
    expired_count=$(jq '[.accounts[] | select(.status == "expired")] | length' "$ACCOUNTS_FILE")

    echo ""
    echo -e "    Total: ${WHITE}${total}${RESET}  ${FG_SUBTLE}│${RESET}  $(badge "Aktif: ${active}" "$GREEN")  ${FG_SUBTLE}│${RESET}  $(badge "Trial: ${trial_count}" "$YELLOW")  ${FG_SUBTLE}│${RESET}  $(badge "Expired: ${expired_count}" "$RED")"
    echo ""
    wait_for_esc
}

# ---------------------------------------------------------------------------
# add_account — Add a new regular account
# ---------------------------------------------------------------------------
add_account() {
    print_header
    echo ""
    section_title "Tambah Akun Baru"
    echo ""

    # Username
    local username
    while true; do
        echo -en "    ${FG_DIM}Username${RESET} ${FG_SUBTLE}(3-32 karakter):${RESET} "
        read -r username
        username=$(echo "$username" | tr -d ' ')
        validate_username "$username" || continue
        if username_exists "$username"; then
            print_error "Username '$username' sudah digunakan"
            continue
        fi
        break
    done

    # Password
    local password
    local auto_pw
    auto_pw=$(generate_password 10)
    echo -en "    ${FG_DIM}Password${RESET} ${FG_SUBTLE}[Enter = auto: ${CYAN}${auto_pw}${RESET}${FG_SUBTLE}]:${RESET} "
    read -r password
    if [[ -z "$password" ]]; then
        password="$auto_pw"
    fi
    if password_exists "$password"; then
        print_warn "Password sudah digunakan akun lain. Menggunakan password yang sama tetap diizinkan."
    fi

    # Duration
    local days
    while true; do
        echo -en "    ${FG_DIM}Durasi${RESET} ${FG_SUBTLE}(hari) [Enter = 30]:${RESET} "
        read -r days
        if [[ -z "$days" ]]; then
            days=30
            break
        fi
        validate_days "$days" && break
    done

    local expired_at
    expired_at=$(date_add_days "$days")
    local created_at
    created_at=$(now_iso)

    echo ""
    divider "subtle"
    echo -e "    ${BOLD}Konfirmasi:${RESET}"
    echo -e "    ${FG_DIM}Username  :${RESET}  ${WHITE}${username}${RESET}"
    echo -e "    ${FG_DIM}Password  :${RESET}  ${CYAN}${password}${RESET}"
    echo -e "    ${FG_DIM}Expired   :${RESET}  ${YELLOW}$(format_date "$expired_at")${RESET}"
    divider "subtle"
    echo ""

    confirm "  Simpan akun ini?" || { print_warn "Dibatalkan."; wait_for_esc; return; }

    # Write to accounts.json
    local new_entry
    new_entry=$(jq -n \
        --arg u  "$username" \
        --arg pw "$password" \
        --arg ca "$created_at" \
        --arg ea "$expired_at" \
        '{username: $u, password: $pw, created_at: $ca, expired_at: $ea,
          status: "active", trial: false, note: ""}')

    modify_accounts_json --argjson entry "$new_entry" '.accounts += [$entry]'

    sync_config

    echo ""
    print_success "Akun '${username}' berhasil ditambahkan!"
    echo ""
    echo -e "    ${BOLD}Info akun untuk diberikan ke pengguna:${RESET}"
    echo ""
    box_top
    box_line "${FG_DIM}Host     :${RESET}  ${CYAN}$(get_server_host)${RESET}"
    box_line "${FG_DIM}Port     :${RESET}  ${WHITE}6000-19999 (UDP)${RESET}"
    box_divider
    box_line "${FG_DIM}Username :${RESET}  ${WHITE}${username}${RESET}"
    box_line "${FG_DIM}Password :${RESET}  ${CYAN}${password}${RESET}"
    box_divider
    box_line "${FG_DIM}Dibuat   :${RESET}  ${FG_SUBTLE}$(format_date "$created_at")${RESET}"
    box_line "${FG_DIM}Expired  :${RESET}  ${YELLOW}$(format_date "$expired_at")${RESET}"
    box_bottom
    wait_for_esc
}

# ---------------------------------------------------------------------------
# delete_account — Remove an account
# ---------------------------------------------------------------------------
delete_account() {
    print_header
    echo ""
    section_title "Hapus Akun"
    echo ""

    local total
    total=$(jq '.accounts | length' "$ACCOUNTS_FILE")
    if [[ "$total" -eq 0 ]]; then
        print_info "Belum ada akun."
        wait_for_esc
        return
    fi

    local account_items=()
    while IFS= read -r acc; do
        local u s ea
        u=$(echo "$acc" | jq -r '.username')
        s=$(echo "$acc" | jq -r '.status')
        ea=$(echo "$acc" | jq -r '.expired_at')
        account_items+=("${u}  (${s}, $(format_date "$ea"))|${u}")
    done < <(jq -c '.accounts[]' "$ACCOUNTS_FILE")

    local username
    username=$(tui_menu "Pilih Akun yang akan Dihapus" account_items)
    if [[ "$username" == "__exit__" || -z "$username" ]]; then
        return
    fi

    # Re-print header because TUI cleared it
    print_header
    echo ""
    section_title "Hapus Akun"
    echo ""
    echo -e "    ${FG_DIM}Akun terpilih:${RESET} ${WHITE}${username}${RESET}"

    echo ""
    confirm "  Hapus akun '${username}'? Aksi ini tidak bisa dibatalkan." || {
        print_warn "Dibatalkan."
        wait_for_esc
        return
    }

    modify_accounts_json --arg u "$username" 'del(.accounts[] | select(.username == $u))'

    sync_config

    print_success "Akun '${username}' berhasil dihapus!"
    wait_for_esc
}

# ---------------------------------------------------------------------------
# set_expired_account — Set a specific expiry date for an account
# ---------------------------------------------------------------------------
set_expired_account() {
    print_header
    echo ""
    section_title "Set Tanggal Expired Akun"
    echo ""

    local total
    total=$(jq '.accounts | length' "$ACCOUNTS_FILE")
    if [[ "$total" -eq 0 ]]; then
        print_info "Belum ada akun."
        wait_for_esc
        return
    fi

    local account_items=()
    while IFS= read -r acc; do
        local u s ea
        u=$(echo "$acc" | jq -r '.username')
        s=$(echo "$acc" | jq -r '.status')
        ea=$(echo "$acc" | jq -r '.expired_at')
        account_items+=("${u}  (${s}, $(format_date "$ea"))|${u}")
    done < <(jq -c '.accounts[]' "$ACCOUNTS_FILE")

    local username
    username=$(tui_menu "Pilih Akun (Set Expired)" account_items)
    if [[ "$username" == "__exit__" || -z "$username" ]]; then
        return
    fi

    print_header
    echo ""
    section_title "Set Tanggal Expired Akun"
    echo ""
    echo -e "    ${FG_DIM}Akun terpilih:${RESET} ${WHITE}${username}${RESET}"

    local datestr
    while true; do
        echo -en "    ${FG_DIM}Tanggal expired baru${RESET} ${FG_SUBTLE}(YYYY-MM-DD):${RESET} "
        read -r datestr
        validate_date "$datestr" && break
    done

    local expired_at
    expired_at=$(date -u -d "$datestr" +"%Y-%m-%dT%H:%M:%SZ")

    modify_accounts_json --arg u "$username" --arg ea "$expired_at" \
        '(.accounts[] | select(.username == $u)) |= (.expired_at = $ea | .status = "active")'

    sync_config

    print_success "Expired akun '${username}' diset ke $(format_date "$expired_at")"
    wait_for_esc
}

# ---------------------------------------------------------------------------
# extend_account — Extend account by N days
# ---------------------------------------------------------------------------
extend_account() {
    print_header
    echo ""
    section_title "Perpanjang Akun"
    echo ""

    local total
    total=$(jq '.accounts | length' "$ACCOUNTS_FILE")
    if [[ "$total" -eq 0 ]]; then
        print_info "Belum ada akun."
        wait_for_esc
        return
    fi

    local account_items=()
    while IFS= read -r acc; do
        local u s ea
        u=$(echo "$acc" | jq -r '.username')
        s=$(echo "$acc" | jq -r '.status')
        ea=$(echo "$acc" | jq -r '.expired_at')
        account_items+=("${u}  (${s}, $(format_date "$ea"))|${u}")
    done < <(jq -c '.accounts[]' "$ACCOUNTS_FILE")

    local username
    username=$(tui_menu "Pilih Akun (Perpanjang)" account_items)
    if [[ "$username" == "__exit__" || -z "$username" ]]; then
        return
    fi

    print_header
    echo ""
    section_title "Perpanjang Akun"
    echo ""
    echo -e "    ${FG_DIM}Akun terpilih:${RESET} ${WHITE}${username}${RESET}"

    local days
    while true; do
        echo -en "    ${FG_DIM}Tambah berapa hari${RESET} ${FG_SUBTLE}[Enter = 30]:${RESET} "
        read -r days
        if [[ -z "$days" ]]; then days=30; break; fi
        validate_days "$days" && break
    done

    # Get current expired_at
    local current_exp
    current_exp=$(jq -r --arg u "$username" '.accounts[] | select(.username == $u) | .expired_at' "$ACCOUNTS_FILE")

    local new_exp
    # If already expired or null, extend from NOW
    if [[ -z "$current_exp" || "$current_exp" == "null" ]] || is_expired "$current_exp"; then
        new_exp=$(date_add_days "$days")
    else
        # Extend from current expired_at
        new_exp=$(date -u -d "$current_exp + ${days} days" +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null)
        if [[ -z "$new_exp" ]]; then
            new_exp=$(date_add_days "$days")
        fi
    fi

    modify_accounts_json --arg u "$username" --arg ea "$new_exp" \
        '(.accounts[] | select(.username == $u)) |= (.expired_at = $ea | .status = "active" | .trial = false)'

    sync_config

    print_success "Akun '${username}' diperpanjang hingga $(format_date "$new_exp")"
    wait_for_esc
}

# ---------------------------------------------------------------------------
# create_trial_account — Create a short-duration trial account
# ---------------------------------------------------------------------------
create_trial_account() {
    print_header
    echo ""
    section_title "Buat Akun Trial"
    echo ""

    # Username
    local username
    while true; do
        echo -en "    ${FG_DIM}Username untuk trial:${RESET} "
        read -r username
        username=$(echo "$username" | tr -d ' ')
        validate_username "$username" || continue
        if username_exists "$username"; then
            print_error "Username '$username' sudah digunakan"
            continue
        fi
        break
    done

    # Trial duration (default 1 day)
    local days
    while true; do
        echo -en "    ${FG_DIM}Durasi trial${RESET} ${FG_SUBTLE}(hari) [Enter = 1]:${RESET} "
        read -r days
        if [[ -z "$days" ]]; then days=1; break; fi
        validate_days "$days" && break
    done

    local password
    password=$(generate_password 8)
    local created_at expired_at
    created_at=$(now_iso)
    expired_at=$(date_add_days "$days")

    echo ""
    divider "subtle"
    echo -e "    ${BOLD}Info Akun Trial:${RESET}"
    echo -e "    ${FG_DIM}Username  :${RESET}  ${WHITE}${username}${RESET}"
    echo -e "    ${FG_DIM}Password  :${RESET}  ${CYAN}${password}${RESET}"
    echo -e "    ${FG_DIM}Expired   :${RESET}  ${YELLOW}$(format_date "$expired_at")${RESET} (${days} hari)"
    divider "subtle"
    echo ""

    confirm "  Buat akun trial ini?" || { print_warn "Dibatalkan."; wait_for_esc; return; }

    local new_entry
    new_entry=$(jq -n \
        --arg u  "$username" \
        --arg pw "$password" \
        --arg ca "$created_at" \
        --arg ea "$expired_at" \
        '{username: $u, password: $pw, created_at: $ca, expired_at: $ea,
          status: "active", trial: true, note: "trial"}')

    modify_accounts_json --argjson entry "$new_entry" '.accounts += [$entry]'

    sync_config

    echo ""
    print_success "Akun trial '${username}' berhasil dibuat!"
    echo ""
    echo -e "    ${BOLD}Info akun trial untuk diberikan ke pengguna:${RESET}"
    echo ""
    box_top
    box_line "${FG_DIM}Host     :${RESET}  ${CYAN}$(get_server_host)${RESET}"
    box_line "${FG_DIM}Port     :${RESET}  ${WHITE}6000-19999 (UDP)${RESET}"
    box_divider
    box_line "${FG_DIM}Username :${RESET}  ${WHITE}${username}${RESET}"
    box_line "${FG_DIM}Password :${RESET}  ${CYAN}${password}${RESET}"
    box_divider
    box_line "${FG_DIM}Dibuat   :${RESET}  ${FG_SUBTLE}$(format_date "$created_at")${RESET}"
    box_line "${FG_DIM}Expired  :${RESET}  ${YELLOW}$(format_date "$expired_at")${RESET} (${days} hari)"
    box_bottom
    wait_for_esc
}

# ---------------------------------------------------------------------------
# expire_checker — Called by cron: mark overdue accounts as expired
# ---------------------------------------------------------------------------
expire_checker() {
    local now_iso
    now_iso=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    local to_expire
    to_expire=$(jq --arg now "$now_iso" '[.accounts[] | select(.status == "active" and .expired_at != null and .expired_at != "" and .expired_at <= $now)] | length' "$ACCOUNTS_FILE" 2>/dev/null || echo 0)

    if [[ "$to_expire" -gt 0 ]]; then
        modify_accounts_json --arg now "$now_iso" '
            .accounts |= map(
                if .status == "active" and .expired_at != null and .expired_at != "" and .expired_at <= $now then
                    .status = "expired"
                else
                    .
                end
            )
        '
        sync_config > /dev/null 2>&1
    fi
}

# ---------------------------------------------------------------------------
# list_accounts_inline — Compact list for use inside other menus
# ---------------------------------------------------------------------------
list_accounts_inline() {
    local total
    total=$(jq '.accounts | length' "$ACCOUNTS_FILE")

    if [[ "$total" -eq 0 ]]; then
        return
    fi

    printf "    ${FG_DIM}%-4s${RESET} ${BOLD}%-16s${RESET} ${BOLD}%-14s${RESET} ${BOLD}%-10s${RESET} ${BOLD}%-22s${RESET}\n" \
        "No" "Username" "Password" "Status" "Expired At"
    divider "subtle"

    local i=0
    while IFS= read -r acc; do
        i=$((i + 1))
        local username password status expired_at
        username=$(echo "$acc"   | jq -r '.username')
        password=$(echo "$acc"   | jq -r '.password')
        status=$(echo "$acc"     | jq -r '.status')
        expired_at=$(echo "$acc" | jq -r '.expired_at')

        local color="$RESET"
        case "$status" in
            active)  color="$GREEN" ;;
            expired) color="$RED"   ;;
            disabled)color="$GRAY"  ;;
        esac

        printf "    ${FG_DIM}%-4s${RESET} %-16s ${CYAN}%-14s${RESET} ${color}%-10s${RESET} %-22s\n" \
            "$i" "$username" "$password" "$status" "$(format_date "$expired_at")"
    done < <(jq -c '.accounts[]' "$ACCOUNTS_FILE")

    divider "subtle"
    echo ""
}
