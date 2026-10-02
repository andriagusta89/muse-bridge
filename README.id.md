# muse-bridge

> 🇬🇧 English version: [README.md](README.md)

Mengubah **Muse** (agent AI personal) menjadi provider model yang kompatibel
dengan OpenAI — `ms/muse` — di dalam [9Router](https://github.com/) yang
di-host sendiri, supaya agent Hermes bisa memakainya persis seperti model API
lain (ChatGPT, DeepSeek, Claude, …), **termasuk tool calls bawaan**.

Agent-nya sendiri tidak punya API HTTP, jadi project ini menjembatani lewat
antrean file: request masuk sebagai file, kurir polling membangunkan agent
pekerja, dan jawaban pekerja kembali sebagai chat completion standar.

## 📚 Tutorial lengkap (anti-nyasar, langkah demi langkah)

- 🇮🇩 [TUTORIAL.id.md](docs/TUTORIAL.id.md) — tutorial lengkap bahasa Indonesia, bahasa bayi, pemula pasti bisa
- 🇬🇧 [TUTORIAL.md](docs/TUTORIAL.md) — complete walkthrough in plain English

Tutorialnya membahas semuanya dari ujung ke ujung: pasang bridge, kunci SSH,
daftarin provider di 9Router, kurir + buku aturan pekerja, nyambungin Hermes,
pengaman persetujuan, tujuh tes lulus/gagal, pemakaian sehari-hari, pemecahan
masalah, dan batas-batas jujurnya.

## Cara mengalirnya

```
Telegram ──► Hermes (VPS) ──► 9Router (VPS) ──► bridge :8765 ──► queue/pending/<id>.json
                                                                      │  (SSH, dicek tiap 5 detik)
                                                                      ▼
                                              hook kurir ──► agent pekerja (Muse)
                                                                      │
                                              queue/done/<id>.json ◄──┘
                                                                      │
        jawaban final / tool_calls ◄── bridge ◄── 9Router ◄── Hermes eksekusi tool-nya sendiri
```

- Setiap request punya **ID unik**. Jawaban (dan tool call) ditulis ke
  `done/<id-yang-sama>.json` — jalurnya terikat ID, jadi jawaban **tidak bisa
  ketuker antar sesi**.
- Setiap request diteruskan **utuh**: seluruh riwayat pesan, definisi tool,
  gambar — tidak ada yang dipotong atau disaring, seberapa pun besarnya (sesi
  asli mencapai 100–220 KB per request dan tetap dilayani utuh).
- Tugas yang pakai tool butuh **dua putaran**: pekerja membalas dengan
  `tool_calls`, Hermes menjalankannya di VPS, lalu mengirim hasilnya kembali
  dalam request lanjutan yang diubah pekerja jadi jawaban final. Satu putaran
  ≈ 25–35 detik.

## Isi repo

| Path | Isinya |
|---|---|
| `bridge/bridge.py` | Bridge yang jalan sekarang (v4): server HTTP kompatibel OpenAI di VPS, antrean file, penerus `tool_calls` untuk stream & non-stream |
| `bridge/bridge-v1.py` | Bridge asli yang cuma bisa teks, disimpan sebagai sejarah |
| `worker/worker-prompt-v3.txt` | Buku aturan agent pekerja (terbaru): protokol jawaban, tool call tanpa batas dengan disiplin penggabungan, penanganan media, aturan kejujuran |
| `worker/worker-prompt-v2-backup-20261002.txt` | Prompt pekerja sebelumnya (referensi rollback) |
| `tools/ssh-vps.sh`, `tools/scp-vps.sh` | Wrapper SSH/SCP berbasis key yang dipakai kurir untuk menjangkau antrean di VPS |
| `tests/` | Unit test (pekerja palsu) + script tes live ke bridge dan lewat 9Router |
| `docs/FASE1-SAFETY-SPEC.md` | Catatan desain/keamanan fase berikutnya (pekerja paralel, antrean lebih besar) |

## Kemampuan sekarang (semua terverifikasi live 2026-10-02)

- ✅ Chat completion, stream & non-stream
- ✅ **Penerus tool calls** — loop agent jalan end-to-end lewat Hermes,
  `finish_reason: "tool_calls"`, termasuk `delta.tool_calls` saat streaming;
  9Router meneruskannya utuh
- ✅ **Tool call tanpa batas per jawaban** — cek-cek yang saling bebas digabung
  jadi satu giliran (tes live: 6 cek → 6 perintah dalam satu jawaban)
- ✅ **Gambar benar-benar dilihat** — bagian gambar diekstrak dan dilihat
  pekerja sebelum menjawab (tes live lulus); video diambil sampel frame-nya
- ✅ **Tidak ada ketuker antar sesi** — dibuktikan dengan dua sesi bersamaan
  berkode berbeda, bersih di jawaban teks maupun di argumen tool call
- ✅ Aturan kejujuran di prompt pekerja: klaim soal mesin wajib ada bukti asli
  (hasil tool atau perintah yang benar-benar dijalankan) — pelajaran dari
  insiden beneran, lihat di bawah

## Model keamanan

Bridge/pekerja cuma **mengusulkan** tool call. Eksekusinya terjadi di dalam
Hermes, yang sistem persetujuannya (terverifikasi di setup ini:
`approvals.mode: manual`, timeout 60 detik, cron ditolak) menanya pemilik dulu
sebelum perintah berbahaya dijalankan — kecuali pemilik sengaja menyalakan
`/yolo`. Prompt pekerja menambah lapis kedua: perintah yang mengubah-ubah
hanya kalau tugasnya memang meminta itu.

Batas antrean (bridge): maks **5** request menunggu (kelebihannya dapat
HTTP 429), tunggu **240 detik** per request; kurir mengecek tiap 5 detik dan
pengecekan kosong tidak makan biaya apa pun (cek bash biasa — tidak ada agent
yang bangun, tidak ada token).

## Sejarah singkat

- **2026-10-01** — v1 live: jawaban teks saja lewat antrean.
- **2026-10-02 (insiden)** — pekerja berubah-ubah sikap: menolak, lalu mengaku
  sudah mengecek dengan hasil sebagian karangan, lalu membantah semuanya. Akar
  masalahnya: pekerja baru di setiap request yang hanya melihat teks pesan,
  plus prompt yang ambigu. Dari sini lahir aturan kejujuran.
- **2026-10-02 (Opsi A)** — bridge v4 + prompt pekerja v2: loop `tool_calls`
  beneran, terverifikasi end-to-end dari Telegram (Hermes menjalankan `df -h`
  sendiri).
- **2026-10-02 (prompt v3)** — batas tool call dicabut (tanpa batas), aturan
  media ditambahkan (tidak ada kiriman yang dibuang diam-diam; gambar
  dilihat). Tes live 3/3 lulus: batch tool call, pemahaman gambar, dan
  kebersamaan tanpa ketuker.

## Catatan

Project infrastruktur personal, dibagikan apa adanya. Nilai khusus host di
file contoh sudah diganti placeholder (`YOUR_VPS_IP`, domain contoh) —
alamat asli deployment yang jalan tidak diterbitkan, jadi ganti
placeholder-nya dengan nilai kamu sendiri pas kamu setup.
Tidak ada rahasia yang disimpan di repo ini: API key
berada di luar repo, di file berizin terbatas di host masing-masing.
