<#
.SYNOPSIS
  Replaces the game database with a dump (from home\backup.ps1 or
  home\import-fly-data.ps1). Everything in the current database is lost, so
  this takes a backup first. The server is down for a moment.

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File home\restore.ps1 -File home\backups\nakama-2026-11-23-0400.dump
#>
param([Parameter(Mandatory = $true)][string]$File)
$ErrorActionPreference = 'Stop'
$Compose = Join-Path $PSScriptRoot 'docker-compose.yml'
if (-not (Test-Path $File)) { throw "No file at $File." }
$File = (Resolve-Path $File).Path

function Compose { & docker compose -f $Compose @args; if ($LASTEXITCODE -ne 0) { throw "docker compose $args failed." } }

Write-Host 'Backing up the current database first...'
& (Join-Path $PSScriptRoot 'backup.ps1')
if ($LASTEXITCODE -ne 0) { throw 'The backup failed, so nothing was restored (see home\backups\backup.log).' }

# Check the dump before touching the live database.
Compose cp $File postgres:/tmp/restore.dump
& docker compose -f $Compose exec -T postgres pg_restore --list /tmp/restore.dump | Out-Null
if ($LASTEXITCODE -ne 0) {
    & docker compose -f $Compose exec -T postgres rm -f /tmp/restore.dump | Out-Null
    throw "$File is not a dump this Postgres can read; the database was not touched."
}

Compose stop nakama
try {
    Compose exec -T postgres dropdb -U postgres --if-exists nakama
    Compose exec -T postgres createdb -U postgres nakama
    # --no-owner/--no-acl: the Fly database belongs to another role name.
    # --exit-on-error: a dump this Postgres cannot read fails here instead of
    # leaving an empty database behind.
    & docker compose -f $Compose exec -T postgres pg_restore -U postgres -d nakama --no-owner --no-acl --exit-on-error /tmp/restore.dump
    if ($LASTEXITCODE -ne 0) { throw "pg_restore failed (exit code $LASTEXITCODE). The previous database is in the backup made above." }
} finally {
    & docker compose -f $Compose exec -T postgres rm -f /tmp/restore.dump | Out-Null
    # Always bring the server back. Nakama runs its migrations on start, so an
    # older dump is brought up to date.
    & docker compose -f $Compose up -d nakama
}
$users = (& docker compose -f $Compose exec -T postgres psql -U postgres -d nakama -tAc 'select count(*) from users' | Out-String).Trim()
Write-Host "Restored ($users accounts). Players sign in again automatically."
