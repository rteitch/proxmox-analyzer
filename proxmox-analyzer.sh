#!/bin/bash
# =============================================================================
# PROXMOX RESOURCE ANALYZER v4.2 — Enterprise Edition
# Analisis komprehensif CPU, RAM, Storage, Network, VM/CT, Backup, Cluster
#
# Penggunaan:
#   bash proxmox-analyzer.sh                      → Tampilkan semua info
#   bash proxmox-analyzer.sh --alert-only          → Hanya tampilkan masalah/peringatan
#   bash proxmox-analyzer.sh --no-color            → Output tanpa warna (untuk log file)
#   bash proxmox-analyzer.sh --name="PVE-Utama"   → Beri nama kustom node ini
#   NODE_LABEL="PVE-Backup" bash proxmox-analyzer.sh → Nama via environment variable
#
# Deploy & Jalankan Otomatis via Cronjob:
#   chmod +x proxmox-analyzer.sh
#   cp proxmox-analyzer.sh /root/scripts/
#   crontab -e
#   → 0 */6 * * * /root/scripts/proxmox-analyzer.sh --no-color >> /var/log/pve-analyzer.log 2>&1
#
# Estimasi Runtime:
#   Normal (tanpa RAID)          : ~8-12 detik
#   Dengan RAID controller       : ~15-25 detik (scan per disk fisik)
#   Tanpa iostat (pakai /proc)   : ~6-8  detik
#   Catatan: Ada beberapa sleep/sample interval yang diperlukan untuk
#   mendapatkan data CPU, IOWait, dan Network yang akurat.
#   Script ini TIDAK mempengaruhi konfigurasi sistem sama sekali.
#
# Changelog v4.2:
#   [FIX] SMART: Auto-detect disk via smartctl --scan (MegaRAID, 3ware, cciss)
#   [FIX] SMART: RAID virtual disk ditandai info, bukan false-alarm kritis
#   [FIX] SMART: Health status multi-line parsing (PASSED\ncheck.)
#   [FIX] SMART: Octal error pada attribute value berawalan 0 (099)
#   [FIX] SMART: Suhu parsing kompatibel SATA/SAS/NVMe
#   [FIX] Backup: Expanded OK pattern (Finished Backup of VM, archive file size)
#   [FIX] VM/CT: Format string %-10s pada status (echo→printf)
#   [FIX] Network: Format string %8d pada error packet (echo→printf)
#   [NEW] SMART: Serial Number, SAS Grown Defects, SSD auto-detection
#   [NEW] SMART: Dukungan MegaRAID, 3ware, cciss, Areca, HP SmartArray
#
# Changelog v4.0:
#   [FIX] IOWait detection: grep-based, tidak lagi hardcode NR==7
#   [FIX] pvecm status di-cache sekali, tidak dipanggil berulang
#   [FIX] progress_bar() threshold kini parameterizable (tidak hardcode CPU)
#   [FIX] Backup error detection pakai pattern spesifik, kurangi false positive
#   [FIX] smartctl dibungkus timeout() agar tidak freeze jika disk bermasalah
#   [FIX] Eliminasi loop df() duplikat di evaluasi summary
#   [NEW] CPU Steal Time (deteksi CPU overcommit / nested virtualization)
#   [NEW] Resource usage aktual per-VM dan per-Container
#   [NEW] pvesm status — semua Proxmox Storage Pool (NFS, iSCSI, LVM-thin, dll)
#   [NEW] Network: error packet, drop packet, throughput realtime per interface
#   [NEW] SMART critical attributes (Reallocated Sectors, Pending, Wear Level)
#   [NEW] Disk temperature threshold + alert
#   [NEW] dmesg kernel error & hardware error (24 jam terakhir)
#   [NEW] OOM Kill event detection (Out of Memory killer)
#   [NEW] Proxmox Task History — failed tasks via pvesh
#   [NEW] HA (High Availability) status via ha-manager
#   [NEW] --no-color flag untuk output log file
# =============================================================================

# ─── WARNA ───────────────────────────────────────────────────────────────────
setup_colors() {
  if [[ "$NO_COLOR" == true ]] || [[ ! -t 1 && "$FORCE_COLOR" != true ]]; then
    RED=''; YELLOW=''; GREEN=''; CYAN=''; BLUE=''; MAGENTA=''; BOLD=''; NC=''
  else
    RED='\033[0;31m'
    YELLOW='\033[1;33m'
    GREEN='\033[0;32m'
    CYAN='\033[0;36m'
    BLUE='\033[0;34m'
    MAGENTA='\033[0;35m'
    BOLD='\033[1m'
    NC='\033[0m'
  fi
}

# ─── THRESHOLD (Ambang Batas) — Sesuaikan sesuai kebutuhan ──────────────────
CPU_WARNING=70
CPU_CRITICAL=90
CPU_STEAL_WARNING=5      # % CPU steal (indikasi overcommit)
CPU_STEAL_CRITICAL=15
RAM_WARNING=80
RAM_CRITICAL=95
STORAGE_WARNING=75
STORAGE_CRITICAL=90
LOAD_WARNING=0.8
LOAD_CRITICAL=1.0
IOWAIT_WARNING=20        # % IOWait aman < 20%
IOWAIT_CRITICAL=40       # % IOWait kritis > 40%
SWAP_WARNING=30          # % swap warning
SWAP_CRITICAL=70         # % swap kritis
DISK_TEMP_WARNING=45     # °C suhu disk
DISK_TEMP_CRITICAL=55    # °C suhu disk kritis
NET_ERROR_WARNING=100    # jumlah error packet per interface
SMART_REALLOCATED_WARN=1 # Reallocated Sectors > 0 sudah warning

# ─── PARSE ARGUMEN ────────────────────────────────────────────────────────────
ALERT_ONLY=false
NO_COLOR=false
FORCE_COLOR=false
NODE_LABEL="${NODE_LABEL:-}"   # Bisa di-set via env: NODE_LABEL="PVE-Utama" bash proxmox-analyzer.sh
for arg in "$@"; do
  [[ "$arg" == "--alert-only" ]] && ALERT_ONLY=true
  [[ "$arg" == "--no-color"   ]] && NO_COLOR=true
  [[ "$arg" == "--color"      ]] && FORCE_COLOR=true
  [[ "$arg" == --name=* ]]       && NODE_LABEL="${arg#--name=}"
done

setup_colors

# =============================================================================
# PRE-CHECK: DEPENDENSI OTOMATIS
# =============================================================================
MISSING_DEPS=()

