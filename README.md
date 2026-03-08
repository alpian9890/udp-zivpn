![ZIVPN](zivpn.png)

# udp-zivpn

UDP server installation for ZIVPN Tunnel (SSH/DNS/UDP) VPN app.

> Server binary for Linux amd64 and arm64.

---

## Instalasi

### AMD64 (VPS / Dedicated Server)

```bash
wget -O zi.sh https://raw.githubusercontent.com/alpian9890/udp-zivpn/main/zi.sh; sudo chmod +x zi.sh; sudo ./zi.sh
```

### ARM64 (Raspberry Pi, Oracle ARM, dll)

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/alpian9890/udp-zivpn/main/zi2.sh)
```

### Uninstall

```bash
sudo wget -O ziun.sh https://raw.githubusercontent.com/alpian9890/udp-zivpn/main/uninstall.sh; sudo chmod +x ziun.sh; sudo ./ziun.sh
```

---

## ZiVPN Manager

ZiVPN Manager adalah tool berbasis terminal untuk mengelola akun VPN, backup data, dan mengontrol service ZiVPN. Tersedia dalam mode **menu interaktif** dan **command line langsung**.

### Menjalankan Manager

```bash
# Mode interaktif (menu)
zivpn-manager

# Mode command line langsung
zivpn-manager <perintah>

# Lihat bantuan
zivpn-manager help

