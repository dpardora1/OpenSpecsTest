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
    [string]$ChangeId
)

$ErrorActionPreference = 'Stop'
$root = (git rev-parse --show-toplevel 2>$null) ?? (Get-Location).Path
$config = Get-Content (Join-Path $root '.sdd/sdd.config.json') -Raw | ConvertFrom-Json
$owner = $config.project.owner
$number = $config.project.number
$statusName = $config.project.statuses.$Status

$saved = @{ GH_TOKEN = $env:GH_TOKEN; GITHUB_TOKEN = $env:GITHUB_TOKEN }
Remove-Item Env:GH_TOKEN, Env:GITHUB_TOKEN -ErrorAction SilentlyContinue
try {
    $url = gh api "repos/$($config.repo)/issues/$Issue" --jq '.html_url'
    if ($LASTEXITCODE -ne 0 -or -not $url) { throw "Issue/PR #$Issue not found in $($config.repo)" }

    $item = gh project item-add $number --owner $owner --url $url --format json | ConvertFrom-Json
    $project = gh project view $number --owner $owner --format json | ConvertFrom-Json
    $fields = (gh project field-list $number --owner $owner --format json | ConvertFrom-Json).fields

    $statusField = $fields | Where-Object name -eq $config.project.statusField
    $option = $statusField.options | Where-Object name -eq $statusName
    if (-not $option) { throw "Status option '$statusName' not found in field '$($config.project.statusField)'" }
    gh project item-edit --id $item.id --project-id $project.id --field-id $statusField.id --single-select-option-id $option.id | Out-Null

    if ($ChangeId) {
        $changeField = $fields | Where-Object name -eq $config.project.changeIdField
        if ($changeField) { gh project item-edit --id $item.id --project-id $project.id --field-id $changeField.id --text $ChangeId | Out-Null }
    }
    Write-Host "Board: #$Issue → $statusName$(if ($ChangeId) { " ($ChangeId)" })"
}
catch {
    Write-Warning "Board update skipped for #${Issue}: $($_.Exception.Message)"
}
finally {
    foreach ($k in $saved.Keys) { if ($saved[$k]) { Set-Item "Env:$k" $saved[$k] } }
}
