#!/usr/bin/env python3
"""Unit tests for bridge v5 (Fase 1): v4 tool_calls suite + new checks:
 6. usage estimates present and positive (non-stream), total = p + c
 7. usage present in final stream chunk
 8. streamed long content arrives as multiple delta chunks that
    concatenate back to the exact original text
 9. queue cap: with 20 files already pending, a new POST gets HTTP 429
"""
import json, os, subprocess, sys, tempfile, threading, time, urllib.request, urllib.error

ROOT = os.path.dirname(os.path.abspath(__file__))
BRIDGE = os.path.join(ROOT, "..", "bridge", "bridge.py")
PORT = 18801
BASE_URL = f"http://127.0.0.1:{PORT}"

tmp = tempfile.mkdtemp(prefix="bridge-v5-test-")
queue = os.path.join(tmp, "queue")
os.makedirs(os.path.join(queue, "pending"))
os.makedirs(os.path.join(queue, "done"))

LONG = ("Ini jawaban panjang untuk menguji pseudo-streaming bridge v5. "
        "Kalimat ini sengaja dibuat bertele-tele supaya total karakternya "
        "melebihi tiga ratus dan bridge harus memecahnya menjadi beberapa "
        "chunk kecil yang dikirim satu per satu ke klien, bukan satu chunk "
        "besar di akhir seperti versi sebelumnya. Satu dua tiga empat lima.")

ANSWERS = {
    "TAG-CONTENT": {"content": "halo biasa"},
    "TAG-LONG": {"content": LONG},
    "TAG-TOOL": {"tool_calls": [{"id": "call_test123", "type": "function",
                                 "function": {"name": "terminal",
                                              "arguments": "{\"command\": \"df -h /\"}"}}]},
    "TAG-TOOL-DICTARGS": {"tool_calls": [{"function": {"name": "read_file",
                                                        "arguments": {"path": "/etc/hostname"}}}]},
}

def worker():
    while True:
        try:
            for name in os.listdir(os.path.join(queue, "pending")):
                rid = name[:-5]
                with open(os.path.join(queue, "pending", name)) as f:
                    req = json.load(f)["request"]
                text = json.dumps(req)
                for tag, ans in sorted(ANSWERS.items(), key=lambda kv: -len(kv[0])):
                    if tag in text:
                        with open(os.path.join(queue, "done", name), "w") as f:
                            json.dump(ans, f)
                        break
        except Exception:
            pass
        time.sleep(0.3)

threading.Thread(target=worker, daemon=True).start()

