#!/usr/bin/env bash
# =============================================================================
# utils.sh — Helper functions: colors, formatting, validation
# =============================================================================

# --- Colors ------------------------------------------------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
GRAY='\033[0;90m'
BOLD='\033[1m'
RESET='\033[0m'

# --- Print helpers -----------------------------------------------------------
print_success() { echo -e "${GREEN}[✓]${RESET} $1"; }
print_error()   { echo -e "${RED}[✗]${RESET} $1"; }
print_info()    { echo -e "${CYAN}[i]${RESET} $1"; }
print_warn()    { echo -e "${YELLOW}[!]${RESET} $1"; }
print_bold()    { echo -e "${BOLD}$1${RESET}"; }

# --- Divider -----------------------------------------------------------------
divider() {
    echo -e "${GRAY}$(printf '─%.0s' {1..60})${RESET}"
}

# --- Server info helpers -----------------------------------------------------

MANAGER_CONFIG="/etc/zivpn/manager.conf"

# Get IPv4 public address only
get_public_ipv4() {
    local ip
    # Try multiple sources, force IPv4
    ip=$(curl -4 -s --max-time 4 https://api.ipify.org 2>/dev/null)
    if [[ -z "$ip" ]]; then
        ip=$(curl -4 -s --max-time 4 https://ifconfig.me 2>/dev/null)
    fi
    if [[ -z "$ip" ]]; then
        # Fallback: get first IPv4 from hostname -I
        ip=$(hostname -I 2>/dev/null | tr ' ' '\n' | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' | head -1)
    fi
    echo "${ip:-N/A}"
}

# Get custom domain (from manager.conf), or empty string if not set
get_custom_domain() {
    if [[ -f "$MANAGER_CONFIG" ]]; then
        grep -E '^CUSTOM_DOMAIN=' "$MANAGER_CONFIG" 2>/dev/null | cut -d'=' -f2 | tr -d '"'
    fi
}

# Get host to display: domain if set, otherwise IPv4
get_server_host() {
    local domain
    domain=$(get_custom_domain)
    if [[ -n "$domain" ]]; then
        echo "$domain"
    else
        get_public_ipv4
    fi
}

# Save custom domain to manager.conf
set_custom_domain() {
    local domain="$1"
    touch "$MANAGER_CONFIG"
    if grep -q '^CUSTOM_DOMAIN=' "$MANAGER_CONFIG" 2>/dev/null; then
        sed -i "s|^CUSTOM_DOMAIN=.*|CUSTOM_DOMAIN=\"${domain}\"|" "$MANAGER_CONFIG"
    else
        echo "CUSTOM_DOMAIN=\"${domain}\"" >> "$MANAGER_CONFIG"
    fi
}

# --- Header ------------------------------------------------------------------
print_header() {
    clear
    local host domain
    domain=$(get_custom_domain)
    if [[ -n "$domain" ]]; then
        host="$domain"
    else
        host=$(get_public_ipv4)
    fi

    local total active expired
    total=$(jq '.accounts | length' "$ACCOUNTS_FILE" 2>/dev/null || echo 0)
    active=$(jq '[.accounts[] | select(.status == "active")] | length' "$ACCOUNTS_FILE" 2>/dev/null || echo 0)
    expired=$(jq '[.accounts[] | select(.status == "expired")] | length' "$ACCOUNTS_FILE" 2>/dev/null || echo 0)

    local host_label="IP Server"
    [[ -n "$domain" ]] && host_label="Domain   "

    echo -e "${BLUE}${BOLD}"
    echo "  ╔══════════════════════════════════════════════════════════╗"
    printf '  ║         ZiVPN Account Manager %-26s ║\n' "v${ZIVPN_MANAGER_VERSION:-1.0}"
    echo "  ╚══════════════════════════════════════════════════════════╝"
    echo -e "${RESET}"
    echo -e "  ${GRAY}${host_label} :${RESET} ${WHITE}${host}${RESET}"
    echo -e "  ${GRAY}Total Akun :${RESET} ${WHITE}${total}${RESET}  |  ${GREEN}Aktif: ${active}${RESET}  |  ${RED}Expired: ${expired}${RESET}"
    divider
}

# --- Date helpers ------------------------------------------------------------

# Get current UTC timestamp in ISO 8601
now_iso() {
    date -u +"%Y-%m-%dT%H:%M:%SZ"
}

# Add N days to current date, return ISO timestamp
date_add_days() {
    local days="$1"
    date -u -d "+${days} days" +"%Y-%m-%dT%H:%M:%SZ"
}

# Format ISO timestamp to human readable: "DD Mon YYYY HH:MM UTC"
format_date() {
    local iso="$1"
    if [[ -z "$iso" || "$iso" == "null" ]]; then
        echo "Permanent"
        return
    fi
    date -u -d "$iso" +"%d %b %Y %H:%M UTC" 2>/dev/null || echo "$iso"
}

# Calculate remaining days from now to ISO date
days_remaining() {
    local iso="$1"
    if [[ -z "$iso" || "$iso" == "null" ]]; then
        echo "∞"
        return
    fi
    local now_epoch expired_epoch
    now_epoch=$(date -u +%s)
    expired_epoch=$(date -u -d "$iso" +%s 2>/dev/null) || { echo "?"; return; }
    local diff=$(( (expired_epoch - now_epoch) / 86400 ))
    echo "$diff"
}

# Check if ISO date is in the past
is_expired() {
    local iso="$1"
    [[ -z "$iso" || "$iso" == "null" ]] && return 1  # permanent = not expired
    local now_epoch expired_epoch
    now_epoch=$(date -u +%s)
    expired_epoch=$(date -u -d "$iso" +%s 2>/dev/null) || return 1
    (( expired_epoch <= now_epoch ))
}

# --- Password generator ------------------------------------------------------
generate_password() {
    local length="${1:-10}"
    tr -dc 'a-zA-Z0-9' < /dev/urandom | head -c "$length"
}

# --- Input validation --------------------------------------------------------
validate_username() {
    local username="$1"
    # Alphanumeric + underscore + hyphen, 3-32 chars
    if [[ ! "$username" =~ ^[a-zA-Z0-9_-]{3,32}$ ]]; then
        print_error "Username hanya boleh huruf, angka, underscore, hyphen (3-32 karakter)"
        return 1
    fi
    return 0
}

validate_days() {
    local days="$1"
    if [[ ! "$days" =~ ^[1-9][0-9]*$ ]]; then
        print_error "Jumlah hari harus angka positif"
        return 1
    fi
    return 0
}

validate_date() {
    local datestr="$1"
    # Accept formats: YYYY-MM-DD or YYYY-MM-DDTHH:MM:SSZ
    if ! date -d "$datestr" &>/dev/null; then
        print_error "Format tanggal tidak valid. Gunakan: YYYY-MM-DD"
        return 1
    fi
    return 0
}

# --- Confirm prompt ----------------------------------------------------------
confirm() {
    local msg="${1:-Yakin?}"
    echo -en "${YELLOW}${msg} (y/n):${RESET} "
    read -r answer
    [[ "$answer" =~ ^[Yy]$ ]]
}

# --- Press any key -----------------------------------------------------------
press_enter() {
    echo ""
    echo -en "${GRAY}Tekan [Enter] untuk kembali ke menu...${RESET}"
    read -r
}

# --- Check dependencies ------------------------------------------------------
check_deps() {
    local missing=()
    for dep in jq curl; do
        if ! command -v "$dep" &>/dev/null; then
            missing+=("$dep")
        fi
    done
    if [[ ${#missing[@]} -gt 0 ]]; then
        print_error "Dependensi tidak ditemukan: ${missing[*]}"
        print_info "Install dengan: apt-get install -y ${missing[*]}"
        exit 1
    fi
}
