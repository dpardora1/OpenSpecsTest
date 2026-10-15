<#
.SYNOPSIS
    Aggregates agent telemetry for one SDD change into the "📈 Métricas del ciclo" PR section and history.csv.

.DESCRIPTION
    Sources (written by the local observability stack and hooks, see observability/README.md):
      - .sdd/telemetry/otel*.jsonl  : OTLP JSON lines from the OpenTelemetry Collector (traces from Copilot Chat/CLI)
      - .sdd/telemetry/events.jsonl : phase.start/phase.end (scripts/sdd-phase.ps1) and Copilot hook events

    A trace belongs to a change when any of its spans has resource/span attribute sdd.change_id = <Change>
    or github.copilot.git.branch = sdd/<Change>. Token usage is summed from "chat" spans only (invoke_agent
    spans carry session totals and would double count). Each chat/tool span is attributed to its nearest
    invoke_agent ancestor, so subagents (e.g. the 4 reviewers) get their own row.

.EXAMPLE
    ./scripts/sdd-metrics.ps1 -Change add-create-booking
    ./scripts/sdd-metrics.ps1 -Change add-create-booking -ReviewIterations 2 -Blockers 1 -AppendHistory
    ./scripts/sdd-metrics.ps1 -Change add-create-booking -Format json
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Change,
    [string]$TelemetryDir,
    [ValidateSet('markdown', 'json')][string]$Format = 'markdown',
    [switch]$AppendHistory,
    [int]$ReviewIterations = 0,
    [int]$Blockers = 0,
    [string]$HistoryFile
)

$ErrorActionPreference = 'Stop'
$root = git rev-parse --show-toplevel 2>$null
if (-not $root) { $root = (Get-Location).Path }
if (-not $TelemetryDir) { $TelemetryDir = Join-Path $root '.sdd/telemetry' }
if (-not $HistoryFile) { $HistoryFile = Join-Path $root '.sdd/metrics/history.csv' }
$inv = [Globalization.CultureInfo]::InvariantCulture

function Get-AttrValue($v) {
    if ($null -eq $v) { return $null }
    foreach ($k in 'stringValue', 'intValue', 'doubleValue', 'boolValue') {
        if ($v.PSObject.Properties.Name -contains $k) {
            $x = $v.$k
            if ($k -eq 'intValue') { return [long]$x }
            if ($k -eq 'doubleValue') { return [double]$x }
            return $x
        }
    }
    return $null
}

function ConvertTo-AttrMap($list) {
    $m = @{}
    foreach ($a in @($list)) { if ($a) { $m[$a.key] = Get-AttrValue $a.value } }
    return $m
}

function Format-Duration([double]$seconds) {
    if ($seconds -lt 60) { return ('{0:0.0} s' -f $seconds).Replace(',', '.') }
    $ts = [TimeSpan]::FromSeconds($seconds)
    if ($ts.TotalHours -ge 1) { return '{0}h {1:00}m' -f [int][Math]::Floor($ts.TotalHours), $ts.Minutes }
    return '{0}m {1:00}s' -f $ts.Minutes, $ts.Seconds
}

function Format-Number([double]$n) { $n.ToString('N0', [Globalization.CultureInfo]::GetCultureInfo('es-ES')) }

# ---- Load spans -------------------------------------------------------------------------------
$spans = [System.Collections.Generic.List[object]]::new()
$files = Get-ChildItem -Path $TelemetryDir -Filter 'otel*.jsonl' -File -ErrorAction SilentlyContinue
foreach ($file in $files) {
    # The collector keeps the file open while writing: read it with a shared handle.
    $stream = [IO.FileStream]::new($file.FullName, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::ReadWrite -bor [IO.FileShare]::Delete)
    $reader = [IO.StreamReader]::new($stream)
    try {
        while ($null -ne ($line = $reader.ReadLine())) {
            if (-not $line.Contains('resourceSpans')) { continue }
            $doc = $line | ConvertFrom-Json -Depth 64
            foreach ($rs in $doc.resourceSpans) {
                $res = ConvertTo-AttrMap $rs.resource.attributes
                foreach ($ss in $rs.scopeSpans) {
                    foreach ($s in $ss.spans) {
                        $spans.Add([pscustomobject]@{
                                TraceId  = $s.traceId
                                SpanId   = $s.spanId
                                ParentId = $s.parentSpanId
                                Name     = $s.name
                                Start    = [decimal]$s.startTimeUnixNano
                                End      = [decimal]$s.endTimeUnixNano
                                Attr     = ConvertTo-AttrMap $s.attributes
                                Res      = $res
                            })
                    }
                }
            }
        }
    }
    finally {
        $reader.Dispose()
    }
}

