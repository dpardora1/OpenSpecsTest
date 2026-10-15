<#
.SYNOPSIS
    Checks that every scenario of an OpenSpec change is verified by at least one passing test.

.DESCRIPTION
    Scenarios: every "#### Scenario:" under ADDED/MODIFIED requirements of openspec/changes/<id>/specs/**/spec.md
    (or of its archived folder openspec/changes/archive/*-<id>/). Trait expected on the tests:
    [Trait("Scenario", "<capability>/<scenario-slug>")] (skill spec-traceability).

    Evidence:
      - With -ResultsDir containing TRX files (dotnet test --report-trx): authoritative. A scenario passes only if at
        least one test carrying its trait ran and all of them passed.
      - Without TRX: the traits are searched in tests/**/*.cs and reported as "not executed" (passes, with a warning).

    A change marked "skip_specs: true" in its .openspec.yaml (tooling/docs change) has nothing to trace.
    Exit codes: 0 = all scenarios traced · 1 = missing or failing scenario tests (or change not found).

.EXAMPLE
    ./scripts/traceability.ps1 -Change add-create-booking -ResultsDir ./TestResults
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidatePattern('^[a-z0-9]+(-[a-z0-9]+)*$')][string]$Change,
    [string]$ResultsDir,
    [string]$Root,
    [ValidateSet('markdown', 'json')][string]$Format = 'markdown'
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'lib/SddQuality.psm1') -Force
if (-not $Root) { $Root = (git rev-parse --show-toplevel 2>$null) ?? (Get-Location).Path }

$changeDir = Join-Path $Root "openspec/changes/$Change"
if (-not (Test-Path $changeDir)) {
    $changeDir = Get-ChildItem (Join-Path $Root 'openspec/changes/archive') -Directory -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -match "^\d{4}-\d{2}-\d{2}-$([regex]::Escape($Change))$" } | Sort-Object Name | Select-Object -Last 1 -ExpandProperty FullName
}
if (-not $changeDir) { Write-Output "❌ Change '$Change' not found in openspec/changes/ or openspec/changes/archive/"; exit 1 }

$meta = Join-Path $changeDir '.openspec.yaml'
if ((Test-Path $meta) -and (Select-String -Path $meta -Pattern '^\s*skip_specs\s*:\s*true\s*$' -Quiet)) {
    Write-Output "✅ ``$Change`` declares skip_specs: true — no scenarios to trace."
    exit 0
}

$scenarios = @(Get-ChangeScenarios -SpecsDir (Join-Path $changeDir 'specs'))
if ($scenarios.Count -eq 0) { Write-Output "❌ ``$Change`` has no ADDED/MODIFIED scenarios to trace (and does not declare skip_specs: true)."; exit 1 }

$trxFiles = @(if ($ResultsDir -and (Test-Path $ResultsDir)) { Get-ChildItem $ResultsDir -Recurse -Filter *.trx | ForEach-Object FullName })
$hasTrx = $trxFiles.Count -gt 0
$currentTraits = @(Get-ChangeScenarios -SpecsDir (Join-Path $Root 'openspec/specs') -AllSections | ForEach-Object trait)
$report = Get-TraceabilityReport -Scenarios $scenarios -HasTrx:$hasTrx -KnownTraits $currentTraits `
    -TrxResults @(if ($hasTrx) { Get-TrxScenarioResults -TrxFiles $trxFiles }) `
    -SourceTraits @(if (-not $hasTrx) { Get-SourceScenarioTraits -TestsDir (Join-Path $Root 'tests') })

if ($Format -eq 'json') {
    [ordered]@{ change = $Change; evidence = $(if ($hasTrx) { 'trx' } else { 'source' }); failures = $report.failures; orphans = $report.orphans; rows = $report.rows } | ConvertTo-Json -Depth 5
}
else {
    $icon = @{ passed = '✅'; failed = '❌ falla'; missing = '❌ sin test'; 'not-executed' = '⚠️ no ejecutado' }
    "### $(if ($report.failures) { '❌' } else { '✅' }) Trazabilidad escenario → test · ``$Change``"
    ''
    "Evidencia: $(if ($hasTrx) { "resultados TRX ($($trxFiles.Count) fichero(s))" } else { 'código fuente (sin resultados de ejecución)' })"
    ''
    '| Escenario (spec) | Trait | Tests | Resultado |'
    '|---|---|---|---|'
    foreach ($r in $report.rows) { "| $($r.title) | ``$($r.trait)`` | $(if ($r.tests) { $r.tests -join '<br>' } else { '—' }) | $($icon[$r.status]) |" }
    ''
    "Escenarios: $($report.rows.Count) · Fallos: $($report.failures)$(if ($report.orphans) { " · ⚠️ Traits sin escenario (¿errata?): $($report.orphans -join ', ')" })"
}
if ($report.failures) { exit 1 }
exit 0