env = dict(os.environ, MUSE_BRIDGE_QUEUE=queue, MUSE_BRIDGE_PORT=str(PORT))
proc = subprocess.Popen([sys.executable, BRIDGE], env=env,
                        stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
try:
    for _ in range(50):
        try:
            with urllib.request.urlopen(BASE_URL + "/health", timeout=2) as r:
                assert json.load(r) == {"ok": True}
            break
        except Exception:
            time.sleep(0.3)
    else:
        print(proc.stdout.read() if proc.stdout else "")
        raise SystemExit("bridge did not come up")

    def post(body):
        req = urllib.request.Request(BASE_URL + "/v1/chat/completions",
                                     data=json.dumps(body).encode(),
                                     headers={"Content-Type": "application/json"})
        with urllib.request.urlopen(req, timeout=30) as r:
            if not body.get("stream"):
                return r.read().decode()
            buf = b""
            while b"[DONE]" not in buf:
                chunk = r.read1(4096) if hasattr(r, "read1") else r.read(4096)
                if not chunk:
                    break
                buf += chunk
            return buf.decode()

    counters = {"ok": 0, "fail": 0}
    def check(name, cond, extra=""):
        if cond:
            counters["ok"] += 1; print(f"ok   - {name}")
        else:
            counters["fail"] += 1; print(f"FAIL - {name} {extra}")

    # 1 plain content
    r = json.loads(post({"model": "muse", "messages": [{"role": "user", "content": "TAG-CONTENT hai"}]}))
    ch = r["choices"][0]
    check("plain content", ch["message"]["content"] == "halo biasa" and ch["finish_reason"] == "stop", str(r))

    # 6 usage estimates (non-stream)
    u = r.get("usage") or {}
    check("usage estimates positive",
          u.get("prompt_tokens", 0) > 0 and u.get("completion_tokens", 0) > 0
          and u.get("total_tokens") == u.get("prompt_tokens", 0) + u.get("completion_tokens", 0), str(u))

    # 2 tool_calls non-stream
    r = json.loads(post({"model": "muse",
                         "messages": [{"role": "user", "content": "TAG-TOOL cek disk"}],
                         "tools": [{"type": "function", "function": {"name": "terminal"}}]}))
    ch = r["choices"][0]
    tc = (ch["message"].get("tool_calls") or [{}])[0]
    check("tool_calls non-stream finish", ch["finish_reason"] == "tool_calls", str(r))
    check("tool_calls non-stream shape",
          tc.get("id") == "call_test123" and tc.get("type") == "function"
          and tc["function"]["name"] == "terminal"
          and tc["function"]["arguments"] == "{\"command\": \"df -h /\"}", str(tc))
    check("tool_calls content null", ch["message"].get("content") is None, str(ch["message"]))

    # 3 tool_calls stream
    raw = post({"model": "muse", "stream": True,
                "messages": [{"role": "user", "content": "TAG-TOOL cek disk"}]})
    check("tool_calls stream delta", '"tool_calls"' in raw and '"terminal"' in raw, raw[:400])
    check("tool_calls stream finish", '"finish_reason": "tool_calls"' in raw, raw[-400:])

    # 4 content stream
    raw = post({"model": "muse", "stream": True,
                "messages": [{"role": "user", "content": "TAG-CONTENT hai"}]})
    check("content stream", '"halo biasa"' in raw and '"finish_reason": "stop"' in raw, raw[:300])

    # 7+8 long content stream: multiple chunks, exact reassembly, usage in final chunk
    raw = post({"model": "muse", "stream": True,
                "messages": [{"role": "user", "content": "TAG-LONG cerita"}]})
    pieces, usage_seen = [], False
    for line in raw.splitlines():
        if not line.startswith("data: ") or "[DONE]" in line:
            continue
        obj = json.loads(line[6:])
        delta = obj["choices"][0].get("delta") or {}
        if delta.get("content"):
            pieces.append(delta["content"])
        if obj.get("usage"):
            usage_seen = True
    check("long content split into >=3 chunks", len(pieces) >= 3, f"pieces={len(pieces)}")
    check("chunks reassemble exactly", "".join(pieces) == LONG, "".join(pieces)[:120])
    check("usage in final stream chunk", usage_seen, raw[-300:])

    # 5 dict arguments normalized
    r = json.loads(post({"model": "muse",
                         "messages": [{"role": "user", "content": "TAG-TOOL-DICTARGS baca"}]}))
    tc = (r["choices"][0]["message"].get("tool_calls") or [{}])[0]
    args = tc.get("function", {}).get("arguments")
    check("dict arguments -> JSON string",
          isinstance(args, str) and json.loads(args) == {"path": "/etc/hostname"}, str(tc))
    check("missing id generated", bool(tc.get("id", "").startswith("call_")), str(tc))

    # 9 queue cap at 20
    fillers = []
    for i in range(20):
        p = os.path.join(queue, "pending", f"filler{i:02d}.json")
        with open(p, "w") as f:
            json.dump({"id": f"filler{i:02d}", "received_at": time.time(),
                       "request": {"messages": []}}, f)
        fillers.append(p)
    try:
        req = urllib.request.Request(BASE_URL + "/v1/chat/completions",
                                     data=json.dumps({"model": "muse", "messages": [
                                         {"role": "user", "content": "overflow"}]}).encode(),
                                     headers={"Content-Type": "application/json"})
        try:
            urllib.request.urlopen(req, timeout=10)
            check("queue cap 20 -> 429", False, "request was accepted")
        except urllib.error.HTTPError as e:
            check("queue cap 20 -> 429", e.code == 429, f"code={e.code}")
    finally:
        for p in fillers:
            try:
                os.remove(p)
            except Exception:
                pass

    print(f"----\n{counters['ok']} passed, {counters['fail']} failed")
    raise SystemExit(1 if counters["fail"] else 0)
finally:
    proc.terminate()
