
---

## 🔗 Blueprint Integrasi: proxmox-analyzer.sh + n8n + Telegram/WhatsApp

> Script v4.2 **sudah stabil** — ini rancangan untuk pengembangan berikutnya
> **Update v4.1**: Fitur `NODE_LABEL` sudah tersedia untuk identifikasi multi-node
> **Update v4.2**: SMART auto-detection RAID controller, perbaikan backup & format output
> **Hotfix Terkini**: `--alert-only` mematikan semua output log (*mute stdout*) sehingga *payload* data ke webhook n8n 100% murni tanpa *spam*.

---

### Gambaran Arsitektur

```
PROXMOX SERVER
┌──────────────────────────────────────┐
│  proxmox-analyzer.sh  ◄── Cronjob   │
│       │ output + exit code (0/1/2)  │
│       ▼                             │
│  run-analyzer.sh (wrapper baru)     │
└──────────────────────┬──────────────┘
                       │ HTTP POST (curl)
                       ▼
       n8n WORKFLOW (di server lain / VPS)
┌──────────────────────────────────────┐
│  Webhook → Parse → IF → Format      │
│                         ├─► Telegram │
│                         └─► WhatsApp │
└──────────────────────────────────────┘
```

---

### 3 Opsi Arsitektur

| Opsi | Cara | Ubah Script? | Terbaik untuk |
|------|------|-------------|---------------|
| **A** — n8n SSH ke Proxmox | n8n jadwalkan SSH, jalankan script | ❌ Tidak | Mulai cepat |
| **B** — Proxmox push webhook | Script kirim `curl` ke n8n saat ada masalah | ❌ Tidak (pakai wrapper) | **Produksi** |
| **C** — Script output JSON | Tambah flag `--json` di v5.0 | ✅ Di v5.0 nanti | Integrasi lebih lanjut |

**Rekomendasi: Mulai dari Opsi A, lalu upgrade ke B**

---

### Opsi A — Paling Cepat, Tidak Ubah Script

n8n SSH ke Proxmox secara terjadwal:

```
n8n Schedule ──► SSH ──► jalankan script ──► parse output ──► Telegram/WA
```

Node di n8n: `Schedule Trigger → SSH Execute → Code (parse) → IF → Telegram`

```bash
# Command yang dijalankan n8n via SSH:
bash /root/scripts/proxmox-analyzer.sh --alert-only --no-color
echo "EXITCODE:$?"
```

---

### Opsi B — Rekomendasi Produksi (Wrapper Script Baru)

Buat file baru `/root/scripts/run-analyzer.sh` — script utama tidak diubah:

```bash
#!/bin/bash
# Wrapper — proxmox-analyzer.sh tidak diubah sama sekali
# Set NODE_LABEL di sini sesuai nama node ini
NODE_LABEL="PVE-JKT-01"   # ← GANTI sesuai nama node

OUTPUT=$(bash /root/scripts/proxmox-analyzer.sh --alert-only --no-color --name="$NODE_LABEL")
EXIT_CODE=$?

if [[ $EXIT_CODE -gt 0 ]]; then
  LEVEL="PERINGATAN"
  [[ $EXIT_CODE -eq 2 ]] && LEVEL="KRITIS"

  curl -s -X POST "https://n8n.yourdomain.com/webhook/proxmox-alert" \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer YOUR_SECRET" \
    -d "{
      \"node_label\": \"${NODE_LABEL}\",
      \"host\": \"$(hostname)\",
      \"timestamp\": \"$(date '+%Y-%m-%d %H:%M:%S')\",
      \"exit_code\": ${EXIT_CODE},
      \"level\": \"${LEVEL}\",
      \"output\": $(echo "$OUTPUT" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))')
    }"
fi
```

Cronjob:

```bash
# Setiap 30 menit, hanya kirim jika ada masalah
*/30 * * * * bash /root/scripts/run-analyzer.sh
```

---

### Opsi C — v5.0: Tambah Flag `--json`

Di masa depan, script akan bisa output JSON terstruktur:

```bash
bash proxmox-analyzer.sh --json
```

Output:

```json
{
  "node_label": "PVE-JKT-01",
  "host": "pve01",
  "exit_code": 2,
  "status": "KRITIS",
  "issues": ["Backup gagal!", "Disk /dev/sda rusak!"],
  "warnings": ["RAM 85%", "IOWait 22%"],
  "metrics": {"cpu": 42.5, "ram": 85.2, "iowait": 22.1}
}
```

