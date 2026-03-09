#!/usr/bin/env bash
# =============================================================================
# config.sh — Sync accounts.json -> /etc/zivpn/config.json & service control
# =============================================================================

ZIVPN_CONFIG="/etc/zivpn/config.json"
ZIVPN_SERVICE="zivpn.service"

# Rebuild /etc/zivpn/config.json from active accounts only, then restart service
sync_config() {
    # Collect passwords of all active accounts
    local passwords
    passwords=$(jq -r '[.accounts[] | select(.status == "active") | .password] | @json' "$ACCOUNTS_FILE" 2>/dev/null)

    if [[ -z "$passwords" || "$passwords" == "null" || "$passwords" == "[]" ]]; then
        # No active accounts — keep a placeholder so the service doesn't error
        passwords='["__no_active_accounts__"]'
    fi

    # Read current config and replace the auth.config array
    local current_config
    current_config=$(cat "$ZIVPN_CONFIG")

    # Build new config JSON with updated password list
    local new_config
    new_config=$(echo "$current_config" | jq --argjson pw "$passwords" '.auth.config = $pw')

    if [[ -z "$new_config" ]]; then
        print_error "Gagal membuat config baru. Cek format $ZIVPN_CONFIG"
        return 1
    fi

    # Atomic write via temp file
    local tmpfile
    tmpfile=$(mktemp)
    echo "$new_config" > "$tmpfile"
    mv "$tmpfile" "$ZIVPN_CONFIG"

    # Restart service
    restart_service
}

restart_service() {
    if systemctl restart "$ZIVPN_SERVICE" 2>/dev/null; then
        print_success "Service zivpn berhasil di-restart"
        return 0
    else
        print_error "Gagal restart service zivpn"
        return 1
    fi
}

service_status() {
    echo ""
    echo -e "  ${BOLD}Status ZiVPN Service:${RESET}"
    divider
    systemctl status "$ZIVPN_SERVICE" --no-pager -l 2>/dev/null || \
        print_error "Tidak dapat membaca status service"
}

service_is_active() {
    systemctl is-active --quiet "$ZIVPN_SERVICE"
}
