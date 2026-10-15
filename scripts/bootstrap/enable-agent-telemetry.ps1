<#
.SYNOPSIS
    Enables agent telemetry on this developer machine (idempotent).

.DESCRIPTION
    1. VS Code user settings: Copilot Chat OpenTelemetry export to the local collector. These settings are
       application-scoped, so they are ignored in .vscode/settings.json (lesson L-002).
    2. Optional (-TrustRepo): adds the repository to `trustedFolders` in ~/.copilot/config.json so repository
       hooks (.github/hooks) run in Copilot CLI sessions (lesson L-001).
       ⚠ Trust is per FOLDER, not per commit: any branch checked out in this folder will run its hooks with your
       user account. Reviews are isolated from this (scripts/parallel-review.ps1 runs in an untrusted worktree),
       but only opt in on a machine where you accept that risk.
    A one-time backup (*.bak-sdd) is written before the first modification of each file. Files with comments
    (JSONC) are not modified: the script prints the settings to add manually instead.

.EXAMPLE
    ./scripts/bootstrap/enable-agent-telemetry.ps1 -TrustRepo
    ./scripts/bootstrap/enable-agent-telemetry.ps1 -NoCaptureContent
#>
[CmdletBinding()]
param(
    [string]$Endpoint = 'http://localhost:4318',
    [switch]$NoCaptureContent,
    [switch]$TrustRepo
)

$ErrorActionPreference = 'Stop'
$root = (git rev-parse --show-toplevel 2>$null) ?? (Get-Location).Path

function Update-JsonFile([string]$path, [scriptblock]$mutate) {
    if (-not (Test-Path $path)) {
        New-Item -ItemType Directory -Force (Split-Path $path) | Out-Null
        '{}' | Set-Content $path -Encoding utf8
    }
    $raw = Get-Content $path -Raw
    try { $data = $raw | ConvertFrom-Json -AsHashtable -Depth 64 }
    catch { Write-Warning "$path is not strict JSON (comments?). Not modified."; return $false }
    if ($null -eq $data) { $data = @{} }
    if (-not (Test-Path "$path.bak-sdd")) { Copy-Item $path "$path.bak-sdd" }
    & $mutate $data
    $data | ConvertTo-Json -Depth 64 | Set-Content $path -Encoding utf8
    return $true
}

$otel = [ordered]@{
    'github.copilot.chat.otel.enabled'                = $true
    'github.copilot.chat.otel.exporterType'           = 'otlp-http'
    'github.copilot.chat.otel.otlpEndpoint'           = $Endpoint
    'github.copilot.chat.otel.captureContent'         = -not $NoCaptureContent
    'github.copilot.chat.otel.dbSpanExporter.enabled' = $true
}

$userDirs = if ($IsWindows) { @("$env:APPDATA/Code/User", "$env:APPDATA/Code - Insiders/User") }
elseif ($IsMacOS) { @("$HOME/Library/Application Support/Code/User", "$HOME/Library/Application Support/Code - Insiders/User") }
else { @("$HOME/.config/Code/User", "$HOME/.config/Code - Insiders/User") }

foreach ($dir in ($userDirs | Where-Object { Test-Path $_ })) {
    $file = Join-Path $dir 'settings.json'
    $ok = Update-JsonFile $file { param($d) foreach ($k in $otel.Keys) { $d[$k] = $otel[$k] } }
    if ($ok) { Write-Host "VS Code user settings updated: $file" }
    else { Write-Host "Add these settings manually to ${file}:"; $otel | ConvertTo-Json }
}

if ($TrustRepo) {
    Write-Warning 'Trusting this folder lets ANY branch checked out here run its .github/hooks with your account.'
    $cliConfig = Join-Path ($env:COPILOT_HOME ?? (Join-Path $HOME '.copilot')) 'config.json'
    $ok = Update-JsonFile $cliConfig {
        param($d)
        $list = [System.Collections.Generic.List[string]]::new()
        if ($d.ContainsKey('trustedFolders')) { foreach ($f in $d['trustedFolders']) { $list.Add([string]$f) } }
        $repoPath = (Resolve-Path $root).Path
        if (-not ($list | Where-Object { $_ -ieq $repoPath })) { $list.Add($repoPath) }
        $d['trustedFolders'] = $list.ToArray()
    }
    if ($ok) { Write-Host "Copilot CLI trusted folder ensured in $cliConfig" }
}
else {
    Write-Host 'Copilot CLI hooks not enabled (use -TrustRepo to opt in; see lesson L-001).'
}

Write-Host 'Done. Reload VS Code (Developer: Reload Window) and start the stack: docker compose -f observability/compose.yaml up -d'
