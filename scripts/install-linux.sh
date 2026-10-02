#!/usr/bin/env bash
# muse-bridge installer — Linux (server side: the bridge on your VPS/machine)
#
# What it does:
#   1. Creates the queue folders (pending/ + done/)
#   2. Installs bridge/bridge.py (backs up an existing one first)
#   3. Installs + starts a systemd service "muse-bridge" (localhost only)
#   4. Health-checks http://127.0.0.1:<PORT>/health
#
# Usage (from the repo root):
#   sudo bash scripts/install-linux.sh
#
# Optional env vars:
#   BRIDGE_DIR=/opt/muse-bridge   install location
#   PORT=8765                      bridge port (localhost)
#   SKIP_SERVICE=1                 skip systemd (folders + files only)
#
# This installs ONLY the bridge (server side). The courier + worker live in
# the Muse environment — see docs/TUTORIAL.md Part 5.
set -euo pipefail

BRIDGE_DIR="${BRIDGE_DIR:-/opt/muse-bridge}"
PORT="${PORT:-8765}"
SERVICE="muse-bridge"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="$REPO_ROOT/bridge/bridge.py"

SUDO=""
if [ "$(id -u)" -ne 0 ]; then SUDO="sudo"; fi

echo "== muse-bridge installer (Linux) =="
echo "Install dir : $BRIDGE_DIR"
echo "Port        : $PORT (localhost only)"

command -v python3 >/dev/null || { echo "ERROR: python3 not found. Install Python 3 first."; exit 1; }
[ -f "$SRC" ] || { echo "ERROR: $SRC not found. Run this from inside the muse-bridge repo."; exit 1; }

echo "-- creating folders"
$SUDO mkdir -p "$BRIDGE_DIR/queue/pending" "$BRIDGE_DIR/queue/done"

if [ -f "$BRIDGE_DIR/bridge.py" ]; then
  BAK="$BRIDGE_DIR/bridge.py.bak-$(date +%Y%m%d-%H%M%S)"
  echo "-- existing bridge.py found, backing up to $BAK"
  $SUDO cp "$BRIDGE_DIR/bridge.py" "$BAK"
fi

echo "-- installing bridge.py"
$SUDO cp "$SRC" "$BRIDGE_DIR/bridge.py"

if [ "${SKIP_SERVICE:-0}" = "1" ]; then
  echo "-- SKIP_SERVICE=1: skipping systemd setup"
else
  command -v systemctl >/dev/null || { echo "ERROR: systemd not found. Re-run with SKIP_SERVICE=1 and start the bridge manually."; exit 1; }
  echo "-- writing systemd unit /etc/systemd/system/$SERVICE.service"
  $SUDO tee "/etc/systemd/system/$SERVICE.service" >/dev/null <<EOF
[Unit]
Description=Muse bridge for 9Router
After=network.target

[Service]
ExecStart=/usr/bin/python3 $BRIDGE_DIR/bridge.py
Environment=MUSE_BRIDGE_QUEUE=$BRIDGE_DIR/queue
Environment=MUSE_BRIDGE_PORT=$PORT
Restart=always
User=root

[Install]
WantedBy=multi-user.target
EOF
  $SUDO systemctl daemon-reload
  $SUDO systemctl enable --now "$SERVICE"
fi

echo "-- health check"
ok=0
for _ in $(seq 1 15); do
  if curl -s --max-time 2 "http://127.0.0.1:$PORT/health" >/dev/null 2>&1; then ok=1; break; fi
  sleep 1
done
if [ "$ok" = "1" ]; then
  echo "OK: bridge is answering on http://127.0.0.1:$PORT/health"
else
  echo "WARNING: bridge did not answer the health check yet."
  echo "Check: systemctl status $SERVICE   /   journalctl -u $SERVICE -n 50"
fi

cat <<EOF

Done. Next steps:
  1. In the 9Router dashboard, add an OpenAI-compatible provider:
     name "muse", prefix "ms", base URL http://127.0.0.1:$PORT/v1
  2. Create the combo "muse" -> ["ms/muse"] and a 9Router API key.
  3. On the Muse side, install the courier hook + worker prompt
     (docs/TUTORIAL.md Part 5) and point Hermes at the new model.
Full tutorial: docs/TUTORIAL.md (EN) / docs/TUTORIAL.id.md (ID)
EOF
