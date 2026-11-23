<#
.SYNOPSIS
  Pulls the latest code and restarts the home server with it (docs/home-server.md).
  Games in progress end when the server restarts: run it at a quiet time.

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File home\update.ps1
#>
$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $PSScriptRoot
$Compose = Join-Path $PSScriptRoot 'docker-compose.yml'

& git -C $Root pull --ff-only
if ($LASTEXITCODE -ne 0) { throw 'git pull failed (local changes or a diverged branch); fix that first.' }

& docker compose -f $Compose up -d --build
if ($LASTEXITCODE -ne 0) { throw 'docker compose up failed.' }

$deadline = (Get-Date).AddMinutes(3)
while ((Get-Date) -lt $deadline) {
    try {
        if ((Invoke-WebRequest -Uri 'http://127.0.0.1:7350/healthcheck' -UseBasicParsing -TimeoutSec 5).StatusCode -eq 200) {
            Write-Host 'Server updated and running.'
            exit 0
        }
    } catch { }
    Start-Sleep -Seconds 3
}
& docker compose -f $Compose logs --tail 60 nakama
throw 'The server did not come back within 3 minutes (logs above).'
