#!/usr/bin/env bash
# =============================================================================
# whatsapp.sh — WhatsApp Bot configuration placeholder
# =============================================================================

config_whatsapp() {
    print_header
    echo ""
    section_title "Konfigurasi Bot WhatsApp"
    echo ""
    
    print_info "Fitur Bot WhatsApp (Integrasi Jualan & Notifikasi) akan segera hadir!"
    echo -e "    ${FG_SUBTLE}WhatsApp API membutuhkan setup server Node.js tambahan.${RESET}"
    echo -e "    ${FG_SUBTLE}Saat ini fitur masih dalam tahap riset keamanan.${RESET}"
    echo ""
    wait_for_esc
}
