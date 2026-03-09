#!/usr/bin/env bash
# =============================================================================
# backup.sh — Backup & restore accounts, config, and certificates
# =============================================================================

BACKUP_DIR="/etc/zivpn/backups"
BACKUP_FILES=(
    "/etc/zivpn/accounts.json"
    "/etc/zivpn/config.json"
    "/etc/zivpn/manager.conf"
    "/etc/zivpn/zivpn.crt"
    "/etc/zivpn/zivpn.key"
)

# ---------------------------------------------------------------------------
# backup_data — Create a timestamped .tar.gz backup
# ---------------------------------------------------------------------------
backup_data() {
    print_header
    echo ""
    section_title "Backup Data ZiVPN"
    echo ""

    echo -e "    ${FG_DIM}File yang akan di-backup:${RESET}"
    echo ""
    local files_to_backup=()
    for f in "${BACKUP_FILES[@]}"; do
        if [[ -f "$f" ]]; then
            echo -e "    ${GREEN}✓${RESET}  $f"
            files_to_backup+=("$f")
        else
            echo -e "    ${FG_SUBTLE}✗  $f (tidak ada, dilewati)${RESET}"
        fi
    done
    echo ""

    if [[ ${#files_to_backup[@]} -eq 0 ]]; then
        print_error "Tidak ada file untuk di-backup."
        press_enter
        return
    fi

    # Show account summary
    if [[ -f "$ACCOUNTS_FILE" ]]; then
        local total active
        total=$(jq '.accounts | length' "$ACCOUNTS_FILE" 2>/dev/null || echo 0)
        active=$(jq '[.accounts[] | select(.status == "active")] | length' "$ACCOUNTS_FILE" 2>/dev/null || echo 0)
        echo -e "    ${FG_DIM}Total akun  :${RESET}  ${WHITE}${total}${RESET}"
        echo -e "    ${FG_DIM}Akun aktif  :${RESET}  ${GREEN}${active}${RESET}"
        echo ""
    fi

    mkdir -p "$BACKUP_DIR"

    local timestamp
    timestamp=$(date +"%Y%m%d_%H%M%S")
    local backup_file="${BACKUP_DIR}/zivpn-backup_${timestamp}.tar.gz"

    confirm "  Buat backup sekarang?" || { print_warn "Dibatalkan."; press_enter; return; }

    echo ""

    # Create backup with tar, stripping the leading /
    if tar -czf "$backup_file" -C / "${files_to_backup[@]/#\//}" 2>/dev/null; then
        chmod 600 "$backup_file"
        local size
        size=$(du -h "$backup_file" | cut -f1)
        print_success "Backup berhasil dibuat!"
        echo ""
        echo -e "    ${BOLD}Detail Backup:${RESET}"
        echo ""
        box_top
        box_line "${FG_DIM}File :${RESET}  ${CYAN}${backup_file}${RESET}"
        box_line "${FG_DIM}Size :${RESET}  ${WHITE}${size}${RESET}"
        box_line "${FG_DIM}Isi  :${RESET}  ${WHITE}${#files_to_backup[@]} file${RESET}"
        box_bottom
        echo ""
        echo -e "    ${FG_DIM}Salin file ini ke server baru untuk restore:${RESET}"
        echo -e "    ${CYAN}scp ${backup_file} root@<IP_SERVER_BARU>:/etc/zivpn/backups/${RESET}"
    else
        print_error "Gagal membuat backup."
    fi

    press_enter
}

# ---------------------------------------------------------------------------
# restore_data — Restore from a .tar.gz backup file
# ---------------------------------------------------------------------------
restore_data() {
    print_header
    echo ""
    section_title "Restore Data ZiVPN"
    echo ""

    mkdir -p "$BACKUP_DIR"

    # List available backups
    local backups=()
    while IFS= read -r f; do
        [[ -n "$f" ]] && backups+=("$f")
    done < <(find "$BACKUP_DIR" -maxdepth 1 -name "zivpn-backup_*.tar.gz" -type f 2>/dev/null | sort -r)

    if [[ ${#backups[@]} -gt 0 ]]; then
        echo -e "    ${BOLD}Backup tersedia:${RESET}"
        echo ""
        local i=0
        for b in "${backups[@]}"; do
            i=$((i + 1))
            local bname bsize bdate
            bname=$(basename "$b")
            bsize=$(du -h "$b" | cut -f1)
            bdate=$(echo "$bname" | sed -E 's/zivpn-backup_([0-9]{4})([0-9]{2})([0-9]{2})_([0-9]{2})([0-9]{2})([0-9]{2})\.tar\.gz/\1-\2-\3 \4:\5:\6/')
            printf "    ${GREEN}[%d]${RESET} %-24s ${FG_DIM}(%s, %s)${RESET}\n" "$i" "$bname" "$bsize" "$bdate"
        done
        echo ""
        echo -e "    ${FG_SUBTLE}[p]${RESET} Masukkan path file backup manual"
        echo -e "    ${RED}[0]${RESET} Batal"
        echo ""
        divider "subtle"

        local choice
        echo -en "    ${FG_DIM}Pilih backup${RESET} [0-${#backups[@]}/p]: "
        read -r choice

        if [[ "$choice" == "0" ]]; then
            print_info "Dibatalkan."
            press_enter
            return
        elif [[ "$choice" == "p" || "$choice" == "P" ]]; then
            echo -en "    ${FG_DIM}Path file backup (.tar.gz):${RESET} "
            read -r backup_path
        elif [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= ${#backups[@]} )); then
            backup_path="${backups[$((choice - 1))]}"
        else
            print_error "Pilihan tidak valid."
            press_enter
            return
        fi
    else
        echo -e "    ${FG_SUBTLE}Tidak ada backup di ${BACKUP_DIR}${RESET}"
        echo ""
        echo -en "    ${FG_DIM}Path file backup (.tar.gz):${RESET} "
        read -r backup_path
    fi

    backup_path=$(echo "$backup_path" | tr -d ' ')

    if [[ -z "$backup_path" ]]; then
        print_warn "Dibatalkan."
        press_enter
        return
    fi

    if [[ ! -f "$backup_path" ]]; then
        print_error "File tidak ditemukan: $backup_path"
        press_enter
        return
    fi

    # Validate it's a valid tar.gz
    if ! tar -tzf "$backup_path" &>/dev/null; then
        print_error "File bukan archive tar.gz yang valid."
        press_enter
        return
    fi

    echo ""
    echo -e "    ${BOLD}Isi backup:${RESET}"
    tar -tzf "$backup_path" 2>/dev/null | while IFS= read -r entry; do
        echo -e "      ${FG_SUBTLE}/${entry}${RESET}"
    done
    echo ""

    # Preview account count from backup
    local tmp_preview
    tmp_preview=$(mktemp -d)
    if tar -xzf "$backup_path" -C "$tmp_preview" "etc/zivpn/accounts.json" 2>/dev/null; then
        local preview_file="${tmp_preview}/etc/zivpn/accounts.json"
        if [[ -f "$preview_file" ]]; then
            local bk_total bk_active
            bk_total=$(jq '.accounts | length' "$preview_file" 2>/dev/null || echo "?")
            bk_active=$(jq '[.accounts[] | select(.status == "active")] | length' "$preview_file" 2>/dev/null || echo "?")
            echo -e "    ${FG_DIM}Akun dalam backup:${RESET} Total ${WHITE}${bk_total}${RESET} ${FG_SUBTLE}│${RESET} $(badge "Aktif ${bk_active}" "$GREEN")"
            echo ""
        fi
    fi
    rm -rf "$tmp_preview"

    echo -e "    ${RED}${BOLD}⚠  PERINGATAN: Restore akan menimpa data saat ini!${RESET}"
    echo ""
    confirm "  Lanjutkan restore dari backup ini?" || { print_warn "Dibatalkan."; press_enter; return; }

    echo ""

    # Create a safety backup of current state before restoring
    local safety_ts safety_file
    safety_ts=$(date +"%Y%m%d_%H%M%S")
    safety_file="${BACKUP_DIR}/zivpn-pre-restore_${safety_ts}.tar.gz"

    local current_files=()
    for f in "${BACKUP_FILES[@]}"; do
        [[ -f "$f" ]] && current_files+=("$f")
    done

    if [[ ${#current_files[@]} -gt 0 ]]; then
        tar -czf "$safety_file" -C / "${current_files[@]/#\//}" 2>/dev/null
        chmod 600 "$safety_file"
        print_info "Backup data saat ini disimpan di: ${safety_file}"
    fi

    # Extract backup to root
    if tar -xzf "$backup_path" -C / 2>/dev/null; then
        chmod 600 "$ACCOUNTS_FILE" 2>/dev/null

        # Sync config and restart
        sync_config

        echo ""
        print_success "Restore berhasil!"
        echo ""

        # Show restored account summary
        if [[ -f "$ACCOUNTS_FILE" ]]; then
            local r_total r_active
            r_total=$(jq '.accounts | length' "$ACCOUNTS_FILE" 2>/dev/null || echo 0)
            r_active=$(jq '[.accounts[] | select(.status == "active")] | length' "$ACCOUNTS_FILE" 2>/dev/null || echo 0)
            echo -e "    ${FG_DIM}Total akun ter-restore :${RESET}  ${WHITE}${r_total}${RESET}"
            echo -e "    ${FG_DIM}Akun aktif             :${RESET}  ${GREEN}${r_active}${RESET}"
        fi
    else
        print_error "Gagal melakukan restore."
        if [[ -f "$safety_file" ]]; then
            print_info "Data sebelumnya tersedia di: ${safety_file}"
        fi
    fi

    press_enter
}

# ---------------------------------------------------------------------------
# list_backups — Show all available backup files
# ---------------------------------------------------------------------------
list_backups() {
    print_header
    echo ""
    section_title "Daftar Backup ZiVPN"
    echo ""

    mkdir -p "$BACKUP_DIR"

    local backups=()
    while IFS= read -r f; do
        [[ -n "$f" ]] && backups+=("$f")
    done < <(find "$BACKUP_DIR" -maxdepth 1 -name "zivpn-*.tar.gz" -type f 2>/dev/null | sort -r)

    if [[ ${#backups[@]} -eq 0 ]]; then
        print_info "Belum ada file backup."
        echo -e "    ${FG_SUBTLE}Buat backup dari menu utama.${RESET}"
        press_enter
        return
    fi

    printf "  ${FG_DIM}┌──────┬──────────────────────────────────────────────┬──────────┬──────────────────────┐${RESET}\n"
    printf "  ${FG_DIM}│${RESET} ${BOLD}%-4s${RESET} ${FG_DIM}│${RESET} ${BOLD}%-44s${RESET} ${FG_DIM}│${RESET} ${BOLD}%-8s${RESET} ${FG_DIM}│${RESET} ${BOLD}%-20s${RESET} ${FG_DIM}│${RESET}\n" \
        "No" "Nama File" "Size" "Tanggal"
    printf "  ${FG_DIM}├──────┼──────────────────────────────────────────────┼──────────┼──────────────────────┤${RESET}\n"

    local i=0
    for b in "${backups[@]}"; do
        i=$((i + 1))
        local bname bsize bdate
        bname=$(basename "$b")
        bsize=$(du -h "$b" | cut -f1)
        bdate=$(stat -c '%y' "$b" 2>/dev/null | cut -d'.' -f1)
        printf "  ${FG_DIM}│${RESET} ${FG_DIM}%-4s${RESET} ${FG_DIM}│${RESET} %-44s ${FG_DIM}│${RESET} ${CYAN}%-8s${RESET} ${FG_DIM}│${RESET} ${FG_SUBTLE}%-20s${RESET} ${FG_DIM}│${RESET}\n" "$i" "$bname" "$bsize" "$bdate"
    done

    printf "  ${FG_DIM}└──────┴──────────────────────────────────────────────┴──────────┴──────────────────────┘${RESET}\n"
    echo ""
    echo -e "    ${FG_SUBTLE}Lokasi backup: ${BACKUP_DIR}${RESET}"
    echo ""
    press_enter
}