check_deps() {
  # bc — WAJIB untuk semua kalkulasi desimal
  if ! command -v bc &>/dev/null; then
    MISSING_DEPS+=("bc")
    echo -e "${RED}${BOLD}[FATAL] 'bc' tidak terinstall. Script tidak dapat menghitung persentase.${NC}"
    echo -e "${RED}  Jalankan: apt install -y bc${NC}"
    exit 127
  fi

  # sysstat — untuk iostat (IOWait analysis)
  command -v iostat &>/dev/null    || MISSING_DEPS+=("sysstat")
  # smartmontools — untuk disk health
  command -v smartctl &>/dev/null  || MISSING_DEPS+=("smartmontools")

  if [[ ${#MISSING_DEPS[@]} -gt 0 ]]; then
    echo -e "${YELLOW}${BOLD}⚠ DEPENDENSI OPSIONAL TIDAK LENGKAP:${NC}"
    echo -e "${YELLOW}  Package berikut tidak terinstall: ${MISSING_DEPS[*]}${NC}"
    echo -e "${YELLOW}  Beberapa fitur terkait tidak akan berjalan, fitur lainnya tetap normal.${NC}"
    echo -e "${CYAN}  Saran install (tidak dieksekusi otomatis): apt install -y ${MISSING_DEPS[*]}${NC}"
    echo ""
  fi
}

check_deps

# =============================================================================
# FUNGSI HELPER
# =============================================================================

print_header() {
  local title="$1"
  local width=64
  echo -e "\n${BLUE}${BOLD}╔$(printf '═%.0s' $(seq 1 $width))╗${NC}"
  printf "${BLUE}${BOLD}║  %-${width}s║${NC}\n" "$title"
  echo -e "${BLUE}${BOLD}╚$(printf '═%.0s' $(seq 1 $width))╝${NC}"
}

print_section() {
  echo -e "\n${CYAN}${BOLD}▶ $1${NC}"
  echo -e "${CYAN}$(printf '─%.0s' {1..66})${NC}"
}

print_subsection() {
  echo -e "\n  ${MAGENTA}${BOLD}◆ $1${NC}"
}

# BUG #3 FIX: progress_bar kini menerima warn/crit sebagai parameter
progress_bar() {
  local percent=${1:-0}
  local warn=${2:-$CPU_WARNING}
  local crit=${3:-$CPU_CRITICAL}
  local width=40
  local filled
  filled=$(echo "scale=0; $percent * $width / 100" | bc 2>/dev/null || echo 0)
  local empty=$(( width - filled ))
  local bar=""
  for ((i=0; i<filled; i++)); do bar="${bar}█"; done
  for ((i=0; i<empty; i++)); do bar="${bar}░"; done

  if (( $(echo "$percent >= $crit" | bc -l 2>/dev/null || echo 0) )); then
    echo -e "${RED}[${bar}] ${percent}%${NC}"
  elif (( $(echo "$percent >= $warn" | bc -l 2>/dev/null || echo 0) )); then
    echo -e "${YELLOW}[${bar}] ${percent}%${NC}"
  else
    echo -e "${GREEN}[${bar}] ${percent}%${NC}"
  fi
}

status_label() {
  local value=$1 warn=$2 crit=$3
  if (( $(echo "$value >= $crit" | bc -l 2>/dev/null || echo 0) )); then
    echo -e "${RED}[KRITIS]${NC}"
  elif (( $(echo "$value >= $warn" | bc -l 2>/dev/null || echo 0) )); then
    echo -e "${YELLOW}[PERINGATAN]${NC}"
  else
    echo -e "${GREEN}[NORMAL]${NC}"
  fi
}

# Fungsi safe timeout wrapper
safe_run() {
  local timeout_sec=${1}; shift
  timeout "$timeout_sec" "$@" 2>/dev/null
}

# ─── HEADER ─────────────────────────────────────────────────────────────────
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
HOSTNAME_SHORT=$(hostname)
HOSTNAME_FULL=$(hostname -f 2>/dev/null || hostname)
PVE_VERSION=$(pveversion 2>/dev/null | head -1 || echo 'N/A')
KERNEL_VER=$(uname -r)
UPTIME_STR=$(uptime -p 2>/dev/null || uptime | awk -F'up ' '{print $2}' | awk -F', load' '{print $1}')

# Jika NODE_LABEL tidak di-set, fallback ke hostname
[[ -z "$NODE_LABEL" ]] && NODE_LABEL="$HOSTNAME_FULL"

print_header "PROXMOX ANALYZER v4.0 — ${NODE_LABEL}"
echo -e "  ${BOLD}Node Label     :${NC} ${MAGENTA}${BOLD}${NODE_LABEL}${NC}"
echo -e "  ${BOLD}Hostname       :${NC} ${HOSTNAME_FULL}"
echo -e "  ${BOLD}Waktu Analisis :${NC} ${TIMESTAMP}"
echo -e "  ${BOLD}Versi PVE      :${NC} ${PVE_VERSION}"
echo -e "  ${BOLD}Kernel         :${NC} ${KERNEL_VER}"
echo -e "  ${BOLD}Uptime         :${NC} ${UPTIME_STR}"
echo -e "  ${BOLD}Dependensi     :${NC} ${#MISSING_DEPS[@]} paket tidak lengkap ($([ ${#MISSING_DEPS[@]} -eq 0 ] && echo "${GREEN}Semua OK${NC}" || echo "${YELLOW}${MISSING_DEPS[*]}${NC}"))"

# =============================================================================
# CACHE DATA AWAL (sekali ambil, pakai berkali-kali)
# BUG #2 FIX: pvecm status di-cache sekali
# =============================================================================
PVECM_OUTPUT=""
command -v pvecm &>/dev/null && PVECM_OUTPUT=$(safe_run 5 pvecm status)

DF_OUTPUT=$(df -hP 2>/dev/null)
DF_KB_OUTPUT=$(df -kP 2>/dev/null)

# Cache array evaluasi (BUG #6 FIX: tidak perlu double loop)
ISSUES=()
WARNINGS=()
OK_LIST=()

# =============================================================================
# BAGIAN 1: CPU ANALYSIS
# =============================================================================
if [[ "$ALERT_ONLY" == true ]]; then
  exec 3>&1 >/dev/null
fi

print_section "CPU ANALYSIS"

CPU_COUNT=$(nproc)
CPU_MODEL=$(grep "model name" /proc/cpuinfo | head -1 | cut -d: -f2 | xargs 2>/dev/null || echo "N/A")
CPU_SOCKETS=$(grep "physical id" /proc/cpuinfo 2>/dev/null | sort -u | wc -l)
CPU_CORES_PER_SOCKET=$(grep "cpu cores" /proc/cpuinfo 2>/dev/null | head -1 | awk '{print $NF}')
CPU_FREQ=$(grep "cpu MHz" /proc/cpuinfo 2>/dev/null | head -1 | awk '{printf "%.0f MHz", $NF}')
CPU_MAX_FREQ=$(grep "cpu MHz" /proc/cpuinfo 2>/dev/null | awk '{print $NF}' | sort -n | tail -1 | awk '{printf "%.0f MHz", $1}' 2>/dev/null)

# Ambil semua stat CPU + IOWait + Steal sekaligus dari vmstat
# (1 interval, 2 sample = block ~2 detik — ini diperlukan agar nilai akurat, bukan nilai boot)
VMSTAT_OUT=$(vmstat 1 2 2>/dev/null | tail -1)
CPU_US=$(echo "$VMSTAT_OUT" | awk '{print $13}')     # user
CPU_SY=$(echo "$VMSTAT_OUT" | awk '{print $14}')     # system
CPU_IDLE=$(echo "$VMSTAT_OUT" | awk '{print $15}')   # idle
CPU_WA=$(echo "$VMSTAT_OUT" | awk '{print $16}')     # iowait — dipakai ulang di bagian IOWait!
CPU_ST=$(echo "$VMSTAT_OUT" | awk '{print $17}')     # steal time

CPU_USAGE=$(echo "100 - ${CPU_IDLE:-0}" | bc 2>/dev/null || echo "0")
CPU_USAGE=$(printf "%.1f" "$CPU_USAGE" 2>/dev/null || echo "0")
CPU_ST=${CPU_ST:-0}

LOAD_1=$(cut -d' ' -f1 /proc/loadavg)
LOAD_5=$(cut -d' ' -f2 /proc/loadavg)
LOAD_15=$(cut -d' ' -f3 /proc/loadavg)
LOAD_PER_CPU=$(echo "scale=2; $LOAD_1 / $CPU_COUNT" | bc 2>/dev/null || echo "0")

echo -e "  Model CPU     : ${CPU_MODEL}"
echo -e "  Jumlah Core   : ${CPU_COUNT} thread (${CPU_SOCKETS} socket × ${CPU_CORES_PER_SOCKET:-?} core/socket)"
echo -e "  Frekuensi     : ${CPU_FREQ} (maks: ${CPU_MAX_FREQ:-N/A})"
echo ""
echo -ne "  Penggunaan CPU: "
progress_bar "$CPU_USAGE" "$CPU_WARNING" "$CPU_CRITICAL"
echo -e "  Status CPU    : $(status_label "$CPU_USAGE" "$CPU_WARNING" "$CPU_CRITICAL")"
echo -e "  Breakdown     : User=${CPU_US}%  System=${CPU_SY}%  Idle=${CPU_IDLE}%  IOWait=${CPU_WA}%  Steal=${CPU_ST}%"
echo ""

# CPU Steal Time — NEW v4.0
if (( $(echo "${CPU_ST:-0} >= $CPU_STEAL_CRITICAL" | bc -l 2>/dev/null || echo 0) )); then
  echo -e "  CPU Steal     : ${RED}[KRITIS] ${CPU_ST}% — CPU banyak dicuri! Kemungkinan overcommit parah.${NC}"
  ISSUES+=("CPU Steal ${CPU_ST}% — KRITIS! Proxmox host mungkin berjalan di atas VM lain atau CPU overcommit parah")
elif (( $(echo "${CPU_ST:-0} >= $CPU_STEAL_WARNING" | bc -l 2>/dev/null || echo 0) )); then
  echo -e "  CPU Steal     : ${YELLOW}[PERINGATAN] ${CPU_ST}% — Ada CPU yang dicuri hypervisor/host${NC}"
  WARNINGS+=("CPU Steal ${CPU_ST}% — Ada indikasi overcommit atau nested virtualization")
else
  echo -e "  CPU Steal     : ${GREEN}[NORMAL] ${CPU_ST}%${NC}"
  OK_LIST+=("CPU Steal ${CPU_ST}% — Normal (tidak ada overcommit)")
fi

echo ""
echo -e "  Load Average  : ${LOAD_1} (1m) | ${LOAD_5} (5m) | ${LOAD_15} (15m)"
echo -e "  Load per Core : ${LOAD_PER_CPU} (batas aman < ${LOAD_WARNING})"

if (( $(echo "$LOAD_PER_CPU >= $LOAD_CRITICAL" | bc -l 2>/dev/null || echo 0) )); then
  echo -e "  Status Load   : ${RED}[KRITIS] Server overloaded!${NC}"
  ISSUES+=("Load ${LOAD_1} (${LOAD_PER_CPU}/core) — KRITIS! Server kelebihan beban")
elif (( $(echo "$LOAD_PER_CPU >= $LOAD_WARNING" | bc -l 2>/dev/null || echo 0) )); then
  echo -e "  Status Load   : ${YELLOW}[PERINGATAN] Load mulai tinggi${NC}"
  WARNINGS+=("Load ${LOAD_1} (${LOAD_PER_CPU}/core) — Perlu diperhatikan")
else
  echo -e "  Status Load   : ${GREEN}[NORMAL]${NC}"
  OK_LIST+=("Load Average ${LOAD_1} — Normal")
fi

if (( $(echo "$CPU_USAGE >= $CPU_CRITICAL" | bc -l 2>/dev/null || echo 0) )); then
  ISSUES+=("CPU ${CPU_USAGE}% — KRITIS! Identifikasi proses berat dan pertimbangkan scale-up")
elif (( $(echo "$CPU_USAGE >= $CPU_WARNING" | bc -l 2>/dev/null || echo 0) )); then
  WARNINGS+=("CPU ${CPU_USAGE}% — Tinggi. Monitor dan pertimbangkan penambahan core")
else
  OK_LIST+=("CPU ${CPU_USAGE}% — Normal")
fi

if [[ "$ALERT_ONLY" == false ]]; then
  echo -e "\n  ${BOLD}Top 5 Proses (CPU):${NC}"
  ps aux --sort=-%cpu 2>/dev/null | awk 'NR>1 && NR<=6 {
    printf "    %-10s %-28s CPU: %5s%%  MEM: %5s%%\n", $1, substr($11,1,28), $3, $4
  }'
fi

# =============================================================================
# BAGIAN 2: I/O WAIT ANALYSIS
# =============================================================================
print_section "I/O WAIT ANALYSIS"

# BUG #1 FIX: gunakan grep-based bukan NR==7 hardcode
# OPTIMASI: jika iostat tersedia, ambil data lebih akurat.
# Jika tidak, gunakan CPU_WA dari vmstat yang sudah diambil di Bagian 1
# (tidak perlu sleep/sample lagi = hemat ~2 detik)
IOWAIT_VAL="N/A"

# Coba ambil dari vmstat terlebih dahulu (data sudah ada, gratis)
if [[ -n "$CPU_WA" ]] && [[ "$CPU_WA" =~ ^[0-9] ]]; then
  IOWAIT_VAL="$CPU_WA"
fi

# Override dengan iostat jika tersedia (lebih presisi, tapi tambah ~2 detik)
if command -v iostat &>/dev/null; then
  # Ambil baris data CPU dari iostat (skip baris kosong, header, info Linux)
  # Hanya 1 interval 1 detik — sudah cukup karena vmstat tadi sudah 2 detik
  IOSTAT_RAW=$(safe_run 5 iostat -c 1 1 2>/dev/null)
  IOSTAT_VAL=$(echo "$IOSTAT_RAW" | grep -v '^$' | grep -v 'avg-cpu\|%user\|Linux\|Device' | tail -1 | awk '{print $4}')

  # Validasi, fallback ke baris numerik terakhir
  if [[ -z "$IOSTAT_VAL" ]] || ! [[ "$IOSTAT_VAL" =~ ^[0-9] ]]; then
    IOSTAT_VAL=$(echo "$IOSTAT_RAW" | grep -E '^[[:space:]]*[0-9]' | tail -1 | awk '{print $4}')
  fi

  # Hanya pakai jika valid
  if [[ -n "$IOSTAT_VAL" ]] && [[ "$IOSTAT_VAL" =~ ^[0-9] ]]; then
    IOWAIT_VAL="$IOSTAT_VAL"
  fi
fi

if [[ -n "$IOWAIT_VAL" ]] && [[ "$IOWAIT_VAL" =~ ^[0-9] ]]; then
  if (( $(echo "$IOWAIT_VAL >= $IOWAIT_CRITICAL" | bc -l 2>/dev/null || echo 0) )); then
    echo -e "  %IOWait       : ${RED}${IOWAIT_VAL}%${NC}  (kritis > ${IOWAIT_CRITICAL}%)"
    echo -e "  Status        : ${RED}[KRITIS] Storage menjadi bottleneck! VM mungkin terasa lag.${NC}"
    ISSUES+=("IOWait ${IOWAIT_VAL}% — KRITIS! Storage bottleneck. Cek: iostat -x 1 5")
  elif (( $(echo "$IOWAIT_VAL >= $IOWAIT_WARNING" | bc -l 2>/dev/null || echo 0) )); then
    echo -e "  %IOWait       : ${YELLOW}${IOWAIT_VAL}%${NC}  (warning > ${IOWAIT_WARNING}%)"
    echo -e "  Status        : ${YELLOW}[PERINGATAN] I/O Wait mulai tinggi${NC}"
    WARNINGS+=("IOWait ${IOWAIT_VAL}% — Tinggi. Cek: iostat -x 1 5")
  else
    echo -e "  %IOWait       : ${GREEN}${IOWAIT_VAL}%${NC}  (aman < ${IOWAIT_WARNING}%)"
    echo -e "  Status        : ${GREEN}[NORMAL]${NC}"
    OK_LIST+=("IOWait ${IOWAIT_VAL}% — Normal (storage tidak bottleneck)")
  fi

  # Per-device I/O stats — 1 sample 1 detik (lebih efisien dari -c 1 2)
  if command -v iostat &>/dev/null && [[ "$ALERT_ONLY" == false ]]; then
    echo -e "\n  ${BOLD}I/O Per Device (1 sampel):${NC}"
    printf "  %-12s %8s %8s %8s %8s\n" "Device" "r/s" "w/s" "rMB/s" "wMB/s"
    echo -e "  $(printf '─%.0s' {1..52})"
    safe_run 5 iostat -dx 1 1 2>/dev/null | awk 'NF>=14 && /^[a-z]/ {
      printf "  %-12s %8.1f %8.1f %8.2f %8.2f\n", $1, $4, $5, $6/1024, $7/1024
    }' 2>/dev/null | head -10
  fi
else
  echo -e "  ${YELLOW}Tidak dapat membaca nilai IOWait (install sysstat: apt install -y sysstat).${NC}"
  IOWAIT_VAL="N/A"
fi

# =============================================================================
# BAGIAN 3: RAM ANALYSIS
# =============================================================================
print_section "RAM ANALYSIS"

TOTAL_RAM=$(free -m | awk '/^Mem:/ {print $2}')
USED_RAM=$(free -m | awk '/^Mem:/ {print $3}')
FREE_RAM=$(free -m | awk '/^Mem:/ {print $4}')
AVAILABLE_RAM=$(free -m | awk '/^Mem:/ {print $7}')
BUFF_CACHE=$(free -m | awk '/^Mem:/ {print $6}')
SWAP_TOTAL=$(free -m | awk '/^Swap:/ {print $2}')
SWAP_USED=$(free -m | awk '/^Swap:/ {print $3}')

RAM_PERCENT=$(echo "scale=1; $USED_RAM * 100 / $TOTAL_RAM" | bc 2>/dev/null || echo "0")

TOTAL_RAM_GB=$(echo "scale=2; $TOTAL_RAM / 1024" | bc)
USED_RAM_GB=$(echo "scale=2; $USED_RAM / 1024" | bc)
AVAIL_RAM_GB=$(echo "scale=2; $AVAILABLE_RAM / 1024" | bc)
BUFF_CACHE_GB=$(echo "scale=2; $BUFF_CACHE / 1024" | bc)
SWAP_TOTAL_GB=$(echo "scale=2; $SWAP_TOTAL / 1024" | bc)
SWAP_USED_GB=$(echo "scale=2; $SWAP_USED / 1024" | bc)

echo -e "  Total RAM     : ${TOTAL_RAM_GB} GB"
echo -e "  Terpakai      : ${USED_RAM_GB} GB"
echo -e "  Tersedia      : ${AVAIL_RAM_GB} GB  ${CYAN}← angka ini yang penting, bukan 'used'${NC}"
echo -e "  Buffer/Cache  : ${BUFF_CACHE_GB} GB  ${CYAN}← dipakai OS sebagai cache, dilepas jika perlu${NC}"
echo ""
echo -ne "  Penggunaan RAM: "
progress_bar "$RAM_PERCENT" "$RAM_WARNING" "$RAM_CRITICAL"
echo -e "  Status RAM    : $(status_label "$RAM_PERCENT" "$RAM_WARNING" "$RAM_CRITICAL")"

if (( $(echo "$RAM_PERCENT >= $RAM_CRITICAL" | bc -l 2>/dev/null || echo 0) )); then
  ISSUES+=("RAM ${RAM_PERCENT}% — KRITIS! Tambah RAM atau kurangi jumlah VM segera")
elif (( $(echo "$RAM_PERCENT >= $RAM_WARNING" | bc -l 2>/dev/null || echo 0) )); then
  WARNINGS+=("RAM ${RAM_PERCENT}% — Tinggi. Pertimbangkan penambahan RAM")
else
  OK_LIST+=("RAM ${RAM_PERCENT}% — Normal")
fi

# Swap
echo ""
echo -e "  Swap Total    : ${SWAP_TOTAL_GB} GB | Terpakai: ${SWAP_USED_GB} GB"
if [[ "$SWAP_TOTAL" -gt 0 ]]; then
  SWAP_PERCENT=$(echo "scale=1; $SWAP_USED * 100 / $SWAP_TOTAL" | bc 2>/dev/null || echo "0")
  echo -ne "  Swap Usage    : "
  progress_bar "$SWAP_PERCENT" "$SWAP_WARNING" "$SWAP_CRITICAL"
  if (( $(echo "$SWAP_PERCENT >= $SWAP_CRITICAL" | bc -l 2>/dev/null || echo 0) )); then
    echo -e "  ${RED}⚠ Swap kritis! Server sangat kekurangan RAM.${NC}"
    ISSUES+=("Swap ${SWAP_PERCENT}% — KRITIS! Server sangat kekurangan RAM, performa sangat menurun")
  elif (( $(echo "$SWAP_PERCENT >= $SWAP_WARNING" | bc -l 2>/dev/null || echo 0) )); then
    echo -e "  ${YELLOW}⚠ Swap tinggi. RAM mulai kurang.${NC}"
    WARNINGS+=("Swap ${SWAP_PERCENT}% — Tinggi. RAM kurang, server menggunakan disk sebagai memori")
  fi
fi

# KSM
if [[ -f /sys/kernel/mm/ksm/pages_shared ]]; then
  KSM_SHARED=$(cat /sys/kernel/mm/ksm/pages_shared 2>/dev/null || echo 0)
  KSM_SHARING=$(cat /sys/kernel/mm/ksm/pages_sharing 2>/dev/null || echo 0)
  KSM_SAVED_MB=$(echo "scale=1; $KSM_SHARED * 4 / 1024" | bc 2>/dev/null || echo 0)
  echo -e "\n  KSM Dedup     : ${KSM_SAVED_MB} MB dihemat | ${KSM_SHARED} halaman shared | ${KSM_SHARING} halaman sharing"
fi

# Hugepages
HUGEPAGES_TOTAL=$(cat /proc/sys/vm/nr_hugepages 2>/dev/null || echo 0)
HUGEPAGES_FREE=$(grep "HugePages_Free" /proc/meminfo 2>/dev/null | awk '{print $2}')
if [[ "$HUGEPAGES_TOTAL" -gt 0 ]]; then
  echo -e "  HugePages     : Total=${HUGEPAGES_TOTAL} | Free=${HUGEPAGES_FREE:-N/A} (dipakai untuk performa VM)"
fi

# ZFS ARC Cache
ZFS_ARC_FILE="/proc/spl/kstat/zfs/arcstats"
if [[ -f "$ZFS_ARC_FILE" ]]; then
  print_subsection "ZFS ARC Cache"
  ARC_SIZE_BYTES=$(awk '/^size / {print $3}'  "$ZFS_ARC_FILE" 2>/dev/null || echo 0)
  ARC_MAX_BYTES=$(awk '/^c_max / {print $3}'  "$ZFS_ARC_FILE" 2>/dev/null || echo 0)
  ARC_MIN_BYTES=$(awk '/^c_min / {print $3}'  "$ZFS_ARC_FILE" 2>/dev/null || echo 0)
  ARC_HITS=$(awk '/^hits / {print $3}'        "$ZFS_ARC_FILE" 2>/dev/null || echo 0)
  ARC_MISSES=$(awk '/^misses / {print $3}'    "$ZFS_ARC_FILE" 2>/dev/null || echo 0)
  L2_HITS=$(awk '/^l2_hits / {print $3}'      "$ZFS_ARC_FILE" 2>/dev/null || echo 0)
  L2_SIZE=$(awk '/^l2_size / {print $3}'      "$ZFS_ARC_FILE" 2>/dev/null || echo 0)

  ARC_SIZE_GB=$(echo "scale=2; $ARC_SIZE_BYTES / 1073741824" | bc 2>/dev/null || echo "N/A")
  ARC_MAX_GB=$(echo "scale=2; $ARC_MAX_BYTES / 1073741824" | bc 2>/dev/null || echo "N/A")
  ARC_MIN_GB=$(echo "scale=2; $ARC_MIN_BYTES / 1073741824" | bc 2>/dev/null || echo "N/A")

  echo -e "  ${CYAN}ℹ RAM tinggi di Proxmox+ZFS seringkali NORMAL. ZFS ARC pakai RAM sebagai cache."
  echo -e "    ARC otomatis melepas RAM jika VM butuh lebih banyak memori.${NC}"
  echo -e "  ARC Aktif     : ${BOLD}${ARC_SIZE_GB} GB${NC} / max ${ARC_MAX_GB} GB  (min ${ARC_MIN_GB} GB)"

  TOTAL_ARC_OPS=$(echo "$ARC_HITS + $ARC_MISSES" | bc 2>/dev/null || echo 0)
  if [[ "$TOTAL_ARC_OPS" -gt 0 ]]; then
    ARC_HIT_RATE=$(echo "scale=1; $ARC_HITS * 100 / $TOTAL_ARC_OPS" | bc 2>/dev/null)
    if (( $(echo "${ARC_HIT_RATE:-0} < 80" | bc -l 2>/dev/null || echo 0) )); then
      echo -e "  ARC Hit Rate  : ${YELLOW}${ARC_HIT_RATE}%${NC}  (idealnya > 90% — cache kurang efektif, pertimbangkan tambah RAM)"
    else
      echo -e "  ARC Hit Rate  : ${GREEN}${ARC_HIT_RATE}%${NC}  (efisien)"
    fi
  fi

  if [[ "$L2_SIZE" -gt 0 ]]; then
    L2_SIZE_GB=$(echo "scale=2; $L2_SIZE / 1073741824" | bc 2>/dev/null)
    echo -e "  L2ARC (SSD)   : ${L2_SIZE_GB} GB | Hits: ${L2_HITS}"
  fi

  ZFS_ARC_MB=$(echo "scale=0; $ARC_SIZE_BYTES / 1048576" | bc 2>/dev/null || echo 0)
  RAM_MINUS_ARC=$(echo "$USED_RAM - $ZFS_ARC_MB" | bc 2>/dev/null || echo "$USED_RAM")
  RAM_MINUS_ARC_PC=$(echo "scale=1; $RAM_MINUS_ARC * 100 / $TOTAL_RAM" | bc 2>/dev/null)
  RAM_MINUS_ARC_GB=$(echo "scale=2; $RAM_MINUS_ARC / 1024" | bc 2>/dev/null)
  echo -e "  RAM tanpa ARC : ${GREEN}${RAM_MINUS_ARC_GB} GB (${RAM_MINUS_ARC_PC}%)${NC}  ← RAM aktual dipakai VM & OS"
fi

if [[ "$ALERT_ONLY" == false ]]; then
  echo -e "\n  ${BOLD}Top 5 Proses (RAM):${NC}"
  ps aux --sort=-%mem 2>/dev/null | awk 'NR>1 && NR<=6 {
    printf "    %-10s %-28s MEM: %5s%%  CPU: %5s%%\n", $1, substr($11,1,28), $4, $3
  }'
