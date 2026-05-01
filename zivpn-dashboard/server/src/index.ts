import express from "express";
import cors from "cors";
import fs from "fs/promises";
import { exec } from "child_process";
import { promisify } from "util";
import path from "path";

const execAsync = promisify(exec);
const app = express();

app.use(cors());
app.use(express.json());

// Serve React static files
app.use(express.static(path.join(__dirname, "../../client/dist")));

const PORT = Number(process.env.PORT) || 3000;
const ACCOUNTS_FILE = process.env.ACCOUNTS_FILE || "/etc/zivpn/accounts.json";
const CONFIG_FILE = process.env.CONFIG_FILE || "/etc/zivpn/config.json";
const TELEGRAM_CONFIG = "/etc/zivpn/telegram.conf";
const CRON_FILE = "/etc/cron.d/zivpn-autobackup";
const IS_DEV = process.env.NODE_ENV !== "production";

// --- Helpers ---
async function readAccounts() {
  try {
    const data = await fs.readFile(ACCOUNTS_FILE, "utf-8");
    return JSON.parse(data);
  } catch (error) {
    if (IS_DEV) {
      console.warn(`Failed reading ${ACCOUNTS_FILE}, creating empty file...`);
      const empty = { accounts: [] };
      await fs.writeFile(ACCOUNTS_FILE, JSON.stringify(empty));
      return empty;
    }
    throw error;
  }
}

async function writeAccounts(data: any) {
  await fs.writeFile(ACCOUNTS_FILE, JSON.stringify(data, null, 2));
}

async function syncConfigAndRestart() {
  if (IS_DEV) {
    console.log("DEV: Skipping config sync and service restart");
    return;
  }
  
  try {
    const accountsData = await readAccounts();
    const activePasswords = accountsData.accounts
      .filter((acc: any) => acc.status === "active")
      .map((acc: any) => acc.password);
      
    if (activePasswords.length === 0) {
      activePasswords.push("__no_active_accounts__");
    }

    const configStr = await fs.readFile(CONFIG_FILE, "utf-8");
    const configData = JSON.parse(configStr);
    configData.auth.config = activePasswords;
    await fs.writeFile(CONFIG_FILE, JSON.stringify(configData, null, 2));
    
    await execAsync("systemctl restart zivpn.service");
  } catch (error) {
    console.error("Error during sync and restart:", error);
    throw error;
  }
}

function generatePassword(length = 10) {
  const chars = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789";
  let result = "";
  for (let i = 0; i < length; i++) {
    result += chars.charAt(Math.floor(Math.random() * chars.length));
  }
  return result;
}

// --- Endpoints ---

app.get("/api/status", async (req, res) => {
  try {
    if (IS_DEV) {
      return res.json({ status: "active", metrics: { cpu: "5% (1 Core)", ram: "20% (1.0G)", uptime: "10 days", ipv4: "192.168.1.1", ipv6: "::1" } });
    }
    
    // Attempt to parse actual metrics via bash wrappers or system tools
    const { stdout: systemctlStatus } = await execAsync("systemctl is-active zivpn.service").catch(e => ({ stdout: "stopped" }));
    const serviceActive = systemctlStatus.trim() === "active";
    
    const { stdout: cpuRaw } = await execAsync("top -bn1 | grep 'Cpu(s)' | awk '{print $2 + $4}'");
    const { stdout: coresRaw } = await execAsync("nproc").catch(() => ({ stdout: "1" }));
    const cpu = `${cpuRaw.trim()}% (${coresRaw.trim()} Core${parseInt(coresRaw.trim()) > 1 ? 's' : ''})`;
    
    const { stdout: ramPercentRaw } = await execAsync("free -m | awk 'NR==2{printf \"%.2f%%\", $3*100/$2 }'");
    const { stdout: ramTotalRaw } = await execAsync("free -h | awk '/^Mem:/{print $2}'").catch(() => ({ stdout: "Unknown" }));
    const ram = `${ramPercentRaw.trim()} (${ramTotalRaw.trim()})`;
    
    const { stdout: uptime } = await execAsync("uptime -p");
    
    const { stdout: ipv4 } = await execAsync("curl -s4 -m 3 https://api.ipify.org || echo 'Unknown'");
    const { stdout: ipv6 } = await execAsync("curl -s6 -m 3 https://api6.ipify.org || echo 'Unknown'");
    
    res.json({
      status: serviceActive ? "active" : "stopped",
      metrics: {
        cpu,
        ram,
        uptime: uptime.trim(),
        ipv4: ipv4.trim(),
        ipv6: ipv6.trim()
      }
    });
  } catch (error: any) {
    res.status(500).json({ error: error.message });
  }
});

