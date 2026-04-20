# PANDUAN LENGKAP PROXMOX VE

## Untuk Pemula hingga Tingkat Profesional

> **Dokumen ini dirancang sebagai pedoman komprehensif** untuk memahami Proxmox Virtual Environment (PVE), monitoring server, analisis resource, dan pengetahuan server profesional.  
> Cocok digunakan sebagai referensi oleh AI maupun manusia untuk mencari informasi lebih lanjut.

---

## DAFTAR ISI

1. [Apa Itu Proxmox VE?](#1-apa-itu-proxmox-ve)
2. [Konsep Dasar Virtualisasi](#2-konsep-dasar-virtualisasi)
3. [Arsitektur Proxmox VE](#3-arsitektur-proxmox-ve)
4. [Instalasi Proxmox VE](#4-instalasi-proxmox-ve)
5. [Pengenalan Web UI Proxmox](#5-pengenalan-web-ui-proxmox)
6. [Manajemen VM dan Container](#6-manajemen-vm-dan-container)
7. [Storage di Proxmox](#7-storage-di-proxmox)
8. [Networking di Proxmox](#8-networking-di-proxmox)
9. [Monitoring CPU, RAM, dan Storage](#9-monitoring-cpu-ram-dan-storage)
10. [Script Analisis Resource Server](#10-script-analisis-resource-server)
11. [Threshold & Batas Wajar Resource](#11-threshold--batas-wajar-resource)
12. [Backup dan Restore](#12-backup-dan-restore)
13. [Cluster Proxmox](#13-cluster-proxmox)
14. [Keamanan Server Proxmox](#14-keamanan-server-proxmox)
15. [Pengetahuan Server Profesional](#15-pengetahuan-server-profesional)
16. [Troubleshooting Umum](#16-troubleshooting-umum)
17. [Referensi & Panduan Lanjutan](#17-referensi--panduan-lanjutan)

---

## 1. Apa Itu Proxmox VE?

### Definisi

**Proxmox Virtual Environment (Proxmox VE / PVE)** adalah platform virtualisasi *open-source* berbasis Linux yang memungkinkan kamu menjalankan banyak sistem operasi (disebut Virtual Machine/VM atau Container) di atas satu server fisik.

Bayangkan satu komputer fisik yang bisa "berpura-pura" menjadi 10, 20, bahkan 100 komputer sekaligus — itulah fungsi Proxmox.

### Mengapa Proxmox?

| Fitur | Keterangan |
|-------|-----------|
| **Gratis & Open Source** | Tidak butuh lisensi mahal |
| **Web UI Modern** | Bisa dikelola dari browser |
| **Dua Teknologi Virtualisasi** | KVM (VM penuh) + LXC (Container ringan) |
| **Cluster Support** | Bisa gabungkan beberapa server fisik |
| **Backup Built-in** | Fitur backup terintegrasi |
| **High Availability** | VM bisa pindah otomatis jika server mati |
| **ZFS Support** | Filesystem canggih untuk data protection |

### Proxmox vs Alternatif Lain

| Platform | Lisensi | Teknologi | Cocok Untuk |
|----------|---------|-----------|-------------|
| **Proxmox VE** | Gratis / Berbayar (support) | KVM + LXC | Semua skala |
| VMware ESXi | Berbayar | VMware | Enterprise |
| Microsoft Hyper-V | Berbayar (Windows) | Hyper-V | Windows Enterprise |
| XenServer | Gratis / Berbayar | Xen | Enterprise |
| oVirt | Gratis | KVM | Enterprise Linux |

---

## 2. Konsep Dasar Virtualisasi

### 2.1 Hypervisor

**Hypervisor** adalah software yang memungkinkan beberapa OS berjalan di atas satu hardware fisik.

```
[ Hardware Fisik: CPU, RAM, Disk, NIC ]
         ↓
[ Hypervisor (Proxmox/KVM) ]
         ↓
[ VM1 ] [ VM2 ] [ VM3 ] [ Container1 ] [ Container2 ]
```

- **Type 1 (Bare Metal)**: Langsung di atas hardware → Proxmox, ESXi, Hyper-V *(lebih efisien)*
- **Type 2 (Hosted)**: Di atas OS biasa → VirtualBox, VMware Workstation *(untuk desktop)*

### 2.2 KVM vs LXC

#### KVM (Kernel-based Virtual Machine)

- Virtualisasi **penuh** (full virtualization)
- Setiap VM punya kernel OS sendiri
- Bisa jalankan Windows, Linux, FreeBSD, dll
- Isolasi sempurna — sangat aman
- Overhead lebih tinggi (butuh lebih banyak RAM/CPU)

#### LXC (Linux Containers)

- Virtualisasi **level OS** (OS-level virtualization)
- Berbagi kernel host, hanya filesystem yang terpisah
- Hanya bisa jalankan Linux
- Sangat ringan — overhead rendah
- Startup lebih cepat

```
KVM (VM Penuh):
┌──────────────────────────────┐
│ App │ App │ App              │
│   Guest OS (Kernel Sendiri)  │
│        KVM Hypervisor        │
│      Host OS (Linux)         │
│         Hardware             │
└──────────────────────────────┘

LXC (Container):
┌──────────────────────────────┐
│ App │ App │ App              │
│ Container  (Namespace/cgroup)│
│      Host OS Kernel (Shared) │
│         Hardware             │
└──────────────────────────────┘
```

### 2.3 Istilah Penting

| Istilah | Singkatan | Arti |
|---------|-----------|------|
| Virtual Machine | VM | Server virtual lengkap |
| Container | CT / LXC | Container Linux ringan |
| Node | - | Server fisik Proxmox |
| Cluster | - | Grup beberapa node |
| Storage Pool | - | Tempat penyimpanan disk virtual |
| VMID | - | ID unik untuk setiap VM/CT |
| Template | - | Blueprint untuk membuat VM/CT baru |
| Snapshot | - | Rekaman kondisi VM pada waktu tertentu |
| vCPU | - | CPU virtual yang dialokasikan ke VM |
| Memory Balloon | - | Teknologi alokasi RAM dinamis |
| Bridge | - | Virtual switch untuk networking |

---

## 3. Arsitektur Proxmox VE

### 3.1 Komponen Utama

```
┌─────────────────────────────────────────────────────────┐
│                    PROXMOX NODE                         │
│                                                         │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────────┐ │
│  │  Web UI     │  │  REST API   │  │  CLI (pvesh)    │ │
│  │ (Port 8006) │  │  (HTTPS)    │  │  (pct/qm/pvectl)│ │
│  └──────┬──────┘  └──────┬──────┘  └────────┬────────┘ │
│         └────────────────┼──────────────────┘          │
│                          ↓                              │
│              ┌───────────────────────┐                 │
│              │   pvedaemon (PVE API) │                 │
│              └───────────┬───────────┘                 │
│                          ↓                              │
│    ┌─────────────────────────────────────────┐         │
│    │              KVM / QEMU                 │         │
│    │         LXC (Linux Containers)          │         │
│    └─────────────────────────────────────────┘         │
│                          ↓                              │
│    ┌──────────┬──────────┬──────────┬──────────┐       │
│    │  CPU     │  RAM     │  Storage │  Network │       │
│    │ (x86-64) │ (DDR4/5) │(SSD/HDD) │ (NIC)   │       │
│    └──────────┴──────────┴──────────┴──────────┘       │
└─────────────────────────────────────────────────────────┘
```

### 3.2 Proses & Service Utama Proxmox

| Service | Fungsi |
|---------|--------|
| `pvedaemon` | Daemon utama API Proxmox |
| `pveproxy` | Web proxy (HTTPS port 8006) |
| `pvestatd` | Mengumpulkan statistik resource |
| `pve-cluster` | Sinkronisasi data cluster (corosync) |
| `corosync` | Cluster messaging layer |
| `pmxcfs` | Proxmox Cluster Filesystem |
| `qemu-system-x86_64` | Proses tiap VM yang berjalan |
| `lxc-start` | Proses tiap container yang berjalan |

### 3.3 File & Direktori Penting

```
/etc/pve/               → Konfigurasi utama Proxmox (cluster filesystem)
/etc/pve/nodes/         → Konfigurasi per node
/etc/pve/qemu-server/   → Konfigurasi file VM (.conf)
/etc/pve/lxc/           → Konfigurasi file Container (.conf)
/var/lib/vz/            → Storage default (images, templates)
/var/lib/vz/images/     → Disk image VM
/var/lib/vz/template/   → Template OS
/var/log/pve/           → Log Proxmox
/var/log/syslog         → Log sistem utama
```

---

## 4. Instalasi Proxmox VE

### 4.1 Persyaratan Hardware Minimum

| Komponen | Minimum | Rekomendasi |
|----------|---------|-------------|
| **CPU** | 64-bit dual-core | Intel/AMD 8+ core dengan VT-x/AMD-V |
| **RAM** | 2 GB | 16 GB+ (lebih banyak = lebih banyak VM) |
| **Storage OS** | 32 GB | SSD 120 GB+ |
| **Storage VM** | Tergantung kebutuhan | SSD/NVMe terpisah |
| **Network** | 1 x 1 Gbps NIC | 2+ NIC untuk bonding/redundansi |

### 4.2 Langkah Instalasi

1. **Download ISO** dari <https://www.proxmox.com/en/downloads>
2. **Buat bootable USB** menggunakan Balena Etcher atau Rufus
3. **Boot dari USB** dan ikuti wizard instalasi:
   - Pilih disk target (akan di-format!)
   - Set hostname (contoh: `pve01.domain.local`)
   - Set IP address, gateway, DNS
   - Set password root
4. **Akses Web UI** setelah reboot: `https://[IP-SERVER]:8006`

### 4.3 Konfigurasi Awal Setelah Instalasi

```bash
# Update sistem
apt update && apt dist-upgrade -y

# Nonaktifkan subscription nag (opsional, untuk non-enterprise)
sed -i.bak "s/data.status !== 'Active'/false/" \
  /usr/share/javascript/proxmox-widget-toolkit/proxmoxlib.js
systemctl restart pveproxy

# Tambahkan repository no-subscription (untuk update gratis)
echo "deb http://download.proxmox.com/debian/pve bookworm pve-no-subscription" \
  > /etc/apt/sources.list.d/pve-no-sub.list

# Nonaktifkan enterprise repository (jika tidak punya lisensi)
# Komentari isi file:
# /etc/apt/sources.list.d/pve-enterprise.list
```

---

## 5. Pengenalan Web UI Proxmox

### 5.1 Layout Utama

```
┌────────────────────────────────────────────────────────────┐
│ HEADER: Logo | Search | Status | Help | User Menu          │
├──────────────────┬─────────────────────────────────────────┤
│  LEFT PANEL      │  RIGHT PANEL (Content Area)             │
│  (Tree View)     │                                         │
│  ┌─ Datacenter   │  Tab: Summary | Console | Hardware |    │
│  │  ├─ pve01     │       Options | Task History | etc.     │
│  │  │  ├─ VM 100 │                                         │
│  │  │  ├─ VM 101 │  [Graphs CPU/RAM/Network/Disk]          │
│  │  │  ├─ CT 200 │                                         │
│  │  │  └─ CT 201 │  [Tombol: Start | Shutdown | Migrate]   │
│  │  └─ Storage   │                                         │
│  └─ Cluster View │                                         │
├──────────────────┴─────────────────────────────────────────┤
│ BOTTOM: Task Log (real-time)                               │
└────────────────────────────────────────────────────────────┘
```

### 5.2 Menu Penting

| Menu | Fungsi |
|------|--------|
| **Datacenter → Summary** | Overview semua node, VM, Storage |
| **Datacenter → Storage** | Kelola storage pools |
| **Datacenter → Backup** | Jadwal backup otomatis |
| **Node → Summary** | Status hardware node |
| **Node → Shell** | Terminal langsung ke node |
| **VM/CT → Console** | Akses layar VM/CT |
| **VM/CT → Snapshots** | Kelola snapshot |

---

## 6. Manajemen VM dan Container

### 6.1 Membuat VM Baru

```bash
# Via CLI (membuat VM dengan spesifikasi):
qm create 100 \
  --name "ubuntu-server" \
  --memory 2048 \
  --cores 2 \
  --sockets 1 \
  --net0 virtio,bridge=vmbr0 \
  --ide2 local:iso/ubuntu-22.04.iso,media=cdrom \
  --scsi0 local-lvm:32 \
  --boot order=scsi0;ide2 \
  --ostype l26

# Start VM
qm start 100

# Stop VM
qm stop 100

# Shutdown graceful
qm shutdown 100

# Lihat status
qm status 100

# List semua VM
qm list
```

### 6.2 Membuat Container (LXC)

```bash
# Download template Ubuntu 22.04 terlebih dahulu
pveam download local ubuntu-22.04-standard_22.04-1_amd64.tar.zst

# Buat container
pct create 200 local:vztmpl/ubuntu-22.04-standard_22.04-1_amd64.tar.zst \
  --hostname "web-server" \
  --memory 1024 \
  --swap 512 \
  --cores 2 \
  --rootfs local-lvm:10 \
  --net0 name=eth0,bridge=vmbr0,ip=dhcp \
  --unprivileged 1 \
  --password "YourSecurePassword123!"

# Start container
pct start 200

# Masuk ke container
pct enter 200

# Stop container
pct stop 200

# List semua container
pct list
```

### 6.3 Resize Disk VM/Container

```bash
# Tambah disk VM 10GB
qm resize 100 scsi0 +10G

# Tambah disk Container 5GB
pct resize 200 rootfs +5G
```

### 6.4 Snapshot

```bash
# Buat snapshot VM
qm snapshot 100 "snap-before-update" --description "Sebelum update OS"

# List snapshot
qm listsnapshot 100

# Rollback ke snapshot
qm rollback 100 snap-before-update

# Hapus snapshot
qm delsnapshot 100 snap-before-update

# Snapshot container
pct snapshot 200 "ct-snap-20240101"
pct listsnapshot 200
pct rollback 200 ct-snap-20240101
```

---

## 7. Storage di Proxmox

### 7.1 Jenis Storage

| Tipe | Protokol | Cocok Untuk | Kelebihan |
|------|---------|-------------|-----------|
| **Directory** | Lokal | Development | Mudah, support backup |
| **LVM** | Lokal | VM disk | Performa baik |
| **LVM-thin** | Lokal | VM disk (rekomendasi) | Support snapshot efisien |
| **ZFS** | Lokal | Semua | Data integrity, snapshot, compression |
| **NFS** | Jaringan | Shared storage | Mudah berbagi antar node |
| **Ceph** | Jaringan | Cluster HA | Distributed, sangat reliable |
| **iSCSI** | Jaringan | Enterprise | Performa tinggi |

### 7.2 ZFS — Filesystem Profesional

ZFS adalah filesystem canggih yang sangat direkomendasikan untuk server profesional.

```bash
# Lihat status pool ZFS
zpool status

# Lihat penggunaan storage ZFS
zfs list

# Lihat statistik I/O
zpool iostat -v 5

# Cek kesehatan disk
zpool status -v

# RAIDZ1 (seperti RAID5): butuh minimal 3 disk
zpool create datapool raidz /dev/sdb /dev/sdc /dev/sdd

# Mirror (seperti RAID1): butuh minimal 2 disk
zpool create mirror-pool mirror /dev/sdb /dev/sdc

# Enable compression (sangat direkomendasikan)
zfs set compression=lz4 datapool

# Enable dedup (hati-hati, butuh banyak RAM)
zfs set dedup=on datapool
```

### 7.3 Monitoring Storage

```bash
# Cek disk usage
df -h

# Cek inode usage
df -i

# Cek disk health dengan smartctl
smartctl -a /dev/sda

# Cek bad blocks
badblocks -v /dev/sda

# Monitor I/O real-time
iostat -x 2

# Cek kecepatan disk
hdparm -Tt /dev/sda
```

---

## 8. Networking di Proxmox

### 8.1 Konsep Network Proxmox

```
Internet / Uplink
      |
[ Physical NIC: eth0 / eno1 / enp3s0 ]
      |
[ Linux Bridge: vmbr0 ]
      |
    ┌─────────────────────────┐
    │  VM1  │  VM2  │  CT1   │  (semua terhubung ke bridge)
    └─────────────────────────┘
```

### 8.2 Konfigurasi Network

```bash
# Lihat konfigurasi network
cat /etc/network/interfaces

# Contoh konfigurasi bridge sederhana:
# auto lo
# iface lo inet loopback
#
# auto eno1
# iface eno1 inet manual
#
# auto vmbr0
# iface vmbr0 inet static
#     address 192.168.1.10/24
#     gateway 192.168.1.1
#     bridge-ports eno1
#     bridge-stp off
#     bridge-fd 0

# Apply konfigurasi tanpa reboot
ifreload -a

# Lihat bridge
brctl show

# Lihat IP
ip addr show
```

### 8.3 VLAN di Proxmox

```bash
# Tambahkan VLAN-aware ke bridge di /etc/network/interfaces:
# auto vmbr0
# iface vmbr0 inet static
#     ...
#     bridge-vlan-aware yes
#     bridge-vids 2-4094

# Kemudian di VM, set VLAN tag di hardware tab
```

---

## 9. Monitoring CPU, RAM, dan Storage

### 9.1 Monitoring via Web UI

Di Proxmox Web UI, tiap Node/VM/Container memiliki tab **Summary** yang menampilkan:

- CPU Usage (%)
- Memory Usage (MB/GB)
- Network I/O (Mbps)
- Disk I/O (MB/s)
- Uptime

### 9.2 Monitoring via CLI

```bash
# ============================================
# CPU MONITORING
# ============================================

# Lihat penggunaan CPU keseluruhan
top
htop  # lebih interaktif (install: apt install htop)

# Lihat per-core CPU
mpstat -P ALL 2

# Lihat load average (1, 5, 15 menit)
uptime

# Cek informasi CPU
lscpu

# Monitor CPU real-time
vmstat 2 10  # setiap 2 detik, 10 kali

# ============================================
# RAM MONITORING
# ============================================

# Lihat penggunaan RAM
free -h

# Lihat detail RAM
cat /proc/meminfo

# Lihat proses yang pakai RAM terbanyak
ps aux --sort=-%mem | head -20

# ============================================
# STORAGE MONITORING
# ============================================

# Penggunaan disk
df -h

# Penggunaan direktori
du -sh /var/lib/vz/*

# I/O monitoring
iostat -x 2

# I/O per proses
iotop  # install: apt install iotop

# ============================================
# PROXMOX KHUSUS
# ============================================

# Status semua VM dan resource
pvesh get /nodes/$(hostname)/qemu --output-format json-pretty

# Status semua Container
pvesh get /nodes/$(hostname)/lxc --output-format json-pretty

# Storage usage via Proxmox API
pvesh get /nodes/$(hostname)/storage --output-format json-pretty

# Resource summary node
pvesh get /nodes/$(hostname)/status --output-format json-pretty

# RRD data (graph data)
pvesh get /nodes/$(hostname)/rrddata --timeframe hour --cf AVERAGE
```

### 9.3 Tool Monitoring Tambahan

```bash
# Install tool monitoring berguna
apt install -y htop iotop iftop nethogs ncdu smartmontools

# Monitor network per interface
iftop -i vmbr0

# Monitor network per proses
nethogs vmbr0

# Analisis penggunaan disk interaktif
ncdu /var/lib/vz

# Monitor semua dalam satu layar
glances  # install: pip3 install glances
```

---

## 10. Script Analisis Resource Server

Di bawah ini adalah script lengkap untuk menganalisis dan memberikan summary status server Proxmox — termasuk penilaian apakah penggunaan masih dalam batas wajar atau tidak.

### 10.1 Script Utama: `proxmox-analyzer.sh`

```bash
#!/bin/bash
# =============================================================================
# PROXMOX RESOURCE ANALYZER
# Script untuk analisis CPU, RAM, Storage, dan kondisi server Proxmox
# Versi: 2.0
# Penggunaan: bash proxmox-analyzer.sh [--json] [--alert-only]
# =============================================================================

# ─── WARNA ──────────────────────────────────────────────────────────────────
RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# ─── THRESHOLD (Ambang Batas) ────────────────────────────────────────────────
CPU_WARNING=70       # % - Peringatan
CPU_CRITICAL=90      # % - Kritis
RAM_WARNING=80       # % - Peringatan
RAM_CRITICAL=95      # % - Kritis
STORAGE_WARNING=75   # % - Peringatan
STORAGE_CRITICAL=90  # % - Kritis
LOAD_WARNING=0.8     # Faktor dari jumlah CPU (load_avg / cpu_count)
LOAD_CRITICAL=1.0    # Load = 100% dari jumlah CPU

# ─── MODE ────────────────────────────────────────────────────────────────────
JSON_MODE=false
ALERT_ONLY=false
for arg in "$@"; do
  [[ "$arg" == "--json" ]] && JSON_MODE=true
  [[ "$arg" == "--alert-only" ]] && ALERT_ONLY=true
done

# ─── FUNGSI HELPER ──────────────────────────────────────────────────────────
print_header() {
  echo -e "\n${BLUE}${BOLD}╔══════════════════════════════════════════════════════════════╗${NC}"
  echo -e "${BLUE}${BOLD}║  $1${NC}"
  echo -e "${BLUE}${BOLD}╚══════════════════════════════════════════════════════════════╝${NC}"
}

print_section() {
  echo -e "\n${CYAN}${BOLD}▶ $1${NC}"
  echo -e "${CYAN}$(printf '─%.0s' {1..62})${NC}"
}

status_label() {
  local value=$1
  local warn=$2
  local crit=$3
  if (( $(echo "$value >= $crit" | bc -l) )); then
    echo -e "${RED}[KRITIS]${NC}"
  elif (( $(echo "$value >= $warn" | bc -l) )); then
    echo -e "${YELLOW}[PERINGATAN]${NC}"
  else
    echo -e "${GREEN}[NORMAL]${NC}"
  fi
}

progress_bar() {
  local percent=$1
  local width=40
  local filled=$(echo "$percent * $width / 100" | bc)
  local empty=$((width - filled))
  local bar=""
  for ((i=0; i<filled; i++)); do bar="${bar}█"; done
  for ((i=0; i<empty; i++)); do bar="${bar}░"; done

  if (( $(echo "$percent >= $CPU_CRITICAL" | bc -l 2>/dev/null) )); then
    echo -e "${RED}[${bar}] ${percent}%${NC}"
  elif (( $(echo "$percent >= $CPU_WARNING" | bc -l 2>/dev/null) )); then
    echo -e "${YELLOW}[${bar}] ${percent}%${NC}"
  else
    echo -e "${GREEN}[${bar}] ${percent}%${NC}"
  fi
}

# ─── TIMESTAMP ───────────────────────────────────────────────────────────────
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
HOSTNAME=$(hostname -f 2>/dev/null || hostname)

print_header "PROXMOX SERVER ANALYZER - ${HOSTNAME}"
echo -e "  ${BOLD}Waktu Analisis:${NC} ${TIMESTAMP}"
echo -e "  ${BOLD}Versi PVE:${NC}      $(pveversion 2>/dev/null | head -1 || echo 'N/A')"
echo -e "  ${BOLD}Kernel:${NC}         $(uname -r)"
echo -e "  ${BOLD}Uptime:${NC}         $(uptime -p 2>/dev/null || uptime)"

# =============================================================================
# BAGIAN 1: CPU ANALYSIS
# =============================================================================
print_section "CPU ANALYSIS"

CPU_COUNT=$(nproc)
CPU_MODEL=$(grep "model name" /proc/cpuinfo | head -1 | cut -d: -f2 | xargs)
CPU_SOCKETS=$(grep "physical id" /proc/cpuinfo | sort -u | wc -l)
CPU_CORES_PER_SOCKET=$(grep "cpu cores" /proc/cpuinfo | head -1 | awk '{print $NF}')
CPU_THREADS=$(grep "siblings" /proc/cpuinfo | head -1 | awk '{print $NF}')

# Dapatkan CPU usage (rata-rata 2 detik)
CPU_IDLE=$(top -bn2 -d0.5 | grep "Cpu(s)" | tail -1 | awk '{print $8}' | tr -d '%id,' 2>/dev/null || \
           vmstat 1 2 | tail -1 | awk '{print $15}')
CPU_USAGE=$(echo "100 - ${CPU_IDLE:-0}" | bc 2>/dev/null || echo "0")
CPU_USAGE=$(printf "%.1f" "$CPU_USAGE")

# Load Average
LOAD_1=$(cat /proc/loadavg | awk '{print $1}')
LOAD_5=$(cat /proc/loadavg | awk '{print $2}')
LOAD_15=$(cat /proc/loadavg | awk '{print $3}')
LOAD_PER_CPU=$(echo "scale=2; $LOAD_1 / $CPU_COUNT" | bc)

echo -e "  Model CPU     : ${CPU_MODEL}"
echo -e "  Jumlah vCPU   : ${CPU_COUNT} (${CPU_SOCKETS} socket x ${CPU_CORES_PER_SOCKET:-N/A} core, ${CPU_THREADS:-N/A} thread)"
echo ""
echo -e "  Penggunaan CPU: $(progress_bar $CPU_USAGE)"
echo -e "  Status        : $(status_label $CPU_USAGE $CPU_WARNING $CPU_CRITICAL)"
echo ""
echo -e "  Load Average  : ${LOAD_1} (1m) | ${LOAD_5} (5m) | ${LOAD_15} (15m)"
echo -e "  Load/CPU      : ${LOAD_PER_CPU} (ideal < 0.8 per core)"

if (( $(echo "$LOAD_PER_CPU >= $LOAD_CRITICAL" | bc -l) )); then
  echo -e "  Load Status   : ${RED}[KRITIS] Server overloaded!${NC}"
elif (( $(echo "$LOAD_PER_CPU >= $LOAD_WARNING" | bc -l) )); then
  echo -e "  Load Status   : ${YELLOW}[PERINGATAN] Load mulai tinggi${NC}"
else
  echo -e "  Load Status   : ${GREEN}[NORMAL]${NC}"
fi

# Top 5 proses CPU
echo -e "\n  ${BOLD}Top 5 Proses (CPU):${NC}"
ps aux --sort=-%cpu | awk 'NR>1 && NR<=6 {printf "    %-8s %-20s %s%%\n", $1, substr($11,1,20), $3}'

# =============================================================================
# BAGIAN 2: RAM ANALYSIS
# =============================================================================
print_section "RAM ANALYSIS"

TOTAL_RAM=$(free -m | awk '/^Mem:/ {print $2}')
USED_RAM=$(free -m | awk '/^Mem:/ {print $3}')
FREE_RAM=$(free -m | awk '/^Mem:/ {print $4}')
AVAILABLE_RAM=$(free -m | awk '/^Mem:/ {print $7}')
BUFF_CACHE=$(free -m | awk '/^Mem:/ {print $6}')
SWAP_TOTAL=$(free -m | awk '/^Swap:/ {print $2}')
SWAP_USED=$(free -m | awk '/^Swap:/ {print $3}')

RAM_PERCENT=$(echo "scale=1; $USED_RAM * 100 / $TOTAL_RAM" | bc)
AVAIL_PERCENT=$(echo "scale=1; $AVAILABLE_RAM * 100 / $TOTAL_RAM" | bc)

# Konversi ke GB untuk tampilan
TOTAL_RAM_GB=$(echo "scale=1; $TOTAL_RAM / 1024" | bc)
USED_RAM_GB=$(echo "scale=1; $USED_RAM / 1024" | bc)
AVAIL_RAM_GB=$(echo "scale=1; $AVAILABLE_RAM / 1024" | bc)
BUFF_CACHE_GB=$(echo "scale=1; $BUFF_CACHE / 1024" | bc)
SWAP_TOTAL_GB=$(echo "scale=1; $SWAP_TOTAL / 1024" | bc)
SWAP_USED_GB=$(echo "scale=1; $SWAP_USED / 1024" | bc)

echo -e "  Total RAM     : ${TOTAL_RAM_GB} GB"
echo -e "  Digunakan     : ${USED_RAM_GB} GB"
echo -e "  Tersedia      : ${AVAIL_RAM_GB} GB"
echo -e "  Buffer/Cache  : ${BUFF_CACHE_GB} GB"
echo ""
echo -e "  Penggunaan RAM: $(progress_bar $RAM_PERCENT)"
echo -e "  Status        : $(status_label $RAM_PERCENT $RAM_WARNING $RAM_CRITICAL)"
echo ""
echo -e "  Swap Total    : ${SWAP_TOTAL_GB} GB"
echo -e "  Swap Digunakan: ${SWAP_USED_GB} GB"

if [[ "$SWAP_TOTAL" -gt "0" ]]; then
  SWAP_PERCENT=$(echo "scale=1; $SWAP_USED * 100 / $SWAP_TOTAL" | bc)
  echo -e "  Swap Usage    : $(progress_bar $SWAP_PERCENT)"
  if (( $(echo "$SWAP_PERCENT > 50" | bc -l) )); then
    echo -e "  ${YELLOW}⚠ Swap tinggi! RAM mungkin kurang.${NC}"
  fi
fi

# KSM (Kernel Same-page Merging) - fitur Proxmox hemat RAM
if [[ -f /sys/kernel/mm/ksm/pages_shared ]]; then
  KSM_SHARED=$(cat /sys/kernel/mm/ksm/pages_shared)
  KSM_SAVED=$(echo "scale=1; $KSM_SHARED * 4 / 1024" | bc)
  echo -e "\n  KSM (Memory Dedup): ${KSM_SAVED} MB disimpan dari deduplication"
fi

# Top 5 proses RAM
echo -e "\n  ${BOLD}Top 5 Proses (RAM):${NC}"
ps aux --sort=-%mem | awk 'NR>1 && NR<=6 {printf "    %-8s %-20s %s%%\n", $1, substr($11,1,20), $4}'

# =============================================================================
# BAGIAN 3: STORAGE ANALYSIS
# =============================================================================
print_section "STORAGE ANALYSIS"

echo -e "  ${BOLD}Penggunaan Filesystem:${NC}"
echo ""

# Cek semua mount point
df -h --output=source,fstype,size,used,avail,pcent,target 2>/dev/null | \
  grep -v "^tmpfs\|^udev\|^none\|devtmpfs\|Filesystem" | \
  while IFS= read -r line; do
    DEVICE=$(echo "$line" | awk '{print $1}')
    FSTYPE=$(echo "$line" | awk '{print $2}')
    SIZE=$(echo "$line" | awk '{print $3}')
    USED=$(echo "$line" | awk '{print $4}')
    AVAIL=$(echo "$line" | awk '{print $5}')
    PERCENT=$(echo "$line" | awk '{print $6}' | tr -d '%')
    MOUNT=$(echo "$line" | awk '{print $7}')

    # Skip mount point tidak relevan
    [[ "$MOUNT" == /run* ]] && continue
    [[ "$MOUNT" == /sys* ]] && continue
    [[ "$MOUNT" == /proc* ]] && continue
    [[ "$MOUNT" == /dev/pts ]] && continue

    if (( PERCENT >= STORAGE_CRITICAL )); then
      STATUS="${RED}[KRITIS]${NC}"
    elif (( PERCENT >= STORAGE_WARNING )); then
      STATUS="${YELLOW}[PERINGATAN]${NC}"
    else
      STATUS="${GREEN}[NORMAL]${NC}"
    fi

    printf "  %-30s %6s %6s %6s " "$MOUNT" "$SIZE" "$USED" "$AVAIL"
    echo -e "$STATUS $(progress_bar $PERCENT 2>/dev/null || echo "${PERCENT}%")"
  done

# ZFS Pool Status
if command -v zpool &>/dev/null; then
  echo -e "\n  ${BOLD}ZFS Pool Status:${NC}"
  zpool list -H -o name,size,alloc,free,cap,health 2>/dev/null | \
    while IFS=$'\t' read -r name size alloc free cap health; do
      CAP_NUM=$(echo "$cap" | tr -d '%')
      if [[ "$health" == "ONLINE" ]]; then
        HEALTH_COLOR="${GREEN}"
      elif [[ "$health" == "DEGRADED" ]]; then
        HEALTH_COLOR="${YELLOW}"
      else
        HEALTH_COLOR="${RED}"
      fi
      echo -e "  Pool: ${BOLD}${name}${NC} | Size: ${size} | Used: ${alloc} | Free: ${free} | Cap: ${cap} | Health: ${HEALTH_COLOR}${health}${NC}"
    done
fi

# LVM Info
if command -v pvs &>/dev/null; then
  echo -e "\n  ${BOLD}LVM Physical Volumes:${NC}"
  pvs --noheadings -o pv_name,vg_name,pv_size,pv_free 2>/dev/null | \
    awk '{printf "  PV: %-15s VG: %-15s Size: %-8s Free: %s\n", $1, $2, $3, $4}'
fi

# =============================================================================
# BAGIAN 4: NETWORK ANALYSIS
# =============================================================================
print_section "NETWORK ANALYSIS"

echo -e "  ${BOLD}Interface Network:${NC}"
ip -o addr show | grep -v "lo\|veth\|tap" | \
  awk '{printf "  %-15s %s\n", $2, $4}'

# Cek traffic (baca /proc/net/dev)
echo -e "\n  ${BOLD}Network Traffic (kumulatif sejak boot):${NC}"
cat /proc/net/dev | grep -v "lo:\|Inter\|face" | \
  awk '{
    if (NF >= 10) {
      rx_mb = $2/1024/1024;
      tx_mb = $10/1024/1024;
      printf "  %-15s RX: %8.1f MB | TX: %8.1f MB\n", $1, rx_mb, tx_mb
    }
  }' | grep -v "^\s*$"

# =============================================================================
# BAGIAN 5: PROXMOX VM/CT STATUS
# =============================================================================
print_section "PROXMOX VM & CONTAINER STATUS"

if command -v qm &>/dev/null; then
  echo -e "  ${BOLD}Virtual Machines (KVM):${NC}"
  VM_RUNNING=0
  VM_STOPPED=0

  qm list 2>/dev/null | tail -n +2 | while read -r vmid name status mem bootdisk pid; do
    if [[ "$status" == "running" ]]; then
      STATUS_COLOR="${GREEN}"
      ((VM_RUNNING++)) 2>/dev/null
    else
      STATUS_COLOR="${YELLOW}"
      ((VM_STOPPED++)) 2>/dev/null
    fi
    printf "  VMID: %-6s %-25s Status: ${STATUS_COLOR}%-10s${NC} RAM: %s MB\n" \
      "$vmid" "$name" "$status" "$mem"
  done

  echo -e "\n  ${BOLD}Containers (LXC):${NC}"
  pct list 2>/dev/null | tail -n +2 | while read -r vmid status lock name; do
    if [[ "$status" == "running" ]]; then
      STATUS_COLOR="${GREEN}"
    else
      STATUS_COLOR="${YELLOW}"
    fi
    printf "  CTID: %-6s %-25s Status: ${STATUS_COLOR}%s${NC}\n" \
      "$vmid" "$name" "$status"
  done
fi

# =============================================================================
# BAGIAN 6: DISK HEALTH
# =============================================================================
print_section "DISK HEALTH (S.M.A.R.T)"

if command -v smartctl &>/dev/null; then
  for disk in /dev/sd? /dev/nvme?; do
    [[ -b "$disk" ]] || continue
    SMART_STATUS=$(smartctl -H "$disk" 2>/dev/null | grep "result:" | awk '{print $NF}')
    TEMP=$(smartctl -A "$disk" 2>/dev/null | grep -i "temperature" | head -1 | awk '{print $(NF-1)}')

    if [[ "$SMART_STATUS" == "PASSED" ]]; then
      DISK_COLOR="${GREEN}"
    elif [[ -n "$SMART_STATUS" ]]; then
      DISK_COLOR="${RED}"
    else
      DISK_COLOR="${CYAN}"
      SMART_STATUS="N/A"
    fi

    echo -e "  ${disk}: Health=${DISK_COLOR}${SMART_STATUS}${NC}  Temp=${TEMP:-N/A}°C"
  done
else
  echo -e "  ${YELLOW}smartmontools tidak terinstall. Install: apt install smartmontools${NC}"
fi

# =============================================================================
# BAGIAN 7: SERVICE STATUS
# =============================================================================
print_section "PROXMOX SERVICE STATUS"

SERVICES=("pvedaemon" "pveproxy" "pvestatd" "pve-cluster" "corosync" "qemu-server" "pve-firewall")

for svc in "${SERVICES[@]}"; do
  STATUS=$(systemctl is-active "$svc" 2>/dev/null)
  if [[ "$STATUS" == "active" ]]; then
    echo -e "  ${GREEN}✓${NC} ${svc}: ${GREEN}${STATUS}${NC}"
  elif [[ "$STATUS" == "inactive" ]]; then
    echo -e "  ${YELLOW}○${NC} ${svc}: ${YELLOW}${STATUS}${NC}"
  else
    echo -e "  ${RED}✗${NC} ${svc}: ${RED}${STATUS:-tidak ditemukan}${NC}"
  fi
done

# =============================================================================
# BAGIAN 8: SUMMARY & REKOMENDASI
# =============================================================================
print_header "SUMMARY & REKOMENDASI"

ISSUES=0
WARNINGS=0

# Evaluasi CPU
if (( $(echo "$CPU_USAGE >= $CPU_CRITICAL" | bc -l) )); then
  echo -e "  ${RED}❌ CPU KRITIS: ${CPU_USAGE}% - Segera investigasi proses berat!${NC}"
  ((ISSUES++))
elif (( $(echo "$CPU_USAGE >= $CPU_WARNING" | bc -l) )); then
  echo -e "  ${YELLOW}⚠ CPU TINGGI: ${CPU_USAGE}% - Monitor dan pertimbangkan scale-up${NC}"
  ((WARNINGS++))
else
  echo -e "  ${GREEN}✓ CPU NORMAL: ${CPU_USAGE}%${NC}"
fi

# Evaluasi RAM
if (( $(echo "$RAM_PERCENT >= $RAM_CRITICAL" | bc -l) )); then
  echo -e "  ${RED}❌ RAM KRITIS: ${RAM_PERCENT}% - Tambah RAM atau kurangi VM!${NC}"
  ((ISSUES++))
elif (( $(echo "$RAM_PERCENT >= $RAM_WARNING" | bc -l) )); then
  echo -e "  ${YELLOW}⚠ RAM TINGGI: ${RAM_PERCENT}% - Pertimbangkan tambah RAM${NC}"
  ((WARNINGS++))
else
  echo -e "  ${GREEN}✓ RAM NORMAL: ${RAM_PERCENT}%${NC}"
fi

# Evaluasi Storage (cek semua mount)
df -h | grep -v "tmpfs\|udev\|/run\|/sys\|/proc\|/dev/pts\|Filesystem" | tail -n +2 | \
  awk '{gsub(/%/,"",$5); if($5+0 >= 90) print "CRIT:"$NF":"$5; else if($5+0 >= 75) print "WARN:"$NF":"$5}' | \
  while IFS=: read -r level mount pct; do
    if [[ "$level" == "CRIT" ]]; then
      echo -e "  ${RED}❌ STORAGE KRITIS: ${mount} ${pct}% - Segera bersihkan atau expand!${NC}"
    else
      echo -e "  ${YELLOW}⚠ STORAGE TINGGI: ${mount} ${pct}% - Pantau terus${NC}"
    fi
  done

# Evaluasi Load
if (( $(echo "$LOAD_PER_CPU >= $LOAD_CRITICAL" | bc -l) )); then
  echo -e "  ${RED}❌ LOAD KRITIS: ${LOAD_1} (${LOAD_PER_CPU}/core) - Server overloaded!${NC}"
  ((ISSUES++))
elif (( $(echo "$LOAD_PER_CPU >= $LOAD_WARNING" | bc -l) )); then
  echo -e "  ${YELLOW}⚠ LOAD TINGGI: ${LOAD_1} (${LOAD_PER_CPU}/core)${NC}"
  ((WARNINGS++))
fi

echo ""
if [[ $ISSUES -gt 0 ]]; then
  echo -e "  ${RED}${BOLD}★ STATUS KESELURUHAN: KRITIS ($ISSUES masalah, $WARNINGS peringatan)${NC}"
elif [[ $WARNINGS -gt 0 ]]; then
  echo -e "  ${YELLOW}${BOLD}★ STATUS KESELURUHAN: PERLU PERHATIAN ($WARNINGS peringatan)${NC}"
else
  echo -e "  ${GREEN}${BOLD}★ STATUS KESELURUHAN: SEHAT - Semua resource dalam batas normal${NC}"
fi

echo ""
echo -e "  ${BOLD}Rekomendasi Umum:${NC}"
echo -e "  • Jadwalkan analisis rutin setiap jam/hari"
echo -e "  • Setup alerting via email/Telegram untuk kondisi kritis"
echo -e "  • Backup reguler sebelum perubahan besar"
echo -e "  • Cek log: journalctl -u pvedaemon --since '24 hours ago'"

echo -e "\n${BLUE}${BOLD}══════════════════════════════════════════════════════════════${NC}"
echo -e "  Analisis selesai: $(date '+%Y-%m-%d %H:%M:%S')"
echo -e "${BLUE}${BOLD}══════════════════════════════════════════════════════════════${NC}\n"
```

### 10.2 Script Monitor Berkelanjutan: `proxmox-monitor-loop.sh`

```bash
#!/bin/bash
# Monitor berkelanjutan dengan alert ke log file
# Penggunaan: bash proxmox-monitor-loop.sh 300  (cek setiap 300 detik / 5 menit)

INTERVAL=${1:-300}
LOG_FILE="/var/log/proxmox-monitor.log"
ALERT_LOG="/var/log/proxmox-alerts.log"

CPU_CRITICAL=90
RAM_CRITICAL=95
STORAGE_CRITICAL=90

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

alert() {
  echo "[ALERT][$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$ALERT_LOG"
  logger -t "proxmox-monitor" "ALERT: $1"
}

log "Monitor dimulai. Interval: ${INTERVAL}s"

while true; do
  # CPU Check
  CPU_IDLE=$(top -bn2 -d0.5 | grep "Cpu(s)" | tail -1 | awk '{print $8}' | tr -d '%id,')
  CPU_USAGE=$(echo "100 - ${CPU_IDLE:-0}" | bc)
  CPU_USAGE=$(printf "%.1f" "$CPU_USAGE")

  # RAM Check
  TOTAL_RAM=$(free -m | awk '/^Mem:/ {print $2}')
  USED_RAM=$(free -m | awk '/^Mem:/ {print $3}')
  RAM_PERCENT=$(echo "scale=1; $USED_RAM * 100 / $TOTAL_RAM" | bc)

  log "CPU: ${CPU_USAGE}% | RAM: ${RAM_PERCENT}%"

  # Alert CPU
  if (( $(echo "$CPU_USAGE >= $CPU_CRITICAL" | bc -l) )); then
    alert "CPU KRITIS: ${CPU_USAGE}% pada $(hostname)"
  fi

  # Alert RAM
  if (( $(echo "$RAM_PERCENT >= $RAM_CRITICAL" | bc -l) )); then
    alert "RAM KRITIS: ${RAM_PERCENT}% pada $(hostname)"
  fi

  # Alert Storage
  df -h | grep -v "tmpfs\|udev" | awk '{gsub(/%/,"",$5); if($5+0 >= 90) print $NF" "$5"%"}' | \
    while read -r mount pct; do
      alert "STORAGE KRITIS: ${mount} ${pct} pada $(hostname)"
    done

  sleep "$INTERVAL"
done
```

### 10.3 Script Laporan Harian: `proxmox-daily-report.sh`

```bash
#!/bin/bash
# Kirim laporan harian via email (butuh mailutils: apt install mailutils)
# Setup cron: 0 7 * * * /root/scripts/proxmox-daily-report.sh

EMAIL="admin@perusahaan.com"
SUBJECT="[Proxmox] Daily Report - $(hostname) - $(date '+%Y-%m-%d')"

REPORT=$(bash /root/scripts/proxmox-analyzer.sh 2>/dev/null | sed 's/\x1b\[[0-9;]*m//g')

echo "$REPORT" | mail -s "$SUBJECT" "$EMAIL"
echo "Laporan dikirim ke $EMAIL"

# Simpan laporan ke file
echo "$REPORT" > "/var/log/proxmox-report-$(date '+%Y%m%d').log"
```

### 10.4 Setup Cron untuk Monitor Otomatis

```bash
# Edit crontab
crontab -e

# Tambahkan baris ini:
# Analisis setiap 6 jam
0 */6 * * * /root/scripts/proxmox-analyzer.sh >> /var/log/proxmox-analysis.log 2>&1

# Laporan harian jam 07:00
0 7 * * * /root/scripts/proxmox-daily-report.sh

# Monitor berkelanjutan (jalankan sekali, berjalan di background)
# @reboot /root/scripts/proxmox-monitor-loop.sh 300 &
```

---

## 11. Threshold & Batas Wajar Resource

### 11.1 Panduan Threshold CPU

| Kondisi | CPU Usage | Load/Core | Tindakan |
|---------|-----------|-----------|----------|
| **Ideal** | 0–50% | < 0.5 | Aman, tidak perlu aksi |
| **Normal** | 50–70% | 0.5–0.7 | Pantau secara berkala |
| **Peringatan** | 70–90% | 0.7–0.9 | Identifikasi proses berat |
| **Kritis** | > 90% | > 1.0 | Tindakan segera! |

**Catatan:**

- Load average 1.0 per core = server penuh terpakai
- Load > 1.0 per core = ada antrian proses, server kelebihan beban
- Spike sesaat wajar, yang berbahaya adalah sustained tinggi (> 15 menit)

### 11.2 Panduan Threshold RAM

| Kondisi | RAM Usage | Tindakan |
|---------|-----------|----------|
| **Ideal** | 0–60% | Aman |
| **Normal** | 60–80% | Pantau |
| **Peringatan** | 80–90% | Cek proses, pertimbangkan tambah RAM |
| **Kritis** | > 90% | Segera tambah RAM atau kurangi VM |
| **Bahaya** | > 95% | OOM Killer aktif, sistem tidak stabil |

**Penting:**

- RAM yang "terpakai" oleh buffer/cache **tidak berbahaya** — Linux menggunakannya sebagai cache
- Yang penting adalah **"available"** RAM, bukan "used"
- Jika swap > 50%, RAM hampir habis → tambah RAM segera

### 11.3 Panduan Threshold Storage

| Kondisi | Disk Usage | Tindakan |
|---------|------------|----------|
| **Ideal** | 0–60% | Aman |
| **Normal** | 60–75% | Pantau, rencanakan ekspansi |
| **Peringatan** | 75–85% | Segera tambah storage atau cleanup |
| **Kritis** | 85–90% | Ekspansi segera! Backup terancam gagal |
| **Bahaya** | > 90% | Disk penuh = sistem crash/hang |

### 11.4 Panduan Alokasi Resource VM

#### Aturan Overcommit yang Aman

```
CPU Overcommit:
- Maksimal 4:1 (4 vCPU virtual per 1 CPU core fisik)
- Untuk workload ringan: 8:1 masih acceptable
- Untuk workload berat (database, compute): 1:1 atau 2:1

RAM Overcommit:
- TANPA KSM: 1:1 (tidak overcommit)
- DENGAN KSM: 1.2:1 – 1.5:1 masih aman
- Jangan overcommit RAM lebih dari 1.5:1

Storage Thin Provisioning:
- Total alokasi VM: maksimal 2x kapasitas fisik
- Selalu sisakan 20% free untuk snapshot & operasional
```

#### Contoh Perencanaan Kapasitas Server

```
Server Fisik: 32 Core, 128 GB RAM, 4 TB NVMe

Untuk VM Production Database:
- 8 vCPU (rasio 1:4 dari 32 core = bisa 8 VM sekelas ini)
- 32 GB RAM (dedicated, no overcommit)
- 500 GB disk

Untuk VM Web Server:
- 4 vCPU
- 8 GB RAM
- 100 GB disk

Untuk Container (LXC) - Development:
- 2 vCPU
- 2 GB RAM
- 20 GB disk
```

---

## 12. Backup dan Restore

### 12.1 Backup Manual

```bash
# Backup VM 100 ke storage "backup-nfs"
vzdump 100 --storage backup-nfs --mode snapshot --compress zstd

# Backup dengan retention (simpan 7 backup terakhir)
vzdump 100 --storage backup-nfs --mode snapshot --compress zstd --maxfiles 7

# Backup semua VM
vzdump --all --storage backup-nfs --mode snapshot --compress zstd

# Mode backup:
# --mode snapshot  : Backup tanpa downtime (rekomendasi, butuh LVM/ZFS)
# --mode suspend   : Suspend VM saat backup
# --mode stop      : Stop VM saat backup (paling konsisten, ada downtime)
```

### 12.2 Backup Terjadwal via Web UI

1. Buka **Datacenter → Backup**
2. Klik **Add**
3. Isi jadwal (setiap hari/minggu)
4. Pilih VM/CT yang akan dibackup
5. Pilih storage tujuan
6. Set retention (berapa backup disimpan)
7. Klik **Create**

### 12.3 Restore

```bash
# Restore VM dari backup
qmrestore /var/lib/vz/dump/vzdump-qemu-100-2024_01_01.vma.zst 100

# Restore ke VMID baru
qmrestore /var/lib/vz/dump/vzdump-qemu-100-2024_01_01.vma.zst 200 --force

# Restore Container
pct restore 200 /var/lib/vz/dump/vzdump-lxc-200-2024_01_01.tar.zst

# Via pvesh API
pvesh create /nodes/pve/qemu --vmid 100 \
  --archive /var/lib/vz/dump/vzdump-qemu-100-2024_01_01.vma.zst
```

---

## 13. Cluster Proxmox

### 13.1 Apa Itu Cluster?

Cluster adalah penggabungan beberapa server Proxmox (node) yang bisa saling berkomunikasi, berbagi data, dan mendukung **High Availability (HA)** — VM bisa otomatis pindah ke node lain jika ada node yang mati.

```
┌─────────────────────────────────────────────────────────┐
│                   PROXMOX CLUSTER                       │
│                                                         │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────────┐ │
│  │   Node 1    │  │   Node 2    │  │    Node 3       │ │
│  │ (Primary)   │  │             │  │                 │ │
│  │  VM 100,101 │  │  VM 102,103 │  │   VM 104,105    │ │
│  └──────┬──────┘  └──────┬──────┘  └────────┬────────┘ │
│         └────────── Corosync Network ────────┘          │
│                    (heartbeat/sync)                     │
│                          ↓                              │
│              ┌─────────────────────┐                   │
│              │  Shared Storage     │                   │
│              │ (Ceph / NFS / iSCSI)│                   │
│              └─────────────────────┘                   │
└─────────────────────────────────────────────────────────┘
```

### 13.2 Membuat Cluster

```bash
# Pada node pertama (primary):
pvecm create nama-cluster

# Pada node lain (join cluster):
pvecm add [IP-NODE-PRIMARY]

# Cek status cluster
pvecm status

# Lihat anggota cluster
pvecm nodes
```

### 13.3 High Availability (HA)

```bash
# Enable HA untuk VM
ha-manager add vm:100 --state started --group default

# Lihat status HA
ha-manager status

# Lihat semua resource HA
ha-manager config
```

---

## 14. Keamanan Server Proxmox

### 14.1 Hardening Dasar

```bash
# ─── FIREWALL ────────────────────────────────────────────────
# Enable Proxmox built-in firewall
# Datacenter → Firewall → Enable

# Aturan firewall penting (di level Datacenter):
# - Izinkan port 8006 (Web UI) hanya dari IP admin
# - Izinkan port 22 (SSH) hanya dari IP admin
# - Izinkan port 3128 (Spice Proxy) jika dibutuhkan
# - Blokir semua yang tidak perlu

# ─── SSH HARDENING ───────────────────────────────────────────
# Edit /etc/ssh/sshd_config:
sed -i 's/#PermitRootLogin yes/PermitRootLogin prohibit-password/' /etc/ssh/sshd_config
sed -i 's/#PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config
sed -i 's/#Port 22/Port 2222/' /etc/ssh/sshd_config

# Setup SSH key
ssh-keygen -t ed25519 -C "admin@server"
# Copy public key ke authorized_keys

systemctl restart sshd

# ─── FAIL2BAN ────────────────────────────────────────────────
apt install fail2ban -y

cat > /etc/fail2ban/jail.local << 'EOF'
[DEFAULT]
bantime = 1h
findtime = 10m
maxretry = 5

[sshd]
enabled = true
port = 2222

[proxmox]
enabled = true
port = 8006
filter = proxmox
logpath = /var/log/daemon.log
maxretry = 3
bantime = 1h
EOF

# Buat filter proxmox
cat > /etc/fail2ban/filter.d/proxmox.conf << 'EOF'
[Definition]
failregex = pvedaemon\[.*authentication failure; rhost=<HOST> user=.* msg=.*
ignoreregex =
EOF

systemctl enable --now fail2ban

# ─── MANAJEMEN USER ──────────────────────────────────────────
# Tambah user admin terbatas (bukan root)
pveum user add admin@pve --password "SecurePass123!" --comment "Admin User"
pveum acl modify / --user admin@pve --role Administrator

# Tambah user readonly (monitoring only)
pveum user add monitor@pve --password "MonPass456!"
pveum acl modify / --user monitor@pve --role PVEAuditor

# Lihat semua user
pveum user list

# ─── SERTIFIKAT SSL ──────────────────────────────────────────
# Gunakan Let's Encrypt (jika server bisa diakses internet)
# Datacenter → ACME → Konfigurasi domain

# Atau generate self-signed cert
pvecm updatecerts --force
```

### 14.2 Best Practice Keamanan

```
✓ Gunakan SSH key, bukan password
✓ Ganti port SSH dari 22 ke nomor lain
✓ Enable firewall Proxmox
✓ Akses Web UI hanya melalui VPN
✓ Update Proxmox secara rutin
✓ Pisahkan network management dari network VM
✓ Gunakan 2FA (Two Factor Authentication) untuk login Proxmox
✓ Audit log secara berkala
✓ Backup konfigurasi /etc/pve secara rutin
✓ Jangan jalankan service tidak perlu di node Proxmox
```

---

## 15. Pengetahuan Server Profesional

### 15.1 Komponen Hardware Server

#### CPU

```
Intel Xeon / AMD EPYC = CPU khusus server
Fitur penting:
- ECC memory support (deteksi & koreksi error memori)
- Lebih banyak core (16, 32, 64 core)
- PCIe lanes lebih banyak
- NUMA (Non-Uniform Memory Access) untuk performa multi-socket
- Hyper-Threading (Intel) / SMT (AMD) = 2x thread per core

Generasi populer:
- Intel Xeon Scalable (Ice Lake, Sapphire Rapids)
- AMD EPYC (Milan, Genoa)
```

#### RAM Server

```
DDR4/DDR5 ECC (Error Correcting Code):
- Mendeteksi dan memperbaiki error bit memori secara otomatis
- Wajib untuk server production
- Lebih mahal dari RAM biasa (non-ECC)

RDIMM (Registered DIMM):
- Memiliki register/buffer untuk stabilitas
- Memungkinkan kapasitas RAM lebih besar

LRDIMM (Load Reduced DIMM):
- Seperti RDIMM tapi lebih bisa diskalakan
- Untuk server dengan RAM 512 GB+
```

#### Storage

```
Hierarchy Kecepatan (cepat → lambat):
1. NVMe SSD (PCIe 4.0/5.0): 3,000–14,000 MB/s
2. SATA SSD: 500–600 MB/s
3. SAS HDD: 150–200 MB/s, 15,000 RPM
4. SATA HDD: 100–180 MB/s, 7,200 RPM

Untuk Proxmox:
- OS + Proxmox: SSD (minimal)
- VM Disk Production: NVMe SSD
- Backup & Arsip: HDD (lebih murah per GB)
- Database: NVMe SSD dedicated

RAID Hardware:
- RAID 1: Mirror (2 disk), tahan 1 disk mati
- RAID 5: Parity (minimal 3 disk), tahan 1 disk mati
- RAID 6: Double parity (minimal 4 disk), tahan 2 disk mati
- RAID 10: Mirror+Stripe (minimal 4 disk), performa & redundansi
```

#### Network

```
1 Gbps (1000BASE-T): Untuk akses manajemen & VM biasa
10 Gbps (10GbE): Untuk storage network & VM berat
25/100 Gbps: Untuk data center besar

NIC Bonding (Link Aggregation):
- Active-Backup: Redundansi (satu aktif, satu standby)
- LACP/802.3ad: Load balancing + redundansi
- Balance-RR: Round-robin (butuh switch support)
```

### 15.2 Konsep NUMA

NUMA (Non-Uniform Memory Access) penting untuk server multi-socket:

```
Socket 0 (CPU 0-15) ←→ RAM Bank 0 (cepat)
Socket 1 (CPU 16-31) ←→ RAM Bank 1 (cepat)

CPU 0 mengakses RAM Bank 0: CEPAT (local)
CPU 0 mengakses RAM Bank 1: LAMBAT (remote, via QPI/UPI)

Untuk performa optimal VM:
- Pin vCPU VM ke satu NUMA node
- Alokasi RAM dari NUMA node yang sama
```

```bash
# Lihat topologi NUMA
numactl --hardware

# Lihat NUMA stats
numastat

# Pin VM ke NUMA node 0 (via Proxmox config)
# Edit /etc/pve/qemu-server/100.conf:
# numa: 0
# cpu: host,sockets=1,cores=8
```

### 15.3 Power Management

```bash
# Cek governor CPU
cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor

# Set ke performance (untuk server production)
for cpu in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; do
  echo performance > $cpu
done

# Permanent via /etc/default/grub:
# GRUB_CMDLINE_LINUX_DEFAULT="... intel_pstate=disable"

# Monitor power consumption
apt install powertop -y
powertop --auto-tune  # Optimasi otomatis untuk efisiensi
```

### 15.4 Monitoring Stack Profesional

Untuk lingkungan enterprise, gunakan stack monitoring lengkap:

```
┌─────────────────────────────────────────────────────────┐
│           PROFESSIONAL MONITORING STACK                 │
│                                                         │
│  Proxmox Node/VM → node_exporter → Prometheus           │
│                                         ↓               │
│                                      Grafana            │
│                                    (Dashboard)          │
│                                         ↓               │
│                                    AlertManager         │
│                               (Email/Slack/PagerDuty)   │
└─────────────────────────────────────────────────────────┘
```

#### Setup Prometheus + Grafana untuk Proxmox

```bash
# Install Prometheus Node Exporter di setiap node
apt install prometheus-node-exporter -y
systemctl enable --now prometheus-node-exporter

# Cek apakah berjalan (port 9100)
curl http://localhost:9100/metrics | head -20

# Install prometheus-pve-exporter (khusus Proxmox metrics)
pip3 install prometheus-pve-exporter --break-system-packages

# Konfigurasi pve.yml untuk pve_exporter:
cat > /etc/prometheus/pve.yml << 'EOF'
default:
  user: monitor@pve
  password: MonPass456!
  verify_ssl: false
EOF

# Jalankan PVE exporter
pve_exporter /etc/prometheus/pve.yml 9221 &
```

**Grafana Dashboard siap pakai untuk Proxmox:**

- Dashboard ID: 10347 (Proxmox via Prometheus)
- Import di Grafana: Dashboards → Import → masukkan ID

### 15.5 Kapasitas dan Perencanaan (Capacity Planning)

```
Framework Capacity Planning:

1. MEASURE (Ukur kondisi saat ini)
   - Kumpulkan data resource utilization selama 4 minggu
   - Identifikasi peak hours dan peak days

2. ANALYZE (Analisis tren)
   - Hitung pertumbuhan rata-rata per bulan
   - Identifikasi bottleneck

3. PROJECT (Proyeksikan kebutuhan)
   - Estimasi kebutuhan 6 bulan / 1 tahun ke depan

4. PLAN (Rencanakan ekspansi)
   - Kapan perlu upgrade CPU/RAM
   - Kapan perlu tambah node cluster
   - Kapan perlu ekspansi storage

Aturan Praktis:
- Mulai pertimbangkan upgrade saat resource rata-rata > 70%
- Order hardware saat rata-rata > 80% (lead time pengiriman)
- JANGAN tunggu sampai kritis (> 90%)
```

### 15.6 Dokumentasi Server Profesional

Setiap server production harus memiliki dokumentasi:

```markdown
## Server Documentation Template

### Informasi Dasar
- Hostname: pve01.company.local
- IP: 192.168.1.10
- Lokasi: Rack 5, Unit 3
- Serial Number: XXXXXXXX
- Tanggal Instalasi: 2024-01-01
- PIC: Nama Admin

### Hardware
- CPU: Intel Xeon Gold 6226R (16 Core, 2.9 GHz)
- RAM: 128 GB DDR4 ECC
- Storage: 2x 480 GB NVMe (RAID-1, OS), 4x 3.8 TB NVMe (ZFS RAIDZ2, VM)
- Network: 4x 10GbE (Bonding)

### Software
- OS: Proxmox VE 8.x
- Kernel: 6.x.x-pve
- Versi PVE: 8.x.x

### Network
- Management: 192.168.1.10/24, GW: 192.168.1.1
- Storage Network: 10.10.1.10/24
- VM Network: 10.20.0.0/16

### VM/Container List
| VMID | Nama | OS | vCPU | RAM | Disk | Fungsi |
|------|----|---|------|-----|------|--------|
| 100 | web-prod | Ubuntu 22.04 | 4 | 8 GB | 100 GB | Web Server |
| 101 | db-prod | Ubuntu 22.04 | 8 | 32 GB | 500 GB | Database |

### Kontak & Eskalasi
- Level 1: Admin IT - admin@company.com - 08xxx
- Level 2: Senior Engineer - senior@company.com - 08xxx
- Level 3: Vendor Support - Proxmox Support - ticket system
```

---

## 16. Troubleshooting Umum

### 16.1 VM Tidak Bisa Start

```bash
# Cek error dari log
qm start 100  # Perhatikan output error

# Cek log VM
cat /var/log/pve/qemu-server/100.log

# Cek apakah disk tersedia
ls -la /dev/pve/vm-100-disk-0  # Untuk LVM

# Cek apakah ada proses zombie
ps aux | grep "kvm.*100"

# Force kill jika stuck
qm stop 100 --timeout 0
kill -9 $(pgrep -f "kvm.*100")
```

### 16.2 Web UI Tidak Bisa Diakses

```bash
# Cek service
systemctl status pveproxy pvedaemon

# Restart service
systemctl restart pveproxy pvedaemon

# Cek port
ss -tlnp | grep 8006

# Cek sertifikat
pvecm updatecerts --force
```

### 16.3 Storage Penuh

```bash
# Cari file besar
du -sh /var/lib/vz/* | sort -rh | head -20
du -sh /var/log/* | sort -rh | head -10

# Bersihkan log lama
journalctl --vacuum-size=500M
journalctl --vacuum-time=7d

# Bersihkan backup lama
ls -la /var/lib/vz/dump/
rm /var/lib/vz/dump/vzdump-qemu-XXX-YYYY_MM_DD*.vma.zst  # Sesuaikan nama file

# Bersihkan template tidak terpakai
ls /var/lib/vz/template/
```

### 16.4 Node Keluar dari Cluster

```bash
# Cek status cluster
pvecm status

# Cek service corosync
systemctl status corosync

# Cek koneksi antar node
ping [IP-NODE-LAIN]

# Restart corosync dan pve-cluster
systemctl restart corosync pve-cluster

# Jika masih error, cek quorum
pvecm expected 1  # Temporary fix jika satu node tersisa
```

### 16.5 High CPU Load

```bash
# Identifikasi VM penyebab
# Lihat CPU usage per VM menggunakan:
for vmid in $(qm list | awk 'NR>1 {print $1}'); do
  STATUS=$(qm status $vmid | awk '{print $2}')
  if [[ "$STATUS" == "running" ]]; then
    CPU=$(pvesh get /nodes/$(hostname)/qemu/$vmid/status/current 2>/dev/null | \
      python3 -c "import sys,json; d=json.load(sys.stdin); print(f'{d.get(\"cpu\",0)*100:.1f}%')" 2>/dev/null)
    NAME=$(qm config $vmid | grep ^name | awk '{print $2}')
    echo "VM $vmid ($NAME): CPU $CPU"
  fi
done

# Limit CPU VM yang berat
qm set 100 --cpulimit 2  # Max 2 core equivalent
qm set 100 --cpuunits 512  # Prioritas CPU (default 1024)
```

---

## 17. Referensi & Panduan Lanjutan

### 17.1 Dokumentasi Resmi

- **Proxmox VE Docs**: <https://pve.proxmox.com/pve-docs/>
- **Proxmox Wiki**: <https://pve.proxmox.com/wiki/Main_Page>
- **Proxmox Forum**: <https://forum.proxmox.com/>
- **Proxmox API**: <https://pve.proxmox.com/pve-docs/api-viewer/>

### 17.2 Perintah CLI Penting — Quick Reference

```bash
# ─── VM MANAGEMENT ───────────────────────────────────────────
qm list                     # List semua VM
qm status <vmid>            # Status VM
qm start <vmid>             # Start VM
qm stop <vmid>              # Stop VM (hard)
qm shutdown <vmid>          # Shutdown graceful
qm reboot <vmid>            # Reboot VM
qm config <vmid>            # Lihat konfigurasi VM
qm set <vmid> --memory 4096 # Ubah konfigurasi VM
qm monitor <vmid>           # QEMU monitor prompt
qm snapshot <vmid> <name>   # Buat snapshot

# ─── CONTAINER MANAGEMENT ────────────────────────────────────
pct list                    # List semua container
pct status <ctid>           # Status container
pct start <ctid>            # Start container
pct stop <ctid>             # Stop container
pct enter <ctid>            # Masuk ke container
pct config <ctid>           # Lihat konfigurasi container
pct set <ctid> --memory 2048 # Ubah konfigurasi

# ─── STORAGE MANAGEMENT ──────────────────────────────────────
pvesm status                # Status semua storage
pvesm list <storage>        # List isi storage
pvesm alloc <storage> <vmid> <filename> <size>  # Alokasi disk baru
pvesm free <storage> <vmid>:<filename>           # Hapus disk

# ─── BACKUP ──────────────────────────────────────────────────
vzdump <vmid>               # Backup VM/CT
vzdump --all                # Backup semua

# ─── CLUSTER ─────────────────────────────────────────────────
pvecm status                # Status cluster
pvecm nodes                 # List node
pvecm add <ip>              # Join node ke cluster

# ─── HA ──────────────────────────────────────────────────────
ha-manager status           # Status HA
ha-manager add vm:<vmid>    # Enable HA untuk VM

# ─── SYSTEM ──────────────────────────────────────────────────
pveversion                  # Versi Proxmox
pveupdate                   # Update package list
pveupgrade                  # Upgrade Proxmox
pvesh get /nodes            # API call via shell
```

### 17.3 Istilah Teknis Penting

| Istilah | Definisi |
|---------|---------|
| **Hypervisor** | Software yang mengelola VM di atas hardware |
| **KVM** | Kernel-based Virtual Machine — teknologi virtualisasi Linux |
| **QEMU** | Emulator yang bekerja bersama KVM |
| **LXC** | Linux Containers — containerisasi level OS |
| **VirtIO** | Driver I/O yang dioptimalkan untuk VM (lebih cepat dari emulasi) |
| **NUMA** | Non-Uniform Memory Access — arsitektur memori multi-socket |
| **IOPS** | Input/Output Operations Per Second — ukuran kecepatan storage |
| **Latency** | Waktu respons (ms/μs) — penting untuk database |
| **Throughput** | Bandwidth data (MB/s) — penting untuk backup/bulk transfer |
| **Quorum** | Mekanisme voting cluster untuk mencegah split-brain |
| **Split-brain** | Kondisi dua node cluster berpikir yang lain mati |
| **Fencing** | Mekanisme isolasi node bermasalah (STONITH) |
| **Live Migration** | Pindah VM antar node tanpa downtime |
| **Cold Migration** | Pindah VM antar node dengan downtime |
| **Thin Provisioning** | Alokasi storage secara virtual, tidak langsung fisik |
| **Overcommit** | Alokasi resource virtual melebihi kapasitas fisik |
| **KSM** | Kernel Same-page Merging — deduplikasi memori |
| **CoW** | Copy-on-Write — teknik snapshot efisien |
| **OOM Killer** | Out-of-Memory Killer — Linux membunuh proses saat RAM penuh |

### 17.4 Checklist Maintenance Rutin

```
HARIAN:
□ Cek status semua VM/CT (running/stopped sesuai ekspektasi)
□ Cek alert di monitoring (CPU/RAM/Storage)
□ Cek task log Proxmox untuk error
□ Verifikasi backup selesai dan berhasil

MINGGUAN:
□ Review log system (journalctl --since "7 days ago")
□ Update package (apt update && apt list --upgradable)
□ Cek disk health (smartctl)
□ Review resource utilization trend
□ Test restore backup (minimal satu VM)

BULANAN:
□ Apply security updates
□ Upgrade Proxmox jika ada versi baru
□ Review kapasitas dan proyeksi pertumbuhan
□ Audit user dan permission
□ Rotasi credential/password admin
□ Review dan update dokumentasi

TAHUNAN:
□ Renew SSL certificate
□ Review hardware warranty
□ Evaluasi capacity planning jangka panjang
□ Disaster Recovery drill (simulasi kegagalan server)
□ Audit keamanan menyeluruh
```

---

*Dokumen ini dibuat sebagai panduan komprehensif Proxmox VE.*  
*Untuk informasi terbaru, selalu rujuk ke [dokumentasi resmi Proxmox](https://pve.proxmox.com/pve-docs/).*  
*Versi Proxmox yang dirujuk: PVE 8.x (Debian Bookworm based)*

---
**Dibuat:** April 2026 | **Bahasa:** Indonesia | **Level:** Pemula → Profesional