fi

# =============================================================================
# BAGIAN 4: STORAGE ANALYSIS
# =============================================================================
print_section "STORAGE ANALYSIS"

print_subsection "Penggunaan Filesystem"
printf "  %-34s %6s %6s %6s  %s\n" "Mount Point" "Ukuran" "Pakai" "Sisa" "Status"
echo -e "  $(printf '─%.0s' {1..66})"

# BUG #6 FIX: simpan storage issues selama loop, tidak perlu double loop
while read -r device size used avail percent mount; do
  [[ "$mount" == /run*  ]] && continue
  [[ "$mount" == /sys*  ]] && continue
  [[ "$mount" == /proc* ]] && continue
  [[ "$mount" == "/dev" || "$mount" == "/dev/pts" ]] && continue

  PCT_NUM=${percent//%/}
  [[ -z "$PCT_NUM" ]] || ! [[ "$PCT_NUM" =~ ^[0-9]+$ ]] && continue

  if (( PCT_NUM >= STORAGE_CRITICAL )); then
    STATUS="${RED}[KRITIS]    ${NC}"
    ISSUES+=("Storage ${mount} ${percent} — KRITIS! Bersihkan atau ekspansi segera")
  elif (( PCT_NUM >= STORAGE_WARNING )); then
    STATUS="${YELLOW}[PERINGATAN]${NC}"
    WARNINGS+=("Storage ${mount} ${percent} — Tinggi. Rencanakan ekspansi")
  else
    STATUS="${GREEN}[NORMAL]    ${NC}"
  fi

  printf "  %-34s %6s %6s %6s  " "$mount" "$size" "$used" "$avail"
  echo -e "${STATUS} ${percent}"
done < <(echo "$DF_OUTPUT" | grep -v "^tmpfs\|^udev\|^devtmpfs\|^Filesystem")

# Proxmox Storage Pools — NEW v4.0 (G3)
if command -v pvesm &>/dev/null; then
  print_subsection "Proxmox Storage Pools (pvesm)"
  printf "  %-20s %-12s %-10s %-10s %s\n" "Nama" "Tipe" "Total" "Tersedia" "Status"
  echo -e "  $(printf '─%.0s' {1..66})"
  pvesm status 2>/dev/null | tail -n +2 | while read -r name type status total used avail pct; do
    [[ -z "$name" ]] && continue
    if [[ "$status" == "active" ]]; then
      SC="${GREEN}"; SS="${GREEN}aktif${NC}"
    else
      SC="${RED}"; SS="${RED}${status}${NC}"
      ISSUES+=("Proxmox Storage '${name}': status ${status} — tidak dapat diakses!")
    fi
    TOTAL_GB=$(echo "scale=1; ${total:-0} / 1073741824" | bc 2>/dev/null || echo "N/A")
    AVAIL_GB=$(echo "scale=1; ${avail:-0} / 1073741824" | bc 2>/dev/null || echo "N/A")
    printf "  %-20s %-12s %-10s %-10s " "$name" "$type" "${TOTAL_GB}G" "${AVAIL_GB}G"
    echo -e "${SS}"
  done
fi

# ZFS Pool
if command -v zpool &>/dev/null && zpool list &>/dev/null 2>&1; then
  print_subsection "ZFS Pool Status"
  zpool list -H 2>/dev/null | while IFS=$'\t' read -r name size alloc free ckpoint expand frag cap dedup health altroot; do
    CAP_NUM=${cap//%/}
    if [[ "$health" == "ONLINE" ]]; then HC="${GREEN}"
    elif [[ "$health" == "DEGRADED" ]]; then HC="${YELLOW}"
    else HC="${RED}"; fi
    echo -e "  Pool: ${BOLD}${name}${NC} | Size: ${size} | Used: ${alloc} | Free: ${free} | Cap: ${cap} | Frag: ${frag} | Health: ${HC}${health}${NC}"
    if [[ -n "$CAP_NUM" ]] && (( CAP_NUM >= STORAGE_CRITICAL )); then
      echo -e "    ${RED}⚠ ZFS Pool '${name}' hampir penuh!${NC}"
    fi
    if [[ "$health" == "DEGRADED" ]]; then
      WARNINGS+=("ZFS Pool '${name}': DEGRADED! Kemungkinan ada disk yang gagal, cek: zpool status ${name}")
    elif [[ "$health" != "ONLINE" ]]; then
      ISSUES+=("ZFS Pool '${name}': ${health}! Cek segera: zpool status ${name}")
    fi
  done
  echo -e "\n  ${BOLD}ZFS Health Detail:${NC}"
  safe_run 10 zpool status -x 2>/dev/null | head -15 | sed 's/^/  /'
fi

# LVM
if command -v pvs &>/dev/null; then
  print_subsection "LVM Volume Groups"
  pvs --noheadings -o pv_name,vg_name,pv_size,pv_free 2>/dev/null | \
    awk '{printf "  PV: %-20s | VG: %-15s | Size: %-8s | Free: %s\n", $1, $2, $3, $4}'
  vgs --noheadings -o vg_name,vg_size,vg_free,lv_count 2>/dev/null | \
    awk '{printf "  VG: %-20s | Size: %-8s | Free: %-8s | LVs: %s\n", $1, $2, $3, $4}'
fi

# =============================================================================
# BAGIAN 5: NETWORK ANALYSIS
# =============================================================================
print_section "NETWORK ANALYSIS"

print_subsection "Interface & IP Address"
ip -o addr show 2>/dev/null | grep -v " lo " | \
  awk '{printf "  %-15s %-18s %s\n", $2, $4, $6}' | \
  grep -v "^  veth\|^  tap\|^  fwpr\|^  fwln" | sort -u

print_subsection "Bridge & VLAN (Proxmox Network)"
if command -v brctl &>/dev/null; then
  echo -e "  Bridges aktif:"
  brctl show 2>/dev/null | grep -v "^bridge" | awk '{
    if ($1 != "") printf "  Bridge: %-15s ", $1
    if ($NF != "") printf "Interface: %s\n", $NF
  }'
fi

print_subsection "Traffic & Error Packet per Interface"
printf "  %-14s %10s %10s %10s %10s %8s %8s\n" \
  "Interface" "RX MB" "TX MB" "RX pkt/s" "TX pkt/s" "RX Err" "TX Err"
echo -e "  $(printf '─%.0s' {1..72})"

# Ambil 2 sampel untuk throughput realtime
declare -A IF_RX1 IF_TX1 IF_RX2 IF_TX2 IF_RX_ERR IF_TX_ERR IF_RX_DROP IF_TX_DROP

while IFS=: read -r iface data; do
  iface=$(echo "$iface" | xargs)
  [[ "$iface" =~ ^lo$|^veth|^tap|^fwpr|^fwln ]] && continue
  read -ra vals <<< "$data"
  IF_RX1[$iface]=${vals[0]}
  IF_TX1[$iface]=${vals[8]}
  IF_RX_ERR[$iface]=${vals[2]}
  IF_TX_ERR[$iface]=${vals[10]}
  IF_RX_DROP[$iface]=${vals[3]}
done < <(awk 'NR>2 {print}' /proc/net/dev)

# Ambil sampel kedua setelah 1 detik untuk hitung throughput realtime
# (sleep 1 tidak bisa dihindari untuk mendapat data rate yang akurat)
sleep 1

while IFS=: read -r iface data; do
  iface=$(echo "$iface" | xargs)
  [[ "$iface" =~ ^lo$|^veth|^tap|^fwpr|^fwln ]] && continue
  [[ -z "${IF_RX1[$iface]}" ]] && continue
  read -ra vals <<< "$data"
  IF_RX2[$iface]=${vals[0]}
  IF_TX2[$iface]=${vals[8]}

  RX_MB=$(echo "scale=1; ${IF_RX2[$iface]} / 1048576" | bc 2>/dev/null || echo 0)
  TX_MB=$(echo "scale=1; ${IF_TX2[$iface]} / 1048576" | bc 2>/dev/null || echo 0)
  RX_RATE=$(( IF_RX2[$iface] - IF_RX1[$iface] ))
  TX_RATE=$(( IF_TX2[$iface] - IF_TX1[$iface] ))
  RX_ERR=${IF_RX_ERR[$iface]:-0}
  TX_ERR=${IF_TX_ERR[$iface]:-0}

  # Cek error packet — NEW v4.0 (G4)
  TOTAL_ERR=$(( RX_ERR + TX_ERR ))
  if (( TOTAL_ERR >= NET_ERROR_WARNING )); then
    ERR_COLOR="${YELLOW}"
    WARNINGS+=("Network ${iface}: ${TOTAL_ERR} error packet terdeteksi — cek kabel atau NIC")
  else
    ERR_COLOR="${NC}"
  fi

  printf "  %-14s %10.1f %10.1f %10d %10d " "$iface" "$RX_MB" "$TX_MB" "$RX_RATE" "$TX_RATE"
  printf "%b%8d %8d%b\n" "${ERR_COLOR}" "$RX_ERR" "$TX_ERR" "${NC}"

done < <(awk 'NR>2 {print}' /proc/net/dev)

# =============================================================================
# BAGIAN 6: VM & CONTAINER STATUS + RESOURCE USAGE
# =============================================================================
print_section "VM & CONTAINER STATUS"

# VMs — NEW v4.0 (G2): resource usage per-VM
if command -v qm &>/dev/null; then
  print_subsection "Virtual Machines (KVM)"
  printf "  %-6s %-28s %-10s %8s %12s\n" "VMID" "Nama" "Status" "Alokasi" "Keterangan"
  echo -e "  $(printf '─%.0s' {1..70})"

  VM_COUNT=0; VM_RUNNING=0; VM_ERROR=0

  while read -r vmid name status mem bootdisk pid; do
    [[ "$vmid" =~ ^[0-9]+$ ]] || continue
    (( VM_COUNT++ ))

    case "$status" in
      running)  SC="${GREEN}"; (( VM_RUNNING++ ));;
      stopped)  SC="${YELLOW}";;
      paused)   SC="${CYAN}";;
      *)        SC="${RED}"; (( VM_ERROR++ ));;
    esac

    MEM_GB=$(echo "scale=1; ${mem:-0} / 1024" | bc 2>/dev/null || echo "?")
    printf "  %-6s %-28s " "$vmid" "${name:0:28}"
    printf "%b%-10s%b" "${SC}" "$status" "${NC}"
    printf " %5s GB" "$MEM_GB"

    # CPU usage aktual per VM dari /proc (ambil dari qemu-system process)
    if [[ "$status" == "running" ]]; then
      QEMU_PID=$(pgrep -f "qemu.*id=${vmid}[^0-9]" 2>/dev/null | head -1)
      if [[ -n "$QEMU_PID" ]]; then
        VM_CPU=$(ps -p "$QEMU_PID" -o %cpu= 2>/dev/null | xargs || echo "?")
        VM_MEM_RES=$(ps -p "$QEMU_PID" -o rss= 2>/dev/null | awk '{printf "%.0f", $1/1024}')
        echo -ne "  CPU:${VM_CPU}%  RAM_aktual:${VM_MEM_RES}MB"
      fi
    fi
    echo ""
  done < <(qm list 2>/dev/null | tail -n +2)

  echo -e "  Total VM: ${VM_COUNT} | ${GREEN}Running: ${VM_RUNNING}${NC} | ${YELLOW}Stopped: $((VM_COUNT - VM_RUNNING - VM_ERROR))${NC} | ${RED}Error: ${VM_ERROR}${NC}"
  [[ "$VM_ERROR" -gt 0 ]] && ISSUES+=("Ada ${VM_ERROR} VM dalam status error!")
