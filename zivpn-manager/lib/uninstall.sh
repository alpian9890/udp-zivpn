#!/usr/bin/env bash
# =============================================================================
# uninstall.sh — Complete removal of ZiVPN and ZiVPN Manager
# =============================================================================

ZIVPN_SERVICE="zivpn.service"
ZIVPN_BIN="/usr/local/bin/zivpn"
ZIVPN_DIR="/etc/zivpn"
MANAGER_BIN="/usr/local/bin/zivpn-manager"
MANAGER_INSTALL_DIR="/etc/zivpn/zivpn-manager"
CRON_FILE="/etc/cron.d/zivpn-manager"
BACKUP_DIR="/etc/zivpn/backups"

# ---------------------------------------------------------------------------
# uninstall_zivpn — Full uninstall with backup prompt
# ---------------------------------------------------------------------------
uninstall_zivpn() {
    print_header
    echo ""
    echo -e "  ${RED}╭──────────────────────────────────────────────────────────╮${RESET}"
    echo -e "  ${RED}│${RESET}                                                          ${RED}│${RESET}"
    echo -e "  ${RED}│${RESET}         ${RED}${BOLD}⚠   UNINSTALL ZIVPN   ⚠${RESET}                        ${RED}│${RESET}"
    echo -e "  ${RED}│${RESET}                                                          ${RED}│${RESET}"
    echo -e "  ${RED}╰──────────────────────────────────────────────────────────╯${RESET}"
    echo ""
    echo -e "    ${WHITE}Proses ini akan menghapus:${RESET}"
    echo ""
    echo -e "    ${FG_DIM}•${RESET}  Service ZiVPN (systemd)"
    echo -e "    ${FG_DIM}•${RESET}  Binary /usr/local/bin/zivpn"
    echo -e "    ${FG_DIM}•${RESET}  Semua konfigurasi /etc/zivpn/"
    echo -e "    ${FG_DIM}•${RESET}  Database akun (accounts.json)"
    echo -e "    ${FG_DIM}•${RESET}  Sertifikat SSL (zivpn.crt, zivpn.key)"
    echo -e "    ${FG_DIM}•${RESET}  ZiVPN Manager dan cron job"
    echo -e "    ${FG_DIM}•${RESET}  Aturan firewall (iptables/ufw)"
    echo ""
    echo -e "    ${RED}${BOLD}Semua data akan hilang dan tidak bisa dikembalikan!${RESET}"
    echo ""

    # Show current account count
    if [[ -f "$ACCOUNTS_FILE" ]]; then
        local total active
        total=$(jq '.accounts | length' "$ACCOUNTS_FILE" 2>/dev/null || echo 0)
        active=$(jq '[.accounts[] | select(.status == "active")] | length' "$ACCOUNTS_FILE" 2>/dev/null || echo 0)
        echo -e "    ${YELLOW}Data saat ini: ${WHITE}${total}${YELLOW} akun (${GREEN}${active} aktif${YELLOW})${RESET}"
        echo ""
    fi

    if command -v tui_confirm &>/dev/null 2>&1 && [[ -t 0 ]]; then
        tui_confirm "Lanjutkan proses uninstall?" || {
            print_info "Uninstall dibatalkan."
            wait_for_esc
            return 0
        }
        echo ""
        echo -e "    ${BOLD}Pilih tindakan:${RESET}"
        echo ""
        echo -e "    ${GREEN}[1]${RESET} Backup dulu, lalu uninstall"
        echo -e "    ${RED}[2]${RESET} Langsung uninstall (tanpa backup)"
        echo -e "    ${FG_SUBTLE}[3]${RESET} Batal"
        echo ""
        divider "subtle"
        echo -en "    ${FG_DIM}Pilih${RESET} [1/2/3]: "
        read -r choice
    else
        echo -e "    ${BOLD}Pilih tindakan:${RESET}"
        echo ""
        echo -e "    ${GREEN}[1]${RESET} Backup dulu, lalu uninstall"
        echo -e "    ${RED}[2]${RESET} Langsung uninstall (tanpa backup)"
        echo -e "    ${FG_SUBTLE}[3]${RESET} Batal"
        echo ""
        divider "subtle"
        echo -en "    ${FG_DIM}Pilih${RESET} [1/2/3]: "
        read -r choice
    fi

    case "$choice" in
        1)
            echo ""
            print_info "Membuat backup sebelum uninstall..."
            echo ""
            _do_pre_uninstall_backup || {
                print_error "Backup gagal. Uninstall dibatalkan."
                wait_for_esc
                return 1
            }
            echo ""
            confirm "  Lanjutkan uninstall sekarang?" || {
                print_warn "Uninstall dibatalkan."
                wait_for_esc
                return 0
            }
            ;;
        2)
            echo ""
            confirm "  ${RED}YAKIN uninstall TANPA backup?${RESET}" || {
                print_warn "Uninstall dibatalkan."
                wait_for_esc
                return 0
            }
            ;;
        3|*)
            print_info "Uninstall dibatalkan."
            wait_for_esc
            return 0
            ;;
    esac

    echo ""
    _execute_uninstall

    # Exit the entire script — files are deleted, don't return to TUI loop
    exit 0
}

