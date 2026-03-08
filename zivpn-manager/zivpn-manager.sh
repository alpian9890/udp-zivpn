#!/usr/bin/env bash
# =============================================================================
# zivpn-manager.sh — Main entry point: interactive terminal menu
# =============================================================================

MANAGER_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
ACCOUNTS_FILE="/etc/zivpn/accounts.json"

# Source libraries
source "$MANAGER_DIR/lib/utils.sh"
source "$MANAGER_DIR/lib/config.sh"
source "$MANAGER_DIR/lib/account.sh"
source "$MANAGER_DIR/lib/backup.sh"
source "$MANAGER_DIR/lib/help.sh"

# ---------------------------------------------------------------------------
# Check root
# ---------------------------------------------------------------------------
if [[ "$EUID" -ne 0 ]]; then
    echo -e "\033[0;31m[✗]\033[0m Script ini harus dijalankan sebagai root (sudo)"
    exit 1
fi

# Check dependencies
check_deps

# Init accounts file if not exists
init_accounts_file

# ---------------------------------------------------------------------------
# Menu: Tambah Akun
# ---------------------------------------------------------------------------
menu_add() {
    add_account
}

# ---------------------------------------------------------------------------
# Menu: Hapus Akun
# ---------------------------------------------------------------------------
menu_delete() {
    delete_account
}

# ---------------------------------------------------------------------------
# Menu: Lihat Daftar Akun
# ---------------------------------------------------------------------------
menu_list() {
    list_accounts
}

# ---------------------------------------------------------------------------
# Menu: Set Expired
# ---------------------------------------------------------------------------
menu_set_expired() {
    set_expired_account
}

# ---------------------------------------------------------------------------
# Menu: Perpanjang Akun
# ---------------------------------------------------------------------------
menu_extend() {
    extend_account
}

# ---------------------------------------------------------------------------
# Menu: Akun Trial
# ---------------------------------------------------------------------------
menu_trial() {
    create_trial_account
}

# ---------------------------------------------------------------------------
# Menu: Backup Data
# ---------------------------------------------------------------------------
menu_backup() {
    backup_data
}

# ---------------------------------------------------------------------------
# Menu: Restore Data
# ---------------------------------------------------------------------------
menu_restore() {
    restore_data
}

# ---------------------------------------------------------------------------
# Menu: Lihat Daftar Backup
# ---------------------------------------------------------------------------
menu_list_backups() {
    list_backups
}

# ---------------------------------------------------------------------------
# Menu: Restart Service
# ---------------------------------------------------------------------------
menu_restart() {
    print_header
    echo -e "${BOLD}  Restart ZiVPN Service${RESET}"
    echo ""
    confirm "  Restart service zivpn sekarang?" || { press_enter; return; }
    echo ""
    restart_service
    press_enter
}

# ---------------------------------------------------------------------------
# Menu: Status Service
# ---------------------------------------------------------------------------
menu_status() {
    print_header
    service_status
    press_enter
}

# ---------------------------------------------------------------------------
# Menu: Info Server
# ---------------------------------------------------------------------------
menu_server_info() {
    print_header
    echo -e "${BOLD}  Info Server & Konfigurasi ZiVPN${RESET}"
    echo ""

    local ipv4 domain port obfs
    ipv4=$(get_public_ipv4)
    domain=$(get_custom_domain)
    port=$(jq -r '.listen' /etc/zivpn/config.json 2>/dev/null | tr -d ':')
    obfs=$(jq -r '.obfs' /etc/zivpn/config.json 2>/dev/null)

    echo -e "  ${GRAY}IP Publik v4  :${RESET} ${WHITE}${ipv4}${RESET}"
    if [[ -n "$domain" ]]; then
        echo -e "  ${GRAY}Custom Domain :${RESET} ${CYAN}${domain}${RESET}"
    else
        echo -e "  ${GRAY}Custom Domain :${RESET} ${GRAY}(belum diset)${RESET}"
    fi
    echo -e "  ${GRAY}Port Internal :${RESET} ${WHITE}${port}${RESET}"
    echo -e "  ${GRAY}Port Eksternal:${RESET} ${WHITE}6000-19999 (UDP)${RESET}"
    echo -e "  ${GRAY}Obfuscation   :${RESET} ${WHITE}${obfs}${RESET}"
    echo -e "  ${GRAY}Config        :${RESET} ${WHITE}/etc/zivpn/config.json${RESET}"
    echo -e "  ${GRAY}Accounts DB   :${RESET} ${WHITE}${ACCOUNTS_FILE}${RESET}"
    echo ""

    local svc_color svc_label
    if service_is_active; then
        svc_color="$GREEN"; svc_label="Running"
    else
        svc_color="$RED"; svc_label="Stopped"
    fi
    echo -e "  ${GRAY}Service Status:${RESET} ${svc_color}${svc_label}${RESET}"
    echo ""
    press_enter
}

