<#
.SYNOPSIS
  Full-stack dev launcher for ClearSplit (Windows).

.DESCRIPTION
  1. Starts the Node backend (npm start) in a new PowerShell window.
  2. Polls http://127.0.0.1:8081/health until the API is ready.
  3. Launches the Flutter frontend on the chosen device.

.PARAMETER Target
  Flutter device target (default: chrome).

.PARAMETER WebPort
  Frontend web port (default: 8080).

.PARAMETER Clean
  Run `flutter clean` before starting.

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File tool/dev.ps1
#>
param(
  [string]$Target = "chrome",
  [int]$WebPort = 8080,
  [switch]$Clean
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$backend = Join-Path $root "backend"

Write-Host "ClearSplit dev launcher" -ForegroundColor Cyan

# Ensure backend dependencies are installed.
if (-not (Test-Path (Join-Path $backend "node_modules"))) {
  Write-Host "Installing backend dependencies..." -ForegroundColor Yellow
  Push-Location $backend
  npm install
  Pop-Location
}

# Start the backend in a new window.
Write-Host "Starting backend (new window)..." -ForegroundColor Yellow
Start-Process powershell -ArgumentList @(
  "-NoExit", "-Command", "Set-Location '$backend'; npm start"
)

# Poll /health until ready.
Write-Host "Waiting for backend health check..." -ForegroundColor Yellow
$ready = $false
for ($i = 0; $i -lt 30; $i++) {
  try {
    $res = Invoke-WebRequest -Uri "http://127.0.0.1:8081/health" -UseBasicParsing -TimeoutSec 2
    if ($res.StatusCode -eq 200) { $ready = $true; break }
  } catch {
    Start-Sleep -Seconds 1
  }
}
if (-not $ready) {
  Write-Host "Backend did not become healthy in time. Check its window for errors." -ForegroundColor Red
  exit 1
}
Write-Host "Backend is up." -ForegroundColor Green

# Optionally clean.
Push-Location $root
if ($Clean) {
  Write-Host "flutter clean..." -ForegroundColor Yellow
  flutter clean
}

# Start the frontend.
Write-Host "Starting Flutter frontend ($Target)..." -ForegroundColor Yellow
if ($Target -eq "chrome") {
  flutter run -d chrome --web-port $WebPort
} else {
  flutter run -d $Target
}
Pop-Location