---

### Strategi Anti-Spam Notifikasi

Masalah umum: notifikasi dikirim setiap 30 menit meskipun masalah yang sama.

**Solusi di n8n — Only On Change:**

```javascript
// Code node di n8n, sebelum node Telegram
const lastStatus = $getWorkflowStaticData('global').lastStatus || 'OK';
const currentStatus = $json.exit_code > 0 ? 'ALERT' : 'OK';

if (currentStatus === lastStatus) return [];  // Tidak kirim jika status sama

$getWorkflowStaticData('global').lastStatus = currentStatus;
return $input.all();  // Kirim hanya saat status BERUBAH
```

**Atau Cooldown 4 jam:**

```javascript
const lastSent = $getWorkflowStaticData('global').lastSent || 0;
if (Date.now() - lastSent < 4 * 3600000) return [];

$getWorkflowStaticData('global').lastSent = Date.now();
return $input.all();
```

---

### Contoh Pesan Telegram Final (Multi-Node)

```
🔴 PROXMOX ALERT — KRITIS

🖥️ Node   : PVE-JKT-01
💻 Host   : pve01.datacenter.local
🕐 Waktu  : 20/04/2026 11:30:00

❌ MASALAH:
• Backup: 1 job GAGAL!
• Disk /dev/sda: Reallocated Sectors=3

⚠️ PERINGATAN:
• RAM 85% — Tinggi
• IOWait 22% — Mulai tinggi

💡 ssh root@pve01.datacenter.local untuk cek langsung
```

---

### Roadmap Pengembangan

```
v4.0 (Selesai)      →  v4.1 (Selesai)            →  v4.2 (Selesai)               →  v5.0 (Rencana)
Script enterprise        + --name / NODE_LABEL          + SMART auto-detect RAID          Tambah --json flag
Enterprise monitoring    + Identitas multi-node         + Fix backup detection            + Integrasi penuh n8n
                         + Header lebih informatif      + Fix printf/format output        + Dashboard Grafana
                                                        + SAS/SSD attributes
```

**Status Saat Ini:**
- [x] v4.0 — Script monitoring enterprise
- [x] v4.1 — NODE_LABEL untuk multi-node (`--name="PVE-xxx"`)
- [x] v4.2 — SMART auto-detection RAID + bug fixes
- [ ] v4.5 — Wrapper + Integrasi n8n (Webhook / SSH)
- [ ] v5.0 — Flag `--json` output terstruktur

**Changelog v4.2:**

| Kategori | Perubahan |
|----------|----------|
| **SMART** | Auto-detect disk via `smartctl --scan` (MegaRAID, 3ware, cciss, SAS, NVMe) |
| **SMART** | RAID virtual disk ditandai sebagai ℹ info, bukan ❌ kritis |
| **SMART** | Tambah Serial Number, SAS Grown Defects, SSD auto-detection |
| **SMART** | Fix parsing health status multi-line (`PASSED\ncheck.`) |
| **SMART** | Fix octal error pada attribute value berawalan 0 (contoh: `099`) |
| **SMART** | Fix parsing suhu untuk format SATA/SAS/NVMe yang berbeda |
| **Backup** | Expanded OK pattern: `Finished Backup of VM`, `archive file size` |
| **VM/CT** | Fix `%-10s` format string pada status VM/Container |
| **Network** | Fix `%8d` format string pada kolom RX/TX Error |
| **System** | **HOTFIX**: Fitur `--alert-only` menggunakan teknik *file descriptor redirection* (`exec 3>&1 >/dev/null`) untuk menyembunyikan log analisis dan log normal yang tidak relevan. |
| **Tampilan** | **HOTFIX**: Pembersihan kalimat *spammy* "Nama pembeda antar Proxmox" pada Header. |

**Pilihan WhatsApp Provider:**

| Provider | Biaya | Kemudahan | Resmi |
|----------|-------|-----------|-------|
| WhatsApp Business Cloud API | Gratis | Sedang (butuh Meta Business) | ✅ |
| Twilio WhatsApp | Berbayar | Mudah | ✅ |
| WA-Automate/Baileys | Gratis | Mudah | ❌ Risiko banned |
