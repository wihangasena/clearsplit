<#
.SYNOPSIS
  One-command launcher for the full ClearSplit stack on Windows.

.DESCRIPTION
  Starts the three pieces of the app and checks each one before moving on:

    1. Database  - MongoDB Atlas (cloud). Nothing is launched locally; the
                   script confirms backend/.env has a connection string and
                   then proves the connection works via the backend health
                   check (the API refuses to start unless Mongo is reachable).
    2. Backend   - Node/Express API (npm start) in its own titled window,
                   listening on http://127.0.0.1:<BackendPort>.
    3. Frontend  - Flutter app on the chosen device (default: chrome).

  Compared to the old dev.ps1, this script validates prerequisites up front,
  gives clear errors when something is missing, keeps the backend window open
  on failure so you can read the stack trace, and lets you start just one
  piece via -Mode.

.PARAMETER Mode
  Which pieces to start: all | backend | frontend. Default: all.
  Positional, e.g.  start.ps1 backend

.PARAMETER Target
  Flutter device target (default: chrome). E.g. windows, edge, <emulator-id>.

.PARAMETER WebPort
  Frontend web port when Target is a browser (default: 8080).

.PARAMETER Clean
  Run `flutter clean` before starting the frontend.

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File tool/start.ps1

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File tool/start.ps1 backend

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File tool/start.ps1 -Target windows
#>
[CmdletBinding()]
param(
  [Parameter(Position = 0)]
  [ValidateSet("all", "backend", "frontend")]
  [string]$Mode = "all",

  [string]$Target = "chrome",
  [int]$WebPort = 8080,
  [switch]$Clean
)

$ErrorActionPreference = "Stop"

$root      = Split-Path -Parent $PSScriptRoot
$backend   = Join-Path $root "backend"
$envFile   = Join-Path $backend ".env"

# Read the backend port from backend/.env if present, else default to 8081.
$backendPort = 8081
if (Test-Path $envFile) {
  $portLine = Select-String -Path $envFile -Pattern '^\s*BACKEND_PORT\s*=\s*(\d+)' -ErrorAction SilentlyContinue
  if ($portLine) { $backendPort = [int]$portLine.Matches[0].Groups[1].Value }
}
$healthUrl = "http://127.0.0.1:$backendPort/health"

function Write-Step($msg) { Write-Host "==> $msg" -ForegroundColor Cyan }
function Write-Ok($msg)   { Write-Host "[OK] $msg"  -ForegroundColor Green }
function Write-Warn($msg) { Write-Host "[!]  $msg"  -ForegroundColor Yellow }
function Fail($msg)       { Write-Host "[X]  $msg"  -ForegroundColor Red; exit 1 }

function Test-Command($name) {
  return [bool](Get-Command $name -ErrorAction SilentlyContinue)
}

# Free a TCP port if a leftover process from a previous run is still holding it.
# This is what prevents the "errno 10048 / address already in use" failure when
# a Flutter or Node dev server didn't shut down cleanly.
function Clear-StalePort($port, $label) {
  $conns = Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction SilentlyContinue
  if (-not $conns) { return }
  $pids = $conns.OwningProcess | Sort-Object -Unique
  foreach ($procId in $pids) {
    $proc = Get-Process -Id $procId -ErrorAction SilentlyContinue
    $name = if ($proc) { $proc.ProcessName } else { "PID $procId" }
    Write-Warn "Port $port ($label) is held by a stale process [$name, PID $procId] - stopping it."
    try { Stop-Process -Id $procId -Force -ErrorAction Stop } catch { Write-Warn "Could not stop PID ${procId}: $($_.Exception.Message)" }
  }
  # Give the OS a moment to release the socket.
  for ($i = 0; $i -lt 10; $i++) {
    if (-not (Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction SilentlyContinue)) {
      Write-Ok "Port $port is free."
      return
    }
    Start-Sleep -Milliseconds 300
  }
  Write-Warn "Port $port still appears busy; the next bind may fail."
}

