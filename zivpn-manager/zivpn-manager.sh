#!/usr/bin/env bash
# =============================================================================
# zivpn-manager.sh — Main entry point: interactive TUI menu + CLI mode
# =============================================================================

MANAGER_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
ACCOUNTS_FILE="/etc/zivpn/accounts.json"

# Source libraries
source "$MANAGER_DIR/lib/utils.sh"
source "$MANAGER_DIR/lib/config.sh"
source "$MANAGER_DIR/lib/account.sh"
source "$MANAGER_DIR/lib/backup.sh"
source "$MANAGER_DIR/lib/help.sh"
source "$MANAGER_DIR/lib/update.sh"
source "$MANAGER_DIR/lib/tui.sh"
source "$MANAGER_DIR/lib/uninstall.sh"

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
# Action handlers — Each corresponds to a CLI command AND a TUI menu item
# ---------------------------------------------------------------------------
action_add() { add_account; }
action_delete() { delete_account; }
action_list() { list_accounts; }
action_set_expired() { set_expired_account; }
action_extend() { extend_account; }
action_trial() { create_trial_account; }

action_backup() { backup_data; }
action_restore() { restore_data; }
action_backups() { list_backups; }

action_restart() {
    print_header
    echo -e "${BOLD}  Restart ZiVPN Service${RESET}"
    echo ""
    confirm "  Restart service zivpn sekarang?" || { press_enter; return; }
    echo ""
    restart_service
    press_enter
}

action_status() {
    print_header
    service_status
    press_enter
}

action_info() {
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

action_domain() {
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

action_help() { show_usage; press_enter; }
action_update() { check_update; }
action_uninstall() { uninstall_zivpn; }

# ---------------------------------------------------------------------------
# dispatch_action — Run an action by its ID (used by both TUI and CLI)
# ---------------------------------------------------------------------------
dispatch_action() {
    local action="$1"
    case "$action" in
        add)          action_add ;;
        delete)       action_delete ;;
        list)         action_list ;;
        set-expired)  action_set_expired ;;
        extend)       action_extend ;;
        trial)        action_trial ;;
        domain)       action_domain ;;
        backup)       action_backup ;;
        restore)      action_restore ;;
        backups)      action_backups ;;
        restart)      action_restart ;;
        status)       action_status ;;
        info)         action_info ;;
        help)         action_help ;;
        update)       action_update ;;
        uninstall)    action_uninstall ;;
        __exit__)     return 1 ;;
        *)            return 1 ;;
    esac
    return 0
}

# ---------------------------------------------------------------------------
# Main menu — Interactive TUI with arrow-key navigation
# ---------------------------------------------------------------------------

# Menu item definitions: "Display Label|action_id"
MENU_ITEMS=(
    "Tambah Akun|add"
    "Hapus Akun|delete"
    "Lihat Daftar Akun|list"
    "Set Expired Akun|set-expired"
    "Perpanjang Akun|extend"
    "Buat Akun Trial|trial"
    "Custom Domain|domain"
    "-"
    "Backup Data|backup"
    "Restore Data|restore"
    "Lihat Daftar Backup|backups"
    "-"
    "Restart Service|restart"
    "Status Service|status"
    "Info Server|info"
    "-"
    "Bantuan (Help)|help"
    "Cek Update|update"
    "Uninstall ZiVPN|uninstall"
    "-"
    "Keluar|__exit__"
)

main_menu() {
    while true; do
        local action
        action=$(tui_menu "MENU UTAMA" MENU_ITEMS)

        if [[ "$action" == "__exit__" ]]; then
            echo ""
            print_info "Keluar dari ZiVPN Manager."
            echo ""
            exit 0
        fi

        dispatch_action "$action" || continue
    done
}

# ---------------------------------------------------------------------------
# CLI mode: direct commands without interactive menu
# All commands here match action IDs used by the TUI menu.
# ---------------------------------------------------------------------------
case "${1:-}" in
    add)          action_add ;;
    delete)       action_delete ;;
    list)         action_list ;;
    set-expired)  action_set_expired ;;
    extend)       action_extend ;;
    trial)        action_trial ;;
    domain)       action_domain ;;
    backup)       action_backup ;;
    restore)      action_restore ;;
    backups)      action_backups ;;
    restart)      action_restart ;;
    status)       action_status ;;
    info)         action_info ;;
    uninstall)    action_uninstall ;;
    expire-check) expire_checker ;;
    help)         show_help "${2:-}" ;;
    update)       action_update ;;
    version|-v|--version) show_version ;;
    "")           main_menu ;;
    *)
        show_usage
        exit 1
        ;;
esac
