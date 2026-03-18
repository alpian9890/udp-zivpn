#!/usr/bin/env bash
# =============================================================================
# telegram.sh — Telegram Bot config and notification helpers
# =============================================================================

TELEGRAM_CONFIG="/etc/zivpn/telegram.conf"

config_telegram_backup() {
    print_header
    echo ""
    section_title "Konfigurasi Bot Telegram (Backup)"
    echo ""

    local current_token="" current_chat_id=""
    if [[ -f "$TELEGRAM_CONFIG" ]]; then
        source "$TELEGRAM_CONFIG"
        current_token="$BOT_TOKEN"
        current_chat_id="$CHAT_ID"
    fi

    if [[ -n "$current_token" && -n "$current_chat_id" ]]; then
        echo -e "    ${FG_DIM}Status      :${RESET}  ${GREEN}Terkonfigurasi${RESET}"
        echo -e "    ${FG_DIM}Chat ID     :${RESET}  ${CYAN}${current_chat_id}${RESET}"
    else
        echo -e "    ${FG_DIM}Status      :${RESET}  ${FG_SUBTLE}Belum dikonfigurasi${RESET}"
    fi

    echo -e "    ${FG_SUBTLE}Ketik '0' untuk membatalkan tanpa mengubah apa pun.${RESET}"
    echo -e "    ${FG_SUBTLE}Kosongkan input dan tekan Enter untuk menghapus konfigurasi.${RESET}"
    echo ""

    flush_stdin

    local new_token new_chat_id
    echo -en "    ${FG_DIM}Bot Token baru:${RESET} "
    read -r new_token
    new_token=$(echo "$new_token" | tr -d ' ')

    if [[ "$new_token" == "0" ]]; then
        print_info "Dibatalkan."
        wait_for_esc
        return
    fi

    if [[ -z "$new_token" ]]; then
        if [[ -f "$TELEGRAM_CONFIG" ]]; then
            confirm "  Hapus konfigurasi Telegram?" || { wait_for_esc; return; }
            rm -f "$TELEGRAM_CONFIG"
            print_success "Konfigurasi Telegram dihapus."
        else
            print_info "Dibatalkan."
        fi
        wait_for_esc
        return
    fi

    echo -en "    ${FG_DIM}Chat ID baru${RESET} ${FG_SUBTLE}(0 = batal):${RESET} "
    read -r new_chat_id
    new_chat_id=$(echo "$new_chat_id" | tr -d ' ')

    if [[ "$new_chat_id" == "0" ]]; then
        print_info "Dibatalkan."
        wait_for_esc
        return
    fi

    if [[ -z "$new_chat_id" ]]; then
        print_error "Chat ID tidak boleh kosong jika Token diisi."
        wait_for_esc
        return
    fi

    # Save to local server safely
    echo "BOT_TOKEN=\"${new_token}\"" > "$TELEGRAM_CONFIG"
    echo "CHAT_ID=\"${new_chat_id}\"" >> "$TELEGRAM_CONFIG"
    chmod 600 "$TELEGRAM_CONFIG"

    print_success "Konfigurasi Telegram berhasil disimpan!"
    echo ""
    print_info "Mengirim pesan test ke Telegram..."
    
    local test_msg
    printf -v test_msg "✅ *ZiVPN Manager*\nKonfigurasi Telegram berhasil dihubungkan ke server!"
    
    local response
    response=$(curl -s -X POST "https://api.telegram.org/bot${new_token}/sendMessage" \
        -d chat_id="${new_chat_id}" \
        --data-urlencode text="${test_msg}" \
        -d parse_mode="Markdown")

    if echo "$response" | grep -q '"ok":true'; then
        print_success "Pesan test terkirim! Cek aplikasi Telegram Anda."
    else
        print_error "Gagal mengirim pesan test. Pastikan Token dan Chat ID benar,"
        print_error "dan Anda sudah klik START / mengirim pesan ke bot tersebut."
    fi

    wait_for_esc
}

send_backup_to_telegram() {
    local file_path="$1"
    if [[ ! -f "$TELEGRAM_CONFIG" ]]; then
        return 1
    fi

    source "$TELEGRAM_CONFIG"
    if [[ -z "$BOT_TOKEN" || -z "$CHAT_ID" ]]; then
        return 1
    fi

    echo ""
    print_info "Mengirim file backup ke Telegram..."
    local hostname
    hostname=$(get_server_host)
    
    local caption
    printf -v caption "📦 *ZiVPN Backup* - %s\n\nBackup file: \`%s\`" "$hostname" "$(basename "$file_path")"

    local response
    response=$(curl -s -X POST "https://api.telegram.org/bot${BOT_TOKEN}/sendDocument" \
        -F chat_id="${CHAT_ID}" \
        -F document=@"${file_path}" \
        -F caption="${caption}" \
        -F parse_mode="Markdown")

    if echo "$response" | grep -q '"ok":true'; then
        print_success "Backup berhasil dikirim ke Telegram!"
        return 0
    else
        print_error "Gagal mengirim backup ke Telegram."
        return 1
    fi
}

