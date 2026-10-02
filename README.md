# muse-bridge

> 🇮🇩 Versi Bahasa Indonesia: [README.id.md](README.id.md)

Turn **Muse** (the personal AI agent) into an OpenAI-compatible model provider —
`ms/muse` — inside a self-hosted [9Router](https://github.com/) instance, so a
Hermes agent can use it exactly like any API model (ChatGPT, DeepSeek, Claude, …),
**including native tool calls**.

There is no HTTP API for the agent itself, so this project bridges the gap with a
file queue: requests land as files, a polling courier wakes a worker agent, and
the worker's answer travels back as a standard chat completion.

## 📚 Full tutorial (beginner-proof, step by step)

- 🇬🇧 [TUTORIAL.md](docs/TUTORIAL.md) — complete walkthrough in plain English
- 🇮🇩 [TUTORIAL.id.md](docs/TUTORIAL.id.md) — tutorial lengkap bahasa Indonesia, bahasa bayi, pemula pasti bisa

The tutorials cover everything end to end: installing the bridge, SSH keys,
registering the provider in 9Router, the courier + worker rulebook, connecting
Hermes, the approval safety gate, seven pass/fail tests, daily use,
troubleshooting, and the honest limits.

## How it flows

```
Telegram ──► Hermes (VPS) ──► 9Router (VPS) ──► bridge :8765 ──► queue/pending/<id>.json
                                                                      │  (SSH, polled every 5s)
                                                                      ▼
                                              courier hook ──► worker agent (Muse)
                                                                      │
                                              queue/done/<id>.json ◄──┘
                                                                      │
        final answer / tool_calls ◄── bridge ◄── 9Router ◄── Hermes executes tools itself
```

- Every request carries a **unique id**. Answers (and tool calls) are written to
  `done/<same-id>.json` — routing is bound to the id, so responses **cannot be
  swapped between sessions**.
- Each request is forwarded **whole**: full message history, tool definitions,
  images — nothing is truncated or filtered, regardless of size (real sessions
  reach 100–220 KB per request and are served intact).
- A tool task takes **two round trips**: the worker replies with `tool_calls`,
  Hermes executes them on the VPS, then sends the results back in a follow-up
  request which the worker turns into a final answer. One round trip ≈ 25–35 s.

## Components

| Path | What it is |
|---|---|
| `bridge/bridge.py` | The bridge (current, v4): OpenAI-compatible HTTP server on the VPS, file queue, `tool_calls` passthrough for stream & non-stream |
| `bridge/bridge-v1.py` | The original text-only bridge, kept for history |
| `worker/worker-prompt-v3.txt` | The worker agent's rulebook (current): answer protocol, unlimited tool calls with batching discipline, media handling, honesty rules |
| `worker/worker-prompt-v2-backup-20261002.txt` | Previous worker prompt (rollback reference) |
| `tools/ssh-vps.sh`, `tools/scp-vps.sh` | Key-based SSH/SCP wrappers used by the courier to reach the VPS queue |
| `scripts/install-linux.sh` | One-shot bridge installer for Linux (folders + systemd service + health check) |
| `scripts/install-macos.sh` | One-shot bridge installer for macOS (folders + launchd agent + health check) |
| `scripts/install-windows.ps1` | One-shot bridge installer for Windows (folders + Scheduled Task + health check) |
| `tests/` | Unit tests (fake worker) + live test scripts against the bridge and via 9Router |
| `docs/FASE1-SAFETY-SPEC.md` | Design/safety notes for the next phase (parallel workers, larger queue) |

## Current capabilities (all live-verified 2026-10-02)

- ✅ Chat completions, stream & non-stream
- ✅ **Tool calls passthrough** — the agent loop works end-to-end through Hermes,
  `finish_reason: "tool_calls"`, streaming `delta.tool_calls` included; 9Router
  passes them through intact
- ✅ **Unlimited tool calls per answer** — independent checks batch into one turn
  (live test: 6 checks → 6 calls in a single response)
- ✅ **Images are actually seen** — image parts are extracted and viewed by the
  worker before answering (live test passed); videos are frame-sampled
- ✅ **No cross-session mix-ups** — proven with two concurrent sessions carrying
  different markers, in both content and tool-call arguments
- ✅ Honesty rules in the worker prompt: claims about the machine require real
  evidence (tool results or commands actually run) — learned from a real
  flip-flop incident, see below

## Safety model

The bridge/worker only **proposes** tool calls. Execution happens inside Hermes,
whose approval system (verified on this setup: `approvals.mode: manual`,
60 s timeout, cron denied) asks the owner before any dangerous command runs —
unless the owner explicitly enables `/yolo`. The worker prompt adds a second
layer: state-changing calls only when the task actually asks for them.

Queue limits (bridge): max **5** pending requests (excess gets HTTP 429),
**240 s** wait per request; the courier polls every 5 s and idle polls cost
nothing (a bash check — no agent wakes, no tokens).

## Short history

- **2026-10-01** — v1 live: text-only answers through the queue.
- **2026-10-02 (incident)** — the worker flip-flopped: refused, then claimed
  checks with partly fabricated results, then denied everything. Root causes: a
  fresh worker per request that sees only message text, plus an ambiguous
  prompt. Led to the honesty rules.
- **2026-10-02 (Option A)** — bridge v4 + worker prompt v2: real `tool_calls`
  loop, verified end-to-end from Telegram (Hermes executed `df -h` itself).
- **2026-10-02 (prompt v3)** — tool-call cap removed (unlimited), media rule
  added (nothing dropped silently; images viewed). Live tests 3/3 passed:
  batch calls, image understanding, no-swap concurrency.

## Notes

Personal infrastructure project, shared as-is. Host-specific values in the
samples are placeholders (`YOUR_VPS_IP`, example domains) — the live
deployment's real addresses are not published, so replace the placeholders
with your own values when you set it up.
No secrets are stored in this repository: API keys live outside it in
permission-restricted files on the hosts themselves.
