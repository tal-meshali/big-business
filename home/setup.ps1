<#
.SYNOPSIS
  Sets up and starts the Big Business game server on this Windows PC.

.DESCRIPTION
  Safe to run again at any time: every step checks what is already done.
    1. Installs Git, Docker Desktop and Tailscale with winget if missing.
    2. Starts Docker Desktop and waits for it.
    3. Writes .env.home with fresh random secrets (first run only). The client
       key is copied from client/scripts/game/app_info.gd, so only the address
       changes in the app.
    4. Builds and starts Postgres + Nakama (home/docker-compose.yml).
    5. Keeps the PC awake while plugged in, and Docker starting at sign-in.
    6. Publishes the server on https://<pc>.<tailnet>.ts.net with Tailscale Funnel.
    7. Registers a nightly database backup (home/backup.ps1).
    8. Writes the public address into client/scripts/game/app_info.gd.
  See docs/home-server.md.

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File home\setup.ps1
#>
param(
    # Skip writing the address into the client (app_info.gd).
    [switch]$NoClientUpdate,
    # Skip Tailscale Funnel (server reachable from this PC only).
    [switch]$NoFunnel
)

$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $PSScriptRoot
$Compose = Join-Path $PSScriptRoot 'docker-compose.yml'
$EnvFile = Join-Path $Root '.env.home'
$AppInfo = Join-Path $Root 'client\scripts\game\app_info.gd'

function Step($text) { Write-Host "`n== $text" -ForegroundColor Cyan }
function Info($text) { Write-Host "   $text" }
function Warn($text) { Write-Host "   $text" -ForegroundColor Yellow }

function Refresh-Path {
    $env:Path = [Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' +
                [Environment]::GetEnvironmentVariable('Path', 'User')
}

# Runs a native command with its output hidden and returns $true when it
# succeeded. WHY: in Windows PowerShell 5.1 a native command writing to a
# redirected stderr raises an error, which $ErrorActionPreference='Stop'
# turns into the end of the script.
function Test-Native([scriptblock]$command) {
    $saved = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try { & $command *> $null; return ($LASTEXITCODE -eq 0) }
    catch { return $false }
    finally { $ErrorActionPreference = $saved }
}

# Like Test-Native, but returns the command's output as text: stdout and
# stderr, or stdout only with -StdoutOnly (for JSON).
function Get-NativeOutput([scriptblock]$command, [switch]$StdoutOnly) {
    $saved = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        if ($StdoutOnly) { return ((& $command 2> $null) | ForEach-Object { "$_" }) -join "`n" }
        return ((& $command 2>&1) | ForEach-Object { "$_" }) -join "`n"
    }
    finally { $ErrorActionPreference = $saved }
}

function Has-Command($name) { [bool](Get-Command $name -ErrorAction SilentlyContinue) }

function Ensure-Installed($command, $wingetId, $extraPaths) {
    if (Has-Command $command) { Info "$command found."; return $false }
    foreach ($p in $extraPaths) {
        if (Test-Path $p) { $env:Path += ";$p"; if (Has-Command $command) { Info "$command found."; return $false } }
    }
    if (-not (Has-Command 'winget')) {
        throw "winget is missing. Install 'App Installer' from the Microsoft Store, then run this again."
    }
    Info "Installing $wingetId (accept the Windows prompt if one appears)..."
    winget install --id $wingetId --exact --silent --accept-package-agreements --accept-source-agreements | Out-Host
    # 0: installed. -1978335189 (0x8A15002B): already installed.
    # 3010 / 1641 / -1978334967 (0x8A150109) / -1978334966 (0x8A15010A): installed, restart needed.
    if (@(0, -1978335189, 3010, 1641, -1978334967, -1978334966) -notcontains $LASTEXITCODE) {
        throw "winget could not install $wingetId (exit code $LASTEXITCODE)."
    }
    Refresh-Path
    foreach ($p in $extraPaths) { if (Test-Path $p) { $env:Path += ";$p" } }
    return $true
}

function New-Secret {
    $bytes = New-Object byte[] 32
    $rng = [Security.Cryptography.RandomNumberGenerator]::Create()
    $rng.GetBytes($bytes)
    $rng.Dispose()
    return -join ($bytes | ForEach-Object { $_.ToString('x2') })
}

function Invoke-Compose {
    & docker compose -f $Compose @args
    if ($LASTEXITCODE -ne 0) { throw "docker compose $args failed (exit code $LASTEXITCODE)." }
}

function Wait-Url($url, $seconds) {
    $deadline = (Get-Date).AddSeconds($seconds)
    while ((Get-Date) -lt $deadline) {
        try {
            $r = Invoke-WebRequest -Uri $url -UseBasicParsing -TimeoutSec 5
            if ($r.StatusCode -eq 200) { return $true }
        } catch { }
        Start-Sleep -Seconds 3
    }
    return $false
}

