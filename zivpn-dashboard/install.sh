#!/usr/bin/env bash
# =============================================================================
# install.sh — Installer for zivpn-dashboard (Build from source)
# =============================================================================

set -e

INSTALL_DIR="/etc/zivpn/dashboard"
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
echo -e "${BOLD}${CYAN}     ZiVPN Dashboard — Installer${RESET}"
echo -e "${BOLD}${CYAN}================================================${RESET}"
echo ""

# --- Node.js Check/Install --------------------------------------------------
if ! command -v node &> /dev/null; then
    print_step "Node.js tidak ditemukan. Menginstall Node.js 20..."
    curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
    apt-get install -y nodejs
    print_success "Node.js $(node -v) terpasang"
else
    print_info "Node.js sudah terpasang: $(node -v)"
fi

# --- vnstat Install ---------------------------------------------------------
if ! command -v vnstat &> /dev/null; then
    print_step "Menginstall vnstat untuk monitoring bandwidth..."
    apt-get install -y vnstat
    systemctl enable vnstat
    systemctl start vnstat
    print_success "vnstat terpasang"
fi

# --- PM2 Check/Install ------------------------------------------------------
if ! command -v pm2 &> /dev/null; then
    print_step "Menginstall PM2 globally..."
    npm install -g pm2
    print_success "PM2 terpasang"
fi

# --- Copy Dashboard Files ---------------------------------------------------
print_step "Menyiapkan direktori dashboard..."
mkdir -p "$INSTALL_DIR"
rm -rf "${INSTALL_DIR:?}/"*

# Determine source (current dir where install.sh lives)
SOURCE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

print_info "Menyalin source code..."
cp -r "$SOURCE_DIR/client" "$INSTALL_DIR/"
cp -r "$SOURCE_DIR/server" "$INSTALL_DIR/"

# --- Build Client -----------------------------------------------------------
print_step "Building Frontend (Client)..."
cd "$INSTALL_DIR/client"
npm install --silent
npm run build
print_success "Frontend berhasil di-build"

# --- Build Server -----------------------------------------------------------
print_step "Building Backend (Server)..."
cd "$INSTALL_DIR/server"
npm install --silent
npm run build
print_success "Backend berhasil di-build"

# --- Cleanup Source ---------------------------------------------------------
print_step "Membersihkan file source yang tidak diperlukan..."
rm -rf "$INSTALL_DIR/client/node_modules"
rm -rf "$INSTALL_DIR/client/src"
# We keep server/node_modules for runtime

# --- Start with PM2 ---------------------------------------------------------
print_step "Menjalankan Dashboard dengan PM2..."
cd "$INSTALL_DIR/server"
pm2 delete zivpn-dashboard 2>/dev/null || true
NODE_ENV=production pm2 start dist/index.js --name zivpn-dashboard
pm2 save --force

echo ""
echo -e "${GREEN}${BOLD}================================================${RESET}"
echo -e "${GREEN}${BOLD}  ZiVPN Dashboard berhasil terpasang!${RESET}"
echo -e "${GREEN}${BOLD}================================================${RESET}"
echo ""
echo -e "  Akses dashboard via SSH Tunneling (Port 3000):"
echo -e "  ${CYAN}${BOLD}ssh -L 3000:localhost:3000 root@<IP_VPS>${RESET}"
echo -e "  Lalu buka ${BOLD}http://localhost:3000${RESET} di browser"
echo ""