app.get("/api/logs", async (req, res) => {
  try {
    if (IS_DEV) {
      return res.json({ logs: "DEV: Simulated log output\\nLine 2...\\nLine 3..." });
    }
    const { stdout: logs } = await execAsync("journalctl -u zivpn.service -n 100 --no-pager");
    res.json({ logs });
  } catch (error: any) {
    res.status(500).json({ error: error.message });
  }
});

app.get("/api/bandwidth", async (req, res) => {
  try {
    if (IS_DEV) {
      // Return mock data for 30 days
      return res.json({
        interfaces: [{
          name: "eth0",
          traffic: {
            day: Array.from({length: 30}).map((_, i) => ({
              date: { year: new Date().getFullYear(), month: new Date().getMonth() + 1, day: i + 1 },
              rx: Math.random() * 1024 * 1024 * 1024 * 5,
              tx: Math.random() * 1024 * 1024 * 1024 * 10
            }))
          }
        }]
      });
    }
    const { stdout } = await execAsync("vnstat -d --json");
    res.json(JSON.parse(stdout));
  } catch (error: any) {
    res.status(500).json({ error: "Failed to fetch bandwidth data. Is vnstat installed?" });
  }
});

app.get("/api/users", async (req, res) => {
  try {
    const data = await readAccounts();
    res.json(data.accounts || []);
  } catch (error: any) {
    res.status(500).json({ error: error.message });
  }
});

app.post("/api/users", async (req, res) => {
  try {
    let { username, password, days } = req.body;
    if (!username) return res.status(400).json({ error: "Username required" });
    if (!password) password = generatePassword();
    
    const daysNum = parseInt(days) || 30;
    const createdAt = new Date().toISOString().replace(/\.\d{3}Z$/, "Z");
    const expiredAt = new Date(Date.now() + daysNum * 24 * 60 * 60 * 1000).toISOString().replace(/\.\d{3}Z$/, "Z");
    
    const data = await readAccounts();
    if (data.accounts.find((a: any) => a.username === username)) {
      return res.status(400).json({ error: "Username already exists" });
    }
    
    const newAccount = {
      username,
      password,
      created_at: createdAt,
      expired_at: expiredAt,
      status: "active",
      trial: false,
      note: ""
    };
    
    data.accounts.push(newAccount);
    await writeAccounts(data);
    await syncConfigAndRestart();
    
    res.json(newAccount);
  } catch (error: any) {
    res.status(500).json({ error: error.message });
  }
});

app.delete("/api/users/:username", async (req, res) => {
  try {
    const { username } = req.params;
    const data = await readAccounts();
    const initialLen = data.accounts.length;
    data.accounts = data.accounts.filter((a: any) => a.username !== username);
    
    if (data.accounts.length === initialLen) {
      return res.status(404).json({ error: "User not found" });
    }
    
    await writeAccounts(data);
    await syncConfigAndRestart();
    res.json({ success: true });
  } catch (error: any) {
    res.status(500).json({ error: error.message });
  }
});