# ---------------------------------------------------------------------------
# Menu: Custom Domain
# ---------------------------------------------------------------------------
menu_custom_domain() {
    print_header
    echo -e "${BOLD}  Custom Domain${RESET}"
    echo ""

    local current
    current=$(get_custom_domain)
    if [[ -n "$current" ]]; then
        echo -e "  Domain saat ini : ${CYAN}${current}${RESET}"
    else
        echo -e "  Domain saat ini : ${GRAY}(belum diset)${RESET}"
    fi
    echo ""
    echo -e "  ${GRAY}Masukkan domain yang sudah di-pointing ke IP server ini.${RESET}"
    echo -e "  ${GRAY}Contoh: vpn.namadomain.com${RESET}"
    echo -e "  ${GRAY}Biarkan kosong + Enter untuk menghapus domain.${RESET}"
    echo ""
    echo -en "  Domain baru: "
    read -r new_domain
    new_domain=$(echo "$new_domain" | tr -d ' ')

    if [[ -z "$new_domain" ]]; then
        if [[ -n "$current" ]]; then
            confirm "  Hapus custom domain '${current}'?" || { print_warn "Dibatalkan."; press_enter; return; }
            set_custom_domain ""
            # Remove the line entirely
            sed -i '/^CUSTOM_DOMAIN=/d' "$MANAGER_CONFIG" 2>/dev/null
            print_success "Custom domain dihapus. Header akan menampilkan IP publik."
        else
            print_info "Tidak ada domain untuk dihapus."
        fi
    else
        set_custom_domain "$new_domain"
        print_success "Custom domain disimpan: ${CYAN}${new_domain}${RESET}"
        echo -e "  ${GRAY}Domain ini akan ditampilkan di header dan info akun.${RESET}"
    fi
    press_enter
}

# ---------------------------------------------------------------------------
# Main menu loop
# ---------------------------------------------------------------------------
main_menu() {
    while true; do
        print_header
        echo -e "${BOLD}  MENU UTAMA${RESET}"
        echo ""
        echo -e "  ${GREEN}[1]${RESET} Tambah Akun"
        echo -e "  ${RED}[2]${RESET} Hapus Akun"
        echo -e "  ${CYAN}[3]${RESET} Lihat Daftar Akun"
        echo -e "  ${YELLOW}[4]${RESET} Set Expired Akun"
        echo -e "  ${BLUE}[5]${RESET} Perpanjang Akun"
        echo -e "  ${YELLOW}[6]${RESET} Buat Akun Trial"
        echo -e "  ${CYAN}[7]${RESET} Custom Domain"
        echo ""
        echo -e "  ${GREEN}[b]${RESET} Backup Data"
        echo -e "  ${BLUE}[r]${RESET} Restore Data"
        echo -e "  ${GRAY}[l]${RESET} Lihat Daftar Backup"
        echo ""
        echo -e "  ${GRAY}[8]${RESET} Restart Service ZiVPN"
        echo -e "  ${GRAY}[9]${RESET} Status Service ZiVPN"
        echo -e "  ${GRAY}[i]${RESET} Info Server"
        echo ""
        echo -e "  ${WHITE}[h]${RESET} Bantuan (Help)"
        echo -e "  ${RED}[0]${RESET} Keluar"
        echo ""
        divider
        echo -en "  Pilih menu [0-9/b/r/l/i/h]: "
        read -r choice

        case "$choice" in
            1) menu_add           ;;
            2) menu_delete        ;;
            3) menu_list          ;;
            4) menu_set_expired   ;;
            5) menu_extend        ;;
            6) menu_trial         ;;
            7) menu_custom_domain ;;
            b|B) menu_backup      ;;
            r|R) menu_restore     ;;
            l|L) menu_list_backups;;
            8) menu_restart       ;;
            9) menu_status        ;;
            i|I) menu_server_info ;;
            h|H) show_usage; press_enter ;;
            0)
                echo ""
                print_info "Keluar dari ZiVPN Manager."
                echo ""
                exit 0
                ;;
            *)
                print_warn "Pilihan tidak valid."
                sleep 1
                ;;
        esac
    done
}

# ---------------------------------------------------------------------------
# CLI mode: allow direct commands without interactive menu
# Usage: zivpn-manager [command] [args]
#   zivpn-manager list
#   zivpn-manager add
#   zivpn-manager delete <username>
#   zivpn-manager expire-check   (used by cron)
# ---------------------------------------------------------------------------
case "${1:-}" in
    list)         init_accounts_file; list_accounts ;;
    add)          init_accounts_file; add_account   ;;
    delete)       init_accounts_file; delete_account;;
    trial)        init_accounts_file; create_trial_account ;;
    extend)       init_accounts_file; extend_account ;;
    set-expired)  init_accounts_file; set_expired_account ;;
    backup)       init_accounts_file; backup_data   ;;
    restore)      init_accounts_file; restore_data  ;;
    backups)      init_accounts_file; list_backups   ;;
    status)       service_status ;;
    restart)      restart_service ;;
    info)         init_accounts_file; menu_server_info ;;
    expire-check) init_accounts_file; expire_checker ;;
    help)         show_help "${2:-}" ;;
    version|-v|--version) show_version ;;
    *)
        show_usage
        exit 1
        ;;
esac
