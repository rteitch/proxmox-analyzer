---

## 🔗 Blueprint Integrasi: proxmox-analyzer.sh + n8n + Telegram/WhatsApp

> Script v4.0 **tidak diubah** — ini rancangan untuk pengembangan berikutnya

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

OUTPUT=$(bash /root/scripts/proxmox-analyzer.sh --alert-only --no-color)
EXIT_CODE=$?

if [[ $EXIT_CODE -gt 0 ]]; then
  LEVEL="PERINGATAN"
  [[ $EXIT_CODE -eq 2 ]] && LEVEL="KRITIS"

  curl -s -X POST "https://n8n.yourdomain.com/webhook/proxmox-alert" \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer YOUR_SECRET" \
    -d "{
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
  "host": "pve01", "exit_code": 2, "status": "KRITIS",
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

### Contoh Pesan Telegram Final

```
🔴 PROXMOX ALERT — KRITIS

🖥️ Host: pve01
🕐 Waktu: 20/04/2026 11:30:00

❌ MASALAH:
• Backup: 1 job GAGAL!
• Disk /dev/sda: Reallocated Sectors=3

⚠️ PERINGATAN:
• RAM 85% — Tinggi
• IOWait 22% — Mulai tinggi

💡 ssh root@pve01 untuk cek langsung
```

---

### Roadmap Pengembangan

```
v4.0 (Sekarang)     →  v4.5 (Fase 1)           →  v5.0 (Fase 2)
Script sudah ada        Buat wrapper.sh              Tambah --json flag
                        + n8n via SSH/Webhook        + Integrasi penuh
                        + Alert Telegram             + Dashboard Grafana
```

**Pilihan WhatsApp Provider:**

| Provider | Biaya | Kemudahan | Resmi |
|----------|-------|-----------|-------|
| WhatsApp Business Cloud API | Gratis | Sedang (butuh Meta Business) | ✅ |
| Twilio WhatsApp | Berbayar | Mudah | ✅ |
| WA-Automate/Baileys | Gratis | Mudah | ❌ Risiko banned |
