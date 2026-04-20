# 📋 Panduan Lengkap: proxmox-analyzer.sh v4.0
**Proxmox Resource Analyzer — Enterprise Edition**

> Script monitoring kesehatan server Proxmox VE yang komprehensif, 100% **read-only**, aman dijalankan di lingkungan produksi.

---

## 📑 Daftar Isi

1. [Gambaran Umum](#1-gambaran-umum)
2. [Persyaratan Dependensi](#2-persyaratan-dependensi)
3. [Instalasi](#3-instalasi)
4. [Cara Penggunaan](#4-cara-penggunaan)
5. [Multi-Node: Membedakan Banyak Proxmox](#5-multi-node-membedakan-banyak-proxmox)
6. [Penjelasan Setiap Bagian Output](#6-penjelasan-setiap-bagian-output)
7. [Konfigurasi Threshold](#7-konfigurasi-threshold)
8. [Setup Cronjob Otomatis](#8-setup-cronjob-otomatis)
9. [Membaca Hasil Summary](#9-membaca-hasil-summary)
10. [FAQ dan Troubleshooting](#10-faq-dan-troubleshooting)
11. [Catatan Keamanan dan Performa](#11-catatan-keamanan-dan-performa)

---

## 1. Gambaran Umum

`proxmox-analyzer.sh` adalah script bash untuk menganalisis kesehatan server Proxmox VE secara menyeluruh. Script ini dirancang sebagai tools **diagnostik manual** yang dijalankan langsung di terminal Proxmox.

### Apa yang Dilakukan Script Ini

| Fitur | Keterangan |
|-------|-----------|
| **CPU Analysis** | Penggunaan CPU, load average, CPU steal time, suhu per-core |
| **I/O Wait** | Deteksi bottleneck storage yang menyebabkan VM lag |
| **RAM Analysis** | Penggunaan RAM, swap, ZFS ARC cache, KSM deduplication |
| **Storage** | Filesystem, Proxmox storage pool, ZFS pool, LVM |
| **Network** | Traffic, error packet, throughput realtime per interface |
| **VM dan Container** | Status + resource usage aktual per VM/LXC |
| **Disk Health** | S.M.A.R.T status, suhu, Reallocated Sectors, Wear Level |
| **Backup Status** | Log vzdump 24 jam, deteksi job yang gagal |
| **Cluster dan HA** | Status quorum, node online/offline, HA manager |
| **Kernel Events** | Error dmesg, OOM Kill events (24 jam) |
| **Task History** | Failed tasks dari Proxmox API |
| **Service Status** | 11 layanan Proxmox penting |

### Apa yang TIDAK Dilakukan Script Ini

- Tidak menginstal software apapun secara otomatis
- Tidak mengubah konfigurasi sistem
- Tidak menulis file ke disk
- Tidak merestart layanan
- Tidak membangunkan HDD yang sedang sleep (dilindungi `--nocheck=standby`)

---

## 2. Persyaratan Dependensi

### Wajib (Script tidak bisa jalan tanpa ini)

| Package | Fungsi | Cek dengan |
|---------|--------|-----------|
| `bc` | Kalkulasi desimal untuk semua persentase | `which bc` |
| `bash` >= 4.0 | Fitur array asosiatif (network section) | `bash --version` |

### Opsional (Fitur tertentu tidak tersedia jika tidak ada)

| Package | Fitur yang Bergantung | Install |
|---------|----------------------|---------|
| `sysstat` | IOWait detail, per-device I/O stats | `apt install -y sysstat` |
| `smartmontools` | Disk health SMART, suhu disk, critical attrs | `apt install -y smartmontools` |
| `lm-sensors` | Suhu CPU per-core | `apt install -y lm-sensors` |
| `python3` | Task history JSON parsing | Biasanya sudah ada di Proxmox |

### Install Semua Sekaligus

```bash
apt install -y bc sysstat smartmontools lm-sensors

# Setup sensor CPU (jawab YES / ENTER terus, jalankan sekali saja)
sensors-detect
```

> **Catatan**: Jika package opsional tidak terinstall, script tetap berjalan normal. Bagian yang memerlukan package tersebut akan menampilkan pesan informasi dan dilewati.

---

## 3. Instalasi

### Langkah 1 — Upload ke Proxmox

Dari PC/laptop via SCP:
```bash
scp proxmox-analyzer.sh root@<IP-PROXMOX>:/root/scripts/
```

Atau langsung di terminal Proxmox:
```bash
mkdir -p /root/scripts
nano /root/scripts/proxmox-analyzer.sh
# Paste konten script, tekan Ctrl+X, Y, Enter untuk simpan
```

### Langkah 2 — Beri Izin Eksekusi

```bash
chmod +x /root/scripts/proxmox-analyzer.sh
```

### Langkah 3 — Install Dependensi

```bash
apt install -y bc sysstat smartmontools lm-sensors
sensors-detect
```

### Langkah 4 — Verifikasi

```bash
bash /root/scripts/proxmox-analyzer.sh
```

---

## 4. Cara Penggunaan

### Mode 1 — Tampilkan Semua Informasi (Default)

```bash
bash /root/scripts/proxmox-analyzer.sh
```

Menampilkan seluruh 13 bagian monitoring secara lengkap. Cocok untuk pemeriksaan rutin manual.

---

### Mode 2 — Hanya Tampilkan Masalah

```bash
bash /root/scripts/proxmox-analyzer.sh --alert-only
```

Hanya menampilkan bagian yang memiliki status PERINGATAN atau KRITIS, plus summary akhir. Cocok untuk pemeriksaan cepat atau cronjob.

---

### Mode 3 — Output Tanpa Warna

```bash
bash /root/scripts/proxmox-analyzer.sh --no-color
```

Output teks tanpa kode warna ANSI. Wajib dipakai saat output diarahkan ke file log.

```bash
# Simpan ke file log
bash /root/scripts/proxmox-analyzer.sh --no-color > /tmp/hasil-analisis.txt
```

---

### Mode 4 — Beri Nama Kustom Node (Multi-Node)

```bash
bash /root/scripts/proxmox-analyzer.sh --name="PVE-Utama"
```

Menambahkan label identitas kustom pada output header. Berguna saat Anda mengelola banyak server Proxmox. Lihat [Bagian 5](#5-multi-node-membedakan-banyak-proxmox) untuk panduan lengkap.

---

### Kombinasi Flag

```bash
# Alert only + tanpa warna + nama node (sempurna untuk cronjob multi-node)
bash /root/scripts/proxmox-analyzer.sh --alert-only --no-color --name="PVE-Utama"
```

---

### Exit Code untuk Scripting

| Exit Code | Arti |
|-----------|------|
| `0` | Semua normal |
| `1` | Ada peringatan (warning) |
| `2` | Ada masalah kritis |

```bash
bash /root/scripts/proxmox-analyzer.sh
if [[ $? -eq 2 ]]; then
    echo "KRITIS! Butuh tindakan segera."
fi
```

---

## 5. Multi-Node: Membedakan Banyak Proxmox

Jika Anda memiliki lebih dari satu server Proxmox, gunakan fitur **`NODE_LABEL`** untuk memberi nama kustom pada setiap node. Label ini akan muncul di:
- Header output terminal
- File log (mudah di-grep)
- Payload notifikasi Telegram/WhatsApp via n8n

### Cara Set NODE_LABEL

| Metode | Contoh | Keterangan |
|--------|--------|------------|
| **Argument `--name`** | `bash proxmox-analyzer.sh --name="PVE-Utama"` | Paling praktis |
| **Environment variable** | `NODE_LABEL="PVE-Backup" bash proxmox-analyzer.sh` | Cocok untuk wrapper script |
| **Default (otomatis)** | Tidak di-set | Fallback ke `hostname -f` |

### Contoh Output Header

```
╔════════════════════════════════════════════════════════════╗
║  PROXMOX ANALYZER v4.0 — PVE-Datacenter-JKT               ║
╚════════════════════════════════════════════════════════════╝
  Node Label     : PVE-Datacenter-JKT  ← Nama pembeda antar Proxmox
  Hostname       : pve01.datacenter.local
  Waktu Analisis : 2026-04-20 14:30:00
  ...
```

### Setup Cronjob untuk Multi-Node

Setiap node Proxmox punya cronjob-nya sendiri dengan nama yang berbeda:

```bash
# ── Di PVE Node 1 (Datacenter Jakarta) ──
crontab -e
# Tambahkan:
0 */6 * * * bash /root/scripts/proxmox-analyzer.sh --no-color --name="PVE-JKT-01" >> /var/log/pve-analyzer.log 2>&1

# ── Di PVE Node 2 (Datacenter Bandung) ──
crontab -e
# Tambahkan:
0 */6 * * * bash /root/scripts/proxmox-analyzer.sh --no-color --name="PVE-BDG-Backup" >> /var/log/pve-analyzer.log 2>&1

# ── Di PVE Node 3 (Development) ──
crontab -e
# Tambahkan:
0 */6 * * * bash /root/scripts/proxmox-analyzer.sh --no-color --name="PVE-DEV" >> /var/log/pve-analyzer.log 2>&1
```

### Grep Log per Node

```bash
# Filter log hanya dari node tertentu
grep "PVE-JKT-01" /var/log/pve-analyzer.log

# Lihat semua KRITIS dari semua node
grep "KRITIS" /var/log/pve-analyzer.log
```

> **Tip Penamaan**: Gunakan format yang konsisten, misalnya `LOKASI-FUNGSI-NOMOR` → `JKT-PROD-01`, `BDG-BACKUP-01`, `DEV-TEST-01`. Ini memudahkan filter dan notifikasi di n8n.

---

## 6. Penjelasan Setiap Bagian Output

### Bagian 1 — CPU Analysis

Menampilkan penggunaan CPU, load average, CPU steal time, dan suhu per-core.

**Breakdown CPU:**

| Kolom | Artinya |
|-------|---------|
| User | Proses aplikasi pengguna |
| System | Proses OS/kernel |
| Idle | CPU menganggur |
| IOWait | CPU menunggu operasi disk selesai |
| Steal | CPU "dicuri" hypervisor (hanya relevan di nested VM) |

**Load Average:**
- Format: `1.20 (1m) | 0.98 (5m) | 0.85 (15m)`
- Load per Core idealnya < 0.8
- Load per Core > 1.0 = server kelebihan beban

> **Tip penting**: Load Average tinggi tapi CPU usage rendah? Lihat IOWait — kemungkinan besar masalah ada di storage, bukan CPU.

---

### Bagian 2 — I/O Wait Analysis

Mengukur berapa persen waktu CPU dihabiskan menunggu operasi I/O disk.

| % IOWait | Kondisi | Artinya |
|----------|---------|---------|
| 0–20% | Normal | Storage tidak menghambat |
| 20–40% | Peringatan | Storage mulai lambat, VM mungkin lag |
| > 40% | Kritis | Storage bottleneck serius! |

**Contoh Salah Diagnosa yang Sering Terjadi:**
CPU usage 10% tapi IOWait 35% bukan berarti server santai. Server Anda TIDAK kelebihan beban CPU, tetapi **storage yang lambat** adalah masalah sebenarnya.

---

### Bagian 3 — RAM Analysis

**Panduan membaca RAM:**

1. **Lihat "Tersedia", bukan "Terpakai"** — Linux selalu pakai RAM bebas sebagai cache. RAM yang terlihat "terpakai" sebagian besar bisa dilepas kapan saja.

2. **ZFS ARC adalah normal** — Jika Anda pakai ZFS dan RAM selalu tinggi, itu wajar. ZFS menggunakan RAM sebagai cache akses storage.

3. **Gunakan "RAM tanpa ARC"** sebagai angka sebenarnya penggunaan RAM oleh VM dan OS.

4. **ARC Hit Rate > 90%** = Cache ZFS bekerja efisien.

---

### Bagian 4 — Storage Analysis

Tiga level storage yang dicek:

| Sub-bagian | Yang Dicek |
|-----------|-----------|
| Filesystem | Partisi aktual Linux (seperti `df`) |
| Proxmox Storage Pools | Storage yang dikonfigurasi di Proxmox GUI |
| ZFS Pool | Health dan kapasitas pool ZFS |
| LVM | Physical volumes dan volume groups |

> Jika Proxmox Storage Pool statusnya bukan `aktif`, VM tidak bisa dijalankan di storage tersebut!

---

### Bagian 5 — Network Analysis

| Kolom | Artinya |
|-------|---------|
| RX/TX MB | Total traffic sejak boot |
| RX/TX pkt/s | Paket per detik saat ini (realtime) |
| RX/TX Err | Error packet — jika > 100 ada masalah fisik NIC/kabel |

---

### Bagian 6 — VM dan Container Status

Menampilkan semua VM dan Container beserta:
- **Status**: running, stopped, paused, error
- **Alokasi RAM**: RAM yang dikonfigurasi di Proxmox
- **RAM aktual**: RAM yang benar-benar dipakai proses QEMU di host
- **CPU aktual %**: Persentase CPU yang dipakai di host

---

### Bagian 7 — Disk Health SMART

**Critical Attributes yang Dipantau:**

| Attribute | Nilai Berbahaya | Artinya |
|-----------|----------------|---------|
| Reallocated Sectors | > 0 | Sektor fisik rusak, diganti cadangan. Segera backup! |
| Current Pending Sectors | > 0 | Sektor menunggu realokasi |
| Uncorrectable Errors | > 0 | Error tidak bisa diperbaiki. Risiko data loss tinggi! |
| Wear Leveling Count | < 20 | SSD hampir habis masa pakainya |
| NVMe Percentage Used | > 80% | SSD NVMe mendekati akhir umurnya |

**Tentang Disk Sleep (ikon 💤):**
Script menggunakan `--nocheck=standby` sehingga HDD yang sedang sleep tidak akan dibangunkan. Disk yang tidur ditampilkan dengan ikon 💤 dan tetap muncul di Summary sebagai "Aman".

---

### Bagian 8 — Backup Status

- Membaca log dari `/var/log/vzdump/` untuk backup 24 jam terakhir
- Jika direktori tidak ada, fallback ke Proxmox Task API
- Pola error yang terdeteksi: `No space left`, `Connection timed out`, `backup failed`, `aborted`

---

### Bagian 9 — Cluster dan HA Status

**Tentang Quorum:**
- Quorum tercapai jika lebih dari setengah node aktif
- Contoh: 3 node cluster = butuh minimal 2 node online
- Jika quorum tidak tercapai, Proxmox memblokir operasi tertentu (split-brain protection)

**Mode Standalone:**
Jika Proxmox Anda hanya 1 node, bagian ini menampilkan informasi bahwa node berjalan standalone. Tidak ada error.

---

### Bagian 10 — Kernel Error dan OOM

**OOM Kill (Out of Memory Killer):**
Terjadi saat RAM benar-benar habis. OS terpaksa membunuh proses secara paksa. Jika ini terjadi berkali-kali, RAM perlu ditambah atau jumlah VM dikurangi.

---

### Bagian 11 — Task History

Mengambil history 50 task terakhir dari Proxmox API dan menampilkan:
- Task yang gagal dalam 24 jam (dengan timestamp dan alasan error)
- Semua task terbaru dengan statusnya

---

### Bagian 12 — Service Status

Layanan Proxmox yang dipantau:

| Service | Fungsi | Dampak jika Mati |
|---------|--------|-----------------|
| `pvedaemon` | API backend Proxmox | Web GUI tidak bisa manage VM |
| `pveproxy` | Web interface | Tidak bisa akses web UI |
| `pvestatd` | Statistik resource | Grafik resource di GUI tidak update |
| `pve-cluster` | Sinkronisasi cluster | Cluster tidak sinkron |
| `corosync` | Komunikasi antar node | Node tidak bisa komunikasi |
| `pve-firewall` | Firewall VM | Semua rule firewall tidak aktif |
| `cron` | Job terjadwal | Backup otomatis tidak jalan |
| `ssh` | Remote access | Tidak bisa SSH ke server |

---

## 7. Konfigurasi Threshold

Edit baris 54–73 di script untuk menyesuaikan ambang batas:

```bash
CPU_WARNING=70        # % CPU mulai peringatan
CPU_CRITICAL=90       # % CPU kritis
RAM_WARNING=80        # % RAM warning
RAM_CRITICAL=95       # % RAM kritis
STORAGE_WARNING=75    # % storage warning
STORAGE_CRITICAL=90   # % storage kritis
IOWAIT_WARNING=20     # % IOWait warning
IOWAIT_CRITICAL=40    # % IOWait kritis
SWAP_WARNING=30       # % swap warning
SWAP_CRITICAL=70      # % swap kritis
DISK_TEMP_WARNING=45  # derajat Celcius suhu disk warning
DISK_TEMP_CRITICAL=55 # derajat Celcius suhu disk kritis
CPU_TEMP_WARNING=75   # derajat Celcius suhu CPU warning
CPU_TEMP_CRITICAL=90  # derajat Celcius suhu CPU kritis
```

### Contoh Penyesuaian

Server dengan RAM besar (>128GB, ZFS ARC bikin RAM selalu tinggi):
```bash
RAM_WARNING=90
RAM_CRITICAL=97
```

Server storage intensif (RAID, banyak VM):
```bash
IOWAIT_WARNING=30
IOWAIT_CRITICAL=60
```

---

## 8. Setup Cronjob Otomatis

### Buka Crontab

```bash
crontab -e
```

### Pilihan Jadwal

```bash
# Setiap 6 jam — single node (direkomendasikan)
0 */6 * * * bash /root/scripts/proxmox-analyzer.sh --no-color >> /var/log/pve-analyzer.log 2>&1

# Setiap 6 jam — multi-node (dengan nama kustom)
0 */6 * * * bash /root/scripts/proxmox-analyzer.sh --no-color --name="PVE-Utama" >> /var/log/pve-analyzer.log 2>&1

# Setiap 1 jam (monitoring ketat)
0 * * * * bash /root/scripts/proxmox-analyzer.sh --no-color --name="PVE-Utama" >> /var/log/pve-analyzer.log 2>&1

# Hanya alert, setiap 30 menit
*/30 * * * * bash /root/scripts/proxmox-analyzer.sh --alert-only --no-color --name="PVE-Utama" >> /var/log/pve-alerts.log 2>&1

# Laporan harian jam 07:00
0 7 * * * bash /root/scripts/proxmox-analyzer.sh --no-color --name="PVE-Utama" >> /var/log/pve-daily.log 2>&1
```

### Manajemen Log (Agar Log Tidak Terlalu Besar)

Buat file `/etc/logrotate.d/pve-analyzer`:

```
/var/log/pve-analyzer.log {
    weekly
    rotate 4
    compress
    missingok
    notifempty
}
```

### Membaca Log

```bash
# Lihat 100 baris terakhir
tail -100 /var/log/pve-analyzer.log

# Cari hanya entry kritis
grep "KRITIS\|GAGAL\|OOM" /var/log/pve-analyzer.log

# Lihat log hari ini saja
grep "$(date '+%Y-%m-%d')" /var/log/pve-analyzer.log
```

---

## 9. Membaca Hasil Summary

### Label Status

| Label | Warna | Arti | Tindakan |
|-------|-------|------|---------|
| `[NORMAL]` | Hijau | Kondisi baik | Tidak perlu |
| `[PERINGATAN]` | Kuning | Mendekati batas | Monitor, rencanakan upgrade |
| `[KRITIS]` | Merah | Melebihi batas kritis | Tindakan segera! |

### Contoh Skenario dan Interpretasi

**Skenario 1 — RAM Tinggi karena ZFS ARC:**
```
⚠ RAM 87% — Tinggi. Pertimbangkan penambahan RAM
```
Cek dulu angka "RAM tanpa ARC". Jika hanya 50%, ini normal karena ZFS ARC yang pakai sisanya.

**Skenario 2 — Reallocated Sectors Ditemukan:**
```
❌ Disk /dev/sda: Reallocated Sectors=5 — Segera backup data & siapkan pengganti!
```
DARURAT. Backup semua data sekarang, pesan disk pengganti segera.

**Skenario 3 — IOWait Tinggi tapi CPU Rendah:**
```
⚠ IOWait 28% — Tinggi. Cek: iostat -x 1 5
```
Storage lambat. Jalankan `iostat -x 1 10` untuk lihat disk mana yang sibuk.

**Skenario 4 — Backup Gagal:**
```
❌ Backup: 1 job GAGAL! Cek /var/log/vzdump
```
Baca file log backup yang gagal untuk cari tahu penyebabnya (storage penuh, koneksi NAS putus, dll).

---

## 10. FAQ dan Troubleshooting

### Semua persentase menunjukkan 0%

**Penyebab**: `bc` tidak terinstall.

```bash
apt install -y bc
```

---

### SMART menampilkan "Timeout"

**Penyebab**: Disk bermasalah atau sangat sibuk, tidak merespons dalam 15 detik.

```bash
# Cek manual
smartctl -a /dev/sda
```

---

### IOWait menampilkan "N/A"

**Penyebab**: `sysstat` tidak terinstall.

```bash
apt install -y sysstat
```

---

### Suhu CPU tidak tersedia

**Penyebab**: `lm-sensors` belum dikonfigurasi.

```bash
apt install -y lm-sensors
sensors-detect  # Jawab YES/ENTER terus
sensors         # Test
```

---

### Disk arsip saya ikut terbangun dari sleep

**Verifikasi bahwa script sudah pakai `--nocheck=standby`:**

```bash
grep "nocheck" /root/scripts/proxmox-analyzer.sh
# Output yang benar: smartctl --nocheck=standby
```

Jika belum ada, pastikan menggunakan script versi v4.0 terbaru.

---

### Cluster Status menampilkan "pvecm tidak tersedia"

**Penyebab**: Normal jika ini bukan Proxmox VE, atau binary tidak ada di PATH.

```bash
which pvecm
pveversion
```

---

### Task History error JSON

**Penyebab**: `python3` tidak tersedia atau pvesh format berbeda.

Script akan otomatis fallback ke tampilan raw output. Tidak masalah.

---

## 11. Catatan Keamanan dan Performa

### Jaminan Keamanan

| Aspek | Status |
|-------|--------|
| Mengubah konfigurasi | Tidak pernah |
| Menulis file | Tidak ada |
| Install software otomatis | Tidak pernah |
| Restart service | Tidak ada |
| Membangunkan disk sleep | Aman (pakai `--nocheck=standby`) |

### Estimasi Waktu Berjalan

| Kondisi | Waktu Estimasi |
|---------|---------------|
| Semua tools lengkap (dengan iostat) | 8–12 detik |
| Tanpa iostat (fallback vmstat) | 4–6 detik |
| Per disk tambahan (SMART) | +2–5 detik per disk |
| Per node cluster (ping) | +1–2 detik per node |

> Script ini lebih ringan dari membuka satu tab browser. Tidak ada dampak signifikan ke performa VM yang sedang berjalan.

### Sumber Data yang Dibaca (Semua Read-Only)

```
/proc/cpuinfo, /proc/loadavg, /proc/stat    → CPU info
/proc/meminfo                               → RAM info
/proc/net/dev                               → Network counters
/proc/spl/kstat/zfs/arcstats               → ZFS ARC stats
/sys/kernel/mm/ksm/                        → KSM info
/sys/class/thermal/                        → Suhu CPU
/sys/fs/cgroup/                            → Resource container
vmstat, free, df, ip                        → System tools
pvesm, qm, pct, pvecm, pvesh               → Proxmox API (read only)
smartctl --nocheck=standby                  → SMART (tidak wake disk)
journalctl -k, dmesg                       → Kernel log (read only)
sensors                                    → Hardware sensors
```

---

*Panduan untuk proxmox-analyzer.sh v4.0 Enterprise Edition*
*Terakhir diperbarui: 2026-04-20 — Tambah fitur NODE_LABEL untuk identifikasi multi-node*