app.put("/api/users/:username/extend", async (req, res) => {
  try {
    const { username } = req.params;
    const { days } = req.body;
    const daysNum = parseInt(days) || 30;
    
    const data = await readAccounts();
    const account = data.accounts.find((a: any) => a.username === username);
    if (!account) return res.status(404).json({ error: "User not found" });
    
    let currentExp = account.expired_at ? new Date(account.expired_at).getTime() : 0;
    if (isNaN(currentExp) || currentExp < Date.now()) {
      currentExp = Date.now();
    }
    
    account.expired_at = new Date(currentExp + daysNum * 24 * 60 * 60 * 1000).toISOString().replace(/\.\d{3}Z$/, "Z");
    account.status = "active";
    account.trial = false;
    
    await writeAccounts(data);
    await syncConfigAndRestart();
    res.json(account);
  } catch (error: any) {
    res.status(500).json({ error: error.message });
  }
});

app.post("/api/service/restart", async (req, res) => {
  try {
    if (IS_DEV) {
      return res.json({ success: true, msg: "DEV: Service restarted" });
    }
    await execAsync("systemctl restart zivpn.service");
    res.json({ success: true });
  } catch (error: any) {
    res.status(500).json({ error: error.message });
  }
});

app.get("/api/settings/telegram", async (req, res) => {
  try {
    let token = "";
    let chatId = "";
    let cronHour = "";
    
    try {
      const confStr = await fs.readFile(TELEGRAM_CONFIG, "utf-8");
      const tokenMatch = confStr.match(/BOT_TOKEN="([^"]+)"/);
      const chatMatch = confStr.match(/CHAT_ID="([^"]+)"/);
      if (tokenMatch) token = tokenMatch[1];
      if (chatMatch) chatId = chatMatch[1];
    } catch (e) {}
    
    try {
      const cronStr = await fs.readFile(CRON_FILE, "utf-8");
      const cronMatch = cronStr.match(/^0 ([0-9]+) \* \* \*/);
      if (cronMatch) cronHour = cronMatch[1];
    } catch (e) {}

    res.json({ botToken: token, chatId, cronHour });
  } catch (error: any) {
    res.status(500).json({ error: error.message });
  }
});

app.post("/api/settings/telegram", async (req, res) => {
  try {
    const { botToken, chatId, cronHour } = req.body;
    
    if (botToken && chatId) {
      await fs.writeFile(TELEGRAM_CONFIG, `BOT_TOKEN="${botToken}"\nCHAT_ID="${chatId}"\n`);
      await execAsync(`chmod 600 ${TELEGRAM_CONFIG}`);
    } else {
      await fs.unlink(TELEGRAM_CONFIG).catch(() => {});
    }

    if (cronHour !== undefined && cronHour !== "") {
      const hour = parseInt(cronHour);
      if (hour >= 0 && hour <= 23) {
        const scriptPath = "/etc/zivpn/auto_backup.sh";
        const scriptContent = `#!/bin/bash
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
MANAGER_DIR="/root/project-tunneling-zivpn/udp-zivpn/zivpn-manager" # fallback
[[ -d "/etc/zivpn/zivpn-manager" ]] && MANAGER_DIR="/etc/zivpn/zivpn-manager"
source "$MANAGER_DIR/lib/utils.sh"
source "$MANAGER_DIR/lib/telegram.sh"
BACKUP_DIR="/etc/zivpn/backups"
mkdir -p "$BACKUP_DIR"
timestamp=$(date +"%Y%m%d_%H%M%S")
backup_file="\${BACKUP_DIR}/zivpn-backup_auto_\${timestamp}.tar.gz"
files=("/etc/zivpn/accounts.json" "/etc/zivpn/config.json" "/etc/zivpn/manager.conf" "/etc/zivpn/zivpn.crt" "/etc/zivpn/zivpn.key")
to_backup=()
for f in "\${files[@]}"; do [[ -f "$f" ]] && to_backup+=("$f"); done
[[ \${#to_backup[@]} -eq 0 ]] && exit 0
tar -czf "$backup_file" -C / "\${to_backup[@]/#\\//}" 2>/dev/null
chmod 600 "$backup_file"
send_backup_to_telegram "$backup_file" >/dev/null 2>&1
find "$BACKUP_DIR" -name "zivpn-backup_auto_*.tar.gz" -type f | sort -r | tail -n +6 | xargs -r rm -f
`;
        await fs.writeFile(scriptPath, scriptContent);
        await execAsync(`chmod +x ${scriptPath}`);
        await fs.writeFile(CRON_FILE, `0 ${hour} * * * root ${scriptPath}\n`);
        await execAsync(`chmod 644 ${CRON_FILE}`);
        await execAsync("systemctl reload cron || systemctl reload crond").catch(() => {});
      }
    } else {
      await fs.unlink(CRON_FILE).catch(() => {});
      await execAsync("systemctl reload cron || systemctl reload crond").catch(() => {});
    }
    
    res.json({ success: true });
  } catch (error: any) {
    res.status(500).json({ error: error.message });
  }
});

