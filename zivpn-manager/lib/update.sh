#!/usr/bin/env bash
# =============================================================================
# update.sh — Check for updates and self-update from GitHub repository
# =============================================================================

GITHUB_REPO="alpian9890/udp-zivpn"
GITHUB_BRANCH="main"
GITHUB_RAW_BASE="https://raw.githubusercontent.com/${GITHUB_REPO}/${GITHUB_BRANCH}"
GITHUB_API_BASE="https://api.github.com/repos/${GITHUB_REPO}"

# Local version is defined in help.sh (ZIVPN_MANAGER_VERSION)
VERSION_FILE="${MANAGER_DIR:-/etc/zivpn/zivpn-manager}/lib/help.sh"

# Files to update (relative to repo root)
UPDATE_FILES=(
    "zivpn-manager/zivpn-manager.sh"
    "zivpn-manager/expire-checker.sh"
    "zivpn-manager/lib/utils.sh"
    "zivpn-manager/lib/config.sh"
    "zivpn-manager/lib/account.sh"
    "zivpn-manager/lib/backup.sh"
    "zivpn-manager/lib/help.sh"
    "zivpn-manager/lib/update.sh"
    "zivpn-manager/lib/tui.sh"
    "zivpn-manager/lib/uninstall.sh"
)

# ---------------------------------------------------------------------------
# get_local_version — Read current installed version
# ---------------------------------------------------------------------------
get_local_version() {
    echo "${ZIVPN_MANAGER_VERSION:-unknown}"
}

# ---------------------------------------------------------------------------
# get_remote_version — Fetch latest version from GitHub
# ---------------------------------------------------------------------------
get_remote_version() {
    local remote_help
    remote_help=$(curl -sS --max-time 10 "${GITHUB_RAW_BASE}/zivpn-manager/lib/help.sh" 2>/dev/null)
    if [[ $? -ne 0 || -z "$remote_help" ]]; then
        echo ""
        return 1
    fi
    echo "$remote_help" | grep -oP '^ZIVPN_MANAGER_VERSION="\K[^"]+' | head -1
}

# ---------------------------------------------------------------------------
# version_gt — Check if version $1 is greater than $2 (semver-ish)
# Returns 0 if $1 > $2
# ---------------------------------------------------------------------------
version_gt() {
    local v1="$1" v2="$2"
    if [[ "$v1" == "$v2" ]]; then
        return 1
    fi
    # Sort versions and check if v1 comes after v2
    local highest
    highest=$(printf '%s\n%s\n' "$v1" "$v2" | sort -V | tail -1)
    [[ "$highest" == "$v1" ]]
}

# ---------------------------------------------------------------------------
# check_update — Check if a newer version is available
# ---------------------------------------------------------------------------
check_update() {
    print_header
    echo ""
    section_title "Cek Update ZiVPN Manager"
    echo ""

    local local_ver remote_ver
    local_ver=$(get_local_version)

    echo -e "    ${FG_DIM}Versi terpasang :${RESET}  ${WHITE}v${local_ver}${RESET}"
    echo -e "    ${FG_SUBTLE}Mengecek versi terbaru...${RESET}"
    echo ""

    remote_ver=$(get_remote_version)

    if [[ -z "$remote_ver" ]]; then
        print_error "Gagal mengecek update. Pastikan server terhubung ke internet."
        echo -e "    ${FG_SUBTLE}Repository: github.com/${GITHUB_REPO}${RESET}"
        wait_for_esc
        return 1
    fi

    echo -e "    ${FG_DIM}Versi terpasang :${RESET}  ${WHITE}v${local_ver}${RESET}"
    echo -e "    ${FG_DIM}Versi terbaru   :${RESET}  ${CYAN}v${remote_ver}${RESET}"
    echo ""

    if version_gt "$remote_ver" "$local_ver"; then
        echo -e "    ${GREEN}${BOLD}⬆  Update tersedia: v${local_ver} → v${remote_ver}${RESET}"
        echo ""
        echo -e "    ${GREEN}[1]${RESET} Update ke v${remote_ver}"
        echo -e "    ${FG_SUBTLE}[2]${RESET} Gunakan versi sekarang (skip)"
        echo ""
        divider "subtle"
        echo -en "    ${FG_DIM}Pilih${RESET} [1/2]: "
        read -r choice

        case "$choice" in
            1)
                echo ""
                do_update "$remote_ver"
                ;;
            *)
                echo ""
                print_info "Update dilewati. Tetap menggunakan v${local_ver}"
                ;;
        esac
    else
        print_success "Anda sudah menggunakan versi terbaru (v${local_ver})"
    fi

    wait_for_esc
}

