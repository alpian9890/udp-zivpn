#!/bin/bash
# Zivpn UDP Module installer
# Creator Zahid Islam

echo -e "Updating server"
sudo apt-get update && apt-get upgrade -y
systemctl stop zivpn.service 1> /dev/null 2> /dev/null
echo -e "Downloading UDP Service"
wget https://github.com/alpian9890/udp-zivpn/releases/download/udp-zivpn_1.4.9/udp-zivpn-linux-amd64 -O /usr/local/bin/zivpn 1> /dev/null 2> /dev/null
chmod +x /usr/local/bin/zivpn
mkdir /etc/zivpn 1> /dev/null 2> /dev/null
wget https://raw.githubusercontent.com/alpian9890/udp-zivpn/main/config.json -O /etc/zivpn/config.json 1> /dev/null 2> /dev/null

echo "Generating cert files:"
openssl req -new -newkey rsa:4096 -days 365 -nodes -x509 -subj "/C=US/ST=California/L=Los Angeles/O=Example Corp/OU=IT Department/CN=zivpn" -keyout "/etc/zivpn/zivpn.key" -out "/etc/zivpn/zivpn.crt"
sysctl -w net.core.rmem_max=16777216 1> /dev/null 2> /dev/null
sysctl -w net.core.wmem_max=16777216 1> /dev/null 2> /dev/null
cat <<EOF > /etc/systemd/system/zivpn.service
[Unit]
Description=zivpn VPN Server
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/etc/zivpn
ExecStart=/usr/local/bin/zivpn server -c /etc/zivpn/config.json
Restart=always
RestartSec=3
Environment=ZIVPN_LOG_LEVEL=info
CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_BIND_SERVICE CAP_NET_RAW
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_BIND_SERVICE CAP_NET_RAW
NoNewPrivileges=true

[Install]
WantedBy=multi-user.target
EOF

echo -e "ZIVPN UDP Passwords"
read -p "Enter passwords separated by commas, example: pass1,pass2 (Press enter for Default 'zi'): " input_config

if [ -n "$input_config" ]; then
    IFS=',' read -r -a config <<< "$input_config"
    if [ ${#config[@]} -eq 1 ]; then
        config+=(${config[0]})
    fi
else
    config=("zi")
fi

new_config_str="\"config\": [$(printf '"%s",' "${config[@]}" | sed 's/,$//')]"

sed -i -E "s/\"config\": ?\[[ ]*\"zi\"[ ]*\]/${new_config_str}/g" /etc/zivpn/config.json

systemctl enable zivpn.service
systemctl start zivpn.service
iptables -t nat -A PREROUTING -i $(ip -4 route ls|grep default|grep -Po '(?<=dev )(\S+)'|head -1) -p udp --dport 6000:19999 -j DNAT --to-destination :5667
ufw allow 6000:19999/udp
ufw allow 5667/udp

echo -e "Installing ZiVPN Manager..."
MANAGER_TMP="/tmp/zivpn-manager-install"
rm -rf "$MANAGER_TMP"
mkdir -p "$MANAGER_TMP/lib"
wget -q "https://raw.githubusercontent.com/alpian9890/udp-zivpn/main/zivpn-manager/install.sh"        -O "$MANAGER_TMP/install.sh"
wget -q "https://raw.githubusercontent.com/alpian9890/udp-zivpn/main/zivpn-manager/zivpn-manager.sh"  -O "$MANAGER_TMP/zivpn-manager.sh"
wget -q "https://raw.githubusercontent.com/alpian9890/udp-zivpn/main/zivpn-manager/expire-checker.sh" -O "$MANAGER_TMP/expire-checker.sh"
wget -q "https://raw.githubusercontent.com/alpian9890/udp-zivpn/main/zivpn-manager/lib/utils.sh"      -O "$MANAGER_TMP/lib/utils.sh"
wget -q "https://raw.githubusercontent.com/alpian9890/udp-zivpn/main/zivpn-manager/lib/config.sh"     -O "$MANAGER_TMP/lib/config.sh"
wget -q "https://raw.githubusercontent.com/alpian9890/udp-zivpn/main/zivpn-manager/lib/account.sh"    -O "$MANAGER_TMP/lib/account.sh"
wget -q "https://raw.githubusercontent.com/alpian9890/udp-zivpn/main/zivpn-manager/lib/backup.sh"     -O "$MANAGER_TMP/lib/backup.sh"
wget -q "https://raw.githubusercontent.com/alpian9890/udp-zivpn/main/zivpn-manager/lib/help.sh"       -O "$MANAGER_TMP/lib/help.sh"
wget -q "https://raw.githubusercontent.com/alpian9890/udp-zivpn/main/zivpn-manager/lib/update.sh"     -O "$MANAGER_TMP/lib/update.sh"
wget -q "https://raw.githubusercontent.com/alpian9890/udp-zivpn/main/zivpn-manager/lib/tui.sh"        -O "$MANAGER_TMP/lib/tui.sh"
wget -q "https://raw.githubusercontent.com/alpian9890/udp-zivpn/main/zivpn-manager/lib/uninstall.sh"  -O "$MANAGER_TMP/lib/uninstall.sh"
chmod +x "$MANAGER_TMP/install.sh"
bash "$MANAGER_TMP/install.sh"
rm -rf "$MANAGER_TMP"

rm zi.* 1> /dev/null 2> /dev/null
echo -e "ZIVPN Installed"
echo -e "Jalankan 'zivpn-manager' untuk mengelola akun VPN"