$branch = "sdd/$Change"
$traceIds = $spans |
    Where-Object { $_.Res['sdd.change_id'] -eq $Change -or $_.Attr['sdd.change_id'] -eq $Change -or $_.Attr['github.copilot.git.branch'] -eq $branch } |
    Select-Object -ExpandProperty TraceId -Unique
$selected = @($spans | Where-Object { $traceIds -contains $_.TraceId -and $_.Res['service.name'] -ne 'sdd-process' })

$byId = @{}
foreach ($s in $selected) { $byId["$($s.TraceId)/$($s.SpanId)"] = $s }

function Get-AgentName($span) {
    $cur = $span
    while ($cur) {
        if ($cur.Name -like 'invoke_agent*') {
            $n = $cur.Attr['gen_ai.agent.name']
            if (-not $n) { $n = ($cur.Name -replace '^invoke_agent\s*', '') }
            if (-not $n) { $n = '(agent)' }
            return $n
        }
        if (-not $cur.ParentId) { break }
        $cur = $byId["$($cur.TraceId)/$($cur.ParentId)"]
    }
    return '(sin agente)'
}

# ---- Aggregate per agent ----------------------------------------------------------------------
$agents = [ordered]@{}
function Get-Row([string]$name) {
    if (-not $agents.Contains($name)) {
        $agents[$name] = [ordered]@{
            agent = $name; models = [Collections.Generic.HashSet[string]]::new(); invocations = 0; duration_s = 0.0
            llm_calls = 0; tokens_in = 0L; tokens_out = 0L; cache_read = 0L; tool_calls = 0; cost = 0.0
        }
    }
    return $agents[$name]
}

foreach ($s in $selected) {
    $seconds = [double](($s.End - $s.Start) / 1e9)
    if ($s.Name -like 'invoke_agent*') {
        $row = Get-Row (Get-AgentName $s)
        $row.invocations++
        $row.duration_s += $seconds
    }
    elseif ($s.Name -like 'chat *' -or $s.Attr['gen_ai.operation.name'] -eq 'chat') {
        $row = Get-Row (Get-AgentName $s)
        $row.llm_calls++
        $row.tokens_in += [long]($s.Attr['gen_ai.usage.input_tokens'] ?? 0)
        $row.tokens_out += [long]($s.Attr['gen_ai.usage.output_tokens'] ?? 0)
        $row.cache_read += [long]($s.Attr['gen_ai.usage.cache_read.input_tokens'] ?? 0)
        $row.cost += [double]($s.Attr['github.copilot.cost'] ?? 0)
        $model = $s.Attr['gen_ai.response.model'] ?? $s.Attr['gen_ai.request.model']
        if ($model) { [void]$row.models.Add($model) }
    }
    elseif ($s.Name -like 'execute_tool*') {
        $row = Get-Row (Get-AgentName $s)
        $row.tool_calls++
    }
}

# ---- Phases and hook events -------------------------------------------------------------------
$events = @()
$eventsFile = Join-Path $TelemetryDir 'events.jsonl'
if (Test-Path $eventsFile) {
    $events = @(Get-Content $eventsFile | ForEach-Object { try { $_ | ConvertFrom-Json -DateKind String } catch { $null } } |
            Where-Object { $_ -and ($_.change_id -eq $Change -or $_.branch -eq $branch) })
}
$phases = @()
$open = @{}
foreach ($e in $events) {
    $key = "$($e.phase)#$($e.iteration)"
    if ($e.event -eq 'phase.start') { $open[$key] = $e }
    elseif ($e.event -eq 'phase.end' -and $open.ContainsKey($key)) {
        $startTs = [DateTimeOffset]::Parse($open[$key].ts, $inv)
        $endTs = [DateTimeOffset]::Parse($e.ts, $inv)
        $phases += [pscustomobject]@{ phase = $e.phase; iteration = [int]($e.iteration ?? 1); duration_s = ($endTs - $startTs).TotalSeconds; status = $e.status; start = $startTs; end = $endTs }
        $open.Remove($key)
    }
}
$subagents = @($events | Where-Object event -eq 'subagentStart').Count
$toolFailures = @($events | Where-Object event -eq 'postToolUseFailure').Count

# ---- Totals -----------------------------------------------------------------------------------
$rows = @($agents.Values | ForEach-Object { [pscustomobject]$_ })
$wallStart = @(); $wallEnd = @()
if ($selected.Count) {
    $wallStart += [DateTimeOffset]::FromUnixTimeMilliseconds([long](($selected | Measure-Object Start -Minimum).Minimum / 1e6))
    $wallEnd += [DateTimeOffset]::FromUnixTimeMilliseconds([long](($selected | Measure-Object End -Maximum).Maximum / 1e6))
}
if ($phases.Count) { $wallStart += ($phases.start | Sort-Object | Select-Object -First 1); $wallEnd += ($phases.end | Sort-Object | Select-Object -Last 1) }
$wallClock = if ($wallStart.Count) { (($wallEnd | Sort-Object | Select-Object -Last 1) - ($wallStart | Sort-Object | Select-Object -First 1)).TotalSeconds } else { 0 }