# ---------------------------------------------------------------------------
# do_update — Download and install the latest version
# ---------------------------------------------------------------------------
do_update() {
    local new_ver="$1"
    local install_dir="${MANAGER_DIR:-/etc/zivpn/zivpn-manager}"
    local tmp_dir
    tmp_dir=$(mktemp -d)

    echo -e "    ${BOLD}Mengunduh update v${new_ver}...${RESET}"
    echo ""

    mkdir -p "$tmp_dir/lib"

    local failed=0
    for file in "${UPDATE_FILES[@]}"; do
        local filename
        filename=$(basename "$file")
        local subdir
        subdir=$(dirname "$file" | sed 's|^zivpn-manager/||; s|^zivpn-manager$||')

        local target_dir="$tmp_dir"
        if [[ -n "$subdir" ]]; then
            target_dir="$tmp_dir/$subdir"
            mkdir -p "$target_dir"
        fi

        local url="${GITHUB_RAW_BASE}/${file}"
        echo -ne "    ${FG_SUBTLE}Mengunduh ${file}...${RESET} "

        if curl -sS --max-time 15 -o "${target_dir}/${filename}" "$url" 2>/dev/null; then
            # Verify downloaded file is not empty and not an error page
            if [[ -s "${target_dir}/${filename}" ]] && head -1 "${target_dir}/${filename}" | grep -q '^#!/'; then
                echo -e "${GREEN}✓${RESET}"
            else
                echo -e "${RED}✗ (file tidak valid)${RESET}"
                failed=1
            fi
        else
            echo -e "${RED}✗ (gagal download)${RESET}"
            failed=1
        fi
    done

    echo ""

    if [[ "$failed" -eq 1 ]]; then
        print_error "Beberapa file gagal diunduh. Update dibatalkan."
        print_info "Versi saat ini tidak berubah."
        rm -rf "$tmp_dir"
        return 1
    fi

    # All files downloaded successfully — install them
    echo -e "    ${BOLD}Menginstall update...${RESET}"

    # Backup current version
    local backup_file="/etc/zivpn/backups/zivpn-pre-update_$(date +%Y%m%d_%H%M%S).tar.gz"
    mkdir -p /etc/zivpn/backups
    tar -czf "$backup_file" -C / "etc/zivpn/zivpn-manager" 2>/dev/null
    chmod 600 "$backup_file"
    print_info "Backup versi lama: ${backup_file}"

    # Copy new files
    cp "$tmp_dir/zivpn-manager.sh"   "$install_dir/zivpn-manager.sh"
    cp "$tmp_dir/expire-checker.sh"  "$install_dir/expire-checker.sh"
    cp "$tmp_dir/lib/utils.sh"       "$install_dir/lib/utils.sh"
    cp "$tmp_dir/lib/config.sh"      "$install_dir/lib/config.sh"
    cp "$tmp_dir/lib/account.sh"     "$install_dir/lib/account.sh"
    cp "$tmp_dir/lib/backup.sh"      "$install_dir/lib/backup.sh"
    cp "$tmp_dir/lib/help.sh"        "$install_dir/lib/help.sh"
    cp "$tmp_dir/lib/update.sh"      "$install_dir/lib/update.sh"
    cp "$tmp_dir/lib/tui.sh"         "$install_dir/lib/tui.sh"
    cp "$tmp_dir/lib/uninstall.sh"   "$install_dir/lib/uninstall.sh"

    chmod +x "$install_dir/zivpn-manager.sh"
    chmod +x "$install_dir/expire-checker.sh"
    chmod 755 "$install_dir/lib/"*.sh

    rm -rf "$tmp_dir"

    echo ""
    print_success "Update berhasil! v${ZIVPN_MANAGER_VERSION} → v${new_ver}"
    echo ""
    echo -e "    ${FG_SUBTLE}Jalankan 'zivpn-manager' kembali untuk menggunakan versi baru.${RESET}"
}

# ---------------------------------------------------------------------------
# check_update_silent — Non-interactive check, returns 0 if update available
# Used for showing a notification in the header
# ---------------------------------------------------------------------------
check_update_silent() {
    local local_ver remote_ver
    local_ver=$(get_local_version)
    remote_ver=$(get_remote_version 2>/dev/null)

    if [[ -n "$remote_ver" ]] && version_gt "$remote_ver" "$local_ver"; then
        echo "$remote_ver"
        return 0
    fi
    return 1
}
