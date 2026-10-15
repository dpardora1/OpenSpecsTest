<#
.SYNOPSIS
    Runs the four SDD reviewers in parallel with Copilot CLI and consolidates their findings.

.DESCRIPTION
    Mode B of the "parallel-code-review" skill (deterministic, also usable in CI):
      1. Launches one Copilot CLI process per reviewer agent (.github/agents/<reviewer>.agent.md) at the same
         time, using the agent's model list (frontmatter `model:`) with fallback to the next model on failure.
         File edits, commits, pushes and merges are denied. Telemetry: sdd.phase=review, sdd.iteration=<n>.
      2. Saves each report in .sdd/reviews/<change>/iter-<n>/<reviewer>.md.
      3. Consolidates deterministically (dedup by file and nearby lines, +2 confidence when >= 2 reviewers agree,
         blocking = severity in blockingSeverities with confidence >= blockingMinConfidence from .sdd/sdd.config.json)
         into consolidated.md and consolidated.json.

    Exit codes: 0 = no blocking findings · 1 = blocking findings · 2 = at least one reviewer could not run.

.EXAMPLE
    ./scripts/parallel-review.ps1 -Change add-create-booking -Iteration 1
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Change,
    [int]$Iteration = 1,
    [string]$Base = 'origin/main',
    [string[]]$Reviewers,
    [string]$OutDir,
    [string]$Prompt,
    [int]$MaxAiCredits = 0,
    [int]$TimeoutMinutes = 20
)

$ErrorActionPreference = 'Stop'
$root = (git rev-parse --show-toplevel 2>$null) ?? (Get-Location).Path
$config = Get-Content (Join-Path $root '.sdd/sdd.config.json') -Raw | ConvertFrom-Json
if (-not $Reviewers) { $Reviewers = $config.reviewers }
if (-not $OutDir) { $OutDir = Join-Path $root ".sdd/reviews/$Change/iter-$Iteration" }
New-Item -ItemType Directory -Force $OutDir | Out-Null

if (-not $Prompt) {
    $Prompt = "Revisa el change '$Change' (iteración $Iteration) en la rama actual contra '$Base'. " +
    "Obtén el diff con 'git --no-pager diff $Base...HEAD' y los artefactos en openspec/changes/$Change/ (o su carpeta archivada en openspec/changes/archive/). " +
    'Devuelve EXCLUSIVAMENTE tu informe con el contrato de salida de tu agente.'
}