$totals = [ordered]@{
    change_id         = $Change
    date              = [DateTimeOffset]::UtcNow.ToString('yyyy-MM-dd')
    wall_clock_min    = [Math]::Round($wallClock / 60, 2)
    llm_calls         = [long](($rows | Measure-Object llm_calls -Sum).Sum ?? 0)
    tokens_in         = [long](($rows | Measure-Object tokens_in -Sum).Sum ?? 0)
    tokens_out        = [long](($rows | Measure-Object tokens_out -Sum).Sum ?? 0)
    cache_read        = [long](($rows | Measure-Object cache_read -Sum).Sum ?? 0)
    tool_calls        = [long](($rows | Measure-Object tool_calls -Sum).Sum ?? 0)
    tool_failures     = $toolFailures
    subagents         = $subagents
    cost              = [Math]::Round([double](($rows | Measure-Object cost -Sum).Sum ?? 0), 2)
    review_iterations = $ReviewIterations
    blockers          = $Blockers
    traces            = @($selected.TraceId | Select-Object -Unique).Count
}

# ---- History ----------------------------------------------------------------------------------
if ($AppendHistory) {
    New-Item -ItemType Directory -Force (Split-Path $HistoryFile) | Out-Null
    $history = @()
    if (Test-Path $HistoryFile) { $history = @(Import-Csv $HistoryFile | Where-Object change_id -ne $Change) }
    $newRow = [pscustomobject]([ordered]@{} + $totals)
    $newRow.PSObject.Properties.Remove('traces')
    ($history + $newRow) | ForEach-Object {
        $o = $_; $o.PSObject.Properties | ForEach-Object { if ($_.Value -is [double]) { $_.Value = $_.Value.ToString($inv) } }; $o
    } | Export-Csv $HistoryFile -NoTypeInformation -Encoding utf8 -UseQuotes AsNeeded
}

# ---- Output -----------------------------------------------------------------------------------
if ($Format -eq 'json') {
    [ordered]@{
        totals = $totals
        agents = @($rows | Select-Object agent, @{ n = 'models'; e = { @($_.models) } }, invocations, duration_s, llm_calls, tokens_in, tokens_out, cache_read, tool_calls, cost)
        phases = @($phases | Select-Object phase, iteration, duration_s, status)
    } | ConvertTo-Json -Depth 6
    return
}

$sb = [Text.StringBuilder]::new()
[void]$sb.AppendLine("### 📈 Métricas del ciclo · ``$Change``")
[void]$sb.AppendLine()
if ($phases.Count) {
    [void]$sb.AppendLine('| Fase | Iteración | Duración | Estado |')
    [void]$sb.AppendLine('|---|---|---|---|')
    foreach ($p in $phases) { [void]$sb.AppendLine("| $($p.phase) | $($p.iteration) | $(Format-Duration $p.duration_s) | $(if ($p.status -eq 'error') { '❌' } else { '✅' }) |") }
    [void]$sb.AppendLine()
}
[void]$sb.AppendLine('| Agente | Modelo(s) | Invocaciones | Duración | Llamadas LLM | Tokens in | Tokens out | Caché leída | Herramientas | Coste |')
[void]$sb.AppendLine('|---|---|---|---|---|---|---|---|---|---|')
foreach ($r in $rows) {
    [void]$sb.AppendLine("| $($r.agent) | $(@($r.models) -join ', ') | $($r.invocations) | $(Format-Duration $r.duration_s) | $($r.llm_calls) | $(Format-Number $r.tokens_in) | $(Format-Number $r.tokens_out) | $(Format-Number $r.cache_read) | $($r.tool_calls) | $($r.cost.ToString('0.00', $inv)) |")
}
[void]$sb.AppendLine("| **Total** | | | **$(Format-Duration $wallClock)** (reloj) | **$($totals.llm_calls)** | **$(Format-Number $totals.tokens_in)** | **$(Format-Number $totals.tokens_out)** | **$(Format-Number $totals.cache_read)** | **$($totals.tool_calls)** | **$($totals.cost.ToString('0.00', $inv))** |")
[void]$sb.AppendLine()
[void]$sb.AppendLine("Subagentes lanzados: $subagents · Fallos de herramientas: $toolFailures · Iteraciones de revisión: $ReviewIterations · Bloqueantes: $Blockers · Trazas: $($totals.traces)")
$sb.ToString()
