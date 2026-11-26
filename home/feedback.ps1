<#
.SYNOPSIS
  Shows what players sent from More > Send feedback (bugs, ideas, other),
  newest first, and clears the ones you have handled. Run it on the server PC.

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File home\feedback.ps1
  powershell -ExecutionPolicy Bypass -File home\feedback.ps1 -Limit 50
  powershell -ExecutionPolicy Bypass -File home\feedback.ps1 -Done 9998235...,9998236...
  powershell -ExecutionPolicy Bypass -File home\feedback.ps1 -Player <player id>

  Listing also deletes messages older than 90 days (decision D29).
  -Player deletes everything one player sent, for a deletion request.
#>
param(
    [int]$Limit = 20,
    # Keys printed above each message; those messages are deleted.
    [string[]]$Done = @(),
    # A player id printed under a message: deletes all of that player's messages.
    [string]$Player = '',
    # WHY: parameters bind by position, so "-Done a, b" under -File would
    # hand "b" to -Limit; extra words land here and join -Done instead.
    [Parameter(ValueFromRemainingArguments = $true)][string[]]$Rest = @()
)
$ErrorActionPreference = 'Stop'
# WHY: under `powershell -File`, "-Done a, b" arrives as "a," and "b"; split
# on commas and spaces so every form works.
$Done = @((@($Done) + @($Rest)) -split '[,\s]+' | Where-Object { $_ })
# Without a console (a scheduled task) the encoding cannot be set; that is fine.
try { [Console]::OutputEncoding = [Text.Encoding]::UTF8 } catch { }
$Root = Split-Path -Parent $PSScriptRoot
$EnvFile = Join-Path $Root '.env.home'
if (-not (Test-Path $EnvFile)) { throw '.env.home not found; run home\setup.ps1 first.' }
$httpKey = (Get-Content $EnvFile | Where-Object { $_ -match '^NAKAMA_HTTP_KEY=' } | Select-Object -First 1) -replace '^NAKAMA_HTTP_KEY=', ''
if (-not $httpKey) { throw 'NAKAMA_HTTP_KEY is missing from .env.home.' }

function Invoke-Rpc($name, $body) {
    $uri = "http://127.0.0.1:7350/v2/rpc/${name}?http_key=$([uri]::EscapeDataString($httpKey))&unwrap"
    $json = $body | ConvertTo-Json -Compress
    # WHY not Invoke-RestMethod: Windows PowerShell 5.1 reads a reply with no
    # charset as Latin-1, which garbles accents, Hebrew and emoji.
    $r = Invoke-WebRequest -Method Post -Uri $uri -Body ([Text.Encoding]::UTF8.GetBytes($json)) -ContentType 'application/json' -UseBasicParsing
    return [Text.Encoding]::UTF8.GetString($r.RawContentStream.ToArray()) | ConvertFrom-Json
}

if ($Player) {
    $res = Invoke-Rpc 'feedback_done' @{ userId = $Player }
    Write-Host "Deleted $($res.deleted) message(s) from that player."
    exit 0
}

if ($Done.Count -gt 0) {
    $res = Invoke-Rpc 'feedback_done' @{ keys = $Done }
    Write-Host "Cleared $($res.deleted) message(s)."
    if ($res.skipped -gt 0) { Write-Host "$($res.skipped) key(s) were not recognised; copy them exactly as printed." -ForegroundColor Yellow }
    exit 0
}

$purged = Invoke-Rpc 'feedback_done' @{ olderThanDays = 90 }
if ($purged.deleted -gt 0) { Write-Host "Deleted $($purged.deleted) message(s) older than 90 days." -ForegroundColor DarkGray }

$cursor = ''
$shown = 0
do {
    $page = Invoke-Rpc 'feedback_list' @{ limit = [Math]::Min(100, $Limit - $shown); cursor = $cursor }
    foreach ($m in $page.items) {
        $when = [DateTimeOffset]::FromUnixTimeMilliseconds([int64]$m.at).ToLocalTime().ToString('yyyy-MM-dd HH:mm')
        $who = if ($m.name) { $m.name } else { '(no name)' }
        Write-Host ''
        Write-Host ("{0}  {1}  from {2}" -f $when, $m.category.ToUpper(), $who) -ForegroundColor Cyan
        Write-Host $m.text
        if ($m.device) {
            $d = $m.device
            Write-Host ("  device: {0}" -f (($d.PSObject.Properties | ForEach-Object { "$($_.Name) $($_.Value)" }) -join ', ')) -ForegroundColor DarkGray
        }
        Write-Host ("  player id: {0}" -f $m.userId) -ForegroundColor DarkGray
        Write-Host ("  key: {0}" -f $m.key) -ForegroundColor DarkGray
        $shown++
    }
    $cursor = $page.cursor
} while ($cursor -and $shown -lt $Limit)

if ($shown -eq 0) { Write-Host 'No feedback waiting.' }
else { Write-Host "`n$shown message(s). Clear handled ones with -Done <key>,<key>." }