# ---------------------------------------------------------------------------
# _do_pre_uninstall_backup — Create backup before uninstall
# ---------------------------------------------------------------------------
_do_pre_uninstall_backup() {
    local backup_files=()
    local candidates=(
        "/etc/zivpn/accounts.json"
        "/etc/zivpn/config.json"
        "/etc/zivpn/manager.conf"
        "/etc/zivpn/zivpn.crt"
        "/etc/zivpn/zivpn.key"
    )

    for f in "${candidates[@]}"; do
        [[ -f "$f" ]] && backup_files+=("$f")
    done

    if [[ ${#backup_files[@]} -eq 0 ]]; then
        print_warn "Tidak ada file untuk di-backup."
        return 0
    fi

    mkdir -p "$BACKUP_DIR"

    local timestamp backup_file
    timestamp=$(date +"%Y%m%d_%H%M%S")
    backup_file="${BACKUP_DIR}/zivpn-pre-uninstall_${timestamp}.tar.gz"

    if tar -czf "$backup_file" -C / "${backup_files[@]/#\//}" 2>/dev/null; then
        chmod 600 "$backup_file"
        local size
        size=$(du -h "$backup_file" | cut -f1)
        print_success "Backup berhasil: ${CYAN}${backup_file}${RESET} (${size})"
        echo ""
        echo -e "    ${YELLOW}${BOLD}⚠  PENTING: Salin file backup ke tempat aman SEBELUM uninstall!${RESET}"
        echo -e "    ${FG_SUBTLE}File backup ada di dalam /etc/zivpn/ yang akan dihapus.${RESET}"
        echo ""
        echo -e "    ${BOLD}Salin ke lokasi aman:${RESET}"
        echo -e "    ${CYAN}cp ${backup_file} /root/${RESET}"
        echo ""
        echo -e "    ${BOLD}Atau salin ke server lain:${RESET}"
        echo -e "    ${CYAN}scp ${backup_file} root@IP_SERVER_BARU:/tmp/${RESET}"
        echo ""

        # Copy to /root/ automatically as safety
        cp "$backup_file" "/root/" 2>/dev/null && \
            print_success "Salinan otomatis disimpan di: ${CYAN}/root/$(basename "$backup_file")${RESET}"

        echo ""
        return 0
    else
        print_error "Gagal membuat backup."
        return 1
    fi
}

# ---------------------------------------------------------------------------
# _execute_uninstall — Actually remove everything
# ---------------------------------------------------------------------------
_execute_uninstall() {
    echo -e "    ${BOLD}Memulai proses uninstall...${RESET}"
    echo ""

    # 1. Stop and disable service
    echo -ne "    ${FG_DIM}Menghentikan service...${RESET}            "
    systemctl stop "$ZIVPN_SERVICE" 2>/dev/null
    systemctl stop zivpn_backfill.service 2>/dev/null
    systemctl disable "$ZIVPN_SERVICE" 2>/dev/null
    systemctl disable zivpn_backfill.service 2>/dev/null
    
    # Stop dashboard if running
    if command -v pm2 &>/dev/null; then
        pm2 delete zivpn-dashboard 2>/dev/null || true
    fi
    echo -e "${GREEN}✓${RESET}"

    # 2. Remove systemd unit files
    echo -ne "    ${FG_DIM}Menghapus systemd unit files...${RESET}    "
    rm -f /etc/systemd/system/zivpn.service 2>/dev/null
    rm -f /etc/systemd/system/zivpn_backfill.service 2>/dev/null
    rm -f /etc/cron.d/zivpn-autobackup 2>/dev/null
    systemctl daemon-reload 2>/dev/null
    echo -e "${GREEN}✓${RESET}"

    # 3. Remove binary
    echo -ne "    ${FG_DIM}Menghapus binary zivpn...${RESET}          "
    rm -f "$ZIVPN_BIN" 2>/dev/null
    echo -e "${GREEN}✓${RESET}"

    # 4. Remove cron job
    echo -ne "    ${FG_DIM}Menghapus cron job...${RESET}              "
    rm -f "$CRON_FILE" 2>/dev/null
    echo -e "${GREEN}✓${RESET}"

    # 5. Remove manager symlink
    echo -ne "    ${FG_DIM}Menghapus command zivpn-manager...${RESET} "
    rm -f "$MANAGER_BIN" 2>/dev/null
    echo -e "${GREEN}✓${RESET}"

    # 6. Remove firewall rules (best effort)
    echo -ne "    ${FG_DIM}Membersihkan aturan firewall...${RESET}    "
    ufw delete allow 6000:19999/udp 2>/dev/null || true
    ufw delete allow 5667/udp 2>/dev/null || true
    echo -e "${GREEN}✓${RESET}"

    # 7. Remove /etc/zivpn directory (config, accounts, certs, manager)
    echo -ne "    ${FG_DIM}Menghapus direktori /etc/zivpn/...${RESET} "
    rm -rf "$ZIVPN_DIR" 2>/dev/null
    echo -e "${GREEN}✓${RESET}"

    echo ""

    # Verify
    local all_clean=true
    if [[ -f "$ZIVPN_BIN" ]]; then
        print_error "Binary masih ada: $ZIVPN_BIN"
        all_clean=false
    fi
    if [[ -d "$ZIVPN_DIR" ]]; then
        print_error "Direktori masih ada: $ZIVPN_DIR"
        all_clean=false
    fi
    if pgrep -x "zivpn" >/dev/null 2>&1; then
        print_error "Proses zivpn masih berjalan"
        all_clean=false
    fi

    if [[ "$all_clean" == true ]]; then
        echo ""
        echo -e "  ${GREEN}╭──────────────────────────────────────────────────────────╮${RESET}"
        echo -e "  ${GREEN}│${RESET}                                                          ${GREEN}│${RESET}"
        echo -e "  ${GREEN}│${RESET}    ${GREEN}${BOLD}✓  ZiVPN berhasil di-uninstall sepenuhnya!${RESET}              ${GREEN}│${RESET}"
        echo -e "  ${GREEN}│${RESET}                                                          ${GREEN}│${RESET}"
        echo -e "  ${GREEN}╰──────────────────────────────────────────────────────────╯${RESET}"
    else
        echo ""
        print_warn "Uninstall selesai dengan beberapa peringatan di atas."
    fi

    local saved_backup
    saved_backup=$(ls -t /root/zivpn-pre-uninstall_*.tar.gz 2>/dev/null | head -1)
    if [[ -n "$saved_backup" ]]; then
        echo -e "    ${FG_DIM}File backup tersedia di: ${CYAN}${saved_backup}${RESET}"
    fi

    echo ""
}
