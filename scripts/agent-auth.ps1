<#
.SYNOPSIS
    Switches the current PowerShell session to the SDD agent identity (GitHub App bot).

.DESCRIPTION
    Mints a short-lived (1 h) installation token for the "sdd-agent" GitHub App and configures,
    for the current process only:
      - GH_TOKEN                 -> gh CLI acts as the bot (PRs, issues, labels...)
      - GIT_AUTHOR_* / GIT_COMMITTER_*  -> commits authored by <slug>[bot]
      - GIT_CONFIG_* extraheader -> git push authenticates as the bot (token never in remote URL)

    Must be dot-sourced so the variables stay in the caller's session:
        . ./scripts/agent-auth.ps1

    Credentials are read from ~/.sdd (created by scripts/bootstrap/create-agent-app.mjs).
    In CI, pass -AppId/-PrivateKey/-InstallationId from repository secrets instead.
#>
[CmdletBinding()]
param(
    [string]$ConfigDir = (Join-Path $HOME '.sdd'),
    [string]$ClientId,
    [string]$PrivateKey,
    [long]$InstallationId,
    [string]$Slug
)

$ErrorActionPreference = 'Stop'

if (-not $PrivateKey) {
    $config = Get-Content (Join-Path $ConfigDir 'sdd-agent.json') -Raw | ConvertFrom-Json
    $PrivateKey = Get-Content (Join-Path $ConfigDir 'sdd-agent.pem') -Raw
    $ClientId = $config.client_id
    $InstallationId = $config.installation_id
    $Slug = $config.slug
}

function ConvertTo-Base64Url([byte[]]$bytes) {
    [Convert]::ToBase64String($bytes).TrimEnd('=').Replace('+', '-').Replace('/', '_')
}

$now = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
$header = ConvertTo-Base64Url ([Text.Encoding]::UTF8.GetBytes('{"alg":"RS256","typ":"JWT"}'))
$payload = ConvertTo-Base64Url ([Text.Encoding]::UTF8.GetBytes((@{ iat = $now - 60; exp = $now + 540; iss = $ClientId } | ConvertTo-Json -Compress)))
$rsa = [Security.Cryptography.RSA]::Create()
try {
    $rsa.ImportFromPem($PrivateKey)
    $signature = $rsa.SignData([Text.Encoding]::UTF8.GetBytes("$header.$payload"),
        [Security.Cryptography.HashAlgorithmName]::SHA256,
        [Security.Cryptography.RSASignaturePadding]::Pkcs1)
}
finally {
    $rsa.Dispose()
}
$jwt = "$header.$payload.$(ConvertTo-Base64Url $signature)"

$apiHeaders = @{ Accept = 'application/vnd.github+json'; 'X-GitHub-Api-Version' = '2022-11-28' }
$token = (Invoke-RestMethod -Method Post -Uri "https://api.github.com/app/installations/$InstallationId/access_tokens" `
        -Headers ($apiHeaders + @{ Authorization = "Bearer $jwt" })).token

$botLogin = "$Slug[bot]"
$botId = (Invoke-RestMethod -Uri "https://api.github.com/users/$([uri]::EscapeDataString($botLogin))" -Headers $apiHeaders).id
$botEmail = "$botId+$botLogin@users.noreply.github.com"

$env:GH_TOKEN = $token
$env:GIT_AUTHOR_NAME = $botLogin
$env:GIT_AUTHOR_EMAIL = $botEmail
$env:GIT_COMMITTER_NAME = $botLogin
$env:GIT_COMMITTER_EMAIL = $botEmail
$basic = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes("x-access-token:$token"))
$env:GIT_CONFIG_COUNT = '2'
$env:GIT_CONFIG_KEY_0 = 'http.https://github.com/.extraheader'
$env:GIT_CONFIG_VALUE_0 = "AUTHORIZATION: basic $basic"
$env:GIT_CONFIG_KEY_1 = 'credential.helper'
$env:GIT_CONFIG_VALUE_1 = ''

Write-Host "SDD agent identity active: $botLogin (token valid ~1h)"
