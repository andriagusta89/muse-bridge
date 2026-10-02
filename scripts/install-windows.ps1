# muse-bridge installer — Windows (server side: the bridge on your Windows PC)
#
# What it does:
#   1. Creates the queue folders (pending\ + done\) under $HOME\muse-bridge
#   2. Installs bridge\bridge.py (backs up an existing one first)
#   3. Registers a Scheduled Task "muse-bridge" that starts the bridge at
#      logon and restarts it if it dies (localhost only)
#   4. Health-checks http://127.0.0.1:<PORT>/health
#
# Usage (from the repo root, in PowerShell):
#   powershell -ExecutionPolicy Bypass -File scripts\install-windows.ps1
#
# Optional parameters:
#   -BridgeDir "$HOME\muse-bridge"   install location
#   -Port 8765                       bridge port (localhost)
#
# This installs ONLY the bridge (server side). The courier + worker live in
# the Muse environment — see docs\TUTORIAL.md Part 5.

param(
  [string]$BridgeDir = "$HOME\muse-bridge",
  [int]$Port = 8765
)

$ErrorActionPreference = "Stop"
$RepoRoot = Split-Path -Parent $PSScriptRoot
$Src = Join-Path $RepoRoot "bridge\bridge.py"
$TaskName = "muse-bridge"

Write-Host "== muse-bridge installer (Windows) =="
Write-Host "Install dir : $BridgeDir"
Write-Host "Port        : $Port (localhost only)"

# --- find Python 3 -----------------------------------------------------------
$Python = $null
foreach ($cand in @("python", "py")) {
  $cmd = Get-Command $cand -ErrorAction SilentlyContinue
  if ($cmd) { $Python = $cmd.Source; break }
}
if (-not $Python) {
  Write-Host "ERROR: Python 3 not found. Install it from https://www.python.org/downloads/"
  Write-Host "       and tick 'Add python.exe to PATH' during setup, then re-run."
  exit 1
}
if (-not (Test-Path $Src)) {
  Write-Host "ERROR: $Src not found. Run this from inside the muse-bridge repo."
  exit 1
}

# --- folders + file ----------------------------------------------------------
Write-Host "-- creating folders"
New-Item -ItemType Directory -Force -Path "$BridgeDir\queue\pending" | Out-Null
New-Item -ItemType Directory -Force -Path "$BridgeDir\queue\done" | Out-Null

$Dst = Join-Path $BridgeDir "bridge.py"
if (Test-Path $Dst) {
  $Bak = "$Dst.bak-$(Get-Date -Format yyyyMMdd-HHmmss)"
  Write-Host "-- existing bridge.py found, backing up to $Bak"
  Copy-Item $Dst $Bak
}
Write-Host "-- installing bridge.py"
Copy-Item $Src $Dst -Force

# --- launcher (sets env, runs bridge, appends to log) ------------------------
$Launcher = Join-Path $BridgeDir "run-bridge.cmd"
@"
@echo off
set MUSE_BRIDGE_QUEUE=$BridgeDir\queue
set MUSE_BRIDGE_PORT=$Port
"$Python" "$Dst" >> "$BridgeDir\bridge.log" 2>&1
"@ | Set-Content -Path $Launcher -Encoding ASCII

# --- scheduled task (start at logon) -----------------------------------------
Write-Host "-- registering scheduled task '$TaskName'"
$Action = New-ScheduledTaskAction -Execute $Launcher
$Trigger = New-ScheduledTaskTrigger -AtLogOn
$Settings = New-ScheduledTaskSettingsSet -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 1) -ExecutionTimeLimit ([TimeSpan]::Zero)
Register-ScheduledTask -TaskName $TaskName -Action $Action -Trigger $Trigger -Settings $Settings -Force | Out-Null
Start-ScheduledTask -TaskName $TaskName

# --- health check --------------------------------------------------------------
Write-Host "-- health check"
$ok = $false
for ($i = 0; $i -lt 15; $i++) {
  try {
    $r = Invoke-WebRequest -UseBasicParsing -TimeoutSec 2 "http://127.0.0.1:$Port/health"
    if ($r.StatusCode -eq 200) { $ok = $true; break }
  } catch { Start-Sleep -Seconds 1 }
}
if ($ok) {
  Write-Host "OK: bridge is answering on http://127.0.0.1:$Port/health"
} else {
  Write-Host "WARNING: bridge did not answer the health check yet."
  Write-Host "Check the log: $BridgeDir\bridge.log"
}

Write-Host ""
Write-Host "Done. Next steps:"
Write-Host "  1. In the 9Router dashboard, add an OpenAI-compatible provider:"
Write-Host "     name 'muse', prefix 'ms', base URL http://127.0.0.1:$Port/v1"
Write-Host "  2. Create the combo 'muse' -> ['ms/muse'] and a 9Router API key."
Write-Host "  3. On the Muse side, install the courier hook + worker prompt"
Write-Host "     (docs\TUTORIAL.md Part 5) and point Hermes at the new model."
Write-Host "  Stop/start later with: Stop-ScheduledTask / Start-ScheduledTask -TaskName $TaskName"
Write-Host "Full tutorial: docs\TUTORIAL.md (EN) / docs\TUTORIAL.id.md (ID)"
