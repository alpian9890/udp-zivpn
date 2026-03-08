#!/usr/bin/env bash
# =============================================================================
# install.sh — Installer for zivpn-manager
# Dijalankan otomatis oleh zi.sh / zi2.sh setelah zivpn terpasang
# Bisa juga dijalankan manual: sudo bash install.sh
# =============================================================================

set -e

INSTALL_DIR="/etc/zivpn/zivpn-manager"
ACCOUNTS_FILE="/etc/zivpn/accounts.json"
ZIVPN_CONFIG="/etc/zivpn/config.json"
BIN_LINK="/usr/local/bin/zivpn-manager"
CRON_FILE="/etc/cron.d/zivpn-manager"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
RESET='\033[0m'

print_success() { echo -e "${GREEN}[✓]${RESET} $1"; }
print_error()   { echo -e "${RED}[✗]${RESET} $1"; }
print_info()    { echo -e "${CYAN}[i]${RESET} $1"; }
print_step()    { echo -e "${BOLD}[→]${RESET} $1"; }

echo ""
echo -e "${BOLD}${CYAN}================================================${RESET}"
echo -e "${BOLD}${CYAN}     ZiVPN Manager — Installer${RESET}"
echo -e "${BOLD}${CYAN}================================================${RESET}"
echo ""

# --- Root check -------------------------------------------------------------
if [[ "$EUID" -ne 0 ]]; then
    print_error "Harus dijalankan sebagai root"
    exit 1
fi

# --- Install dependencies ---------------------------------------------------
print_step "Memeriksa dependensi (jq, curl, cron)..."
for dep in jq curl; do
    if ! command -v "$dep" &>/dev/null; then
        print_info "Menginstall ${dep}..."
        apt-get install -y "$dep" -q 2>/dev/null || {
            print_error "Gagal install ${dep}. Install manual: apt-get install -y ${dep}"
            exit 1
        }
    fi
done

# Ensure cron is running
if ! systemctl is-active --quiet cron 2>/dev/null; then
    systemctl enable cron --quiet 2>/dev/null || true
    systemctl start cron 2>/dev/null || true
fi

print_success "Semua dependensi tersedia"

# --- Copy files to install dir ----------------------------------------------
print_step "Menyalin file manager ke ${INSTALL_DIR}..."

# Determine source directory (where install.sh lives)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

mkdir -p "$INSTALL_DIR/lib"

cp "$SCRIPT_DIR/zivpn-manager.sh"   "$INSTALL_DIR/zivpn-manager.sh"
cp "$SCRIPT_DIR/expire-checker.sh"  "$INSTALL_DIR/expire-checker.sh"
cp "$SCRIPT_DIR/lib/utils.sh"       "$INSTALL_DIR/lib/utils.sh"
cp "$SCRIPT_DIR/lib/config.sh"      "$INSTALL_DIR/lib/config.sh"
cp "$SCRIPT_DIR/lib/account.sh"     "$INSTALL_DIR/lib/account.sh"
cp "$SCRIPT_DIR/lib/backup.sh"      "$INSTALL_DIR/lib/backup.sh"
cp "$SCRIPT_DIR/lib/help.sh"        "$INSTALL_DIR/lib/help.sh"
cp "$SCRIPT_DIR/lib/update.sh"      "$INSTALL_DIR/lib/update.sh"

chmod +x "$INSTALL_DIR/zivpn-manager.sh"
chmod +x "$INSTALL_DIR/expire-checker.sh"
chmod 755 "$INSTALL_DIR/lib/"*.sh

print_success "File manager terpasang di ${INSTALL_DIR}"

# --- Create symlink ---------------------------------------------------------
print_step "Membuat command 'zivpn-manager'..."
ln -sf "$INSTALL_DIR/zivpn-manager.sh" "$BIN_LINK"
chmod +x "$BIN_LINK"
print_success "Command tersedia: zivpn-manager"

# --- Initialize accounts.json -----------------------------------------------
print_step "Menginisialisasi database akun..."

if [[ ! -f "$ACCOUNTS_FILE" ]]; then
    echo '{"accounts":[]}' > "$ACCOUNTS_FILE"
    chmod 600 "$ACCOUNTS_FILE"
    print_success "File ${ACCOUNTS_FILE} dibuat"
else
    print_info "File ${ACCOUNTS_FILE} sudah ada, tidak ditimpa"
fi

# --- Migrate existing passwords from config.json ----------------------------
print_step "Migrasi akun dari config.json yang sudah ada..."

if [[ -f "$ZIVPN_CONFIG" ]]; then
    existing_passwords=$(jq -r '.auth.config[]' "$ZIVPN_CONFIG" 2>/dev/null || true)
    imported=0

    while IFS= read -r pw; do
        [[ -z "$pw" || "$pw" == "__no_active_accounts__" ]] && continue

        # Check if already in accounts.json
        count=$(jq --arg p "$pw" '[.accounts[] | select(.password == $p)] | length' "$ACCOUNTS_FILE")
        if [[ "$count" -eq 0 ]]; then
            username="user_$(tr -dc 'a-z0-9' < /dev/urandom | head -c 6)"
            now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
            new_entry=$(jq -n \
                --arg u  "$username" \
                --arg pw "$pw" \
                --arg ca "$now" \
                '{username: $u, password: $pw, created_at: $ca, expired_at: null,
                  status: "active", trial: false, note: "migrated"}')
            tmp=$(mktemp)
            jq --argjson entry "$new_entry" '.accounts += [$entry]' "$ACCOUNTS_FILE" > "$tmp" && mv "$tmp" "$ACCOUNTS_FILE"
            imported=$((imported + 1))
            print_info "Akun diimpor: ${username} (password: ${pw})"
        fi
    done <<< "$existing_passwords"

    if [[ "$imported" -gt 0 ]]; then
        print_success "${imported} akun berhasil diimpor dari config.json"
    else
        print_info "Tidak ada akun baru untuk diimpor"
    fi
fi

# --- Setup cron job ---------------------------------------------------------
print_step "Memasang cron job expire checker (setiap jam)..."

cat > "$CRON_FILE" <<EOF
# ZiVPN Manager — Auto expire checker
0 * * * * root $INSTALL_DIR/expire-checker.sh >> /var/log/zivpn-expire.log 2>&1
EOF

chmod 644 "$CRON_FILE"
print_success "Cron job terpasang: ${CRON_FILE}"

# --- Done -------------------------------------------------------------------
echo ""
echo -e "${GREEN}${BOLD}================================================${RESET}"
echo -e "${GREEN}${BOLD}  ZiVPN Manager berhasil terpasang!${RESET}"
echo -e "${GREEN}${BOLD}================================================${RESET}"
echo ""
echo -e "  Jalankan manager dengan perintah:"
echo -e "  ${CYAN}${BOLD}zivpn-manager${RESET}"
echo ""
