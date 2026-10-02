#!/bin/bash
# Regression + tool_calls tests against the VPS bridge directly (127.0.0.1:8765).
# Run ON the VPS. Each request waits for the real bridge worker.
set -u
B=http://127.0.0.1:8765/v1/chat/completions
H='Content-Type: application/json'

echo "=== T1 plain non-stream ==="
curl -s --max-time 260 -X POST "$B" -H "$H" -d '{"model":"muse","stream":false,"messages":[{"role":"user","content":"Tes regresi bridge v2: jawab singkat saja, 2+2 berapa?"}]}'
echo
echo "=== T2 plain stream ==="
curl -sN --max-time 260 -X POST "$B" -H "$H" -d '{"model":"muse","stream":true,"messages":[{"role":"user","content":"Tes regresi stream: jawab singkat, ibukota Jepang apa?"}]}' | head -c 1200
echo
echo "=== T3 tool_calls non-stream ==="
curl -s --max-time 260 -X POST "$B" -H "$H" -d '{"model":"muse","stream":false,"messages":[{"role":"user","content":"Cek pemakaian disk VPS ini sekarang, pakai tool yang tersedia."}],"tools":[{"type":"function","function":{"name":"run_terminal_command","description":"Run a shell command on this VPS and return its stdout","parameters":{"type":"object","properties":{"command":{"type":"string","description":"The shell command to run"}},"required":["command"]}}}]}'
echo
echo "=== T4 tool result follow-up ==="
curl -s --max-time 260 -X POST "$B" -H "$H" -d '{"model":"muse","stream":false,"messages":[{"role":"user","content":"Cek pemakaian disk VPS ini sekarang, pakai tool yang tersedia."},{"role":"assistant","content":null,"tool_calls":[{"id":"call_aaaaaaaaaaaaaaaaaaaaaaaa","type":"function","function":{"name":"run_terminal_command","arguments":"{\"command\": \"df -h /\"}"}}]},{"role":"tool","tool_call_id":"call_aaaaaaaaaaaaaaaaaaaaaaaa","content":"Filesystem      Size  Used Avail Use% Mounted on\n/dev/sda1       193G   53G  140G  28% /"}],"tools":[{"type":"function","function":{"name":"run_terminal_command","description":"Run a shell command on this VPS and return its stdout","parameters":{"type":"object","properties":{"command":{"type":"string","description":"The shell command to run"}},"required":["command"]}}}]}'
echo
echo "=== ALL DONE ==="
