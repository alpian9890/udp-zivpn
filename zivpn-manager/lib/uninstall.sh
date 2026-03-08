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
    echo -e "${RED}${BOLD}  ╔══════════════════════════════════════════════════════════╗${RESET}"
    echo -e "${RED}${BOLD}  ║            ⚠  UNINSTALL ZIVPN  ⚠                        ║${RESET}"
    echo -e "${RED}${BOLD}  ╚══════════════════════════════════════════════════════════╝${RESET}"
    echo ""
    echo -e "  ${WHITE}Proses ini akan menghapus:${RESET}"
    echo -e "  ${GRAY}• Service ZiVPN (systemd)${RESET}"
    echo -e "  ${GRAY}• Binary /usr/local/bin/zivpn${RESET}"
    echo -e "  ${GRAY}• Semua konfigurasi /etc/zivpn/${RESET}"
    echo -e "  ${GRAY}• Database akun (accounts.json)${RESET}"
    echo -e "  ${GRAY}• Sertifikat SSL (zivpn.crt, zivpn.key)${RESET}"
    echo -e "  ${GRAY}• ZiVPN Manager dan cron job${RESET}"
    echo -e "  ${GRAY}• Aturan firewall (iptables/ufw)${RESET}"
    echo ""
    echo -e "  ${RED}${BOLD}Semua data akan hilang dan tidak bisa dikembalikan!${RESET}"
    echo ""

    # Show current account count
    if [[ -f "$ACCOUNTS_FILE" ]]; then
        local total active
        total=$(jq '.accounts | length' "$ACCOUNTS_FILE" 2>/dev/null || echo 0)
        active=$(jq '[.accounts[] | select(.status == "active")] | length' "$ACCOUNTS_FILE" 2>/dev/null || echo 0)
        echo -e "  ${YELLOW}Data saat ini: ${WHITE}${total}${YELLOW} akun (${GREEN}${active} aktif${YELLOW})${RESET}"
        echo ""
    fi

    if command -v tui_confirm &>/dev/null 2>&1 && [[ -t 0 ]]; then
        # TUI mode
        echo -e "  ${BOLD}Pilih tindakan:${RESET}"
        echo ""
        echo -e "  ${GREEN}[1]${RESET} Backup dulu, lalu uninstall"
        echo -e "  ${RED}[2]${RESET} Langsung uninstall (tanpa backup)"
        echo -e "  ${GRAY}[3]${RESET} Batal"
        echo ""
        divider
        echo -en "  Pilih [1/2/3]: "
        read -r choice
    else
        echo -e "  ${BOLD}Pilih tindakan:${RESET}"
        echo ""
        echo -e "  ${GREEN}[1]${RESET} Backup dulu, lalu uninstall"
        echo -e "  ${RED}[2]${RESET} Langsung uninstall (tanpa backup)"
        echo -e "  ${GRAY}[3]${RESET} Batal"
        echo ""
        divider
        echo -en "  Pilih [1/2/3]: "
        read -r choice
    fi

    case "$choice" in
        1)
            echo ""
            print_info "Membuat backup sebelum uninstall..."
            echo ""
            _do_pre_uninstall_backup || {
                print_error "Backup gagal. Uninstall dibatalkan."
                press_enter
                return 1
            }
            echo ""
            confirm "  Lanjutkan uninstall sekarang?" || {
                print_warn "Uninstall dibatalkan."
                press_enter
                return 0
            }
            ;;
        2)
            echo ""
            confirm "  ${RED}YAKIN uninstall TANPA backup?${RESET}" || {
                print_warn "Uninstall dibatalkan."
                press_enter
                return 0
            }
            ;;
        3|*)
            print_info "Uninstall dibatalkan."
            press_enter
            return 0
            ;;
    esac

    echo ""
    _execute_uninstall
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
        echo -e "  ${YELLOW}${BOLD}⚠  PENTING: Salin file backup ke tempat aman SEBELUM uninstall!${RESET}"
        echo -e "  ${GRAY}File backup ada di dalam /etc/zivpn/ yang akan dihapus.${RESET}"
        echo ""
        echo -e "  ${BOLD}Salin ke lokasi aman:${RESET}"
        echo -e "  ${CYAN}cp ${backup_file} /root/${RESET}"
        echo ""
        echo -e "  ${BOLD}Atau salin ke server lain:${RESET}"
        echo -e "  ${CYAN}scp ${backup_file} root@IP_SERVER_BARU:/tmp/${RESET}"
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
    echo -e "  ${BOLD}Memulai proses uninstall...${RESET}"
    echo ""

    # 1. Stop and disable service
    echo -ne "  Menghentikan service...            "
    systemctl stop "$ZIVPN_SERVICE" 2>/dev/null
    systemctl stop zivpn_backfill.service 2>/dev/null
    systemctl disable "$ZIVPN_SERVICE" 2>/dev/null
    systemctl disable zivpn_backfill.service 2>/dev/null
    echo -e "${GREEN}✓${RESET}"

    # 2. Remove systemd unit files
    echo -ne "  Menghapus systemd unit files...    "
    rm -f /etc/systemd/system/zivpn.service 2>/dev/null
    rm -f /etc/systemd/system/zivpn_backfill.service 2>/dev/null
    systemctl daemon-reload 2>/dev/null
    echo -e "${GREEN}✓${RESET}"

    # 3. Remove binary
    echo -ne "  Menghapus binary zivpn...          "
    rm -f "$ZIVPN_BIN" 2>/dev/null
    echo -e "${GREEN}✓${RESET}"

    # 4. Remove cron job
    echo -ne "  Menghapus cron job...              "
    rm -f "$CRON_FILE" 2>/dev/null
    echo -e "${GREEN}✓${RESET}"

    # 5. Remove manager symlink
    echo -ne "  Menghapus command zivpn-manager... "
    rm -f "$MANAGER_BIN" 2>/dev/null
    echo -e "${GREEN}✓${RESET}"

    # 6. Remove firewall rules (best effort)
    echo -ne "  Membersihkan aturan firewall...    "
    ufw delete allow 6000:19999/udp 2>/dev/null || true
    ufw delete allow 5667/udp 2>/dev/null || true
    echo -e "${GREEN}✓${RESET}"

    # 7. Remove /etc/zivpn directory (config, accounts, certs, manager)
    echo -ne "  Menghapus direktori /etc/zivpn/... "
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
        echo -e "${GREEN}${BOLD}"
        echo "  ╔══════════════════════════════════════════════════════════╗"
        echo "  ║       ZiVPN berhasil di-uninstall sepenuhnya!           ║"
        echo "  ╚══════════════════════════════════════════════════════════╝"
        echo -e "${RESET}"
    else
        echo ""
        print_warn "Uninstall selesai dengan beberapa peringatan di atas."
    fi

    # Check if backup was saved to /root/
    local saved_backup
    saved_backup=$(ls -t /root/zivpn-pre-uninstall_*.tar.gz 2>/dev/null | head -1)
    if [[ -n "$saved_backup" ]]; then
        echo -e "  ${GRAY}File backup tersedia di: ${CYAN}${saved_backup}${RESET}"
    fi

    echo ""
}
