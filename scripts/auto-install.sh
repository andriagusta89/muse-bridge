#!/usr/bin/env bash
# muse-bridge AUTO-INSTALL (Linux & macOS) — one command, guided.
#
# What it does for you automatically:
#   1. Detects your OS and runs the right bridge installer
#      (folders + bridge.py + always-on service + health check)
#   2. Walks you through the 3 short steps that cannot be automated
#      (9Router dashboard values, Muse-side hook, Hermes model)
#      with the exact values to paste
#   3. Tests the bridge at the end (health + model list)
#
# Usage (from the repo root):
#   bash scripts/auto-install.sh
#
# Pass-through env vars for the installers: BRIDGE_DIR, PORT, SKIP_SERVICE.
#   SKIP_GUIDE=1   skip the guided part (bridge install + tests only)
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PORT="${PORT:-8765}"

echo "=============================================="
echo "  muse-bridge AUTO-INSTALL"
echo "  Muse as a model inside your 9Router"
echo "=============================================="
echo

OS="$(uname -s)"
case "$OS" in
  Linux)  INSTALLER="$REPO_ROOT/scripts/install-linux.sh" ;;
  Darwin) INSTALLER="$REPO_ROOT/scripts/install-macos.sh" ;;
  *) echo "ERROR: this script supports Linux and macOS. On Windows use scripts\\auto-install.ps1"; exit 1 ;;
esac
echo "Detected OS: $OS"
echo "Step 1/3: installing the bridge (folders, service, health check)..."
echo
bash "$INSTALLER"

if [ "${SKIP_GUIDE:-0}" != "1" ]; then
  cat <<EOF

==============================================
Step 2/3: three short steps only YOU can do
(automation cannot click your dashboard for you)
==============================================

A) In the 9Router dashboard (on this machine), add a provider:
     Type     : OpenAI-compatible
     Name     : muse
     Prefix   : ms
     Base URL : http://127.0.0.1:$PORT/v1
   Then add a connection (auth type: API key, any value), and a combo:
     Combo name : muse
     Combo value: ["ms/muse"]
   And create one 9Router API key for your clients. Save it in a
   private file (chmod 600) — never in a repo, never in chat.

B) On the Muse side (where your agent lives), install the courier:
   hook script + definition and the worker prompt from worker/.
   Full click-by-click: docs/TUTORIAL.md Part 5
   (docs/TUTORIAL.id.md Bagian 5 for Indonesian).

C) In Hermes, point one profile at the new model:
     model = muse   (through your local 9Router, with the API key
     from step A). Keep Hermes approvals on "manual" — see Part 6
     of the tutorial before you ever touch /yolo.
EOF
  printf "\nPress ENTER when A is done (or Ctrl+C to finish later)... "
  read -r _ || true
fi

echo
echo "=============================================="
echo "Step 3/3: testing the bridge"
echo "=============================================="
fail=0
if curl -s --max-time 3 "http://127.0.0.1:$PORT/health" | grep -q '"ok"'; then
  echo "[PASS] bridge /health answers"
else
  echo "[FAIL] bridge /health does not answer — see the installer warnings above"
  fail=1
fi
if curl -s --max-time 3 "http://127.0.0.1:$PORT/v1/models" | grep -q '"muse"'; then
  echo "[PASS] bridge /v1/models lists the muse model"
else
  echo "[FAIL] bridge /v1/models looks wrong"
  fail=1
fi
echo
if [ "$fail" = "0" ]; then
  echo "Bridge side is DONE. After steps B and C, test from Hermes with:"
  echo "  'Check the VPS disk now, using a tool'"
  echo "Hermes should show a real tool step and answer with real numbers."
else
  echo "Something needs attention above. The tutorial's Part 9"
  echo "(Troubleshooting) maps each symptom to its fix."
fi
echo "Full tutorial: docs/TUTORIAL.md (EN) / docs/TUTORIAL.id.md (ID)"