# ---------------------------------------------------------------------------
# 1. Database (MongoDB Atlas) - validate config, real check happens at health.
# ---------------------------------------------------------------------------
function Confirm-Database {
  Write-Step "Database: checking MongoDB configuration"
  if (-not (Test-Path $envFile)) {
    Fail "backend/.env is missing. Copy backend/.env.example to backend/.env and set MONGODB_URI (your MongoDB Atlas connection string)."
  }
  $uri = Select-String -Path $envFile -Pattern '^\s*MONGODB_URI\s*=\s*(\S+)' -ErrorAction SilentlyContinue
  if (-not $uri -or $uri.Matches[0].Groups[1].Value -match '<.*>') {
    Fail "MONGODB_URI in backend/.env is not set (still has placeholders). Paste your real MongoDB Atlas connection string."
  }
  Write-Ok "MongoDB connection string found (Atlas/cloud - nothing to launch locally)."
  Write-Host "     Connectivity is verified when the backend passes its health check below." -ForegroundColor DarkGray
}

# ---------------------------------------------------------------------------
# Backend dependency install (only when node_modules is absent).
# ---------------------------------------------------------------------------
function Initialize-Backend {
  if (-not (Test-Command "node")) { Fail "Node.js is not installed or not on PATH. Install Node 20+ from https://nodejs.org" }
  if (-not (Test-Path (Join-Path $backend "node_modules"))) {
    Write-Step "Installing backend dependencies (first run)..."
    Push-Location $backend
    try { npm install } finally { Pop-Location }
    if ($LASTEXITCODE -ne 0) { Fail "npm install failed in backend/." }
  }
}

# ---------------------------------------------------------------------------
# 2a. Backend in THIS window (blocking) - used for -Mode backend.
# ---------------------------------------------------------------------------
function Start-BackendForeground {
  Confirm-Database
  Initialize-Backend
  Clear-StalePort $backendPort "backend"
  Write-Step "Starting backend (foreground) -> $healthUrl"
  Push-Location $backend
  try { npm start } finally { Pop-Location }
}

# ---------------------------------------------------------------------------
# 2b. Backend in a NEW window, then poll /health until the API + DB are ready.
# ---------------------------------------------------------------------------
function Start-BackendBackground {
  Confirm-Database
  Initialize-Backend
  Clear-StalePort $backendPort "backend"
  Write-Step "Starting backend in a new window..."
  # -NoExit keeps the window (and any error stack trace) visible on crash.
  Start-Process powershell -ArgumentList @(
    "-NoExit", "-Command",
    "`$Host.UI.RawUI.WindowTitle = 'ClearSplit Backend'; Set-Location '$backend'; npm start"
  )

  Write-Step "Waiting for backend + database to be ready ($healthUrl)..."
  for ($i = 1; $i -le 45; $i++) {
    try {
      $res = Invoke-WebRequest -Uri $healthUrl -UseBasicParsing -TimeoutSec 2
      if ($res.StatusCode -eq 200) {
        Write-Ok "Backend is up and connected to MongoDB."
        return
      }
    } catch {
      Start-Sleep -Seconds 1
    }
    if ($i % 10 -eq 0) { Write-Warn "Still waiting... ($i s). Atlas cold starts can take a moment." }
  }
  Fail "Backend did not become healthy in 45s. Check the 'ClearSplit Backend' window - the most common cause is a wrong MONGODB_URI or no network access to Atlas."
}

# ---------------------------------------------------------------------------
# 3. Frontend (Flutter) in THIS window (blocking).
# ---------------------------------------------------------------------------
function Start-Frontend {
  if (-not (Test-Command "flutter")) { Fail "Flutter is not installed or not on PATH. See https://docs.flutter.dev/get-started/install/windows" }
  Push-Location $root
  try {
    if ($Clean) {
      Write-Step "flutter clean..."
      flutter clean
    }
    if ($Target -in @("chrome", "edge", "web-server")) {
      Clear-StalePort $WebPort "frontend"
    }
    Write-Step "Starting Flutter frontend (device: $Target)..."
    if ($Target -in @("chrome", "edge", "web-server")) {
      flutter run -d $Target --web-port $WebPort
    } else {
      flutter run -d $Target
    }
  } finally {
    Pop-Location
  }
}

# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "  ClearSplit launcher  -  mode: $Mode" -ForegroundColor Magenta
Write-Host "  ---------------------------------------" -ForegroundColor DarkGray

switch ($Mode) {
  "backend"  { Start-BackendForeground }
  "frontend" { Start-Frontend }
  "all"      { Start-BackendBackground; Start-Frontend }
}
