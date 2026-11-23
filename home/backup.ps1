<#
.SYNOPSIS
  Saves the game database to home\backups\nakama-<date>.dump and keeps the
  newest 14. Setup registers it to run daily at 04:00.
  Restore one: home\restore.ps1 -File home\backups\nakama-<date>.dump
  The dumps hold player data (ids, reports): keep them private.
#>
$ErrorActionPreference = 'Stop'
$Compose = Join-Path $PSScriptRoot 'docker-compose.yml'
$Dir = Join-Path $PSScriptRoot 'backups'
New-Item -ItemType Directory -Force -Path $Dir | Out-Null
# Nightly runs have no window: keep a log next to the dumps.
Start-Transcript -Path (Join-Path $Dir 'backup.log') -Append | Out-Null
trap { Write-Host "BACKUP FAILED: $_"; Stop-Transcript | Out-Null; exit 1 }

$name = "nakama-$(Get-Date -Format 'yyyy-MM-dd-HHmmss').dump"
# Dump inside the container and copy the file out: PowerShell redirection
# would re-encode the binary dump.
& docker compose -f $Compose exec -T postgres pg_dump -U postgres -Fc -f /tmp/backup.dump nakama
if ($LASTEXITCODE -ne 0) { throw 'pg_dump failed (is the server running?).' }
& docker compose -f $Compose cp postgres:/tmp/backup.dump (Join-Path $Dir $name)
if ($LASTEXITCODE -ne 0) { throw 'Copying the dump out of the container failed.' }
& docker compose -f $Compose exec -T postgres rm -f /tmp/backup.dump | Out-Null

Get-ChildItem $Dir -Filter 'nakama-*.dump' | Sort-Object Name -Descending | Select-Object -Skip 14 | Remove-Item
Write-Host "Saved $(Join-Path $Dir $name)"
Stop-Transcript | Out-Null