config_telegram_jualan() {
    print_header
    echo ""
    section_title "Konfigurasi Bot Jualan"
    echo ""
    print_info "Fitur Bot Jualan (Integrasi Pembayaran, dll) akan segera hadir!"
    echo -e "    ${FG_SUBTLE}Saat ini fitur masih dalam tahap pengembangan.${RESET}"
    wait_for_esc
}

config_auto_backup() {
    print_header
    echo ""
    section_title "Konfigurasi Auto Backup"
    echo ""
    
    local cron_file="/etc/cron.d/zivpn-autobackup"
    local current_cron=""
    if [[ -f "$cron_file" ]]; then
        current_cron=$(grep -oP '^0 \K[0-9]+' "$cron_file" 2>/dev/null)
    fi

    if [[ -n "$current_cron" ]]; then
        echo -e "    ${FG_DIM}Status      :${RESET}  ${GREEN}Aktif${RESET}"
        echo -e "    ${FG_DIM}Jadwal      :${RESET}  ${WHITE}Setiap hari jam ${current_cron}:00 server${RESET}"
    else
        echo -e "    ${FG_DIM}Status      :${RESET}  ${FG_SUBTLE}Nonaktif${RESET}"
    fi

    echo ""
    echo -e "    ${FG_SUBTLE}Masukkan jam (0-23) kapan Auto Backup dilakukan.${RESET}"
    echo -e "    ${FG_SUBTLE}Kosongkan input untuk menonaktifkan Auto Backup.${RESET}"
    echo -e "    ${FG_SUBTLE}Ketik 'c' atau '000' untuk batal.${RESET}"
    echo ""

    flush_stdin

    local hour
    echo -en "    ${FG_DIM}Jam Auto Backup:${RESET} "
    read -r hour
    hour=$(echo "$hour" | tr -d ' ')

    if [[ "$hour" == "c" || "$hour" == "C" || "$hour" == "000" ]]; then
        print_info "Dibatalkan."
        wait_for_esc
        return
    fi

    if [[ -z "$hour" ]]; then
        if [[ -f "$cron_file" ]]; then
            confirm "  Matikan Auto Backup?" || { wait_for_esc; return; }
            rm -f "$cron_file"
            systemctl reload cron 2>/dev/null || systemctl reload crond 2>/dev/null
            print_success "Auto Backup dinonaktifkan."
        else
            print_info "Auto Backup memang belum aktif."
        fi
        wait_for_esc
        return
    fi

    if [[ ! "$hour" =~ ^([0-9]|1[0-9]|2[0-3])$ ]]; then
        print_error "Input tidak valid. Masukkan angka 0 sampai 23."
        wait_for_esc
        return
    fi

    # Buat script auto backup command jika belum ada
    local script_path="/etc/zivpn/auto_backup.sh"
    cat << 'EOF' > "$script_path"
#!/bin/bash
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
MANAGER_DIR="/root/project-tunneling-zivpn/udp-zivpn/zivpn-manager" # fallback
[[ -d "/etc/zivpn/zivpn-manager" ]] && MANAGER_DIR="/etc/zivpn/zivpn-manager"
source "$MANAGER_DIR/lib/utils.sh"
source "$MANAGER_DIR/lib/telegram.sh"
BACKUP_DIR="/etc/zivpn/backups"
mkdir -p "$BACKUP_DIR"
timestamp=$(date +"%Y%m%d_%H%M%S")
backup_file="${BACKUP_DIR}/zivpn-backup_auto_${timestamp}.tar.gz"
files=("/etc/zivpn/accounts.json" "/etc/zivpn/config.json" "/etc/zivpn/manager.conf" "/etc/zivpn/zivpn.crt" "/etc/zivpn/zivpn.key")
to_backup=()
for f in "${files[@]}"; do [[ -f "$f" ]] && to_backup+=("$f"); done
[[ ${#to_backup[@]} -eq 0 ]] && exit 0
tar -czf "$backup_file" -C / "${to_backup[@]/#\//}" 2>/dev/null
chmod 600 "$backup_file"
send_backup_to_telegram "$backup_file" >/dev/null 2>&1
# Hapus backup lama (sisakan 5 terbaru)
find "$BACKUP_DIR" -name "zivpn-backup_auto_*.tar.gz" -type f | sort -r | tail -n +6 | xargs -r rm -f
EOF
    chmod +x "$script_path"

    # Setup cron
    echo "0 $hour * * * root $script_path" > "$cron_file"
    chmod 644 "$cron_file"
    systemctl reload cron 2>/dev/null || systemctl reload crond 2>/dev/null

    print_success "Auto Backup diatur berjalan setiap jam ${hour}:00!"
    wait_for_esc
}

menu_telegram() {
    local telegram_items=(
        "Config Bot Backup|config-bot-backup"
        "Config Bot Jualan|config-bot-jualan"
        "Auto Backup|auto-backup"
        "-"
        "Kembali|__exit__"
    )

    while true; do
        local action
        action=$(tui_menu "MENU BOT TELEGRAM" telegram_items)

        case "$action" in
            config-bot-backup) config_telegram_backup ;;
            config-bot-jualan) config_telegram_jualan ;;
            auto-backup)       config_auto_backup ;;
            __exit__)          return 0 ;;
            *)                 return 0 ;;
        esac
    done
}