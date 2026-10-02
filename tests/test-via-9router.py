#!/usr/bin/env python3
"""T5/T6: tool_calls through the VPS 9Router (public URL), like Hermes would.
Reads the test API key from ~/.config/muse-bridge-vps/test_key (never prints it).
Reads SSE incrementally until [DONE].
"""
import json, urllib.request, urllib.error, os, sys

KEY = open(os.environ.get("TEST_KEY_FILE",
             os.path.expanduser("~/.config/muse-bridge-vps/test_key"))).read().strip()
URL = os.environ.get("NR_URL", "https://your-9router.example.com/v1/chat/completions")
TOOLS = [{"type": "function", "function": {
    "name": "run_terminal_command",
    "description": "Run a shell command on this VPS and return its stdout",
    "parameters": {"type": "object",
                   "properties": {"command": {"type": "string"}},
                   "required": ["command"]}}}]


def post(body):
    req = urllib.request.Request(URL, data=json.dumps(body).encode(),
                                 headers={"Content-Type": "application/json",
                                          "Authorization": "Bearer " + KEY})
    try:
        with urllib.request.urlopen(req, timeout=280) as r:
            if not body.get("stream"):
                return r.read().decode()
            buf = b""
            while b"[DONE]" not in buf:
                chunk = r.read1(4096) if hasattr(r, "read1") else r.read(4096)
                if not chunk:
                    break
                buf += chunk
            return buf.decode()
    except urllib.error.HTTPError as e:
        return f"HTTP {e.code}: " + e.read().decode()[:500]


print("=== T5 via 9Router, tool_calls, non-stream ===")
out = post({"model": "muse", "stream": False,
            "messages": [{"role": "user",
                          "content": "Cek sisa disk VPS ini pakai tool yang tersedia ya."}],
            "tools": TOOLS})
print(out[:1500])
try:
    ch = json.loads(out)["choices"][0]
    tc = ch["message"].get("tool_calls")
    print("VERDICT T5:", "PASS" if (ch["finish_reason"] == "tool_calls" and tc
          and tc[0]["function"]["name"] == "run_terminal_command") else "FAIL")
except Exception as e:
    print("VERDICT T5: FAIL (parse)", e)

print("=== T6 via 9Router, tool_calls, stream ===")
out = post({"model": "muse", "stream": True,
            "messages": [{"role": "user",
                          "content": "Cek uptime VPS ini pakai tool yang tersedia ya."}],
            "tools": TOOLS})
print(out[:1500])
print("VERDICT T6:", "PASS" if ('"tool_calls"' in out and 'run_terminal_command' in out
      and '"finish_reason": "tool_calls"' in out.replace('\\"', '"')) else "CHECK-ABOVE")