# Bantuan untuk perintah tertentu
zivpn-manager help <perintah>
```

---

### Daftar Perintah

| Perintah | Menu | Deskripsi |
|----------|------|-----------|
| `list` | `[3]` | Lihat daftar semua akun |
| `add` | `[1]` | Tambah akun baru |
| `delete` | `[2]` | Hapus akun |
| `trial` | `[6]` | Buat akun trial (durasi pendek) |
| `extend` | `[5]` | Perpanjang masa aktif akun |
| `set-expired` | `[4]` | Set tanggal expired akun |
| `backup` | `[b]` | Buat backup data |
| `restore` | `[r]` | Restore data dari backup |
| `backups` | `[l]` | Lihat daftar file backup |
| `status` | `[9]` | Lihat status service |
| `restart` | `[8]` | Restart service |
| `info` | `[i]` | Info server & konfigurasi |
| `help` | `[h]` | Tampilkan bantuan |
| `update` | `[u]` | Cek dan install update dari GitHub |
| `version` | — | Tampilkan versi |
| `expire-check` | — | Cek akun expired (cron) |

---

### Manajemen Akun

#### Tambah Akun

Membuat akun VPN baru dengan username, password, dan durasi masa aktif.

```bash
zivpn-manager add
```

Contoh:
```
Username (3-32 karakter): john_doe
Password [Enter = auto: aB3kX9mP2q]:
Durasi (hari) [Enter = 30]: 60
```

Setelah dibuat, info koneksi akan ditampilkan untuk diberikan ke pengguna (host, port, username, password, expired).

#### Hapus Akun

Menghapus akun secara permanen. Disarankan untuk membuat backup terlebih dahulu.

```bash
zivpn-manager delete
```

#### Lihat Daftar Akun

Menampilkan tabel semua akun beserta status, tanggal expired, dan sisa hari masa aktif.

```bash
zivpn-manager list
```

Contoh output:
```
No   Username         Password       Status     Expired At             Sisa
1    john_doe         aB3kX9mP2q     aktif      15 Apr 2026 00:00 UTC  38 hari
2    trial_user       xK7pQ2wR       trial      10 Mar 2026 00:00 UTC  2 hari
3    old_user         mN4vL8tY       expired    01 Mar 2026 00:00 UTC  Expired
```

#### Perpanjang Akun

Menambah durasi masa aktif akun. Jika akun masih aktif, hari ditambahkan dari tanggal expired saat ini. Jika sudah expired, dihitung dari sekarang.

```bash
zivpn-manager extend
```

Contoh:
```
Username: john_doe
Tambah berapa hari [Enter = 30]: 30
```

#### Set Expired

Mengatur tanggal expired akun secara manual ke tanggal tertentu.

```bash
zivpn-manager set-expired
```

Contoh:
```
Username: john_doe
Tanggal expired baru (YYYY-MM-DD): 2026-06-30
```

#### Buat Akun Trial

Membuat akun percobaan dengan durasi pendek (default 1 hari). Password di-generate otomatis.

```bash
zivpn-manager trial
```

---

### Backup & Restore

Fitur backup memudahkan migrasi data ke server baru tanpa kehilangan data pelanggan.

#### Membuat Backup

Membuat file `.tar.gz` berisi semua data penting ZiVPN:
- `accounts.json` — Database akun pengguna
- `config.json` — Konfigurasi service
- `manager.conf` — Konfigurasi manager (custom domain, dll)
- `zivpn.crt` & `zivpn.key` — Sertifikat SSL

```bash
zivpn-manager backup
```

File backup disimpan di `/etc/zivpn/backups/` dengan nama mengandung timestamp, contoh: `zivpn-backup_20260308_193000.tar.gz`.

#### Restore dari Backup

Mengembalikan data dari file backup. Sebelum restore, data saat ini otomatis di-backup sebagai safety net.

```bash
zivpn-manager restore
```

Anda bisa memilih dari daftar backup yang tersedia atau memasukkan path file secara manual.

#### Lihat Daftar Backup

```bash
zivpn-manager backups
```

#### Panduan Migrasi Server

1. **Di server lama**, buat backup:
   ```bash
   zivpn-manager backup
   ```

2. **Salin** file backup ke server baru:
   ```bash
   scp /etc/zivpn/backups/zivpn-backup_*.tar.gz root@IP_SERVER_BARU:/tmp/
   ```

3. **Di server baru**, install ZiVPN terlebih dahulu:
   ```bash
   # AMD64
   wget -O zi.sh https://raw.githubusercontent.com/alpian9890/udp-zivpn/main/zi.sh; sudo chmod +x zi.sh; sudo ./zi.sh

   # ARM64
   bash <(curl -fsSL https://raw.githubusercontent.com/alpian9890/udp-zivpn/main/zi2.sh)
   ```

4. **Pindahkan** file backup ke direktori backups:
   ```bash
   mkdir -p /etc/zivpn/backups
   mv /tmp/zivpn-backup_*.tar.gz /etc/zivpn/backups/
   ```

5. **Restore** data:
   ```bash
   zivpn-manager restore
   ```

   Semua akun, konfigurasi, dan sertifikat akan dikembalikan. Service otomatis di-restart.

---

### Service

#### Status Service

```bash
zivpn-manager status
```

#### Restart Service

```bash
zivpn-manager restart
```

> Service otomatis di-restart setiap kali ada perubahan akun (tambah, hapus, perpanjang, dll).

---

### Info Server

Menampilkan IP publik, custom domain, port, obfuscation, dan status service.

```bash
zivpn-manager info
```

---

### Custom Domain

Set custom domain yang sudah di-pointing ke IP server. Domain ini akan ditampilkan di header dan info akun.

Tersedia melalui menu interaktif: `zivpn-manager` → pilih `[7] Custom Domain`.

---

### Sistem Expired Otomatis

Cron job berjalan setiap jam untuk memeriksa akun yang sudah melewati tanggal expired. Akun expired otomatis dinonaktifkan dan dihapus dari konfigurasi service.

File cron: `/etc/cron.d/zivpn-manager`
Log: `/var/log/zivpn-expire.log`

---

### Struktur File

```
/etc/zivpn/
├── config.json              Konfigurasi service ZiVPN
├── accounts.json            Database akun pengguna
├── manager.conf             Konfigurasi manager
├── zivpn.crt                Sertifikat SSL
├── zivpn.key                Private key SSL
├── backups/                 Direktori file backup
│   └── zivpn-backup_*.tar.gz
└── zivpn-manager/
    ├── zivpn-manager.sh     Script utama
    ├── expire-checker.sh    Script cron expire
    └── lib/
        ├── utils.sh         Helper: warna, format, validasi
        ├── config.sh        Sync config & service control
        ├── account.sh       Manajemen akun
        ├── backup.sh        Backup & restore
        ├── help.sh          Sistem bantuan
        └── update.sh        Cek & install update
```

---

### Update

ZiVPN Manager bisa diperbarui langsung dari terminal tanpa perlu install ulang.

```bash
zivpn-manager update
```

Cara kerja:
1. Membandingkan versi lokal dengan versi terbaru di GitHub
2. Jika ada versi baru, menampilkan pilihan untuk update atau skip
3. Jika memilih update, semua file manager diunduh dan diganti otomatis
4. Backup versi lama dibuat otomatis sebelum update

> Data akun (`accounts.json`) dan konfigurasi tidak terpengaruh oleh update.

---

### Bantuan

```bash
# Bantuan umum
zivpn-manager help

# Bantuan per perintah
zivpn-manager help add
zivpn-manager help backup
zivpn-manager help restore
```

---

## Client App

<a href="https://play.google.com/store/apps/details?id=com.zi.zivpn" target="_blank" rel="noreferrer">Download APP on Playstore</a>
> ZIVPN

---
Bash script by PowerMX
