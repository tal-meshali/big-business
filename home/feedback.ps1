<#
.SYNOPSIS
  Shows what players sent from More > Send feedback (bugs, ideas, other),
  newest first, and clears the ones you have handled. Run it on the server PC.

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File home\feedback.ps1
  powershell -ExecutionPolicy Bypass -File home\feedback.ps1 -Limit 50
  powershell -ExecutionPolicy Bypass -File home\feedback.ps1 -Done 9998235..., 9998236...
#>
param(
    [int]$Limit = 20,
    # Keys printed above each message; those messages are deleted.
    [string[]]$Done = @()
)
$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $PSScriptRoot
$EnvFile = Join-Path $Root '.env.home'
if (-not (Test-Path $EnvFile)) { throw '.env.home not found; run home\setup.ps1 first.' }
$httpKey = (Get-Content $EnvFile | Where-Object { $_ -match '^NAKAMA_HTTP_KEY=' } | Select-Object -First 1) -replace '^NAKAMA_HTTP_KEY=', ''
if (-not $httpKey) { throw 'NAKAMA_HTTP_KEY is missing from .env.home.' }

function Invoke-Rpc($name, $body) {
    $uri = "http://127.0.0.1:7350/v2/rpc/${name}?http_key=$([uri]::EscapeDataString($httpKey))&unwrap"
    $json = $body | ConvertTo-Json -Compress
    return Invoke-RestMethod -Method Post -Uri $uri -Body ([Text.Encoding]::UTF8.GetBytes($json)) -ContentType 'application/json'
}

if ($Done.Count -gt 0) {
    $res = Invoke-Rpc 'feedback_done' @{ keys = $Done }
    if ($res.error) { throw "Not cleared: $($res.error) (copy the key exactly as printed)." }
    Write-Host "Cleared $($res.deleted) message(s)."
    exit 0
}

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
else { Write-Host "`n$shown message(s). Clear handled ones with -Done <key>, <key>." }
