#!/bin/bash
# - ZiVPN Remover -
clear
echo -e "Uninstalling ZiVPN & Dashboard ..."

# 1. Check if zivpn-manager is installed and use its uninstall if available
if [ -f "/etc/zivpn/zivpn-manager/lib/utils.sh" ]; then
    source "/etc/zivpn/zivpn-manager/lib/utils.sh"
    source "/etc/zivpn/zivpn-manager/lib/config.sh"
    source "/etc/zivpn/zivpn-manager/lib/account.sh"
    source "/etc/zivpn/zivpn-manager/lib/backup.sh"
    source "/etc/zivpn/zivpn-manager/lib/help.sh"
    source "/etc/zivpn/zivpn-manager/lib/update.sh"
    source "/etc/zivpn/zivpn-manager/lib/telegram.sh"
    source "/etc/zivpn/zivpn-manager/lib/tui.sh"
    source "/etc/zivpn/zivpn-manager/lib/uninstall.sh"
    
    # Run the comprehensive uninstall
    _execute_uninstall
else
    # Fallback to manual cleanup if manager not found
    systemctl stop zivpn.service 1> /dev/null 2> /dev/null
    systemctl disable zivpn.service 1> /dev/null 2> /dev/null
    
    if command -v pm2 &>/dev/null; then
        pm2 delete zivpn-dashboard 2>/dev/null || true
    fi

    rm /etc/systemd/system/zivpn.service 1> /dev/null 2> /dev/null
    rm -f /etc/cron.d/zivpn-manager 2>/dev/null
    rm -f /etc/cron.d/zivpn-autobackup 2>/dev/null
    
    killall zivpn 1> /dev/null 2> /dev/null
    rm -rf /etc/zivpn 1> /dev/null 2> /dev/null
    rm /usr/local/bin/zivpn 1> /dev/null 2> /dev/null
    rm /usr/local/bin/zivpn-manager 1> /dev/null 2> /dev/null
fi

echo "Cleaning Cache & Swap"
echo 3 > /proc/sys/vm/drop_caches
sysctl -w vm.drop_caches=3 1> /dev/null 2> /dev/null
swapoff -a && swapon -a

echo ""
echo -e "\033[0;32m✓  ZiVPN has been successfully removed.\033[0m"
echo -e "Done."