# ---------------------------------------------------------------- 1. Tools
Step 'Checking Git, Docker Desktop and Tailscale'
$null = Ensure-Installed 'git' 'Git.Git' @("$env:ProgramFiles\Git\cmd")
$dockerNew = Ensure-Installed 'docker' 'Docker.DockerDesktop' @("$env:ProgramFiles\Docker\Docker\resources\bin")
$null = Ensure-Installed 'tailscale' 'Tailscale.Tailscale' @("$env:ProgramFiles\Tailscale")

# ---------------------------------------------------------------- 2. Docker
Step 'Starting Docker'
if (-not (Test-Native { docker info })) {
    $desktop = "$env:ProgramFiles\Docker\Docker\Docker Desktop.exe"
    if (-not (Test-Path $desktop)) { throw "Docker Desktop is not at $desktop." }
    Info 'Opening Docker Desktop. The first time, accept its terms in the window that opens.'
    Start-Process $desktop
    $deadline = (Get-Date).AddMinutes(5)
    do {
        Start-Sleep -Seconds 5
        $running = Test-Native { docker info }
    } while (-not $running -and (Get-Date) -lt $deadline)
    if (-not $running) {
        if ($dockerNew) {
            Warn 'Docker Desktop was just installed and usually needs a restart (it turns on WSL 2).'
            Warn 'Restart Windows, sign in, then run this script again.'
            exit 2
        }
        throw 'Docker did not start within 5 minutes. Open Docker Desktop, check it says "Engine running", and run this again.'
    }
}
Info 'Docker is running.'

# ---------------------------------------------------------------- 3. Secrets
Step 'Secrets (.env.home)'
$volumeExists = Test-Native { docker volume inspect big-business-home_pgdata }
if (Test-Path $EnvFile) {
    Info '.env.home exists; keeping it.'
} elseif ($volumeExists) {
    # The database keeps the password it was created with; new secrets would lock Nakama out.
    throw ('.env.home is missing but the database already exists. Put the saved .env.home back in ' +
           "$Root, or, to start over with an EMPTY database, run: docker compose -f home/docker-compose.yml down -v")
} else {
    $serverKey = $null
    if (Test-Path $AppInfo) {
        $m = Select-String -Path $AppInfo -Pattern 'const SERVER_KEY := "([^"]+)"'
        if ($m) { $serverKey = $m.Matches[0].Groups[1].Value }
    }
    if (-not $serverKey) { $serverKey = New-Secret; Warn 'No SERVER_KEY in app_info.gd; made a new one (it will be written there).' }
    $pg = New-Secret
    $lines = @(
        '# Big Business home server secrets (home/setup.ps1). Never commit; keep a copy in a password manager.',
        "POSTGRES_PASSWORD=$pg",
        "DATABASE_URL=postgres://postgres:$pg@postgres:5432/nakama",
        '# The client key embedded in the app (AppInfo.SERVER_KEY): not a secret.',
        "NAKAMA_SERVER_KEY=$serverKey",
        "NAKAMA_SESSION_KEY=$(New-Secret)",
        "NAKAMA_REFRESH_KEY=$(New-Secret)",
        'NAKAMA_CONSOLE_USER=ops',
        "NAKAMA_CONSOLE_PASSWORD=$(New-Secret)",
        "NAKAMA_CONSOLE_SIGNING_KEY=$(New-Secret)",
        "NAKAMA_HTTP_KEY=$(New-Secret)",
        "REVENUECAT_WEBHOOK_AUTH=$(New-Secret)",
        '# Store, push and moderation keys (docs/deploy.md); empty keeps each feature off.',
        'APPLE_BUNDLE_ID=',
        'REVENUECAT_API_KEY=',
        'FCM_PROJECT_ID=',
        'FCM_CLIENT_EMAIL=',
        'FCM_PRIVATE_KEY=',
        'GOOGLE_VISION_API_KEY='
    )
    # UTF-8 without BOM, LF endings: Docker reads it as-is.
    [IO.File]::WriteAllText($EnvFile, ($lines -join "`n") + "`n", (New-Object Text.UTF8Encoding $false))
    Info 'Wrote .env.home with fresh random secrets.'
}
$envValues = @{}
foreach ($line in Get-Content $EnvFile) {
    if ($line -match '^\s*([A-Z0-9_]+)=(.*)$') { $envValues[$Matches[1]] = $Matches[2] }
}

# ---------------------------------------------------------------- 4. Server
Step 'Building and starting the server (the first build takes a few minutes)'
Invoke-Compose up -d --build
if (-not (Wait-Url 'http://127.0.0.1:7350/healthcheck' 180)) {
    Invoke-Compose logs --tail 60 nakama
    throw 'The server did not answer on http://127.0.0.1:7350 within 3 minutes (logs above).'
}
$insecure = (Get-NativeOutput { docker compose -f $Compose logs nakama }) -split "`n" | Select-String 'insecure default'
if ($insecure) { throw "Nakama fell back to a default key: $insecure" }
Info 'Server is up on http://127.0.0.1:7350 (console: http://127.0.0.1:7351).'

