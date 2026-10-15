<#
.SYNOPSIS
    Copilot hook: appends a lifecycle event (session, subagent, failures) to .sdd/telemetry/events.jsonl.
.NOTES
    Invoked by .github/hooks/sdd-telemetry.json with the hook payload on stdin.
    Never fails the agent: any error is swallowed and the script always exits 0.
#>
param([Parameter(Mandatory)][string]$Event)

try {
    $raw = [Console]::In.ReadToEnd()
    $payload = $null
    if ($raw) {
        try { $payload = $raw | ConvertFrom-Json -AsHashtable -Depth 20 } catch { $payload = @{ raw = $raw } }
    }

    $dir = Join-Path (Get-Location) '.sdd/telemetry'
    New-Item -ItemType Directory -Force $dir | Out-Null

    $entry = [ordered]@{
        ts        = [DateTimeOffset]::UtcNow.ToString('o')
        event     = $Event
        branch    = (git branch --show-current 2>$null)
        change_id = $env:SDD_CHANGE_ID
        phase     = $env:SDD_PHASE
        payload   = $payload
    }
    ($entry | ConvertTo-Json -Depth 20 -Compress) | Add-Content -Path (Join-Path $dir 'events.jsonl') -Encoding utf8
}
catch {
    # Telemetry must never break the agent session.
}
exit 0
