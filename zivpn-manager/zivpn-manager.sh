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

    local server_ip port obfs
    server_ip=$(curl -s --max-time 3 ifconfig.me 2>/dev/null || hostname -I | awk '{print $1}')
    port=$(jq -r '.listen' /etc/zivpn/config.json 2>/dev/null | tr -d ':')
    obfs=$(jq -r '.obfs' /etc/zivpn/config.json 2>/dev/null)

    echo -e "  ${GRAY}IP Server     :${RESET} ${WHITE}${server_ip}${RESET}"
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
        echo ""
        echo -e "  ${GRAY}[7]${RESET} Restart Service ZiVPN"
        echo -e "  ${GRAY}[8]${RESET} Status Service ZiVPN"
        echo -e "  ${GRAY}[9]${RESET} Info Server"
        echo ""
        echo -e "  ${RED}[0]${RESET} Keluar"
        echo ""
        divider
        echo -en "  Pilih menu [0-9]: "
        read -r choice

        case "$choice" in
            1) menu_add        ;;
            2) menu_delete     ;;
            3) menu_list       ;;
            4) menu_set_expired;;
            5) menu_extend     ;;
            6) menu_trial      ;;
            7) menu_restart    ;;
            8) menu_status     ;;
            9) menu_server_info;;
            0)
                echo ""
                print_info "Keluar dari ZiVPN Manager."
                echo ""
                exit 0
                ;;
            *)
                print_warn "Pilihan tidak valid. Masukkan angka 0-9."
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
    status)       service_status ;;
    expire-check) init_accounts_file; expire_checker ;;
    "")           main_menu ;;
    *)
        echo "Usage: zivpn-manager [list|add|delete|trial|extend|status|expire-check]"
        exit 1
        ;;
esac
