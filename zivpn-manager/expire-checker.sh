#!/usr/bin/env bash
# =============================================================================
# expire-checker.sh — Cron script to auto-expire overdue accounts
# Called by: /etc/cron.d/zivpn-manager (every hour)
# =============================================================================

MANAGER_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
ACCOUNTS_FILE="/etc/zivpn/accounts.json"

source "$MANAGER_DIR/lib/utils.sh"
source "$MANAGER_DIR/lib/config.sh"
source "$MANAGER_DIR/lib/account.sh"

# Run expire check silently
expire_checker