fi

# Containers — dengan resource usage
if command -v pct &>/dev/null; then
  print_subsection "Containers (LXC)"
  printf "  %-6s %-28s %-10s %s\n" "CTID" "Nama" "Status" "Keterangan"
  echo -e "  $(printf '─%.0s' {1..66})"

  CT_COUNT=0; CT_RUNNING=0; CT_ERROR=0

  while read -r ctid status lock name; do
    [[ "$ctid" =~ ^[0-9]+$ ]] || continue
    (( CT_COUNT++ ))

    case "$status" in
      running)  SC="${GREEN}"; (( CT_RUNNING++ ));;
      stopped)  SC="${YELLOW}";;
      *)        SC="${RED}"; (( CT_ERROR++ ));;
    esac

    printf "  %-6s %-28s " "$ctid" "${name:0:28}"
    printf "%b%-10s%b" "${SC}" "$status" "${NC}"

    # CPU & RAM aktual per container dari /sys/fs/cgroup
    if [[ "$status" == "running" ]]; then
      CT_CPU_FILE="/sys/fs/cgroup/lxc/${ctid}/cpuacct.usage"
      CT_MEM_FILE="/sys/fs/cgroup/lxc/${ctid}/memory.usage_in_bytes"
      [[ ! -f "$CT_MEM_FILE" ]] && CT_MEM_FILE="/sys/fs/cgroup/system.slice/lxc@${ctid}.service/memory.current"
      if [[ -f "$CT_MEM_FILE" ]]; then
        CT_MEM_MB=$(echo "scale=0; $(cat "$CT_MEM_FILE" 2>/dev/null || echo 0) / 1048576" | bc 2>/dev/null)
        echo -ne "  RAM:${CT_MEM_MB}MB"
      fi
    fi
    echo ""
  done < <(pct list 2>/dev/null | tail -n +2)

  echo -e "  Total CT: ${CT_COUNT} | ${GREEN}Running: ${CT_RUNNING}${NC} | ${YELLOW}Stopped: $((CT_COUNT - CT_RUNNING - CT_ERROR))${NC} | ${RED}Error: ${CT_ERROR}${NC}"
