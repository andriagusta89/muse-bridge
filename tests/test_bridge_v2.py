#!/usr/bin/env python3
"""Local unit test for bridge-v2.py tool_calls passthrough.

Runs the real bridge on a scratch port with a temp queue; a fake worker
thread watches pending/ and writes canned done files. Asserts:
 1. plain chat (content done) -> classic response, finish_reason stop
 2. tool_calls done, non-stream -> message.tool_calls + finish_reason tool_calls
 3. tool_calls done, stream -> SSE delta.tool_calls + finish_reason tool_calls
 4. content done, stream -> classic SSE content + stop
 5. tool_calls with dict arguments -> arguments normalized to JSON string
"""
import json, os, subprocess, sys, tempfile, threading, time, urllib.request

ROOT = os.path.dirname(os.path.abspath(__file__))
BRIDGE = os.path.join(ROOT, "bridge-v2.py")
PORT = 18799
BASE_URL = f"http://127.0.0.1:{PORT}"

tmp = tempfile.mkdtemp(prefix="bridge-v2-test-")
queue = os.path.join(tmp, "queue")
os.makedirs(os.path.join(queue, "pending"))
os.makedirs(os.path.join(queue, "done"))

# canned answer per test tag embedded in the user message
ANSWERS = {
    "TAG-CONTENT": {"content": "halo biasa"},
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
            # SSE: read incrementally until [DONE] (server keeps socket open)
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

    # 5 dict arguments normalized
    r = json.loads(post({"model": "muse",
                         "messages": [{"role": "user", "content": "TAG-TOOL-DICTARGS baca"}]}))
    tc = (r["choices"][0]["message"].get("tool_calls") or [{}])[0]
    args = tc.get("function", {}).get("arguments")
    check("dict arguments -> JSON string",
          isinstance(args, str) and json.loads(args) == {"path": "/etc/hostname"}, str(tc))
    check("missing id generated", bool(tc.get("id", "").startswith("call_")), str(tc))

    print(f"----\n{counters['ok']} passed, {counters['fail']} failed")
    raise SystemExit(1 if counters["fail"] else 0)
finally:
    proc.terminate()
