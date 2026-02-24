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
    echo -e "${BOLD}  Daftar Akun ZiVPN${RESET}"
    echo ""

    local total
    total=$(jq '.accounts | length' "$ACCOUNTS_FILE")

    if [[ "$total" -eq 0 ]]; then
        print_info "Belum ada akun. Tambahkan akun baru dari menu."
        press_enter
        return
    fi

    # Table header
    printf "  ${BOLD}%-4s %-16s %-14s %-10s %-22s %-8s${RESET}\n" \
        "No" "Username" "Password" "Status" "Expired At" "Sisa"

    divider

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

        printf "  ${GRAY}%-4s${RESET} %-16s ${CYAN}%-14s${RESET} ${color}%-10s${RESET} %-22s %b\n" \
            "$i" "$username" "$password" "$status_label" "$expired_fmt" "$sisa_colored"

    done < <(jq -c '.accounts[]' "$ACCOUNTS_FILE")

    divider

    local active trial_count expired_count
    active=$(jq '[.accounts[] | select(.status == "active" and .trial == false)] | length' "$ACCOUNTS_FILE")
    trial_count=$(jq '[.accounts[] | select(.status == "active" and .trial == true)] | length' "$ACCOUNTS_FILE")
    expired_count=$(jq '[.accounts[] | select(.status == "expired")] | length' "$ACCOUNTS_FILE")

    echo -e "  Total: ${WHITE}${total}${RESET}  |  Aktif: ${GREEN}${active}${RESET}  |  Trial: ${YELLOW}${trial_count}${RESET}  |  Expired: ${RED}${expired_count}${RESET}"
    echo ""
    press_enter
}

# ---------------------------------------------------------------------------
# add_account — Add a new regular account
# ---------------------------------------------------------------------------
add_account() {
    print_header
    echo -e "${BOLD}  Tambah Akun Baru${RESET}"
    echo ""

    # Username
    local username
    while true; do
        echo -en "  Username (3-32 karakter): "
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
    echo -en "  Password [Enter = auto: ${CYAN}${auto_pw}${RESET}]: "
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
        echo -en "  Durasi (hari) [Enter = 30]: "
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
    echo -e "  ${BOLD}Konfirmasi:${RESET}"
    echo -e "  Username  : ${WHITE}${username}${RESET}"
    echo -e "  Password  : ${CYAN}${password}${RESET}"
    echo -e "  Expired   : ${YELLOW}$(format_date "$expired_at")${RESET}"
    echo ""

    confirm "  Simpan akun ini?" || { print_warn "Dibatalkan."; press_enter; return; }

    # Write to accounts.json
    local new_entry
    new_entry=$(jq -n \
        --arg u  "$username" \
        --arg pw "$password" \
        --arg ca "$created_at" \
        --arg ea "$expired_at" \
        '{username: $u, password: $pw, created_at: $ca, expired_at: $ea,
          status: "active", trial: false, note: ""}')

    local tmp
    tmp=$(mktemp)
    jq --argjson entry "$new_entry" '.accounts += [$entry]' "$ACCOUNTS_FILE" > "$tmp" && mv "$tmp" "$ACCOUNTS_FILE"

    sync_config

    echo ""
    print_success "Akun '${username}' berhasil ditambahkan!"
    press_enter
}

# ---------------------------------------------------------------------------
# delete_account — Remove an account
# ---------------------------------------------------------------------------
delete_account() {
    print_header
    echo -e "${BOLD}  Hapus Akun${RESET}"
    echo ""

    local total
    total=$(jq '.accounts | length' "$ACCOUNTS_FILE")
    if [[ "$total" -eq 0 ]]; then
        print_info "Belum ada akun."
        press_enter
        return
    fi

    # Show list first
    list_accounts_inline

    local username
    echo -en "  Username yang akan dihapus: "
    read -r username
    username=$(echo "$username" | tr -d ' ')

    if ! username_exists "$username"; then
        print_error "Akun '$username' tidak ditemukan"
        press_enter
        return
    fi

    echo ""
    confirm "  Hapus akun '${username}'? Aksi ini tidak bisa dibatalkan." || {
        print_warn "Dibatalkan."
        press_enter
        return
    }

    local tmp
    tmp=$(mktemp)
    jq --arg u "$username" 'del(.accounts[] | select(.username == $u))' "$ACCOUNTS_FILE" > "$tmp" && mv "$tmp" "$ACCOUNTS_FILE"

    sync_config

    print_success "Akun '${username}' berhasil dihapus!"
    press_enter
}

# ---------------------------------------------------------------------------
# set_expired_account — Set a specific expiry date for an account
# ---------------------------------------------------------------------------
set_expired_account() {
    print_header
    echo -e "${BOLD}  Set Tanggal Expired Akun${RESET}"
    echo ""

    list_accounts_inline

    local username
    echo -en "  Username: "
    read -r username
    username=$(echo "$username" | tr -d ' ')

    if ! username_exists "$username"; then
        print_error "Akun '$username' tidak ditemukan"
        press_enter
        return
    fi

    local datestr
    while true; do
        echo -en "  Tanggal expired baru (YYYY-MM-DD): "
        read -r datestr
        validate_date "$datestr" && break
    done

    local expired_at
    expired_at=$(date -u -d "$datestr" +"%Y-%m-%dT%H:%M:%SZ")

    local tmp
    tmp=$(mktemp)
    jq --arg u "$username" --arg ea "$expired_at" \
        '(.accounts[] | select(.username == $u)) |= (.expired_at = $ea | .status = "active")' \
        "$ACCOUNTS_FILE" > "$tmp" && mv "$tmp" "$ACCOUNTS_FILE"

    sync_config

    print_success "Expired akun '${username}' diset ke $(format_date "$expired_at")"
    press_enter
}

