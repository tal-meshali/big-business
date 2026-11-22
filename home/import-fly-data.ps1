<#
.SYNOPSIS
  Copies the players' data (accounts, friends, stats, clubs, purchases) from
  the Fly.io database into the home server. Optional: without it the home
  server starts empty and every phone makes a new guest account.

  Needs flyctl signed in to the Fly account (the script installs flyctl and
  runs `fly auth login` if needed). Run it once, right before switching the
  app to the home server, since anything played on Fly afterwards is not copied.

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File home\import-fly-data.ps1
#>
param(
    [string]$App = 'big-business-server',
    [string]$DbApp = 'big-business-db',
    # Skip asking Fly for it: the app's DATABASE_URL (postgres://user:pass@host:5432/db).
    [string]$DatabaseUrl
)
$ErrorActionPreference = 'Stop'

# Native commands with their stderr captured. WHY: in Windows PowerShell 5.1
# a native command writing to a redirected stderr raises an error, which
# $ErrorActionPreference='Stop' turns into the end of the script.
function Get-NativeOutput([scriptblock]$command) {
    $saved = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try { return ((& $command 2>&1) | ForEach-Object { "$_" }) -join "`n" }
    finally { $ErrorActionPreference = $saved }
}

$Dir = Join-Path $PSScriptRoot 'backups'
New-Item -ItemType Directory -Force -Path $Dir | Out-Null

if (-not (Get-Command fly -ErrorAction SilentlyContinue)) {
    $flyBin = Join-Path $env:USERPROFILE '.fly\bin'
    if (-not (Test-Path (Join-Path $flyBin 'fly.exe'))) {
        Write-Host 'Installing flyctl...'
        Invoke-Expression (Invoke-RestMethod 'https://fly.io/install.ps1')
    }
    $env:Path += ";$flyBin"
}
$null = Get-NativeOutput { fly auth whoami }
if ($LASTEXITCODE -ne 0) { & fly auth login; if ($LASTEXITCODE -ne 0) { throw 'fly auth login failed.' } }

if (-not $DatabaseUrl) {
    $out = Get-NativeOutput { fly ssh console -a $App -C 'printenv DATABASE_URL' }
    $DatabaseUrl = ($out -split "`n" | Where-Object { $_ -match '^\s*postgres' } | Select-Object -First 1)
    if (-not $DatabaseUrl) { throw "Could not read DATABASE_URL from $App. Pass it with -DatabaseUrl.`n$out" }
    $DatabaseUrl = $DatabaseUrl.Trim()
}
if ($DatabaseUrl -notmatch '^postgres(?:ql)?://([^:]+):([^@]+)@[^/]+/([^?]+)') { throw 'DATABASE_URL has an unexpected form.' }
$user = $Matches[1]; $pass = $Matches[2]; $db = $Matches[3]

$port = 15432
Write-Host "Opening a tunnel to $DbApp on 127.0.0.1:$port..."
$proxyLog = Join-Path $Dir 'fly-proxy.log'
$proxy = Start-Process fly -ArgumentList @('proxy', "$($port):5432", '-a', $DbApp) -PassThru -WindowStyle Hidden `
    -RedirectStandardOutput $proxyLog -RedirectStandardError "$proxyLog.err"
try {
    $local = "postgres://$($user):$($pass)@host.docker.internal:$port/$($db)?sslmode=disable"
    # The first fly proxy sets up a WireGuard peer, which can take a while.
    $deadline = (Get-Date).AddSeconds(90)
    do {
        Start-Sleep -Seconds 5
        $version = (Get-NativeOutput { docker run --rm postgres:17-alpine psql $local -tAc 'show server_version_num' }).Trim()
    } while ($version -notmatch '^\d+$' -and -not $proxy.HasExited -and (Get-Date) -lt $deadline)
    if ($version -notmatch '^\d+$') {
        $log = (Get-Content $proxyLog, "$proxyLog.err" -ErrorAction SilentlyContinue) -join "`n"
        throw "Could not reach the Fly database through fly proxy.`npsql: $version`nfly proxy: $log"
    }
    if ([int]$version -ge 180000) { throw "The Fly database is Postgres $version; update the postgres images in home/ to that major version first." }

    $name = "fly-$(Get-Date -Format 'yyyy-MM-dd-HHmmss').dump"
    Write-Host "Dumping the Fly database (Postgres $version)..."
    & docker run --rm -v "$($Dir):/out" postgres:17-alpine pg_dump $local -Fc --no-owner --no-acl -f "/out/$name"
    if ($LASTEXITCODE -ne 0) { throw 'pg_dump of the Fly database failed.' }
} finally {
    Stop-Process -Id $proxy.Id -ErrorAction SilentlyContinue
}

& (Join-Path $PSScriptRoot 'restore.ps1') -File (Join-Path $Dir $name)
Write-Host 'Fly data copied into the home server.'
