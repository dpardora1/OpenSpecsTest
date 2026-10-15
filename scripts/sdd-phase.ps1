<#
.SYNOPSIS
    Marks the start or end of an SDD phase for a change (used by the sdd-conductor agent).

.DESCRIPTION
    - Appends phase.start / phase.end events to .sdd/telemetry/events.jsonl (input for sdd-metrics.ps1).
    - On "end", also publishes the phase as an OpenTelemetry span (service "sdd-process") to the local
      collector. All phases of a change share one deterministic trace id, so Tempo shows the whole change
      as a single timeline: propose → apply → verify → review → archive → pr.
    - Telemetry failures never break the workflow (the OTLP export is best effort).

.EXAMPLE
    ./scripts/sdd-phase.ps1 -Change add-create-booking -Phase apply -Action start
    ./scripts/sdd-phase.ps1 -Change add-create-booking -Phase apply -Action end -Status ok
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Change,
    [Parameter(Mandatory)][ValidateSet('explore', 'propose', 'apply', 'verify', 'review', 'archive', 'retrospective', 'pr', 'consolidation')][string]$Phase,
    [Parameter(Mandatory)][ValidateSet('start', 'end')][string]$Action,
    [ValidateSet('ok', 'error')][string]$Status = 'ok',
    [int]$Iteration = 1,
    [string]$Note,
    [string]$Endpoint = ($env:OTEL_EXPORTER_OTLP_ENDPOINT ?? 'http://localhost:4318')
)

$ErrorActionPreference = 'Stop'
$root = git rev-parse --show-toplevel 2>$null
if (-not $root) { $root = (Get-Location).Path }
$dir = Join-Path $root '.sdd/telemetry'
New-Item -ItemType Directory -Force $dir | Out-Null
$eventsFile = Join-Path $dir 'events.jsonl'
$now = [DateTimeOffset]::UtcNow

$entry = [ordered]@{
    ts        = $now.ToString('o')
    event     = "phase.$Action"
    branch    = (git branch --show-current 2>$null)
    change_id = $Change
    phase     = $Phase
    iteration = $Iteration
    status    = $Status
    note      = $Note
}
($entry | ConvertTo-Json -Compress) | Add-Content -Path $eventsFile -Encoding utf8

if ($Action -eq 'end') {
    try {
        $start = Get-Content $eventsFile -ErrorAction SilentlyContinue |
            ForEach-Object { try { $_ | ConvertFrom-Json -DateKind String } catch { $null } } |
            Where-Object { $_ -and $_.event -eq 'phase.start' -and $_.change_id -eq $Change -and $_.phase -eq $Phase } |
            Select-Object -Last 1
        if ($start) {
            $md5 = [Security.Cryptography.MD5]::HashData([Text.Encoding]::UTF8.GetBytes("sdd:$Change"))
            $traceId = [Convert]::ToHexString($md5).ToLowerInvariant()
            $spanId = [Convert]::ToHexString([Security.Cryptography.RandomNumberGenerator]::GetBytes(8)).ToLowerInvariant()
            $toNanos = { param([DateTimeOffset]$d) ([decimal]$d.ToUnixTimeMilliseconds() * 1000000).ToString('0') }
            $attr = { param($k, $v) @{ key = $k; value = @{ stringValue = "$v" } } }
            $body = @{
                resourceSpans = @(@{
                        resource   = @{ attributes = @(
                                (& $attr 'service.name' 'sdd-process'),
                                (& $attr 'sdd.change_id' $Change)
                            ) }
                        scopeSpans = @(@{
                                scope = @{ name = 'sdd.phase' }
                                spans = @(@{
                                        traceId           = $traceId
                                        spanId            = $spanId
                                        name              = "sdd.phase $Phase"
                                        kind              = 1
                                        startTimeUnixNano = (& $toNanos ([DateTimeOffset]::Parse($start.ts, [Globalization.CultureInfo]::InvariantCulture)))
                                        endTimeUnixNano   = (& $toNanos $now)
                                        attributes        = @(
                                            (& $attr 'sdd.change_id' $Change),
                                            (& $attr 'sdd.phase' $Phase),
                                            (& $attr 'sdd.iteration' $Iteration),
                                            (& $attr 'github.copilot.git.branch' $entry.branch)
                                        )
                                        status            = @{ code = $(if ($Status -eq 'ok') { 1 } else { 2 }) }
                                    })
                            })
                    })
            } | ConvertTo-Json -Depth 12 -Compress
            Invoke-RestMethod -Method Post -Uri "$($Endpoint.TrimEnd('/'))/v1/traces" -ContentType 'application/json' -Body $body -TimeoutSec 5 | Out-Null
        }
    }
    catch {
        Write-Verbose "OTLP export skipped: $($_.Exception.Message)"
    }
}

Write-Host "sdd phase $Phase $Action ($Change)"
