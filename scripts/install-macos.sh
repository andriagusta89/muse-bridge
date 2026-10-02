#!/usr/bin/env bash
# muse-bridge installer — macOS (server side: the bridge on your Mac)
#
# What it does:
#   1. Creates the queue folders (pending/ + done/) under ~/muse-bridge
#   2. Installs bridge/bridge.py (backs up an existing one first)
#   3. Installs + starts a launchd agent "ai.muse.bridge" (localhost only)
#   4. Health-checks http://127.0.0.1:<PORT>/health
#
# Usage (from the repo root):
#   bash scripts/install-macos.sh
#
# Optional env vars:
#   BRIDGE_DIR=$HOME/muse-bridge   install location
#   PORT=8765                      bridge port (localhost)
#
# This installs ONLY the bridge (server side). The courier + worker live in
# the Muse environment — see docs/TUTORIAL.md Part 5.
set -euo pipefail

BRIDGE_DIR="${BRIDGE_DIR:-$HOME/muse-bridge}"
PORT="${PORT:-8765}"
LABEL="ai.muse.bridge"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="$REPO_ROOT/bridge/bridge.py"

echo "== muse-bridge installer (macOS) =="
echo "Install dir : $BRIDGE_DIR"
echo "Port        : $PORT (localhost only)"

PYTHON_BIN="$(command -v python3 || true)"
[ -n "$PYTHON_BIN" ] || { echo "ERROR: python3 not found. Install Python 3 (e.g. 'brew install python' or python.org)."; exit 1; }
[ -f "$SRC" ] || { echo "ERROR: $SRC not found. Run this from inside the muse-bridge repo."; exit 1; }

echo "-- creating folders"
mkdir -p "$BRIDGE_DIR/queue/pending" "$BRIDGE_DIR/queue/done"

if [ -f "$BRIDGE_DIR/bridge.py" ]; then
  BAK="$BRIDGE_DIR/bridge.py.bak-$(date +%Y%m%d-%H%M%S)"
  echo "-- existing bridge.py found, backing up to $BAK"
  cp "$BRIDGE_DIR/bridge.py" "$BAK"
fi

echo "-- installing bridge.py"
cp "$SRC" "$BRIDGE_DIR/bridge.py"

echo "-- writing launchd plist $PLIST"
mkdir -p "$HOME/Library/LaunchAgents"
cat > "$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>$LABEL</string>
  <key>ProgramArguments</key>
  <array>
    <string>$PYTHON_BIN</string>
    <string>$BRIDGE_DIR/bridge.py</string>
  </array>
  <key>EnvironmentVariables</key>
  <dict>
    <key>MUSE_BRIDGE_QUEUE</key><string>$BRIDGE_DIR/queue</string>
    <key>MUSE_BRIDGE_PORT</key><string>$PORT</string>
  </dict>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
  <key>StandardOutPath</key><string>$BRIDGE_DIR/bridge.log</string>
  <key>StandardErrorPath</key><string>$BRIDGE_DIR/bridge.log</string>
</dict>
</plist>
EOF

launchctl unload "$PLIST" >/dev/null 2>&1 || true
launchctl load "$PLIST"

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
  echo "Check the log: $BRIDGE_DIR/bridge.log"
fi

cat <<EOF

Done. Next steps:
  1. In the 9Router dashboard, add an OpenAI-compatible provider:
     name "muse", prefix "ms", base URL http://127.0.0.1:$PORT/v1
  2. Create the combo "muse" -> ["ms/muse"] and a 9Router API key.
  3. On the Muse side, install the courier hook + worker prompt
     (docs/TUTORIAL.md Part 5) and point Hermes at the new model.
  Stop/start later with: launchctl unload|load $PLIST
Full tutorial: docs/TUTORIAL.md (EN) / docs/TUTORIAL.id.md (ID)
EOF
