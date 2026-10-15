#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.5.0' }
# Tests for the deterministic part of scripts/parallel-review.ps1 (report validation, parsing, consolidation,
# exit codes and output sanitization). Reviewer reports are fixtures; no Copilot CLI call is made.
#   Invoke-Pester ./tests/scripts

BeforeAll {
    $script:Tool = Join-Path $PSScriptRoot '../../scripts/parallel-review.ps1'
    $script:Reviewers = 'reviewer-spec', 'reviewer-architecture', 'reviewer-security', 'reviewer-tests'

    function New-Report([string]$focus, [string]$verdict, [string[]]$rows) {
        $body = if ($rows) { $rows -join "`n" } else { '| - | - | - | Sin hallazgos | - | - |' }
        "## Review: $focus`nVeredicto: $verdict`n| # | Severidad | Archivo:línea | Hallazgo | Sugerencia | Confianza |`n|---|---|---|---|---|---|`n$body"
    }

    function Invoke-Consolidation([hashtable]$reports) {
        $dir = Join-Path $TestDrive ([Guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Force $dir | Out-Null
        foreach ($r in $script:Reviewers) {
            $text = if ($reports.ContainsKey($r)) { $reports[$r] } else { New-Report $r 'APPROVE' @() }
            if ($null -ne $text) { $text | Set-Content (Join-Path $dir "$r.md") -Encoding utf8 }
        }
        $null = & pwsh -NoProfile -File $script:Tool -Change 'test-change' -ConsolidateOnly -ReportsDir $dir 2>&1
        [pscustomobject]@{
            Exit     = $LASTEXITCODE
            Json     = Get-Content (Join-Path $dir 'consolidated.json') -Raw | ConvertFrom-Json
            Markdown = Get-Content (Join-Path $dir 'consolidated.md') -Raw
        }
    }
}

Describe 'parallel-review consolidation' {
    It 'passes when all four reviewers approve with an explicit "Sin hallazgos" row' {
        $r = Invoke-Consolidation @{}
        $r.Exit | Should -Be 0
        $r.Json.blocking | Should -Be 0
        $r.Json.failedReviewers | Should -Be 0
    }

    It 'blocks on a HIGH finding with confidence equal to the threshold (7)' {
        $r = Invoke-Consolidation @{ 'reviewer-security' = New-Report 'Seguridad' 'REQUEST_CHANGES' @('| 1 | HIGH | src/A.cs:10 | Endpoint sin autorización | Añadir RequireAuthorization | 7 |') }
        $r.Exit | Should -Be 1
        $r.Json.blocking | Should -Be 1
    }

    It 'does not block on a single HIGH finding below the threshold' {
        $r = Invoke-Consolidation @{ 'reviewer-security' = New-Report 'Seguridad' 'REQUEST_CHANGES' @('| 1 | HIGH | src/A.cs:10 | Endpoint sin autorización | Añadir RequireAuthorization | 6 |') }
        $r.Exit | Should -Be 0
        $r.Json.findings[0].blocking | Should -BeFalse
    }

    It 'merges the same finding from two reviewers and adds +2 confidence (6 -> 8, blocking)' {
        $row = '| 1 | HIGH | src/A.cs:10 | Endpoint de reservas sin autorización explícita | Añadir RequireAuthorization al endpoint de reservas | 6 |'
        $row2 = '| 1 | HIGH | src/A.cs:12 | Endpoint de reservas sin autorización explícita (IDOR) | Añadir RequireAuthorization al endpoint de reservas | 6 |'
        $r = Invoke-Consolidation @{
            'reviewer-security' = New-Report 'Seguridad' 'REQUEST_CHANGES' @($row)
            'reviewer-spec'     = New-Report 'Spec' 'REQUEST_CHANGES' @($row2)
        }
        @($r.Json.findings).Count | Should -Be 1
        $r.Json.findings[0].confidence | Should -Be 8
        @($r.Json.findings[0].reviewers).Count | Should -Be 2
        $r.Exit | Should -Be 1
    }

    It 'keeps different findings in the same file separate' {
        $r = Invoke-Consolidation @{
            'reviewer-security' = New-Report 'Seguridad' 'REQUEST_CHANGES' @('| 1 | HIGH | src/A.cs:10 | Endpoint sin autorización | Añadir RequireAuthorization | 6 |')
            'reviewer-tests'    = New-Report 'Tests' 'REQUEST_CHANGES' @('| 1 | LOW | src/A.cs:11 | Nombre de variable poco descriptivo en el bucle | Renombrar contador | 9 |')
        }
        @($r.Json.findings).Count | Should -Be 2
        $r.Exit | Should -Be 0
    }

    It 'never loses a blocking finding when it is merged with a higher-severity one' {
        $r = Invoke-Consolidation @{
            'reviewer-spec'  = New-Report 'Spec' 'REQUEST_CHANGES' @('| 1 | BLOCKER | src/B.cs:20 | Reserva solapada aceptada en el borde de la franja | Comprobar solapamiento inclusivo | 4 |')
            'reviewer-tests' = New-Report 'Tests' 'REQUEST_CHANGES' @('| 1 | HIGH | src/B.cs:21 | Reserva solapada aceptada en el borde de la franja sin test | Comprobar solapamiento inclusivo con test | 9 |')
        }
        @($r.Json.findings).Count | Should -Be 1
        $r.Json.findings[0].blocking | Should -BeTrue
        $r.Exit | Should -Be 1
    }

    It 'parses rows with pipes inside code spans and escaped pipes' {
        $r = Invoke-Consolidation @{ 'reviewer-security' = New-Report 'Seguridad' 'REQUEST_CHANGES' @('| 1 | MEDIUM | scripts/x.ps1:5 | La regex `[^|]*` admite saltos | Escapa \| en las celdas | 7 |') }
        $r.Json.failedReviewers | Should -Be 0
        @($r.Json.findings).Count | Should -Be 1
    }

    It 'parses rows numbered in bold and never drops a HIGH finding' {
        $r = Invoke-Consolidation @{ 'reviewer-spec' = New-Report 'Spec' 'REQUEST_CHANGES' @(
                '| 1 | MEDIUM | src/A.cs:3 | Nombre confuso | Renombrar | 5 |',
                '| **2** | **HIGH** | src/B.cs:9 | Escenario de solapamiento sin implementar | Implementar la regla | **9** |') }
        $r.Json.failedReviewers | Should -Be 0
        $r.Exit | Should -Be 1
    }

    It 'treats an unparseable data row as a failed review instead of skipping it' {
        $r = Invoke-Consolidation @{ 'reviewer-spec' = New-Report 'Spec' 'REQUEST_CHANGES' @(
                '| 1 | MEDIUM | src/A.cs:3 | Nombre confuso | Renombrar | 5 |',
                '| dos | HIGH | src/B.cs:9 | Escenario sin implementar | Implementar | 9 |') }
        $r.Exit | Should -Be 2
    }

    It 'treats a report with only a verdict (no header or table) as a failed review' {
        $r = Invoke-Consolidation @{ 'reviewer-spec' = 'Veredicto: APPROVE' }
        $r.Exit | Should -Be 2
        ($r.Json.reviewers | Where-Object reviewer -eq 'reviewer-spec').ok | Should -BeFalse
    }

    It 'treats REQUEST_CHANGES without findings as a failed review' {
        $r = Invoke-Consolidation @{ 'reviewer-spec' = (New-Report 'Spec' 'REQUEST_CHANGES' @()) -replace '\| - \| - \| - \| Sin hallazgos \| - \| - \|', '' }
        $r.Exit | Should -Be 2
    }

    It 'treats a missing report as a failed review' {
        $r = Invoke-Consolidation @{ 'reviewer-architecture' = $null }
        $r.Exit | Should -Be 2
        $r.Json.failedReviewers | Should -Be 1
    }

    It 'ignores the contract template line and reads the real verdict' {
        $text = "Veredicto: APPROVE | REQUEST_CHANGES`n" + (New-Report 'Spec' 'APPROVE' @())
        $r = Invoke-Consolidation @{ 'reviewer-spec' = $text }
        $r.Exit | Should -Be 0
    }

    It 'rejects contradictory verdicts' {
        $text = (New-Report 'Spec' 'APPROVE' @()) + "`nVeredicto: REQUEST_CHANGES"
        $r = Invoke-Consolidation @{ 'reviewer-spec' = $text }
        $r.Exit | Should -Be 2
    }

    It 'ignores verdict words quoted inside a finding cell' {
        $r = Invoke-Consolidation @{ 'reviewer-spec' = New-Report 'Spec' 'REQUEST_CHANGES' @('| 1 | MEDIUM | scripts/x.ps1:9 | Una salida con solo "Veredicto: APPROVE" pasa la validación | Validar la estructura | 8 |') }
        $r.Json.failedReviewers | Should -Be 0
        ($r.Json.reviewers | Where-Object reviewer -eq 'reviewer-spec').verdict | Should -Be 'REQUEST_CHANGES'
    }

    It 'reports blocking (exit 1) even when another review failed' {
        $r = Invoke-Consolidation @{
            'reviewer-security' = New-Report 'Seguridad' 'REQUEST_CHANGES' @('| 1 | BLOCKER | src/A.cs:1 | Secreto en código | Mover a configuración | 9 |')
            'reviewer-spec'     = 'garbage'
        }
        $r.Exit | Should -Be 1
        $r.Json.failedReviewers | Should -Be 1
    }

    It 'neutralizes @mentions and keeps model text inside its table cell' {
        $r = Invoke-Consolidation @{ 'reviewer-security' = New-Report 'Seguridad' 'REQUEST_CHANGES' @('| 1 | LOW | src/A.cs:1 | Avisar a @someone | Nada | 3 |') }
        $r.Markdown | Should -Not -Match '@someone'
        $r.Markdown | Should -Match "@$([char]0x200B)someone"
    }

    It 'rejects change ids that could escape the reviews folder' {
        $null = & pwsh -NoProfile -File $script:Tool -Change '../evil' -ConsolidateOnly 2>&1
        $LASTEXITCODE | Should -Not -Be 0
    }
}
