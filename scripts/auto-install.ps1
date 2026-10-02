# muse-bridge AUTO-INSTALL (Windows) — one command, guided.
#
# What it does for you automatically:
#   1. Runs the Windows bridge installer (folders + bridge.py +
#      Scheduled Task + health check)
#   2. Walks you through the 3 short steps that cannot be automated
#      (9Router dashboard values, Muse-side hook, Hermes model)
#      with the exact values to paste
#   3. Tests the bridge at the end (health + model list)
#
# Usage (from the repo root, in PowerShell):
#   powershell -ExecutionPolicy Bypass -File scripts\auto-install.ps1
#
# Optional parameters: -Port 8765, -BridgeDir "$HOME\muse-bridge",
#                      -SkipGuide (bridge install + tests only)

param(
  [int]$Port = 8765,
  [string]$BridgeDir = "$HOME\muse-bridge",
  [switch]$SkipGuide
)

$ErrorActionPreference = "Stop"
$RepoRoot = Split-Path -Parent $PSScriptRoot

Write-Host "=============================================="
Write-Host "  muse-bridge AUTO-INSTALL"
Write-Host "  Muse as a model inside your 9Router"
Write-Host "=============================================="
Write-Host ""
Write-Host "Step 1/3: installing the bridge (folders, task, health check)..."
Write-Host ""
& powershell -ExecutionPolicy Bypass -File (Join-Path $RepoRoot "scripts\install-windows.ps1") -BridgeDir $BridgeDir -Port $Port

if (-not $SkipGuide) {
  Write-Host ""
  Write-Host "=============================================="
  Write-Host "Step 2/3: three short steps only YOU can do"
  Write-Host "(automation cannot click your dashboard for you)"
  Write-Host "=============================================="
  Write-Host ""
  Write-Host "A) In the 9Router dashboard (on this machine), add a provider:"
  Write-Host "     Type     : OpenAI-compatible"
  Write-Host "     Name     : muse"
  Write-Host "     Prefix   : ms"
  Write-Host "     Base URL : http://127.0.0.1:$Port/v1"
  Write-Host "   Then add a connection (auth type: API key, any value), and a combo:"
  Write-Host "     Combo name : muse"
  Write-Host "     Combo value: ['ms/muse']"
  Write-Host "   And create one 9Router API key for your clients. Save it in a"
  Write-Host "   private file - never in a repo, never in chat."
  Write-Host ""
  Write-Host "B) On the Muse side (where your agent lives), install the courier:"
  Write-Host "   hook script + definition and the worker prompt from worker\."
  Write-Host "   Full click-by-click: docs\TUTORIAL.md Part 5"
  Write-Host "   (docs\TUTORIAL.id.md Bagian 5 for Indonesian)."
  Write-Host ""
  Write-Host "C) In Hermes, point one profile at the new model:"
  Write-Host "     model = muse   (through your local 9Router, with the API key"
  Write-Host "     from step A). Keep Hermes approvals on 'manual' - see Part 6"
  Write-Host "     of the tutorial before you ever touch /yolo."
  Write-Host ""
  Read-Host "Press ENTER when A is done (or Ctrl+C to finish later)"
}

Write-Host ""
Write-Host "=============================================="
Write-Host "Step 3/3: testing the bridge"
Write-Host "=============================================="
$fail = $false
try {
  $h = Invoke-WebRequest -UseBasicParsing -TimeoutSec 3 "http://127.0.0.1:$Port/health"
  if ($h.Content -match '"ok"') { Write-Host "[PASS] bridge /health answers" } else { throw "bad health" }
} catch { Write-Host "[FAIL] bridge /health does not answer - see the installer warnings above"; $fail = $true }
try {
  $m = Invoke-WebRequest -UseBasicParsing -TimeoutSec 3 "http://127.0.0.1:$Port/v1/models"
  if ($m.Content -match '"muse"') { Write-Host "[PASS] bridge /v1/models lists the muse model" } else { throw "bad models" }
} catch { Write-Host "[FAIL] bridge /v1/models looks wrong"; $fail = $true }
Write-Host ""
if (-not $fail) {
  Write-Host "Bridge side is DONE. After steps B and C, test from Hermes with:"
  Write-Host "  'Check the VPS disk now, using a tool'"
  Write-Host "Hermes should show a real tool step and answer with real numbers."
} else {
  Write-Host "Something needs attention above. The tutorial's Part 9"
  Write-Host "(Troubleshooting) maps each symptom to its fix."
}
Write-Host "Full tutorial: docs\TUTORIAL.md (EN) / docs\TUTORIAL.id.md (ID)"