fi

# =============================================================================
# BAGIAN 7: DISK HEALTH (S.M.A.R.T) — ENHANCED v4.0
# =============================================================================
print_section "DISK HEALTH (S.M.A.R.T)"

if command -v smartctl &>/dev/null; then
  DISK_FOUND=false

  # Gunakan smartctl --scan untuk menemukan SEMUA disk, termasuk di belakang RAID controller
  # Output format: /dev/bus/0 -d megaraid,0 # /dev/bus/0 [megaraid_disk_00], SCSI device
  SCAN_OUTPUT=$(safe_run 10 smartctl --scan 2>/dev/null)

  # Bangun daftar disk: "device|dtype" per baris
  DISK_LIST=""
  if [[ -n "$SCAN_OUTPUT" ]]; then
    while IFS= read -r scan_line; do
      [[ -z "$scan_line" ]] && continue
      SCAN_DEV=$(echo "$scan_line" | awk '{print $1}')
      SCAN_DTYPE=$(echo "$scan_line" | awk '{print $3}')
      [[ -z "$SCAN_DEV" ]] && continue
      DISK_LIST+="${SCAN_DEV}|${SCAN_DTYPE:-auto}"$'\n'
    done <<< "$SCAN_OUTPUT"
  fi

  # Fallback: jika --scan kosong, gunakan glob /dev/sd? dan /dev/nvme?n?
  if [[ -z "$DISK_LIST" ]]; then
    for disk in /dev/sd? /dev/nvme?n?; do
      [[ -b "$disk" ]] || continue
      DISK_LIST+="${disk}|auto"$'\n'
    done
  fi

  [[ -z "$DISK_LIST" ]] && { echo -e "  ${YELLOW}Tidak ada disk yang terdeteksi.${NC}"; }

  while IFS='|' read -r disk dtype; do
    [[ -z "$disk" ]] && continue
    DISK_FOUND=true

    # Tentukan label tipe disk
    DISK_TYPE="HDD"
    [[ "$disk" == /dev/nvme* ]] && DISK_TYPE="NVMe"
    [[ "$dtype" == megaraid,* ]] && DISK_TYPE="RAID-Disk"

    # Label tampilan untuk disk di belakang RAID
    if [[ "$dtype" == megaraid,* || "$dtype" == 3ware,* || "$dtype" == cciss,* || "$dtype" == hpt,* ]]; then
      DISK_LABEL="${disk} [${dtype}]"
    else
      DISK_LABEL="${disk}"
    fi

    # --nocheck=standby : JANGAN bangunkan disk yang sedang sleep/standby.
    SMART_ALL=$(safe_run 15 smartctl --nocheck=standby -a -d "$dtype" "$disk" 2>/dev/null)
    SMART_EXIT=$?

    # Exit code 2 dari smartctl berarti disk sedang dalam mode standby/sleep
    if [[ $SMART_EXIT -eq 2 ]] || echo "$SMART_ALL" | grep -qi "standby\|sleep mode\|in STANDBY"; then
      echo -e "  ${CYAN}💤${NC} ${BOLD}${DISK_LABEL}${NC} — Disk sedang dalam mode ${CYAN}Standby/Sleep${NC} (tidak dibangunkan)"
      echo -e "    ${CYAN}ℹ Gunakan: smartctl -a ${disk} -d ${dtype}  untuk membaca (akan membangunkan disk)${NC}"
      echo ""
      OK_LIST+=("Disk ${DISK_LABEL}: Mode Standby/Sleep (Aman — tidak dibangunkan)")
      continue
    fi

    [[ -z "$SMART_ALL" ]] && { echo -e "  ${YELLOW}? ${DISK_LABEL}: Timeout atau tidak bisa dibaca${NC}"; continue; }

    SMART_STATUS=$(echo "$SMART_ALL" | grep -iE "overall-health|SMART Health Status" | head -1 | awk '{print $NF}')

    # Temperature: cari field numerik > 0 dari kanan, kompatibel SATA/SAS/NVMe
    TEMP=$(echo "$SMART_ALL" | grep -iE "temperature_celsius|Airflow_Temp|Temperature:|Current Drive Temperature" | grep -vi "Min\|Max\|Limit\|Lifetime\|Warning\|Critical\|Shipping" | head -1 | awk '{for(i=NF;i>=1;i--) if($i+0==$i && $i>0){print int($i); exit}}')
    POWER_ON=$(echo "$SMART_ALL" | grep -iE "power_on_hours|Accumulated power on" | head -1 | awk '{for(i=NF;i>=1;i--) if($i+0==$i && $i>0){print $i; exit}}')
    POWER_CYCLE=$(echo "$SMART_ALL" | grep -iE "power_cycle_count|Accumulated start-stop" | head -1 | awk '{for(i=NF;i>=1;i--) if($i+0==$i && $i>0){print $i; exit}}')
    MODEL=$(echo "$SMART_ALL" | grep -iE "^Device Model|^Model Number|^Product:" | head -1 | cut -d: -f2 | xargs)
    SERIAL=$(echo "$SMART_ALL" | grep -iE "^Serial Number|^Serial number:" | head -1 | cut -d: -f2 | xargs)
    CAPACITY=$(echo "$SMART_ALL" | grep -iE "User Capacity|Namespace 1 Size" | head -1 | grep -oP '\[.*?\]' | head -1)

    # SMART critical attributes (SATA format)
    REALLOCATED=$(echo "$SMART_ALL" | grep -i "Reallocated_Sector_Ct\|Reallocated_Event" | awk '{print $10}')
    PENDING=$(echo "$SMART_ALL" | grep -i "Current_Pending_Sector\|Pending_Sector" | awk '{print $10}')
    UNCORRECT=$(echo "$SMART_ALL" | grep -i "Offline_Uncorrectable\|Uncorrectable_Error" | awk '{print $10}')
    WEAR_LEVEL=$(echo "$SMART_ALL" | grep -i "Wear_Leveling_Count\|SSD_Life_Left\|Percent_Lifetime" | awk '{print $4}' | head -1)
    MEDIA_ERRORS=$(echo "$SMART_ALL" | grep -i "Media_Wearout_Indicator\|media_errors" | awk '{print $10}' | head -1)

    # SAS/SCSI specific critical attributes
    SAS_GROWN_DEFECTS=$(echo "$SMART_ALL" | grep -iE "grown defect|Elements in grown defect" | awk '{print $NF}')
    SAS_READ_UNCORRECT=$(echo "$SMART_ALL" | grep -A1 "read:" 2>/dev/null | tail -1 | awk '{print $NF}')

    # NVMe specific
    NVME_MEDIA_ERR=$(echo "$SMART_ALL" | grep -i "Media and Data" | awk '{print $NF}')
    NVME_PERCENT_USED=$(echo "$SMART_ALL" | grep -i "Percentage Used" | awk '{print $NF}')

    # Deteksi tipe disk (SSD/HDD) dari rotation rate jika ada
    ROTATION=$(echo "$SMART_ALL" | grep -i "Rotation Rate" | head -1)
    if echo "$ROTATION" | grep -qi "Solid State"; then
      DISK_TYPE="SSD"
    elif [[ "$disk" == /dev/nvme* ]]; then
      DISK_TYPE="NVMe"
    fi

    # Status keseluruhan — 3 cabang: OK, tidak terbaca (RAID virtual disk), atau GAGAL
    if [[ "$SMART_STATUS" == "PASSED" ]] || [[ "$SMART_STATUS" == "OK" ]]; then
      echo -e "  ${GREEN}✓${NC} ${BOLD}${DISK_LABEL}${NC} [${DISK_TYPE}] ${MODEL} ${SERIAL:+(S/N: ${SERIAL})}"
      echo -e "    Health: ${GREEN}${SMART_STATUS}${NC}  Suhu: ${TEMP:-N/A}°C  Power On: ${POWER_ON:-N/A}h  Siklus: ${POWER_CYCLE:-N/A}  ${CAPACITY}"
    elif [[ -z "$SMART_STATUS" ]]; then
      # SMART tidak terbaca — kemungkinan RAID virtual disk, skip
      if [[ "$dtype" == "scsi" ]] && [[ -n "$(echo "$DISK_LIST" | grep 'megaraid\|3ware\|cciss')" ]]; then
        # Ini RAID virtual disk (/dev/sda -d scsi), disk fisik sudah di-scan terpisah via megaraid
        echo -e "  ${CYAN}ℹ${NC} ${BOLD}${DISK_LABEL}${NC} — RAID Virtual Disk (disk fisik di-scan terpisah di bawah)"
        echo ""
        continue
      fi
      echo -e "  ${YELLOW}?${NC} ${BOLD}${DISK_LABEL}${NC} [${DISK_TYPE}] ${MODEL}"
      echo -e "    Health: ${YELLOW}TIDAK DAPAT DIBACA${NC} — SMART data tidak tersedia"
      echo -e "    ${CYAN}ℹ Coba: smartctl --scan  untuk menemukan interface yang benar${NC}"
      WARNINGS+=("Disk ${DISK_LABEL}: SMART tidak dapat dibaca")
      echo ""
      continue
    else
      echo -e "  ${RED}✗${NC} ${BOLD}${DISK_LABEL}${NC} [${DISK_TYPE}] ${MODEL} ${SERIAL:+(S/N: ${SERIAL})}"
      echo -e "    Health: ${RED}${SMART_STATUS}${NC}  Suhu: ${TEMP:-N/A}°C  ${RED}⚠ PERIKSA SEGERA!${NC}"
      ISSUES+=("Disk ${DISK_LABEL}: SMART status ${SMART_STATUS} — Kemungkinan kerusakan hardware!")
    fi

    # Tampilkan critical attributes
    DISK_ATTR_ISSUES=false
    if [[ -n "$REALLOCATED" ]] && (( 10#${REALLOCATED:-0} >= SMART_REALLOCATED_WARN )); then
      echo -e "    ${RED}  ⚠ Reallocated Sectors: ${REALLOCATED} — Disk mulai mengalami kerusakan fisik!${NC}"
      ISSUES+=("Disk ${DISK_LABEL}: Reallocated Sectors=${REALLOCATED} — Segera backup data & siapkan pengganti!")
      DISK_ATTR_ISSUES=true
    fi
    if [[ -n "$PENDING" ]] && (( 10#${PENDING:-0} > 0 )); then
      echo -e "    ${YELLOW}  ⚠ Pending Sectors  : ${PENDING} — Sektor menunggu realokasi${NC}"
      WARNINGS+=("Disk ${DISK_LABEL}: Current Pending Sector=${PENDING} — Monitor ketat!")
      DISK_ATTR_ISSUES=true
    fi
    if [[ -n "$UNCORRECT" ]] && (( 10#${UNCORRECT:-0} > 0 )); then
      echo -e "    ${RED}  ⚠ Uncorrectable Err : ${UNCORRECT} — Error yang tidak bisa diperbaiki!${NC}"
      ISSUES+=("Disk ${DISK_LABEL}: Uncorrectable Error=${UNCORRECT} — Risiko kehilangan data tinggi!")
      DISK_ATTR_ISSUES=true
    fi
    if [[ -n "$WEAR_LEVEL" ]] && (( 10#${WEAR_LEVEL:-255} < 20 )); then
      echo -e "    ${YELLOW}  ⚠ Wear Level        : ${WEAR_LEVEL} — SSD mendekati akhir umur pakai${NC}"
      WARNINGS+=("Disk ${DISK_LABEL}: Wear Level=${WEAR_LEVEL} — SSD hampir habis masa pakainya")
      DISK_ATTR_ISSUES=true
    fi
    # SAS: Grown Defect List
    if [[ -n "$SAS_GROWN_DEFECTS" ]] && (( 10#${SAS_GROWN_DEFECTS:-0} > 0 )); then
      echo -e "    ${YELLOW}  ⚠ Grown Defects     : ${SAS_GROWN_DEFECTS} — Bad sector terdeteksi pada disk SAS${NC}"
      WARNINGS+=("Disk ${DISK_LABEL}: Grown Defects=${SAS_GROWN_DEFECTS} — Monitor ketat!")
      DISK_ATTR_ISSUES=true
    fi
    [[ -n "$NVME_PERCENT_USED" ]] && echo -e "    NVMe Used%: ${NVME_PERCENT_USED}  Media Errors: ${NVME_MEDIA_ERR:-N/A}"
    [[ "$DISK_ATTR_ISSUES" == false ]] && echo -e "    ${GREEN}  ✓ Semua critical attributes normal${NC}"

    # Disk temperature threshold — NEW v4.0 (G6)
    if [[ -n "$TEMP" ]] && [[ "$TEMP" =~ ^[0-9]+$ ]]; then
      if (( TEMP >= DISK_TEMP_CRITICAL )); then
        echo -e "    ${RED}  🔥 Suhu disk KRITIS: ${TEMP}°C!${NC}"
        ISSUES+=("Disk ${DISK_LABEL}: Suhu ${TEMP}°C — OVERHEAT! Periksa airflow server")
      elif (( TEMP >= DISK_TEMP_WARNING )); then
        echo -e "    ${YELLOW}  ⚠ Suhu disk tinggi: ${TEMP}°C${NC}"
        WARNINGS+=("Disk ${DISK_LABEL}: Suhu ${TEMP}°C — Tinggi, periksa airflow")
      fi
    fi
    echo ""
  done <<< "$DISK_LIST"
  [[ "$DISK_FOUND" == false ]] && echo -e "  ${YELLOW}Tidak ada disk yang terdeteksi.${NC}"
else
  echo -e "  ${YELLOW}smartmontools tidak terinstall.${NC}"
  echo -e "  ${CYAN}Install: apt install -y smartmontools${NC}"
fi

# =============================================================================
# BAGIAN 8: BACKUP STATUS (vzdump)
# =============================================================================
print_section "BACKUP STATUS (vzdump)"

BACKUP_LOG_DIR="/var/log/vzdump"
BACKUP_ISSUES_COUNT=0
BACKUP_OK_COUNT=0

# BUG #4 FIX: pattern deteksi error lebih spesifik (hindari false positive)
BACKUP_ERROR_PATTERN='ERROR:|TASK ERROR:|backup failed|command .* failed|No space left|Connection timed out|aborted|FAILED:'
BACKUP_OK_PATTERN='TASK OK|backup successful|Backup job finished|Finished Backup of VM|Finished Backup of CT|archive file size|transferred .* in .* seconds'

if [[ -d "$BACKUP_LOG_DIR" ]]; then
  echo -e "  ${BOLD}Log Backup 24 Jam Terakhir (${BACKUP_LOG_DIR}):${NC}"
  printf "  %-50s %s\n" "File Log" "Status"
  echo -e "  $(printf '─%.0s' {1..62})"

  FOUND_ANY=false
  while IFS= read -r logfile; do
    FOUND_ANY=true
    BASENAME=$(basename "$logfile")
    if grep -qiP "$BACKUP_ERROR_PATTERN" "$logfile" 2>/dev/null; then
      ERR_LINE=$(grep -iP "$BACKUP_ERROR_PATTERN" "$logfile" 2>/dev/null | tail -1 | cut -c1-60)
      printf "  %-50s " "${BASENAME:0:50}"
      echo -e "${RED}[GAGAL]${NC}"
      echo -e "    ${RED}↳ ${ERR_LINE}${NC}"
      (( BACKUP_ISSUES_COUNT++ ))
    elif grep -qiP "$BACKUP_OK_PATTERN" "$logfile" 2>/dev/null; then
      printf "  %-50s " "${BASENAME:0:50}"
      echo -e "${GREEN}[SUKSES]${NC}"
      (( BACKUP_OK_COUNT++ ))
    else
      printf "  %-50s " "${BASENAME:0:50}"
      echo -e "${CYAN}[TIDAK LENGKAP / BERJALAN]${NC}"
    fi
  done < <(find "$BACKUP_LOG_DIR" -type f -name "*.log" -mmin -1440 2>/dev/null | sort | head -30)

  if [[ "$FOUND_ANY" == false ]]; then
    echo -e "  ${YELLOW}ℹ Tidak ada log backup dalam 24 jam terakhir.${NC}"
    echo -e "  ${CYAN}  Konfigurasi backup: Proxmox GUI → Datacenter → Backup${NC}"
  else
    echo -e "\n  Ringkasan: ${GREEN}${BACKUP_OK_COUNT} Sukses${NC} | ${RED}${BACKUP_ISSUES_COUNT} Gagal${NC}"
  fi
else
  # Cek Proxmox Task API untuk backup history
  echo -e "  ${CYAN}Direktori ${BACKUP_LOG_DIR} tidak ditemukan. Mengecek Proxmox Task API...${NC}"
  if command -v pvesh &>/dev/null; then
    BACKUP_TASKS=$(safe_run 10 pvesh get /nodes/"${HOSTNAME_SHORT}"/tasks \
      --output-format json 2>/dev/null | \
      grep -i '"type":"vzdump"' | head -5)
    if [[ -n "$BACKUP_TASKS" ]]; then
      echo -e "  ${CYAN}Task backup terakhir (via pvesh):${NC}"
      echo "$BACKUP_TASKS" | grep -o '"status":"[^"]*"\|"starttime":[0-9]*\|"type":"[^"]*"' | \
        paste - - - | head -10 | sed 's/^/  /'
    else
      echo -e "  ${YELLOW}Tidak ada data backup task ditemukan.${NC}"
    fi
  fi
fi

if [[ "$BACKUP_ISSUES_COUNT" -gt 0 ]]; then
  ISSUES+=("Backup: ${BACKUP_ISSUES_COUNT} job GAGAL dalam 24 jam terakhir! Cek ${BACKUP_LOG_DIR}")
fi
if [[ "$BACKUP_OK_COUNT" -gt 0 ]]; then
  OK_LIST+=("Backup: ${BACKUP_OK_COUNT} job berhasil dalam 24 jam terakhir")
fi

# =============================================================================
# BAGIAN 9: CLUSTER & HA STATUS
# =============================================================================
print_section "CLUSTER & HA STATUS"

# BUG #2 FIX: gunakan $PVECM_OUTPUT yang sudah di-cache di awal
if [[ -n "$PVECM_OUTPUT" ]]; then
  CLUSTER_NAME=$(echo "$PVECM_OUTPUT" | grep "^Name:" | awk '{print $2}')
else
  CLUSTER_NAME=""
fi

if [[ -n "$CLUSTER_NAME" ]]; then
  QUORATE=$(echo "$PVECM_OUTPUT" | grep "^Quorate" | awk '{print $2}')
  NODES_TOTAL=$(echo "$PVECM_OUTPUT" | grep "^Nodes" | awk '{print $2}')
  EXPECTED_VOTES=$(echo "$PVECM_OUTPUT" | grep "Expected votes" | awk '{print $NF}')
  TOTAL_VOTES=$(echo "$PVECM_OUTPUT" | grep "Total votes" | awk '{print $NF}')

  echo -e "  Nama Cluster  : ${BOLD}${CLUSTER_NAME}${NC}"
  echo -e "  Total Node    : ${NODES_TOTAL:-N/A}"
  echo -e "  Votes         : Total=${TOTAL_VOTES:-N/A} | Expected=${EXPECTED_VOTES:-N/A}"

  if [[ "$QUORATE" == "Yes" ]] || [[ "$QUORATE" == "1" ]]; then
    echo -e "  Status Quorum : ${GREEN}[TERCAPAI]${NC} Cluster berfungsi normal"
    OK_LIST+=("Cluster '${CLUSTER_NAME}': Quorum tercapai (${TOTAL_VOTES:-?} votes)")
  else
    echo -e "  Status Quorum : ${RED}[KRITIS] QUORUM TIDAK TERCAPAI!${NC}"
    echo -e "    ${RED}Ada node yang offline atau split-brain! Jangan lakukan operasi apapun!${NC}"
    ISSUES+=("Cluster Quorum GAGAL untuk '${CLUSTER_NAME}'! Emergency: pvecm status")
  fi

  # Status per node
  print_subsection "Status Per Node"
  if command -v pvecm &>/dev/null; then
    safe_run 5 pvecm nodes 2>/dev/null | tail -n +3 | while read -r node_id votes local node_ip node_name rest; do
      [[ -z "$node_name" ]] && node_name="$node_ip"
      [[ -z "$node_name" ]] && continue
      NODE_ADDR="${node_ip}"
      if ping -c 1 -W 2 "$NODE_ADDR" &>/dev/null 2>&1; then
        echo -e "  ${GREEN}✓${NC} Node #${node_id}: ${node_name} (${NODE_ADDR}) — ${GREEN}Online${NC}  Votes: ${votes}"
      else
        echo -e "  ${RED}✗${NC} Node #${node_id}: ${node_name} (${NODE_ADDR}) — ${RED}TIDAK DAPAT DIJANGKAU!${NC}"
      fi
    done
  fi

  if [[ "$ALERT_ONLY" == false ]]; then
    print_subsection "Detail Cluster"
    echo "$PVECM_OUTPUT" | sed 's/^/  /'
  fi
else
  echo -e "  ${CYAN}ℹ Node ini berjalan dalam mode Standalone (tidak bergabung ke cluster).${NC}"
  OK_LIST+=("Mode Standalone — tidak ada cluster")
fi

# HA Status — NEW v4.0 (G7)
if command -v ha-manager &>/dev/null; then
  print_subsection "High Availability (HA) Status"
  HA_STATUS=$(safe_run 10 ha-manager status 2>/dev/null)
  if [[ -n "$HA_STATUS" ]]; then
    echo "$HA_STATUS" | while read -r line; do
      if echo "$line" | grep -qi "error\|failed\|stopped unexpectedly\|OFFLINE"; then
        echo -e "  ${RED}✗${NC} $line"
        ISSUES+=("HA: ${line}")
      elif echo "$line" | grep -qi "started\|running\|online"; then
        echo -e "  ${GREEN}✓${NC} $line"
      else
        echo -e "    $line"
      fi
    done
  else
    echo -e "  ${CYAN}ℹ HA Manager tidak aktif atau tidak ada resource HA yang dikonfigurasi.${NC}"
  fi
fi

# =============================================================================
# BAGIAN 10: KERNEL ERROR & OOM DETECTION — NEW v4.0
# =============================================================================
print_section "KERNEL ERROR & SYSTEM EVENTS (24 Jam)"

print_subsection "dmesg — Hardware & Kernel Error"
DMESG_ERRORS=""
if command -v journalctl &>/dev/null; then
  DMESG_ERRORS=$(journalctl -k --since "24 hours ago" --no-pager 2>/dev/null | \
    grep -iE "error|fail|fault|critical|oom|panic|bad page|hardware error|memory leak|i/o error|ext4-fs error|nfs: server|zfs: pool" | \
    grep -v "firmware bug\|Unknown" | tail -20)
else
  DMESG_ERRORS=$(dmesg --level=err,crit,alert,emerg 2>/dev/null | tail -20)
fi

if [[ -n "$DMESG_ERRORS" ]]; then
  echo -e "  ${YELLOW}⚠ Ditemukan error di kernel log:${NC}"
  echo "$DMESG_ERRORS" | tail -15 | while read -r line; do
    if echo "$line" | grep -qi "oom\|kill\|out of memory"; then
      echo -e "  ${RED}💀 OOM: ${line:0:90}${NC}"
    elif echo "$line" | grep -qi "hardware error\|mce\|uncorrected"; then
      echo -e "  ${RED}🔥 HW : ${line:0:90}${NC}"
    elif echo "$line" | grep -qi "i/o error\|disk error\|read error"; then
      echo -e "  ${RED}💽 IO : ${line:0:90}${NC}"
    else
      echo -e "  ${YELLOW}⚠    : ${line:0:90}${NC}"
    fi
  done
  WARNINGS+=("Ada $(echo "$DMESG_ERRORS" | wc -l) kernel error dalam 24 jam — cek: journalctl -k --since '24h ago'")
else
  echo -e "  ${GREEN}✓ Tidak ada kernel error dalam 24 jam terakhir.${NC}"
  OK_LIST+=("Kernel: Tidak ada hardware/kernel error dalam 24 jam")
fi

# OOM Kill Detection — NEW v4.0 (G10)
print_subsection "OOM Kill Events (Out of Memory Killer)"
OOM_EVENTS=""
if command -v journalctl &>/dev/null; then
  OOM_EVENTS=$(journalctl --since "24 hours ago" --no-pager 2>/dev/null | \
    grep -iE "oom.kill|killed process|out of memory.*kill" | tail -10)
fi
[[ -z "$OOM_EVENTS" ]] && OOM_EVENTS=$(dmesg 2>/dev/null | grep -i "oom\|killed process\|out of memory" | tail -10)

if [[ -n "$OOM_EVENTS" ]]; then
  OOM_COUNT=$(echo "$OOM_EVENTS" | wc -l)
  echo -e "  ${RED}${BOLD}💀 DITEMUKAN ${OOM_COUNT} OOM Kill Event dalam 24 jam!${NC}"
  echo -e "  ${RED}   Ini berarti RAM benar-benar habis dan OS paksa membunuh proses/VM!${NC}"
  echo "$OOM_EVENTS" | while read -r line; do
    echo -e "  ${RED}  ↳ ${line:0:100}${NC}"
  done
  ISSUES+=("OOM Killer aktif ${OOM_COUNT}x dalam 24 jam — RAM habis total, proses/VM dibunuh paksa!")
else
  echo -e "  ${GREEN}✓ Tidak ada OOM Kill event dalam 24 jam. RAM mencukupi.${NC}"
  OK_LIST+=("OOM: Tidak ada proses yang dibunuh karena kekurangan RAM")
fi

# =============================================================================
# BAGIAN 11: PROXMOX TASK HISTORY (24 Jam)
# =============================================================================
print_section "PROXMOX TASK HISTORY (24 Jam)"

if command -v pvesh &>/dev/null; then
  echo -e "  ${CYAN}Mengambil task history dari Proxmox API...${NC}"
  TASK_OUTPUT=$(safe_run 15 pvesh get /nodes/"${HOSTNAME_SHORT}"/tasks \
    --limit 50 --output-format json 2>/dev/null)

  if [[ -n "$TASK_OUTPUT" ]] && echo "$TASK_OUTPUT" | python3 -m json.tool &>/dev/null 2>&1; then

    # [FIX] Simpan JSON ke Environment Variable agar aman dibaca oleh Python
    export TASK_JSON="$TASK_OUTPUT"

    # 1. Parse Task Gagal
    echo -e "\n  ${BOLD}Task Gagal / Error (24 jam):${NC}"
    python3 - <<'PYEOF' 2>/dev/null
import json, sys, time, os

try:
    # Membaca data dari Environment Variable
    data = json.loads(os.environ.get('TASK_JSON', '[]'))
except:
    sys.exit(0)

now = time.time()
cutoff = now - 86400  # 24 jam

failed = [t for t in data if isinstance(t, dict) and
          t.get('starttime', 0) > cutoff and
          t.get('status', '') not in ('OK', 'running', '')]

if not failed:
    print("  \033[0;32m✓ Tidak ada task yang gagal dalam 24 jam.\033[0m")
else:
    print(f"  \033[1;33m⚠ Ditemukan {len(failed)} task gagal:\033[0m")
    for t in failed[:15]:
        ts = time.strftime('%Y-%m-%d %H:%M', time.localtime(t.get('starttime', 0)))
        print(f"  \033[0;31m✗\033[0m [{ts}] {t.get('type','?'):12s} {t.get('id','?'):20s} → {t.get('status','?')}")
PYEOF

    # 2. Parse Task Terbaru
    echo -e "\n  ${BOLD}Task Terbaru (semua tipe):${NC}"
    printf "  %-18s %-14s %-22s %s\n" "Waktu" "Tipe" "ID/VMID" "Status"
    echo -e "  $(printf '─%.0s' {1..66})"

    python3 - <<'PYEOF' 2>/dev/null
import json, sys, time, os

try:
    data = json.loads(os.environ.get('TASK_JSON', '[]'))
except:
    sys.exit(0)

now = time.time()
cutoff = now - 86400

recent = [t for t in data if isinstance(t, dict) and t.get('starttime', 0) > cutoff]
recent.sort(key=lambda x: x.get('starttime', 0), reverse=True)

for t in recent[:20]:
    ts = time.strftime('%m-%d %H:%M:%S', time.localtime(t.get('starttime', 0)))
    status = t.get('status', 'running')
    if status == 'OK':
        sc = '\033[0;32m'
    elif status == 'running':
        sc = '\033[0;36m'
    else:
        sc = '\033[0;31m'
    print(f"  [{ts}] {t.get('type','?'):13s} {t.get('id','?'):22s} {sc}{status}\033[0m")
PYEOF

    # Bersihkan environment variable
    unset TASK_JSON

  else
    # Fallback jika Python tidak ada atau API error
    echo -e "  ${YELLOW}Data API kosong atau python3 gagal mem-parsing. Output raw:${NC}"
    safe_run 15 pvesh get /nodes/"${HOSTNAME_SHORT}"/tasks --limit 10 2>/dev/null | \
      grep -E "type|status|starttime" | head -30 | sed 's/^/  /'
  fi
else
  echo -e "  ${YELLOW}pvesh tidak tersedia.${NC}"
fi

# =============================================================================
# BAGIAN 12: PROXMOX SERVICE STATUS
# =============================================================================
print_section "PROXMOX SERVICE STATUS"

SERVICES=(
  "pvedaemon:PVE API Daemon"
  "pveproxy:PVE Web Proxy"
  "pvestatd:PVE Statistics Daemon"
  "pve-cluster:PVE Cluster Service"
  "corosync:Cluster Messaging (Corosync)"
  "pve-firewall:PVE Firewall"
  "pvesr:PVE Storage Replication"
  "cron:Cron Scheduler"
  "ssh:SSH Server"
  "ntp:NTP Time Sync"
  "chrony:Chrony Time Sync"
)

SVC_FAIL=0
for svc_entry in "${SERVICES[@]}"; do
  SVC="${svc_entry%%:*}"
  DESC="${svc_entry##*:}"
  STATUS=$(systemctl is-active "$SVC" 2>/dev/null)

  case "$STATUS" in
    active)
      [[ "$ALERT_ONLY" == false ]] && echo -e "  ${GREEN}✓${NC} ${DESC} (${SVC}): ${GREEN}aktif${NC}"
      ;;
    inactive)
      # Layanan opsional (ntp/chrony mungkin salah satu saja aktif)
      [[ "$SVC" == "ntp" || "$SVC" == "chrony" ]] && continue
      echo -e "  ${YELLOW}○${NC} ${DESC} (${SVC}): ${YELLOW}tidak aktif${NC}"
      ;;
    failed)
      echo -e "  ${RED}✗${NC} ${DESC} (${SVC}): ${RED}GAGAL/CRASH${NC}"
      ISSUES+=("Service ${SVC} (${DESC}): GAGAL — jalankan: systemctl restart ${SVC}")
      (( SVC_FAIL++ ))
      ;;
    *)
      # Skip jika service tidak ada di sistem ini
      [[ "$STATUS" == "" || "$STATUS" == "unknown" ]] && continue
      echo -e "  ${YELLOW}?${NC} ${DESC} (${SVC}): ${YELLOW}${STATUS}${NC}"
      ;;
  esac
done

[[ "$SVC_FAIL" -eq 0 ]] && OK_LIST+=("Service: Semua service Proxmox berjalan normal")

# =============================================================================
# BAGIAN 13: SUMMARY & REKOMENDASI
# =============================================================================
if [[ "$ALERT_ONLY" == true ]]; then
  exec 1>&3 3>&-
fi

print_header "SUMMARY ANALISIS & REKOMENDASI"

# ─── Cetak Masalah Kritis ────────────────────────────────────────────────────
if [[ ${#ISSUES[@]} -gt 0 ]]; then
  echo -e "\n  ${RED}${BOLD}❌ MASALAH KRITIS (${#ISSUES[@]}):${NC}"
  for issue in "${ISSUES[@]}"; do
    echo -e "  ${RED}  • ${issue}${NC}"
  done
fi

# ─── Cetak Peringatan ────────────────────────────────────────────────────────
if [[ ${#WARNINGS[@]} -gt 0 ]]; then
  echo -e "\n  ${YELLOW}${BOLD}⚠ PERINGATAN (${#WARNINGS[@]}):${NC}"
  for warn in "${WARNINGS[@]}"; do
    echo -e "  ${YELLOW}  • ${warn}${NC}"
  done
fi

# ─── Cetak Normal ────────────────────────────────────────────────────────────
if [[ ${#OK_LIST[@]} -gt 0 ]] && [[ "$ALERT_ONLY" == false ]]; then
  echo -e "\n  ${GREEN}${BOLD}✓ STATUS NORMAL (${#OK_LIST[@]}):${NC}"
  for ok in "${OK_LIST[@]}"; do
    echo -e "  ${GREEN}  • ${ok}${NC}"
  done
fi

# ─── Status Keseluruhan ───────────────────────────────────────────────────────
echo ""
if [[ ${#ISSUES[@]} -gt 0 ]]; then
  echo -e "  ${RED}${BOLD}★ STATUS KESELURUHAN: 🔴 KRITIS — ${#ISSUES[@]} masalah perlu ditangani segera!${NC}"
elif [[ ${#WARNINGS[@]} -gt 0 ]]; then
  echo -e "  ${YELLOW}${BOLD}★ STATUS KESELURUHAN: 🟡 PERLU PERHATIAN — Ada ${#WARNINGS[@]} peringatan${NC}"
else
  echo -e "  ${GREEN}${BOLD}★ STATUS KESELURUHAN: 🟢 SEHAT — Semua sistem dalam kondisi normal ✓${NC}"
fi

# ─── Panduan Threshold ───────────────────────────────────────────────────────
if [[ "$ALERT_ONLY" == false ]]; then
echo ""
echo -e "  ${BOLD}📋 Threshold Aktif:${NC}"
printf "  %-12s Normal       Peringatan     Kritis\n" "Metrik"
echo -e "  $(printf '─%.0s' {1..52})"
printf "  %-12s %-13s %-15s %s\n" "CPU"      "< ${CPU_WARNING}%"      "${CPU_WARNING}-${CPU_CRITICAL}%"   "> ${CPU_CRITICAL}%"
printf "  %-12s %-13s %-15s %s\n" "RAM"      "< ${RAM_WARNING}%"      "${RAM_WARNING}-${RAM_CRITICAL}%"   "> ${RAM_CRITICAL}%"
printf "  %-12s %-13s %-15s %s\n" "Storage"  "< ${STORAGE_WARNING}%"  "${STORAGE_WARNING}-${STORAGE_CRITICAL}%" "> ${STORAGE_CRITICAL}%"
printf "  %-12s %-13s %-15s %s\n" "IOWait"   "< ${IOWAIT_WARNING}%"   "${IOWAIT_WARNING}-${IOWAIT_CRITICAL}%"   "> ${IOWAIT_CRITICAL}%"
printf "  %-12s %-13s %-15s %s\n" "CPU Steal" "< ${CPU_STEAL_WARNING}%" "${CPU_STEAL_WARNING}-${CPU_STEAL_CRITICAL}%" "> ${CPU_STEAL_CRITICAL}%"
printf "  %-12s %-13s %-15s %s\n" "Disk Temp" "< ${DISK_TEMP_WARNING}°C" "${DISK_TEMP_WARNING}-${DISK_TEMP_CRITICAL}°C" "> ${DISK_TEMP_CRITICAL}°C"

# ─── Tips Operasional ───────────────────────────────────────────────────────
echo ""
echo -e "  ${BOLD}💡 Perintah Diagnosis Cepat:${NC}"
echo -e "  • Real-time VM   : watch -n5 'qm list && pct list'"
echo -e "  • I/O per disk   : iostat -x 1 5"
echo -e "  • Network live   : watch -n2 'ip -s link'"
echo -e "  • ZFS ARC live   : watch -n2 'arc_summary'"
echo -e "  • Kernel log     : journalctl -k --since '1h ago' -f"
echo -e "  • OOM history    : journalctl --since '24h ago' | grep -i oom"
echo -e "  • Task history   : pvesh get /nodes/\$(hostname)/tasks --limit 20"
echo -e "  • Storage pool   : pvesm status"
echo -e "  • HA status      : ha-manager status"

echo -e "  • SMART detail   : smartctl -a /dev/sda"
echo -e "  • Log backup     : ls -lhrt /var/log/vzdump/ | tail -20"
echo -e "  • Cron setup     : 0 */6 * * * /root/scripts/proxmox-analyzer.sh --no-color >> /var/log/pve-analyzer.log 2>&1"
fi

echo -e "\n${BLUE}${BOLD}$(printf '═%.0s' {1..68})${NC}"
printf "${BLUE}${BOLD}  Selesai: %-30s Host: %-20s${NC}\n" "$(date '+%Y-%m-%d %H:%M:%S')" "${HOSTNAME_FULL}"
echo -e "${BLUE}${BOLD}$(printf '═%.0s' {1..68})${NC}\n"

# Exit code: 2=kritis, 1=peringatan, 0=normal
[[ ${#ISSUES[@]}   -gt 0 ]] && exit 2
[[ ${#WARNINGS[@]} -gt 0 ]] && exit 1
exit 0