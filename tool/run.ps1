<#
.SYNOPSIS
  Run ClearSplit's frontend, backend, or both - selected by argument.

.DESCRIPTION
  -Mode backend   Start only the Node backend (this window, foreground).
  -Mode frontend  Start only the Flutter frontend (assumes a backend is up).
  -Mode both      Start the backend in a new window, wait for /health, then
                  start the frontend in this window (default).

.PARAMETER Mode
  What to run: backend | frontend | both. Default: both.
  Accepts a positional value too, e.g. `run.ps1 backend`.

.PARAMETER Target
  Flutter device target (default: chrome).

.PARAMETER WebPort
  Frontend web port (default: 8080).

.PARAMETER Clean
  Run `flutter clean` before starting the frontend.

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File tool/run.ps1 backend

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File tool/run.ps1 -Mode frontend -WebPort 9000

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File tool/run.ps1 both -Clean
#>
[CmdletBinding()]
param(
  [Parameter(Position = 0)]
  [ValidateSet("backend", "frontend", "both")]
  [string]$Mode = "both",

  [string]$Target = "chrome",
  [int]$WebPort = 8080,
  [switch]$Clean
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$backend = Join-Path $root "backend"
$healthUrl = "http://127.0.0.1:8081/health"

function Write-Step($msg) { Write-Host $msg -ForegroundColor Cyan }

# Ensure backend dependencies are present before any backend start.
function Initialize-Backend {
  if (-not (Test-Path (Join-Path $backend "node_modules"))) {
    Write-Step "Installing backend dependencies..."
    Push-Location $backend
    try { npm install } finally { Pop-Location }
  }
}

# Start backend in THIS window (blocking).
function Start-BackendForeground {
  Initialize-Backend
  Write-Step "Starting backend (foreground) at $healthUrl ..."
  Push-Location $backend
  try { npm start } finally { Pop-Location }
}

# Start backend in a NEW window and poll until healthy.
function Start-BackendBackground {
  Initialize-Backend
  Write-Step "Starting backend in a new window..."
  Start-Process powershell -ArgumentList @(
    "-NoExit", "-Command", "Set-Location '$backend'; npm start"
  )

  Write-Step "Waiting for backend health check..."
  for ($i = 0; $i -lt 30; $i++) {
    try {
      $res = Invoke-WebRequest -Uri $healthUrl -UseBasicParsing -TimeoutSec 2
      if ($res.StatusCode -eq 200) { Write-Host "Backend is up." -ForegroundColor Green; return }
    } catch {
      Start-Sleep -Seconds 1
    }
  }
  throw "Backend did not become healthy in time. Check its window for errors."
}

# Start the Flutter frontend in THIS window (blocking).
function Start-Frontend {
  Push-Location $root
  try {
    if ($Clean) {
      Write-Step "flutter clean..."
      flutter clean
    }
    Write-Step "Starting Flutter frontend ($Target)..."
    if ($Target -eq "chrome") {
      flutter run -d chrome --web-port $WebPort
    } else {
      flutter run -d $Target
    }
  } finally {
    Pop-Location
  }
}

Write-Host "ClearSplit runner - mode: $Mode" -ForegroundColor Magenta

switch ($Mode) {
  "backend"  { Start-BackendForeground }
  "frontend" { Start-Frontend }
  "both"     { Start-BackendBackground; Start-Frontend }
}