# ---------------------------------------------------------------------------
# extend_account — Extend account by N days
# ---------------------------------------------------------------------------
extend_account() {
    print_header
    echo -e "${BOLD}  Perpanjang Akun${RESET}"
    echo ""

    list_accounts_inline

    local username
    echo -en "  Username: "
    read -r username
    username=$(echo "$username" | tr -d ' ')

    if ! username_exists "$username"; then
        print_error "Akun '$username' tidak ditemukan"
        press_enter
        return
    fi

    local days
    while true; do
        echo -en "  Tambah berapa hari [Enter = 30]: "
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

    local tmp
    tmp=$(mktemp)
    jq --arg u "$username" --arg ea "$new_exp" \
        '(.accounts[] | select(.username == $u)) |= (.expired_at = $ea | .status = "active" | .trial = false)' \
        "$ACCOUNTS_FILE" > "$tmp" && mv "$tmp" "$ACCOUNTS_FILE"

    sync_config

    print_success "Akun '${username}' diperpanjang hingga $(format_date "$new_exp")"
    press_enter
}

# ---------------------------------------------------------------------------
# create_trial_account — Create a short-duration trial account
# ---------------------------------------------------------------------------
create_trial_account() {
    print_header
    echo -e "${BOLD}  Buat Akun Trial${RESET}"
    echo ""

    # Username
    local username
    while true; do
        echo -en "  Username untuk trial: "
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
        echo -en "  Durasi trial (hari) [Enter = 1]: "
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
    echo -e "  ${BOLD}Info Akun Trial:${RESET}"
    echo -e "  Username  : ${WHITE}${username}${RESET}"
    echo -e "  Password  : ${CYAN}${password}${RESET}"
    echo -e "  Expired   : ${YELLOW}$(format_date "$expired_at")${RESET} (${days} hari)"
    echo ""

    confirm "  Buat akun trial ini?" || { print_warn "Dibatalkan."; press_enter; return; }

    local new_entry
    new_entry=$(jq -n \
        --arg u  "$username" \
        --arg pw "$password" \
        --arg ca "$created_at" \
        --arg ea "$expired_at" \
        '{username: $u, password: $pw, created_at: $ca, expired_at: $ea,
          status: "active", trial: true, note: "trial"}')

    local tmp
    tmp=$(mktemp)
    jq --argjson entry "$new_entry" '.accounts += [$entry]' "$ACCOUNTS_FILE" > "$tmp" && mv "$tmp" "$ACCOUNTS_FILE"

    sync_config

    echo ""
    print_success "Akun trial '${username}' berhasil dibuat!"
    echo ""
    echo -e "  ${BOLD}Bagikan info berikut ke pengguna:${RESET}"
    echo -e "  ┌─────────────────────────────────────┐"
    echo -e "  │  Username : ${CYAN}${username}${RESET}"
    echo -e "  │  Password : ${CYAN}${password}${RESET}"
    echo -e "  │  Expired  : ${YELLOW}$(format_date "$expired_at")${RESET}"
    echo -e "  └─────────────────────────────────────┘"
    press_enter
}

# ---------------------------------------------------------------------------
# expire_checker — Called by cron: mark overdue accounts as expired
# ---------------------------------------------------------------------------
expire_checker() {
    local changed=0
    local now_epoch
    now_epoch=$(date -u +%s)

    while IFS= read -r acc; do
        local username status expired_at exp_epoch
        username=$(echo "$acc"   | jq -r '.username')
        status=$(echo "$acc"     | jq -r '.status')
        expired_at=$(echo "$acc" | jq -r '.expired_at')

        [[ "$status" != "active" ]] && continue
        [[ -z "$expired_at" || "$expired_at" == "null" ]] && continue

        exp_epoch=$(date -u -d "$expired_at" +%s 2>/dev/null) || continue

        if (( exp_epoch <= now_epoch )); then
            local tmp
            tmp=$(mktemp)
            jq --arg u "$username" \
                '(.accounts[] | select(.username == $u)) |= (.status = "expired")' \
                "$ACCOUNTS_FILE" > "$tmp" && mv "$tmp" "$ACCOUNTS_FILE"
            changed=1
        fi
    done < <(jq -c '.accounts[]' "$ACCOUNTS_FILE")

    if [[ "$changed" -eq 1 ]]; then
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

    printf "  ${GRAY}%-4s %-16s %-14s %-10s %-22s${RESET}\n" \
        "No" "Username" "Password" "Status" "Expired At"
    divider

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

        printf "  ${GRAY}%-4s${RESET} %-16s ${CYAN}%-14s${RESET} ${color}%-10s${RESET} %-22s\n" \
            "$i" "$username" "$password" "$status" "$(format_date "$expired_at")"
    done < <(jq -c '.accounts[]' "$ACCOUNTS_FILE")

    divider
    echo ""
}
