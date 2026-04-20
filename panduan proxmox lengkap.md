# 📘 PANDUAN LENGKAP PROXMOX VE (ENTERPRISE EDITION)

## Panduan Utama Dari Level Awam hingga *Cloud Architect*

> **Edisi Disempurnakan (Ultimate Guide):** Dokumen ini dirancang sebagai pedoman komprehensif tanpa kompromi untuk memahami Proxmox Virtual Environment (PVE). Telah divalidasi dan diperkaya dengan standar ketat industri *Data Center*, mencakup dari instalasi dasar hingga konfigurasi kelas super (*SDN, Ceph, ZFS Replication, SR-IOV/IOMMU Passthrough, Terraform IaC, dan Mitigasi Bencana/QDevice*).
> 
> *Cocok digunakan sebagai literatur referensi tertinggi oleh Engineer, System Administrator, maupun asisten AI untuk memecahkan segala kasus fungsional dan operasional.*

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
16. [Fitur Advanced & Optimasi Lanjutan](#16-fitur-advanced--optimasi-lanjutan)
17. [Troubleshooting Umum](#17-troubleshooting-umum)
18. [Referensi & Panduan Lanjutan](#18-referensi--panduan-lanjutan)

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

### 6.5 Optimasi Wajib VM (Guest Agent, Ballooning, & Watchdog)

Ribuan pengguna pemula sering mengeluh: *"Kenapa RAM VM saya di Proxmox terbaca 90%, tapi saat dicek di dalam Windows/Ubuntu cuma dipakai 10%?"* atau *"Kenapa saat di-backup, database saya sering korup/error?"* 
Jawabannya karena mereka **lupa menginstal QEMU Guest Agent**.

**1. QEMU Guest Agent (Wajib!)**
Ini adalah *software* penghubung komunikasi antara OS di dalam VM dengan layar Proxmox.
- **Tanpa Guest Agent**: Proxmox buta terhadap apa yang terjadi di dalam VM. Proxmox tak bisa melihat IP address Anda di panel *Summary*, mematikan VM terasa seperti memutus kabel listrik paksa, dan proses Backup sangat rawan mengorupsi *database* yang sedang berjalan.
- **Cara Aktifkan**:
  1. Di Web GUI: Klik VM → Options → QEMU Guest Agent → Edit centang **Use QEMU Guest Agent (Enabled)**.
  2. Masuk ke dalam OS VM Linux Anda dan ketik: `apt install qemu-guest-agent -y && systemctl start qemu-guest-agent`.
  3. *(Khusus Windows, Anda harus mengambilnya dari CD Driver VirtIO berlabel `qemu-ga-x86_64.msi`)*.

**2. Memory Ballooning**
Pernahkah Anda bertanya bagaimana triknya Cloud Hosting berani menjual VPS/VM kapasitas 16GB ke banyak pelanggan padahal RAM fisik server mereka terbatas? Triknya adalah *Ballooning*.
- Ketika VM A tidak memakai RAM-nya, Proxmox akan menghembuskan suatu "Balon" virtual pencabut memori ke dalam VM A untuk merampas kembali sisa RAM-nya, lalu meminjamkannya ke VM B yang sedang butuh ngebut.
- Fitur dinamis *Auto-Scaling* ini **hanya** berfungsi jika QEMU Guest Agent terpasang sempurna!

**3. Watchdog Timer (Asisten Bekerja Semalaman)**
Jika VM Windows Server Anda tiba-tiba *Blue Screen* (BSOD) atau Linux mengalami *Kernel Panic* di jam 2 pagi, VM tersebut akan hang selamanya (memakan energi CPU 100%) sampai Anda bangun dan menekan paksa tombol *Reset* esok harinya.
- **Watchdog Timer** adalah "Anjing Penjaga". OS VM harus mengirim sinyal "Saya hidup!" ke Proxmox setiap beberapa detik. Jika VM hang atau *Blue Screen*, anjing ini tidak menerima sinyal dan akan secara otomatis **merestart VM tersebut**!
- **Cara Setup**: Hardware → Add → Watchdog Timer → Pilih *i6300esb*. Di dalam VM, tinggal *install watchdog daemon*, lalu Anda serahkan OS untuk diwasiati penjaga otomatis yang tak pernah tidur.

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

### 7.4 Ceph: Hyper-Converged Storage (Level Enterprise)

Panduan di atas menyebutkan ZFS (lokal) dan NFS (jaringan). Namun, jika Anda menginginkan **High Availability (HA)** mutlak—di mana VM bisa pindah otomatis ke mesin lain secara instan, Anda butuh penyimpanan yang tersebar (*Distributed*). Solusi jawaranya adalah **Ceph**.
- **Ceph** menyulap susunan SSD/NVMe bawaan dari beberapa server fisik menjadi satu "Kolam / Pool" raksasa yang transparan.
- Setiap keping data VM akan di-*copy* ke minimal 2 atau 3 server berbeda (*replica*) secara langsung.
- Jika satu server fisik utuh (beserta seluruh disknya) hangus/rusak tiba-tiba, VM Anda secara ajaib tetap bisa di-*start* dari server lain karena salinan *real-time* datanya ada di sana.

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

### 8.4 Software-Defined Network (SDN) & VxLAN

Pada Proxmox VE 8, **SDN (Software-Defined Network)** resmi diperkenalkan yang akhirnya mengubah peta jaringan tradisional (*VLAN* konvensional).
- **VxLAN (Virtual eXtensible LAN)**: Bayangkan Anda memiliki sebuah server Proxmox di *Data Center* kawasan A, dan server lain di kawasan B. Via teknologi VxLAN di SDN Proxmox, Anda bisa melemparkan sebuah "Kabel Switch Virtual" kasat mata yang menjahit gedung A dan gedung B agar mesin VM di dalamnya seakan-akan satu colokan *switch* lokal L2 (*Layer-2*), tanpa dipusingkan oleh blokade IP Public/Mikrotik di luarnya!
- Cocok buat membangun ekosistem komputasi perusahaan yang berskala lintas-wilayah (multi-site).

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

> **Catatan:** Kode script tidak lagi ditulis panjang di sini untuk mempermudah pembacaan.
> Anda dapat melihat, mengedit, atau mengunduh script lengkapnya melalui tautan berikut:

📄 **[Lihat/Edit proxmox-analyzer.sh](proxmox-analyzer.sh)**


### 10.2 Integrasi Notifikasi Otomatis (Telegram / WhatsApp)

> Script `proxmox-analyzer.sh` dirancang untuk berjalan secara otomatis via Cronjob dan dapat mengirim peringatan ke Telegram atau WhatsApp menggunakan n8n (Webhook).

Fitur mutakhir yang disematkan:
- **Mode `--alert-only`**: Script berjalan diam-diam (senyap) di background. Jika tidak ada error, script tidak mencetak apapun. Jika ada error kritis, script hanya mencetak alert murni yang siap dikirim.
- **Multi-node Identifier (`--name`)**: Mendukung nama pembeda (contoh: `--name="PVE-Utama"`) sehingga Anda tahu notifikasi berasal dari mesin mana.

📄 **[Lihat Blueprint Integrasi n8n Lengkap](rencana-integrasi.md)**

### 10.3 Contoh Setup Cronjob Sederhana

Jika Anda hanya ingin menyimpan hasil analisis masalah ke dalam log (tanpa n8n):

```bash
# Edit crontab
crontab -e

# Tambahkan baris ini untuk mengecek per 30 menit (hanya mencetak log jika ada masalah)
*/30 * * * * bash /root/scripts/proxmox-analyzer.sh --alert-only --no-color --name="Node-01" >> /var/log/pve-alerts.log 2>&1
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

### 13.4 Eksekusi Live Migration (Migrasi Tanpa Mati)

Tutorial *Backup* lazimnya memakan waktu karena data harus dibekukan. Tetapi bagaimana jika siang bolong Anda darurat melihat *RAM server fisik utama* mulai rusak/terbakar, dan aplikasi perusahaan tak boleh mati barang sesaat pun? Konsep penyelamatnya dinamakan **Live Migration**!
- Fitur ini absolut mensyaratkan server tergabung dalam **satu Cluster** (Bab 13) dan memakai **Shared Storage** (seperti *Ceph/NFS* di Bab 7) agar semua host bisa mengakses file `disk` VM tersebut secara sejajar.
- **Cara eksekusi**: Di GUI Proxmox, cukup Klik Kanan nama VM Anda → Pilih **Migrate** → Pilih panah *Target Node* fisik → Centang bagian **Online**.
- **Keajaiban di balik layar**: Proxmox akan menembakkan isi RAM (memori kognitif) dari VM tersebut via kabel LAN dengan laju *Gigabit* tanpa perlu *Shut down*. Pada detik persis perpindahan, VM di mesin lama membeku (sekitar nol koma sekian milidetik), dan seketika bangun di mesin tujuan dan masih meneruskan pekerjaannya. Nyaris tak ada paket PING yang jatuh di hadapan *User*!

### 13.5 ZFS Storage Replication (Disaster Recovery Kelas Ringan)

Ceph sangat luar biasa (lihat Bab 7.4), namun mewajibkan kehadiran minimal 3 buah *server fisik* (Nodes) berspesifikasi super tinggi. Jika Anda **hanya memiliki 2 Server Proxmox**, Anda tidak direkomendasikan memakai Ceph. Sang penyelamat kemiskinan di skenario ini adalah **ZFS Replication**.

- **Cara Kerja**: Jika kedua Node menggunakan partisi penggerak lokal berformat ZFS, Anda bisa menjadwalkan siklus sinkronisasi data antar VM setiap *15 menit* (atau bahkan super ketat setiap *1 menit*!). Proxmox hanya akan mendeteksi dan mengirim bit-bit data terkecil yang berubah (pemanfaatan insting *ZFS Send/Recv* delta) sehingga nyaris tidak membebani lalu lintas kabel LAN.
- **Keuntungan Taktis (Disaster Recovery)**: Apabila Node 1 menelan korsleting listrik dan mati total, Anda hanya perlu Login ke Node 2, mencari bayangan (*replica*) VM tersebut, dan menekan tombol **Start**. VM akan spontan menyala dan batas kerugian data Anda *(Recovery Point Objective / RPO)* paling malang hanyalah mundurnya waktu sekitar 1-15 menit ke belakang.
- **Cara Setup Secara GUI**: Di area kiri bawah per-layar VM Anda, kunjungi menu **Replication** → Klik **Add** → Tentukan *Target Node*, lalu di bagian jadwal (*Schedule*) ketik parameter dewasanya: `*/1` (sinkronisasi per 1 menit tanpa lelah).

### 13.6 Corosync QDevice (Arbiter Pihak Ketiga untuk 2-Node)

Sebagai kelanjutan dari ZFS Replication di *Cluster 2-Node*, ada satu celah hukum kritis: Jika Node 1 mati total, Node 2 secara *default* akan mengalami *Quorum Loss* (kehilangan suara mayoritas) dan sistem akan membekukan dirinya secara sepihak menjadi *Read-Only* untuk mencegah cacat *Split-Brain*. Anda terpaksa meretasnya manual via `pvecm expected 1` (Bab 17.7).

Solusi *Standar Industri* untuk Cluster 2-Node yang direkomendasikan wiki resmi Proxmox adalah **QDevice (Quorum Device)**.
- **Konsep**: Anda menginstal utilitas eksternal `corosync-qdevice` di mesin ketiga yang sangat murah dan *lightweight*, misal Raspberry Pi atau penyewaan VPS Cloud seharga Rp50Ribu/bulan.
- Opsi ini tidak menyimpan data VM apa pun; wewenangnya *murni* hanya untuk menumpang memberikan **VOTING KETIGA (Tie-Breaker)**.
- Dengan QDevice terkalibrasi, sewaktu Node 1 meledak, himpunan Node 2 + QDevice masih sah memegang 2 dari 3 suara, sehingga Node 2 tak akan meneteskan keringat kepanikan dan sisa cluster tetap hidup proporsional 100% bebas intervensi.

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

### 15.7 Aturan Sakral Sistem Update Proxmox (Waspada!)

Banyak malapetaka dialami *System Administrator* pendatang baru yang lahir dari budaya *Debian/Ubuntu*. Ketika melihat pemberitahuan rilis (*updates*), refleks mereka adalah mengetikkan peluru ini di terminal: `apt update && apt upgrade`.
Di kawasan ekosistem Proxmox, menekan `apt upgrade` **adalah dosa fatal** yang bisa menghancurleburkan seluruh pondasi *Host* Anda!

1. Proxmox tak memakai *kernel* Debian biasa. Keterikatan komponen KVM, QEMU, dan sistem disk ZFS dirangkul teramat ketat (*tight software dependencies*). *Upgrade* standar bisa tidak sengaja 'menyisihkan' / 'mendepak' library vital Proxmox dan melahirkan kepincangan (*broken libraries*).
2. **SOP Mutlak Berstandar Internasional**: Anda **selalu diwajibkan** mendaratkan perintah ini (*Distro-grade upgrade*):
   ```bash
   apt update
   apt dist-upgrade   # Atau opsional memakai apt full-upgrade
   ```
3. Anda baru sadar betapa rawannya perintah ini makanya pihak pembuat menyematkan satu tombol spesial **"Upgrade"** tersendiri yang diprogram aman di dalam Web GUI Anda (*Node → System → Updates → Upgrade*).

---

## 16. Fitur Advanced & Optimasi Lanjutan

### 16.1 Limitasi RAM ZFS ARC (Sangat Penting!)

Salah satu "jebakan" terbesar di Proxmox adalah **ZFS ARC (Adaptive Replacement Cache)**. Secara default, ZFS akan memakan hingga **50% dari total RAM fisik Anda** untuk menyimpan *cache* disk. Hal ini sering membuat admin panik karena RAM terlihat penuh, padahal itu hanya cache.

Cara melimitasi ARC agar tidak rakus RAM (Misal: maksimal 4GB):

```bash
# 1. Edit / buat file modprobe ZFS
nano /etc/modprobe.d/zfs.conf

# 2. Tambahkan baris berikut (angka dalam Bytes, contoh 4GB = 4 * 1024^3 = 4294967296):
options zfs zfs_arc_max=4294967296

# 3. Update initramfs agar konfigurasi dimuat saat booting
update-initramfs -u -k all

# 4. Reboot server
reboot
```

### 16.2 PCI / GPU Passthrough (IOMMU)

Fitur ini memungkinkan Anda memberikan akses hardware fisik murni (*Direct Access*) ke dalam Virtual Machine. Sangat diidamkan untuk VM *Machine Learning* AI (NVIDIA GPU Passthrough) atau NAS (HBA Passthrough untuk TrueNAS).

**Langkah Mengaktifkan IOMMU:**
```bash
# Edit GRUB
nano /etc/default/grub

# Tambahkan parameter intel_iommu=on (atau amd_iommu=on) di baris GRUB_CMDLINE_LINUX_DEFAULT
# Contoh: GRUB_CMDLINE_LINUX_DEFAULT="quiet intel_iommu=on iommu=pt"
update-grub

# Tambahkan modul kernel passthrough
echo -e "vfio\nvfio_iommu_type1\nvfio_pci\nvfio_virqfd" >> /etc/modules

# Update kernel dan Reboot
update-initramfs -u -k all
reboot
```
Setelah aktif, Anda bisa masuk ke setting VM → Hardware → Add PCI Device → Pilih GPU/Hardware fisik Anda.

### 16.3 Proxmox Backup Server (PBS)

Skrip dan metode standar menggunakan `vzdump` memiliki kelemahan: ia mencetak file *.tar* utuh secara manual. Untuk lingkungan profesional berskala besar, Proxmox memiliki produk terpisah berlogo hijau: **Proxmox Backup Server**.

**Keunggulan Utama PBS:**
- **Deduplikasi Tingkat Blok**: Menghemat ratusan Gigabyte karena blok data yang sama dari berbagai VM hanya disimpan 1 kali secara fisik.
- **Incremental Backup Sejati**: Setelah proses backup penuh pertama kali, backup selanjutnya hanya menyimpan blok data *yang berubah* saja (hanya hitungan detik/menit).
- **Ransomware Protection**: Mendukung *Tape Backup* tingkat lanjut dan enkripsi penuh.
- PBS biasanya disematkan ke *bare-metal* server terpisah dari cluster Proxmox VE (PVE).

### 16.4 Cloud-Init & Otomatisasi VM

Bagi *cloud-engineer*, melakukan klik *"next-next"* saat mengamankan instalasi ISO Ubuntu sungguh memakan waktu. **Cloud-Init** memungkinkan Anda me-*deploy* puluhan VM kosong jadi langsung menyala, dengan user, IP Statis, dan *SSH Keys* yang sudah terinjeksi dari luar.

**Cara Memanfaatkan Cloud-Init di Proxmox:**
1. Download image Ubuntu/Debian versi *Cloud* (`.img`, bukan `.iso`).
2. Buat VM baru tanpa media hardisk (`qm create`).
3. Impor `.img` langsung ke *storage* Proxmox lalu jadikan *hardisk* utama (`qm importdisk`).
4. Tambahkan drive virtual "CloudInit" dari Web GUI secara manual (Hardware → Add → CloudInit Drive).
5. Pada Tab *Cloud-Init*, atur *username*, SSH Public Key, dan IP Address.
6. Saat VM di-start, script kecil di dalam OS akan membaca dari Drive CloudInit Anda dan menjalankan autokonfigurasi secara ajaib!

### 16.5 Infrastructure as Code (IaC) via Terraform & API

Administrator pemula bangga bisa mengklik dengan cepat tombol-tombol antarmuka web (*Web GUI*) demi menelurkan 5 mesin virtual baru. Namun seorang *DevOps Cloud Engineer* sejati di perusahaan multinasional tak akan pernah sudi menyentuh tombol di GUI. Mereka bekerja menggenggam prinsip gaib **Infrastructure as Code (IaC)**.

Alih-alih berletih lelah membangun server manual, Anda mendelegasikan perintah ini kepada perabot industri mutakhir seperti **Terraform** untuk mencambuk *Proxmox API* secara *Back-end*.
- **Skenario Riil**: Anda menyusun barisan kalimat pemrograman pada dokumen teks biasa (`.tf`), mendeklarasikan: *"Hai Terraform, tolong sediakan untuk saya 50 VM Clone dari template Ubuntu, masing-masing injeksikan 4 Core CPU dan 8GB RAM, lalu lempar semuanya ke jalur VLAN-101."*
- Cukup hantam perintah `terraform apply` di terminal Laptop Anda sambil menyeruput secangkir kopi. Terraform akan memerintah API Proxmox tanpa henti untuk meng-kloning, meracik jaringan, hingga mem-booting keseluruhan 50 VM Anda serentak dari udara kosong hanya dalam hitungan detik.
- Apabila terjadi kelumpuhan infrastruktur global, Anda sama sekali tidak panik. Karena Anda punya *blueprint kode* aslinya, Anda sisa menekan Enter lagi, dan keseluruhan ekosistem server terbangun identik dari nol.

Proxmox sudah menerima restu dan di-_backing_ resmi oleh pemelihara Terraform dunia (seperti *Telmate Proxmox Provider* atau *Ansible Proxmox Modules*). Kemampuan mentraslasikan klik Proxmox menjadi ketikan skrip inilah yang akan mengangkat profil gaji Anda ke tataran teknisi arsitektur puluhan juta rupiah.

### 16.6 Akses Mentah: Raw Disk & USB Passthrough

Di samping eksotisme GPU Passthrough (Bab 16.2), skenario operasional *Smart-Home* (seperti platform Home Assistant) atau ekosistem *NAS* terdedikasi (TrueNAS) acapkali mewajibkan jalur pintas murni ke *hardware*.
- **Raw Disk Passthrough**: Tinimbang mem-format *hardisk* 4TB baru menjadi lapisan partisi abstraksi VM (*ZFS/LVM*), Anda bisa mendepak *hardisk* fisik seutuhnya menabrak masuk ke dimensi OS VM (*block-level access*).
  - Tentukan persis ID Disk fisik Anda (dilarang keras memakai alias seperti `/dev/sda` yang bisa berubah saat *reboot*): `ls -l /dev/disk/by-id/`
  - Tembakkan ia ke jantung VM via CLI: `qm set 100 -scsi1 /dev/disk/by-id/ata-ST4000VN008-2DR...`
- **USB Passthrough**: Esensial sewaktu VM Home Assistant menuntut sinkronisasi antena radio *USB Zigbee/Bluetooth* fisik yang menduduki port eksterior server Anda. Tinggal raih via *Hardware → Add → USB Device → Set ke 'Use USB Vendor/Device ID'*.

*(Peringatan: Seluruh partisi raw-disk yang di-passthrough dilarang untuk ikut diotomatisasi pada siklus backup).*

### 16.7 Nested Virtualization (Menjalankan Proxmox di dalam Proxmox)

Sangat lazim tatkala pakar IT hendak membina kurikulum tanpa tega membakar bujet untuk *hardware* baru yang mahal. **Nested Virtualization** mengistimewakan Anda untuk menetaskan *Hypervisor* (induk seperti Proxmox atau VMware ESXi) menumpang hidup subur di dalam VM Proxmox Anda!
1. Inspek pertama kalinya jika keran saklar fitur ini secara bawaan telah terbuka pada *kernel host*: `cat /sys/module/kvm_intel/parameters/nested` (valid jika mereturnasikan karakter **Y** atau **1**).
2. Jika ia bisu (N/0), hidupkan paksa di akar kernel OS Linux induknya: `echo "options kvm-intel nested=Y" > /etc/modprobe.d/kvm-intel.conf` diikuti me-*reload* modul `modprobe kvm_intel`.
3. Menjelang kreasi penciptaan wujud VM Proxmox virtualnya pada antarmuka Web, tukar spesifikasi mutlak **CPU Type** dari *kvm64/default* beralih menjadi jenis rujukan **host**.
4. Ajaib! Segala rantai instruksi *VT-x Hardware* dari mainboard fisik tembus tanpa tersumbat merasuk ke inti CPU sang OS "cucu", mengkaderkannya siap mencetak ribuan VM level turunan ke-3.

---

## 17. Troubleshooting Umum

### 17.1 VM Tidak Bisa Start

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

### 17.2 Web UI Tidak Bisa Diakses

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

### 17.3 Storage Penuh

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

### 17.4 Node Keluar dari Cluster

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

### 17.5 High CPU Load

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

### 17.6 Kejadian Tak Terduga: VM Terkunci (Locked VM)

**Skenario**: Anda mencoba *Start*, *Stop*, atau menghapus VM, tetapi Proxmox menampilkan error kemerahan berbunyi: `VM is locked (backup/migrate/snapshot/clone)`.
**Penyebab**: Proses (seperti Backup semalam atau *Clone*) terputus paksa di tengah jalan sehingga file *lock* / kunci tidak sempat dihapus oleh sistem.

**Solusi Resmi**:
Langkah paling aman menurut pedoman resmi adalah melepaskan kuncinya menggunakan `qm` atau `pct`.
```bash
# Untuk mesin virtual (KVM)
qm unlock <VMID>
# Contoh: qm unlock 100

# Untuk Container (LXC)
pct unlock <CTID>
```
*Catatan:* Sebelum melakukan ini, pastikan memang tidak ada proses *vzdump* (backup) atau migrasi yang *benar-benar* masih berjalan di *background*.

### 17.7 Kejadian Tak Terduga: Cluster Quorum Hilang (Split-Brain)

**Skenario**: Anda memiliki 3 server di cluster. Tiba-tiba kabel jaringan putus atau switch mati yang menyebabkan 2 server *offline*. Anda login ke server ke-3 yang tersisa, tetapi Anda tidak bisa mengedit apapun, tidak bisa start VM, icon di GUI muncul tanda tanya (?) abu-abu, dan terbaca *Read-Only*.
**Penyebab**: Sistem *Quorum* Proxmox mencegah satu node bertindak sendiri saat tersolasi untuk menghindari korupsi data (*Split-Brain protection*). Node butuh "suara mayoritas" agar bisa mengubah konfigurasi.

**Solusi Darurat**:
Anda bisa melemahkan hukum mayoritas ini (secara sementara) agar server yang tersisa bisa kembali dioperasikan secara normal (bisa Read/Write).
```bash
# Beritahu Proxmox bahwa mulai sekarang, "1 node" saja sudah cukup dianggap sebagai kourum (mayoritas)
pvecm expected 1
```
*(Perhatian: Hanya lakukan ini jika Anda yakin bahwa node lain memang benar-benar mati dan VM-nya tidak sedang menyala memperebutkan storage disk yang sama.)*

### 17.8 Kejadian Tak Terduga: Tiba-tiba VM Mati / Hilang (OOM Killer)

**Skenario**: Beberapa VM Anda sering mati mendadak pada jam-jam sibuk. Tidak ada catatan *error* di GUI, tiba-tiba VM stop saja.
**Penyebab**: Terjadi *Out-Of-Memory* (OOM). Ketika sisa RAM fisik Proxmox benar-benar menyentuh angka 0, *kernel* Linux memiliki sang algojo (*OOM Killer*) yang akan menembak mati proses yang paling rakus RAM secara membabi-buta demi menyelamatkan OS Proxmox agar tidak *crash*. Seringkali korbannya adalah proses `qemu-server` (VM Anda).

**Solusi Investigasi**:
```bash
# Cek catatan pembunuhan oleh algojo (OOM Killer)
dmesg -T | grep -i oom
```
Solusi kuratifnya: Anda harus membatasi batas ZFS ARC (lihat Bab 16.1), mengurangi jumlah alokasi (overcommit) RAM VM, atau segera beli keping RAM fisik tambahan.

### 17.9 Kejadian Tak Terduga: Lupa Password VM / Container

**Skenario**: Anda lama tidak membuka sebuah *Virtual Machine* atau *Container* dan benar-benar lupa *password* root atau admin utamanya.

**Solusi 1: Untuk Container (LXC)**
Ini adalah keuntungan menggunakan LXC. Karena LXC berbagi *kernel* dengan Proxmox, superadmin Proxmox memiliki "kunci master" untuk menerobos masuk tanpa *password* sama sekali.
```bash
# 1. Dari terminal Proxmox, paksa masuk ke dalam CT sebagai root
pct enter <CTID>   # Contoh: pct enter 200

# 2. Sekarang Anda berada di dalam sistem tersebut! Langsung ganti passwordnya
passwd root

# 3. Masukkan password baru 2x. Keluar dengan mengetik "exit". Selesai!
```

**Solusi 2: Untuk Virtual Machine Linux (KVM)**
Berbeda dengan LXC, mesin KVM diisolasi penuh. Proxmox tidak bisa asal menembus dindingnya. Anda harus menggunakan jurus peretasan *GRUB Bootloader*.
1. Buka halaman **Console** VM tersebut.
2. *Reboot* mesinnya, dan saat layar **GRUB** (pemilihan OS) muncul, cepat tekan tombol **ESC** atau **E** di keyboard agar ia menjeda (tidak langsung masuk OS).
3. Cari baris yang berawalan kata `linux` atau `linux16`.
4. Di ujung baris tersebut, ketikkan spasi lalu tambahkan `rw init=/bin/bash`
5. Tekan **Ctrl + X** atau **F10** untuk melanjutkan *boot*.
6. VM akan mem-buka terminal berlatar hitam secara ajaib tanpa meminta password (akses level kernel murni)!
7. Ketik `passwd`, ganti password Anda, lalu paksa *restart* mesin tersebut.

**Solusi 3: Untuk Virtual Machine Windows (KVM)**
Jika VM Anda berisi OS Windows:
1. Pasang/Mount ISO installer Windows di CD/DVD Drive VM tersebut.
2. Matikan paksa VM, ubah *Boot Order* agar booting dari CD-ROM.
3. Saat masuk layar instalasi Windows, tekan **Shift + F10** (Terminal CMD akan terbuka).
4. Gunakan trik memanipulasi `Utilman.exe` milik Windows yang legendaris, kembalikan *Boot Order* ke *Hardisk*, dan saat berada di layar login Windows, Anda bisa menggunakan terminal darurat berhak administrator untuk `net user Administrator passwordBaru`!

### 17.10 Kejadian Tak Terduga: Lupa Password Root Induk Proxmox Sendiri

**Skenario**: Mimpi buruk terburuk! Server menyala, tapi Anda lupa *password* akses `root` ke Web GUI / Terminal server Proxmox Anda sendiri.
**Penyebab**: Terlalu banyak memegang akun atau administrator lama baru saja ditiadakan.

**Solusi Darurat**:
Skenario ini mewajibkan Anda hadir di depan server fisik (atau menggunakan fasilitas iLO / iDRAC / IPMI KVM dari Data Center).
1. Sambungkan Keyboard dan Monitor ke mesin fisik Proxmox Anda.
2. *Restart* paksa server secara fisik.
3. Saat *Blue Screen GRUB* bertuliskan **Proxmox Virtual Environment GNU/Linux** muncul, buru-buru tekan tombol **E** untuk mengedit instruksi *booting*.
4. Gulir ke bawah hingga menemukan baris yang dimulai dengan kata kunci `linux`.
5. Di akhir persis baris tersebut, tambahkan teks: `init=/bin/bash`
6. Lalu tekan **F10** untuk menyalakan ulang.
7. Anda akan dihadapkan pada terminal berhak super-user. Ketikkan:
   ```bash
   # Remount ulang disk agar bisa ditulis
   mount -o remount,rw /
   
   # Paksa reset password yang lama!
   passwd root
   
   # Simpan perubahan dan reboot
   exec /sbin/init
   ```
Sekarang Anda bisa kembali login ke GUI portal 8006 kesayangan Anda!

---

## 18. Referensi & Panduan Lanjutan

### 18.1 Dokumentasi Resmi

- **Proxmox VE Docs**: <https://pve.proxmox.com/pve-docs/>
- **Proxmox Wiki**: <https://pve.proxmox.com/wiki/Main_Page>
- **Proxmox Forum**: <https://forum.proxmox.com/>
- **Proxmox API**: <https://pve.proxmox.com/pve-docs/api-viewer/>

### 18.2 Perintah CLI Penting — Quick Reference

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
