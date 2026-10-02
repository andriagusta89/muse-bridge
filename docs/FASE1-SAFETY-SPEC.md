# Fase 1 — Safety-first spec untuk ms/muse tool_calls (DRAF, belum deploy)
Disiapkan 2026-10-02 sore, setelah Opsi A live & terverifikasi E2E 16:14-16:15 WIB.
Status prompt live saat spec ini dibuat: ~/hooks/definitions/muse-bridge-vps-queue.json
sudah berisi protokol v2 (tool_calls maks 3, nama hanya dari request.tools,
honesty rules) — TAPI belum ada aturan konfirmasi untuk aksi destruktif.

## Kenapa ini langkah 0, sebelum Fase 1 lain
- Hermes di VPS jalan sebagai root; tool_calls dari worker sekarang dieksekusi
  Hermes beneran (bukti: df -h di profil negro, 2026-10-02 16:15 WIB).
- Risiko yang sudah disebut di chat: (1) worker salah pilih tool = tindakan
  nyata, bukan omongan; (2) retry Hermes bisa mengeksekusi perintah yang sama
  dua kali; (3) antrean bridge maks 5 per run — 3 profil barengan bisa 429.

## Patch prompt yang diusulkan (sisipkan sebagai aturan 3d, sebelum 4a/4b)
3d. DESTRUCTIVE-ACTION GUARDRAIL:
   - READ-ONLY / AMAN (boleh langsung tool_call): perintah inspeksi yang tidak
     mengubah state — df, du, ls, cat/head/tail log, systemctl status/is-active,
     ps, free, uptime, ss -tlnp, journalctl tanpa --rotate/--vacuum.
   - DESTRUKTIF (DILARANG langsung tool_call): rm/rmdir, mv yang menimpa,
     penulisan/pengeditan file (write_file, patch, sed -i, tee, > redirect),
     systemctl restart/stop/start/disable/mask, kill/pkill, reboot/shutdown,
     chmod/chown, user/package changes (apt, pip install), docker rm/stop/prune.
   - Untuk permintaan destruktif: JANGAN keluarkan tool_calls. Balas CONTENT
     yang menyebut persis perintah/tool + targetnya dan minta konfirmasi
     eksplisit user di chat itu (mis. "balas: ya, jalanin").
   - Tool_call destruktif hanya boleh keluar bila di messages SUDAH ada
     konfirmasi eksplisit user untuk perintah+target yang sama persis.
     Konfirmasi umum ("terserah", "beresin aja") TIDAK cukup.
   - IDEMPOTENCY: bila messages sudah memuat role:tool untuk perintah yang
     sama, jangan keluarkan tool_call yang sama lagi — rangkum hasilnya (kasus a).

## Sisa Fase 1 (setelah guardrail, sesuai urutan di chat 2026-10-02 16:20 WIB)
1. Hormati tool_choice dari request (wajib-tool = tidak boleh balas teks).
2. Naikkan batas antrean bridge dari 5 (cek dulu di bridge.py VPS; backup dulu).
3. Streaming dipecah beberapa chunk (bukan 1 chunk gede di akhir).
4. Usage/token diisi estimasi wajar (bukan nol).
5. Gambar di chat diekstrak jadi file agar bisa dilihat worker.
6. Paralel per-profil: ditunda ke Fase 2 bila butuh pekerja standby.
Tiap langkah: unit test lokal dulu (pola test_bridge_v2.py 9/9), tes regresi
chat biasa stream+non-stream, backup bridge.py.bak-<tanggal>, restart hanya
muse-bridge.service, rollback = restore backup + restart (~1 menit).

## Yang TIDAK berubah
VPS: tidak ada port/service/paket baru. Hermes, 9Router, node ms/muse, combo:
utuh. Perubahan prompt hanya di VM Muse (hook definition), perubahan bridge
hanya bila langkah 2/3/4 dipilih.
