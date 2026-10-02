#!/usr/bin/env python3
"""Live tests for worker prompt v3 (unlimited tool calls + media) against the
VPS bridge directly (127.0.0.1:8765). Run ON the VPS. Answers come from the
real bridge worker via the hook."""
import base64, json, struct, zlib, urllib.request
from concurrent.futures import ThreadPoolExecutor

B = "http://127.0.0.1:8765/v1/chat/completions"
TOOL = {"type": "function", "function": {
    "name": "run_terminal_command",
    "description": "Run a shell command on this VPS and return its stdout",
    "parameters": {"type": "object", "properties": {
        "command": {"type": "string", "description": "The shell command to run"}},
        "required": ["command"]}}}

def post(payload, timeout=280):
    req = urllib.request.Request(B, data=json.dumps(payload).encode(),
                                 headers={"Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return json.loads(r.read().decode())

def solid_png(rgb, w=64, h=64):
    def chunk(typ, data):
        c = struct.pack(">I", len(data)) + typ + data
        return c + struct.pack(">I", zlib.crc32(typ + data) & 0xffffffff)
    ihdr = struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0)
    raw = b"".join(b"\x00" + bytes(rgb) * w for _ in range(h))
    return (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", ihdr) +
            chunk(b"IDAT", zlib.compress(raw)) + chunk(b"IEND", b""))

print("=== T5 BATCH tool calls (>3 in one answer) ===", flush=True)
r = post({"model": "muse", "stream": False, "messages": [
    {"role": "user", "content": "Cek SEMUA ini di VPS sekarang, pakai tool untuk "
     "masing-masing dalam satu giliran: (1) pemakaian disk, (2) pemakaian RAM, "
     "(3) uptime, (4) status service 9router, (5) status service muse-bridge, "
     "(6) siapa user yang sedang login. Jalanin semuanya sekaligus."}],
    "tools": [TOOL]})
msg = r["choices"][0]["message"]
tcs = msg.get("tool_calls") or []
print("finish:", r["choices"][0].get("finish_reason"), "| tool_calls:", len(tcs), flush=True)
for tc in tcs:
    print("  -", tc["function"]["arguments"][:110], flush=True)
print("T5 PASS" if len(tcs) >= 4 else "T5 FAIL (expected >=4 calls)", flush=True)

print("=== T6 IMAGE understanding ===", flush=True)
b64 = base64.b64encode(solid_png((0, 0, 255))).decode()
r = post({"model": "muse", "stream": False, "messages": [
    {"role": "user", "content": [
        {"type": "text", "text": "Gambar ini warna dominannya apa? Jawab singkat."},
        {"type": "image_url", "image_url": {"url": "data:image/png;base64," + b64}}]}]})
ans = (r["choices"][0]["message"].get("content") or "")
print("answer:", ans[:300], flush=True)
print("T6 PASS" if ("biru" in ans.lower() or "blue" in ans.lower()) else "T6 FAIL", flush=True)

print("=== T7 NO-SWAP: two sessions at once ===", flush=True)
def req_a():
    return post({"model": "muse", "stream": False, "messages": [
        {"role": "user", "content": "Kode rahasia sesi ini adalah ALPHA-7734. "
         "Sebutkan kembali kode rahasia sesi ini, hanya kodenya saja."}]})
def req_b():
    return post({"model": "muse", "stream": False, "messages": [
        {"role": "user", "content": "Kode rahasia sesi ini adalah BETA-2210. Pakai tool "
         "untuk menjalankan perintah: echo KODE-BETA-2210"}],
        "tools": [TOOL]})
with ThreadPoolExecutor(2) as ex:
    fa, fb = ex.submit(req_a), ex.submit(req_b)
    ra, rb = fa.result(), fb.result()
ans_a = (ra["choices"][0]["message"].get("content") or "")
tcs_b = rb["choices"][0]["message"].get("tool_calls") or []
args_b = " ".join(tc["function"]["arguments"] for tc in tcs_b)
print("A answer:", ans_a[:200], flush=True)
print("B tool args:", args_b[:200], flush=True)
ok_a = "ALPHA-7734" in ans_a and "BETA" not in ans_a
ok_b = "BETA-2210" in args_b and "ALPHA" not in args_b
print("T7 PASS" if (ok_a and ok_b) else "T7 FAIL", flush=True)
print("=== ALL DONE ===", flush=True)