function Get-AgentModels([string]$agent) {
    $file = Join-Path $root ".github/agents/$agent.agent.md"
    if (-not (Test-Path $file)) { throw "Agent file not found: $file" }
    $line = (Get-Content $file | Select-String -Pattern '^model:\s*(.+)$' | Select-Object -First 1)
    if (-not $line) { return @($null) }
    $value = $line.Matches[0].Groups[1].Value.Trim()
    if ($value.StartsWith('[')) {
        return @([regex]::Matches($value, "'([^']+)'|`"([^`"]+)`"") | ForEach-Object { $_.Groups[1].Value + $_.Groups[2].Value })
    }
    return @($value.Trim('''', '"'))
}

$otelEndpoint = $env:OTEL_EXPORTER_OTLP_ENDPOINT ?? 'http://localhost:4318'
$started = [DateTimeOffset]::UtcNow
$jobs = foreach ($reviewer in $Reviewers) {
    $models = Get-AgentModels $reviewer
    Start-Job -Name $reviewer -ArgumentList $root, $reviewer, $models, $Prompt, $Change, $Iteration, $MaxAiCredits, $otelEndpoint -ScriptBlock {
        param($root, $reviewer, $models, $prompt, $change, $iteration, $maxCredits, $otelEndpoint)
        Set-Location $root
        # Copilot CLI writes UTF-8; background jobs default to the OEM code page (garbled accents in reports).
        [Console]::OutputEncoding = [Text.Encoding]::UTF8
        $OutputEncoding = [Text.Encoding]::UTF8
        $env:SDD_CHANGE_ID = $change
        $env:SDD_PHASE = 'review'
        $env:OTEL_EXPORTER_OTLP_ENDPOINT = $otelEndpoint
        $env:OTEL_INSTRUMENTATION_GENAI_CAPTURE_MESSAGE_CONTENT = 'true'
        $env:OTEL_RESOURCE_ATTRIBUTES = "sdd.change_id=$change,sdd.phase=review,sdd.iteration=$iteration,sdd.reviewer=$reviewer"
        $attempts = @()
        foreach ($model in $models) {
            $start = [DateTimeOffset]::UtcNow
            $cliArgs = @('-p', $prompt, '--agent', $reviewer, '--allow-all-tools', '--no-ask-user', '-s',
                '--deny-tool', 'write', '--deny-tool', 'shell(git push)', '--deny-tool', 'shell(git commit)',
                '--deny-tool', 'shell(gh pr merge)', '--deny-tool', 'shell(gh pr review)')
            if ($model) { $cliArgs += @('--model', $model) }
            if ($maxCredits -gt 0) { $cliArgs += @('--max-ai-credits', "$maxCredits") }
            $output = (& copilot @cliArgs 2>&1 | Out-String).Trim()
            $exit = $LASTEXITCODE
            $ok = ($exit -eq 0) -and ($output -match 'Veredicto\s*:')
            $attempts += [pscustomobject]@{ model = $model; exit = $exit; ok = $ok; start = $start; end = [DateTimeOffset]::UtcNow }
            if ($ok) {
                return [pscustomobject]@{ reviewer = $reviewer; model = $model; ok = $true; output = $output; attempts = $attempts }
            }
        }
        [pscustomobject]@{ reviewer = $reviewer; model = $null; ok = $false; output = $output; attempts = $attempts }
    }
}

Write-Host "Launched $($jobs.Count) reviewers in parallel for '$Change' (iteration $Iteration)..."
$null = $jobs | Wait-Job -Timeout ($TimeoutMinutes * 60)
$results = foreach ($job in $jobs) {
    if ($job.State -eq 'Completed') { Receive-Job $job }
    else {
        Stop-Job $job
        [pscustomobject]@{ reviewer = $job.Name; model = $null; ok = $false; output = "Timed out after $TimeoutMinutes min"; attempts = @() }
    }
}
$jobs | Remove-Job -Force

# ---- Parse reports ------------------------------------------------------------------------------
$severityRank = @{ BLOCKER = 4; HIGH = 3; MEDIUM = 2; LOW = 1 }
$findings = [System.Collections.Generic.List[object]]::new()
$summary = foreach ($r in $results) {
    $r.output | Set-Content (Join-Path $OutDir "$($r.reviewer).md") -Encoding utf8
    $verdict = if ($r.output -match 'Veredicto\s*:\s*\**\s*(APPROVE|REQUEST_CHANGES)') { $Matches[1] } else { 'N/D' }
    foreach ($m in [regex]::Matches($r.output, '(?m)^\|\s*(\d+)\s*\|\s*\**(BLOCKER|HIGH|MEDIUM|LOW)\**\s*\|([^|]*)\|([^|]*)\|([^|]*)\|\s*(\d+)\s*\|')) {
        $location = $m.Groups[3].Value.Trim().Trim('`')
        $file = $location; $lineNo = 0
        if ($location -match '^(.+?):(\d+)') { $file = $Matches[1]; $lineNo = [int]$Matches[2] }
        $findings.Add([pscustomobject]@{
                reviewer = $r.reviewer; severity = $m.Groups[2].Value; file = $file.Trim(); line = $lineNo
                location = $location; finding = $m.Groups[4].Value.Trim(); suggestion = $m.Groups[5].Value.Trim()
                confidence = [int]$m.Groups[6].Value
            })
    }
    $first = @($r.attempts | Sort-Object start | Select-Object -First 1)
    $last = @($r.attempts | Sort-Object end | Select-Object -Last 1)
    [pscustomobject]@{
        reviewer  = $r.reviewer
        model     = $r.model ?? 'N/D'
        ok        = $r.ok
        verdict   = $verdict
        findings  = @($findings | Where-Object reviewer -eq $r.reviewer).Count
        start_s   = if ($first) { [Math]::Round(($first[0].start - $started).TotalSeconds, 1) } else { $null }
        duration_s = if ($first -and $last) { [Math]::Round(($last[0].end - $first[0].start).TotalSeconds, 1) } else { $null }
        attempts  = @($r.attempts | ForEach-Object { "$($_.model ?? 'default'):$(if ($_.ok) { 'ok' } else { "exit $($_.exit)" })" }) -join ', '
    }
}

# ---- Consolidate --------------------------------------------------------------------------------
$groups = [System.Collections.Generic.List[object]]::new()
foreach ($f in ($findings | Sort-Object file, line)) {
    $g = $groups | Where-Object { $_.file -eq $f.file -and [Math]::Abs($_.line - $f.line) -le 5 } | Select-Object -First 1
    if (-not $g) {
        $g = [pscustomobject]@{ file = $f.file; line = $f.line; severity = $f.severity; confidence = $f.confidence; reviewers = [Collections.Generic.List[string]]::new(); items = [Collections.Generic.List[object]]::new() }
        $groups.Add($g)
    }
    if ($severityRank[$f.severity] -gt $severityRank[$g.severity]) { $g.severity = $f.severity }
    $g.confidence = [Math]::Max($g.confidence, $f.confidence)
    if (-not $g.reviewers.Contains($f.reviewer)) { $g.reviewers.Add($f.reviewer) }
    $g.items.Add($f)
}
foreach ($g in $groups) {
    if ($g.reviewers.Count -ge 2) { $g.confidence = [Math]::Min(10, $g.confidence + 2) }
    $g | Add-Member -NotePropertyName blocking -NotePropertyValue (($config.blockingSeverities -contains $g.severity) -and $g.confidence -ge $config.blockingMinConfidence)
}
$blocking = @($groups | Where-Object blocking)
$failed = @($summary | Where-Object { -not $_.ok })

$sb = [Text.StringBuilder]::new()
[void]$sb.AppendLine("## 🤖 Revisión paralela · ``$Change`` · iteración $Iteration")
[void]$sb.AppendLine()
[void]$sb.AppendLine('| Revisor | Modelo | Veredicto | Hallazgos | Inicio (s) | Duración (s) | Intentos |')
[void]$sb.AppendLine('|---|---|---|---|---|---|---|')
foreach ($s in $summary) { [void]$sb.AppendLine("| $($s.reviewer) | $($s.model) | $(if ($s.ok) { $s.verdict } else { '❌ no ejecutado' }) | $($s.findings) | $($s.start_s) | $($s.duration_s) | $($s.attempts) |") }
[void]$sb.AppendLine()
[void]$sb.AppendLine("**Bloqueantes: $($blocking.Count)** (severidad $($config.blockingSeverities -join '/') y confianza ≥ $($config.blockingMinConfidence)) · Hallazgos consolidados: $($groups.Count) · Revisores fallidos: $($failed.Count)")
[void]$sb.AppendLine()
if ($groups.Count) {
    [void]$sb.AppendLine('| # | Bloqueante | Severidad | Ubicación | Revisores | Confianza | Hallazgo | Sugerencia |')
    [void]$sb.AppendLine('|---|---|---|---|---|---|---|---|')
    $i = 0
    foreach ($g in ($groups | Sort-Object @{ e = { -$severityRank[$_.severity] } }, @{ e = { -$_.confidence } })) {
        $i++
        $main = $g.items | Sort-Object @{ e = { -$severityRank[$_.severity] } }, @{ e = { -$_.confidence } } | Select-Object -First 1
        [void]$sb.AppendLine("| $i | $(if ($g.blocking) { '⛔' } else { '' }) | $($g.severity) | ``$($main.location)`` | $($g.reviewers -join ', ') | $($g.confidence) | $($main.finding) | $($main.suggestion) |")
    }
}
$markdown = $sb.ToString()
$markdown | Set-Content (Join-Path $OutDir 'consolidated.md') -Encoding utf8
[ordered]@{
    change = $Change; iteration = $Iteration; base = $Base; started = $started.ToString('o')
    reviewers = $summary; blocking = $blocking.Count; failedReviewers = $failed.Count
    findings = @($groups | Select-Object file, line, severity, confidence, blocking, @{ n = 'reviewers'; e = { @($_.reviewers) } }, @{ n = 'items'; e = { @($_.items) } })
} | ConvertTo-Json -Depth 8 | Set-Content (Join-Path $OutDir 'consolidated.json') -Encoding utf8

$markdown
if ($failed.Count) { exit 2 }
if ($blocking.Count) { exit 1 }
exit 0
