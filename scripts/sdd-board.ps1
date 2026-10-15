<#
.SYNOPSIS
    Adds an Issue (or PR) to the SDD GitHub Project board and sets its Status column and Change ID.

.DESCRIPTION
    The board is a user-owned GitHub Project, which a GitHub App (the agents' bot identity) cannot access.
    This script therefore uses the human's `gh` session (keyring) instead of the bot token: it temporarily
    removes GH_TOKEN/GITHUB_TOKEN from the environment and restores them afterwards.
    Board updates are best effort: failures are reported as warnings and never break the SDD workflow
    (e.g. in the Copilot cloud agent, where no user session exists).

.EXAMPLE
    ./scripts/sdd-board.ps1 -Issue 12 -Status dev -ChangeId add-create-booking
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][int]$Issue,
    [Parameter(Mandatory)][ValidateSet('idea', 'approved', 'spec', 'dev', 'pr', 'done')][string]$Status,
    [ValidatePattern('^[a-z0-9]+(-[a-z0-9]+)*$')][string]$ChangeId
)

$ErrorActionPreference = 'Stop'
$root = (git rev-parse --show-toplevel 2>$null) ?? (Get-Location).Path
# The board is updated with the HUMAN's gh session, so its destination must not come from an unreviewed branch:
# read the config from origin/main when available and check it targets this repository's origin.
$configJson = git -C $root show 'origin/main:.sdd/sdd.config.json' 2>$null
if ($LASTEXITCODE -ne 0 -or -not $configJson) { $configJson = Get-Content (Join-Path $root '.sdd/sdd.config.json') -Raw }
$config = ($configJson -join "`n") | ConvertFrom-Json
$originUrl = git -C $root remote get-url origin 2>$null
if ($originUrl -notmatch "github\.com[:/]$([regex]::Escape($config.repo))(\.git)?$") { throw "sdd.config.json repo '$($config.repo)' does not match origin '$originUrl'" }
if ($config.project.owner -ne ($config.repo -split '/')[0]) { throw "Project owner '$($config.project.owner)' must be the repository owner" }
$owner = $config.project.owner
$number = $config.project.number
$statusName = $config.project.statuses.$Status

function Invoke-Gh {
    $out = & gh @args
    if ($LASTEXITCODE -ne 0) { throw "gh $($args[0..2] -join ' ') failed (exit $LASTEXITCODE)" }
    $out
}

$tokenVars = 'GH_TOKEN', 'GITHUB_TOKEN', 'GH_ENTERPRISE_TOKEN', 'GITHUB_ENTERPRISE_TOKEN'
$saved = @{}
foreach ($v in $tokenVars) { $saved[$v] = [Environment]::GetEnvironmentVariable($v); Remove-Item "Env:$v" -ErrorAction SilentlyContinue }
try {
    $url = Invoke-Gh api "repos/$($config.repo)/issues/$Issue" --jq '.html_url'
    if (-not $url) { throw "Issue/PR #$Issue not found in $($config.repo)" }

    $item = Invoke-Gh project item-add $number --owner $owner --url $url --format json | ConvertFrom-Json
    $project = Invoke-Gh project view $number --owner $owner --format json | ConvertFrom-Json
    $fields = (Invoke-Gh project field-list $number --owner $owner --format json | ConvertFrom-Json).fields

    $statusField = $fields | Where-Object name -eq $config.project.statusField
    $option = $statusField.options | Where-Object name -eq $statusName
    if (-not $option) { throw "Status option '$statusName' not found in field '$($config.project.statusField)'" }
    Invoke-Gh project item-edit --id $item.id --project-id $project.id --field-id $statusField.id --single-select-option-id $option.id | Out-Null

    if ($ChangeId) {
        $changeField = $fields | Where-Object name -eq $config.project.changeIdField
        if ($changeField) { Invoke-Gh project item-edit --id $item.id --project-id $project.id --field-id $changeField.id --text $ChangeId | Out-Null }
    }
    Write-Host "Board: #$Issue → $statusName$(if ($ChangeId) { " ($ChangeId)" })"
}
catch {
    Write-Warning "Board update skipped for #${Issue}: $($_.Exception.Message)"
}
finally {
    foreach ($k in $saved.Keys) { if ($saved[$k]) { Set-Item "Env:$k" $saved[$k] } }
}
