<#
.SYNOPSIS
    Checks that every scenario of an OpenSpec change is verified by at least one passing test.

.DESCRIPTION
    Scenarios: every "#### Scenario:" under ADDED/MODIFIED requirements of openspec/changes/<id>/specs/**/spec.md
    (or of its archived folder openspec/changes/archive/*-<id>/). Trait expected on the tests:
    [Trait("Scenario", "<capability>/<scenario-slug>")] (skill spec-traceability).

    Evidence:
      - TRX files in -ResultsDir (dotnet test --report-trx): authoritative. A scenario passes only if at least one test
        carrying its trait ran and all of them passed.
      - Without TRX the traits are searched in tests/**/*.cs and reported as "not executed": this is a diagnostic,
        never a pass (exit code 3). With -RequireTrx (used by the quality gate once a .NET solution exists) a missing
        TRX is a failure.

    "skip_specs: true" in the change's .openspec.yaml (tooling/docs change) is honored only when the change really has
    no ADDED/MODIFIED scenarios: it can never hide scenarios from traceability.

    Exit codes: 0 = all scenarios traced by passing tests (or nothing to trace) · 1 = missing/failing scenario tests,
    missing TRX with -RequireTrx, or change not found · 3 = traced only in source code (not executed).

.EXAMPLE
    ./scripts/traceability.ps1 -Change add-create-booking -ResultsDir ./TestResults -RequireTrx
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidatePattern('^[a-z0-9]+(-[a-z0-9]+)*$')][string]$Change,
    [string]$ResultsDir,
    [switch]$RequireTrx,
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

$scenarios = @(Get-ChangeScenarios -SpecsDir (Join-Path $changeDir 'specs'))
$meta = Join-Path $changeDir '.openspec.yaml'
$skipSpecs = (Test-Path $meta) -and (Select-String -Path $meta -Pattern '^\s*skip_specs\s*:\s*true\s*$' -Quiet)
if ($scenarios.Count -eq 0) {
    if ($skipSpecs) { Write-Output "✅ ``$Change`` declares skip_specs: true and has no scenarios — nothing to trace."; exit 0 }
    Write-Output "❌ ``$Change`` has no ADDED/MODIFIED scenarios to trace (and does not declare skip_specs: true)."
    exit 1
}
$skipNote = if ($skipSpecs) { "⚠️ ``skip_specs: true`` se ignora: el change tiene $($scenarios.Count) escenario(s) ADDED/MODIFIED." }

$trxFiles = @(if ($ResultsDir -and (Test-Path $ResultsDir)) { Get-ChildItem $ResultsDir -Recurse -Filter *.trx | ForEach-Object FullName })
$hasTrx = $trxFiles.Count -gt 0
if ($RequireTrx -and -not $hasTrx) {
    Write-Output "❌ No TRX results found in '$ResultsDir': traceability requires executed tests (dotnet test --report-trx)."
    exit 1
}
$currentTraits = @(Get-ChangeScenarios -SpecsDir (Join-Path $Root 'openspec/specs') -AllSections | ForEach-Object trait)
$report = Get-TraceabilityReport -Scenarios $scenarios -HasTrx:$hasTrx -KnownTraits $currentTraits `
    -TrxResults @(if ($hasTrx) { Get-TrxScenarioResults -TrxFiles $trxFiles }) `
    -SourceTraits @(if (-not $hasTrx) { Get-SourceScenarioTraits -TestsDir (Join-Path $Root 'tests') })

if ($Format -eq 'json') {
    [ordered]@{ change = $Change; evidence = $(if ($hasTrx) { 'trx' } else { 'source' }); failures = $report.failures; orphans = $report.orphans; rows = $report.rows } | ConvertTo-Json -Depth 5
}
else {
    $icon = @{ passed = '✅'; failed = '❌ falla'; missing = '❌ sin test'; 'not-executed' = '⚠️ no ejecutado' }
    $title = if ($report.failures) { '❌' } elseif ($hasTrx) { '✅' } else { '⚠️' }
    "### $title Trazabilidad escenario → test · ``$Change``"
    ''
    "Evidencia: $(if ($hasTrx) { "resultados TRX ($($trxFiles.Count) fichero(s))" } else { 'solo código fuente: los tests NO se han ejecutado' })"
    if ($skipNote) { ''; $skipNote }
    ''
    '| Escenario (spec) | Trait | Tests | Resultado |'
    '|---|---|---|---|'
    foreach ($r in $report.rows) { "| $($r.title) | ``$($r.trait)`` | $(if ($r.tests) { $r.tests -join '<br>' } else { '—' }) | $($icon[$r.status]) |" }
    ''
    "Escenarios: $($report.rows.Count) · Fallos: $($report.failures)$(if ($report.orphans) { " · ⚠️ Traits sin escenario (¿errata?): $($report.orphans -join ', ')" })"
}
if ($report.failures) { exit 1 }
if (-not $hasTrx) { exit 3 }
exit 0