# ---------------------------------------------------------------- 5. Stay on
Step 'Keeping the PC awake and Docker starting at sign-in'
powercfg /change standby-timeout-ac 0
powercfg /change hibernate-timeout-ac 0
Info 'Sleep and hibernate are off while plugged in (the screen may still turn off).'
# Docker Desktop's own "Start when you sign in" setting writes this same Run entry.
$runKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
$desktopExe = "$env:ProgramFiles\Docker\Docker\Docker Desktop.exe"
if ((Get-ItemProperty -Path $runKey -ErrorAction SilentlyContinue).'Docker Desktop') {
    Info 'Docker Desktop already starts at sign-in.'
} elseif (Test-Path $desktopExe) {
    New-ItemProperty -Path $runKey -Name 'Docker Desktop' -Value "`"$desktopExe`"" -PropertyType String -Force | Out-Null
    Info 'Docker Desktop now starts at sign-in.'
} else {
    Warn "Turn on 'Start Docker Desktop when you sign in' in Docker Desktop's settings."
}

# ---------------------------------------------------------------- 6. Public address
$publicUrl = $null
if (-not $NoFunnel) {
    Step 'Public address (Tailscale Funnel)'
    $status = $null
    try { $status = (Get-NativeOutput { tailscale status --json } -StdoutOnly) | ConvertFrom-Json } catch { }
    if (-not $status -or $status.BackendState -ne 'Running') {
        Info 'Signing in to Tailscale: open the link it prints (or use the Tailscale tray icon) and sign in.'
        tailscale up
        if ($LASTEXITCODE -ne 0) { throw 'tailscale up failed. Open the Tailscale app, sign in, and run this again.' }
        $status = (Get-NativeOutput { tailscale status --json } -StdoutOnly) | ConvertFrom-Json
    }
    $dns = ([string]$status.Self.DNSName).TrimEnd('.')
    if (-not $dns) { throw 'Tailscale has no DNS name for this PC (turn on MagicDNS in the Tailscale admin console).' }
    Info 'Turning on Funnel for port 7350. If it prints a link, open it and allow Funnel, and it carries on.'
    tailscale funnel --bg 7350
    if ($LASTEXITCODE -ne 0) { throw 'tailscale funnel failed (see the message above).' }
    $publicUrl = "https://$dns"
    $funnel = Get-NativeOutput { tailscale funnel status }
    if ($funnel -notmatch 'Funnel on') { Warn "tailscale funnel status does not say 'Funnel on':`n$funnel" }
    # This PC reaches the name over the tailnet, not the public relays, so this
    # proves the certificate and the proxy; a phone on mobile data proves Funnel.
    Info "Waiting for $publicUrl (the first certificate can take a minute)..."
    if (Wait-Url "$publicUrl/healthcheck" 180) {
        Info "Answers from this PC: $publicUrl"
        Info "Now open $publicUrl/healthcheck on a phone on mobile data (Wi-Fi off): it should show {}."
    }
    else { Warn "$publicUrl did not answer yet. Check again in a few minutes; it can take a while for a new name to appear." }
}

# ---------------------------------------------------------------- 7. Backups
Step 'Nightly backup'
$backup = Join-Path $PSScriptRoot 'backup.ps1'
try {
    $action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument "-NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$backup`""
    $trigger = New-ScheduledTaskTrigger -Daily -At '04:00'
    $settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -DontStopIfGoingOnBatteries -AllowStartIfOnBatteries
    Register-ScheduledTask -TaskName 'Big Business server backup' -Action $action -Trigger $trigger -Settings $settings -Force | Out-Null
    Info "Daily at 04:00 into home\backups (the last 14 are kept)."
} catch {
    Warn "Could not register the backup task ($($_.Exception.Message)). Run home\backup.ps1 by hand meanwhile."
}

# ---------------------------------------------------------------- 8. Client
if ($publicUrl -and -not $NoClientUpdate -and (Test-Path $AppInfo)) {
    Step 'Pointing the app at the new server'
    $text = [IO.File]::ReadAllText($AppInfo)
    $text = [regex]::Replace($text, 'const SERVER_ADDRESS := "[^"]*"', "const SERVER_ADDRESS := `"$publicUrl`"")
    $text = [regex]::Replace($text, 'const SERVER_KEY := "[^"]*"', "const SERVER_KEY := `"$($envValues['NAKAMA_SERVER_KEY'])`"")
    [IO.File]::WriteAllText($AppInfo, $text, (New-Object Text.UTF8Encoding $false))
    Info 'Updated client/scripts/game/app_info.gd. Commit it and make a new build for phones.'
}

Step 'Done'
if ($publicUrl) { Info "Public address: $publicUrl" }
Info 'Local API:      http://127.0.0.1:7350'
Info "Console:        http://127.0.0.1:7351  (user $($envValues['NAKAMA_CONSOLE_USER']), password in .env.home)"
Info 'Update later:   home\update.ps1     Backup now: home\backup.ps1'