app.post("/api/backup/telegram", async (req, res) => {
  try {
    let confStr;
    try {
      confStr = await fs.readFile(TELEGRAM_CONFIG, "utf-8");
    } catch(e) {
      return res.status(400).json({ error: "Telegram Bot Token and Chat ID not configured." });
    }
    const tokenMatch = confStr.match(/BOT_TOKEN="([^"]+)"/);
    const chatMatch = confStr.match(/CHAT_ID="([^"]+)"/);
    if (!tokenMatch || !chatMatch) {
      return res.status(400).json({ error: "Telegram Bot Token and Chat ID not configured." });
    }
    
    const botToken = tokenMatch[1];
    const chatId = chatMatch[1];
    
    await execAsync("mkdir -p /etc/zivpn/backups");
    
    const d = new Date();
    const pad = (n: number) => n.toString().padStart(2, '0');
    const timestamp = `${d.getFullYear()}${pad(d.getMonth()+1)}${pad(d.getDate())}_${pad(d.getHours())}${pad(d.getMinutes())}${pad(d.getSeconds())}`;
    const backupFile = `/etc/zivpn/backups/zivpn-backup_${timestamp}.tar.gz`;
    
    const filesToBackup = [
      "/etc/zivpn/accounts.json",
      "/etc/zivpn/config.json",
      "/etc/zivpn/manager.conf",
      "/etc/zivpn/zivpn.crt",
      "/etc/zivpn/zivpn.key"
    ];
    
    const existingFiles = [];
    for (const f of filesToBackup) {
      try { await fs.access(f); existingFiles.push(f.replace(/^\//, "")); } catch(e) {}
    }
    
    if (existingFiles.length === 0) return res.status(400).json({ error: "No files to backup" });
    
    await execAsync(`tar -czf ${backupFile} -C / ${existingFiles.join(' ')}`);
    await execAsync(`chmod 600 ${backupFile}`);
    
    let hostname = "Unknown";
    try {
      const { stdout: domain } = await execAsync("source /etc/zivpn/manager.conf 2>/dev/null && echo $CUSTOM_DOMAIN").catch(() => ({stdout: ""}));
      if (domain.trim()) {
        hostname = domain.trim();
      } else {
        const { stdout: ipv4 } = await execAsync("curl -s4 -m 3 https://api.ipify.org || echo 'Unknown'");
        hostname = ipv4.trim();
      }
    } catch(e) {}
    
    const caption = `📦 *ZiVPN Backup* - ${hostname}\n\nBackup file: \`zivpn-backup_${timestamp}.tar.gz\``;
    
    const { stdout } = await execAsync(`curl -s -X POST "https://api.telegram.org/bot${botToken}/sendDocument" -F chat_id="${chatId}" -F document=@"${backupFile}" -F caption="${caption}" -F parse_mode="Markdown"`);
    
    const tgRes = JSON.parse(stdout);
    if (!tgRes.ok) {
      return res.status(400).json({ error: "Failed to send backup to Telegram: " + tgRes.description });
    }
    
    res.json({ success: true, message: "Backup successfully sent to Telegram." });
  } catch (error: any) {
    res.status(500).json({ error: error.message });
  }
});

// Catch-all route to serve the React app
app.use((req, res) => {
  res.sendFile(path.join(__dirname, "../../client/dist/index.html"));
});

app.listen(PORT, "127.0.0.1", () => {
  console.log(`Zivpn Dashboard Server listening on http://127.0.0.1:${PORT}`);
});
